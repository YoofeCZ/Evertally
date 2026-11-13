"""Route refresh work, right-click dispatch and replacement planning, without WoW."""
import unittest
import test_route_lines
import test_terrain


class RouteStabilityTests(unittest.TestCase):
    def setUp(self):
        self.scene = test_route_lines.RouteLineTests()
        self.scene.setUp()
        self.lua, self.m, self.g = self.scene.lua, self.scene.m, self.scene.g

    def show(self):
        self.scene.show(self.scene.plan(("flight", .6, .5, .65, .5)))

    def test_stationary_ticks_do_not_project_or_touch_lines_again(self):
        self.show()
        self.lua.execute('''
          SETS=0;PROJECTS=0;PLAN_READS=0
          local methods=getmetatable(REGIONS[1]).__index
          local original=methods.SetStartPoint
          methods.SetStartPoint=function(...) SETS=SETS+1;return original(...) end
          local project=HBD.GetZoneCoordinatesFromWorldInstance
          HBD.GetZoneCoordinatesFromWorldInstance=function(...) PROJECTS=PROJECTS+1;return project(...) end
          M.RoutePlan=function() PLAN_READS=PLAN_READS+1;return M.route end
          for i=1,120 do Drive(1/60) end
        ''')
        self.assertEqual(self.g.SETS, 0)
        self.assertEqual(self.g.PROJECTS, 0)
        self.assertLessEqual(self.g.PLAN_READS, 20, "the route snapshot must not be copied on every rendered frame")

    def test_moving_origin_reuses_world_geometry_of_a_long_unchanged_tail(self):
        self.lua.execute('''
          local points={}
          for i=1,1000 do points[i]={.5+i*.0001,.5+math.sin(i/10)*.01} end
          LONGSTEP={mode="walk",fu=points[1][1],fv=points[1][2],tu=points[1000][1],tv=points[1000][2],
            routePath=points,routeGeometry={}}
          M.route={steps={LONGSTEP}};M.RefreshRoute(true)
          WORLD_READS=0
          local original=HBD.GetWorldCoordinatesFromZone
          HBD.GetWorldCoordinatesFromZone=function(...) WORLD_READS=WORLD_READS+1;return original(...) end
          LONGSTEP.fu=LONGSTEP.fu+.00001
          LONGSTEP.routePath[1]={LONGSTEP.fu,LONGSTEP.fv}
          M.RefreshRoute()
        ''')
        self.assertEqual(self.g.WORLD_READS, 2, "only the changed first edge needs conversion, not all 999 edges")

    def test_stitched_view_change_updates_projection_with_an_unchanged_canvas_rect(self):
        self.lua.execute('''
          NEXT_STITCH=true;VIEW_U=.5;STITCH_READS=0
          OpenMapAPI.GetView=function() return VIEW_U,.5,2 end
          OpenMapAPI.CanvasFromWorldPos=function(c,north,west)
            STITCH_READS=STITCH_READS+1
            return .6-west/1000+(VIEW_U-.5),.5-north/1000
          end
        ''')
        self.show()
        line = self.scene.strokes("VIEW")[0]
        before = line.x1
        self.g.STITCH_READS = 0
        self.g.Drive(.11)
        self.assertEqual(self.g.STITCH_READS, 0, "stationary stitched views still do no per-edge projection work")
        self.g.VIEW_U = .55
        self.g.Drive(.11)
        self.assertGreater(self.g.STITCH_READS, 0)
        self.assertAlmostEqual(line.x1 - before, 20)

    def test_hit_test_uses_only_visible_clipped_strokes(self):
        self.show()
        self.assertEqual(self.m.RouteHitTest("world", 250, 104, 6)[0:2], (True, 1))
        self.assertFalse(self.m.RouteHitTest("world", 250, 108, 6))
        self.assertFalse(self.m.RouteHitTest("world", 350, 100, 6))
        self.m.ClearRoute()
        self.assertFalse(self.m.RouteHitTest("world", 250, 100, 6))

    def install_click_hook(self):
        self.lua.execute('''
          HOOKS=0;MENU_OPENS=0;MENU_RESULT=true;CX=350;CY=700
          GetCursorPosition=function() return CX,CY end
          function WorldMapFrame:AddCanvasClickHandler(callback,priority)
            HOOKS=HOOKS+1;CLICK=callback;PRIORITY=priority
          end
          M.ShowRouteMenu=function() MENU_OPENS=MENU_OPENS+1;return MENU_RESULT end
        ''')
        self.show()

    def test_right_click_on_line_consumes_before_openmap_zoom_and_misses_pass_through(self):
        self.install_click_hook()
        self.assertEqual(self.g.PRIORITY, 1100)
        self.assertTrue(self.g.CLICK(self.g.WorldMapFrame, "RightButton"))
        self.assertFalse(self.g.CLICK(self.g.WorldMapFrame, "LeftButton"))
        self.g.CY = 680
        self.assertFalse(self.g.CLICK(self.g.WorldMapFrame, "RightButton"))
        self.assertEqual(self.g.MENU_OPENS, 1)
        self.m.RefreshRoute()
        self.assertEqual(self.g.HOOKS, 1)

    def test_failed_menu_and_six_screen_pixel_tolerance_preserve_normal_zoom(self):
        self.install_click_hook()
        self.g.MENU_RESULT = False
        self.assertFalse(self.g.CLICK(self.g.WorldMapFrame, "RightButton"))
        self.g.MENU_RESULT = True
        self.g.VIEW.scale = 2
        self.m.RefreshRoute()
        self.g.CX, self.g.CY = 700, (800 - 105) * 2
        self.assertFalse(self.g.CLICK(self.g.WorldMapFrame, "RightButton"), "5 map-local pixels are 10 screen pixels")
        self.g.CY = (800 - 102) * 2
        self.assertTrue(self.g.CLICK(self.g.WorldMapFrame, "RightButton"))


class NavigatorStabilityTests(unittest.TestCase):
    def test_pending_recalculation_keeps_last_verified_plan_and_walking_job(self):
        fixture = test_terrain.TerrainTests()
        fixture.setUp()
        m = fixture.navigator()
        lua = fixture.lua
        m.Navigate(lua.table_from(dict(kind="point", map=1429, x=.95, y=.25, label="Verified destination")))
        lua.execute('''
          local M=NAVTEST
          local job=M.nav.ground.job
          job.state="ready";job.result={points={{15,25},{45,95},{95,25}},tails={200,100,0}}
          M.nav.Update()
          VERIFIED_PLAN=M.nav.plan;VERIFIED_GROUND=M.nav.ground
          M.Journey={Available=function() return true end,Begin=function() return {state="pending"} end,
            Step=function() end,Cancel=function(job) job.state="cancelled" end}
        ''')
        self.assertTrue(m.RecalculateRoute())
        self.assertEqual(m.nav.journey.state, "pending")
        self.assertTrue(lua.eval("NAVTEST.nav.plan==VERIFIED_PLAN"))
        self.assertTrue(lua.eval("NAVTEST.nav.ground==VERIFIED_GROUND"))
        self.assertGreater(len(m.RoutePlan().steps[1].routePath), 1)
        lua.execute("NAVTEST.nav.journey.plan=VERIFIED_PLAN;NAVTEST.nav.journey.state='ready'")
        m.nav.Update()
        self.assertTrue(lua.eval("NAVTEST.nav.ground==VERIFIED_GROUND"))
        m.Stop()
        self.assertIsNone(m.RoutePlan())
        self.assertFalse(m.RecalculateRoute())


if __name__ == "__main__":
    unittest.main()

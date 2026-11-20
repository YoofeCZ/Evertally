"""The actual arrow/route contracts while a collision path is pending, failed or ready."""
import unittest
from test_addon import map_toc_lines
import base64
import time
import zlib
import test_terrain
import test_navigation


class RoadNavigationTests(unittest.TestCase):
    def setUp(self):
        fixture = test_terrain.TerrainTests()
        fixture.setUp()
        self.lua, self.a = fixture.lua, fixture.a
        self.m = fixture.navigator()
        self.lua.execute('''
          UnitPosition=function() return 15,25,42,0 end
          NAVTEST.Terrain.RoadBacked=function() return true end
          NAVTEST.Terrain.Begin=function(map,x,y,tx,ty,options)
            GOT_OPTIONS=options
            return {provider="roads",state="pending",map={id=map,cell=8}}
          end
          NAVTEST.Terrain.Step=function(job) return job.state end
          NAVTEST.Terrain.Cancel=function(job) job.state="cancelled" end
        ''')
        self.m.Navigate(self.lua.table(kind="point", map=1429, x=.95, y=.25, label="Road route"))
        self.tracker = self.lua.globals().EvertallyTracker

    def test_pending_and_failed_paths_do_not_point_through_obstacles(self):
        self.assertEqual(self.lua.globals().GOT_OPTIONS.fromZ, 42)
        self.assertTrue(self.lua.globals().GOT_OPTIONS.roads)
        self.assertIsNone(self.m.nav.aim)
        self.assertFalse(self.tracker.arrow.shown)
        self.assertEqual(len(self.m.RoutePlan().steps[1].routePath), 1)
        self.assertIn(self.a.L("navGroundPending"), self.tracker.hint.text)
        self.m.nav.ground.job.state = "failed"
        self.m.nav.Update()
        self.assertIsNone(self.m.nav.aim)
        self.assertFalse(self.tracker.arrow.shown)
        self.assertEqual(len(self.m.RoutePlan().steps[1].routePath), 1)
        self.assertIn(self.a.L("navGroundFailed"), self.tracker.hint.text)

    def test_ready_path_aims_at_its_first_bend_and_exposes_the_same_route(self):
        self.lua.execute('''
          NAVTEST.nav.ground.job.state="ready"
          NAVTEST.nav.ground.job.result={points={{15,25},{45,95},{95,95},{95,25}},tails={200,150,50,0}}
        ''')
        self.m.nav.Update()
        self.assertEqual(self.m.nav.groundStatus, "roads")
        self.assertEqual((self.m.nav.aim.x, self.m.nav.aim.y), (45, 95))
        self.assertTrue(self.tracker.arrow.shown)
        self.assertEqual(len(self.m.RoutePlan().steps[1].routePath), 4)
        self.assertIn(self.a.L("navGroundRoads"), self.tracker.hint.text)

    def test_floor_change_replans_even_when_horizontal_position_is_unchanged(self):
        old = self.m.nav.ground.job
        old.marker = "old floor"
        self.lua.execute('UnitPosition=function() return 15,25,80,0 end;CLOCK=CLOCK+2')
        self.m.nav.Update()
        self.assertEqual(old.state, "cancelled")
        self.assertIsNone(self.m.nav.ground.job.marker)
        self.assertEqual(self.lua.globals().GOT_OPTIONS.fromZ, 80)

    def test_point_on_floor_above_is_not_skipped_at_identical_horizontal_coordinates(self):
        self.lua.execute('''
          NAVTEST.nav.ground.job.state="ready"
          NAVTEST.nav.ground.job.result={points={{15,25,42},{15,25,80},{95,25,80}},tails={118,80,0}}
        ''')
        self.m.nav.Update()
        self.assertEqual(self.m.nav.ground.index, 2)
        self.assertEqual(self.m.nav.groundStatus, "floor")
        self.assertIsNone(self.m.nav.aim)
        self.assertIn(self.a.L("navGroundFloor"), self.tracker.hint.text)


class FullRoadNavigationTests(unittest.TestCase):
    def test_real_stormwind_wall_detour_reaches_arrow_and_line_through_full_toc(self):
        lua, addon = test_terrain.runtime()
        lua.execute(test_terrain.MOCK_UI_LUA)
        lua.execute(test_navigation.RECORD_ROTATION)
        lua.execute(test_navigation.FAKE_LIBS)
        lua.globals().PYUNPACK = lambda data, _method: zlib.decompress(base64.b64decode(data))
        lua.globals().debugprofilestop = lambda: time.perf_counter() * 1000
        lua.execute('''
          C_EncodingUtil={DecodeBase64=function(v) return v end,DecompressString=PYUNPACK}
          Enum={CompressionMethod={Zlib=1}}
          GetPlayerFacing=function() return 0 end
          UnitFactionGroup=function() return "Alliance" end
          function geterrorhandler() return function(e) error(e) end end
        ''')
        m = lua.table()
        for name in map_toc_lines():
            if name.endswith(".lua") and not name.startswith("Libs"):
                test_terrain.load(lua, m, name)
        lua.globals().FULLNAV = m
        lua.execute('''
          local M=FULLNAV;local f=M.data.yards[0]
          local u,v=f[1]+600.9950248756222*f[2],f[3]-8800*f[4]
          local tu,tv=f[1]+608.9552238805974*f[2],f[3]-8800*f[4]
          local map,x,y=M.Locate(tu,tv)
          M.PlayerPosition=function() return u,v,map,x,y end
          M.Navigate({kind="point",map=map,x=x,y=y,label="Real Stormwind wall"})
        ''')
        self.assertTrue(m.Terrain.RoadBacked(0))
        self.assertIsNotNone(m.nav.journey)
        for _ in range(5000):
            m.nav.Update()
            if m.nav.ground and m.nav.ground.job.state != "pending":
                break
        m.nav.Update()
        self.assertEqual(m.nav.ground.job.provider, "roads")
        result = m.nav.ground.job.result
        self.assertEqual(m.nav.ground.job.state, "ready")
        self.assertGreater(result.yards, 20)
        self.assertIsNotNone(m.nav.aim)
        self.assertNotEqual(lua.globals().EvertallyTracker.line1.text, addon.L("navArrived"))
        route = m.RoutePlan()
        edges = m.RouteSegments(route)
        summary = [(route.steps[i].mode, len(route.steps[i].routePath or [])) for i in range(1, len(route.steps) + 1)]
        self.assertGreaterEqual(len(edges), 3, f"the actual renderer receives the collision detour, not a chord: {summary}")
        m.Stop()
        self.assertIsNone(m.nav.target)


if __name__ == "__main__":
    unittest.main()

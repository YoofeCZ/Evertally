"""Evertally next to OpenMap: it leaves OpenMap's own layers to it, adds what OpenMap has no layer for, and follows OpenMap's stitched view.
OpenMap's interface is replaced by a stand-in that has the shape read from OpenMap 0.8.3 (API.lua)."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_addon import MOCK_UI_LUA, ROOT, runtime
from test_navigation import FAKE_LIBS

MAP_DIR = ROOT / "addon" / "Evertally_Map"
OPENMAP = """
TOGGLES={}; GLIDES={}; STITCHED=true
OPEN_U,OPEN_V,OPEN_ZOOM=0.5,0.5,4
OpenMapAPI={major=1,version=4,
  RegisterMenuToggle=function(owner,spec) TOGGLES[#TOGGLES+1]={owner=owner,spec=spec} end,
  IsStitched=function() return STITCHED end,
  GetView=function() if STITCHED then return OPEN_U,OPEN_V,OPEN_ZOOM end end,
  MapAt=function(u,v) if u<0.45 then return 1436 elseif v>0.55 then return 1453 else return 1429 end end,
  WorldFromMap=function(map,x,y) return 0.31,0.62 end,
  ShowWorld=function(u,v,zoom) GLIDES[#GLIDES+1]={u=u,v=v,zoom=zoom} return true end}
"""


def lst(table):
    return [table[i] for i in range(1, len(table) + 1)] if table is not None else []


class OpenMapTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = runtime()
        self.lua.execute(MOCK_UI_LUA)
        self.lua.execute(FAKE_LIBS)
        self.lua.execute("""
          MAPID=1429;WORLDMAP=1429
          C_Map={GetBestMapForUnit=function() return MAPID end,
            GetPlayerMapPosition=function() return {GetXY=function() return .42,.65 end} end,
            GetMapInfo=function(id) return {name="Map "..id} end}
          UnitFactionGroup=function() return "Alliance" end
          GetPlayerFacing=function() return 0 end
          IsMounted=function() return false end
          WorldMapFrame=CreateFrame("Frame","WorldMapFrame")
          WorldMapFrame.GetMapID=function() return WORLDMAP end
          OpenWorldMap=function(id) OPENED=id end
        """)
        self.m = self.lua.table()
        for line in (MAP_DIR / "Evertally_Map.toc").read_text(encoding="utf8").splitlines():
            if line.endswith(".lua") and not line.startswith("Libs"):
                chunk = self.lua.eval("loadstring")((MAP_DIR / line).read_text(encoding="utf8"), line)
                if isinstance(chunk, tuple):
                    self.fail(str(chunk))
                chunk("Evertally_Map", self.m)
        self.a.db.settings.mapLayers = self.lua.table(travel=True, trainer=True, vendor=True, inn=True, gather=True, instances=True)

    def pin_maps(self):
        frames = lst(self.lua.eval("(function() local o={} for f in pairs(PINLOG.world) do o[#o+1]=f end return o end)()"))
        return sorted({int(f.spec.map) for f in frames})

    def active(self):
        return sorted(str(k) for k in self.m.ActiveLayers().keys())

    # ---- OpenMap is a dependency ----
    def test_the_map_add_on_depends_on_openmap_and_loads_only_files_that_exist(self):
        lines = (MAP_DIR / "Evertally_Map.toc").read_text(encoding="utf8").splitlines()
        self.assertIn("## Dependencies: Evertally", lines)
        self.assertTrue(any(l.startswith("## OptionalDeps:") and "OpenMap" in l for l in lines), "OpenMap loads first when it is there; the guide pages work without it")
        for line in lines:
            if line.endswith(".lua"):
                self.assertTrue((MAP_DIR / line).is_file(), f"the toc lists {line}, which is not there")
        self.assertFalse(any("OwnMap" in line or "RevealData" in line for line in lines), "the own map window is gone")

    def test_without_openmap_loading_the_map_says_what_is_missing_instead_of_failing_silently(self):
        self.lua.execute("PRINTED={}; Evertally.Print=function(msg) PRINTED[#PRINTED+1]=msg end")
        self.a.db.settings.mapPins = True
        self.lua.execute("C_AddOns={GetAddOnInfo=function(name) return nil end}")
        self.a.map = None
        ok, why = self.a.LoadMap()
        self.assertFalse(ok)
        self.assertEqual(str(why), "openmap_missing")
        said = [str(self.lua.globals().PRINTED[i]) for i in range(1, len(self.lua.globals().PRINTED) + 1)]
        self.assertEqual(said, [self.a.L("mapNeedsOpenMap")])
        self.assertIn("OpenMap", said[0])
        self.lua.execute("C_AddOns.GetAddOnInfo=function(name) return name end; C_AddOns.LoadAddOn=function() return false, 'DEP_DISABLED' end")
        ok, why = self.a.LoadMap()
        self.assertEqual((ok, str(why)), (False, "openmap_missing"), "OpenMap is installed but switched off")
        self.lua.execute("C_AddOns.GetAddOnInfo=function() error('boom') end; C_AddOns.LoadAddOn=function() return true end")
        self.assertFalse(self.a.OpenMapMissing(), "when the game cannot tell, OpenMap is taken to be there")

    # ---- the way of a journey on the map ----
    def route_dots_on_map(self):
        return int(self.lua.eval("(function() local n=0 for f,e in pairs(PINLOG.world) do if e.ref=='EvertallyRoute' then n=n+1 end end return n end)()"))

    def journey(self):
        place = self.m.Plan.Search("shadowprey", 5)[1]
        plan = self.m.Plan.Journey(place)
        self.assertIsNotNone(plan, "a way from Elwynn to Desolace is known")
        return place, plan

    def test_a_journey_becomes_a_dotted_line_along_all_its_legs_in_the_colours_of_their_kinds(self):
        place, plan = self.journey()
        dots = lst(self.m.RouteDots(plan))
        self.assertGreater(len(dots), 30, "a trip across the sea is a long line")
        self.assertLessEqual(len(dots), 420, "never more dots than the budget")
        colours = {tuple(round(float(d.color[i]), 2) for i in (1, 2, 3)) for d in dots}
        self.assertGreaterEqual(len(colours), 2, "walking and travelling by boat or air look different")
        self.assertTrue(all(0 <= d.x <= 1 and 0 <= d.y <= 1 for d in dots), "every dot lies on its map")
        self.assertTrue(any(d.size > 6 for d in dots), "a bigger dot where one leg ends and the next begins")

    def test_the_dots_reach_the_map_and_go_when_the_route_is_cleared(self):
        place, plan = self.journey()
        self.assertEqual(self.route_dots_on_map(), 0)
        self.m.route = plan
        self.m.RefreshRoute(True)
        self.assertEqual(self.route_dots_on_map(), len(lst(self.m.RouteDots(plan))))
        before = self.route_dots_on_map()
        self.m.RefreshRoute()
        self.assertEqual(self.route_dots_on_map(), before, "nothing changed: nothing redrawn")
        self.m.ClearRoute()
        self.assertEqual(self.route_dots_on_map(), 0)
        self.m.route = plan
        self.m.RefreshRoute(True)
        self.m.ClearExtra()
        self.assertEqual(self.route_dots_on_map(), 0, "clearing the marked places clears the route too")

    def walking_step(self, wall=True):
        """A walk across a small map of continent 1 (Kalimdor) with a wall in the way, as a step of a plan."""
        from test_terrain import grid
        rows = [[1] * 12 for _ in range(12)]
        if wall:
            for y in range(9):
                rows[5][y] = 0
        self.m.Terrain.maps[1] = grid(self.lua, rows, 10, 1)
        frame = self.m.data.yards[1]

        def uv(x, y):
            return frame[1] + y * frame[2], frame[3] + x * frame[4]
        fu, fv = uv(15, 25)
        tu, tv = uv(95, 25)
        step = self.lua.table(mode="walk", fu=fu, fv=fv, tu=tu, tv=tv, seconds=10)
        return step, self.lua.table(steps=self.lua.table_from([step]), seconds=10)

    def search(self):
        for _ in range(3000):
            if not self.m.RouteStep():
                return
        self.fail("the search did not end")

    def test_a_walking_leg_follows_the_terrain_round_a_wall_and_not_the_straight_line(self):
        step, plan = self.walking_step()
        self.assertIsNone(self.m.RouteLegPath(step), "while it is searched for the line is straight")
        self.assertEqual(len(lst(self.m.RoutePoly(step))), 2, "from where it starts to where it ends")
        straight = len(lst(self.m.RouteDots(plan)))
        self.assertGreater(straight, 0)
        self.search()
        path = lst(self.m.RouteLegPath(step))
        self.assertGreater(len(path), 2, "it bends")
        ys = [float(self.m.ToYards(p[1], p[2])[2]) for p in path]
        self.assertTrue(any(y >= 90 for y in ys), "round the end of the wall, at the far side")
        self.assertEqual(int(self.m.routeReady), 1)
        self.assertGreater(len(lst(self.m.RouteDots(plan))), 0)
        self.assertGreater(len(lst(self.m.RoutePoly(step))), 2, "the line that is drawn is the bent one")

    def test_the_line_is_drawn_again_when_the_search_has_found_the_way(self):
        step, plan = self.walking_step()
        self.m.route = plan
        self.m.RefreshRoute(True)
        before = self.route_dots_on_map()
        self.assertGreater(before, 0, "straight at first")
        self.search()
        self.m.RefreshRoute()                       # (not forced: the found way alone changes what is drawn)
        positions = sorted((round(float(f.x), 4), round(float(f.y), 4)) for f in lst(self.lua.eval(
            "(function() local o={} for f,e in pairs(PINLOG.world) do if e.ref=='EvertallyRoute' then o[#o+1]=e end end return o end)()")))
        self.assertTrue(positions)
        self.assertNotEqual(self.route_dots_on_map(), 0)

    def test_a_leg_on_a_map_without_terrain_stays_straight(self):
        step, plan = self.walking_step()
        self.m.Terrain.maps[1] = None
        self.assertIsNone(self.m.RouteLegPath(step))
        self.search()
        self.assertIsNone(self.m.RouteLegPath(step))
        self.assertGreater(len(lst(self.m.RouteDots(plan))), 0, "the straight line is still drawn")

    def test_a_search_that_is_no_longer_wanted_is_cancelled(self):
        step, plan = self.walking_step()
        self.m.route = plan
        self.m.RefreshRoute(True)                   # starts the search
        job_state = lambda: str(self.m.Terrain.maps[1] is not None)
        self.m.route = None
        self.m.RefreshRoute(True)
        self.assertEqual(int(self.m.routeDots or 0), 0)
        self.assertFalse(self.m.RouteStep(), "nothing left to search for")

    def test_show_on_map_in_the_journey_tab_draws_the_way_and_moves_the_view_to_hold_both_ends(self):
        self.lua.execute(OPENMAP)
        # (places that differ, unlike the stand-in's one point)
        self.lua.execute("OpenMapAPI.WorldFromMap=function(map,x,y) return (map-1400)/40+x*0.05, 0.5+y*0.05 end")
        place, plan = self.journey()
        body = self.lua.eval("CreateFrame")("Frame", None, None)
        body.SetSize(body, 600, 420)
        self.m.BuildWorld(body, self.a.UIKit())
        body.mode = "plan"
        self.m.RefreshWorld(body)
        frame = body.tabFrames["plan"]
        self.assertFalse(bool(frame.failed), self.a.errors["world_plan"])
        frame.plan.chosen = place
        self.m.WorldPlanShow(frame)
        frame.plan.show.scripts.OnClick()
        self.assertIsNotNone(self.m.route, "the route is kept")
        self.assertGreater(self.route_dots_on_map(), 30)
        glides = lst(self.lua.globals().GLIDES)
        self.assertTrue(glides, "the view moved")
        self.assertLess(glides[-1].zoom, 6, "wide enough for a whole journey, not close in on the goal")

    def test_navigating_replaces_a_route_that_was_only_shown(self):
        place, plan = self.journey()
        self.m.route = plan
        self.assertIsNone(self.m.RoutePlan(), "no navigation: nothing to draw from the navigator")
        self.m.Navigate(self.lua.table(kind="point", map=1436, x=0.5, y=0.5, label="Somewhere"))
        self.assertIsNone(self.m.route, "navigation draws its own plan")

    # ---- who draws what ----
    def test_layers_openmap_draws_itself_are_off_while_openmap_is_there_and_come_back_without_it(self):
        self.assertEqual(self.active(), sorted(["travel", "trainer", "vendor", "inn", "gather", "instances"]), "no OpenMap: all of them")
        self.lua.execute(OPENMAP)
        self.assertEqual(self.active(), ["gather"], "OpenMap has flights, townsfolk and dungeons: only gathering is Evertally's")
        self.assertFalse(self.m.LayerOn("trainer"))
        self.assertTrue(self.m.LayerOn("gather"))
        self.assertTrue(self.a.db.settings.mapLayers.trainer, "the choice itself is kept for the day OpenMap is gone")
        specs = lst(self.m.MapPlaces(1429))
        self.assertTrue(specs, "gathering places are there")
        self.assertTrue(all(str(s.icon) != "goal" for s in specs))
        self.lua.execute("OpenMapAPI=nil")
        self.assertTrue(self.m.LayerOn("trainer"))

    def test_the_menu_of_openmap_gets_gathering_the_marked_places_and_the_way_into_the_window(self):
        self.lua.execute(OPENMAP)
        self.assertTrue(self.m.RegisterWithOpenMap())
        toggles = lst(self.lua.globals().TOGGLES)
        ids = [str(t.spec.id) for t in toggles]
        self.assertEqual(ids[:10], ["evertally_gather", "evertally_gather_herb", "evertally_gather_ore", "evertally_gather_fishing", "evertally_gather_container", "evertally_gather_all", "evertally_resources", "evertally_marked", "evertally_search", "evertally_journey"])
        self.assertTrue(all(i.startswith("evertally_res_") for i in ids[10:]), "after them one row for every resource (no kinds of trainers yet: the NPC database has not been read)")
        self.assertEqual(len(ids) - 10, 70, "all 70 resources")
        self.a.ShowView = self.lua.eval("function(view) SHOWN=view end")
        marked, search = toggles[7].spec, toggles[8].spec
        self.assertFalse(marked.get())
        self.m.ShowOnWorldMap(self.lua.table_from([self.lua.table(map=1429, x=0.5, y=0.5, title="Here")]), 1429)
        self.assertTrue(marked.get(), "something is marked now")
        marked.set(False)
        self.assertEqual(len(lst(self.m.extra)), 0, "switching it off clears the places")
        search.set(True)
        self.assertEqual(self.lua.globals().SHOWN, "database")
        self.assertFalse(search.get(), "an action stays off")

    def test_there_is_no_second_button_over_openmaps_map(self):
        self.lua.execute(OPENMAP)
        self.assertTrue(self.m.BuildMapPanel())
        self.assertIsNone(self.lua.globals().EvertallyMapButton)

    # ---- the stitched view ----
    def test_the_zones_round_the_stitched_view_are_visible_maps_too(self):
        self.lua.execute(OPENMAP)
        self.assertEqual(sorted(int(i) for i in lst(self.m.VisibleMaps())), [1429, 1436, 1453], "the zone under the map and the two neighbours OpenMap names at the edges of the view")
        self.lua.execute("STITCHED=false")
        self.assertEqual([int(i) for i in lst(self.m.VisibleMaps())], [1429], "not stitched: only the map the game shows")
        self.lua.execute("OpenMapAPI=nil;WorldMapFrame.IsShown=function() return false end")
        self.assertEqual(lst(self.m.VisibleMaps()), [], "no map open: nothing to draw")

    def test_gathering_places_are_drawn_in_the_neighbouring_zones_of_the_stitched_map(self):
        self.lua.execute(OPENMAP)
        self.m.RefreshLayerPins(True)
        drawn = self.pin_maps()
        self.assertIn(1429, drawn)
        self.assertIn(1436, drawn, "Westfall lies in the view: its gathering places come along")
        count = len(lst(self.lua.eval("(function() local o={} for f in pairs(PINLOG.world) do o[#o+1]=f end return o end)()")))
        self.assertLessEqual(count, 900, "never more than the pin budget")
        self.lua.execute("STITCHED=false")
        self.m.RefreshLayerPins(False)
        self.assertEqual(self.pin_maps(), [1429], "back on a plain zone map only its own")

    def test_showing_a_place_glides_openmaps_view_to_it(self):
        self.lua.execute(OPENMAP)
        self.m.ShowOnWorldMap(self.lua.table_from([self.lua.table(map=1429, x=0.4, y=0.6, title="Here")]), 1429)
        self.assertEqual(self.lua.globals().OPENED, 1429)
        glides = lst(self.lua.globals().GLIDES)
        self.assertEqual((glides[0].u, glides[0].v, glides[0].zoom), (0.31, 0.62, 6), "the stitched world's own coordinates, close in")

    # ---- the tab in the window ----
    def test_the_map_tab_shows_only_what_evertally_adds_to_openmap_and_each_switch_works(self):
        self.lua.execute(OPENMAP)
        body = self.lua.eval("CreateFrame")("Frame", None, None)
        body.SetSize(body, 600, 420)
        self.m.BuildWorld(body, self.a.UIKit())
        self.m.RefreshWorld(body)
        rows = {str(r.key): r for r in lst(body.tabFrames["map"].mapTab.rows)}
        self.assertEqual(sorted(rows), ["container", "fishing", "gather", "herb", "ore"], "OpenMap has the other layers itself: no switch for them here")
        self.assertTrue(self.a.db.settings.mapLayers.gather)
        rows["gather"].scripts.OnClick(rows["gather"])
        self.assertFalse(self.a.db.settings.mapLayers.gather, "gathering is Evertally's: a click switches it (it was on)")
        self.assertTrue(self.m.GatherTypeOn("herb"))
        rows["herb"].scripts.OnClick(rows["herb"])
        self.assertFalse(self.m.GatherTypeOn("herb"), "a click takes the herbs off")


if __name__ == "__main__":
    unittest.main()

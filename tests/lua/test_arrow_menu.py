"""The navigation arrow: a right click opens a menu (change size, hide, reset, stop), the size is changed by dragging a corner, a drag moves it
and a plain left click opens what the arrow leads to."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_addon import MOCK_UI_LUA, ROOT, runtime
import test_navigation as navigation_tests   # (the module, so that its tests are not collected again here)
from test_navigation import FAKE_LIBS, RECORD_ROTATION

MAP_DIR = ROOT / "addon" / "Evertally_Map"


def lst(table):
    return [table[i] for i in range(1, len(table) + 1)] if table is not None else []


class ArrowTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = runtime()
        self.lua.execute(MOCK_UI_LUA)
        self.lua.execute(RECORD_ROTATION)
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
          SHOWN=nil
        """)
        self.lua.execute(navigation_tests.MapTests.FAKE_QUESTIE)
        self.m = self.lua.table()
        for line in (MAP_DIR / "Evertally_Map.toc").read_text(encoding="utf8").splitlines():
            if line.endswith(".lua") and not line.startswith("Libs"):
                chunk = self.lua.eval("loadstring")((MAP_DIR / line).read_text(encoding="utf8"), line)
                if isinstance(chunk, tuple):
                    self.fail(str(chunk))
                chunk("Evertally_Map", self.m)
        # These tests isolate arrow input/rotation. Real collision searches and
        # waiting states are exercised by test_roadpath/test_road_navigation.
        self.m.RoadPath = None
        self.a.ShowView = self.lua.eval("function(view) SHOWN=view end")

    def go(self, **extra):
        target = self.lua.table(kind="point", map=1429, x=0.6, y=0.3, label="Goal", **extra)
        self.assertTrue(self.m.Navigate(target))
        return self.lua.globals().EvertallyTracker

    def menu(self):
        return self.lua.globals().EvertallyArrowMenu

    def choose(self, index):
        item = self.menu()["items"][index]
        item.scripts.OnClick(item)

    def labels(self):
        menu = self.menu()
        return [str(menu["items"][i].text.text) for i in range(1, 6)]

    # ---- the menu ----
    def test_a_right_click_opens_a_menu_and_does_not_stop_the_navigation(self):
        tracker = self.go()
        tracker.scripts.OnMouseUp(tracker, "RightButton")
        self.assertTrue(self.menu().IsShown(self.menu()))
        self.assertEqual(self.labels(), [self.a.L(k) for k in ("arrowMenuResize", "arrowMenuHide", "arrowMenuReset", "arrowMenuSpfOff", "arrowMenuStop")])
        self.assertIsNotNone(self.m.nav.target, "the old right click ended the navigation: now it only opens the menu")
        self.m.ArrowMenuClose()
        self.assertFalse(self.menu().IsShown(self.menu()))

    def test_stop_in_the_menu_ends_the_navigation(self):
        tracker = self.go()
        tracker.scripts.OnMouseUp(tracker, "RightButton")
        self.choose(5)
        self.assertIsNone(self.m.nav.target)
        self.assertFalse(tracker.IsShown(tracker))
        self.assertFalse(self.menu().IsShown(self.menu()), "choosing closes the menu")

    def test_hide_takes_the_arrow_away_and_the_navigation_goes_on_until_it_is_shown_again(self):
        tracker = self.go()
        tracker.scripts.OnMouseUp(tracker, "RightButton")
        self.choose(2)
        self.assertFalse(tracker.IsShown(tracker))
        self.assertTrue(self.a.db.settings.navArrowHidden, "kept")
        self.assertIsNotNone(self.m.nav.target, "the route and the pins go on")
        self.m.Stop()
        tracker = self.go()
        self.assertFalse(tracker.IsShown(tracker), "a new navigation does not bring it back by itself")
        self.assertTrue(self.m.ArrowShown() is False)
        self.m.SetArrowShown(True)
        self.assertTrue(tracker.IsShown(tracker))
        self.assertFalse(self.a.db.settings.navArrowHidden)

    def test_reset_brings_back_the_size_and_the_place(self):
        tracker = self.go()
        self.a.db.settings.navScale = 2.2
        self.a.db.settings.navPos = self.lua.table_from(["CENTER", 300, 200])
        tracker.scripts.OnMouseUp(tracker, "RightButton")
        self.choose(3)
        self.assertIsNone(self.a.db.settings.navScale)
        self.assertIsNone(self.a.db.settings.navPos)

    # ---- it turns smoothly ----
    def test_the_arrow_turns_with_you_every_frame_not_only_every_tick_of_the_navigation(self):
        self.lua.execute("FACING=0; GetPlayerFacing=function() return FACING end")
        tracker = self.go()       # (the goal is north-east of the player)
        tracker.arrow.SetVertexColor = self.lua.eval("function(self, r, g, b) self.color = {r, g, b} end")
        tracker.scripts.OnUpdate(tracker, 0.016)
        first = float(tracker.arrow.rotation)
        seen = []
        for step in range(1, 6):
            self.lua.execute("FACING=%f" % (step * 0.2))
            tracker.scripts.OnUpdate(tracker, 0.016)           # one frame: no tick of the navigation in between
            seen.append(float(tracker.arrow.rotation))
        self.assertEqual(len(set(seen)), 5, "every frame a new angle")
        self.assertAlmostEqual(first - seen[-1], 1.0, places=2, msg="turning the character by one radian turns the arrow by the same")
        self.assertTrue(all(a > b for a, b in zip([first] + seen, seen)), "it follows you one way, in small steps")

    def test_the_distance_under_the_arrow_follows_you_between_ticks_too(self):
        tracker = self.go()
        tracker.scripts.OnUpdate(tracker, 0.016)
        near = int(str(tracker.distance.text).split()[0])
        self.lua.execute("C_Map.GetPlayerMapPosition=function() return {GetXY=function() return .55,.35 end} end")
        tracker.scripts.OnUpdate(tracker, 0.2)            # (the position is read twenty times a second)
        closer = int(str(tracker.distance.text).split()[0])
        self.assertLess(closer, near, "walking towards it shortens the distance at once")

    # ---- the route line from Shortest Path Forever ----
    FAKE_SPF = """
      SPFLOG = {}
      ShortestPathForever = {API = {
        Navigate = function(owner, map, x, y, title) SPFLOG[#SPFLOG + 1] = "navigate:" .. owner .. ":" .. map; SPFON = true; return true end,
        CurrentStop = function(owner) return SPFON and 1 or nil end,
        Cancel = function(owner) SPFLOG[#SPFLOG + 1] = "cancel:" .. owner; SPFON = nil; return true end}}
    """

    def test_spf_guidance_is_explicit_for_one_destination_and_keeps_our_solid_renderer(self):
        self.lua.execute(self.FAKE_SPF)
        tracker = self.go()
        self.assertFalse(self.m.SpfAuto())
        tracker.scripts.OnMouseUp(tracker, "RightButton")
        self.choose(4)
        self.assertTrue(self.m.SpfAuto())
        self.assertEqual(str(self.lua.globals().SPFLOG[1]), "navigate:Evertally:1429", "the goal goes to it at once")
        self.assertTrue(self.m.SpfDrawsRoute(), "the explicitly requested supplemental journey is running")
        self.m.route = None
        self.m.RefreshRoute(True)
        self.assertEqual(int(self.m.routeDots or 0), 0)
        self.assertEqual(self.labels()[3], self.a.L("arrowMenuSpfOff"), "(the label is read when the menu opens)")
        self.m.Stop()
        self.assertEqual(str(self.lua.globals().SPFLOG[2]), "cancel:Evertally", "stopping ends its journey too")
        self.lua.execute("SPFLOG = {}")
        self.go()
        self.assertEqual(len(self.lua.globals().SPFLOG), 0, "a new destination must not automatically revive breadcrumb guidance")
        self.assertFalse(self.m.SpfAuto())

    def test_old_saved_spf_handoff_is_not_revived_by_normal_navigation(self):
        self.lua.execute(self.FAKE_SPF)
        self.a.db.settings.navSpfAuto = True
        self.go()
        self.assertEqual(len(self.lua.globals().SPFLOG), 0)
        self.assertFalse(self.m.SpfAuto())
        self.assertIsNone(self.a.db.settings.navSpfAuto)

    def test_solid_route_reuses_arrow_terrain_and_drops_already_passed_bends(self):
        self.go()
        self.lua.execute('''
          local M=Evertally.map
          local u,v=M.PlayerPosition();local c,x,y=M.ToYards(u,v)
          M.nav.plan={seconds=30,steps={{mode="walk",fu=u-.01,fv=v-.01,tu=u+.01,tv=v+.01,seconds=30}}}
          M.nav.ground={map=c,index=3,job={state="ready",result={points={{x-20,y-20},{x-10,y-10},{x+5,y+7},{x+10,y+9}}}}}
        ''')
        remaining = self.m.RoutePlan()
        step = remaining.steps[1]
        u, v, *_ = self.m.PlayerPosition()
        self.assertEqual((step.fu, step.fv), (u, v))
        self.assertEqual(len(step.routePath), 3, "player and only the two remaining bends")
        self.assertEqual((step.routePath[1][1], step.routePath[1][2]), (u, v))
        original_start = self.m.nav.plan.steps[1].fu
        self.lua.execute("C_Map.GetPlayerMapPosition=function() return {GetXY=function() return .55,.35 end} end")
        moved = self.m.RoutePlan().steps[1]
        self.assertNotEqual(step.fu, moved.fu, "the route origin moves without a transport replan")
        self.assertEqual(self.m.nav.plan.steps[1].fu, original_start, "the planner's source is not mutated")

    def test_without_shortest_path_forever_the_menu_says_so(self):
        tracker = self.go()
        tracker.scripts.OnMouseUp(tracker, "RightButton")
        self.choose(4)
        self.assertFalse(self.m.SpfAuto())

    # ---- the size ----
    def test_change_size_shows_a_corner_and_dragging_it_sets_the_size_within_limits(self):
        tracker = self.go()
        tracker.GetCenter = self.lua.eval("function() return 500, 400 end")
        tracker.GetScale = self.lua.eval("function(self) return self.scaleNow or 1 end")
        self.lua.execute("CURSOR={x=500,y=400}; GetCursorPosition=function() return CURSOR.x, CURSOR.y end")
        tracker.scripts.OnMouseUp(tracker, "RightButton")
        self.choose(1)
        self.assertTrue(tracker.grip.IsShown(tracker.grip), "the corner to drag")
        tracker.grip.scripts.OnMouseDown(tracker.grip)
        self.assertTrue(tracker.resizing)

        def drag_to(distance):
            self.lua.execute("CURSOR.x = %f" % (500 + distance))
            tracker.scripts.OnUpdate(tracker)
            return float(self.a.db.settings.navScale)
        self.assertAlmostEqual(drag_to(84.8), 2.0, places=1, msg="twice as far as the corner sits: twice the size")
        self.assertEqual(drag_to(2000), 3, "not bigger than three times")
        self.assertEqual(drag_to(1), 0.5, "not smaller than half")
        tracker.grip.scripts.OnMouseUp(tracker.grip)
        self.assertFalse(tracker.resizing)
        self.assertFalse(tracker.grip.IsShown(tracker.grip), "the corner goes when the button is let go")
        drag_to(300)
        self.assertEqual(float(self.a.db.settings.navScale), 0.5, "no more changes after that")

    def test_the_kept_size_and_place_are_applied_when_the_arrow_is_made(self):
        self.a.db.settings.navScale = 1.5
        self.a.db.settings.navPos = self.lua.table_from(["CENTER", 300, 150])
        tracker = self.go()
        self.assertEqual(float(self.m.ArrowScale()), 1.5)
        self.assertIsNotNone(tracker)

    # ---- a drag and a click ----
    def test_a_drag_moves_it_and_opens_nothing_but_a_plain_click_opens_the_goal(self):
        tracker = self.go()
        tracker.scripts.OnMouseDown(tracker)
        tracker.scripts.OnDragStart(tracker)
        tracker.scripts.OnDragStop(tracker)
        tracker.scripts.OnMouseUp(tracker, "LeftButton")
        self.assertIsNone(self.lua.globals().SHOWN, "after a drag nothing opens")
        tracker.scripts.OnMouseDown(tracker)
        tracker.scripts.OnMouseUp(tracker, "LeftButton")
        self.assertEqual(self.lua.globals().SHOWN, "world", "a plain click opens the World page")

    def test_a_click_on_an_arrow_to_a_person_opens_the_people_page(self):
        self.lua.execute("Evertally.LivePeer=function(name) return {name=name,map=1429,x=0.5,y=0.5} end")
        self.assertTrue(self.m.Navigate(self.lua.table(kind="player", name="Bran")))
        tracker = self.lua.globals().EvertallyTracker
        tracker.scripts.OnMouseDown(tracker)
        tracker.scripts.OnMouseUp(tracker, "LeftButton")
        self.assertEqual(self.lua.globals().SHOWN, "people")

    def test_a_click_on_a_meet_or_a_ping_opens_the_people_page_too(self):
        tracker = self.go(source=self.lua.table(view="people"))
        tracker.scripts.OnMouseDown(tracker)
        tracker.scripts.OnMouseUp(tracker, "LeftButton")
        self.assertEqual(self.lua.globals().SHOWN, "people")

    def world(self, tab):
        body = self.lua.eval("CreateFrame")("Frame", None, None)
        body.SetSize(body, 600, 420)
        self.m.BuildWorld(body, self.a.UIKit())
        body.mode = tab
        self.m.RefreshWorld(body)
        self.a.worldBody = body
        return body

    def click(self, tracker):
        tracker.scripts.OnMouseDown(tracker)
        tracker.scripts.OnMouseUp(tracker, "LeftButton")

    def test_a_click_on_a_goal_from_the_database_selects_it_in_the_database_page(self):
        body = self.lua.eval("CreateFrame")("Frame", None, None)
        body.SetSize(body, 600, 420)
        self.m.BuildDatabase(body, self.a.UIKit())
        self.m.RefreshDatabase(body)
        self.a.databaseBody = body
        tracker = self.go(source=self.lua.table(tab="db", kind="quest", id=200))
        self.click(tracker)
        self.assertEqual(self.lua.globals().SHOWN, "database")
        db = body.tabFrames["db"].db
        self.assertEqual((str(db.selected.kind), int(db.selected.id)), ("quest", 200))
        self.assertEqual(str(db.title.text), "Kobold Candles", "the quest the arrow leads to")

    def test_a_click_on_a_resource_goal_selects_that_resource_in_the_gathering_tab(self):
        body = self.world("map")
        spec = self.m.GatherSpecs(1429)[0][1]
        self.assertTrue(self.m.NavigateLayerSpot(spec))
        tracker = self.lua.globals().EvertallyTracker
        self.click(tracker)
        self.assertEqual(str(body.mode), "gather")
        catalog = body.tabFrames["gather"].catalog
        self.assertEqual(str(catalog.selected.key), str(spec.resource), "the resource the arrow leads to is the one selected")

    def test_a_click_on_a_trainer_or_merchant_goal_selects_its_kind_in_the_services_tab(self):
        # (the kinds as they were kept after the NPC database was read)
        group = self.lua.table(key="trainer:prof:herbalism", label="Herbalism trainers", kind="trainer", count=1)
        self.a.db.settings.serviceCache = self.lua.table(v=1, side="A", trainer=self.lua.table_from([group]), vendor=self.lua.table())
        body = self.world("map")
        spec = self.lua.table(kind="service", groupKey="trainer:prof:herbalism", map=1429, x=0.5, y=0.5, title="Brother Herbert")
        self.assertTrue(self.m.NavigateLayerSpot(spec))
        self.click(self.lua.globals().EvertallyTracker)
        self.assertEqual(str(body.mode), "services")
        self.assertEqual(str(body.tabFrames["services"].catalog.selected.key), "trainer:prof:herbalism")

    def test_a_click_on_a_goal_of_the_journey_planner_shows_that_place_in_the_journey_tab(self):
        body = self.world("map")
        place = self.m.Plan.Search("shadowprey", 5)[1]
        tracker = self.go(source=self.lua.table(tab="plan", name=str(place.name)))
        self.click(tracker)
        self.assertEqual(str(body.mode), "plan")
        self.assertEqual(str(body.tabFrames["plan"].plan.chosen.name), str(place.name))

    def test_a_goal_with_no_list_behind_it_opens_the_map_tab(self):
        body = self.world("db")
        tracker = self.go()
        self.click(tracker)
        self.assertEqual(str(body.mode), "map")

    # ---- /etally arrow ----
    def test_etally_arrow_toggles_it(self):
        self.a.map = self.m
        tracker = self.go()
        self.assertFalse(self.a.ToggleArrow(), "toggled off")
        self.assertFalse(tracker.IsShown(tracker))
        self.assertTrue(self.a.ToggleArrow(), "and on again")
        self.assertTrue(tracker.IsShown(tracker))


if __name__ == "__main__":
    unittest.main()

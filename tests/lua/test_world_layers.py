"""Reference gathering/instance layers and catalogue actions, using mock WoW frames only."""
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_addon import MOCK_UI_LUA, ROOT, runtime, map_toc_lines
from test_navigation import FAKE_LIBS

MAP_DIR = ROOT / "addon/Evertally_Map"


def entries(table):
    return [table[i] for i in range(1, len(table) + 1)]


class WorldLayerTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = runtime()
        self.lua.execute(MOCK_UI_LUA)
        self.lua.execute(FAKE_LIBS)
        self.lua.execute('''
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
        ''')
        self.m = self.lua.table()
        # The distribution's own load order, including data modules, is the test contract.
        for line in map_toc_lines():
            if line.endswith(".lua") and not line.startswith("Libs"):
                chunk = self.lua.eval("loadstring")((MAP_DIR / line).read_text(encoding="utf8"), line)
                if isinstance(chunk, tuple):
                    self.fail(str(chunk))
                chunk("Evertally_Map", self.m)

    def pins(self):
        return entries(self.lua.eval("(function() local out={} for f in pairs(PINLOG.world) do out[#out+1]=f end return out end)()"))

    def catalogue(self, tab):
        body = self.lua.eval("CreateFrame")("Frame", None, None)
        body.SetSize(body, 600, 420)
        self.m.BuildWorld(body, self.a.UIKit())
        body.mode = tab
        self.m.RefreshWorld(body)
        frame = body.tabFrames[tab]
        self.assertFalse(bool(frame.failed), self.a.errors["world_" + tab])
        return frame.catalog, body

    def test_gathering_is_zone_scoped_and_bounded_and_does_not_claim_availability(self):
        self.assertEqual(entries(self.m.LayerSpecs(1429, self.lua.table())), [])
        specs = entries(self.m.LayerSpecs(1429, self.lua.table(gather=True)))
        self.assertGreater(len(specs), 10)
        self.assertLessEqual(len(specs), 500)
        self.assertGreaterEqual(self.m.gatherTotal, self.m.gatherDrawn)
        self.assertTrue(all(s.map == 1429 and 0 <= s.x <= 1 and 0 <= s.y <= 1 for s in specs))
        self.assertTrue(all(any("availability" in str(line) for line in entries(s.lines)) for s in specs))
        self.assertEqual(entries(self.m.LayerSpecs(1415, self.lua.table(gather=True))), [])

    def test_resource_type_and_name_filters_change_the_real_pin_set(self):
        nodes = entries(self.m.GatherResources("peacebloom"))
        self.assertEqual(len(nodes), 1)
        item = nodes[0]
        self.m.SetGatherResource(item.key)
        specs, total = self.m.GatherSpecs(1429)
        self.assertGreater(total, 0)
        self.assertTrue(all(str(s.title) == "Peacebloom" for s in entries(specs)))
        self.m.SetGatherType("herb", False)
        self.assertEqual(entries(self.m.GatherSpecs(1429)[0]), [])
        self.assertEqual(entries(self.m.GatherResources("peacebloom")), [])
        self.assertFalse(self.m.SetGatherType("untrusted", True))

    def test_generated_entrances_match_the_source_and_missing_locations_stay_unknown(self):
        source = json.loads((ROOT / "platform/public/media/db/dungeons.json").read_text(encoding="utf8"))["entries"]
        self.assertEqual(len(self.m.Instances()), len(source))
        got = {str(item.key): item for item in entries(self.m.Instances())}
        for item in source:
            if item.get("entrance") and got[item["key"]].map:
                self.assertAlmostEqual(got[item["key"]].x, item["entrance"]["x"] / 100)
                self.assertAlmostEqual(got[item["key"]].y, item["entrance"]["y"] / 100)
        self.assertTrue(any(not item.map for item in got.values()))
        self.assertEqual(entries(self.m.Instances("deadmines", "raid")), [])
        self.assertEqual(len(self.m.Instances("deadmines", "dungeon")), 1)

    def test_continent_entrance_pin_click_navigates_to_the_original_zone_coordinate(self):
        self.lua.globals().WORLDMAP = 1415
        self.m.SetLayer("instances", True)
        pin = next(p for p in self.pins() if str(p.spec.title) == "The Deadmines")
        self.assertEqual(pin.spec.map, 1415)
        self.assertEqual(pin.spec.targetMap, 1436)
        pin.scripts.OnMouseUp(pin, "LeftButton")
        self.assertEqual(self.m.nav.target.map, 1436)
        self.assertAlmostEqual(self.m.nav.target.x, pin.spec.targetX)
        self.m.Stop()
        pin.scripts.OnMouseUp(pin, "RightButton")
        self.assertIsNone(self.m.nav.target)

    def test_switches_refresh_pins_and_persist_and_filter_raids(self):
        self.lua.globals().WORLDMAP = 1415
        self.m.SetInstanceKind("raid")
        self.m.SetLayer("instances", True)
        self.assertTrue(self.a.db.settings.mapLayers.instances)
        kinds = {str(p.spec.kind) for p in self.pins()}
        self.assertEqual(kinds, {"instance"})
        for pin in self.pins():
            item = next(item for item in entries(self.m.Instances()) if str(item.key) == str(pin.spec.key))
            self.assertEqual(item.kind, "raid")
        self.m.SetLayer("instances", False)
        self.assertEqual(self.pins(), [])
        self.assertFalse(self.m.SetLayer("not-a-layer", True))

    def test_catalogues_build_search_and_show_only_known_places(self):
        gather, body = self.catalogue("gather")
        gather.box.SetText(gather.box, "peacebloom")
        gather.box.scripts.OnTextChanged(gather.box)
        self.assertEqual(len(gather.results), 1)
        self.assertTrue(gather.show.IsShown(gather.show))
        gather.show.scripts.OnClick()
        self.assertTrue(self.m.LayerOn("gather"))
        self.assertEqual(self.a.db.settings.gatherResource, gather.selected.key)
        self.assertEqual(self.lua.globals().OPENED, 1429)
        instances, body = self.catalogue("instances")
        unknown = next(item for item in entries(self.m.Instances()) if not item.map)
        instances.box.SetText(instances.box, str(unknown.name))
        instances.box.scripts.OnTextChanged(instances.box)
        self.assertFalse(instances.go.IsShown(instances.go))
        self.assertIn("unavailable", str(instances.detail.text))

    def test_each_resource_filter_controls_its_own_type_and_gather_pin_click_starts_navigation(self):
        gather, _ = self.catalogue("gather")
        for kind in ("herb", "ore", "fishing", "container"):
            self.assertTrue(self.m.GatherTypeOn(kind))
            gather.filterButtons[kind].scripts.OnClick()
            self.assertFalse(self.m.GatherTypeOn(kind))
        self.assertEqual(len(gather.results), 0)
        gather.filterButtons.herb.scripts.OnClick()
        self.assertTrue(self.m.GatherTypeOn("herb"))
        self.m.SetLayer("gather", True)
        pin = next(pin for pin in self.pins() if str(pin.spec.kind) == "gather")
        pin.scripts.OnMouseUp(pin, "LeftButton")
        self.assertEqual(self.m.nav.target.map, 1429)
        self.assertAlmostEqual(self.m.nav.target.x, pin.spec.x)

    def test_generated_gathering_points_match_the_existing_reference_source(self):
        source = json.loads((ROOT / "platform/public/media/gather/gather.json").read_text(encoding="utf8"))
        actual = {}
        for map_id, groups in self.m.layerData.gather.items():
            for group in entries(groups):
                key = str(self.m.layerData.nodes[group[1]][1])
                actual.setdefault(key, {})[str(map_id)] = entries(group[2])
        self.assertEqual(actual, source["points"])

    # ---- pictures and the resources the player hides ----
    def test_every_gathering_resource_has_a_picture_of_its_own_or_of_its_kind(self):
        nodes = entries(self.m.layerData.nodes)
        self.assertGreater(len(nodes), 60)
        for node in nodes:
            icon = self.m.GatherIcon(node[1], node[3])
            self.assertIsInstance(icon, (int, float), f"{node[1]} has no picture")
            self.assertGreater(icon, 0)
        specific = [n for n in nodes if self.m.gatherIcons[n[1]] is not None]
        self.assertGreaterEqual(len(specific) / len(nodes), 0.9, "nearly every resource has its own picture, not just its kind's")
        self.assertEqual(self.m.GatherIcon("herb:no_such_thing", "herb"), self.m.gatherKindIcons["herb"], "an unknown one falls back to its kind")
        self.assertIsNone(self.m.GatherIcon("herb:no_such_thing", "nothing"))

    def test_the_pins_carry_the_picture_and_the_ring_of_the_kind(self):
        specs = entries(self.m.LayerSpecs(1429, self.lua.table(gather=True)))
        self.assertTrue(all(s.iconFile for s in specs), "a gathering pin always has a picture")
        self.m.RefreshLayerPins(True)
        pin = next(p for p in self.pins() if str(p.spec.kind) == "gather")
        self.assertEqual(pin.tex.texture, pin.spec.iconFile, "the pin shows the resource's own picture")
        self.assertTrue(pin.ring.IsShown(pin.ring), "behind it the ring that says herb, ore, fishing or chest")

    def test_gathering_is_on_from_the_start_and_the_older_layers_are_not(self):
        self.assertTrue(self.m.LayerOn("gather"))
        self.assertFalse(self.m.LayerOn("trainer") or self.m.LayerOn("travel"))

    def test_a_resource_the_player_hides_leaves_the_map_and_comes_back(self):
        self.m.RefreshLayerPins(True)
        key = str(self.m.GatherResources("peacebloom")[1].key)
        before = len(self.pins())
        self.assertTrue(self.m.GatherShown(key))
        self.m.SetGatherShown(key, False)
        self.assertFalse(self.m.GatherShown(key))
        self.assertTrue(self.a.db.settings.gatherOff[key], "kept in the settings")
        self.assertLess(len(self.pins()), before, "its pins are gone")
        self.assertFalse(any(str(p.spec.resource) == key for p in self.pins()))
        self.m.SetGatherShown(key, True)
        self.assertEqual(len(self.pins()), before)
        self.assertIsNone(self.a.db.settings.gatherOff[key], "shown again: no entry left")
        self.assertFalse(self.m.SetGatherShown(5, False), "only a name can be switched")

    def test_a_whole_kind_or_everything_is_hidden_and_shown_at_once(self):
        herbs = [n[1] for n in entries(self.m.layerData.nodes) if n[3] == "herb"]
        ores = [n[1] for n in entries(self.m.layerData.nodes) if n[3] == "ore"]
        self.m.SetGatherAll(False, "herb")
        self.assertFalse(any(self.m.GatherShown(k) for k in herbs))
        self.assertTrue(all(self.m.GatherShown(k) for k in ores), "the other kinds are not touched")
        self.m.SetGatherAll(False)
        self.assertFalse(any(self.m.GatherShown(k) for k in ores))
        self.m.SetGatherAll(True)
        self.assertTrue(all(self.m.GatherShown(k) for k in herbs + ores))
        self.assertEqual(len([k for k in self.a.db.settings.gatherOff.keys()]), 0, "nothing is left hidden")

    def test_the_catalogue_shows_a_picture_and_a_tick_on_every_resource_and_the_tick_hides_it(self):
        gather, _ = self.catalogue("gather")
        row = gather.rows[1]
        self.assertTrue(row.icon.IsShown(row.icon) and row.check.IsShown(row.check))
        self.assertEqual(row.icon.texture, self.m.GatherIcon(row.item.key, row.item.kind))
        self.assertTrue(self.m.GatherShown(row.item.key))
        key = str(row.item.key)
        row.check.box.SetAlpha = self.lua.eval("function(self, v) self.alpha = v end")   # (the plain mock keeps no alpha)
        row.check.scripts.OnClick()
        self.assertFalse(self.m.GatherShown(key), "the tick takes the resource off the map")
        self.assertEqual(row.check.box.alpha, 0.25, "and shows it unticked")
        row.check.scripts.OnClick()
        self.assertTrue(self.m.GatherShown(key))
        self.assertEqual(row.check.box.alpha, 1)
        instances, _ = self.catalogue("instances")
        self.assertFalse(instances.rows[1].icon.IsShown(instances.rows[1].icon), "dungeons have no tick")

    def test_the_map_tab_switches_the_layers_and_is_the_first_thing_the_world_page_shows(self):
        body = self.lua.eval("CreateFrame")("Frame", None, None)
        body.SetSize(body, 600, 420)
        self.m.BuildWorld(body, self.a.UIKit())
        self.assertEqual(body.mode, "map")
        self.m.RefreshWorld(body)
        frame = body.tabFrames["map"]
        self.assertFalse(bool(frame.failed), self.a.errors["world_map"])
        rows = frame.mapTab.rows
        self.assertEqual(len(entries(rows)), len(entries(self.m.layerKeys)) + 4, "one switch per layer and one per kind of gathering")
        first = rows[1]
        self.assertFalse(self.m.LayerOn(first.key))
        first.scripts.OnClick(first)
        self.assertTrue(self.m.LayerOn(first.key), "a click switches the layer on")
        first.scripts.OnClick(first)
        self.assertFalse(self.m.LayerOn(first.key))
        self.lua.execute("OPENED=nil; C_Map.OpenWorldMap=function(id) OPENED=id end")
        frame.mapTab.open.scripts.OnClick(frame.mapTab.open)
        self.assertEqual(self.lua.globals().OPENED, 1429, "the button opens the game's world map on the zone you are in")


if __name__ == "__main__":
    unittest.main()

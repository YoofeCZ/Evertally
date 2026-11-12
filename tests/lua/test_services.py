"""Trainers and merchants picked one kind at a time: the kinds (from the NPC titles), what is kept, what is drawn, OpenMap's menu and the window's list."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_addon import MOCK_UI_LUA, ROOT, runtime
from test_navigation import FAKE_LIBS

MAP_DIR = ROOT / "addon" / "Evertally_Map"
OPENMAP = "TOGGLES={}; OpenMapAPI={major=1,version=4,RegisterMenuToggle=function(owner,spec) TOGGLES[#TOGGLES+1]={owner=owner,spec=spec} end}"
QUESTIE = """
local function entity(rows)
  local e = {}
  function e.GetAllIds() local ids = {} for id in pairs(rows) do ids[#ids + 1] = id end table.sort(ids) return ids end
  function e.GetAll(id, wanted)
    local row = rows[id]
    if not row then return nil end
    local out = {n = #wanted}
    for i, key in ipairs(wanted) do out[i] = row[key] end
    return out
  end
  return e
end
LibQuestieDB = {
  RequireContract = function(n) return n == 2 end,
  Support = {Get = function(name) if name == "ZoneDB" then return {private = {areaIdToUiMapId = "return {[12]=1429,[40]=1436}", areaIdToUiMapIdOverride = "return {}"}} end end},
  Npc = entity({
    [1] = {name = "Brother Herbert", subName = "Herbalism Trainer", npcFlags = 16, friendlyToFaction = "AH", spawns = {[12] = {{40, 40}}}},
    [2] = {name = "Kaela", subName = "Journeyman Alchemist", npcFlags = 16, friendlyToFaction = "AH", spawns = {[12] = {{50, 50}, {52, 52}}}},
    [3] = {name = "Magda", subName = "Warrior Trainer", npcFlags = 16, friendlyToFaction = "A", spawns = {[12] = {{20, 20}}}},
    [4] = {name = "Grok", subName = "Warrior Trainer", npcFlags = 16, friendlyToFaction = "H", spawns = {[12] = {{30, 30}}}},
    [5] = {name = "Gina", subName = "Alchemy Supplies", npcFlags = 128, friendlyToFaction = "AH", spawns = {[12] = {{60, 60}}}},
    [6] = {name = "Tom", subName = "Innkeeper", npcFlags = 128 + 65536, friendlyToFaction = "AH", spawns = {[12] = {{70, 70}}}},
    [7] = {name = "Reagent Rob", subName = "Reagent Vendor", npcFlags = 128, friendlyToFaction = "AH", spawns = {[12] = {{10, 10}}}},
    [8] = {name = "Alchemy Teacher", subName = "Alchemy Trainer", npcFlags = 16, friendlyToFaction = "AH", spawns = {[40] = {{55, 55}}}},
  }),
  Quest = entity({}), Item = entity({}),
}
"""


def lst(table):
    return [table[i] for i in range(1, len(table) + 1)] if table is not None else []


class ServiceTests(unittest.TestCase):
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
        self.lua.execute(QUESTIE)
        self.m = self.lua.table()
        for line in (MAP_DIR / "Evertally_Map.toc").read_text(encoding="utf8").splitlines():
            if line.endswith(".lua") and not line.startswith("Libs"):
                chunk = self.lua.eval("loadstring")((MAP_DIR / line).read_text(encoding="utf8"), line)
                if isinstance(chunk, tuple):
                    self.fail(str(chunk))
                chunk("Evertally_Map", self.m)
        self.a.db.settings.mapLayers = self.lua.table(gather=False)

    def scan(self):
        db = self.m.Db.Open()
        self.assertIsNotNone(db)
        self.m.dbHandle = db
        done, _ = self.m.Db.ScanServices(db, None, "A")
        self.assertTrue(done)
        return db

    def labels(self, kind):
        return [str(g.label) for g in lst(self.m.ServiceGroups(kind))]

    # ---- the kinds ----
    def test_titles_become_kinds_the_way_a_player_thinks_of_them(self):
        group = self.m.ServiceGroupOf
        self.assertEqual(tuple(str(x) for x in group("trainer", "Journeyman Alchemist")), ("prof:alchemy", "Alchemy trainers"))
        self.assertEqual(str(group("trainer", "Alchemy Trainer")[0]), "prof:alchemy", "the rank and the plain title are one kind")
        self.assertEqual(str(group("trainer", "Expert Blacksmith")[0]), "prof:blacksmithing")
        self.assertEqual(str(group("trainer", "Warrior Trainer")[0]), "class:warrior")
        self.assertEqual(str(group("trainer", "Alchemy Supplies")[0]), "t:alchemy supplies", "a shop with a profession's name is not its trainer")
        self.assertEqual(str(group("trainer", "Pet Trainer")[0]), "t:pet trainer")
        self.assertEqual(tuple(str(x) for x in group("vendor", "Reagent Vendor")), ("t:reagent vendor", "Reagent Vendor"))
        self.assertIsNone(group("vendor", "Innkeeper"), "OpenMap draws innkeepers itself")
        self.assertIsNone(group("vendor", ""))
        self.assertIsNone(group("vendor", None))

    def test_the_scan_lists_the_kinds_of_your_side_with_the_places_each_has(self):
        self.scan()
        self.assertEqual(self.labels("trainer"), ["Alchemy trainers", "Herbalism trainers", "Warrior trainers"])
        counts = {str(g.label): int(g.count) for g in lst(self.m.ServiceGroups("trainer"))}
        self.assertEqual(counts["Alchemy trainers"], 3, "two titles, three places")
        self.assertEqual(counts["Warrior trainers"], 1, "the other side's trainer is not yours")
        self.assertEqual(self.labels("vendor"), ["Alchemy Supplies", "Reagent Vendor"])

    # ---- picking and drawing ----
    def test_only_the_picked_kinds_are_drawn_and_unpicking_takes_them_off(self):
        self.scan()
        layers = self.lua.table()
        self.assertEqual(lst(self.m.LayerSpecs(1429, layers)), [], "nothing is picked: nothing is drawn")
        self.assertTrue(self.m.SetServicePicked("trainer:prof:herbalism", True))
        specs = lst(self.m.LayerSpecs(1429, layers))
        self.assertEqual([str(s.title) for s in specs], ["Brother Herbert"])
        self.assertTrue(specs[0].iconFile and specs[0].navigate, "a picture, and a click navigates")
        self.assertEqual(lst(specs[0].lines)[0], "Herbalism Trainer")
        self.m.SetServicePicked("trainer:prof:alchemy", True)
        self.assertEqual(sorted(str(s.title) for s in lst(self.m.LayerSpecs(1429, layers))), ["Brother Herbert", "Kaela", "Kaela"])
        self.m.SetServicePicked("trainer:prof:herbalism", False)
        self.assertEqual(sorted(str(s.title) for s in lst(self.m.LayerSpecs(1429, layers))), ["Kaela", "Kaela"])
        self.assertEqual([str(s.title) for s in lst(self.m.LayerSpecs(1436, layers))], ["Alchemy Teacher"], "each map has its own")
        self.assertFalse(self.m.SetServicePicked("nonsense", True), "only a kind in the form kind:name")
        self.m.ClearServicePicks()
        self.assertEqual(lst(self.m.LayerSpecs(1429, layers)), [])

    def test_a_layer_that_already_draws_the_whole_sort_leaves_the_picked_ones_alone(self):
        self.scan()
        self.m.SetServicePicked("trainer:class:warrior", True)
        both = lst(self.m.LayerSpecs(1429, self.lua.table(trainer=True)))
        self.assertEqual([str(s.title) for s in both if str(s.kind) == "service"], [], "no place twice")
        self.assertTrue(any(str(s.title) == "Magda" for s in both), "the layer draws it")

    def test_the_picks_are_kept_in_the_settings(self):
        self.m.SetServicePicked("vendor:t:reagent vendor", True)
        self.assertTrue(self.a.db.settings.servicePicks["vendor:t:reagent vendor"])
        self.assertTrue(self.m.ServicePicked("vendor:t:reagent vendor"))

    # ---- the scan and what is kept ----
    def test_the_list_is_kept_so_the_menu_has_it_without_reading_the_database_again(self):
        self.assertTrue(self.m.ServiceNeeded(), "nothing kept yet: the scan has to run once")
        self.scan()
        self.m.ServiceScanDone()
        self.assertTrue(self.m.ServiceCacheValid())
        self.assertFalse(self.m.ServiceNeeded(), "kept, nothing picked, nobody looking: left alone")
        self.m.Db.scan = None
        self.assertEqual(self.labels("trainer"), ["Alchemy trainers", "Herbalism trainers", "Warrior trainers"], "from what was kept")
        self.m.wantServices = True
        self.assertTrue(self.m.ServiceNeeded(), "the window's list wants it read")
        self.m.wantServices = False
        self.m.SetServicePicked("trainer:prof:alchemy", True)
        self.assertTrue(self.m.ServiceNeeded(), "something picked has to be drawn: needs the places")
        self.a.db.settings.serviceCache.side = "H"
        self.assertFalse(self.m.ServiceCacheValid(), "kept for the other side: not valid")

    # ---- OpenMap's menu ----
    def test_openmaps_menu_gets_a_row_for_each_trainer_kind_and_the_merchant_kinds_with_places(self):
        self.lua.execute(OPENMAP)
        self.scan()
        self.m.ServiceScanDone()
        toggles = lst(self.lua.globals().TOGGLES)
        rows = {str(t.spec.id): t.spec for t in toggles if str(t.spec.id).startswith("evertally_svc_")}
        self.assertIn("evertally_svc_trainer:prof:alchemy", rows)
        self.assertEqual(str(rows["evertally_svc_trainer:prof:alchemy"].label), "Alchemy trainers (3)")
        self.assertEqual(str(rows["evertally_svc_trainer:prof:alchemy"].section), "Evertally: trainers")
        self.assertEqual(str(rows["evertally_svc_trainer:prof:alchemy"].tab), "show")
        self.assertFalse(any("vendor" in key for key in rows), "merchants with fewer than six places are in the window only")
        spec = rows["evertally_svc_trainer:prof:herbalism"]
        self.assertFalse(spec.get())
        spec.set(True)
        self.assertTrue(spec.get())
        self.assertTrue(self.m.ServicePicked("trainer:prof:herbalism"))

    def test_openmaps_menu_is_in_english_whatever_language_the_player_uses(self):
        self.lua.execute(OPENMAP)
        self.a.db.settings.language = "cs"
        self.assertTrue(self.m.RegisterWithOpenMap())
        for toggle in lst(self.lua.globals().TOGGLES):
            label = str(toggle.spec.label)
            self.assertFalse(any(ch in label for ch in "čřšžěůďťňÁČŘŠŽ"), f"'{label}' has letters the menu's font lacks")
        labels = [str(t.spec.label) for t in lst(self.lua.globals().TOGGLES)]
        self.assertIn("Gathering: herbs", labels)

    def test_every_resource_has_a_row_with_its_icon_and_ticking_one_shows_it(self):
        self.lua.execute(OPENMAP)
        self.m.RegisterWithOpenMap()
        rows = {str(t.spec.id): t.spec for t in lst(self.lua.globals().TOGGLES) if str(t.spec.id).startswith("evertally_res_")}
        self.assertEqual(len(rows), 70)
        peace = rows["evertally_res_herb:peacebloom"]
        self.assertEqual(str(peace.label), "Peacebloom")
        self.assertTrue(peace.icon, "its own icon")
        self.assertEqual(str(peace.section), "Evertally: herbs")
        self.m.SetGatherAll(False)
        self.m.SetLayer("gather", False)
        self.m.SetGatherType("herb", False)
        self.assertFalse(peace.get())
        peace.set(True)
        self.assertTrue(peace.get())
        self.assertTrue(self.m.LayerOn("gather") and self.m.GatherTypeOn("herb"), "ticking one is asking to see it")
        self.assertFalse(rows["evertally_res_herb:silverleaf"].get(), "and only that one")

    def test_the_all_resources_row_shows_or_hides_every_one(self):
        self.lua.execute(OPENMAP)
        self.m.RegisterWithOpenMap()
        every = next(t.spec for t in lst(self.lua.globals().TOGGLES) if str(t.spec.id) == "evertally_gather_all")
        self.assertTrue(every.get())
        every.set(False)
        self.assertFalse(any(self.m.GatherShown(n[1]) for n in lst(self.m.layerData.nodes)))
        self.assertFalse(every.get())
        self.m.SetGatherShown("herb:peacebloom", True)
        self.assertFalse(every.get(), "not all of them")
        every.set(True)
        self.assertTrue(every.get())

    # ---- the window ----
    def services_tab(self):
        body = self.lua.eval("CreateFrame")("Frame", None, None)
        body.SetSize(body, 600, 420)
        self.m.BuildWorld(body, self.a.UIKit())
        body.mode = "services"
        self.m.RefreshWorld(body)
        frame = body.tabFrames["services"]
        self.assertFalse(bool(frame.failed), self.a.errors["world_services"])
        return frame.catalog

    def test_the_services_tab_lists_the_kinds_with_a_tick_and_asks_for_the_scan(self):
        self.scan()
        tab = self.services_tab()
        self.assertTrue(self.m.wantServices, "the scan runs while the list is open")
        self.assertEqual([str(i.name) for i in lst(tab.results)], ["Alchemy trainers", "Herbalism trainers", "Warrior trainers"])
        row = tab.rows[1]
        self.assertTrue(row.check.IsShown(row.check) and row.icon.IsShown(row.icon))
        self.assertFalse(self.m.ServicePicked(str(row.item.key)))
        row.check.scripts.OnClick()
        self.assertTrue(self.m.ServicePicked(str(row.item.key)), "the tick draws it on the map")
        tab.filterButtons["vendor"].scripts.OnClick()
        self.assertEqual([str(i.name) for i in lst(tab.results)], ["Alchemy Supplies", "Reagent Vendor"], "the other sort")
        tab.box.SetText(tab.box, "reag")
        tab.box.scripts.OnTextChanged(tab.box)
        self.assertEqual([str(i.name) for i in lst(tab.results)], ["Reagent Vendor"], "search narrows it")

    def test_show_all_and_hide_all_take_what_the_list_shows(self):
        self.scan()
        tab = self.services_tab()
        tab.showAll.scripts.OnClick()
        self.assertTrue(all(self.m.ServicePicked(str(i.key)) for i in lst(tab.results)))
        tab.hideAll.scripts.OnClick()
        self.assertFalse(any(self.m.ServicePicked(str(i.key)) for i in lst(tab.results)))
        tab.box.SetText(tab.box, "alch")
        tab.box.scripts.OnTextChanged(tab.box)
        tab.showAll.scripts.OnClick()
        self.assertTrue(self.m.ServicePicked("trainer:prof:alchemy"))
        self.assertFalse(self.m.ServicePicked("trainer:class:warrior"), "only what the search found")
        tab.all.scripts.OnClick()
        self.assertEqual(self.a.db.settings.servicePicks.keys() and len(list(self.a.db.settings.servicePicks.keys())), 0, "clear picks")

    def test_show_all_and_hide_all_work_on_the_resources_too(self):
        body = self.lua.eval("CreateFrame")("Frame", None, None)
        body.SetSize(body, 600, 420)
        self.m.BuildWorld(body, self.a.UIKit())
        body.mode = "gather"
        self.m.RefreshWorld(body)
        tab = body.tabFrames["gather"].catalog
        tab.hideAll.scripts.OnClick()
        self.assertFalse(any(self.m.GatherShown(str(i.key)) for i in lst(tab.results)))
        tab.box.SetText(tab.box, "silver")
        tab.box.scripts.OnTextChanged(tab.box)
        tab.showAll.scripts.OnClick()
        self.assertTrue(self.m.GatherShown("herb:silverleaf"))
        self.assertFalse(self.m.GatherShown("herb:peacebloom"), "only what the search found")


if __name__ == "__main__":
    unittest.main()

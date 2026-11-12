"""The Dungeon Journal page, built like the journal itself: a grid of cards with banners, and in a dungeon the tabs Bosses / Quests / Map. The data and the
art are the DungeonJournal add-on's; without it the instances Evertally knows."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_addon import MOCK_UI_LUA, ROOT, runtime
from test_navigation import FAKE_LIBS

MAP_DIR = ROOT / "addon" / "Evertally_Map"
FAKE_JOURNAL = """
ForeverDungeonJournal_NS = {
  BOSS_LEVELS = {["The Deadmines"] = {["Rhahk'Zor"] = "19", ["Cookie"] = "20"}},
  DUNGEON_HOME_ART = {["The Deadmines"] = "Interface\\\\AddOns\\\\ForeverDungeonJournal\\\\Media\\\\DeadminesHome"},
  DUNGEON_HOME_TEXCOORD = {["The Deadmines"] = {0, 1, 0.06, 0.94}},
  DUNGEON_MAPS = {["The Deadmines"] = {floors = {{texture = "Interface\\\\AddOns\\\\ForeverDungeonJournal\\\\Media\\\\DeadminesMap", texBottom = 683 / 1024}},
    bosses = {{name = "Rhahk'Zor", x = 0.5, y = 0.7}, {name = "Cookie", x = 0.3, y = 0.2}}}},
  DB = {
    ["Wailing Caverns"] = {level = "15-24", location = "Northern Barrens", description = "Deep beneath the Barrens.", icon = "Interface\\\\Icons\\\\Spell_Nature_Purge",
      bosses = {{name = "Lord Cobrahn", loot = {{6460, "Cobrahn's Grasp", "Waist, Leather", 3}}}},
      quests = {{id = 1486, name = "Deviate Hides", level = 17, requires = 13, faction = "Both", objective = "Bring 20 Deviate Hides to Nalpak.", pickup = "Nalpak, The Barrens",
        turnin = "Nalpak, The Barrens", rewardChoice = true, rewards = "Choose: Slick Deviate Leggings\\n4,640 XP", rewardItems = {{6480, "Slick Deviate Leggings", 2}, {918, "Deviate Hide Pack", 1}}}}},
    ["The Deadmines"] = {level = "10-20", location = "Westfall", description = "Miners and pirates.", icon = "Interface\\\\Icons\\\\INV_Misc_Bone_ElfSkull_01",
      bosses = {{name = "Rhahk'Zor", loot = {{872, "Rockslicer", "Two-Hand, Axe", 3}, {5187, "Rhahk'Zor's Hammer", "Two-Hand, Mace", 3}}},
                {name = "Cookie", loot = {{5197, "Cookie's Tenderizer", "One-Hand, Mace", 3}, {5198, "Cookie's Stirring Rod", "Held In Off-hand", 3}}}},
      quests = {}},
  }}
"""


def lst(table):
    return [table[i] for i in range(1, len(table) + 1)] if table is not None else []


class DungeonTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = runtime()
        self.lua.execute(MOCK_UI_LUA)
        self.lua.execute(FAKE_LIBS)
        self.lua.execute("""
          MAPID=1429
          C_Map={GetBestMapForUnit=function() return MAPID end,
            GetPlayerMapPosition=function() return {GetXY=function() return .42,.65 end} end,
            GetMapInfo=function(id) return {name="Map "..id} end}
          UnitFactionGroup=function() return "Alliance" end
          GetItemIcon=function(id) return 130000 + id end
          SHOWN=nil
        """)
        self.m = self.lua.table()
        for line in (MAP_DIR / "Evertally_Map.toc").read_text(encoding="utf8").splitlines():
            if line.endswith(".lua") and not line.startswith("Libs"):
                chunk = self.lua.eval("loadstring")((MAP_DIR / line).read_text(encoding="utf8"), line)
                if isinstance(chunk, tuple):
                    self.fail(str(chunk))
                chunk("Evertally_Map", self.m)
        self.a.ShowView = self.lua.eval("function(view) SHOWN=view end")

    def page(self):
        body = self.lua.eval("CreateFrame")("Frame", None, None)
        body.SetSize(body, 700, 420)
        self.m.BuildDungeons(body, self.a.UIKit())
        self.m.RefreshDungeons(body)
        self.a.dungeonsBody = body
        return body, body["dungeons"]

    def names(self, dj):
        return [str(e.name) for e in lst(dj.results)]

    def open(self, dj, name):
        card = next(c for c in lst(dj.cards) if c.entry and str(c.entry.name) == name)
        card.scripts.OnClick(card)

    def tab(self, dj, key):
        chip = dj.tabs[key]
        chip.scripts.OnClick(chip)

    def links(self, dj):
        return [dj.detail.pools.link[i] for i in range(1, int(dj.detail.used.link) + 1)]

    def texts(self, dj):
        return [str(dj.detail.pools.text[i].text) for i in range(1, int(dj.detail.used.text) + 1)]

    # ---- the home: cards with banners ----
    def test_the_home_is_a_grid_of_cards_lowest_level_first_with_the_banner_of_each(self):
        self.lua.execute(FAKE_JOURNAL)
        body, dj = self.page()
        self.assertEqual(self.names(dj), ["The Deadmines", "Wailing Caverns"])
        cards = [c for c in lst(dj.cards) if c.shown]
        self.assertEqual(len(cards), 2)
        self.assertEqual(str(cards[0].art.texture), "Interface\\AddOns\\ForeverDungeonJournal\\Media\\DeadminesHome", "the journal's own art, used by its path")
        self.assertEqual(str(cards[0].title.text), "The Deadmines")
        self.assertEqual(str(cards[0].level.text), "LV 10-20")
        self.assertEqual(str(cards[1].quests.text), "1 quests" if False else self.a.L("dungeonsQuestCount") % 1)
        self.assertEqual(str(dj.mode), "home")

    def test_searching_narrows_the_cards_by_name_or_place(self):
        self.lua.execute(FAKE_JOURNAL)
        body, dj = self.page()
        dj.box.SetText(dj.box, "barrens")
        dj.box.scripts.OnTextChanged(dj.box)
        self.assertEqual(self.names(dj), ["Wailing Caverns"])
        dj.box.SetText(dj.box, "zzz")
        dj.box.scripts.OnTextChanged(dj.box)
        self.assertEqual(self.names(dj), [])
        self.assertEqual(str(dj.count.text), self.a.L("dungeonsNone"))

    # ---- a dungeon: bosses ----
    def test_a_card_opens_the_dungeon_on_its_bosses_with_their_levels(self):
        self.lua.execute(FAKE_JOURNAL)
        body, dj = self.page()
        self.open(dj, "The Deadmines")
        self.assertEqual(str(dj.mode), "dungeon")
        self.assertEqual(str(dj.title.text), "The Deadmines")
        self.assertIn("Westfall", str(dj.subtitle.text))
        items = lst(dj["items"])
        self.assertEqual([str(i.title) for i in items], ["Rhahk'Zor", "Cookie"])
        self.assertEqual([str(i.badge) for i in items], ["LV 19", "LV 20"])
        self.assertTrue(dj.back.shown and dj.head.shown)

    def test_the_loot_of_a_boss_is_rows_with_icon_name_in_the_colour_of_its_quality_and_slot(self):
        self.lua.execute(FAKE_JOURNAL)
        body, dj = self.page()
        self.open(dj, "The Deadmines")
        links = self.links(dj)
        self.assertEqual([int(r.spec.itemId) for r in links], [872, 5187])
        self.assertEqual(str(links[0].title.text), "Rockslicer")
        self.assertEqual(str(links[0].sub.text), "Two-Hand, Axe")
        self.assertEqual(links[0].icon.texture, 130872, "the item's own icon")
        self.assertEqual(int(links[0].spec.quality), 3, "rare: its name is blue")
        texts = self.texts(dj)
        self.assertTrue(any("Rhahk'Zor" in t and "LV 19" in t for t in texts), "the boss and his level above the loot")
        self.lua.execute("TIP={}; GameTooltip={SetOwner=function() end, SetHyperlink=function(_, link) TIP[#TIP+1]=link end, Show=function() end, Hide=function() end, NumLines=function() return 1 end, AddLine=function() end, SetText=function() end}")
        links[1].scripts.OnEnter(links[1])
        self.assertEqual(str(self.lua.globals().TIP[1]), "item:5187", "the game's tooltip")

    def test_choosing_another_boss_shows_his_loot(self):
        self.lua.execute(FAKE_JOURNAL)
        body, dj = self.page()
        self.open(dj, "The Deadmines")
        row = dj.rows[2]
        row.scripts.OnClick(row)
        self.assertEqual([int(r.spec.itemId) for r in self.links(dj)], [5197, 5198])

    # ---- quests ----
    def test_the_quests_tab_lists_them_and_the_detail_has_objective_starts_turn_in_and_the_rewards_to_choose_from(self):
        self.lua.execute(FAKE_JOURNAL)
        body, dj = self.page()
        self.open(dj, "Wailing Caverns")
        self.tab(dj, "quests")
        items = lst(dj["items"])
        self.assertEqual([str(i.title) for i in items], ["Deviate Hides"])
        self.assertIn("13", str(items[0].sub), "available from level 13")
        texts = " | ".join(self.texts(dj))
        self.assertIn("Deviate Hides", texts)
        self.assertIn("Bring 20 Deviate Hides to Nalpak.", texts)
        self.assertIn("Nalpak, The Barrens", texts)
        self.assertIn(self.a.L("dungeonsChoose"), texts, "choose one reward")
        badges = [str(dj.detail.pools.badge[i].text.text) for i in range(1, int(dj.detail.used.badge) + 1)]
        self.assertIn("4,640 XP", badges, "XP is a compact reward badge, not a paragraph below the item list")
        ids = [int(r.spec.itemId) for r in self.links(dj) if r.spec.itemId]
        self.assertEqual(ids, [6480, 918])
        last = self.links(dj)[-1]
        self.assertIn("1486", str(last.sub.text), "a way into the database for the quest")

    def test_a_refresh_of_the_window_keeps_the_tab_the_choice_and_the_dungeon(self):
        # the window is drawn again several times a second: it must not throw the player back to the first tab (it did)
        self.lua.execute(FAKE_JOURNAL)
        body, dj = self.page()
        self.open(dj, "The Deadmines")
        row = dj.rows[2]
        row.scripts.OnClick(row)
        self.tab(dj, "quests")
        self.tab(dj, "bosses")
        row = dj.rows[2]
        row.scripts.OnClick(row)
        before = [int(r.spec.itemId) for r in self.links(dj)]
        for _ in range(5):
            self.m.RefreshDungeons(body)
        self.assertEqual(str(dj.mode), "dungeon")
        self.assertEqual(str(dj.tab), "bosses")
        self.assertEqual([int(r.spec.itemId) for r in self.links(dj)], before, "the second boss is still the one shown")
        self.open(dj, "The Deadmines") if False else None
        dj.back.scripts.OnClick(dj.back)
        self.open(dj, "Wailing Caverns")
        self.tab(dj, "quests")
        self.m.RefreshDungeons(body)
        self.assertEqual(str(dj.tab), "quests", "on the quests tab it stays on the quests")
        self.tab(dj, "map")
        self.m.RefreshDungeons(body)
        self.assertEqual(str(dj.tab), "map")

    # ---- the map ----
    def test_the_map_tab_draws_the_floor_and_a_numbered_mark_for_each_boss(self):
        self.lua.execute(FAKE_JOURNAL)
        body, dj = self.page()
        self.open(dj, "The Deadmines")
        self.tab(dj, "map")
        self.assertTrue(dj.mapArea.shown)
        self.assertEqual(str(dj.map.single.texture), "Interface\\AddOns\\ForeverDungeonJournal\\Media\\DeadminesMap")
        marks = [m for m in lst(dj.map.marks) if m.shown]
        self.assertEqual([str(m.bossName) for m in marks], ["Rhahk'Zor", "Cookie"])
        self.assertEqual([str(m.num.text) for m in marks], ["1", "2"])
        self.open(dj, "Wailing Caverns") if False else None

    def test_a_dungeon_without_a_map_says_so(self):
        self.lua.execute(FAKE_JOURNAL)
        body, dj = self.page()
        self.open(dj, "Wailing Caverns")
        self.tab(dj, "map")
        self.assertEqual(str(dj.map.note.text), self.a.L("dungeonsNoMap"))

    def test_a_boss_on_the_floor_map_opens_that_boss_and_his_loot(self):
        self.lua.execute(FAKE_JOURNAL)
        body, dj = self.page(); self.open(dj, "The Deadmines"); self.tab(dj, "map")
        mark = dj.map.marks[2]
        mark.scripts.OnClick(mark)
        self.assertEqual(dj.tab, "bosses")
        self.assertEqual(dj.chosen.boss.name, "Cookie")
        self.assertEqual([int(r.spec.itemId) for r in self.links(dj)], [5197, 5198])
        self.assertTrue(dj.detail.portrait.shown)

    # ---- back, the entrance, the arrow ----
    def test_the_way_back_and_the_entrance(self):
        self.lua.execute(FAKE_JOURNAL)
        body, dj = self.page()
        self.open(dj, "The Deadmines")
        self.assertTrue(dj.show.shown and dj.go.shown, "The Deadmines has an entrance on the map")
        self.assertEqual(str(dj.entrance.name), "The Deadmines")
        dj.back.scripts.OnClick(dj.back)
        self.assertEqual(str(dj.mode), "home")
        self.assertFalse(dj.show.shown)

    def test_opening_a_dungeon_by_name_asks_for_its_page(self):
        self.lua.execute(FAKE_JOURNAL)
        body, dj = self.page()
        self.assertTrue(self.m.OpenDungeonEntry("Wailing Caverns"))
        self.assertEqual(self.lua.globals().SHOWN, "dungeons")
        self.assertEqual(str(dj.selected.name), "Wailing Caverns")
        self.assertEqual(str(dj.mode), "dungeon")
        self.assertFalse(self.m.OpenDungeonEntry("No Such Place"))

    def test_a_dungeon_quest_that_questiedb_lacks_is_still_explained_in_a_record(self):
        self.lua.execute(FAKE_JOURNAL)
        rows = lst(self.m.DatabaseRows("quest", 1486))
        self.assertEqual(str(rows[0].title), "Deviate Hides")
        self.assertIn("Wailing Caverns", str(rows[0].sub))
        self.assertIn("Bring 20 Deviate Hides to Nalpak.", [str(r.title) for r in rows])
        unknown = lst(self.m.DatabaseRows("quest", 99999999))
        self.assertEqual(str(unknown[0].title), self.a.L("worldDbUnknown"))

    # ---- without the add-on ----
    def test_without_the_journal_the_known_instances_are_cards_and_the_page_says_what_is_missing(self):
        body, dj = self.page()
        names = self.names(dj)
        self.assertGreaterEqual(len(names), 40, "the 45 instances Evertally has the entrances of")
        self.assertIn("The Deadmines", names)
        self.open(dj, "The Deadmines")
        self.assertTrue(dj.noJournal.shown)
        self.assertEqual(str(dj.noJournal.text), self.a.L("dungeonsNoJournal"))
        self.assertFalse(dj.tabs["bosses"].shown, "no tabs without the data")


if __name__ == "__main__":
    unittest.main()

"""The Dungeon Journal page, built like the journal itself: a grid of cards with banners, and in a dungeon the tabs Guide / Bosses / Quests (/ Map
when a map is known). The data is Evertally's own (DungeonData.lua + QuestGuideData.lua); no other add-on is read."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_addon import MOCK_UI_LUA, ROOT, runtime
from test_navigation import FAKE_LIBS

MAP_DIR = ROOT / "addon" / "Evertally_Map"
# a small journal in the shape of DungeonData.lua and QuestGuideData.lua (the real ones are tested at the end)
FAKE_JOURNAL = """
local M, A = ...
local zones = {[1436] = "Westfall", [1413] = "The Barrens"}
C_Map.GetMapInfo = function(id) return {name = zones[id] or ("Map " .. id)} end
A.OpenDatabaseEntry = function(kind, id) OPENED = {kind, id} end
M.dungeonData = {
  ["Wailing Caverns"] = {name = "Wailing Caverns", raid = false, level = {10, 15, 24}, art = 131882,
    bosses = {{name = "Lord Cobrahn", npc = 3669, loot = {{6460, "Cobrahn's Grasp", "Waist, Leather", 3}}}}},
  ["The Deadmines"] = {name = "The Deadmines", raid = false, level = {10, 10, 20}, art = 131833,
    bosses = {{name = "Rhahk'Zor", npc = 644, loot = {{872, "Rockslicer", "Two-Hand, Axe", 3}, {5187, "Rhahk'Zor's Hammer", "Two-Hand, Mace", 3}}},
              {name = "Cookie", npc = 645, loot = {{5197, "Cookie's Tenderizer", "One-Hand, Mace", 3}, {5198, "Cookie's Stirring Rod", "", 3}}}}},
}
A.questGuideData = {quests = {
  [1486] = {id = 1486, title = "Deviate Hides", level = 17, minLevel = 13, faction = "Both", classMask = 0, dungeon = "Wailing Caverns",
    text = "Bring 20 Deviate Hides to Nalpak.", requiresAny = {1490},
    starts = {{kind = "npc", id = 5767, name = "Nalpak", spots = {{map = 1413, x = 0.46, y = 0.36}}}},
    ends = {{kind = "npc", id = 5767, name = "Nalpak", spots = {{map = 1413, x = 0.46, y = 0.36}}}}},
  [1490] = {id = 1490, title = "Earlier Errand", level = 12, minLevel = 10, faction = "Both"},
  [1487] = {id = 1487, title = "Mage Only", level = 18, minLevel = 14, faction = "Horde", classMask = 128, dungeon = "Wailing Caverns"},
}}
"""
# levels, a portrait, places on the floors (the second floor of the three has no boss of this dungeon: not shown)
FAKE_MAP = """
local M = ...
local dm = M.dungeonData["The Deadmines"]
dm.floors = 36
dm.bosses[1].level = {19, 19}; dm.bosses[1].display = 14403; dm.bosses[1].pos = {1, 0.5, 0.7}
dm.bosses[2].level = {20, 21}; dm.bosses[2].pos = {3, 0.3, 0.2}
local function tiles(base) local t = {} for i = 1, 12 do t[i] = base + i end return t end
M.dungeonFloors = {[36] = {{tiles = tiles(100), name = "The Mine"}, {tiles = tiles(200)}, {tiles = tiles(300), name = "Ironclad Cove"}}}
SetPortraitTextureFromCreatureDisplayID = function(texture, id) texture:SetTexture("portrait:" .. id) end
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

    def fake(self, with_map=False):
        self.lua.execute(FAKE_JOURNAL, self.m, self.a)
        if with_map:
            self.lua.execute(FAKE_MAP, self.m)

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
        self.fake()
        body, dj = self.page()
        self.assertEqual(self.names(dj), ["The Deadmines", "Wailing Caverns"])
        cards = [c for c in lst(dj.cards) if c.shown]
        self.assertEqual(len(cards), 2)
        self.assertEqual(cards[0].art.texture, 131833, "the loading screen of the instance, drawn by the game by its file ID")
        self.assertEqual(str(cards[0].title.text), "The Deadmines")
        self.assertEqual(str(cards[0].level.text), "LV 10-20")
        self.assertEqual(str(cards[1].quests.text), "1 quests" if False else self.a.L("dungeonsQuestCount") % 2)
        self.assertEqual(str(dj.mode), "home")

    def test_searching_narrows_the_cards_by_name_or_place(self):
        self.fake()
        body, dj = self.page()
        dj.box.SetText(dj.box, "barrens")
        dj.box.scripts.OnTextChanged(dj.box)
        self.assertEqual(self.names(dj), ["Wailing Caverns"])
        dj.box.SetText(dj.box, "zzz")
        dj.box.scripts.OnTextChanged(dj.box)
        self.assertEqual(self.names(dj), [])
        self.assertEqual(str(dj.count.text), self.a.L("dungeonsNone"))

    # ---- a dungeon: bosses ----
    def test_a_card_opens_the_dungeon_on_its_guide_and_its_bosses(self):
        self.fake()
        body, dj = self.page()
        self.open(dj, "The Deadmines")
        self.assertEqual(str(dj.mode), "dungeon")
        self.assertEqual(str(dj.title.text), "The Deadmines")
        self.assertIn("Westfall", str(dj.subtitle.text))
        self.assertEqual(str(dj.tab), "guide", "a dungeon opens on its guide")
        self.assertEqual([str(i.section) for i in lst(dj["items"])], ["overview", "tank", "healer", "dps", "classes"])
        self.tab(dj, "bosses")
        items = lst(dj["items"])
        self.assertEqual([str(i.title) for i in items], ["Rhahk'Zor", "Cookie"])
        self.assertEqual([str(i.badge) for i in items], ["", ""], "Evertally's data has no boss levels: no made-up badge")
        self.assertTrue(dj.back.shown and dj.head.shown)

    def test_the_loot_of_a_boss_is_rows_with_icon_name_in_the_colour_of_its_quality_and_slot(self):
        self.fake()
        body, dj = self.page()
        self.open(dj, "The Deadmines")
        self.tab(dj, "bosses")
        links = [r for r in self.links(dj) if r.spec.itemId]
        self.assertEqual([int(r.spec.itemId) for r in links], [872, 5187])
        npc = [r for r in self.links(dj) if not r.spec.itemId][-1]
        self.assertEqual(str(npc.sub.text), "#644", "a way into the database for the boss")
        npc.scripts.OnClick(npc)
        self.assertEqual(list(self.lua.globals().OPENED.values()), ["npc", 644])
        self.assertEqual(str(links[0].title.text), "Rockslicer")
        self.assertEqual(str(links[0].sub.text), "Two-Hand, Axe")
        self.assertEqual(links[0].icon.texture, 130872, "the item's own icon")
        self.assertEqual(int(links[0].spec.quality), 3, "rare: its name is blue")
        texts = self.texts(dj)
        self.assertTrue(any("Rhahk'Zor" in t for t in texts), "the boss above the loot")
        self.lua.execute("TIP={}; GameTooltip={SetOwner=function() end, SetHyperlink=function(_, link) TIP[#TIP+1]=link end, Show=function() end, Hide=function() end, NumLines=function() return 1 end, AddLine=function() end, SetText=function() end}")
        links[1].scripts.OnEnter(links[1])
        self.assertEqual(str(self.lua.globals().TIP[1]), "item:5187", "the game's tooltip")

    def test_choosing_another_boss_shows_his_loot(self):
        self.fake()
        body, dj = self.page()
        self.open(dj, "The Deadmines")
        self.tab(dj, "bosses")
        row = dj.rows[2]
        row.scripts.OnClick(row)
        self.assertEqual([int(r.spec.itemId) for r in self.links(dj) if r.spec.itemId], [5197, 5198])

    # ---- the guide ----
    def test_the_guide_has_an_overview_role_advice_and_class_tips_with_the_players_class_first(self):
        self.fake()
        self.lua.execute("UnitClass=function() return 'Priest','PRIEST',5 end")
        body, dj = self.page()
        self.open(dj, "The Deadmines")
        texts = " ".join(self.texts(dj))
        self.assertIn("Moonbrook", texts, "the written intro of a Classic dungeon")
        self.assertIn(self.a.L("dgClassicNote"), texts)
        self.assertIn("dominik.mracek@afstudio.dev", texts)
        for section in ("tank", "healer", "dps"):
            self.m.DungeonGuide.Render(dj.detail, dj.selected, section)
            self.assertGreater(len(self.texts(dj)), 4, section)
        self.m.DungeonGuide.Render(dj.detail, dj.selected, "classes")
        texts = self.texts(dj)
        self.assertIn(self.a.L("dgYourClass"), texts[1], "the player's class comes first")

    def test_a_boss_has_its_tactic_before_the_loot_and_a_new_dungeons_boss_asks_for_one(self):
        self.fake()
        body, dj = self.page()
        self.open(dj, "The Deadmines")
        self.tab(dj, "bosses")
        texts = self.texts(dj)
        tactic = texts.index(self.a.L("dgTactic"))
        self.assertLess(tactic, texts.index(self.a.L("dungeonsLoot")))
        self.assertIn("Rhahk'Zor Slam", texts[tactic + 1])
        guide = self.m.DungeonGuide
        entry = self.lua.eval('{name = "Blackmaw Hold", data = {}}')
        boss = self.lua.eval('{name = "Withermaw"}')
        dj.detail.Reset(); guide.RenderBoss(dj.detail, entry, boss)
        joined = " ".join(self.texts(dj))
        self.assertIn(self.a.L("dgBossUnknown"), joined)
        self.assertIn("dominik.mracek@afstudio.dev", joined)
        # a published fight of a new dungeon: its tactic, and the overview says where the tactics come from
        entry = self.lua.eval('{name = "Krol\'dok Stronghold", data = {}}')
        dj.detail.Reset(); guide.RenderBoss(dj.detail, entry, self.lua.eval('{name = "Overlord Mugg"}'))
        self.assertIn("Crushing Slam", " ".join(self.texts(dj)))
        guide.Render(dj.detail, entry, "overview")
        self.assertIn(self.a.L("dgPublished"), self.texts(dj))

    def test_the_new_dungeons_have_a_tactic_for_every_boss_the_guides_describe(self):
        guides = self.m.dungeonGuides
        data = self.m.dungeonData
        missing = {}
        for name in ("Hall of Thanes", "Ruins of Lordaeron", "Excavation Site: Wetlands", "City of Dalaran", "The Drowned City",
                     "Krol'dok Stronghold", "Alcaz Prison", "Shaper's Terrace"):
            self.assertTrue(guides[name].published, name)
            bosses = [str(b.name) for b in lst(data[name].bosses) if not str(b.name).startswith("Trash")]
            lacking = [b for b in bosses if guides[name].bosses[b] is None]
            if lacking:
                missing[name] = lacking
        # the published guides say nothing about him
        self.assertEqual(missing, {"Ruins of Lordaeron": ["Lordaeron Captain"]})

    def test_every_guide_names_real_dungeons_and_bosses(self):
        guides = self.m.dungeonGuides
        self.assertEqual(len(list(guides.keys())), 35, "9 of Forever's own and 26 from Classic")
        for name, guide in guides.items():
            self.assertTrue(guide.intro.en and guide.intro.cs, name)
            for boss, tactic in (guide.bosses or {}).items():
                self.assertTrue(tactic.en and tactic.cs, (name, boss))

    # ---- quests ----
    def test_the_quests_tab_lists_them_and_the_detail_has_objective_starts_turn_in_and_the_rewards_to_choose_from(self):
        self.fake()
        body, dj = self.page()
        self.open(dj, "Wailing Caverns")
        self.tab(dj, "quests")
        items = lst(dj["items"])
        self.assertEqual([str(i.title) for i in items], ["Deviate Hides", "Mage Only"], "the quests of this dungeon, lowest level first")
        self.assertIn("13", str(items[0].sub), "available from level 13")
        self.assertIn("Horde", str(items[1].sub), "a quest of one faction says so")
        texts = " | ".join(self.texts(dj))
        self.assertIn("Deviate Hides", texts)
        self.assertIn("Bring 20 Deviate Hides to Nalpak.", texts)
        self.assertIn("Nalpak, The Barrens", texts, "who gives it, with the zone of the place")
        self.assertIn(self.a.L("dungeonsChoose"), texts, "choose one reward (from the quest facts, the journal lists none)")
        badges = [str(dj.detail.pools.badge[i].text.text) for i in range(1, int(dj.detail.used.badge) + 1)]
        self.assertIn("1600 XP*", badges, "XP is a compact reward badge, not a paragraph below the item list")
        ids = [int(r.spec.itemId) for r in self.links(dj) if r.spec.itemId]
        self.assertEqual(ids, [6480, 918])
        model = self.m.JournalQuestModel(dj.chosen.quest)
        self.assertEqual([str(model.chain[i].name) for i in range(1, len(model.chain) + 1)], ["Earlier Errand"], "what must come first")
        self.assertEqual(float(model.starts[1].spot.x), 0.46, "the giver has a place on the map")
        self.assertEqual(str(self.m.JournalQuestModel(items[1].quest).classOnly), "Mage")
        last = self.links(dj)[-1]
        self.assertIn("1486", str(last.sub.text), "a way into the database for the quest")

    def test_a_refresh_of_the_window_keeps_the_tab_the_choice_and_the_dungeon(self):
        # the window is drawn again several times a second: it must not throw the player back to the first tab (it did)
        self.fake()
        body, dj = self.page()
        self.open(dj, "The Deadmines")
        row = dj.rows[2]
        row.scripts.OnClick(row)
        self.tab(dj, "quests")
        self.tab(dj, "bosses")
        row = dj.rows[2]
        row.scripts.OnClick(row)
        before = [int(r.spec.itemId) for r in self.links(dj) if r.spec.itemId]
        for _ in range(5):
            self.m.RefreshDungeons(body)
        self.assertEqual(str(dj.mode), "dungeon")
        self.assertEqual(str(dj.tab), "bosses")
        self.assertEqual([int(r.spec.itemId) for r in self.links(dj) if r.spec.itemId], before, "the second boss is still the one shown")
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
        self.fake(with_map=True)
        body, dj = self.page()
        self.open(dj, "The Deadmines")
        self.tab(dj, "map")
        self.assertTrue(dj.mapArea.shown)
        self.assertTrue(dj.tabs["map"].shown, "a dungeon with a map has the tab")
        self.assertEqual([dj.map.tiles[i].texture for i in (1, 12)], [101, 112], "the floor's tiles, drawn by file ID")
        chips = [c for c in lst(dj.map.floorChips) if c.shown]
        self.assertEqual(len(chips), 2, "a button for each floor a boss stands on")
        marks = [m for m in lst(dj.map.marks) if m.shown]
        self.assertEqual([str(m.bossName) for m in marks], ["Rhahk'Zor"])
        self.assertEqual([str(m.num.text) for m in marks], ["1"])
        chips[1].scripts.OnClick(chips[1])
        self.assertEqual(dj.map.tiles[1].texture, 301, "the other floor")
        marks = [m for m in lst(dj.map.marks) if m.shown]
        self.assertEqual([(str(m.bossName), str(m.num.text)) for m in marks], [("Cookie", "2")], "numbered as in the Bosses list")
        chips[0].scripts.OnClick(chips[0])
        mark = [m for m in lst(dj.map.marks) if m.shown][0]
        self.assertEqual(str(mark.bg.texture), "portrait:14403", "a mark is the boss's portrait, not a dot")

    def test_the_guides_codex_adds_the_quests_our_catalogue_lacks_once_each(self):
        self.fake()
        self.lua.execute("""
          EvertallyGuide = {Dungeons = {
            Load = function() return true end,
            List = function() return {{key = "wailing-caverns", name = "Wailing Caverns", minLevel = 15, maxLevel = 25}} end,
            Quests = function(key) return {
              {id = 1486, title = "Deviate Hides (again)", level = 17},
              {id = 96001, title = "Forever's Own Errand", level = 18, minLevel = 15, faction = "H", inside = true, chain = {96000},
               start = {kind = "npc", name = "Ebru", map = 1413, x = 46.2, y = 36.1},
               finish = {kind = "npc", name = "Ebru", map = 1413, x = 46.2, y = 36.1},
               rewards = {items = {{id = 6480, name = "Slick Deviate Leggings", quality = 2, choice = true}, {id = 918, name = "Deviate Hide Pack", quality = 1, choice = true}}, xp = 2450, money = 900}}} end,
            Quest = function(key, id) if id == 96000 then return {id = 96000, title = "The Step Before"} end end,
            ObjectiveText = function(q) return "Bring 5 Glowing Shards." end}}
        """)
        body, dj = self.page()
        self.open(dj, "Wailing Caverns")
        self.tab(dj, "quests")
        titles = [str(i.title) for i in lst(dj["items"])]
        self.assertEqual(titles, ["Deviate Hides", "Forever's Own Errand", "Mage Only"], "added once, in level order; the one we have is not repeated")
        added = lst(dj["items"])[1].quest
        self.assertEqual(str(added.faction), "Horde")
        model = self.m.JournalQuestModel(added)
        self.assertEqual([int(r.id) for r in lst(model.choiceRewards)], [6480, 918])
        self.assertEqual(int(model.xp), 2450)
        self.assertEqual(str(model.objective), "Bring 5 Glowing Shards.")
        self.assertEqual(round(float(model.starts[1].spot.x), 3), 0.462, "its place on the map, 0..1")
        self.assertEqual([str(c.name) for c in lst(model.chain)], ["The Step Before"])
        self.assertEqual(str(dj.selected.level), "15-24", "AtlasLoot's level stays; the Codex fills only a missing one")

    def test_bosses_have_their_levels_and_a_portrait_of_their_model(self):
        self.fake(with_map=True)
        body, dj = self.page()
        self.open(dj, "The Deadmines")
        self.tab(dj, "bosses")
        items = lst(dj["items"])
        self.assertEqual([str(i.badge) for i in items], ["LV 19", "LV 20-21"])
        self.assertEqual(str(dj.rows[1].icon.texture), "portrait:14403", "the game draws the boss's model")
        self.assertIn("Skull", str(dj.rows[2].icon.texture), "no model known: the skull")
        self.assertEqual(str(dj.detail.portrait.icon.texture), "portrait:14403")

    def test_a_boss_without_a_level_learns_it_when_the_player_sees_him(self):
        self.fake()
        self.lua.execute('UnitGUID=function() return "Creature-0-1-2-3-3669-0000ABCD" end; UnitLevel=function() return 20 end')
        body, dj = self.page()
        self.assertEqual(self.m.LearnBossLevel("target"), 20)
        self.lua.execute('UnitGUID=function() return "Creature-0-1-2-3-9999-0000ABCD" end')
        self.assertIsNone(self.m.LearnBossLevel("target"), "not a boss of the journal")
        self.open(dj, "Wailing Caverns")
        self.tab(dj, "bosses")
        self.assertEqual(str(lst(dj["items"])[0].badge), "LV 20")
        self.assertIn(self.a.L("dungeonsLearned"), self.texts(dj), "says where the level comes from")

    def test_a_dungeon_without_a_map_has_no_map_tab_and_the_map_says_so(self):
        self.fake()
        body, dj = self.page()
        self.open(dj, "Wailing Caverns")
        self.assertFalse(dj.tabs["map"].shown, "no tab that only says there is nothing")
        self.assertTrue(dj.tabs["bosses"].shown and dj.tabs["quests"].shown)
        self.tab(dj, "map")
        self.assertEqual(str(dj.map.note.text), self.a.L("dungeonsNoMap"))

    def test_a_boss_on_the_floor_map_opens_that_boss_and_his_loot(self):
        self.fake(with_map=True)
        body, dj = self.page(); self.open(dj, "The Deadmines"); self.tab(dj, "map")
        chip = dj.map.floorChips[2]; chip.scripts.OnClick(chip)
        mark = dj.map.marks[1]
        mark.scripts.OnClick(mark)
        self.assertEqual(dj.tab, "bosses")
        self.assertEqual(dj.chosen.boss.name, "Cookie")
        self.assertEqual([int(r.spec.itemId) for r in self.links(dj) if r.spec.itemId], [5197, 5198])
        self.assertTrue(dj.detail.portrait.shown)

    # ---- back, the entrance, the arrow ----
    def test_the_way_back_and_the_entrance(self):
        self.fake()
        body, dj = self.page()
        self.open(dj, "The Deadmines")
        self.assertTrue(dj.show.shown and dj.go.shown, "The Deadmines has an entrance on the map")
        self.assertEqual(str(dj.entrance.name), "The Deadmines")
        dj.back.scripts.OnClick(dj.back)
        self.assertEqual(str(dj.mode), "home")
        self.assertFalse(dj.show.shown)

    def test_opening_a_dungeon_by_name_asks_for_its_page(self):
        self.fake()
        body, dj = self.page()
        self.assertTrue(self.m.OpenDungeonEntry("Wailing Caverns"))
        self.assertEqual(self.lua.globals().SHOWN, "dungeons")
        self.assertEqual(str(dj.selected.name), "Wailing Caverns")
        self.assertEqual(str(dj.mode), "dungeon")
        self.assertFalse(self.m.OpenDungeonEntry("No Such Place"))

    def test_the_guides_show_dungeon_opens_the_journal_at_that_dungeon(self):
        # SHOW_DUNGEON(key) of Evertally Guide (map pins, the dungeon toast, Lookup) has no hub section: it lands here
        self.fake()
        body, dj = self.page()
        self.lua.execute("""EvertallyGuide={Dungeons={Load=function() return true end,
            Find=function(text) if text=="Wailing Caverns" then return "WC" end end, Open=function() end}}""")
        self.assertTrue(self.m.OpenGuideDungeon("WC"))
        self.assertEqual(self.lua.globals().SHOWN, "dungeons")
        self.assertEqual(str(dj.selected.name), "Wailing Caverns")
        self.assertEqual(str(dj.mode), "dungeon")
        self.assertTrue(self.m.OpenGuideDungeon("NOPE"), "an unknown key: the journal's home")
        self.assertEqual(str(dj.mode), "home")
        self.assertTrue(self.m.OpenGuideDungeon(None))
        self.assertEqual(str(dj.mode), "home")

    def test_a_dungeon_quest_that_questiedb_lacks_is_still_explained_in_a_record(self):
        self.fake()
        rows = lst(self.m.DatabaseRows("quest", 1486))
        self.assertEqual(str(rows[0].title), "Deviate Hides")
        self.assertIn("Wailing Caverns", str(rows[0].sub))
        self.assertIn("Bring 20 Deviate Hides to Nalpak.", [str(r.title) for r in rows])
        unknown = lst(self.m.DatabaseRows("quest", 99999999))
        self.assertEqual(str(unknown[0].title), self.a.L("worldDbUnknown"))

    # ---- without the data file ----
    def test_without_the_journal_the_known_instances_are_cards_and_the_page_says_what_is_missing(self):
        self.m.dungeonData = None
        body, dj = self.page()
        names = self.names(dj)
        self.assertGreaterEqual(len(names), 40, "the 45 instances Evertally has the entrances of")
        self.assertIn("The Deadmines", names)
        self.open(dj, "The Deadmines")
        self.assertTrue(dj.noJournal.shown)
        self.assertEqual(str(dj.noJournal.text), self.a.L("dungeonsNoJournal"))
        self.assertFalse(dj.tabs["bosses"].shown, "no tabs without the data")

    # ---- the real data ----
    def test_the_real_journal_has_every_dungeon_with_bosses_loot_art_and_quests_and_reads_no_other_add_on(self):
        self.lua.execute("ForeverDungeonJournal_NS = setmetatable({}, {__index = function() error('read the other add-on') end})")
        body, dj = self.page()
        entries = {str(e.name): e for e in lst(dj.results)}
        self.assertGreaterEqual(len(entries), 40, "44 dungeons and raids in DungeonData.lua")
        for name in ("The Deadmines", "Wailing Caverns", "Stratholme: Living", "Stratholme: Undead", "Molten Core", "Hall of Thanes"):
            self.assertIn(name, entries)
            self.assertEqual(str(entries[name].source), "journal", name)
            self.assertGreater(len(entries[name].data.bosses), 0, name)
        deadmines = entries["The Deadmines"]
        self.assertIsInstance(deadmines.banner, int, "a loading screen's file ID")
        self.assertGreater(deadmines.quests, 0, "quests from QuestGuideData.lua")
        first = deadmines.data.bosses[1]
        self.assertEqual(str(first.name), "Rhahk'Zor")
        self.assertEqual(int(first.loot[1][1]), 872)
        # every dungeon of a quest in the catalogue is a page of the journal (the names agree)
        quests = self.a.questGuideData.quests
        dungeons = {str(q.dungeon) for q in quests.values() if q.dungeon}
        self.assertEqual(dungeons - set(entries), set(), "a quest's dungeon with no page")
        # every page with a written guide is one of the journal's
        self.assertEqual({str(k) for k in self.m.dungeonGuides.keys()} - set(entries), set(), "a guide with no page")

    def test_a_dungeon_opens_in_the_guides_dungeons_for_attunements_and_quest_runs(self):
        # Evertally's journal keeps bosses, loot, floor maps and tactics; Evertally Guide's page has attunements and
        # the quest pick-up and hand-in guides: one button between them, found by name (a wing by its dungeon's name).
        self.assertIsNone(self.m.GuideDungeonKey(self.lua.eval("{name='Wailing Caverns'}")), "no guide: no button")
        self.lua.execute("""OPENED={}
          EvertallyGuide={Dungeons={Load=function() return true end,
            Find=function(text) if text=="Wailing Caverns" then return "WC" elseif text=="Scarlet Monastery" then return "SM" end end,
            Open=function(key) OPENED[#OPENED+1]=key; return true end}}""")
        self.assertEqual(self.m.GuideDungeonKey(self.lua.eval("{name='Wailing Caverns'}")), "WC")
        self.assertEqual(self.m.GuideDungeonKey(self.lua.eval("{name='Scarlet Monastery: Library'}")), "SM")
        self.assertIsNone(self.m.GuideDungeonKey(self.lua.eval("{name='Hall of Thanes'}")))

    FAKE_GUIDE = """CALLED={}
      local function q(id, title, minLevel) return {id=id, title=title, level=minLevel+2, minLevel=minLevel} end
      local quests = {q(1, "Done one", 10), q(2, "In the log", 10), q(3, "Finished", 10), q(4, "Open", 10), q(5, "Later", 40), q(6, "Warlocks", 10)}
      local att = {id=7, name="The Key", kind="key", need="each", item={id=5396, name="Key to Searing Gorge", quality=1},
        steps={{kind="quest", id=11, title="First step", start={map=1426, x=50, y=50, name="Giver"}}, {kind="drop", item={id=9, name="Shard"}, npc={name="Ogre"}}}}
      EvertallyGuide={L={},
        Compat={IsQuestCompleted=function(id) return id==1 end, IsOnQuest=function(id) return id==2 or id==3 end,
          IsQuestReadyForTurnIn=function(id) return id==3 end},
        Lookup={Guide={}},
        Dungeons={Load=function() return true end,
          Find=function(text) if text=="Wailing Caverns" then return "WC" end end, Open=function() end,
          Get=function(key) if key=="WC" then return {key="WC", name="Wailing Caverns", minLevel=15, maxLevel=25, entrance={map=1413, x=46, y=36}} end end,
          BestAt=function() return 19 end,
          QuestXP=function() return {levels=2.4, ready={levels=1.1}} end,
          Quests=function() return quests end,
          QuestFor=function(q) if q.id==6 then return "Warlock", "class" end end,
          PickupPlan=function() return {take={4}, carried={}, later=1} end,
          WaitingLines=function() return {"Later: level 40"} end,
          HandinPlan=function() return {hand={3}, errands={}, unfinished={2}, inside={}, unplaced={}} end,
          PickUp=function(key) CALLED[#CALLED+1]="pickup:"..key end,
          HandIn=function(key) CALLED[#CALLED+1]="handin:"..key end,
          GuideTo=function(key) CALLED[#CALLED+1]="go:"..key end,
          GuideToPoint=function(p, label) CALLED[#CALLED+1]="point:"..label end,
          Attunements=function() return {att} end,
          AttunementState=function(a) return {done=false, owned=false, left=2, steps={{step=a.steps[1], state="open"}, {step=a.steps[2], state="locked"}}} end,
          Attune=function(key, id) CALLED[#CALLED+1]="attune:"..key..":"..id end}}"""

    def test_the_for_you_tab_has_the_quest_state_runs_and_attunements_of_the_guide(self):
        self.fake()
        self.lua.execute(self.FAKE_GUIDE)
        self.lua.execute("UnitFactionGroup=function() return 'Horde' end; UnitLevel=function() return 18 end")
        body, dj = self.page()
        self.open(dj, "Wailing Caverns")
        self.assertTrue(dj.tabs["prep"].shown, "the guide knows Wailing Caverns")
        self.assertEqual(str(dj.tabs["prep"].text.text), self.a.L("prepTab"))
        self.tab(dj, "prep")
        self.assertEqual([str(i.title) for i in lst(dj["items"])], [self.a.L("prepOverview"), "The Key"])
        texts = self.texts(dj)
        self.assertIn(self.a.L("prepXP") % 2.4, texts)
        counts = "  ·  ".join(self.a.L("prepCount_" + key) % 1 for key in ("ready", "log", "open", "low", "done", "other"))
        self.assertIn(counts, texts, "every state counted, on one line")
        links = {str(r.spec.title): r for r in self.links(dj)}
        for title, called in ((self.a.L("prepPickup") % 1, "pickup:WC"), (self.a.L("prepHandin") % 1, "handin:WC")):
            links[title].scripts.OnClick(links[title])
            self.assertEqual(self.lua.globals().CALLED[len(self.lua.globals().CALLED)], called)
        # an attunement: its item, the guide through it, each step with its state; a step with a place sets the arrow
        row = next(r for r in lst(dj.rows) if r.item and str(r.item.title) == "The Key")
        row.scripts.OnClick(row)
        links = {str(r.spec.title): r for r in self.links(dj)}
        self.assertIn("Key to Searing Gorge", links)
        self.assertEqual(str(links["Key to Searing Gorge"].spec.sub), self.a.L("prepHaveNot"))
        guide = links[self.a.L("prepAttGuide")]
        guide.scripts.OnClick(guide)
        self.assertEqual(self.lua.globals().CALLED[len(self.lua.globals().CALLED)], "attune:WC:7")
        self.assertIn(self.a.L("prepState_open"), str(links["First step"].spec.sub))
        links["First step"].scripts.OnClick(links["First step"])
        self.assertEqual(self.lua.globals().CALLED[len(self.lua.globals().CALLED)], "point:Giver")
        self.assertEqual(str(links[self.a.L("prepFrom") % ("Shard", "Ogre")].spec.sub), self.a.L("prepState_locked"))
        self.assertIsNone(links[self.a.L("prepFrom") % ("Shard", "Ogre")].spec.onClick, "no place: no arrow")

    def test_the_quests_tab_says_which_quests_are_done_or_in_the_log(self):
        self.fake()
        self.lua.execute("EvertallyGuide={Compat={IsQuestCompleted=function(id) return id==1486 end, IsOnQuest=function() return false end}}")
        body, dj = self.page()
        self.open(dj, "Wailing Caverns")
        self.tab(dj, "quests")
        badges = {str(i.title): (str(i.badge) if i.badge else None) for i in lst(dj["items"])}
        self.assertEqual(badges["Deviate Hides"], self.a.L("prepBadge_done"))

    def test_without_the_guide_there_is_no_for_you_tab(self):
        self.fake()
        body, dj = self.page()
        self.open(dj, "Wailing Caverns")
        self.assertFalse(dj.tabs["prep"].shown)
        self.assertTrue(dj.tabs["bosses"].shown)
        for lang in ("en", "cs"):
            for key in ("prepTab", "prepOverview", "prepPickup", "prepHandin", "prepAttGuide", "prepUnknown"):
                self.assertTrue(self.a.locale[lang][key], (lang, key))
    def test_the_database_hands_its_search_to_the_guides_lookup(self):
        # Lookup (Evertally Guide) has its own Codex and needs no QuestieDB; the Database keeps browsing and the card.
        self.assertFalse(self.m.OpenGuideLookup("Linen Cloth"), "no guide: no Lookup")
        self.lua.execute("FIRED={}; EvertallyGuide={Lookup={}, Fire=function(msg, q) FIRED[#FIRED+1]={msg, q} end}")
        self.assertTrue(self.m.OpenGuideLookup("  Linen Cloth "))
        self.assertTrue(self.m.OpenGuideLookup(""))
        fired = self.lua.globals().FIRED
        self.assertEqual((fired[1][1], fired[1][2]), ("SHOW_LOOKUP", "Linen Cloth"))
        self.assertIsNone(fired[2][2], "an empty search opens Lookup as it is")
        for lang in ("en", "cs"):
            self.assertTrue(self.a.locale[lang]["worldDbLookup"] and self.a.locale[lang]["worldDbLookupHint"])

if __name__ == "__main__":
    unittest.main()

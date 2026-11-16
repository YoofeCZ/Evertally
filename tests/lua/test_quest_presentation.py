"""Shared parchment reader: factual reward groups, readable cards and repeat-refresh state. No game or user files."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_dungeons as fixture
import test_navigation as navigation


class QuestPresentationTests(unittest.TestCase):
    def setUp(self):
        self.f = fixture.DungeonTests("test_searching_narrows_the_cards_by_name_or_place")
        self.f.setUp()
        self.lua, self.a, self.m = self.f.lua, self.f.a, self.f.m

    def reader(self, width=420):
        parent = self.lua.eval("CreateFrame")("Frame", None, None)
        view = self.m.GuideDetail(self.a.UIKit(), parent)
        view.SetWidth(width)
        return view

    def strings(self, view):
        return [str(view.pools.text[i].text) for i in range(1, int(view.used.text) + 1)]

    def test_world_and_dungeon_quests_use_the_same_parchment_reader(self):
        self.f.fake()
        body, dj = self.f.page()
        self.f.open(dj, "Wailing Caverns"); self.f.tab(dj, "quests")
        self.assertEqual(dj.detail.theme, "quest")
        self.assertTrue(dj.detail.surface.shown)
        self.assertEqual(dj.detail.model.title, "Deviate Hides")
        model = self.m.DatabaseQuestModel(None, 1486)
        self.assertEqual(model.title, dj.detail.model.title)
        self.assertEqual(model.objective, dj.detail.model.objective)
        view = self.reader(); self.assertTrue(self.m.RenderQuestCard(view, model))
        self.assertEqual(view.theme, dj.detail.theme)

    def test_uncategorised_database_rewards_are_not_claimed_to_be_a_choice(self):
        self.lua.execute(navigation.MapTests.FAKE_QUESTIE)
        self.m.questDetails[200] = self.lua.table(rewards=self.lua.table_from([self.lua.table_from([6480, 1])]))
        model = self.m.DatabaseQuestModel(self.m.Db.Open(), 200)
        self.assertEqual(len(model.rewards), 1)
        self.assertEqual(len(model.choiceRewards), 0)
        self.assertEqual(len(model.guaranteedRewards), 0)
        view = self.reader(); self.m.RenderQuestCard(view, model)
        self.assertIn(self.a.L("questCardRewards"), self.strings(view))
        self.assertNotIn(self.a.L("questCardChoose"), self.strings(view))

    def test_choice_and_additional_guaranteed_rewards_are_separate(self):
        q = self.lua.eval('''{id=9001,name="An Ancient Grudge",requires=10,faction="Both",objective="Put the spirit to rest.",
          pickup="Ghostly Attendant, Hall of Thanes",turnin="Ghostly Attendant, inside the dungeon",rewardChoice=true,
          rewardItems={{15421,"Shroud of the Exile",3},{15422,"Dark Leather Pants",2}},additionalRewardItems={{6948,"Hearthstone",1}},xp=2300}''')
        model = self.m.JournalQuestModel(q)
        self.assertEqual(len(model.choiceRewards), 2); self.assertEqual(len(model.guaranteedRewards), 1)
        view = self.reader(); self.m.RenderQuestCard(view, model)
        texts = self.strings(view)
        self.assertIn("Put the spirit to rest.", texts)
        self.assertIn(self.a.L("questCardChoose"), texts); self.assertIn(self.a.L("questCardAlso"), texts)
        self.assertEqual([view.pools.link[i].spec.itemId for i in range(1, int(view.used.link) + 1)], [15421, 15422, 6948])
        self.assertTrue(view.factions[1].shown); self.assertTrue(view.factions[2].shown)

    def test_stale_text_xp_is_not_shown_when_an_explicit_base_reward_exists(self):
        model = self.m.JournalQuestModel(self.lua.eval('{id=9002,name="Known quest",liveXPFallback=1050,rewards="3,570 XP"}'))
        self.assertEqual(model.xpBase, 1050)
        self.assertIsNone(model.xp)
        self.assertEqual(len(model.extras), 0)
        view = self.reader(); self.m.RenderQuestCard(view, model)
        self.assertEqual(view.pools.badge[1].text.text, "1050 XP*")
        self.assertTrue(any("Base XP" in text for text in self.strings(view)))

    def test_cached_client_xp_takes_precedence_and_uncached_zero_does_not_hide_base(self):
        self.lua.execute('GetQuestLogRewardXP=function(id) return id==9002 and 2300 or 0 end')
        known = self.m.JournalQuestModel(self.lua.eval('{id=9002,name="Known quest",liveXPFallback=1050,rewards="3,570 XP"}'))
        self.assertEqual(known.xp, 2300)
        view = self.reader(); self.m.RenderQuestCard(view, known)
        self.assertEqual(view.pools.badge[1].text.text, "2300 XP")
        unknown = self.m.JournalQuestModel(self.lua.eval('{id=9003,name="Unknown quest",liveXPFallback=1050}'))
        self.assertIsNone(unknown.xp); self.assertEqual(unknown.xpBase, 1050)

    def test_reward_cards_use_two_columns_and_fall_back_to_one_when_narrow(self):
        model = self.m.JournalQuestModel(self.lua.eval('{id=9003,name="Two rewards",rewardChoice=true,rewardItems={{1,"First",2},{2,"Second",3}}}'))
        view = self.reader(420); self.m.RenderQuestCard(view, model)
        self.assertEqual(view.pools.link[1].GetWidth(view.pools.link[1]), 205)
        view.SetWidth(240); self.m.RenderQuestCard(view, model)
        self.assertEqual(view.pools.link[1].GetWidth(view.pools.link[1]), 240)
        self.assertEqual(view.pools.link[2].GetWidth(view.pools.link[2]), 240)

    def test_repeat_refresh_preserves_scroll_but_a_different_quest_starts_at_top(self):
        view = self.reader()
        self.lua.globals().SCROLL_VALUE = 0
        view.scroll.GetVerticalScroll = self.lua.eval("function() return SCROLL_VALUE end")
        view.scroll.SetVerticalScroll = self.lua.eval("function(_, value) SCROLL_VALUE=value end")
        view.scroll.GetHeight = self.lua.eval("function() return 60 end")
        model = self.m.JournalQuestModel(self.lua.eval('{id=9004,name="Long quest",objective=string.rep("A long objective. ",60)}'))
        self.m.RenderQuestCard(view, model)
        self.lua.globals().SCROLL_VALUE = 45
        self.m.RenderQuestCard(view, model)
        self.assertEqual(self.lua.globals().SCROLL_VALUE, 45)
        model.id = 9005; self.m.RenderQuestCard(view, model)
        self.assertEqual(self.lua.globals().SCROLL_VALUE, 0)

    def test_switching_back_to_a_boss_keeps_the_book_but_replaces_quest_rewards_with_boss_loot(self):
        self.f.fake()
        body, dj = self.f.page(); self.f.open(dj, "Wailing Caverns")
        self.f.tab(dj, "quests"); self.f.tab(dj, "bosses")
        self.assertEqual(dj.detail.theme, "quest"); self.assertTrue(dj.detail.surface.shown)
        self.assertIsNone(dj.detail.model, "the former quest is no longer the reader's model")
        self.assertEqual(dj.detail.pools.link[1].spec.itemId, 6460)
        self.assertFalse(dj.detail.pools.link[1].title.shown is False)


if __name__ == "__main__":
    unittest.main()

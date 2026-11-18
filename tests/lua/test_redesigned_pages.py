"""Behaviour of the character book, journal reader, dungeon record board and contact ledger. No running game."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_addon import runtime, MOCK_UI_LUA


class RedesignedPagesTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = runtime()
        self.lua.execute("date=os.date")
        self.lua.execute(MOCK_UI_LUA)

    def test_journal_selection_is_inline_and_survives_a_refresh(self):
        self.a.Record("quest.accepted", self.lua.table_from({"questId": 11, "title": "First quest"}))
        self.a.Record("quest.accepted", self.lua.table_from({"questId": 12, "title": "Second quest"}))
        self.a.OpenUI(); self.a.ShowView("journal")
        page = self.a.journalPage
        items = page.list["items"]
        event_rows = [items[i] for i in range(1, len(items)+1) if items[i].event]
        chosen = event_rows[-1]
        chosen.onClick()
        self.assertEqual(page.selectedEvent.payload.questId, 11)
        self.assertEqual(page.readerTitle.text, "First quest")
        self.assertIsNone(self.lua.globals().EvertallyDetailFrame, "selecting a row reads it in the journal instead of opening a second window")
        signature = page.detailSignature
        self.a.RefreshUI()
        self.assertEqual(page.selectedEvent.payload.questId, 11)
        self.assertEqual(page.detailSignature, signature)

    def test_journal_uses_the_same_quest_card_as_database_and_dungeon_journal(self):
        self.a.Record("quest.accepted", self.lua.table_from({"questId": 42, "title": "A real quest"}))
        self.lua.execute('''
          QUEST_DRAWS=0
          Evertally.LoadGuide=function() return true end
          Evertally.map={
            Db={Open=function() return {} end},
            DatabaseQuestModel=function(db,id) return {id=id,title="A real quest",objective="Find the book"} end,
            GuideDetail=function(kit,parent) return {scroll=CreateFrame("ScrollFrame",nil,parent),SetWidth=function() end} end,
            RenderQuestCard=function(view,model) QUEST_DRAWS=QUEST_DRAWS+1;DRAWN_QUEST=model.id end
          }
        ''')
        self.a.OpenUI(); self.a.ShowView("journal")
        self.assertEqual(self.lua.globals().DRAWN_QUEST, 42)
        self.assertTrue(self.a.journalPage.questView.scroll.shown)
        draws = self.lua.globals().QUEST_DRAWS
        self.a.RefreshUI()
        self.assertEqual(self.lua.globals().QUEST_DRAWS, draws, "ordinary refresh must not reset a quest card's reading position")

    def test_dungeon_selection_filters_times_and_completion_counts_without_mutating_history(self):
        self.lua.execute('''
          Evertally.db.runs={
            {character={id="Player-TEST-own"},status="completed",name="The Deadmines",durationMs=1800000},
            {character={id="Player-TEST-own"},status="completed",name="Wailing Caverns",durationMs=900000},
            {character={id="Player-TEST-own"},status="interrupted",name="Do not count",durationMs=100}}
        ''')
        self.a.OpenUI(); kit = self.a.UIKit()
        self.assertEqual(self.a.RankingRows(kit, "fastest")[1].valueText, "15:00")
        self.assertEqual(self.a.RankingRows(kit, "fastest", "The Deadmines")[1].valueText, "30:00")
        self.assertEqual(self.a.RankingRows(kit, "runs", "The Deadmines")[1].valueText, "1")
        self.assertEqual(len(self.a.RankingRows(kit, "fastest", "Unknown dungeon")), 0)
        self.assertEqual(len(self.a.db.runs), 3)
        names = self.a.RankingDungeons()
        self.assertEqual([names[i] for i in range(1,len(names)+1)], ["The Deadmines", "Wailing Caverns"])

    def test_contact_selection_only_fills_the_request_and_preserves_explicit_consent(self):
        self.lua.execute('''
          C_FriendList={GetNumFriends=function() return 1 end,
            GetFriendInfoByIndex=function() return {name="Bran",connected=true,level=30} end}
          INSPECT_COUNT=0
          Evertally.RequestInspect=function(name,kinds) INSPECT_COUNT=INSPECT_COUNT+1;INSPECT_NAME=name;INSPECT_KINDS=kinds;return true end
        ''')
        self.a.OpenUI(); self.a.ShowView("social")
        page = self.a.social.page
        self.a.SocialRoster()[1].onClick()
        self.assertEqual(page.name.text, "Bran")
        self.assertEqual(self.lua.globals().INSPECT_COUNT, 0)
        self.assertFalse(page.kinds.g, "gold remains opt-in")
        page.sendRequest.scripts.OnClick(page.sendRequest)
        self.assertEqual(self.lua.globals().INSPECT_COUNT, 1)
        # gear, stats, talents, professions, quests, reputations and (the website is on from the start since 2026-11-18) the
        # website; never gold
        self.assertEqual(self.lua.globals().INSPECT_KINDS, "istpqrw")
        self.assertTrue(page.requestLeaf.shown)
        self.assertIsNone(self.a.lastUIError)


if __name__ == "__main__":
    unittest.main()

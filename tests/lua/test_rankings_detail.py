"""Detailed personal/shared rankings: real attribution, missing data and independent filters."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_addon import runtime, MOCK_UI_LUA


def rows(table):
    return [table[i] for i in range(1, len(table) + 1)]


FIXTURE = '''
local A=Evertally
local c=A.Character()
A.db.runs={
 {runId="own-party",character=c,name="The Deadmines",instanceType="party",status="completed",completion="last_boss",durationMs=1200000,startedAt=NOW-1500,groupSize=5,deaths=2,
  bosses={{name="Rhahk'Zor",killedAt=NOW-1300},{name="Edwin VanCleef",durationMs=90000}},
  roster={{guid=c.id,name=c.name,classId=c.classId,raceId=c.raceId},{guid="Player-Missing",name="Unmeasured"}},
  combat={source="combat_log",coverage="observed",coveredMs=1200000,activeMs=100000,damage=999999,healing=888888,
   players={{guid=c.id,name=c.name,classId=c.classId,raceId=c.raceId,damage=10000,healing=2000,deaths=1,activeMs=100000},
    {guid="Player-Healer",name="Healer",classId=5,raceId=1,damage=1000,healing=30000,activeMs=100000}}}},
 {runId="own-raid",character=c,name="Molten Core",instanceType="raid",status="completed",durationMs=3600000,startedAt=NOW-86400,groupSize=40,
  combat={source="damage_meter",coverage="observed",activeMs=200000,coveredMs=3600000,players={{guid=c.id,name=c.name,damage=100000,healing=30000}}}},
 {runId="partial",character=c,name="The Deadmines",instanceType="party",status="completed",durationMs=1100000,startedAt=NOW-3000,
  combat={source="combat_log",coverage="partial",activeMs=1000,players={{guid=c.id,name=c.name,damage=99999999,healing=99999999}}}},
 {runId="missing",character=c,name="Wailing Caverns",instanceType="party",status="interrupted",durationMs=800000,startedAt=NOW-5000}}
A.peerDB.peers.Mage={producerId="peer",completedRuns=25,receivedAt=NOW,character={id="Player-Mage",name="Mage",classId=8,raceId=1,level=60},runs={
 {name="The Deadmines",instanceType="party",status="completed",durationMs=1000000,startedAt=NOW-2000,
  combat={source="combat_log",coverage="observed",activeMs=100000,damage=9999999,players={{guid="Player-Mage",name="Mage",damage=20000,healing=1000}}}}}}
'''


class DetailedRankingTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = runtime()
        self.lua.execute(MOCK_UI_LUA)
        self.lua.execute(FIXTURE)
        self.a.OpenUI()
        self.kit = self.a.UIKit()

    def filtered(self, mode, **filters):
        return rows(self.a.RankingRows(self.kit, mode, None, self.lua.table_from(filters)))

    def detail_text(self, run):
        model = self.a.RankingRunDetail(self.kit, run, self.a.Character())
        return "\n".join(str(entry.text) for entry in rows(model.entries))

    def test_instance_type_class_and_race_filters_intersect_without_mutating_runs(self):
        raid = self.filtered("history", kind="raid", classId=7, raceId=6)
        self.assertEqual(len(raid), 1)
        self.assertEqual(raid[0].run.name, "Molten Core")
        party_mages = self.filtered("history", kind="party", classId=8, raceId=1)
        self.assertEqual(len(party_mages), 1)
        self.assertEqual(party_mages[0].name, "Mage")
        self.assertEqual(len(self.a.db.runs), 4)
        self.assertEqual(self.filtered("history", kind="raid", classId=8), [])

    def test_search_intersects_filters_preserves_rank_and_searches_realms(self):
        self.lua.execute('''Evertally.peerDB.peers.Mage.character.realm="Železný svět"''')
        all_levels = self.filtered("level")
        mage_rank = next(row.rank for row in all_levels if row.name == "Mage")
        for mode in ("runs", "level", "fastest", "dps", "heals", "history"):
            with self.subTest(mode=mode):
                result = self.filtered(mode, query="ŽELEZNÝ", classId=8, raceId=1, kind="party")
                self.assertTrue(result)
                self.assertTrue(all(row.name == "Mage" for row in result))
        result = self.filtered("level", query="ŽELEZNÝ")
        self.assertEqual(result[0].rank, mage_rank, "search preserves the real position before text filtering")
        self.assertEqual(self.filtered("history", query="železný", kind="raid"), [])
        dungeons = self.filtered("dungeons", query="mage", kind="party")
        self.assertEqual([r.name for r in dungeons], ["The Deadmines"])
        self.assertEqual(self.filtered("dungeons", query="mage", kind="raid"), [])

    def test_search_control_opens_filtered_detail_and_clear_restores_rows(self):
        self.a.ShowView("rankings")
        page = self.a.rankingsPage
        page.search.SetText(page.search, "mage")
        page.search.scripts.OnTextChanged(page.search)
        self.assertEqual(len(rows(page.data)), 1)
        self.assertEqual(page.data[1].name, "Mage")
        page.boardList["items"][1].onClick()
        self.assertEqual(page.document.spec.title, "Mage")
        page.clearSearch.scripts.OnClick()
        self.assertEqual(page.filters.query, "")
        self.assertGreater(len(rows(page.data)), 1)

    def test_czech_heading_uppercase_preserves_utf8(self):
        self.a.db.settings.language = "cs"
        self.a.ShowView("rankings")
        page = self.a.rankingsPage
        page.mode = "level"
        page.Refresh()
        self.assertEqual(page.boardTitle.text, "ÚROVEŇ")
        page.dungeon = "Český řetěz žluťoučký kůň"
        page.Refresh()
        self.assertEqual(page.boardTitle.text, "ČESKÝ ŘETĚZ ŽLUŤOUČKÝ KŮŇ")

    def test_dps_and_hps_use_individual_combat_seconds_and_exclude_partial_spikes(self):
        dps = self.filtered("dps", kind="party")
        self.assertEqual([r.name for r in dps], ["Mage", "Fixture Hero", "Healer"])
        self.assertEqual([r.valueText for r in dps], ["200.0 DPS", "100.0 DPS", "10.0 DPS"])
        self.assertEqual(dps[1].run.runId, "own-party")
        raids = self.filtered("heals", kind="raid")
        self.assertEqual(raids[0].valueText, "150.0 HPS")
        self.assertEqual(raids[0].run.runId, "own-raid")

    def test_observed_group_players_need_no_peer_addon_but_are_not_duplicate_profiles(self):
        healers = self.filtered("heals", kind="party", classId=5, raceId=1)
        self.assertEqual(len(healers),1)
        self.assertEqual(healers[0].name,"Healer")
        self.assertEqual(healers[0].valueText,"300.0 HPS")
        self.assertTrue(healers[0].entry.observed)
        self.assertIn(self.a.L("rankObservedGroup"),healers[0].entry and self.a.RankingRows(self.kit,"runs",None,self.lua.table(classId=5))[1].sub)
        self.lua.execute('''Evertally.peerDB.peers.Healer={producerId="h",character={id="Player-Healer",name="Healer",classId=5},runs={}}''')
        self.assertEqual(len(self.filtered("runs",classId=5)),1)

    def test_group_totals_are_never_misattributed_to_owner_or_same_name_different_guid(self):
        self.lua.execute('''
          local r=Evertally.db.runs[1]
          r.combat.players={{guid="Player-Impostor",name=Evertally.Character().name,damage=1000000,healing=1000000}}
        ''')
        run = self.a.db.runs[1]
        self.assertIsNone(self.a.RankingRate(run, self.a.Character(), "dps"))
        run.combat.players = self.lua.table()
        self.assertIsNone(self.a.RankingRate(run, self.a.Character(), "heals"))

    def test_run_detail_contains_instance_boss_splits_roster_group_totals_and_rates(self):
        text = self.detail_text(self.a.db.runs[1])
        for expected in ("20:00", "Rhahk'Zor", "3:20", "Edwin VanCleef", "1:30", "999999", "Fixture Hero", "100.0", "Healer", "300.0", "Unmeasured", self.a.L("rankUnrecorded")):
            self.assertIn(expected, text)
        self.assertIn(self.a.L("rankScope"), text)
        self.assertIn(self.a.L("rankObserved"), text)

    def test_missing_combat_remains_missing_and_partial_coverage_is_explicit(self):
        missing = self.detail_text(self.a.db.runs[4])
        self.assertIn(self.a.L("rankUnavailable"), missing)
        self.assertNotIn("0.0 DPS", missing)
        partial = self.detail_text(self.a.db.runs[3])
        self.assertIn(self.a.L("rankPartial"), partial)
        self.assertEqual(self.a.RankingRate(self.a.db.runs[3], self.a.Character(), "dps"), None)

    def test_reference_catalogue_and_raid_observations_remain_selectable_without_invented_runs(self):
        self.a.db.runs = self.lua.table()
        self.a.peerDB.peers = self.lua.table()
        catalogue = rows(self.a.RankingCatalog())
        self.assertIn("The Deadmines", [r.name for r in catalogue])
        self.assertTrue(all(r.count == 0 for r in catalogue))
        raids=rows(self.a.RankingCatalog(self.lua.table(kind="raid")))
        self.assertIn("Molten Core",[r.name for r in raids])
        self.assertEqual(self.filtered("history"), [])

    def test_page_selection_opens_run_and_back_returns_to_filtered_board(self):
        self.a.ShowView("rankings")
        page = self.a.rankingsPage
        page.mode = "history"
        page.Refresh()
        first = next(e for e in rows(page.document.spec.entries) if e.onClick is not None)
        first.onClick()
        self.assertEqual(page.document.spec.title, "The Deadmines")
        self.assertIsNotNone(page.selection.run)
        back = page.document.spec.entries[1]
        self.assertEqual(back.text, self.a.L("rankBack"))
        back.onClick()
        self.assertIsNone(page.selection)
        self.assertEqual(page.mode, "history")

    def test_active_instance_is_visible_without_claiming_completion_or_finished_dps(self):
        self.lua.execute('''
          INSIDE=true;INSTANCE=409
          GetInstanceInfo=function() return "Active raid","raid",1,"Normal",40,0,false,409 end
          Evertally.RefreshInstance()
        ''')
        history=self.filtered("history",kind="raid")
        active=next(r for r in history if r.run.name=="Active raid")
        self.assertEqual(active.run.status,"visiting")
        self.assertFalse(any(r.run.name=="Active raid" for r in self.filtered("dps",kind="raid")))
        self.assertEqual(self.filtered("runs",kind="raid")[0].valueText,"1")
        spec=self.a.RankingRunDetail(self.kit,active.run,self.a.Character())
        finish=next(e for e in rows(spec.entries) if e.onClick is not None and e.text==self.a.L("rankEndManual"))
        finish.onClick()
        self.assertIsNone(self.a.ActiveRun())
        self.assertEqual(self.a.db.runs[len(self.a.db.runs)].status,"manual")


if __name__ == "__main__":
    unittest.main()

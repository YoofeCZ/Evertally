"""Behavioral checks for Evertally's own computed guide; no live game state."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_addon import runtime, MOCK_UI_LUA, ROOT  # noqa: E402


class QuestGuideTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = runtime()
        if self.a.QuestGuide is None:
            for name in ("QuestGuideData.lua", "QuestGuide.lua", "QuestGuideUI.lua"):
                fn = self.lua.eval("loadstring")((ROOT / "addon/Evertally" / name).read_text(encoding="utf8"), name)
                if isinstance(fn, tuple): raise AssertionError(fn)
                fn("Evertally", self.a)
        self.lua.execute("""
        CHARACTER='Player-TEST-own'; LEVEL=12; RACE=1; CLASS=2; SIDE='Alliance'
        UnitGUID=function()return CHARACTER end
        UnitLevel=function()return LEVEL end
        UnitRace=function()return 'Human','Human',RACE end
        UnitClass=function()return 'Paladin','PALADIN',CLASS end
        UnitFactionGroup=function()return SIDE end
        DONE={};ON={};COMPLETE={};OBJS={};CALLS=0
        C_Timer=nil
        C_QuestLog={IsQuestFlaggedCompleted=function(id)CALLS=CALLS+1;return DONE[id]==true end,
          IsOnQuest=function(id)return ON[id]==true end,IsComplete=function(id)return COMPLETE[id]==true end,
          GetQuestObjectives=function(id)return OBJS[id] end,GetAllCompletedQuestIDs=function()local out={};for id in pairs(DONE)do out[#out+1]=id end;return out end}
        C_Map={GetBestMapForUnit=function()return 1429 end}
        local spot={{map=1429,x=.4,y=.6}}
        Evertally.questGuideData={raceBits={[1]=1,[2]=2,[95]=4294967296,[96]=8589934592},quests={
          [1]={id=1,title='First task',level=10,minLevel=1,map=1429,zone='Elwynn',starts={{name='Giver',spots=spot}},ends={{name='Return',spots=spot}},objectives={{name='Target',spots=spot}},text='Do something'},
          [2]={id=2,title='Followup',level=10,minLevel=1,map=1429,zone='Elwynn',requiresAll={1},starts={{name='Giver',spots=spot}}},
          [3]={id=3,title='Other area',level=14,minLevel=10,map=1436,zone='Westfall',starts={{name='Giver',spots=spot}}}
        }}
        Evertally.QuestGuide.ResetCache()
        Evertally.QuestGuide.SelectRoute(1429)
        """)
        self.q = self.a.QuestGuide

    def runlua(self, text):
        return self.lua.execute(text)

    def test_generated_catalogue_is_substantial_and_has_forever_races(self):
        fn = self.lua.eval("loadstring")((ROOT / "addon/Evertally/QuestGuideData.lua").read_text(encoding="utf8"))
        fn("Evertally", self.a)
        count = self.runlua("local n=0;for _ in pairs(Evertally.questGuideData.quests)do n=n+1 end;return n")
        self.assertGreater(count, 5000)
        self.assertEqual(self.a.questGuideData.raceBits[95], 4294967296)
        dungeon = self.runlua("local n=0;for _,q in pairs(Evertally.questGuideData.quests)do if q.dungeon then n=n+1 end end;return n")
        self.assertGreater(dungeon, 100)

    def test_accept_objectives_turnin_and_completion_are_distinct(self):
        self.assertEqual(self.q.Current()[0].phase, "accept")
        self.runlua("ON[1]=true;Evertally.Dispatch('QUEST_ACCEPTED',4,1)")
        self.assertEqual(self.q.Current()[0].phase, "objectives")
        self.runlua("OBJS[1]={{text='Kobolds',finished=true}};Evertally.Dispatch('QUEST_LOG_UPDATE')")
        self.assertEqual(self.q.Current()[0].phase, "turnin")
        self.assertEqual(self.q.Plan().done, 0)
        self.runlua("ON[1]=nil;DONE[1]=true;Evertally.Dispatch('QUEST_TURNED_IN',1)")
        self.assertEqual(self.q.Plan().done, 1)
        self.assertEqual(self.q.Current()[0].questId, 2)

    def test_abandonment_does_not_complete_or_unlock_followup(self):
        self.runlua("ON[1]=true;Evertally.QuestGuide.Invalidate()")
        self.assertEqual(self.q.State(1), "objectives")
        self.runlua("ON[1]=nil;Evertally.Dispatch('QUEST_REMOVED',1)")
        self.assertEqual(self.q.Current()[0].phase, "accept")
        self.assertFalse(self.q.Available(self.a.questGuideData.quests[2])[0])

    def test_skip_never_satisfies_a_prerequisite_and_resume_persists(self):
        self.assertTrue(self.q.Skip())
        self.assertEqual(len(self.q.Plan().steps), 0)
        self.assertEqual(self.q.Plan().skipped, 1)
        self.q.ResetCache()
        self.assertEqual(self.q.Plan().skipped, 1)
        self.assertFalse(self.q.Available(self.a.questGuideData.quests[2])[0])
        self.assertTrue(self.q.Resume())
        self.assertEqual(self.q.Current()[0].questId, 1)

    def test_and_or_prerequisites_keep_their_semantics(self):
        self.runlua("local q=Evertally.questGuideData.quests[2];q.requiresAll=nil;q.requiresAny={1,100};DONE[100]=true;Evertally.QuestGuide.ResetCache()")
        self.assertTrue(self.q.Available(self.a.questGuideData.quests[2])[0])
        self.runlua("local q=Evertally.questGuideData.quests[2];q.requiresAny=nil;q.requiresAll={1,100};Evertally.QuestGuide.ResetCache()")
        self.assertFalse(self.q.Available(self.a.questGuideData.quests[2])[0])
        self.runlua("DONE[1]=true;Evertally.QuestGuide.ResetCache()")
        self.assertTrue(self.q.Available(self.a.questGuideData.quests[2])[0])

    def test_cycles_stay_locked(self):
        self.runlua("Evertally.questGuideData.quests[1].requiresAll={2};Evertally.QuestGuide.ResetCache()")
        self.assertEqual(len(self.q.Plan().steps), 0)
        self.assertEqual(len(self.q.Plan().locked), 2)

    def test_exclusive_done_or_active_branch_blocks_pickup(self):
        self.runlua("Evertally.questGuideData.quests[1].exclusive={200};ON[200]=true")
        self.assertEqual(self.q.Available(self.a.questGuideData.quests[1]), (False, "exclusive"))
        self.runlua("ON[200]=nil;DONE[200]=true;Evertally.QuestGuide.ResetCache()")
        self.assertEqual(self.q.Available(self.a.questGuideData.quests[1]), (False, "exclusive"))

    def test_skyborne_faction_and_class_masks_use_high_bits(self):
        self.runlua("RACE=95;local q=Evertally.questGuideData.quests[1];q.raceMask=4294967296;q.classMask=2;q.faction='Alliance'")
        self.assertTrue(self.q.Visible(self.a.questGuideData.quests[1]))
        self.runlua("RACE=96")
        self.assertEqual(self.q.Visible(self.a.questGuideData.quests[1]), (False, "race"))
        self.runlua("RACE=95;CLASS=3")
        self.assertEqual(self.q.Visible(self.a.questGuideData.quests[1]), (False, "class"))
        self.runlua("CLASS=2;SIDE='Horde'")
        self.assertEqual(self.q.Visible(self.a.questGuideData.quests[1]), (False, "faction"))

    def test_per_character_progress_is_separate(self):
        self.runlua("Evertally.Dispatch('QUEST_TURNED_IN',1)")
        self.assertEqual(self.q.State(1), "done")
        self.runlua("CHARACTER='Other';DONE={}")
        self.assertEqual(self.q.State(1), "available")
        self.assertIsNone(self.q.Store().done[1])
        self.runlua("CHARACTER='Player-TEST-own'")
        self.assertEqual(self.q.State(1), "done")

    def test_level_class_and_optional_dungeon_filters(self):
        self.runlua("local q=Evertally.questGuideData.quests[1];q.minLevel=20")
        self.assertEqual(self.q.Available(self.a.questGuideData.quests[1]), (False, "level"))
        self.runlua("local q=Evertally.questGuideData.quests[1];q.minLevel=1;q.dungeon='Deadmines'")
        self.assertEqual(self.q.Visible(self.a.questGuideData.quests[1]), (False, "dungeon_off"))
        self.q.SetOption("includeDungeons", True)
        self.assertTrue(self.q.Visible(self.a.questGuideData.quests[1]))
        self.runlua("Evertally.questGuideData.quests[1].classMask=2")
        self.q.SetOption("includeClass", False)
        self.assertEqual(self.q.Visible(self.a.questGuideData.quests[1]), (False, "class_off"))

    def test_missing_requirement_apis_never_assume_requirements_satisfied(self):
        self.runlua("Evertally.questGuideData.quests[1].requiredSkill={164,75};C_TradeSkillUI=nil")
        self.assertEqual(self.q.Available(self.a.questGuideData.quests[1]), (False, "skill"))
        self.runlua("local q=Evertally.questGuideData.quests[1];q.requiredSkill=nil;q.requiredSpell=123;C_SpellBook=nil;IsSpellKnown=nil;IsPlayerSpell=nil")
        self.assertEqual(self.q.Available(self.a.questGuideData.quests[1]), (False, "spell"))

    def test_missing_quest_api_does_not_claim_active_or_done(self):
        self.runlua("C_QuestLog=nil;Evertally.QuestGuide.ResetCache()")
        self.assertEqual(self.q.State(1), "unknown")
        self.assertFalse(self.q.Available(self.a.questGuideData.quests[2])[0])
        self.assertEqual(self.q.Current()[0].phase, "accept")

    def test_dynamic_availability_is_not_invented_but_active_quest_is_supported(self):
        self.runlua("Evertally.questGuideData.quests[1].dynamic=true")
        self.assertEqual(self.q.Available(self.a.questGuideData.quests[1]), (False, "dynamic"))
        self.runlua("ON[1]=true")
        self.assertEqual(self.q.Available(self.a.questGuideData.quests[1]), (True, "objectives"))

    def test_parent_must_be_active_and_next_branch_makes_old_pickup_unavailable(self):
        self.runlua("Evertally.questGuideData.quests[1].parentQuest=200;DONE[200]=true")
        self.assertEqual(self.q.Available(self.a.questGuideData.quests[1]), (False, "prerequisite"))
        self.runlua("DONE[200]=nil;ON[200]=true;Evertally.QuestGuide.ResetCache()")
        self.assertEqual(self.q.Available(self.a.questGuideData.quests[1]), (True, "accept"))
        self.runlua("local q=Evertally.questGuideData.quests[1];q.parentQuest=nil;q.nextQuest=200")
        self.assertEqual(self.q.Available(self.a.questGuideData.quests[1]), (False, "exclusive"))

    def test_unknown_signed_spell_requirement_is_not_misread(self):
        self.runlua("Evertally.questGuideData.quests[1].requiredSpell=-12345")
        self.assertEqual(self.q.Available(self.a.questGuideData.quests[1]), (False, "unverified_requirement"))

    def test_navigation_uses_current_phase_and_existing_terrain_navigation(self):
        self.runlua("Evertally.PlayerPosition=function()return 1429,.3,.5 end;Evertally.NavigateToPoint=function(label,map,x,y,source)NAV={label,map,x,y,source};return true end")
        self.assertTrue(self.q.Navigate()[0])
        nav = self.lua.globals().NAV
        self.assertEqual(nav[2], 1429)
        self.assertEqual(nav[5].view, "questguide")
        self.assertEqual(nav[5].questId, 1)
        self.assertEqual(nav[5].step, "accept")

    def test_unchanged_render_reuses_plan_without_rescanning_quests(self):
        self.q.Plan()
        before = self.lua.globals().CALLS
        for _ in range(30): self.q.Plan()
        self.assertEqual(self.lua.globals().CALLS, before)

    def test_next_does_not_mark_current_done(self):
        self.runlua("Evertally.questGuideData.quests[2].requiresAll=nil;Evertally.QuestGuide.ResetCache()")
        self.assertTrue(self.q.Next())
        self.assertEqual(self.q.Current()[0].questId, 2)
        self.assertNotEqual(self.q.State(1), "done")
        self.assertTrue(self.q.Back())
        self.assertEqual(self.q.Current()[0].questId, 1)

    def test_page_and_tracker_render_with_mock_frames(self):
        self.lua.execute(MOCK_UI_LUA)
        page = self.lua.eval("object(UIParent)")
        self.a.BuildQuestGuidePage(page, self.a.UIKit())
        page.Refresh()
        self.assertIsNotNone(self.a.questGuidePage)
        self.q.SetOption("tracker", True)
        self.a.QuestGuideRefreshTracker()

    def test_routes_are_level_legs_and_recommendations_are_bounded(self):
        self.runlua("""
        Evertally.questGuideData.zoneLevels={[1429]={1,10},[1418]={35,45},[1461]={20,60}}
        Evertally.questGuideData.quests[4]={id=4,title='Late Elwynn',level=55,minLevel=1,map=1429,zone='Elwynn'}
        Evertally.questGuideData.quests[5]={id=5,title='Badlands',level=40,minLevel=1,map=1418,zone='Badlands'}
        Evertally.questGuideData.quests[6]={id=6,title='AB token',level=1,minLevel=1,map=1461,zone='Arathi Basin'}
        Evertally.QuestGuide.ResetCache()
        """)
        routes = self.q.Routes()
        recommended = []
        elwynn_legs = []
        for i in range(1, len(routes) + 1):
            r = routes[i]
            if r.recommended: recommended.append(r)
            if r.map == 1429: elwynn_legs.append((r.minLevel, r.maxLevel))
        self.assertLessEqual(len(recommended), 3)
        self.assertNotIn(1418, [r.map for r in recommended])
        self.assertNotIn(1461, [r.map for r in recommended])
        self.assertEqual(sorted(elwynn_legs), [(6, 10), (50, 55)])

    def test_recommendations_prefer_nearby_zones_on_current_continent(self):
        self.runlua('''
          Evertally.questGuideData.zoneGeometry={
            [1429]={continent='east',rect={.6,.7,.6,.7}},
            [1436]={continent='east',rect={.5,.6,.6,.7}},
            [1439]={continent='west',rect={.2,.3,.3,.4}}}
          Evertally.questGuideData.quests[4]={id=4,title='Far away',level=14,minLevel=10,map=1439,zone='Darkshore'}
          Evertally.questGuideData.zoneLevels={[1429]={1,10},[1436]={10,20},[1439]={10,20}}
          Evertally.QuestGuide.ResetCache()
        ''')
        self.assertEqual(self.q.Routes()[1].map, 1436)

    def test_navigation_targets_only_unfinished_objectives_when_client_supplies_ids(self):
        self.runlua('''
          ON[1]=true
          Evertally.questGuideData.quests[1].objectives={
            {kind='npc',id=10,name='Already killed',spots={{map=1429,x=.1,y=.2}}},
            {kind='npc',id=20,name='Still needed',spots={{map=1429,x=.8,y=.9}}}}
          OBJS[1]={{objectID=10,type='monster',finished=true},{objectID=20,type='monster',finished=false}}
          Evertally.QuestGuide.Invalidate()
        ''')
        step = self.q.Current()[0]
        self.assertEqual(step.phase, 'objectives')
        self.assertEqual(len(step.targets), 1)
        self.assertEqual(step.targets[1].label, 'Still needed')

    def test_parent_and_starting_quests_require_real_quest_state(self):
        quest = self.a.questGuideData.quests[2]
        self.runlua('local q=Evertally.questGuideData.quests[2];q.requiresAll=nil;q.parentQuest=1')
        self.assertEqual(self.q.Available(quest), (False, 'prerequisite'))
        self.runlua('ON[1]=true')
        self.assertEqual(self.q.Available(quest), (True, 'accept'))
        self.runlua('local q=Evertally.questGuideData.quests[2];q.parentQuest=nil;q.startingWith=1;ON[1]=nil;DONE[1]=true')
        self.assertEqual(self.q.Available(quest), (True, 'accept'))
        self.runlua('local q=Evertally.questGuideData.quests[2];q.startingWith=nil;q.nextQuest=3;ON[3]=true')
        self.assertEqual(self.q.Available(quest), (False, 'exclusive'))

    def test_missing_prerequisite_from_previous_leg_is_included(self):
        self.runlua("Evertally.questGuideData.quests[2].level=15;Evertally.QuestGuide.ResetCache();Evertally.QuestGuide.SelectRoute('1429:10:15')")
        self.assertEqual(self.q.Current()[0].questId, 1)
        self.runlua("Evertally.Dispatch('QUEST_TURNED_IN',1)")
        self.assertEqual(self.q.Current()[0].questId, 2)
        self.q.SetOption("tracker", False)
        self.a.QuestGuideRefreshTracker()


if __name__ == "__main__": unittest.main()

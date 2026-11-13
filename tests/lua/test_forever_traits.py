"""Forever's C_Traits-only contract: no legacy GetTalent* globals and no game mutations."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_addon import runtime, MOCK_UI_LUA


# Explicitly modern-only. The game API names/group/edge shape match the installed Forever talent reader.
# Spell names and node identities below are synthetic fixtures, never shipped game talent data.
FOREVER_TRAITS = r'''
GetNumTalentTabs=nil;GetTalentTabInfo=nil;GetNumTalents=nil;GetTalentInfo=nil;GetTalentPrereqs=nil
TRAIT_WRITES=0;TRAIT_ORDER={100003,100001,100201,100006,100004,100002,100301,100005,199998,199999}
TRAIT_NODES={}
local function node(id,x,y,group,rank,max)
 TRAIT_NODES[id]={ID=id,posX=x,posY=y,groupIDs={group},activeRank=rank,currentRank=0,maxRanks=max,
  isVisible=true,entryIDs={id+100000},activeEntry={entryID=id+100000},visibleEdges={}}
end
node(100001,100,100,91,5,5);node(100002,200,100,91,0,5)
node(100003,100,200,91,0,1);node(100004,200,200,91,0,1)
node(100005,100,300,91,0,1);node(100006,100,500,91,0,1)
node(100201,1000,100,92,2,5);node(100301,2000,100,93,0,1)
node(199998,30000,100,91,0,1);node(199999,100,400,91,0,1);TRAIT_NODES[199999].isVisible=false
TRAIT_NODES[100001].visibleEdges={{targetNode=100003,type=3},{targetNode=100004,type=2},{targetNode=100005,type=3},{targetNode=100006,type=0}}
TRAIT_NODES[100002].visibleEdges={{targetNode=100004,type=2},{targetNode=100005,type=3},{targetNode=100006,type=4}}
TRAIT_NODES[100301].entryIDs={200301,200302};TRAIT_NODES[100301].activeEntry={entryID=200302}
local function forbidden()TRAIT_WRITES=TRAIT_WRITES+1;error("Must never mutate actual talents")end
C_ClassTalents={GetActiveConfigID=function()return 81000 end,CommitConfig=forbidden}
C_Traits={
 GetConfigInfo=function(id)if id==81000 then return {treeIDs={70000}}end end,
 GetTreeNodes=function(id)return TRAIT_ORDER end,
 GetGroupDisplayInfoByTreeID=function(id)return {{groupID=93,displayName="Fixture Retribution"},{groupID=91,displayName="Fixture Holy"},{groupID=92,displayName="Fixture Protection"}}end,
 GetNodeInfo=function(config,id)return TRAIT_NODES[id]end,
 GetEntryInfo=function(config,entryID)return {definitionID=entryID+100000}end,
 GetDefinitionInfo=function(id)return {spellID=id+100000,overrideName=""}end,
 PurchaseRank=forbidden,RefundRank=forbidden,CommitConfig=forbidden,ResetTree=forbidden,SetSelection=forbidden,
}
C_Spell={GetSpellName=function(id)return "Fixture spell "..id end,GetSpellTexture=function(id)return id+100000 end}
LearnTalent=forbidden
'''


class ForeverTraitTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = runtime()
        self.lua.execute(FOREVER_TRAITS)

    def trees(self):
        trees = self.a.TalentTrees()
        self.assertEqual(len(trees), 3)
        return trees

    @staticmethod
    def talent(tree, node_id):
        return next(value for _, value in tree.talents.items() if value.nodeID == node_id)

    def change(self, plan, trees, node_id, amount=1):
        result = self.a.ChangeTalentPlan(plan, trees, trees[1].tab, node_id, amount)
        return result if isinstance(result, bool) else result[0]

    def test_modern_only_reader_gets_three_real_sections_committed_ranks_icons_and_choice_spell(self):
        trees = self.trees()
        self.assertEqual([trees[i].name for i in range(1, 4)], ['Fixture Holy', 'Fixture Protection', 'Fixture Retribution'])
        self.assertEqual(trees[1].spent, 5)
        self.assertEqual(trees[2].spent, 2)
        first = self.talent(trees[1], 100001)
        self.assertEqual((first.index, first.rank, first.max, first.tier, first.column), (100001, 5, 5, 1, 1))
        self.assertEqual(first.name, 'Fixture spell 400001')
        self.assertEqual(first.icon, 500001)
        choice = self.talent(trees[3], 100301)
        self.assertEqual(choice.entryID, 200302)
        self.assertEqual(choice.spellID, 400302)
        self.assertEqual(self.talent(trees[1], 100006).tier, 5, 'retain an empty row instead of compressing the tree')
        self.assertEqual(len(trees[1].talents), 6, 'exclude hidden and off-grid DB2 records')

    def test_unsorted_and_rotated_node_lists_keep_saved_build_identity_and_position(self):
        trees = self.trees()
        plan = self.a.NewTalentPlan(trees, 60, False)
        self.a.SaveTalentBuild(plan, 'Modern saved')
        self.lua.execute('TRAIT_ORDER={100301,100005,100002,100006,100201,100001,100004,100003}')
        reordered = self.trees()
        self.assertEqual(reordered[1].tab, trees[1].tab)
        self.assertEqual([reordered[1].talents[i].nodeID for i in range(1, 7)], [100001, 100002, 100003, 100004, 100005, 100006])
        loaded = self.a.LoadTalentBuild(self.a.SavedTalentBuilds()[1], reordered)
        self.assertEqual(loaded.ranks[trees[1].tab][100001], 5)
        self.assertEqual(loaded.ranks[trees[2].tab][100201], 2)

    def test_required_and_sufficient_edges_and_remove_dependencies_are_distinct(self):
        trees = self.trees()
        plan = self.a.NewTalentPlan(trees, 60, True)
        self.assertFalse(self.change(plan, trees, 100003))
        for _ in range(5): self.assertTrue(self.change(plan, trees, 100001))
        self.assertTrue(self.change(plan, trees, 100003), 'required parent is complete')
        self.assertTrue(self.change(plan, trees, 100004), 'one sufficient parent is enough')
        self.assertFalse(self.change(plan, trees, 100001, -1), 'cannot break a learned dependent')
        self.assertFalse(self.change(plan, trees, 100005), 'two required parents must both be complete')
        for _ in range(5): self.assertTrue(self.change(plan, trees, 100002))
        self.assertTrue(self.change(plan, trees, 100005))
        self.assertEqual(self.lua.globals().TRAIT_WRITES, 0)

    def test_budget_is_shared_without_spending_actual_modern_ranks(self):
        trees = self.trees()
        plan = self.a.NewTalentPlan(trees, 10, True)
        self.assertTrue(self.change(plan, trees, 100001))
        result = self.a.ChangeTalentPlan(plan, trees, trees[2].tab, 100201, 1)
        self.assertFalse(result[0])
        self.assertEqual(self.talent(self.trees()[1], 100001).rank, 5)
        self.assertEqual(self.lua.globals().TRAIT_WRITES, 0)

    def test_trait_config_uses_forever_specialization_fallback(self):
        self.lua.execute('C_ClassTalents=nil;C_SpecializationInfo={GetActiveSpecGroup=function()return 2 end,GetCombatConfigIDForSpecGroup=function(group)assert(group==2);return 81000 end}')
        self.assertEqual(self.trees()[1].configID, 81000)

    def test_missing_group_headers_split_the_single_forever_tree_by_real_section_gaps(self):
        self.lua.execute('C_Traits.GetGroupDisplayInfoByTreeID=nil')
        trees = self.trees()
        self.assertEqual([len(trees[i].talents) for i in range(1, 4)], [6, 1, 1])
        self.assertEqual(self.talent(trees[1], 100001).rank, 5)

    def test_delayed_config_read_is_loading_and_a_trait_event_refreshes_the_visible_page(self):
        self.lua.execute(MOCK_UI_LUA)
        self.lua.execute('C_ClassTalents.GetActiveConfigID=function()return nil end')
        page = self.lua.eval('CreateFrame')('Frame', None, None)
        self.a.BuildTalentsPage(page, self.a.UIKit())
        page.Refresh()
        self.assertEqual(page.talents.note.text, self.a.L('talentLoading'))
        self.lua.execute('REFRESHES=0;Evertally.RefreshUI=function()REFRESHES=REFRESHES+1 end')
        self.a.Dispatch('TRAIT_CONFIG_UPDATED', 81000)
        self.assertEqual(self.lua.globals().REFRESHES, 1)
        self.lua.execute('C_ClassTalents.GetActiveConfigID=function()return 81000 end')
        page.Refresh()
        self.assertEqual(len(page.talents.buttons), 8)
        self.assertNotEqual(page.talents.note.text, self.a.L('talentNoApi'))

    def test_modern_tooltip_reads_the_spell_and_never_legacy_talent_or_writer(self):
        self.lua.execute(MOCK_UI_LUA)
        self.lua.execute('''TOOLTIP_SPELL=nil;GameTooltip={SetOwner=function()end,SetSpellByID=function(self,id)TOOLTIP_SPELL=id end,
          SetTalent=function()error("Wrong legacy tooltip")end,AddLine=function()end,Show=function()end,Hide=function()end}''')
        page = self.lua.eval('CreateFrame')('Frame', None, None)
        self.a.BuildTalentsPage(page, self.a.UIKit())
        page.Refresh()
        button = page.talents.buttons[1]
        button.scripts.OnEnter(button)
        self.assertEqual(self.lua.globals().TOOLTIP_SPELL, 400001)
        self.assertEqual(self.lua.globals().TRAIT_WRITES, 0)


if __name__ == '__main__': unittest.main()

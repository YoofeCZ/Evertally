"""Profiles and import/export in the game's talent window (NativeTalents.lua): staging a profile, never committing it."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_addon import runtime, MOCK_UI_LUA
from test_forever_traits import FOREVER_TRAITS

# A staging talent window: ResetTree refunds the staged ranks, PurchaseRank adds one while the node can take it.
# Node 100003 sits a tier below 100001 and refuses a rank until 100001 is full, like the game.
STAGING = r'''
for _,n in pairs(TRAIT_NODES) do n.currentRank=n.activeRank end
RESETS=0;BUYS={};COMBAT=false
InCombatLockdown=function() return COMBAT end
C_Traits.ResetTree=function(config,tree) RESETS=RESETS+1;for _,n in pairs(TRAIT_NODES) do n.currentRank=0 end;return true end
C_Traits.PurchaseRank=function(config,id)
  local n=TRAIT_NODES[id]
  if n.currentRank>=n.maxRanks then return false end
  if id==100003 and TRAIT_NODES[100001].currentRank<5 then return false end
  if id==100301 then return false end
  n.currentRank=n.currentRank+1;BUYS[#BUYS+1]=id;return true
end
'''


class NativeTalentTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = runtime()
        self.lua.execute(FOREVER_TRAITS)
        self.lua.execute(STAGING)
        self.trees = self.a.TalentTrees()

    def plan(self, extra=False):
        plan = self.a.NewTalentPlan(self.trees, 60, True)
        plan.ranks[self.trees[1].tab][100001] = 5
        plan.ranks[self.trees[1].tab][100003] = 1
        plan.ranks[self.trees[2].tab][100201] = 2
        if extra:
            plan.ranks[self.trees[3].tab][100301] = 1
        return plan

    def test_a_profile_is_staged_tier_by_tier_and_never_committed(self):
        ok, missing = self.a.StageTalentPlan(self.plan(), self.trees)
        self.assertTrue(ok); self.assertEqual(missing, 0)
        g = self.lua.globals()
        self.assertEqual(g.RESETS, 1, "the old talents are refunded first (staged, not learned)")
        nodes = g.TRAIT_NODES
        self.assertEqual((nodes[100001].currentRank, nodes[100003].currentRank, nodes[100201].currentRank), (5, 1, 2))
        buys = [g.BUYS[i] for i in range(1, len(g.BUYS) + 1)]
        self.assertLess(buys.index(100001), buys.index(100003), "the upper tier first")
        self.assertEqual(g.TRAIT_WRITES, 0, "CommitConfig, RefundRank, LearnTalent never called: Apply Changes is the player's")

    def test_ranks_the_game_refuses_are_counted(self):
        ok, missing = self.a.StageTalentPlan(self.plan(extra=True), self.trees)
        self.assertTrue(ok); self.assertEqual(missing, 1)

    def test_nothing_happens_in_combat(self):
        self.lua.execute("COMBAT=true")
        ok, why = self.a.StageTalentPlan(self.plan(), self.trees)
        self.assertFalse(ok); self.assertEqual(why, "ntCombat")
        self.assertEqual(self.lua.globals().RESETS, 0)

    def test_the_window_gets_two_buttons_and_the_menu_lists_profiles(self):
        self.lua.execute(MOCK_UI_LUA)
        self.lua.execute('PlayerSpellsFrame=CreateFrame("Frame","PlayerSpellsFrame",UIParent);PlayerSpellsFrame.TalentsFrame=CreateFrame("Frame",nil,PlayerSpellsFrame)')
        self.assertTrue(self.a.NativeTalents.Attach())
        g = self.lua.globals()
        self.assertEqual(g.EvertallyTalentProfilesButton.text, self.a.L("ntProfiles"))
        self.a.SaveTalentBuild(self.plan(), "Enh leveling")
        button = g.EvertallyTalentProfilesButton
        button.scripts.OnClick(button)
        menu = g.EvertallyTalentProfilesMenu
        self.assertTrue(menu.IsShown(menu))
        self.assertEqual(menu.rows[1].text.text, "Enh leveling")
        menu.rows[1].scripts.OnClick(menu.rows[1], "LeftButton")
        self.assertEqual(g.TRAIT_NODES[100003].currentRank, 1, "clicking a profile stages it")
        transfer = g.EvertallyTalentTransferButton
        transfer.scripts.OnClick(transfer)
        d = g.EvertallyTalentTransfer
        self.assertTrue(d.IsShown(d))
        self.a.NativeTalents.Transfer("export")
        self.assertTrue(str(d.box.text).startswith("ETB1|"))


if __name__ == "__main__":
    unittest.main()

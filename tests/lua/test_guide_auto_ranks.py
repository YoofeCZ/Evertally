"""Auto spell ranks (Evertally_Guide/QoL/Spells.lua, qol.autoRanks, on by default): an old rank on the bars found after
training or at login is put right by itself (Spells.Upgrade), once per list in a session; the card (OLD_RANKS) is told
only for what is left, and as before when the option is off. 2026-11-19: the user wanted Auto Spell Ranks in Evertally."""
from pathlib import Path
import unittest

import lupa

ROOT = Path(__file__).resolve().parents[2]
SPELLS = ROOT / "addon" / "Evertally_Guide" / "QoL" / "Spells.lua"

STUB = r'''
  ON = {oldRanks = true, autoRanks = true, levelUpSpells = true}
  FIRED, UPGRADES, DEFAULTS = {}, 0, nil
  NS = {
    L = setmetatable({}, {__index = function(_, k) return k end}),
    RegisterDefaults = function(_, t) DEFAULTS = t end,
    RegisterEvent = function() end, On = function() end,
    After = function() end, SafeCall = function(f, ...) return f(...) end,
    Fire = function(ev, data) FIRED[#FIRED + 1] = {ev, data} end,
    Print = function() end,
    Compat = {InCombat = function() return false end},
  }
  NS.QoL = {Client = {}, On = function(k) return ON[k] == true end, State = function() return {} end,
    Secure = function(_, fn) fn(); return true end}
'''


class AutoRanksTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(STUB)
        chunk = self.lua.eval("loadstring or load")(SPELLS.read_text(encoding="utf8"))
        self.assertIsNotNone(chunk)
        self.lua.globals().SP_CHUNK = chunk
        self.lua.execute('''
          SP_CHUNK("Evertally_Guide", NS)
          S = NS.QoL.Spells
          LIST = {{id = 133, bestId = 8400, slots = {1, 13}}}
          S.OldRanks = function() return LIST, 2 end
          S.Upgrade = function() UPGRADES = UPGRADES + 1; return 2 end
        ''')
        self.g = self.lua.globals()

    def told(self):
        return [str(e[1]) for e in self.g.FIRED.values() if e[2] is not None]

    def test_on_by_default(self):
        self.assertTrue(self.g.DEFAULTS.autoRanks)

    def test_an_old_rank_is_put_right_by_itself_once_per_list(self):
        self.assertTrue(self.lua.eval("S.CheckRanks()"))
        self.assertEqual(self.g.UPGRADES, 1)
        self.assertEqual(self.told(), [], "no card when it was done")
        # the same list again (a slot that did not take it): the card, no second try
        self.lua.eval("S.CheckRanks(true)")
        self.assertEqual(self.g.UPGRADES, 1)
        self.assertEqual(self.told(), ["OLD_RANKS"])

    def test_something_on_the_cursor_leaves_it_to_the_card(self):
        self.lua.execute('GetCursorInfo = function() return "item", 6948 end')
        self.lua.eval("S.CheckRanks()")
        self.assertEqual(self.g.UPGRADES, 0)
        self.assertEqual(self.told(), ["OLD_RANKS"])

    def test_off_the_card_as_before(self):
        self.g.ON.autoRanks = False
        self.lua.eval("S.CheckRanks()")
        self.assertEqual(self.g.UPGRADES, 0)
        self.assertEqual(self.told(), ["OLD_RANKS"])


if __name__ == "__main__":
    unittest.main()

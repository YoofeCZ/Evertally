"""Evertally's loot window (LootWindow.lua): off by default; on, it takes the corpse by hand in its own look, with auto
loot takes everything at once and then shows what came in, leaves master loot to the game's frame, and switches only
the game's loot frame's LOOT_OPENED off (and back on), writing nothing of Blizzard's."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_addon import MOCK_UI_LUA, runtime

FAKE = r"""
  SLOTS = {
    {icon = 1, name = "Silk Cloth", count = 3, quality = 1, link = "|Hitem:4306|h[Silk Cloth]|h"},
    {icon = 2, name = "Wolfskin Bracers", count = 1, quality = 2, link = "|Hitem:6070|h[Wolfskin Bracers]|h"},
  }
  TAKEN, CLOSED = {}, 0
  GetNumLootItems = function() return #SLOTS end
  GetLootSlotInfo = function(i) local s = SLOTS[i]; if s then return s.icon, s.name, s.count, nil, s.quality, false end end
  GetLootSlotLink = function(i) return SLOTS[i] and SLOTS[i].link end
  GetLootSlotType = function() return 1 end
  LootSlot = function(i) TAKEN[#TAKEN + 1] = i end
  CloseLoot = function() CLOSED = CLOSED + 1 end
  CVARS = {autoLootDefault = "0"}
  GetCVar = function(k) return CVARS[k] end
  IsModifiedClick = function() return false end
  LOOT_METHOD = "freeforall"
  GetLootMethod = function() return LOOT_METHOD end
  GAME_EVENTS, GAME_OPENED = {LOOT_OPENED = true}, 0
  LootFrame = CreateFrame("Frame")
  rawset(LootFrame, "UnregisterEvent", function(self, ev) GAME_EVENTS[ev] = nil end)
  rawset(LootFrame, "RegisterEvent", function(self, ev) GAME_EVENTS[ev] = true end)
  rawset(LootFrame, "GetScript", function(self, what) if what == "OnEvent" then return function() GAME_OPENED = GAME_OPENED + 1 end end end)
"""


class LootWindowTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = runtime()
        self.lua.execute(MOCK_UI_LUA)
        self.lua.execute(FAKE)
        self.lw = self.a.LootWindow
        self.g = self.lua.globals()

    def shown_rows(self):
        return self.lua.eval("(function() local n = 0; for _, r in ipairs(EvertallyLootWindow.rows) do if r:IsShown() then n = n + 1 end end; return n end)()")

    def test_off_by_default_the_game_keeps_its_frame(self):
        self.assertFalse(self.lw.Enabled())
        self.lw.OnOpened(False)
        self.assertIsNone(self.g.EvertallyLootWindow)
        self.assertTrue(self.g.GAME_EVENTS["LOOT_OPENED"])

    def test_by_hand_the_window_lists_the_corpse_and_a_click_takes_one(self):
        self.lw.SetEnabled(True)
        self.assertIsNone(self.g.GAME_EVENTS["LOOT_OPENED"], "the game's frame no longer opens")
        self.lw.OnOpened(False)
        self.assertTrue(self.g.EvertallyLootWindow.IsShown(self.g.EvertallyLootWindow))
        self.assertEqual(self.shown_rows(), 2)
        self.lw.TakeAll()
        self.assertEqual(list(self.g.TAKEN.values()), [1, 2])
        self.lw.Close()
        self.assertEqual(self.g.CLOSED, 1)
        self.lw.SetEnabled(False)
        self.assertTrue(self.g.GAME_EVENTS["LOOT_OPENED"], "off: the game's frame listens again")

    def test_auto_loot_takes_everything_and_shows_what_came_in(self):
        self.lw.SetEnabled(True)
        self.g.CVARS.autoLootDefault = "1"
        self.lw.OnReady(None)
        self.assertEqual(sorted(self.g.TAKEN.values()), [1, 2])
        self.lua.execute("SLOTS = {}")
        self.lw.OnOpened(True)
        self.assertFalse(bool(self.g.EvertallyLootWindow and self.g.EvertallyLootWindow.IsShown(self.g.EvertallyLootWindow)),
                         "nothing left: no window to click")
        self.lw.OnClosed()
        self.assertTrue(self.g.EvertallyLootWindow.IsShown(self.g.EvertallyLootWindow), "the toast")
        self.assertEqual(self.shown_rows(), 2)
        text = self.lua.eval("EvertallyLootWindow.rows[1].name:GetText()")
        self.assertIn("+3", str(text))

    def test_master_loot_is_left_to_the_game(self):
        self.lw.SetEnabled(True)
        self.g.LOOT_METHOD = "master"
        self.lw.OnOpened(False)
        self.assertEqual(self.g.GAME_OPENED, 1)
        self.assertIsNone(self.g.EvertallyLootWindow)


if __name__ == "__main__":
    unittest.main()

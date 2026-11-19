"""Drawers (DrawerMacro.lua): an entry dragged from the cursor, the secure buttons' attributes (set out of combat only,
a change in combat waits for its end), the toggle that /click reaches (a "click" action on the secure handler) and the
macro written for the action bar."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_addon import MOCK_UI_LUA, runtime

FAKE = r"""
  local make = CreateFrame
  ATTR = {}
  CreateFrame = function(kind, name, parent, template)
    local f = make(kind, name, parent)
    rawset(f, "template", template)
    rawset(f, "attrs", {})
    rawset(f, "SetAttribute", function(self, k, v) self.attrs[k] = v end)
    rawset(f, "GetAttribute", function(self, k) return self.attrs[k] end)
    rawset(f, "SetFrameRef", function(self, k, v) self.attrs["frameref-" .. k] = v end)
    if name then _G[name] = f end
    return f
  end
  CURSOR = nil
  GetCursorInfo = function() if CURSOR then return unpack(CURSOR) end end
  ClearCursor = function() CURSOR = nil end
  GetItemIcon = function(id) return 1000 + id end
  GetSpellInfo = function(id) return "Spell " .. id end
  GetSpellTexture = function() return 7 end
  GetItemCount = function() return 3 end
  COMBAT = false
  InCombatLockdown = function() return COMBAT end
  MACROS, PICKED = {}, nil
  GetMacroIndexByName = function(n) for i, m in ipairs(MACROS) do if m.name == n then return i end end return 0 end
  CreateMacro = function(n, icon, body) MACROS[#MACROS + 1] = {name = n, body = body}; return #MACROS end
  EditMacro = function(i, n, icon, body) MACROS[i].body = body end
  PickupMacro = function(i) PICKED = i end
  GetMacroInfo = function(i) local m = MACROS[i] or {}; return m.name, 5 end
"""


class DrawerTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = runtime()
        self.lua.execute(MOCK_UI_LUA)
        self.lua.execute(FAKE)
        self.dm = self.a.Drawers
        self.g = self.lua.globals()

    def test_a_dropped_item_and_spell_become_secure_buttons(self):
        self.dm.Show()
        self.assertEqual(len(self.dm.List()), 1, "the window starts with one drawer")
        self.lua.execute('CURSOR = {"item", 6948}')
        self.lua.execute("EvertallyDrawers.rows[1].slots[1].scripts.OnReceiveDrag(EvertallyDrawers.rows[1].slots[1])")
        self.assertIsNone(self.g.CURSOR, "taken off the cursor")
        self.lua.execute('CURSOR = {"spell", 3, "spell", 8690}')
        self.lua.execute("EvertallyDrawers.rows[1].slots[2].scripts.OnReceiveDrag(EvertallyDrawers.rows[1].slots[2])")
        b1, b2 = self.g.EvertallyDrawer1Slot1, self.g.EvertallyDrawer1Slot2
        self.assertEqual(b1.attrs.type, "item"); self.assertEqual(b1.attrs.item, "item:6948")
        self.assertEqual(b2.attrs.type, "spell"); self.assertEqual(b2.attrs.spell, "Spell 8690")
        self.assertEqual(b1.template, "SecureActionButtonTemplate")
        # the toggle /click reaches: a click action on the secure handler, whose snippet shows or hides the tray
        t = self.g.EvertallyDrawer1
        self.assertEqual(t.template, "SecureActionButtonTemplate")
        self.assertEqual(t.attrs.type, "click")
        h = t.attrs.clickbutton
        self.assertEqual(h.template, "SecureHandlerClickTemplate")
        self.assertIn("tray:Show()", h.attrs._onclick)
        self.assertTrue(self.lua.eval("EvertallyDrawer1.attrs.clickbutton.attrs['frameref-tray'] == EvertallyDrawerTray1"))

    def test_in_combat_the_change_waits_for_its_end(self):
        self.dm.Add()
        self.g.COMBAT = True
        self.lua.execute('Evertally.db.settings.drawers[1].entries = {{kind = "item", id = 159}}')
        self.assertFalse(self.dm.Apply())
        self.assertIsNone(self.g.EvertallyDrawer1Slot1)
        self.g.COMBAT = False
        self.a.Dispatch("PLAYER_REGEN_ENABLED")
        self.assertEqual(self.g.EvertallyDrawer1Slot1.attrs.item, "item:159")

    def test_the_macro_clicks_the_drawer_and_lands_on_the_cursor(self):
        i = self.dm.Add()
        self.assertTrue(self.dm.MakeMacro(i))
        m = self.g.MACROS[1]
        self.assertIn("/click EvertallyDrawer1", m.body)
        self.assertIn("#evertally:drawer 1", m.body)
        self.assertEqual(self.g.PICKED, 1)
        self.assertTrue(self.dm.MakeMacro(i))
        self.assertEqual(len(self.g.MACROS), 1, "made once, found the next time")


if __name__ == "__main__":
    unittest.main()

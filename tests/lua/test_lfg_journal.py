"""The Dungeon Journal category in the game's Looking For Group window (LfgJournal.lua)."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_addon import runtime, MOCK_UI_LUA

WINDOW = """
LFGListingFrame=CreateFrame("Frame","LFGListingFrame",UIParent)
local view=CreateFrame("Frame",nil,LFGListingFrame);LFGListingFrame.CategoryView=view
view.CategoryButtons={CreateFrame("Button",nil,view),CreateFrame("Button",nil,view),CreateFrame("Button",nil,view)}
view.CategoryButtons[3]:Hide()
HOOKED={};hooksecurefunc=function(name,fn) HOOKED[name]=fn end
LFGListingCategorySelection_UpdateCategoryButtons=function() end
OPENED=nil;Evertally.OpenUI=function() end;Evertally.ShowView=function(v) OPENED=v end
"""


class LfgJournalTests(unittest.TestCase):
    def test_a_button_under_the_last_shown_category_opens_the_journal(self):
        lua, a = runtime(); lua.execute(MOCK_UI_LUA); lua.execute(WINDOW)
        self.assertTrue(a.LfgJournal.Attach())
        self.assertFalse(a.LfgJournal.Attach(), "once only")
        b = lua.globals().EvertallyLfgJournalCategory
        self.assertTrue(b.IsShown(b)); self.assertEqual(b.text, a.L("lfgJournal"))
        self.assertIsNotNone(lua.globals().HOOKED.LFGListingCategorySelection_UpdateCategoryButtons, "follows the window's own updates")
        b.scripts.OnClick(b)
        self.assertEqual(lua.globals().OPENED, "dungeons")

    def test_no_window_no_button(self):
        lua, a = runtime(); lua.execute(MOCK_UI_LUA)
        self.assertFalse(a.LfgJournal.Attach())


if __name__ == "__main__":
    unittest.main()

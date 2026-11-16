"""The "What can I train?" tab in the game's spellbook (SpellbookTraining.lua): grouping, the page over the book, its tab."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_addon import MOCK_UI_LUA
from test_training import training_runtime

CATALOG = ("Evertally.trainingData={classes={DRUID={spells={{id=10,level=1,baseCost=10},{id=11,level=10,baseCost=300},"
           "{id=12,level=11,baseCost=500},{id=13,level=12,baseCost=500},{id=14,level=20,baseCost=900}},overrides={}}},"
           "questSpells={DRUID={}},trainers={}}")
BOOK = """
    PlayerSpellsFrame=CreateFrame("Frame","PlayerSpellsFrame",UIParent)
    PlayerSpellsFrame.NineSlice=CreateFrame("Frame",nil,PlayerSpellsFrame)
    PlayerSpellsFrame.SpellBookFrame=CreateFrame("Frame",nil,PlayerSpellsFrame)
    PlayerSpellsFrame.SpellBookFrame.CategoryTabSystem=CreateFrame("Frame",nil,PlayerSpellsFrame.SpellBookFrame)
    PlayerSpellsFrame.SpellBookFrame.SearchBox=CreateFrame("EditBox",nil,PlayerSpellsFrame.SpellBookFrame)
"""


class SpellbookTrainingTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = training_runtime()
        self.lua.execute(MOCK_UI_LUA)
        self.lua.execute(CATALOG + "; KNOWN[10]=true")
        self.a.Training.Invalidate(False)
        self.s = self.a.SpellbookTraining

    def test_spells_fall_into_now_soon_and_later(self):
        lines, _ = self.s.Lines(10)
        got = [(str(lines[i].header) if lines[i].header else lines[i].row.id) for i in range(1, len(lines) + 1)]
        self.assertEqual(got, ["now", 11, "soon", 12, 13, "later", 14], "known spell 10 left out; soon = up to two levels ahead")

    def test_the_tab_opens_a_page_over_the_book_and_the_book_closing_puts_it_away(self):
        self.lua.execute(BOOK)
        self.assertTrue(self.s.Attach())
        self.assertFalse(self.s.Attach(), "once only")
        tab = self.lua.globals().EvertallySpellbookTrainingTab
        page = self.lua.globals().EvertallySpellbookTraining
        self.assertFalse(page.IsShown(page))
        tab.scripts.OnClick(tab)
        self.assertTrue(page.IsShown(page)); self.assertTrue(tab.glow.IsShown(tab.glow))
        self.assertEqual(page.rows[1].name.text, self.a.L("sbNow") + "  •  1")
        self.assertEqual(page.rows[2].name.text, "Spell 11")
        self.assertIn("|cffffd700", page.total.text, "the total is money")
        tab.scripts.OnClick(tab)
        self.assertFalse(page.IsShown(page))
        self.s.SetEnabled(False)
        self.assertFalse(tab.IsShown(tab))
        self.assertIs(self.a.db.settings.spellbookTraining, False)

    def test_no_book_no_tab(self):
        self.assertFalse(self.s.Attach())
        self.assertIsNone(self.lua.globals().EvertallySpellbookTrainingTab)


if __name__ == "__main__":
    unittest.main()

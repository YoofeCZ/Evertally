"""Evertally drawn in Evertally Guide's look (Theme.lua scheme "guide"): with the guide's theme its palette becomes
Evertally's (skin and accent), shapes are square, tabs are underlined, the font is the guide's; a new skin in the guide
repaints Evertally; a scheme chosen by hand stays; without the guide nothing changes."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_addon import MOCK_UI_LUA, runtime

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "ui_preview"))

FAKE_THEME = r'''
CHANGED = {}
PAL = {
  bg = {0.095, 0.115, 0.178, 0.97}, panel = {0.11, 0.133, 0.203, 0.98}, panelAlt = {0.139, 0.166, 0.249, 1},
  sidebar = {0.072, 0.088, 0.14, 1}, sky = {0.156, 0.196, 0.329, 1},
  text = {0.967, 0.974, 0.991, 1}, textDim = {0.765, 0.793, 0.868, 1}, textMuted = {0.606, 0.637, 0.726, 1},
  accent = {0.9, 0.73, 0.4, 1}, border = {1, 1, 1, 0.1}, divider = {1, 1, 1, 0.1},
}
EvertallyGuide = {Theme = {
  Palette = function() return PAL end,
  FontSpec = function(role) return "Interface\\AddOns\\Evertally_Guide\\Media\\Fonts\\Inter-" .. role .. ".ttf", 13, "" end,
  OnChanged = function(fn) CHANGED[#CHANGED + 1] = fn end,
}}
'''


class GuideLookTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = runtime()
        self.lua.execute(MOCK_UI_LUA)

    def near(self, a, b):
        for i in (1, 2, 3):
            self.assertAlmostEqual(a[i], b[i], places=3)

    def test_without_the_guide_the_night_scheme_stays(self):
        self.assertEqual(self.a.Theme.ApplyScheme(), "night")
        self.assertFalse(self.a.Theme.Flat())
        self.assertFalse(self.a.Theme.SetScheme("guide"))

    def test_the_guides_palette_becomes_evertallys(self):
        self.lua.execute(FAKE_THEME)
        self.assertEqual(self.a.Theme.ApplyScheme(), "guide")
        self.assertTrue(self.a.Theme.Flat())
        C = self.a.Theme.colors
        self.near(C.gold, [None, 0.9, 0.73, 0.4])
        self.near(C.text, [None, 0.967, 0.974, 0.991])
        self.near(C.canvas, [None, 0.095, 0.115, 0.178])
        self.assertGreater(C.card[1], C.canvas[1], "panels a touch lighter than the ground")
        tex = self.lua.eval("CreateFrame")("Frame").CreateTexture(self.lua.eval("CreateFrame")("Frame"))
        self.assertFalse(self.a.Theme.Shape(tex, "round"), "square in the guide's look")

    def test_a_new_skin_in_the_guide_repaints_evertally(self):
        self.lua.execute(FAKE_THEME)
        self.a.Theme.ApplyScheme()
        self.lua.execute("Evertally.Theme.followsGuide=nil; for _, fn in ipairs(Evertally.handlers.PLAYER_LOGIN or {}) do pcall(fn) end")
        changed = self.lua.globals().CHANGED
        self.assertGreaterEqual(len(changed), 1, "Evertally listens to the guide's theme")
        self.lua.execute("PAL.accent = {0.2, 0.6, 0.9, 1}")
        changed[1]()
        self.near(self.a.Theme.colors.gold, [None, 0.2, 0.6, 0.9])

    def test_a_scheme_chosen_by_hand_stays(self):
        self.lua.execute(FAKE_THEME)
        self.assertTrue(self.a.Theme.SetScheme("dusk"))
        self.assertEqual(self.a.Theme.SchemeKey(), "dusk")
        self.assertFalse(self.a.Theme.Flat())
        self.assertTrue(self.a.Theme.SetScheme("guide"))
        self.assertEqual(self.a.Theme.SchemeKey(), "guide")

    def test_the_font_is_the_guides(self):
        self.lua.execute(FAKE_THEME)
        self.a.Theme.ApplyScheme()
        self.assertIn("Inter-body", str(self.a.FontPath()))
        self.assertTrue(self.a.SetUIFont("game"))
        self.assertNotIn("Inter", str(self.a.FontPath()))

    def test_every_page_draws_in_the_guides_look_without_overlaps(self):
        import preview
        preview.GUIDE_LOOK = True
        try:
            for view in ("overview", "journal", "settings", "talents", "rankings"):
                lua, a = preview.make_session(1120, 740, language="cs")
                self.assertTrue(a.Theme.Flat())
                nodes = preview.capture(lua, a, view, "")
                problems = [p for p in preview.lint(nodes) if "overlap" in p]
                self.assertEqual(problems, [], view)
        finally:
            preview.GUIDE_LOOK = False


if __name__ == "__main__":
    unittest.main()

"""Evertally and Evertally Guide share one window, so what both can do is done once (stage 4): while the guide scores
gear (its tooltip, quest reward marks, bag arrows), Evertally's own step back; the guide's Talents ("Coming soon" in
Polestar 0.4.0.1) leave the hub's rail and its command opens Evertally's Talents."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_addon import MOCK_UI_LUA, runtime

ROOT = Path(__file__).resolve().parents[2]
FAKE_GEAR = r'''
GUIDE_SET = {["gear.tooltip"] = true, ["gear.rewards"] = true, ["gear.bagArrows"] = true}
GUIDE_GEAR_ON = true
EvertallyGuide = {Gear = {IsEnabled = function() return GUIDE_GEAR_ON end}, Get = function(path) return GUIDE_SET[path] end}
'''


class GuideMergeTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = runtime()
        self.lua.execute(MOCK_UI_LUA)

    def test_without_the_guide_evertallys_gear_marks_stay(self):
        self.assertFalse(self.a.Gear.GuideHas("tooltip"))
        self.assertTrue(self.a.BagHighlight.Enabled())

    def test_the_guides_gear_parts_take_over_each_on_its_own(self):
        self.lua.execute(FAKE_GEAR)
        G, B = self.a.Gear, self.a.BagHighlight
        self.assertTrue(G.GuideHas("tooltip") and G.GuideHas("rewards") and G.GuideHas("bagArrows"))
        self.assertFalse(B.Enabled(), "one arrow per bag item: the guide's")
        tooltip = self.lua.eval("{GetItem=function() return 'x', 'y', '|cff1eff00|Hitem:2488::::::::20:::::|h[Gladius]|h|r' end, AddLine=function() error('drawn twice') end, Show=function() end}")
        self.assertFalse(G.AppendTooltip(tooltip), "no second gear line in the tooltip")
        self.lua.execute('GUIDE_SET["gear.bagArrows"] = false')
        self.assertTrue(B.Enabled(), "the guide's arrows off: Evertally's come back")
        self.lua.execute("GUIDE_GEAR_ON = false")
        self.assertFalse(G.GuideHas("tooltip"), "the guide's gear switched off: Evertally scores again")

    def test_the_guides_talents_leave_the_rail_while_they_are_coming_soon(self):
        view = (ROOT / "addon" / "Evertally_Guide" / "Talents" / "View.lua").read_text(encoding="latin-1")
        self.assertIn("if UI.RegisterSection and not T.SOON then", view)
        self.assertIn('E.ShowView("talents")', view)
        talents = (ROOT / "addon" / "Evertally_Guide" / "Talents" / "Talents.lua").read_text(encoding="latin-1")
        self.assertIn("T.SOON = true", talents, "when Polestar ships its talents this test asks to look again")

    def test_the_bag_setting_says_who_draws_the_arrows(self):
        for lang in ("en", "cs"):
            self.assertTrue(self.a.locale[lang]["bagHighlightGuide"])


if __name__ == "__main__":
    unittest.main()

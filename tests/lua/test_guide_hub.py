"""The Leveling page: the way into Evertally Guide (the Evertally_Guide add-ons, from Polestar). Each button runs the
guide's own command; without the guide loaded the page says how to turn it on and its buttons do nothing."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_addon import MOCK_UI_LUA, runtime


class GuideHubTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = runtime()
        self.lua.execute(MOCK_UI_LUA)

    def page(self):
        body = self.lua.eval("CreateFrame")("Frame", None, None)
        body.SetSize(body, 760, 520)
        self.a.BuildLevelingPage(body, self.a.UIKit())
        body.Refresh()
        return body, body["leveling"]

    def test_without_the_guide_the_page_says_how_to_turn_it_on(self):
        body, hub = self.page()
        self.assertTrue(hub.missing.shown)
        self.assertEqual(str(hub.missing.text), self.a.L("lvMissing"))
        self.assertFalse(self.a.RunGuide("lookup"))
        self.assertIn("Polestar", str(hub.credit.text), "the authors are credited")

    def test_every_button_runs_its_guide_command(self):
        self.lua.execute("RAN={}; EvertallyGuide={RunCommand=function(cmd) RAN[#RAN+1]=cmd end}")
        body, hub = self.page()
        self.assertFalse(hub.missing.shown)
        rows = [hub.rows[i] for i in range(1, len(hub.rows) + 1)]
        for row in rows:
            row.button.scripts.OnClick(row.button)
        ran = [self.lua.globals().RAN[i] for i in range(1, len(rows) + 1)]
        self.assertEqual(ran, ["show", "guides", "lookup", "rares", "alts", "dungeons", "gear", "talents", "options", "install"])
        self.assertEqual(str(rows[2].button.text.text), self.a.L("lvLookup"))

    def test_the_page_is_in_the_menu_in_both_languages(self):
        for lang in ("en", "cs"):
            self.assertTrue(self.a.locale[lang]["leveling"] and self.a.locale[lang]["sub_leveling"], lang)


if __name__ == "__main__":
    unittest.main()

"""Evertally's settings as pages of Evertally Guide's settings window (EvertallySettings.lua): one group "Evertally",
every control reads and writes Evertally's own settings through get/set, set(nil) (the guide's Reset page) puts the
default back, and the menu's Settings opens that window. The guide's window is faked here; its rule for a control
without a key of its own (Theme/Widgets.lua checkControl) is checked against the real file."""
from pathlib import Path
import re
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_addon import MOCK_UI_LUA, runtime
from test_guide_shell import FAKE_GUIDE

ROOT = Path(__file__).resolve().parents[2]
FAKE_OPTIONS = r'''
SPECS, OPENED, FIRED = {}, {}, {}
EvertallyGuide = EvertallyGuide or {UI = {}}
EvertallyGuide.RegisterOptions = function(spec) SPECS[#SPECS + 1] = spec; return true end
EvertallyGuide.UI.ShowOptions = function(key) OPENED[#OPENED + 1] = key end
EvertallyGuide.Fire = function(msg, path) FIRED[#FIRED + 1] = path end
'''


class GuideSettingsTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = runtime()
        self.lua.execute(MOCK_UI_LUA)

    def install(self, hub=False):
        if hub:
            self.lua.execute(FAKE_GUIDE)
            self.assertTrue(self.a.InstallGuideShell())
        self.lua.execute(FAKE_OPTIONS)
        self.assertTrue(self.a.InstallGuideSettings())
        specs = self.lua.globals().SPECS
        return [specs[i] for i in range(1, len(specs) + 1)]

    def controls(self, specs):
        for spec in specs:
            for i in range(1, len(spec.controls) + 1):
                yield spec, spec.controls[i]

    def find(self, specs, key):
        for _, c in self.controls(specs):
            if c.localeKey == key:
                return c
        raise AssertionError(key)

    def test_without_the_guide_nothing_is_registered(self):
        self.assertFalse(self.a.InstallGuideSettings())
        self.assertFalse(self.a.ShowGuideSettings())

    def test_one_group_of_pages_every_control_valid_and_named_in_both_languages(self):
        specs = self.install()
        self.assertEqual([s.key for s in specs], ["evertallysharing", "evertallylive", "evertallyweb", "evertallyinterface",
                                                  "evertallyplates", "evertallymusic", "evertallyactions", "evertallydiagnostics"])
        self.assertTrue(all(s.group == "evertally" for s in specs))
        self.assertTrue(all(s.custom for s in specs if s.key in ("evertallyplates", "evertallymusic", "evertallydiagnostics")))
        for _, c in self.controls(specs):
            if c.kind == "button":
                self.assertTrue(callable(c.onClick))
            else:
                self.assertIn(c.kind, ("toggle", "dropdown"))
                self.assertIsNone(c.key, "no key of the guide's: the values are Evertally's")
                self.assertTrue(callable(c.get) and callable(c.set))
            for lang in ("en", "cs"):
                self.assertNotEqual(self.a.locale[lang][c.localeKey] or self.a.locale.en[c.localeKey], None, (lang, c.localeKey))
        widgets = (ROOT / "addon" / "Evertally_Guide" / "Theme" / "Widgets.lua").read_text(encoding="latin-1")
        self.assertIn('c.key == nil and type(c.get) == "function" and type(c.set) == "function"', widgets,
                      "the guide still takes a control without a key when it has get and set")
        options = (ROOT / "addon" / "Evertally_Guide_Options" / "UI" / "Options.lua").read_text(encoding="latin-1")
        self.assertRegex(options, r'local GROUPS = \{\n\t\{ key = "evertally", label = "Evertally" \},', "the group leads the sidebar")

    def test_toggles_write_evertallys_settings_and_reset_puts_the_default_back(self):
        specs = self.install()
        settings = self.a.db.settings
        rank = self.find(specs, "rankTooltip")
        rank.set(False)
        self.assertFalse(rank.get())
        self.assertFalse(settings.rankTooltip)
        rank.set(None)
        self.assertTrue(rank.get(), "Reset page: on again")
        share, group = self.find(specs, "share"), self.find(specs, "group")
        share.set(False)
        self.assertTrue(group.disabled(), "the party row waits for sharing")
        share.set(True)
        self.assertTrue(settings.ingame)
        self.assertFalse(group.disabled())
        fired = self.lua.globals().FIRED
        self.assertIn("evertally.share", [fired[i] for i in range(1, len(fired) + 1)], "rows greyed by a rule look again")

    def test_the_language_is_a_dropdown_of_both(self):
        specs = self.install()
        lang = self.find(specs, "language")
        choices = lang.choices()
        self.assertEqual([choices[i].value for i in range(1, len(choices) + 1)], ["en", "cs"])
        lang.set("cs")
        self.assertEqual(self.a.db.settings.language, "cs")
        self.assertEqual(lang.get(), "cs")
        lang.set(None)
        self.assertEqual(lang.get(), "en")

    def test_the_menus_settings_open_the_guides_window(self):
        self.install(hub=True)
        self.a.ShowView("settings")
        opened = self.lua.globals().OPENED
        self.assertEqual(opened[1], "evertallysharing")
        section = self.lua.globals().SECTIONS[1]
        section.onNav("settings")
        self.assertEqual(len(opened), 2)
        self.assertFalse(self.a.guideShell.Shown("settings"), "the hub keeps its page; the settings are a window")

    def test_czech_in_evertally_loads_the_guide_in_czech(self):
        self.lua.execute("""LOADED={}; USED=nil
          C_AddOns={LoadAddOn=function(name) LOADED[#LOADED+1]=name; return true end}
          EvertallyGuide={GuideTexts={UseLanguage=function(loc) USED=loc end}}""")
        self.a.db.settings.language = "en"
        self.assertFalse(self.a.ApplyGuideLanguage(), "English: the guide stays English")
        self.a.db.settings.language = "cs"
        self.assertTrue(self.a.ApplyGuideLanguage())
        g = self.lua.globals()
        self.assertEqual(g.EvertallyGuide.EvertallyLanguage, "csCZ")
        self.assertEqual(g.USED, "csCZ")
        self.assertEqual(g.LOADED[1], "Evertally_Guide_csCZ")
        self.assertTrue(self.a.ApplyGuideLanguage())
        self.assertEqual(len(g.LOADED), 1, "once")

if __name__ == "__main__":
    unittest.main()

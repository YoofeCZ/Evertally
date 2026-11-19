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
        # (2026-11-19: sharing, live and website are one page in three tabs; the interface one page in three sections)
        keys = []
        for spec in specs:
            if spec.key not in keys: keys.append(spec.key)
        self.assertEqual(keys, ["evertallysharing", "evertallyinterface", "evertallybags", "evertallyplates", "evertallymusic", "evertallyactions",
                                "evertallydiagnostics"])
        tabs = [spec.tab for spec in specs if spec.key == "evertallysharing"]
        self.assertEqual(tabs, ["In game", "Live & map", "Website"])
        self.assertTrue(all(s.group == "evertally" for s in specs))
        self.assertTrue(all(s.custom for s in specs if s.key in ("evertallyplates", "evertallymusic", "evertallydiagnostics")))
        for _, c in self.controls(specs):
            if c.kind == "button":
                self.assertTrue(callable(c.onClick))
            else:
                self.assertIn(c.kind, ("toggle", "dropdown", "slider"))
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

    def test_a_new_language_reloads_the_ui_at_once_the_same_one_does_not(self):
        # (the guide reads its texts when it loads: a language changed without a reload left it in English)
        self.lua.execute("RELOADS = 0; ReloadUI = function() RELOADS = RELOADS + 1 end; "
                         "C_Timer = C_Timer or {}; C_Timer.After = function(_, fn) fn() end")
        g = self.lua.globals()
        self.a.db.settings.language = "en"
        self.assertTrue(self.a.SetLanguage("en"))
        self.assertEqual(g.RELOADS, 0, "the same language: no reload")
        self.assertTrue(self.a.SetLanguage("cs"))
        self.assertEqual(self.a.db.settings.language, "cs", "saved before the reload")
        self.assertEqual(g.RELOADS, 1)
        self.assertTrue(self.a.SetLanguage("cs"))
        self.assertEqual(g.RELOADS, 1)
        self.assertTrue(self.a.SetLanguage("en"))
        self.assertEqual(g.RELOADS, 2, "back to English too")


class GuideOptionsWindowTests(unittest.TestCase):
    """The real guide's settings window (preview harness): every setting has one home and the merged pages are one
    page, in English and in Czech. (2026-11-19: in Czech the rules missed every registration that gave only its
    translated page name; 20 settings stayed on two pages.)"""

    def dump(self, czech):
        import json, os, subprocess, tempfile
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "options.json"
            env = dict(os.environ, QUESTS="1", DUMP_OPTIONS=str(out))
            env.pop("CS", None)
            if czech: env["CS"] = "1"
            subprocess.run([sys.executable, str(ROOT / "tools" / "ui_preview" / "guide_preview.py"),
                            "Evertally_Guide,Evertally_Guide_SkinAPI,Evertally_Guide_Options,Evertally_Guide_Guides,"
                            "Evertally_Guide_Guides_Horde,Evertally_Guide_Guides_Scourge", "--skin"],
                           env=env, cwd=str(ROOT), capture_output=True, timeout=300)
            self.assertTrue(out.exists(), "the preview dumped the options")
            return [r for r in json.loads(out.read_text(encoding="utf8")) if r]

    def test_one_home_per_setting_in_both_languages(self):
        for czech in (False, True):
            rows = self.dump(czech)
            pages = [r["key"] for r in rows if r.get("kind") == "page"]
            for gone in ("routelines", "trackers"):
                self.assertNotIn(gone, pages, "merged into another page")
            self.assertIn("mappins", pages)
            self.assertIn("alerts", pages)
            seen = {}
            for r in rows:
                key = r.get("key")
                if r.get("kind") != "control" or key in (None, "", "nil"): continue
                seen.setdefault(key, []).append(r.get("page"))
            twice = {k: v for k, v in seen.items() if len(v) > 1}
            self.assertEqual(twice, {}, "czech" if czech else "english")


if __name__ == "__main__":
    unittest.main()

"""One setup (SetupPages.lua): Evertally's steps are pages of Evertally Guide's Install window. The window itself is
faked here (UI.WelcomeHost / WelcomeKit / Welcome): what is checked is what Evertally hands it and how it answers.
The look is checked in tools/ui_preview/guide_preview.py (SETUP=<page key>) on the real window."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_addon import MOCK_UI_LUA, runtime, ADDON

FAKE_HOST = r"""
HOSTED, SHOWN_PAGE, OPEN = {}, nil, false
EvertallyGuide = {UI = {
  WelcomeHost = function(spec) HOSTED[#HOSTED + 1] = spec; return true end,
  WelcomeKit = {CW = 536, refresh = function() end},
  Welcome = {Show = function(key) SHOWN_PAGE = key; OPEN = true end, IsShown = function() return OPEN end, Hide = function() OPEN = false end},
}}
"""


class SetupPagesTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = runtime()
        self.lua.execute(MOCK_UI_LUA)
        self.lua.execute(FAKE_HOST)
        # SetupPages.lua registered at load, before the fake host: hand the pages over now
        self.assertTrue(self.a.setupPages.Register())
        self.ui = self.lua.globals().EvertallyGuide.UI

    def hosted(self):
        return list(self.lua.globals().HOSTED.values())

    def test_every_step_is_a_page_after_the_guides_welcome_the_summary_before_its_finish(self):
        pages = self.hosted()
        keys = [str(p.key) for p in pages]
        # (no website and public pages since 2026-11-18: everything is public)
        self.assertEqual(keys, ["et-language", "et-install", "et-pair", "et-live", "et-sharing",
                                "et-map", "et-window", "et-tracker", "et-bags", "et-combat", "et-plates", "et-music", "et-summary"])
        afters = [str(p.after) for p in pages]
        self.assertEqual(afters[0], "welcome", "right after the guide's welcome")
        self.assertEqual(afters[1:-1], keys[:-2], "each after the one before")
        self.assertEqual(afters[-1], "look", "the summary after the guide's own pages, before its finish")
        self.assertEqual(str(self.ui.WelcomeOwner), "Evertally", "Evertally decides when the window opens")

    def test_the_installation_check_and_the_pairing_do_not_hold_next_back(self):
        # (2026-11-20: the app and OpenMap are optional)
        pages = {str(p.key): p for p in self.hosted()}
        self.a.BridgePaired = self.lua.eval("function() return false end")
        for key in ("et-install", "et-pair", "et-live"):
            self.assertIsNone(pages[key].blocked, key)

    def test_the_setup_opens_in_the_guides_window_at_the_step_and_finish_applies_the_draft(self):
        self.a.OpenOnboarding(None)
        self.assertTrue(self.a.OnboardingShown())
        self.assertIsNone(self.lua.globals().SHOWN_PAGE, "the first page")
        self.a.OpenOnboarding(2)
        self.assertEqual(self.lua.globals().SHOWN_PAGE, "et-install")
        self.a.OpenOnboarding(5)
        self.assertEqual(self.lua.globals().SHOWN_PAGE, "et-live", "the public step is passed over (2026-11-18)")
        self.assertIsNone(self.lua.globals().EvertallySetup, "Evertally's own window is not built")
        # the window's Finish: the draft is applied (as Onboarding.lua's own Finish)
        self.a.RequirementsReady = self.lua.eval("function() return true end")
        self.ui.WelcomeOnOpen()
        draft = self.a.SetupDraft()
        draft.language = "cs"
        self.ui.WelcomeOnFinish()
        self.assertEqual(self.a.db.settings.onboarded, 8)
        self.assertEqual(self.a.db.settings.language, "cs")
        self.a.OnboardingClose()
        self.assertFalse(self.a.OnboardingShown())

    def test_texts_in_both_languages(self):
        for lang in ("en", "cs"):
            for key in ("setupLangTitle", "setupQuickTitle", "setupSizeTitle", "setupMusicSource", "setupSpotifyIdTitle", "setupHostSumTitle"):
                self.assertTrue(self.a.locale[lang][key], (lang, key))
        self.assertIn("SetupPages.lua", (ADDON / "Evertally.toc").read_text(encoding="utf8"))


if __name__ == "__main__":
    unittest.main()

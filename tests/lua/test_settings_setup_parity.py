"""Everything the setup can set can be set in Evertally's settings too (EvertallySettings.lua), on the same saved
values the setup writes: the quest tracker (et-tracker), the bags (et-bags) on their own page with the loot window, the
tracked items and the categories, the gathering places and their kinds (et-map), the window's size (et-window) and the
pairing (et-pair). The bags picked switch the other bag add-ons off only after a reload: the setup's Finish and the
settings reload the UI when the loaded bag add-ons disagree with the choice (2026-11-19: Bagnon opened beside
Evertally's bags after the setup)."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_addon import MOCK_UI_LUA, runtime
from test_guide_settings import FAKE_OPTIONS

# Which settings controls (locale keys) stand for each page of the setup. A new setup page fails the coverage test
# until it is listed here with its controls in the settings.
SETUP_TO_SETTINGS = {
    "et-language": ["language"],
    "et-install": ["installVerify"],
    "et-pair": ["setPairRow", "bridgeAutostart"],
    "et-live": ["liveParty", "liveGuild", "liveFriends", "liveWeb"],
    "et-sharing": ["share", "group", "guild", "socialEnabled", "presence"],
    "et-map": ["setupGather", "setupKind_herb", "setupKind_ore", "setupKind_fishing", "setupKind_container", "mapPins"],
    "et-window": ["minimap", "uiScaleLabel"],
    "et-tracker": ["qtPickTitle"],
    "et-bags": ["bwPickLabel"],
    "et-plates": None,      # the nameplate editor: the same panel (A.BuildFriendlyPlateControls) on its own page
    "et-music": None,       # the music page (custom): on, source, Spotify id
    "et-summary": [],
}
CUSTOM_PAGES = {"et-plates": "evertallyplates", "et-music": "evertallymusic"}

ADDONS = r"""
  ENABLED = {Bagnon = true}
  LOADED = {Bagnon = true}
  C_AddOns = {
    GetAddOnInfo = function(n) if n == "Bagnon" then return n, "Bagnon", "", true, nil end; return nil, nil, nil, false, "MISSING" end,
    IsAddOnLoaded = function(n) return LOADED[n] == true end,
    GetAddOnEnableState = function(n) return ENABLED[n] and 2 or 0 end,
    DisableAddOn = function(n) ENABLED[n] = false end, EnableAddOn = function(n) ENABLED[n] = true end}
  RELOADS = 0; ReloadUI = function() RELOADS = RELOADS + 1 end
  C_Timer = {After = function(_, fn) fn() end}
  PRINTED = {}; Evertally.Print = function(m) PRINTED[#PRINTED + 1] = m end
"""


class SettingsSetupParityTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = runtime()
        self.lua.execute(MOCK_UI_LUA)
        self.lua.execute(FAKE_OPTIONS)
        self.assertTrue(self.a.InstallGuideSettings())
        specs = self.lua.globals().SPECS
        self.specs = [specs[i] for i in range(1, len(specs) + 1)]
        self.s = self.a.db.settings

    def control(self, key):
        for spec in self.specs:
            for i in range(1, len(spec.controls) + 1):
                c = spec.controls[i]
                if c.localeKey == key:
                    return spec, c
        raise AssertionError(key)

    def test_every_setup_page_has_its_choices_in_the_settings(self):
        pages = self.a.setupPages.pages
        keys = [str(pages[i].key) for i in range(1, len(pages) + 1)]
        self.assertEqual(sorted(keys), sorted(SETUP_TO_SETTINGS), "a setup page without its settings listed here")
        page_keys = {spec.key for spec in self.specs}
        for page, controls in SETUP_TO_SETTINGS.items():
            if controls is None:
                self.assertIn(CUSTOM_PAGES[page], page_keys)
                continue
            for key in controls:
                _, c = self.control(key)
                for lang in ("en", "cs"):
                    self.assertIsNotNone(self.a.locale[lang][key], (lang, key))

    def test_the_bags_have_their_own_page(self):
        bag_keys = ["bwPickLabel", "lootWindow", "bwTrackHide", "bagHighlight", "bwCats"]
        for key in bag_keys:
            spec, _ = self.control(key)
            self.assertEqual(spec.key, "evertallybags", key)
        spec, _ = self.control("bwPickLabel")
        self.assertEqual(spec.page, "Bags")
        self.assertIsNone(next((c for s in self.specs for c in s.controls.values() if c.localeKey == "bwReplace"), None),
                          "the bag choice stands for the old switch")
        self.assertEqual(self.a.locale.cs.bagsSection, "Batoh")

    def test_quest_tracker_is_the_setups_choice(self):
        _, c = self.control("qtPickTitle")
        values = [str(v.value) for v in c.choices().values()]
        self.assertEqual(values, ["evertally", "blizzard"])
        self.assertIsNone(c.get(), "nothing picked yet, as before the setup")
        c.set("blizzard")
        self.assertEqual(self.a.QuestTracker.Choice(), "blizzard")
        self.assertEqual(self.s.questTracker.choice, "blizzard")
        self.a.SetQuestTrackerChoice("evertally")   # what the setup page calls
        self.assertEqual(c.get(), "evertally")
        c.set(None)
        self.assertEqual(c.get(), "evertally", "Reset page: Evertally's")

    def test_the_bag_choice_is_the_setups_and_reloads_when_an_addon_changes(self):
        self.lua.execute(ADDONS)
        g = self.lua.globals()
        _, c = self.control("bwPickLabel")
        values = [str(v.value) for v in c.choices().values()]
        self.assertEqual(values, ["evertally", "game", "Bagnon"])
        c.set("evertally")
        self.assertEqual(self.s.bagWindow.choice, "evertally")
        self.assertEqual(self.a.BagWindow.Choice(), "evertally", "what the setup's page reads")
        self.assertFalse(g.ENABLED.Bagnon)
        self.assertEqual(g.RELOADS, 1, "Bagnon is still loaded until the UI reloads")

    def test_the_setups_finish_reloads_when_the_bags_disagree_with_the_choice(self):
        self.lua.execute(ADDONS)
        g = self.lua.globals()
        self.a.BagWindow.SetChoice("evertally")   # the setup's bag page
        self.assertEqual(g.RELOADS, 0, "not while the setup is open")
        self.a.SetupDraft()
        self.a.OnboardingFinish()
        self.assertEqual(g.RELOADS, 1)

    def test_no_reload_when_the_loaded_bags_agree(self):
        self.lua.execute(ADDONS)
        g = self.lua.globals()
        g.LOADED.Bagnon = False
        g.ENABLED.Bagnon = False
        self.a.BagWindow.SetChoice("evertally")
        self.assertIsNone(self.a.BagWindow.Mismatch())
        self.assertFalse(self.a.BagWindow.ReloadIfNeeded())
        self.assertEqual(g.RELOADS, 0)

    def test_login_with_a_bag_addon_against_the_choice_switches_it_off_and_says_so(self):
        self.lua.execute(ADDONS)
        g = self.lua.globals()
        self.s.bagWindow = self.lua.eval("{choice = 'evertally'}")
        self.a.Dispatch("PLAYER_LOGIN")
        self.assertFalse(g.ENABLED.Bagnon)
        printed = [str(g.PRINTED[i]) for i in range(1, len(g.PRINTED) + 1)]
        self.assertTrue(any("Bagnon" in p and "/reload" in p for p in printed), printed)

    def test_loot_tracked_items_and_categories(self):
        _, loot = self.control("lootWindow")
        loot.set(True)
        self.assertTrue(self.s.lootWindow)
        _, hide = self.control("bwTrackHide")
        self.assertTrue(hide.get())
        hide.set(False)
        self.assertFalse(self.s.bagWindow.trackHide)
        self.assertFalse(self.a.BagWindow.TrackHides(), "the bag window's gear menu reads the same")
        hide.set(None)
        self.assertTrue(self.a.BagWindow.TrackHides())
        _, cats = self.control("bwCats")
        shown = []
        self.a.BagWindow.Categories.Show = lambda *a: shown.append(True)
        cats.onClick()
        self.assertEqual(shown, [True])

    def test_gathering_and_its_kinds_are_the_setups_values(self):
        _, gather = self.control("setupGather")
        _, ore = self.control("setupKind_ore")
        self.assertTrue(gather.get(), "on until switched off, as in the setup")
        ore.set(False)
        self.assertFalse(self.s.gatherTypes.ore)
        self.assertFalse(self.a.OnboardingDraft().kinds.ore, "the setup reads the same")
        gather.set(False)
        self.assertFalse(self.s.mapLayers.gather)
        self.assertTrue(ore.disabled(), "the kinds wait for the gathering places")
        self.assertFalse(self.a.OnboardingDraft().layers.gather)
        gather.set(None)
        self.assertTrue(self.s.mapLayers.gather)

    def test_window_size_is_the_setups_scale(self):
        _, c = self.control("uiScaleLabel")
        self.assertEqual(c.kind, "slider")
        self.assertEqual((c.min, c.max), (0.6, 1.6))
        c.set(1.2)
        self.assertAlmostEqual(self.s.uiScale, 1.2)
        self.assertAlmostEqual(self.a.OnboardingDraft().scale, 1.2, msg="the setup's Large")
        self.assertEqual(c.format(0.85), "85 %")
        c.set(None)
        self.assertAlmostEqual(self.a.GetUIScale(), 1)

    def test_pairing_is_a_button_greyed_once_paired(self):
        _, c = self.control("setPairRow")
        self.assertEqual(c.kind, "button")
        self.assertEqual(c.button, "Pair")
        asked = []
        self.a.RequestPairing = lambda: asked.append(True)
        c.onClick()
        self.assertEqual(asked, [True])
        self.a.BridgePaired = lambda: True
        self.assertTrue(c.disabled())
        self.a.BridgePaired = lambda: False
        self.assertFalse(c.disabled())


if __name__ == "__main__":
    unittest.main()

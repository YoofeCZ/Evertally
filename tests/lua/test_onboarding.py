"""The setup (first start): what the choices are, how they agree with each other, what they do when applied, the steps, skipping and when it opens."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_addon import MOCK_UI_LUA, runtime

OPENMAP = "OpenMapAPI={RegisterMenuToggle=function() end}"
KINDS = ("herb", "ore", "fishing", "container")


def lst(table):
    return [table[i] for i in range(1, len(table) + 1)] if table is not None else []


class OnboardingTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = runtime()
        self.lua.execute(MOCK_UI_LUA)
        self.lua.execute("date=os.date; InCombatLockdown=function() return false end")

    def draft(self):
        return self.a.OnboardingDraft()

    # ---- the choices ----
    def test_a_new_player_starts_with_everything_that_sends_something_off(self):
        d = self.draft()
        self.assertFalse(d.web); self.assertFalse(d.liveWeb); self.assertFalse(d.ingame)
        self.assertFalse(d.live.party or d.live.guild or d.live.friends)
        self.assertEqual(str(d.language), "en")
        self.assertTrue(d.minimap)

    def test_the_quick_choices_set_the_switches_and_stay_visible_as_switches(self):
        d = self.draft()
        self.a.OnboardingPreset(d, "recommended")
        self.assertTrue(d.web)
        self.assertEqual([bool(d.scopes[k]) for k in ("world_facts", "own_runs", "own_character", "own_professions", "own_track")], [True, True, True, True, False], "everything but the route")
        self.a.OnboardingPreset(d, "everything")
        self.assertTrue(d.scopes.own_track)
        self.a.OnboardingPreset(d, "local_only")
        self.assertFalse(d.web)
        self.assertFalse(any(d.scopes[k] for k in ("world_facts", "own_runs", "own_character", "own_professions", "own_track")))

    def test_choices_that_need_each_other_agree(self):
        d = self.draft()
        d.liveWeb = True
        self.a.OnboardingNormalize(d)
        self.assertTrue(d.web and d.scopes.own_character and d.scopes.own_track, "the live position on the website needs the website, the character and the route")

    def test_gathering_starts_on_for_every_kind_and_follows_what_was_saved(self):
        d = self.draft()
        self.assertTrue(d.layers.gather)
        self.assertTrue(all(d.kinds[k] for k in KINDS))
        self.a.db.settings.mapLayers = self.lua.table(gather=False)
        self.a.db.settings.gatherTypes = self.lua.table(ore=False)
        d = self.draft()
        self.assertFalse(d.layers.gather)
        self.assertEqual([bool(d.kinds[k]) for k in KINDS], [True, False, True, True])

    # ---- applying ----
    def test_applying_does_what_the_settings_page_does(self):
        d = self.draft()
        self.a.OnboardingPreset(d, "recommended")
        d.language = "cs"; d.live.party = True; d.ingame = True; d.guild = True; d.social = False
        d.layers.gather = False; d.kinds.ore = False; d.kinds.herb = True; d.mapPins = True; d.minimap = False; d.scale = 1.2
        self.a.db.settings.ownMap = True   # (left over from the map window Evertally had)
        self.a.db.settings.mapLayers = self.lua.table(trainer=True)
        before = self.a.db.settings.consentEpoch
        notes = self.a.OnboardingApply(d)
        s = self.a.db.settings
        self.assertEqual(len(lst(notes)), 0)
        self.assertEqual(str(s.language), "cs")
        self.assertTrue(s.web); self.assertGreater(s.consentEpoch, before, "a new policy starts a new consent")
        self.assertTrue(s.scopes.own_professions); self.assertFalse(s.scopes.own_track)
        self.assertTrue(s.ingame and s.liveParty and s.guild); self.assertFalse(s.social)
        self.assertIsNone(s.ownMap, "the old map-window setting is cleared"); self.assertTrue(s.mapPins)
        self.assertFalse(s.mapLayers.gather); self.assertTrue(s.mapLayers.trainer, "the other layers are left as they were")
        self.assertFalse(s.gatherTypes.ore); self.assertTrue(s.gatherTypes.herb)
        self.assertTrue(s.hideMinimap); self.assertAlmostEqual(self.a.GetUIScale(), 1.2)
        self.assertEqual(s.onboarded, 3)

    def test_nothing_changes_for_what_was_not_touched(self):
        s = self.a.db.settings
        before = (s.consentEpoch, bool(s.web))
        d = self.draft()
        self.a.OnboardingApply(d)
        self.assertEqual((s.consentEpoch, bool(s.web)), before, "no change of policy, no new consent")
        self.assertFalse(s.liveParty or s.liveGuild or s.liveFriends or s.ingame)

    def test_the_website_stays_off_with_a_note_when_the_export_helper_is_missing(self):
        self.lua.execute("EvertallyExportDB=nil")
        d = self.draft()
        self.a.OnboardingPreset(d, "everything"); d.liveWeb = True
        notes = [str(n) for n in lst(self.a.OnboardingApply(d))]
        self.assertEqual(notes, ["export_missing"])
        self.assertFalse(self.a.db.settings.web); self.assertFalse(self.a.db.settings.liveWeb, "the live position on the website needs the website")

    def test_the_summary_says_what_will_be_on(self):
        d = self.draft()
        lines = [str(x) for x in lst(self.a.OnboardingSummary(d))]
        self.assertEqual(len(lines), 8)
        self.assertIn("nameplates", lines[7].lower())
        self.assertIn("off", lines[1].lower()); self.assertIn("nothing", lines[2])
        self.assertIn("not installed", lines[4], "no OpenMap: the summary says so")
        self.assertIn("Herbs", lines[5]); self.assertIn("Chests", lines[5])
        self.lua.execute(OPENMAP)
        self.a.OnboardingPreset(d, "recommended"); d.live.guild = True; d.liveWeb = True; d.kinds.fishing = False
        lines = [str(x) for x in lst(self.a.OnboardingSummary(d))]
        self.assertIn("on (", lines[1]); self.assertIn("guild", lines[2]); self.assertIn("website", lines[2])
        self.assertIn("OpenMap", lines[4]); self.assertNotIn("not installed", lines[4])
        self.assertNotIn("Fishing", lines[5], "a kind that is switched off is not listed")
        d.layers.gather = False
        self.assertIn("off", str(lst(self.a.OnboardingSummary(d))[5]))

    # ---- the window ----
    def open(self):
        self.a.OpenOnboarding()
        return self.a.onboarding.window

    def test_the_steps_lead_from_the_language_to_a_finish_that_applies_everything(self):
        f = self.open()
        self.assertTrue(self.a.OnboardingShown())
        step, draft = self.a.OnboardingState()
        self.assertEqual(step, 1)
        pages = self.a.onboarding.pages
        pages[1].languages["cs"].scripts.OnClick(pages[1].languages["cs"])
        self.assertEqual(str(self.a.db.settings.language), "cs", "the language is chosen at once, so the rest is read in it")
        for expected in range(2, 10):
            f.next.scripts.OnClick(f.next)
            self.assertEqual(self.a.OnboardingState()[0], expected)
        self.assertEqual(str(f.next.text.text), self.a.L("setupFinish"), "the last step ends with Finish")
        f.back.scripts.OnClick(f.back)
        self.assertEqual(self.a.OnboardingState()[0], 8)
        self.a.OnboardingGo(2)
        pages[2].presets["recommended"].scripts.OnClick(pages[2].presets["recommended"])
        self.a.OnboardingGo(9)
        f.next.scripts.OnClick(f.next)
        self.assertFalse(self.a.OnboardingShown())
        self.assertTrue(self.a.db.settings.web); self.assertEqual(self.a.db.settings.onboarded, 3)

    def test_skipping_keeps_the_settings_and_does_not_ask_again(self):
        f = self.open()
        pages = self.a.onboarding.pages
        self.a.OnboardingGo(2)
        pages[2].presets["everything"].scripts.OnClick(pages[2].presets["everything"])
        f.skip.scripts.OnClick(f.skip)
        self.assertFalse(self.a.OnboardingShown())
        self.assertFalse(self.a.db.settings.web, "skipping applies nothing")
        self.assertEqual(self.a.db.settings.onboarded, 3)

    def test_a_switch_that_needs_others_shows_what_it_switches_on(self):
        self.open()
        pages = self.a.onboarding.pages
        self.a.OnboardingGo(3)
        pages[3].liveWeb.scripts.OnClick(pages[3].liveWeb)
        step, draft = self.a.OnboardingState()
        self.assertTrue(draft.liveWeb and draft.web and draft.scopes.own_track)
        self.assertNotEqual(str(pages[3].needs.text), "", "it says what else is switched on")
        self.a.OnboardingGo(2)
        self.assertFalse(pages[2].scopes["own_track"].enabled, "and the route cannot be switched off while the live position needs it")
        pages[2].web.scripts.OnClick(pages[2].web)
        step, draft = self.a.OnboardingState()
        self.assertFalse(draft.web or draft.liveWeb, "switching the website off takes the live position on it with it")

    def test_the_map_step_says_openmap_is_the_map_and_sets_what_evertally_adds_to_it(self):
        self.open()
        pages = self.a.onboarding.pages
        self.a.OnboardingGo(5)
        self.assertEqual(str(pages[5].body.text), self.a.L("setupMapBodyNone"), "no OpenMap: the step says the map features need it")
        self.lua.execute(OPENMAP)
        self.a.OpenOnboarding(5)
        self.assertEqual(str(pages[5].body.text), self.a.L("setupMapBodyOpenMap"))
        self.assertEqual(sorted(str(k) for k in pages[5].kinds.keys()), sorted(KINDS))
        ore = pages[5].kinds["ore"]
        ore.scripts.OnClick(ore)
        self.assertFalse(self.a.OnboardingState()[1].kinds.ore, "a click takes that kind off")
        pages[5].gather.scripts.OnClick(pages[5].gather)
        self.assertFalse(self.a.OnboardingState()[1].layers.gather)
        pages[5].pins.scripts.OnClick(pages[5].pins)
        self.assertFalse(self.a.OnboardingState()[1].mapPins)

    def test_the_install_step_gives_the_addresses_of_the_app_and_of_openmap_to_copy(self):
        self.open()
        pages = self.a.onboarding.pages
        self.a.OnboardingGo(8)
        page = pages[8]
        self.assertEqual(str(page.app.link.url), "https://evertally.afstudio.dev/#sync", "the Download page of the website")
        self.assertEqual(str(page.openmap.link.url), "https://www.curseforge.com/wow/addons/openmap")
        self.assertEqual(str(page.openmap.status.text), self.a.L("setupGetMissing"), "no OpenMap here: it says so")
        self.lua.execute(OPENMAP)
        self.a.OpenOnboarding(8)
        self.assertEqual(str(page.openmap.status.text), self.a.L("setupGetInstalled"))
        link = page.openmap.link
        link.scripts.OnEditFocusGained(link)   # (a click selects it all, ready for Ctrl+C)
        link.SetText(link, "typed over")
        link.scripts.OnTextChanged(link, True)
        self.assertEqual(str(link.text), str(link.url), "the address cannot be edited")

    # ---- when it opens by itself ----
    def test_it_opens_once_after_the_world_is_there_and_never_in_combat(self):
        self.lua.execute("C_Timer={After=function(s,fn) fn() end}")
        self.lua.execute("INCOMBAT=true; InCombatLockdown=function() return INCOMBAT end")
        self.a.Dispatch("PLAYER_ENTERING_WORLD")
        self.assertFalse(self.a.OnboardingShown(), "not in combat")
        self.lua.execute("INCOMBAT=false")
        self.a.Dispatch("PLAYER_REGEN_ENABLED")
        self.assertTrue(self.a.OnboardingShown(), "when the fight is over")
        self.a.onboarding.window.Hide(self.a.onboarding.window)
        self.a.Dispatch("PLAYER_ENTERING_WORLD")
        self.assertFalse(self.a.OnboardingShown(), "once per session")

    def test_it_does_not_open_for_someone_who_has_done_it(self):
        self.lua.execute("C_Timer={After=function(s,fn) fn() end}")
        self.a.db.settings.onboarded = 3
        self.a.Dispatch("PLAYER_ENTERING_WORLD")
        self.assertFalse(self.a.OnboardingShown())
        self.lua.execute('SlashCmdList.EVERTALLY("setup")')
        self.assertTrue(self.a.OnboardingShown(), "/etally setup opens it any time")

    def test_previous_setup_version_offers_the_new_nameplate_choices(self):
        self.lua.execute("C_Timer={After=function(s,fn) fn() end}")
        self.a.db.settings.onboarded = 1
        self.a.Dispatch("PLAYER_ENTERING_WORLD")
        self.assertTrue(self.a.OnboardingShown())

    def plate_cvars(self):
        self.lua.execute('''
            CVARS={nameplateShowFriendlyPlayers="0",nameplateShowOnlyNameForFriendlyPlayerUnits="0"}; CVAR_WRITES=0
            C_CVar={GetCVar=function(k) return CVARS[k] end,SetCVar=function(k,v) CVARS[k]=v;CVAR_WRITES=CVAR_WRITES+1 end}
        ''')

    def test_nameplate_choice_activates_before_live_controls_are_shown(self):
        self.plate_cvars()
        self.a.OpenOnboarding(7)
        editor = self.a.onboarding.pages[7].plates
        self.assertTrue(editor.choosing)
        self.assertFalse(editor.config.shown)
        editor.providers.evertally.scripts.OnClick(editor.providers.evertally)
        self.assertTrue(self.a.FriendlyPlatesShown())
        self.assertFalse(editor.choosing)
        self.assertTrue(editor.config.shown)
        editor.controls.plateFontSize.plus.scripts.OnClick(editor.controls.plateFontSize.plus)
        self.assertEqual(self.a.db.settings.plateFontSize, 16)
        self.assertEqual(editor.preview.frame.name.fontSize, 16)
        self.assertTrue(editor.preview.frame.IsShown(editor.preview.frame))
        self.assertEqual(self.a.OnboardingState()[1].plates.plateFontSize, 16)
        self.a.OnboardingSkip()
        self.assertEqual(self.a.db.settings.plateFontSize, 16, 'explicit live changes stay applied when other setup choices are skipped')

    def test_blizzard_choice_restores_native_names_and_preserves_custom_options(self):
        self.plate_cvars()
        self.a.OpenOnboarding(7)
        editor = self.a.onboarding.pages[7].plates
        editor.providers.evertally.scripts.OnClick(editor.providers.evertally)
        editor.controls.plateLogoSize.plus.scripts.OnClick(editor.controls.plateLogoSize.plus)
        editor.change.scripts.OnClick(editor.change)
        editor.providers.blizzard.scripts.OnClick(editor.providers.blizzard)
        self.assertFalse(self.a.FriendlyPlatesShown())
        self.assertFalse(self.a.db.settings.plateGameLook)
        self.assertEqual(self.a.db.settings.plateLogoSize, 13)
        self.assertTrue(editor.choosing)

    def test_nameplate_choice_is_refused_in_combat_and_stays_on_choice_page(self):
        self.plate_cvars()
        self.a.OpenOnboarding(7)
        editor = self.a.onboarding.pages[7].plates
        self.lua.execute('InCombatLockdown=function() return true end')
        editor.providers.evertally.scripts.OnClick(editor.providers.evertally)
        self.assertEqual(self.lua.globals().CVAR_WRITES, 0)
        self.assertTrue(editor.choosing)

    def test_live_editor_bounds_fonts_and_saved_settings_are_shared(self):
        self.plate_cvars()
        self.a.db.settings.plateFontSize = 32
        self.a.OpenOnboarding(7)
        editor = self.a.onboarding.pages[7].plates
        editor.providers.evertally.scripts.OnClick(editor.providers.evertally)
        editor.controls.plateFontSize.plus.scripts.OnClick(editor.controls.plateFontSize.plus)
        editor.controls.plateFont.plus.scripts.OnClick(editor.controls.plateFont.plus)
        self.assertEqual(self.a.db.settings.plateFontSize, 32)
        self.assertEqual(self.a.db.settings.plateFont, 'friz')
        self.a.OnboardingSkip()
        self.a.ShowView('settings')
        page = self.a.settingsPage
        page.SelectSection(5)
        page.plates.controls.plateFontSize.minus.scripts.OnClick(page.plates.controls.plateFontSize.minus)
        self.a.OpenOnboarding(7)
        self.assertEqual(str(editor.controls.plateFontSize.value.text), '31')



if __name__ == "__main__":
    unittest.main()

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
        # the app reports a paired PC; the pairing step has its own tests below
        self.a.bridgeInstallation = self.lua.table(schemaVersion=1, paired=True, autostart=False)

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
        self.assertEqual(s.onboarded, 7)

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
        self.assertEqual(len(lines), 12)
        self.assertIn("nameplates", lines[10].lower())
        self.assertIn("music", lines[11].lower())
        self.assertIn("paired", lines[1]); self.assertNotIn("not paired", lines[1])
        self.assertIn("off", lines[2].lower()); self.assertIn("off", lines[3].lower(), "no public page")
        self.assertIn(self.a.L("setupChron_off"), lines[4], "no chronicle"); self.assertIn("nothing", lines[5])
        self.assertIn("not installed", lines[7], "no OpenMap: the summary says so")
        self.assertIn("Herbs", lines[8]); self.assertIn("Chests", lines[8])
        self.lua.execute(OPENMAP)
        self.a.OnboardingPreset(d, "recommended"); d.live.guild = True; d.liveWeb = True; d.kinds.fishing = False
        lines = [str(x) for x in lst(self.a.OnboardingSummary(d))]
        self.assertIn("on (", lines[2]); self.assertIn("guild", lines[5]); self.assertIn("website", lines[5])
        self.assertIn(self.a.L("setupChron_private"), lines[4], "the live position needs the route: a chronicle only for the player")
        self.assertIn("OpenMap", lines[7]); self.assertNotIn("not installed", lines[7])
        self.assertNotIn("Fishing", lines[8], "a kind that is switched off is not listed")
        d.layers.gather = False
        self.assertIn("off", str(lst(self.a.OnboardingSummary(d))[8]))

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
        self.assertEqual(str(pages[1].title.text), self.a.L("setupWelcomeTitle"), "the language comes first, so the rest is read in it")
        pages[1].languages["cs"].scripts.OnClick(pages[1].languages["cs"])
        self.assertEqual(str(self.a.db.settings.language), "cs", "the language is chosen at once")
        f.next.scripts.OnClick(f.next)
        self.assertEqual(self.a.OnboardingState()[0], 2, "then the installation")
        f.next.scripts.OnClick(f.next)
        self.assertEqual(self.a.OnboardingState()[0], 3, "then pairing")
        for expected in range(4, 13):
            f.next.scripts.OnClick(f.next)
            self.assertEqual(self.a.OnboardingState()[0], expected)
        self.assertEqual(str(f.next.text.text), self.a.L("setupFinish"), "the last step ends with Finish")
        f.back.scripts.OnClick(f.back)
        self.assertEqual(self.a.OnboardingState()[0], 11)
        self.a.OnboardingGo(4)
        pages[4].presets["recommended"].scripts.OnClick(pages[4].presets["recommended"])
        self.a.OnboardingGo(12)
        f.next.scripts.OnClick(f.next)
        self.assertFalse(self.a.OnboardingShown())
        self.assertTrue(self.a.db.settings.web); self.assertEqual(self.a.db.settings.onboarded, 7)

    def test_the_music_step_turns_the_player_on_with_the_chosen_service(self):
        self.open()
        pages = self.a.onboarding.pages
        self.lua.execute("SENTCMD={};Evertally.OpticalSendCommand=function(t) SENTCMD[#SENTCMD+1]=t;return true end")
        self.a.OnboardingGo(11)
        page = pages[11]
        self.assertFalse(page.id.IsShown(page.id), "the Client ID field waits for the player switch")
        page.enable.scripts.OnClick(page.enable)
        self.assertTrue(page.id.IsShown(page.id), "Spotify is the first choice and asks for its Client ID")
        page.sources["youtube"].scripts.OnClick(page.sources["youtube"])
        self.assertFalse(page.id.IsShown(page.id))
        page.sources["spotify"].scripts.OnClick(page.sources["spotify"])
        _, draft = self.a.OnboardingState()
        draft.spotifyId = "0123456789abcdef0123456789abcdef"
        self.a.OnboardingFinish()
        self.assertTrue(self.a.Music.Enabled())
        sent = self.lua.globals().SENTCMD
        self.assertEqual([sent[i] for i in range(1, len(sent) + 1)], ["m:src:spotify", "m:spid:0123456789abcdef0123456789abcdef"])

    def test_a_setup_that_fails_to_open_is_tried_again_at_the_next_loading_screen(self):
        self.lua.execute("TIMERS={};C_Timer={After=function(d,fn) TIMERS[#TIMERS+1]=fn end,NewTicker=function() end};function RunTimers() local l=TIMERS;TIMERS={};for _,f in ipairs(l) do f() end end")
        self.a.db.settings.onboarded = None
        self.lua.execute("REALOPEN=Evertally.OpenOnboarding;Evertally.OpenOnboarding=function() error('not yet') end")
        self.a.Dispatch("PLAYER_ENTERING_WORLD"); self.lua.execute("RunTimers()")
        self.assertFalse(self.a.OnboardingShown())
        self.assertEqual(self.a.errors.onboarding, 1)
        self.lua.execute("Evertally.OpenOnboarding=REALOPEN")
        self.a.Dispatch("PLAYER_ENTERING_WORLD"); self.lua.execute("RunTimers()")
        self.assertTrue(self.a.OnboardingShown(), "the next loading screen shows it")

    def test_closing_keeps_the_settings_without_completing_setup(self):
        f = self.open()
        pages = self.a.onboarding.pages
        self.a.OnboardingGo(4)
        pages[4].presets["everything"].scripts.OnClick(pages[4].presets["everything"])
        f.close.scripts.OnClick(f.close)
        self.assertFalse(self.a.OnboardingShown())
        self.assertFalse(self.a.db.settings.web, "skipping applies nothing")
        self.assertIsNone(self.a.db.settings.onboarded)

    def test_a_switch_that_needs_others_shows_what_it_switches_on(self):
        self.open()
        pages = self.a.onboarding.pages
        self.a.OnboardingGo(6)
        pages[6].liveWeb.scripts.OnClick(pages[6].liveWeb)
        step, draft = self.a.OnboardingState()
        self.assertTrue(draft.liveWeb and draft.web and draft.scopes.own_track)
        self.assertNotEqual(str(pages[6].needs.text), "", "it says what else is switched on")
        self.a.OnboardingGo(4)
        self.assertFalse(pages[4].scopes["own_track"].enabled, "and the route cannot be switched off while the live position needs it")
        pages[4].web.scripts.OnClick(pages[4].web)
        step, draft = self.a.OnboardingState()
        self.assertFalse(draft.web or draft.liveWeb, "switching the website off takes the live position on it with it")

    def test_the_map_step_says_openmap_is_the_map_and_sets_what_evertally_adds_to_it(self):
        self.open()
        pages = self.a.onboarding.pages
        self.a.OnboardingGo(8)
        self.assertEqual(str(pages[8].body.text), self.a.L("setupMapBodyNone"), "no OpenMap: the step says the map features need it")
        self.lua.execute(OPENMAP)
        self.a.OpenOnboarding(8)
        self.assertEqual(str(pages[8].body.text), self.a.L("setupMapBodyOpenMap"))
        self.assertEqual(sorted(str(k) for k in pages[8].kinds.keys()), sorted(KINDS))
        ore = pages[8].kinds["ore"]
        ore.scripts.OnClick(ore)
        self.assertFalse(self.a.OnboardingState()[1].kinds.ore, "a click takes that kind off")
        pages[8].gather.scripts.OnClick(pages[8].gather)
        self.assertFalse(self.a.OnboardingState()[1].layers.gather)
        pages[8].pins.scripts.OnClick(pages[8].pins)
        self.assertFalse(self.a.OnboardingState()[1].mapPins)

    def test_the_install_step_has_buttons_and_opens_the_requested_download_dialog(self):
        self.open()
        pages = self.a.onboarding.pages
        self.a.OnboardingGo(2)
        page = pages[2]
        self.assertIsNone(page.install.rows.bridge.link)
        self.assertIsNone(page.install.rows.openmap.link)
        page.install.rows.bridge.open.scripts.OnClick(page.install.rows.bridge.open)
        self.assertEqual(str(self.a.installationLinkWindow.address.url), "https://evertally.afstudio.dev/#sync")
        page.install.rows.openmap.open.scripts.OnClick(page.install.rows.openmap.open)
        self.assertEqual(str(self.a.installationLinkWindow.address.url), "https://www.curseforge.com/wow/addons/openmap")
        self.assertEqual(str(page.install.rows.openmap.status.text), self.a.L("installMissing"), "no OpenMap here: it says so")
        self.lua.execute(OPENMAP)
        self.a.OpenOnboarding(2)
        self.assertEqual(str(page.install.rows.openmap.status.text), self.a.L("installPresent"))
        link = self.a.installationLinkWindow.address
        link.scripts.OnEditFocusGained(link)   # (a click selects it all, ready for Ctrl+C)
        link.SetText(link, "typed over")
        link.scripts.OnTextChanged(link, True)
        self.assertEqual(str(link.text), str(link.url), "the address cannot be edited")

    # ---- pairing with the app ----
    def test_the_setup_goes_no_further_than_pairing_until_the_app_is_paired(self):
        self.a.bridgeInstallation.paired = False
        f = self.open()
        pages = self.a.onboarding.pages
        self.a.OnboardingGo(7)
        self.assertEqual(self.a.OnboardingState()[0], 3, "no way past the pairing step")
        f.next.scripts.OnClick(f.next)
        self.assertEqual(self.a.OnboardingState()[0], 3)
        self.assertEqual(str(pages[3].status.text), self.a.L("setupPairNot"))
        self.assertTrue(pages[3].pair.shown)
        self.a.bridgeInstallation.paired = None
        self.a.OnboardingGo(3)
        self.assertEqual(str(pages[3].status.text), self.a.L("setupPairOld"), "an app that does not report it is asked to update")
        self.a.bridgeInstallation.paired = True
        self.a.OnboardingGo(3)
        self.assertEqual(str(pages[3].status.text), self.a.L("setupPairDone"))
        self.assertFalse(pages[3].pair.shown, "nothing to pair any more")
        f.next.scripts.OnClick(f.next)
        self.assertEqual(self.a.OnboardingState()[0], 4)

    def test_pair_saves_a_request_for_the_app_and_reloads_so_the_game_writes_it(self):
        self.lua.execute("RELOADS=0; ReloadUI=function() RELOADS=RELOADS+1 end")
        self.a.bridgeInstallation.paired = False
        self.open()
        page = self.a.onboarding.pages[3]
        self.a.OnboardingGo(3)
        page.pair.scripts.OnClick(page.pair)
        self.assertEqual(self.lua.globals().RELOADS, 1)
        self.assertGreater(self.a.db.bridgeRequest.pairAt, 0)
        self.a.OnboardingGo(3)
        self.assertEqual(str(page.status.text), self.a.L("setupPairWaiting"), "after the reload it says where to look")
        self.lua.execute("InCombatLockdown=function() return true end")
        page.pair.scripts.OnClick(page.pair)
        self.assertEqual(self.lua.globals().RELOADS, 1, "never a reload in combat")

    def test_start_with_wow_is_a_request_for_the_app_and_shows_what_the_app_reports(self):
        self.open()
        page = self.a.onboarding.pages[3]
        self.a.OnboardingGo(3)
        self.assertFalse(self.a.BridgeAutostart())
        self.assertIn(self.a.L("setupOff"), str(page.autostartState.text))
        page.autostart.scripts.OnClick(page.autostart)
        self.assertTrue(self.a.db.bridgeRequest.autostart)
        self.assertGreater(self.a.db.bridgeRequest.autostartAt, 0)
        self.assertTrue(self.a.BridgeAutostart(), "the player's choice shows until the app reports it")
        self.assertTrue(self.a.webChangePending, "it reaches the app only when the game saves")

    def test_the_chronicle_is_off_only_for_me_or_public_and_public_needs_the_public_page(self):
        f = self.open()
        page = self.a.onboarding.pages[5]
        self.a.OnboardingGo(5)
        self.assertEqual(str(page.title.text), self.a.L("setupPublicTitle"))
        self.assertTrue(page.chronicle["off"].selected, "a new player sends no chronicle")
        self.assertEqual(str(page.publish.sub.text), self.a.L("setupPublicSub"), "the public page says it is the leaderboard")
        page.chronicle["private"].scripts.OnClick(page.chronicle["private"])
        step, draft = self.a.OnboardingState()
        self.assertEqual(str(self.a.OnboardingChronicle(draft)), "private")
        self.assertTrue(draft.web and draft.scopes.own_track); self.assertFalse(draft.publish, "only for me is not public")
        page.chronicle["public"].scripts.OnClick(page.chronicle["public"])
        step, draft = self.a.OnboardingState()
        self.assertTrue(draft.chronicle and draft.publish and draft.web and draft.scopes.own_character and draft.scopes.own_track,
                        "a public chronicle needs the public page, the character and the route")
        page.publish.scripts.OnClick(page.publish)
        step, draft = self.a.OnboardingState()
        self.assertEqual(str(self.a.OnboardingChronicle(draft)), "private", "without the public page the chronicle cannot stay public")
        self.assertFalse(page.extras["gear"].enabled, "the extras of the public page need it")
        page.chronicle["public"].scripts.OnClick(page.chronicle["public"])
        self.a.OnboardingGo(12)
        f.next.scripts.OnClick(f.next)
        choice = self.a.PublishChoice()
        self.assertTrue(choice.public and choice.chronicle)
        self.assertTrue(self.a.SaveBarShown(), "after Finish a bar offers to save for the website right away")

    def test_the_position_on_the_website_keeps_the_route_so_the_chronicle_cannot_be_off(self):
        self.open()
        pages = self.a.onboarding.pages
        self.a.OnboardingGo(6)
        pages[6].liveWeb.scripts.OnClick(pages[6].liveWeb)
        self.a.OnboardingGo(5)
        pages[5].chronicle["off"].scripts.OnClick(pages[5].chronicle["off"])
        step, draft = self.a.OnboardingState()
        self.assertEqual(str(self.a.OnboardingChronicle(draft)), "private")
        self.assertEqual(str(pages[5].note.text), self.a.L("setupChronLocked"))

    def test_a_website_choice_in_settings_offers_to_save_now(self):
        self.a.SetPublish("public", True)
        self.assertTrue(self.a.SaveBarShown())

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
        self.a.db.settings.onboarded = 7
        self.a.Dispatch("PLAYER_ENTERING_WORLD")
        self.assertFalse(self.a.OnboardingShown())
        self.lua.execute('SlashCmdList.EVERTALLY("setup")')
        self.assertTrue(self.a.OnboardingShown(), "/etally setup opens it any time")

    def test_delayed_automatic_open_does_not_reopen_a_manually_closed_setup(self):
        self.lua.execute('C_Timer={After=function(_,fn) PENDING_SETUP=fn end}')
        self.a.Dispatch("PLAYER_ENTERING_WORLD")
        self.a.OpenOnboarding();self.a.OnboardingClose()
        self.lua.globals().PENDING_SETUP()
        self.assertFalse(self.a.OnboardingShown())

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
        self.a.OpenOnboarding(10)
        editor = self.a.onboarding.pages[10].plates
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
        self.a.OpenOnboarding(10)
        editor = self.a.onboarding.pages[10].plates
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
        self.a.OpenOnboarding(10)
        editor = self.a.onboarding.pages[10].plates
        self.lua.execute('InCombatLockdown=function() return true end')
        editor.providers.evertally.scripts.OnClick(editor.providers.evertally)
        self.assertEqual(self.lua.globals().CVAR_WRITES, 0)
        self.assertTrue(editor.choosing)

    def test_live_editor_bounds_fonts_and_saved_settings_are_shared(self):
        self.plate_cvars()
        self.a.db.settings.plateFontSize = 32
        self.a.OpenOnboarding(10)
        editor = self.a.onboarding.pages[10].plates
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
        self.a.OpenOnboarding(10)
        self.assertEqual(str(editor.controls.plateFontSize.value.text), '31')



if __name__ == "__main__":
    unittest.main()

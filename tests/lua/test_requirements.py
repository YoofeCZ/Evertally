"""Installation is the first step of exactly one onboarding window."""
import unittest
from test_addon import runtime, MOCK_UI_LUA

class InstallationTests(unittest.TestCase):
    def setUp(self):
        self.lua,self.a=runtime(enforce_requirements=True)
        self.lua.execute(MOCK_UI_LUA)
        self.lua.execute('''RELOADS=0;ReloadUI=function() RELOADS=RELOADS+1 end
            CREATED_WINDOWS={};local factory=CreateFrame
            CreateFrame=function(kind,name,...)
                if name then CREATED_WINDOWS[name]=(CREATED_WINDOWS[name] or 0)+1 end
                local object=factory(kind,name,...)
                if kind=="Button" then object.SetEnabled=function(self,on) self.enabled=on and true or false end end
                return object
            end''')
    def proof(self,version="0.9.9"):
        self.a.bridgeInstallation=self.lua.table(schemaVersion=1,kind="evertally-bridge-installation",bridgeVersion=version,createdAt=self.lua.globals().NOW)
    def openmap(self):self.lua.execute('OpenMapAPI={RegisterMenuToggle=function() end}')
    def open(self):
        self.a.ShowRequirements()
        return self.a.onboarding.window,self.a.installationPage
    def test_missing_dependencies_open_first_step_with_no_skip_or_main_window(self):
        self.a.db.settings.installVerified=True
        self.a.OpenUI()
        self.assertTrue(self.a.OnboardingShown())
        self.assertEqual(self.a.OnboardingState()[0],1)
        self.assertEqual(self.a.onboarding.pages[1].title.text,self.a.L("setupGetTitle"))
        self.assertIsNone(self.lua.globals().EvertallyFrame)
        self.assertIsNone(self.lua.globals().EvertallyInstallation)
        self.assertFalse(self.a.onboarding.window.next.enabled)
        self.assertIsNone(self.a.onboarding.window.skip)
    def test_next_skip_finish_direct_steps_and_apply_cannot_bypass_installation(self):
        gate,_=self.open()
        for _ in range(3):gate.next.scripts.OnClick(gate.next)
        self.a.OnboardingGo(9);self.assertEqual(self.a.OnboardingState()[0],1)
        self.a.OpenOnboarding(8);self.assertEqual(self.a.OnboardingState()[0],1)
        self.a.OnboardingFinish();self.assertEqual(self.a.OnboardingState()[0],1)
        self.a.OnboardingApply(self.a.OnboardingDraft())
        self.a.OnboardingSkip();self.assertFalse(self.a.OnboardingShown())
        self.assertIsNone(self.a.db.settings.onboarded)
        self.assertFalse(self.a.db.settings.web or self.a.db.settings.ingame)
        self.a.OpenUI();self.assertEqual(self.a.OnboardingState()[0],1)
    def test_verify_reuses_window_and_enables_next_only_when_both_installed(self):
        gate,panel=self.open()
        for _ in range(3):panel.verify.scripts.OnClick(panel.verify)
        self.proof();panel.verify.scripts.OnClick(panel.verify)
        self.assertFalse(gate.next.enabled)
        self.openmap();panel.verify.scripts.OnClick(panel.verify)
        self.assertTrue(gate.next.enabled)
        self.assertEqual(self.a.OnboardingState()[0],1)
        gate.next.scripts.OnClick(gate.next);self.assertEqual(self.a.OnboardingState()[0],2)
        self.assertEqual(self.lua.globals().CREATED_WINDOWS.EvertallySetup,1)
        self.assertIsNone(self.lua.globals().CREATED_WINDOWS.EvertallyInstallation)
        self.assertFalse(self.a.db.settings.web or self.a.db.settings.ingame)
    def test_old_future_and_malformed_receipts_do_not_unlock(self):
        self.openmap()
        for version in ("0.9.8","x","0.9","0.9.9x","999999.0.0"):
            self.proof(version);self.assertFalse(self.a.RequirementsReady(),version)
        self.proof();self.a.bridgeInstallation.createdAt=self.lua.globals().NOW+301
        self.assertFalse(self.a.RequirementsReady())
        self.proof();self.a.bridgeInstallation.kind="other-proof"
        self.assertFalse(self.a.RequirementsReady())
        self.proof("0.10.0");self.assertTrue(self.a.RequirementsReady())
    def test_close_reopen_and_settings_verify_keep_exactly_one_window(self):
        gate,panel=self.open();gate.close.scripts.OnClick(gate.close)
        self.assertFalse(self.a.OnboardingShown())
        self.lua.execute('SlashCmdList.EVERTALLY("forum")');self.assertTrue(self.a.OnboardingShown())
        panel.reload.scripts.OnClick(panel.reload);self.assertEqual(self.lua.globals().RELOADS,1)
        self.proof();self.openmap();self.a.OpenUI();self.assertFalse(self.a.OnboardingShown())
        self.a.settingsPage.SelectSection(6)
        for _,button in self.a.settingsPage.actions.items():
            if button.localeKey=="installVerify":button.scripts.OnClick(button)
        self.assertTrue(self.a.OnboardingShown());self.assertEqual(self.a.OnboardingState()[0],1)
        self.assertFalse(self.lua.globals().EvertallyFrame.shown)
        self.assertEqual(self.lua.globals().CREATED_WINDOWS.EvertallySetup,1)
    def test_minimap_is_available_without_dependencies_despite_previously_hidden_setting(self):
        self.lua.execute('Minimap=CreateFrame("Frame",nil,UIParent);Minimap:SetSize(140,140)')
        self.a.db.settings.hideMinimap=True;self.a.Dispatch("PLAYER_LOGIN")
        button=self.lua.globals().EvertallyMinimapButton;self.assertTrue(button.shown)
        button.scripts.OnClick(button);self.assertEqual(self.a.OnboardingState()[0],1)
        self.a.OnboardingClose();button.scripts.OnClick(button);self.assertTrue(self.a.OnboardingShown())
        self.assertEqual(self.a.OnboardingState()[0],1)
    def test_collectors_map_and_optical_packet_wait_for_dependencies(self):
        self.lua.execute('Evertally.On("FAKE_EVENT",function() RAN=true end)')
        self.a.Dispatch("FAKE_EVENT");self.assertIsNone(self.lua.globals().RAN)
        self.assertIsNone(self.a.Record("quest.accepted",self.lua.table(questId=1)))
        self.assertIsNone(self.a.OpticalPacket());self.assertEqual(self.a.LoadMap(),(False,"dependencies_required"))
        self.proof();self.openmap();self.a.Dispatch("FAKE_EVENT");self.assertTrue(self.lua.globals().RAN)
    def test_initial_check_defers_during_combat_and_stays_closed_after_dismissal(self):
        self.lua.execute('INCOMBAT=true');self.a.Dispatch("PLAYER_ENTERING_WORLD")
        self.assertFalse(self.a.OnboardingShown())
        self.lua.execute('INCOMBAT=false');self.a.Dispatch("PLAYER_REGEN_ENABLED")
        self.assertTrue(self.a.OnboardingShown())
        self.a.OnboardingClose();self.a.Dispatch("PLAYER_REGEN_ENABLED");self.assertFalse(self.a.OnboardingShown())
    def test_download_buttons_open_only_requested_destination_without_unlocking(self):
        _,panel=self.open()
        for which,url in (("bridge","https://evertally.afstudio.dev/#sync"),("openmap","https://www.curseforge.com/wow/addons/openmap")):
            self.assertIsNone(panel.rows[which].url)
            button=panel.rows[which].open;button.scripts.OnClick(button)
            self.assertEqual(self.a.installationLinkWindow.address.url,url)
            self.assertFalse(self.a.RequirementsReady())
            self.a.installationLinkWindow.close.scripts.OnClick(self.a.installationLinkWindow.close)
        self.assertFalse(self.a.OpenInstallationLink("https://untrusted.example"))

if __name__=="__main__":unittest.main()

"""Mandatory app/OpenMap install screen and its guards. No files or processes are inspected by Lua."""
import unittest
from test_addon import runtime, MOCK_UI_LUA


class InstallationTests(unittest.TestCase):
    def setUp(self):
        self.lua,self.a=runtime(enforce_requirements=True)
        self.lua.execute(MOCK_UI_LUA)
        self.lua.execute('RELOADS=0;ReloadUI=function() RELOADS=RELOADS+1 end')

    def proof(self,version="0.9.9"):
        self.a.bridgeInstallation=self.lua.table(schemaVersion=1,kind="evertally-bridge-installation",bridgeVersion=version,createdAt=self.lua.globals().NOW)

    def openmap(self):
        self.lua.execute('OpenMapAPI={RegisterMenuToggle=function() end}')

    def test_nothing_is_assumed_installed_and_old_checkbox_is_ignored(self):
        self.a.db.settings.installVerified=True
        status=self.a.RequirementsStatus()
        self.assertFalse(status.bridge or status.openmap or status.ready)
        self.a.OpenUI()
        self.assertTrue(self.a.requirementsWindow.shown)
        self.assertIsNone(self.lua.globals().EvertallyFrame)
        self.assertIsNotNone(self.a.requirementsWindow.verify)

    def test_verify_does_not_unlock_one_missing_requirement(self):
        self.proof()
        ok,status=self.a.VerifyInstallation()
        self.assertFalse(ok)
        self.assertTrue(status.bridge)
        self.openmap()
        self.a.bridgeInstallation=None
        self.assertFalse(self.a.VerifyInstallation()[0])
        self.proof()
        self.assertTrue(self.a.VerifyInstallation()[0])

    def test_receipt_validation_rejects_old_future_or_malformed_data(self):
        self.openmap()
        for version in ("0.9.8","x","0.9","0.9.9x","999999.0.0"):
            self.proof(version)
            self.assertFalse(self.a.RequirementsReady(),version)
        self.proof()
        self.a.bridgeInstallation.createdAt=self.lua.globals().NOW+301
        self.assertFalse(self.a.RequirementsReady())
        self.proof()
        self.a.bridgeInstallation.kind="some-other-proof"
        self.assertFalse(self.a.RequirementsReady())
        self.proof("0.10.0")
        self.assertTrue(self.a.RequirementsReady())

    def test_continue_is_guarded_and_cannot_skip_installation(self):
        self.a.OpenOnboarding()
        gate=self.a.requirementsWindow
        gate.next.scripts.OnClick(gate.next)
        self.assertFalse(self.a.OnboardingShown())
        self.proof();self.openmap()
        gate.verify.scripts.OnClick(gate.verify)
        self.assertTrue(self.a.RequirementsReady())
        self.assertTrue(gate.shown)
        gate.next.scripts.OnClick(gate.next)
        self.assertFalse(gate.shown)
        self.assertTrue(self.a.OnboardingShown())
        self.assertFalse(self.a.db.settings.web or self.a.db.settings.ingame)

    def test_install_check_stays_accessible_and_closing_screen_does_not_bypass_gate(self):
        self.lua.execute('SlashCmdList.EVERTALLY("install")')
        gate=self.a.requirementsWindow
        gate.close.scripts.OnClick(gate.close)
        self.assertFalse(gate.shown)
        self.lua.execute('SlashCmdList.EVERTALLY("forum")')
        self.assertTrue(gate.shown)
        gate.reload.scripts.OnClick(gate.reload)
        self.assertEqual(self.lua.globals().RELOADS,1)
        self.proof();self.openmap()
        self.a.OpenUI()
        self.a.settingsPage.SelectSection(6)
        self.assertTrue(any(self.a.settingsPage.actions[i].localeKey=="installVerify" for i in range(1,len(self.a.settingsPage.actions)+1)))

    def test_collectors_messages_map_and_optical_packet_wait_for_dependencies(self):
        self.lua.execute('Evertally.On("FAKE_EVENT",function() RAN=true end)')
        self.a.Dispatch("FAKE_EVENT")
        self.assertIsNone(self.lua.globals().RAN)
        self.assertIsNone(self.a.Record("quest.accepted",self.lua.table(questId=1)))
        self.assertEqual(len(self.a.db.events),0)
        self.assertIsNone(self.a.OpticalPacket())
        self.assertEqual(self.a.LoadMap(),(False,"dependencies_required"))
        self.proof();self.openmap()
        self.a.Dispatch("FAKE_EVENT")
        self.assertTrue(self.lua.globals().RAN)
        self.assertIsNotNone(self.a.Record("quest.accepted",self.lua.table(questId=1)))

    def test_gate_defers_until_combat_ends_without_enabling_sharing(self):
        self.lua.execute('INCOMBAT=true')
        self.a.Dispatch("PLAYER_ENTERING_WORLD")
        self.assertIsNone(self.a.requirementsWindow)
        self.lua.execute('INCOMBAT=false')
        self.a.Dispatch("PLAYER_REGEN_ENABLED")
        self.assertTrue(self.a.requirementsWindow.shown)
        self.assertFalse(self.a.db.settings.web or self.a.db.settings.ingame)

    def test_download_buttons_show_only_the_selected_destination_and_do_not_unlock(self):
        self.a.ShowRequirements()
        gate=self.a.requirementsWindow
        self.assertIsNone(gate.rows.bridge.url)
        self.assertIsNone(gate.rows.openmap.url)
        for which,url in (("bridge","https://evertally.afstudio.dev/#sync"),("openmap","https://www.curseforge.com/wow/addons/openmap")):
            button=gate.rows[which].open
            button.scripts.OnClick(button)
            dialog=self.a.installationLinkWindow
            self.assertTrue(dialog.shown)
            self.assertEqual(dialog.address.url,url)
            self.assertFalse(self.a.RequirementsReady())
            dialog.close.scripts.OnClick(dialog.close)
            self.assertFalse(dialog.shown)
        self.assertFalse(self.a.OpenInstallationLink("https://untrusted.example"))


if __name__=="__main__":unittest.main()

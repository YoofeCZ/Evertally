"""The Evertally app and OpenMap are optional (2026-11-20, the user: "kdo nechce, nechce"). The add-on runs without them;
the installation page, the setup's summary, its Finish and the settings say what goes missing then: party members in
the game, the chronicle on the website, the leaderboard, the online part. The receipt rules still decide whether the
app counts as installed."""
from pathlib import Path
import unittest
from test_addon import runtime, MOCK_UI_LUA

ROOT = Path(__file__).resolve().parents[2]


class OptionalRequirementsTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = runtime(enforce_requirements=True)
        self.lua.execute(MOCK_UI_LUA)
        self.lua.execute('''RELOADS=0;ReloadUI=function() RELOADS=RELOADS+1 end
            PRINTED={};Evertally.Print=function(m) PRINTED[#PRINTED+1]=m end
            CREATED_WINDOWS={};local factory=CreateFrame
            CreateFrame=function(kind,name,...)
                if name then CREATED_WINDOWS[name]=(CREATED_WINDOWS[name] or 0)+1 end
                local object=factory(kind,name,...)
                if kind=="Button" then object.SetEnabled=function(self,on) self.enabled=on and true or false end end
                return object
            end''')

    def proof(self, version="0.9.9"):
        self.a.bridgeInstallation = self.lua.table(schemaVersion=1, kind="evertally-bridge-installation", bridgeVersion=version,
                                                   createdAt=self.lua.globals().NOW)

    def openmap(self): self.lua.execute('OpenMapAPI={RegisterMenuToggle=function() end}')

    def printed(self):
        g = self.lua.globals().PRINTED
        return [str(g[i]) for i in range(1, len(g) + 1)]

    def test_without_the_app_and_openmap_the_addon_runs(self):
        self.assertTrue(self.a.RequirementsReady())
        self.assertTrue(self.a.RequirementsGuard())
        self.assertFalse(self.a.RequirementsComplete())
        self.assertEqual(list(self.a.RequirementsMissing().values()), ["bridge", "openmap"])
        self.lua.execute('Evertally.On("FAKE_EVENT",function() RAN=true end)')
        self.a.Dispatch("FAKE_EVENT")
        self.assertTrue(self.lua.globals().RAN, "events run without the app and OpenMap")
        self.assertIsNotNone(self.a.Record("quest.accepted", self.lua.table(questId=1)), "the journal records")
        self.a.OpenUI()
        self.assertIsNotNone(self.lua.globals().EvertallyFrame, "the window opens, no installation gate")

    def test_the_warning_names_what_goes_missing_in_both_languages(self):
        for lang in ("en", "cs"):
            text = str(self.a.locale[lang].installLimited)
            for word in {"en": ("party members", "chronicle", "leaderboard", "online"),
                         "cs": ("spoluhráče", "kroniku", "žebříčku", "online")}[lang]:
                self.assertIn(word, text, (lang, word))
        self.assertNotIn("required", str(self.a.locale.en.setupGetBody))
        self.assertIn("optional", str(self.a.locale.en.setupGetBody))

    def test_the_installation_page_shows_the_warning_until_both_are_there(self):
        self.a.ShowRequirements()
        panel = self.a.installationPage
        panel.Update()
        self.assertEqual(panel.result.text, self.a.L("installLimited"))
        self.proof(); self.openmap()
        panel.verify.scripts.OnClick(panel.verify)
        panel.Update()
        self.assertEqual(panel.result.text, self.a.L("installSuccess"))

    def test_the_setups_next_does_not_wait_for_them(self):
        self.a.ShowRequirements()
        gate = self.a.onboarding.window
        self.assertTrue(gate.next.enabled, "Next on the installation page without the app or OpenMap")
        gate.next.scripts.OnClick(gate.next)
        self.assertEqual(self.a.OnboardingState()[0], 3)

    def test_the_guide_setups_pages_do_not_hold_next(self):
        pages = self.a.setupPages.pages
        for i in range(1, len(pages) + 1):
            if str(pages[i].key) in ("et-install", "et-pair"):
                self.assertIsNone(pages[i].blocked, str(pages[i].key))
        source = (ROOT / "addon" / "Evertally" / "SetupPages.lua").read_text(encoding="utf-8")
        self.assertIn('A.L("installLimited")', source, "the summary says it before Finish")

    def test_finish_without_them_says_what_goes_missing(self):
        self.a.SetupDraft()
        self.a.OnboardingFinish()
        self.assertEqual(self.a.db.settings.onboarded is not None, True)
        self.assertIn(self.a.L("installLimited"), self.printed())

    def test_finish_with_both_says_nothing_of_it(self):
        self.proof(); self.openmap()
        self.a.SetupDraft()
        self.a.OnboardingFinish()
        self.assertNotIn(self.a.L("installLimited"), self.printed())

    def test_old_future_and_malformed_receipts_do_not_count_as_the_app(self):
        self.openmap()
        for version in ("0.9.8", "x", "0.9", "0.9.9x", "999999.0.0"):
            self.proof(version); self.assertFalse(self.a.RequirementsComplete(), version)
        self.proof(); self.a.bridgeInstallation.createdAt = self.lua.globals().NOW + 301
        self.assertFalse(self.a.RequirementsComplete())
        self.proof(); self.a.bridgeInstallation.kind = "other-proof"
        self.assertFalse(self.a.RequirementsComplete())
        self.proof("0.10.0"); self.assertTrue(self.a.RequirementsComplete())

    def test_app_verified_once_stays_verified_after_the_receipt_is_gone(self):
        self.openmap()
        self.assertFalse(self.a.RequirementsComplete())
        self.proof(); self.assertTrue(self.a.RequirementsComplete())
        self.a.bridgeInstallation = None
        self.assertTrue(self.a.RequirementsComplete())
        self.assertEqual(self.a.RequirementsStatus().bridgeVersion, "0.9.9")
        self.a.db.bridgeVerified.bridgeVersion = "0.9.8"
        self.assertFalse(self.a.RequirementsComplete())

    def test_nothing_opens_by_itself_for_the_missing_installation(self):
        self.a.RequirementsMaybe()
        self.assertFalse(bool(self.a.OnboardingShown and self.a.OnboardingShown()), "no installation page forced on the player")

    def test_download_buttons_open_only_requested_destination(self):
        self.a.ShowRequirements()
        panel = self.a.installationPage
        for which, url in (("bridge", "https://evertally.afstudio.dev/#sync"), ("openmap", "https://www.curseforge.com/wow/addons/openmap")):
            button = panel.rows[which].open; button.scripts.OnClick(button)
            self.assertEqual(self.a.installationLinkWindow.address.url, url)
            self.a.installationLinkWindow.close.scripts.OnClick(self.a.installationLinkWindow.close)
        self.assertFalse(self.a.OpenInstallationLink("https://untrusted.example"))


if __name__ == "__main__":
    unittest.main()

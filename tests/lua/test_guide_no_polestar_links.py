"""No link to Polestar's repository in the game: the guide's pack docs address (ns.DocsURL, built from the TOC's
X-Website = github.com/fitzforge/polestar) is off, and the Import and Community guides pages show no pointer to its
docs instead (2026-11-19: the Import page showed github.com/fitzforge/polestar/.../GUIDE_PACKS.md). The fork and
tools/import_polestar.py carry the same edits, so the next import keeps them."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
FORK = ROOT / "addon" / "Evertally_Guide"


class NoPolestarLinksTests(unittest.TestCase):
    def test_docs_url_is_off_in_the_fork(self):
        init = (FORK / "Core" / "Init.lua").read_text(encoding="latin-1")
        body = init.split("function ns.DocsURL()", 1)[1].split("\nend", 1)[0]
        self.assertIn("do return nil end", body)
        self.assertLess(body.index("do return nil end"), body.index('"/blob/HEAD/docs/PACKS.md"'))

    def test_no_docs_pointer_on_the_import_and_packs_pages(self):
        for rel in ("UI/Import.lua", "UI/Packs.lua"):
            text = (FORK / rel).read_text(encoding="latin-1")
            self.assertNotIn('SetText(L["Read more: docs/GUIDE_PACKS.md', text, rel)

    def test_the_importer_keeps_the_edits(self):
        imp = (ROOT / "tools" / "import_polestar.py").read_text(encoding="utf-8")
        block = imp.split("# ---- 2026-11-19: no link to Polestar's repository", 1)[1].split("\ndef ", 1)[0]
        for rel in ("Core/Init.lua", "UI/Import.lua", "UI/Packs.lua"):
            self.assertIn(f"_more('{rel}'", block)


    def test_forum_instead_of_polestars_discord_github_and_site(self):
        init = (FORK / "Core" / "Init.lua").read_text(encoding="latin-1")
        self.assertIn('ns.DiscordURL = "https://evertally.afstudio.dev/#forum"', init)
        self.assertNotIn("discord.gg", init)
        update = (FORK / "Core" / "Update.lua").read_text(encoding="latin-1")
        body = update.split("function U.ReleaseURL(v)", 1)[1].split("\nend", 1)[0]
        self.assertIn('return "https://evertally.afstudio.dev"', body)
        self.assertNotIn("fitzforge", body)
        self.assertIn('local SITE = "evertally.afstudio.dev"', (FORK / "UI" / "WhatsNew.lua").read_text(encoding="latin-1"))
        report = (FORK / "UI" / "Report.lua").read_text(encoding="latin-1")
        self.assertIn("F.GitHubRule:Hide(); F.GitHubNote:Hide(); F.GitHub:Hide()", report)
        self.assertNotIn("put(F.GitHub,", report)
        self.assertIn('UI.ShowCopy(L["Evertally forum"], ns.DiscordURL', report)
        sidebar = report.split("function R.SidebarLink(f)", 1)[1]
        self.assertTrue(sidebar.lstrip().startswith("do return end"), "no Discord mark in the sidebars")
        welcome = (FORK / "UI" / "Welcome.lua").read_text(encoding="latin-1")
        self.assertNotIn('L["Join us on Discord"]', welcome)
        options = (ROOT / "addon" / "Evertally_Guide_Options" / "UI" / "Options.lua").read_text(encoding="latin-1")
        self.assertNotIn("Help improve it on Discord.", options)

    def test_the_new_texts_are_in_czech_and_the_importer_keeps_them(self):
        cs = (ROOT / "addon" / "Evertally_Guide_csCZ" / "Interface.lua").read_text(encoding="utf-8")
        for key in ("Open the forum", "Evertally forum", "This translation was made with AI. Help improve it on the Evertally forum."):
            self.assertIn(f'L["{key}"] = ', cs)
        imp = (ROOT / "tools" / "import_polestar.py").read_text(encoding="utf-8")
        block = imp.split("# ---- 2026-11-20: Evertally's forum instead of Polestar's", 1)[1].split("\ndef ", 1)[0]
        for rel in ("Core/Init.lua", "Core/Update.lua", "UI/WhatsNew.lua", "UI/Report.lua", "UI/Welcome.lua", "UI/Options.lua"):
            self.assertIn(f"_more('{rel}'", block)
        self.assertIn("'Evertally forum':", imp)

if __name__ == "__main__":
    unittest.main()

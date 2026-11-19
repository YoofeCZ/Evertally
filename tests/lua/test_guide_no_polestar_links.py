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


if __name__ == "__main__":
    unittest.main()

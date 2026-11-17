"""The Evertally_Guide* add-ons that tools/import_polestar.py generates from Polestar (GPL-3.0-only): every file compiles,
no Polestar identifier is left in the code (an installed Polestar would clash), every add-on a TOC or the code names exists,
the folders the TOCs list exist, and each folder carries Polestar's licence and Evertally's notice of what changed."""
from pathlib import Path
import importlib.util
import re
import sys
import unittest

from lupa.lua51 import LuaRuntime  # the game runs Lua 5.1

ROOT = Path(__file__).resolve().parents[2]
ADDONS = ROOT / "addon"
FOLDERS = sorted(p for p in ADDONS.glob("Evertally_Guide*") if p.is_dir())
spec = importlib.util.spec_from_file_location("import_polestar", ROOT / "tools" / "import_polestar.py")
importer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(importer)


def code_of(text):
    """The text outside comments and strings."""
    out, at = [], 0
    for m in importer.LUA_TOKEN.finditer(text):
        out.append(text[at:m.start()])
        at = m.end()
    out.append(text[at:])
    return "".join(out)


@unittest.skipUnless(FOLDERS, "run tools/import_polestar.py first")
class PolestarImportTests(unittest.TestCase):
    def test_the_fork_is_all_there_without_the_language_packs(self):
        names = {p.name for p in FOLDERS}
        for must in ("Evertally_Guide", "Evertally_Guide_Codex", "Evertally_Guide_Nav", "Evertally_Guide_Options", "Evertally_Guide_Guides",
                     "Evertally_Guide_QuestDB", "Evertally_Guide_ItemDB", "Evertally_Guide_Nav_EK", "Evertally_Guide_Nav_Kalimdor"):
            self.assertIn(must, names)
        self.assertFalse([n for n in names if re.search(r"_[a-z]{2}[A-Z]{2}$", n)], "no language packs")

    def test_every_lua_file_compiles(self):
        lua = LuaRuntime()
        load = lua.eval("function(s, name) local f, e = loadstring(s, name); return e end")
        bad = []
        for folder in FOLDERS:
            for path in folder.rglob("*.lua"):
                error = load(path.read_bytes(), path.name)
                if error:
                    bad.append(f"{path.relative_to(ADDONS)}: {error}")
        self.assertEqual(bad, [])

    def test_no_polestar_identifier_is_left_in_the_code(self):
        left = []
        for folder in FOLDERS:
            for path in list(folder.rglob("*.lua")) + list(folder.rglob("*.xml")):
                text = path.read_bytes().decode("latin-1")
                code = code_of(text) if path.suffix == ".lua" else re.sub(r"<!--.*?-->", "", text, flags=re.S)
                for m in re.finditer(r"\b(Polestar\w*|POLESTAR\w*)", code):
                    left.append(f"{path.relative_to(ADDONS)}: {m.group(1)}")
        self.assertEqual(left[:20], [])

    def test_every_addon_named_exists_and_every_listed_file_too(self):
        names = {p.name for p in FOLDERS} | {"Evertally", "Evertally_Map", "Evertally_Export"}
        missing = []
        for folder in FOLDERS:
            toc = folder / f"{folder.name}.toc"
            self.assertTrue(toc.is_file(), folder.name)
            for line in toc.read_text(encoding="utf8").splitlines():
                deps = re.match(r"## (?:Dependencies|RequiredDeps):\s*(.*)", line)
                if deps:
                    missing += [f"{folder.name} needs {d}" for d in re.split(r"[,\s]+", deps.group(1)) if d and d not in names]
                if line and not line.startswith("#") and not line.startswith("Libs") and re.search(r"\.(lua|xml)$", line.strip()):
                    if not (folder / line.strip().replace("\\", "/")).is_file():
                        missing.append(f"{folder.name} lists {line.strip()}")
            for path in folder.rglob("*.lua"):
                for m in re.finditer(r"LoadAddOn\w*\(\s*\"(Evertally_Guide\w*)\"", path.read_bytes().decode("latin-1")):
                    if m.group(1) not in names and not re.search(r"_[a-z]{2}[A-Z]{2}$", m.group(1)):
                        missing.append(f"{path.name} loads {m.group(1)}")
        self.assertEqual(missing, [])

    def test_the_fork_does_not_touch_evertallys_own_globals(self):
        own = set()
        for path in (ADDONS / "Evertally").glob("*.lua"):
            own |= set(re.findall(r"\b(EvertallyGuide\w*)", path.read_text(encoding="utf8", errors="replace")))
        self.assertEqual(own, set(), "the core add-on must not define the fork's globals")

    def test_each_folder_carries_the_licence_and_the_notice_of_changes(self):
        main = ADDONS / "Evertally_Guide"
        self.assertIn("GNU General Public License", (main / "LICENSE").read_text(encoding="utf8"))
        for folder in FOLDERS:
            notice = (folder / "NOTICE-EVERTALLY.txt").read_text(encoding="utf8")
            self.assertIn("Polestar", notice)
            self.assertIn("GPL-3.0-only", notice)

    def test_player_text_says_evertally_but_the_guides_author_and_party_messages_stay_polestar(self):
        self.assertEqual(importer.string_literal('"Open Polestar options"'), '"Open Evertally options"')
        self.assertEqual(importer.string_literal('"Polestar"'), '"Polestar"', "author and party prefix")
        self.assertEqual(importer.string_literal('"PolestarT1"'), '"PolestarT1"')
        self.assertEqual(importer.string_literal('"Polestar Pack: <title>"'), '"Polestar Pack: <title>"', "import strings other players paste")
        self.assertEqual(importer.string_literal('"Polestar_Options"'), '"Evertally_Guide_Options"')
        self.assertEqual(importer.lua('local x = Polestar.Nav; PolestarDB = {}'), 'local x = EvertallyGuide.Nav; EvertallyGuideDB = {}')
        self.assertEqual(importer.lua('-- Polestar wrote this\nlocal y = 1'), '-- Polestar wrote this\nlocal y = 1')


if __name__ == "__main__":
    unittest.main()

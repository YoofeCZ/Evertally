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
        self.assertFalse([n for n in names if re.search(r"_[a-z]{2}[A-Z]{2}$", n) and n != "Evertally_Guide_csCZ"],
                         "no language packs of Polestar's (Czech is Evertally's own)")

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

    def test_every_file_has_a_type_the_updater_installs(self):
        allowed = {".lua", ".toc", ".xml", ".md", ".txt", ".tga", ".blp", ".ttf", ".ogg"}  # sync/src/addon_update.rs FILE_TYPES
        odd = [str(p.relative_to(ADDONS)) for folder in FOLDERS for p in folder.rglob("*") if p.is_file() and p.suffix.lower() not in allowed]
        self.assertEqual(odd, [])

    def test_the_fork_does_not_touch_evertallys_own_globals(self):
        own = set()
        for path in (ADDONS / "Evertally").glob("*.lua"):
            # reading the guide (rawget(_G, "EvertallyGuide")) is fine; assigning one of its globals is not
            own |= set(re.findall(r"\b(EvertallyGuide\w*)\s*=[^=]", path.read_text(encoding="utf8", errors="replace")))
        self.assertEqual(own, set(), "the core add-on must not define the fork's globals")

    def test_each_folder_carries_the_licence_and_the_notice_of_changes(self):
        main = ADDONS / "Evertally_Guide"
        self.assertIn("GNU General Public License", (main / "LICENSE.txt").read_text(encoding="utf8"))
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

    def test_slash_commands_and_binding_labels_are_the_forks_own(self):
        # SLASH_POLESTAR1 slipped past \bPOLESTAR: the fork's commands were never registered and its key bindings had
        # no labels; and with Polestar installed both would have answered /polestar.
        init = (ADDONS / "Evertally_Guide" / "Core" / "Init.lua").read_text(encoding="latin-1")
        self.assertIn('SLASH_EVERTALLYGUIDE1 = "/etguide"', init)
        self.assertIn("SlashCmdList.EVERTALLYGUIDE = ", init)
        self.assertNotRegex(init, r'"/(polestar|pole|ps)"')
        bindings = set(re.findall(r'<Binding name="(\w+)"', (ADDONS / "Evertally_Guide" / "Bindings.xml").read_text(encoding="utf8")))
        labels = set(re.findall(r"^BINDING_NAME_(\w+) =", (ADDONS / "Evertally_Guide" / "Core" / "Commands.lua").read_text(encoding="latin-1"), re.M))
        self.assertTrue(bindings)
        self.assertEqual(bindings - labels, set())
        self.assertEqual(importer.string_literal('"Usage: /polestar way <x> <y>"'), '"Usage: /etguide way <x> <y>"')
        self.assertEqual(importer.string_literal('"https://discord.gg/polestar"'), '"https://discord.gg/polestar"')

    def test_ids_other_addons_key_us_by_differ_from_polestars(self):
        # Baganator asserts on a corner widget id registered twice ("API/Main.lua:230: assertion failed").
        self.assertEqual(importer.string_literal('"polestar_quest_needed"'), '"evertally_guide_quest_needed"')
        self.assertEqual(importer.string_literal('"polestar"'), '"polestar"', "the default skin's id is ours alone")
        left = []
        for folder in FOLDERS:
            for path in folder.rglob("*.lua"):
                for m in re.finditer(r"\"(polestar_[a-z_]+)\"", path.read_bytes().decode("latin-1")):
                    left.append(f"{path.relative_to(ADDONS)}: {m.group(1)}")
        self.assertEqual(left, [])
        nav = ADDONS / "Evertally_Guide" / "Nav"
        for name, needle in (("Handoff.lua", 'OWNER = "EvertallyGuide"'), ("Bridges.lua", 'FLAG = "EvertallyGuide"')):
            self.assertIn(needle, (nav / name).read_text(encoding="latin-1"))

    def test_the_welcome_stage_can_refresh_before_it_is_bound(self):
        # Polestar 0.4.0.1: W.Bind(stage, ...) ran before stage.Refresh existed ("Theme/Widgets.lua:1114").
        text = (ADDONS / "Evertally_Guide" / "UI" / "Welcome.lua").read_text(encoding="latin-1")
        self.assertLess(text.index("stage.Refresh = paintStage"), text.index('W.Bind(stage, "qol.targetPlate"'))


    def test_czech_keeps_every_placeholder_token_colour_and_line_break(self):
        # A translation that drops a %s, a {quest:123}, a |cff..|r or a line break breaks the text it fills.
        import json
        memory = {}
        for name in ("interface.json", "texts.json"):
            path = ROOT / "tools" / "polestar-cs" / name
            if path.is_file():
                memory.update(json.loads(path.read_text(encoding="utf8")))
        marks = re.compile(r"%[-+ #0]*\d*(?:\.\d+)?[sdifgxXc%]|\{\w+:\d+\}|\|c[0-9a-fA-F]{8}|\|r|\|T[^|]*\|t|\|H[^|]*\|h|\n")
        bad = [k for k, v in memory.items() if v and sorted(marks.findall(k)) != sorted(marks.findall(v))]
        self.assertEqual(bad[:10], [], f"{len(bad)} translations change a placeholder")

    def test_czech_loads_only_when_evertally_asks_and_keeps_the_games_names(self):
        folder = ADDONS / "Evertally_Guide_csCZ"
        self.assertTrue((folder / "Evertally_Guide_csCZ.toc").is_file())
        toc = (folder / "Evertally_Guide_csCZ.toc").read_text(encoding="utf8")
        self.assertIn("## LoadOnDemand: 1", toc)
        self.assertNotIn("Names.lua", toc, "the game's names stay English: the client is English")
        ui = (folder / "Interface.lua").read_text(encoding="utf8")
        self.assertIn('ns.EvertallyLanguage == "csCZ"', ui)
        texts = (folder / "Texts.lua").read_text(encoding="utf8")
        self.assertIn('EvertallyGuide.RegisterGuideTexts("csCZ", "guides", t)', texts)
        gt = (ADDONS / "Evertally_Guide" / "Core" / "GuideTexts.lua").read_text(encoding="latin-1")
        self.assertIn("function GuideTexts.UseLanguage(loc)", gt)
        lua = LuaRuntime()
        for name in ("Interface.lua", "Texts.lua"):
            err = lua.eval("function(s, n) local f, e = loadstring(s, n); return e end")((folder / name).read_bytes(), name)
            self.assertIsNone(err, name)

if __name__ == "__main__":
    unittest.main()

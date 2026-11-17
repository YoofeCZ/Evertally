"""Import Polestar (GPL-3.0-only, https://github.com/fitzforge/polestar) into Evertally as the Evertally_Guide* add-ons.

    python -I tools/import_polestar.py ["D:/World of Warcraft/_forever_/Interface/AddOns"]

Polestar changes every day, so the fork is generated, never edited by hand: run this again to take a newer Polestar. What
Evertally changes in the fork lives here (RENAMES, KEEP, PATCHES), so it survives every import. The renames keep the fork
apart from an installed Polestar: other folders, globals, frames, SavedVariables and key bindings.

  folders     Polestar -> Evertally_Guide, Polestar_X -> Evertally_Guide_X (language packs and the Recorder are left out)
  code        Polestar -> EvertallyGuide, PolestarDB -> EvertallyGuideDB, POLESTAR_X -> EVERTALLYGUIDE_X
  player text "Polestar" in a sentence -> "Evertally"; the guides' author stays "Polestar" (it is theirs), and so do the
              strings other Polestar users exchange with us (party addon messages, import strings), so the two can talk
  notices     LICENSE, THIRD_PARTY.md, CREDITS.md and LICENSE-DATA.txt are copied unchanged; NOTICE-EVERTALLY.txt says
              what was changed and when (GPL-3.0 section 5a)
"""
from __future__ import annotations

import datetime
import hashlib
import json
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(r"D:\World of Warcraft\_forever_\Interface\AddOns")
DEST = ROOT / "addon"
LANGUAGE = re.compile(r"^Polestar_[a-z]{2}[A-Z]{2}$")
SKIP = {"Polestar_Recorder"}
# The file types Evertally's updater installs (sync/src/addon_update.rs FILE_TYPES).
INSTALLED = {".lua", ".toc", ".xml", ".md", ".txt", ".tga", ".blp", ".ttf", ".ogg"}

# Strings other Polestar users send or paste: kept word for word so a party with Polestar players still works.
KEEP = {"PolestarT1"}
INTEROP = re.compile(r"Polestar (Pack|Community)|import string|^\^Polestar")
# Exact edits after the renames, per file (relative to the new folder): (old, new, expected count).
# Names other add-ons key us by (Auctionator caller, EllesmereUI painter, Waypoint UI flag, TomTom `from`, the SPF
# handoff owner) must differ from Polestar's: with both installed, the same name would overwrite or cancel the other's.
PATCHES: dict[str, list[tuple[str, str, int]]] = {
    # Polestar 0.4.0.1 bug: W.Bind calls stage:Refresh() before stage.Refresh is set ("Theme/Widgets.lua:1114:
    # attempt to call a nil value" on the Welcome page). Set it first.
    "UI/Welcome.lua": [
        ('\t\t\tW.Painter(stage, paintStage)\n\t\t\tW.Bind(stage, "qol.targetPlate", "qol.targetButton")\n'
         '\t\t\tW.Bind(stage, "qol.targetSimple")\n\t\t\tW.Bind(stage, "qol.markTarget")\n\t\t\tstage.Refresh = paintStage\n',
         '\t\t\tW.Painter(stage, paintStage)\n\t\t\tstage.Refresh = paintStage\n\t\t\tW.Bind(stage, "qol.targetPlate", "qol.targetButton")\n'
         '\t\t\tW.Bind(stage, "qol.targetSimple")\n\t\t\tW.Bind(stage, "qol.markTarget")\n', 1),
    ],
    "Core/Init.lua": [('SLASH_EVERTALLYGUIDE3 = "/ps"', 'SLASH_EVERTALLYGUIDE3 = "/evertallyguide"', 1)],
    "Core/Materials.lua": [('local CALLER = "Polestar"', 'local CALLER = "Evertally Guide"', 1)],
    "Gear/Bags.lua": [('local ELLESMERE = "Polestar"', 'local ELLESMERE = "EvertallyGuide"', 1)],
    "Nav/Bridges.lua": [('local FLAG = "Polestar"', 'local FLAG = "EvertallyGuide"', 1),
                        ('from = "Polestar",', 'from = "EvertallyGuide",', 1)],
    "Nav/Journey.lua": [('opts.from == "Polestar"', 'opts.from == "EvertallyGuide"', 1),
                        ('uid.from == "Polestar"', 'uid.from == "EvertallyGuide"', 1)],
    "Nav/Handoff.lua": [('local OWNER = "Polestar"', 'local OWNER = "EvertallyGuide"', 1)],
    "Nav/Pins.lua": [('section = "Polestar",', 'section = "Evertally Guide",', 1)],
    "UI/GameMenu.lua": [('button:SetText("Polestar")', 'button:SetText("Evertally Guide")', 1)],
    # Czech on an English client (Evertally_Guide_csCZ, chosen in Evertally): the guide texts take the language
    # Evertally sets; the game's names stay English, as the client shows them.
    "Core/GuideTexts.lua": [
        ('local english = ENGLISH[locale] or false\n',
         'local english = ENGLISH[locale] or false\n'
         '-- Evertally: the language of the guide texts when it is not the client\'s (Evertally_Guide_csCZ on an English\n'
         '-- client, set by Evertally before the guide packs load).\n'
         'function GuideTexts.UseLanguage(loc) locale = loc; english = ENGLISH[loc] or false end\n', 1),
    ],
    # Talents in Polestar 0.4.0.1 are "Coming soon" (T.SOON): no section on the hub's rail, and SHOW_TALENTS opens
    # Evertally's own Talents page (its planner, ETB1 codes, profiles in the talent window) instead.
    "Talents/View.lua": [
        ('ns.On("SHOW_TALENTS", TV.Show)',
         'ns.On("SHOW_TALENTS", function(...)\n'
         '\tlocal E = rawget(_G, "Evertally")\n'
         '\tif T.SOON and type(E) == "table" and E.ShowView then return E.ShowView("talents") end\n'
         '\treturn TV.Show(...)\nend)', 1),
        ('if UI.RegisterSection then\n\tUI.RegisterSection({\n\t\tkey = "Talents"',
         'if UI.RegisterSection and not T.SOON then\n\tUI.RegisterSection({\n\t\tkey = "Talents"', 1),
    ],
    # The settings window's sidebar groups are fixed; Evertally's own settings (addon/Evertally/EvertallySettings.lua)
    # register pages with group = "evertally", which leads the list.
    "UI/Options.lua": [
        ('local GROUPS = {\n\t{ key = "guiding", label = L["Guiding"] },',
         'local GROUPS = {\n\t{ key = "evertally", label = "Evertally" },\n\t{ key = "guiding", label = L["Guiding"] },', 1),
    ],
    # The hub's rail drops the sections past its foot group (rows of 56 px); with Evertally's own section the 640 px
    # hub of the Halo and Hearth skins is 2 px short. Close the rows up (to 46 px: icon and caption) before dropping.
    "Theme/Widgets.lua": [
        ("\tfor k = 1, #(bottom or {}) do\n\t\ti = i + 1\n\t\tplace(bottom[k], i, y, true)\n\t\ty = y + RAIL_ROW\n\tend\n"
         "\tlocal limit = f:GetHeight() - 2 - y -- the top of the bottom group\n"
         "\ty = f.psNavTop -- the first section level with the sidebar's first row\n"
         "\tfor k = 1, #items do\n\t\tif y + RAIL_ROW > limit then break end\n\t\ti = i + 1\n\t\tn = n + 1\n"
         "\t\tplace(items[k], i, y)\n\t\ty = y + RAIL_ROW\n\tend\n",
         "\tfor k = 1, #(bottom or {}) do\n\t\ti = i + 1\n\t\tplace(bottom[k], i, y, true)\n"
         "\t\trailButton(f, i):SetHeight(RAIL_ROW)\n\t\ty = y + RAIL_ROW\n\tend\n"
         "\tlocal limit = f:GetHeight() - 2 - y -- the top of the bottom group\n"
         "\ty = f.psNavTop -- the first section level with the sidebar's first row\n"
         "\t-- Evertally: more sections than rows close up (to 46 px) before one is dropped.\n"
         "\tlocal step = RAIL_ROW\n"
         "\tif #items > 0 and y + #items * step > limit then step = max(46, math.floor((limit - y) / #items)) end\n"
         "\tfor k = 1, #items do\n\t\tif y + step > limit then break end\n\t\ti = i + 1\n\t\tn = n + 1\n"
         "\t\tplace(items[k], i, y)\n\t\trailButton(f, i):SetHeight(step)\n\t\ty = y + step\n\tend\n", 1),
    ],
}
# Slash commands: Polestar's own words would clash with an installed Polestar (the game picks one of the two).
SLASH_WORDS = [(re.compile(r"(?<![\w./])/polestar\b"), "/etguide"), (re.compile(r"(?<![\w./])/pole\b"), "/etg")]
# Ids other add-ons key us by, spelled in lower case ("polestar_quest_needed": a Baganator corner widget). Registering
# Polestar's id a second time fails ("Baganator API/Main.lua:230: assertion failed"). Plain "polestar" (the default
# skin's id) is ours alone and stays.
LOWER_ID = re.compile(r"^polestar_([a-z_]+)$")
# Everywhere: a few literals that name the add-on itself or are shown as its name.
GLOBAL_PATCHES = [
    ('GetAddOnMemoryUsage, "Polestar"', 'GetAddOnMemoryUsage, "Evertally_Guide"'),
    ('L["Polestar"] = "Polestar"', 'L["Polestar"] = "Evertally"'),
    ('Tooltip(owner, "ANCHOR_LEFT", "Polestar"', 'Tooltip(owner, "ANCHOR_LEFT", "Evertally"'),
    ('RegisterCanvasLayoutCategory, canvas, "Polestar")', 'RegisterCanvasLayoutCategory, canvas, "Evertally Guide")'),
]

LUA_TOKEN = re.compile(
    r"(--\[(=*)\[.*?\]\2\])"              # long comment
    r"|(--[^\n]*)"                         # comment
    r"|(\[(=*)\[.*?\]\5\])"                # long string
    r"|(\"(?:\\.|[^\"\\\n])*\")"           # "string"
    r"|('(?:\\.|[^'\\\n])*')",             # 'string'
    re.S)


def folder_name(name: str) -> str:
    return "Evertally_Guide" + name[len("Polestar"):]


def identifiers(text: str, code: bool) -> str:
    text = re.sub(r"AddOns(\\\\|\\|/)Polestar(?=\\|/|\")", r"AddOns\1Evertally_Guide", text)
    text = re.sub(r"\bPolestar_", "Evertally_Guide_", text)
    text = re.sub(r"(?<![A-Za-z0-9])POLESTAR", "EVERTALLYGUIDE", text)   # also SLASH_POLESTAR1, BINDING_NAME_POLESTAR_X
    text = re.sub(r"\bPolestar(?=[A-Za-z0-9])", "EvertallyGuide", text)
    if code:
        text = re.sub(r"\bPolestar\b", "EvertallyGuide", text)
    return text


def string_literal(token: str) -> str:
    quote, body = token[0], token[1:-1]
    if body in KEEP or body == "Polestar":
        return token
    body = LOWER_ID.sub(r"evertally_guide_\1", body)
    body = identifiers(body, code=False)
    for pattern, word in SLASH_WORDS:
        body = pattern.sub(word, body)
    if re.search(r"\bPolestar\b", body) and not INTEROP.search(body):
        body = re.sub(r"\bPolestar\b", "Evertally", body)
    return quote + body + quote


def lua(text: str) -> str:
    out, at = [], 0
    for m in LUA_TOKEN.finditer(text):
        out.append(identifiers(text[at:m.start()], code=True))
        token = m.group(0)
        if m.group(6) or m.group(7):
            out.append(string_literal(token))
        elif m.group(3) and not m.group(1):
            out.append(token)                                   # a comment stays as Polestar wrote it
        elif m.group(4):
            out.append(identifiers(token, code=False))          # long strings hold data, not prose
        else:
            out.append(token)
        at = m.end()
    out.append(identifiers(text[at:], code=True))
    text = "".join(out)
    for old, new in GLOBAL_PATCHES:
        text = text.replace(old, new)
    return text


def toc(text: str) -> str:
    lines = []
    for line in text.replace("\r\n", "\n").split("\n"):  # not splitlines(): in latin-1 a UTF-8 byte 0x85 would split
        if re.match(r"## (Title|Notes|Category)(-\w+)?:", line):
            line = re.sub(r"\bPolestar(?=_)", "Evertally_Guide", line)
            line = re.sub(r"\bPolestar\b", "Evertally Guide", line)
        else:
            line = identifiers(line, code=False)
            line = re.sub(r"(## (?:Dependencies|RequiredDeps|OptionalDeps|LoadWith):.*)", lambda m: re.sub(r"\bPolestar\b", "Evertally_Guide", m.group(1)), line)
        lines.append(line)
    lines.append("## X-Evertally: generated from Polestar by tools/import_polestar.py; see NOTICE-EVERTALLY.txt")
    return "\n".join(lines) + "\n"


def lua_string(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "\\r") + '"'


def czech(today: str, version: str) -> None:
    """Evertally_Guide_csCZ from the translation memory (tools/polestar-cs, keys from tools/polestar_cs_keys.py):
    the interface (L) and the guide texts in Czech, loaded by Evertally when its language is Czech. Only what is
    translated goes in; the rest stays English."""
    src = ROOT / "tools" / "polestar-cs"
    if not (src / "keys.json").is_file():
        return
    keys = json.loads((src / "keys.json").read_text(encoding="utf8"))
    ui = json.loads((src / "interface.json").read_text(encoding="utf8"))
    tx = json.loads((src / "texts.json").read_text(encoding="utf8"))
    dst = DEST / "Evertally_Guide_csCZ"
    dst.mkdir(parents=True, exist_ok=True)
    lines = ["-- Czech (csCZ) for Evertally Guide. Generated by tools/import_polestar.py from tools/polestar-cs/interface.json:",
             "-- edit the translation there. Keys are the English strings as the code writes them; a key missing here shows",
             "-- in English. Fills L only when Evertally asked for Czech (EvertallyGuide.EvertallyLanguage).", "",
             "local ns = EvertallyGuide", 'if not (ns and ns.EvertallyLanguage == "csCZ") then return end', "local L = ns.L", ""]
    n_ui = 0
    for k in keys["interface"]:
        v = ui.get(k) or ""
        if v:
            lines.append(f"L[{lua_string(k)}] = {lua_string(v)}")
            n_ui += 1
    (dst / "Interface.lua").write_text("\n".join(lines) + "\n", encoding="utf8", newline="\n")
    out = ["-- Czech guide texts for Evertally Guide. Generated by tools/import_polestar.py from tools/polestar-cs/texts.json.",
           "", "local t = { guides = {} }", "t.pack = {"]
    n_tx = 0
    for k in keys["pack"]:
        if tx.get(k):
            out.append(f"\t[{lua_string(k)}] = {lua_string(tx[k])},")
            n_tx += 1
    out.append("}")
    for gid, ks in keys["guides"].items():
        rows = [f"\t[{lua_string(k)}] = {lua_string(tx[k])}," for k in ks if tx.get(k)]
        if rows:
            out.append(f"t.guides[{lua_string(gid)}] = {{")
            out += rows
            out.append("}")
            n_tx += len(rows)
    out += ["", 'EvertallyGuide.RegisterGuideTexts("csCZ", "guides", t)']
    (dst / "Texts.lua").write_text("\n".join(out) + "\n", encoding="utf8", newline="\n")
    (dst / "Evertally_Guide_csCZ.toc").write_text(
        "## Interface: 16001\n## Title: Evertally Guide - Czech\n## Notes: Evertally Guide in Czech: the interface and the guide texts.\n"
        "## Title-csCZ: Evertally Guide - čeština\n## Author: Evertally (translation); Polestar (the English)\n"
        f"## Version: {version}\n## LoadOnDemand: 1\n## Dependencies: Evertally_Guide\n## X-License: GPL-3.0-only\n"
        "## X-Evertally: generated by tools/import_polestar.py from tools/polestar-cs; see NOTICE-EVERTALLY.txt\n\nInterface.lua\nTexts.lua\n",
        encoding="utf8", newline="\n")
    shutil.copy2(SOURCE / "Polestar" / "LICENSE", dst / "LICENSE.txt")
    (dst / "NOTICE-EVERTALLY.txt").write_text(
        f"This folder is part of Evertally. It was generated on {today} by Evertally's tools/import_polestar.py. It is a Czech\n"
        f"translation of the interface and guide texts of Polestar {version} (https://github.com/fitzforge/polestar, Copyright (c)\n"
        "2026 The Polestar authors, GPL-3.0-only), made for Evertally from the English strings Polestar's own language folders\n"
        "list. Translated: " + f"{n_ui} interface strings, {n_tx} guide texts" + ". Distributed under the GNU GPL, version 3.\n",
        encoding="utf8", newline="\n")
    print(f"Czech: {n_ui}/{len(keys['interface'])} interface strings, {n_tx} guide texts")


def main() -> None:
    sources = sorted(p for p in SOURCE.glob("Polestar*") if p.is_dir() and not LANGUAGE.match(p.name) and p.name not in SKIP)
    if not sources or not (SOURCE / "Polestar" / "Polestar.toc").is_file():
        raise SystemExit(f"Polestar not found in {SOURCE}")
    version = re.search(r"^## Version: (.+)$", (SOURCE / "Polestar" / "Polestar.toc").read_text(encoding="utf8"), re.M).group(1).strip()
    today = datetime.date.today().isoformat()
    for old in DEST.glob("Evertally_Guide*"):
        if (old / "NOTICE-EVERTALLY.txt").is_file():          # only folders this script made
            shutil.rmtree(old)
    report = {"polestar": version, "date": today, "folders": {}}
    for src in sources:
        dst = DEST / folder_name(src.name)
        files = 0
        for path in sorted(src.rglob("*")):
            if not path.is_file():
                continue
            rel = path.relative_to(src)
            name = rel.name
            if name.startswith("Polestar") and path.suffix.lower() in {".toc", ".lua", ".xml"}:
                name = folder_name(name)
            if path.suffix.lower() not in INSTALLED:
                name += ".txt"      # LICENSE, PACK.json: Evertally's updater installs known file types only (the text is unchanged)
            out = dst / rel.parent / name
            out.parent.mkdir(parents=True, exist_ok=True)
            suffix = path.suffix.lower()
            if suffix in {".lua", ".xml", ".toc"}:
                text = path.read_text(encoding="latin-1")  # byte for byte: packed data holds raw bytes, every rename is ASCII
                text = lua(text) if suffix == ".lua" else toc(text) if suffix == ".toc" else identifiers(text, code=True)
                for old, new, count in PATCHES.get(str(rel.parent / name).replace("\\", "/"), []):
                    assert text.count(old) == count, (src.name, rel, old)
                    text = text.replace(old, new)
                out.write_bytes(text.encode("latin-1"))
            else:
                shutil.copy2(path, out)
            files += 1
        (dst / "NOTICE-EVERTALLY.txt").write_text(
            f"This folder is part of Evertally. It was generated on {today} from {src.name} of Polestar {version}\n"
            "(https://github.com/fitzforge/polestar, Copyright (c) 2026 The Polestar authors, GPL-3.0-only) by\n"
            "Evertally's tools/import_polestar.py, which changed it as follows:\n"
            "  - the folder and file names: Polestar -> Evertally_Guide;\n"
            "  - globals, frames, saved variables and key bindings: Polestar -> EvertallyGuide, POLESTAR -> EVERTALLYGUIDE;\n"
            "  - the add-on's name shown to players: Polestar -> Evertally (the guides' author is still Polestar);\n"
            "  - slash commands /polestar, /pole, /ps -> /etguide, /etg, /evertallyguide, and the ids other add-ons know\n"
            "    us by (polestar_* bag widgets, waypoint owners) -> evertally_guide_* / EvertallyGuide;\n"
            "  - the patches listed in tools/import_polestar.py.\n"
            "Everything else is Polestar's work, under its licence (LICENSE.txt) and notices (THIRD_PARTY.md, CREDITS.md,\n"
            "LICENSE-DATA.txt where present). This modified version is distributed under the GNU GPL, version 3.\n",
            encoding="utf8", newline="\n")
        report["folders"][dst.name] = files
    czech(today, version)
    (ROOT / "tools" / "polestar-import.json").write_text(json.dumps(report, indent=1) + "\n", encoding="utf8")
    print(f"Polestar {version}: {len(sources)} folders, {sum(report['folders'].values())} files -> {DEST}\\Evertally_Guide*")


if __name__ == "__main__":
    main()

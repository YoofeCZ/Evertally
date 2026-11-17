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
PATCHES: dict[str, list[tuple[str, str, int]]] = {}
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
    text = re.sub(r"\bPOLESTAR", "EVERTALLYGUIDE", text)
    text = re.sub(r"\bPolestar(?=[A-Za-z0-9])", "EvertallyGuide", text)
    if code:
        text = re.sub(r"\bPolestar\b", "EvertallyGuide", text)
    return text


def string_literal(token: str) -> str:
    quote, body = token[0], token[1:-1]
    if body in KEEP or body == "Polestar":
        return token
    body = identifiers(body, code=False)
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
            "  - the patches listed in tools/import_polestar.py.\n"
            "Everything else is Polestar's work, under its licence (LICENSE.txt) and notices (THIRD_PARTY.md, CREDITS.md,\n"
            "LICENSE-DATA.txt where present). This modified version is distributed under the GNU GPL, version 3.\n",
            encoding="utf8", newline="\n")
        report["folders"][dst.name] = files
    (ROOT / "tools" / "polestar-import.json").write_text(json.dumps(report, indent=1) + "\n", encoding="utf8")
    print(f"Polestar {version}: {len(sources)} folders, {sum(report['folders'].values())} files -> {DEST}\\Evertally_Guide*")


if __name__ == "__main__":
    main()

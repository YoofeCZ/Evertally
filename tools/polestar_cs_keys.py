"""The English strings of Evertally Guide (the fork of Polestar) that a translation covers, as the fork spells them.

    python -I tools/polestar_cs_keys.py ["D:/World of Warcraft/_forever_/Interface/AddOns"]

Polestar's language folders (Polestar_<locale>) key every string by its English: Interface.lua the interface (L),
Texts.lua the guides' prose. Their keys are the complete list; the German folder is read for it (its translations are
not used). The fork renames Polestar in strings (tools/import_polestar.py string_literal), so the keys are renamed the
same way. Names.lua and Subzones.lua (the game's names) are left out: the client is English and the guides match
names in English.

Writes tools/polestar-cs/keys.json: {"interface": [english, ...], "pack": [...], "guides": {guide id: [...]}} and
merges new keys into tools/polestar-cs/interface.json and texts.json (translations, "" until translated). A key gone
from Polestar is dropped from keys.json; its translation stays in the memory files, unused.
"""
from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(r"D:\World of Warcraft\_forever_\Interface\AddOns")
OUT = ROOT / "tools" / "polestar-cs"

spec = importlib.util.spec_from_file_location("import_polestar", ROOT / "tools" / "import_polestar.py")
importer = importlib.util.module_from_spec(spec)
sys.argv = sys.argv[:1]
spec.loader.exec_module(importer)


def renamed(english: str) -> str:
    """The key as the fork's code spells it (the same rename as its string literals)."""
    quoted = '"' + english.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'
    out = importer.string_literal(quoted)[1:-1]
    return out.replace("\\n", "\n").replace('\\"', '"').replace("\\\\", "\\")


def read_pack(folder: Path) -> tuple[list[str], list[str], dict[str, list[str]]]:
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute('GetLocale = function() return "deDE" end')
    lua.execute('L = {}; Polestar = {L = L}; TEXTS = nil; Polestar.RegisterGuideTexts = function(loc, id, t) TEXTS = t end')
    for name in ("Interface.lua", "Texts.lua"):
        chunk = lua.eval("loadstring")((folder / name).read_bytes().decode("utf8"), name)
        if isinstance(chunk, tuple):
            raise SystemExit(f"{name}: {chunk}")
        chunk()
    interface = sorted(str(k) for k in lua.globals().L.keys())
    t = lua.globals().TEXTS
    pack = sorted(str(k) for k in (t.pack or {}).keys()) if t.pack else []
    guides = {}
    for gid, entries in (t.guides or {}).items():
        guides[str(gid)] = sorted(str(k) for k in entries.keys())
    return interface, pack, guides


def main() -> None:
    interface, pack, guides = read_pack(SOURCE / "Polestar_deDE")
    interface = sorted({renamed(k) for k in interface})
    pack = sorted({renamed(k) for k in pack})
    guides = {gid: sorted({renamed(k) for k in keys}) for gid, keys in sorted(guides.items())}
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "keys.json").write_text(json.dumps({"interface": interface, "pack": pack, "guides": guides}, ensure_ascii=False, indent=0) + "\n", encoding="utf8")
    for name, keys in (("interface.json", interface), ("texts.json", sorted({k for ks in guides.values() for k in ks} | set(pack)))):
        path = OUT / name
        memory = json.loads(path.read_text(encoding="utf8")) if path.is_file() else {}
        for k in keys:
            memory.setdefault(k, "")
        path.write_text(json.dumps(dict(sorted(memory.items())), ensure_ascii=False, indent=0) + "\n", encoding="utf8")
    texts = {k for ks in guides.values() for k in ks} | set(pack)
    print(f"interface {len(interface)}, guide texts {len(texts)} distinct ({sum(len(v) for v in guides.values())} in {len(guides)} guides, {len(pack)} pack)")
    for label, keys in (("interface", interface), ("texts", texts)):
        print(f"  {label}: {sum(len(k) for k in keys)} characters")


if __name__ == "__main__":
    main()

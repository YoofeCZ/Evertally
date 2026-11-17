"""Translate Evertally Guide into Czech batch by batch (tools/polestar-cs).

    python -I tools/polestar_cs_batch.py next interface 300      # writes the next 300 untranslated strings
    python -I tools/polestar_cs_batch.py merge interface          # reads the translations back, checks, saves
    python -I tools/polestar_cs_batch.py status

`next` writes tools/polestar-cs/batch/<memory>.in.json: [[number, english], ...]. The translator writes
<memory>.out.json: a list of the Czech strings in the same order ("" leaves one untranslated). `merge` checks each one
keeps the English's placeholders (%s, %d, {quest:123}, |cff..|r, |T..|t, line breaks) and stores the good ones in the
memory (interface.json or texts.json); a bad one is reported and left out. Then run tools/import_polestar.py.

Glossary (keep the game's and the community's English where Czech players use it): quest, NPC, loot, buff, debuff,
rare (vzácný mob), elite, attunement, cooldown, tank, healer, DPS, raid, dungeon, item level, addon, minimap, tooltip
stay English (declined in Czech); guide = návod, step = krok, arrow = šipka, route = trasa, waypoint = bod trasy,
Options/Settings = Nastavení, skin = skin, hearthstone = Hearthstone, flight master = letový mistr, vendor = obchodník,
trainer = trenér, turn in = odevzdat, accept = přijmout. Names of quests, NPCs, items, zones stay English.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DIR = ROOT / "tools" / "polestar-cs"
BATCH = DIR / "batch"
MEMORY = {"interface": DIR / "interface.json", "texts": DIR / "texts.json"}
MARKS = re.compile(r"%[-+ #0]*\d*(?:\.\d+)?[sdifgxXc%]|\{\w+:\d+\}|\|c[0-9a-fA-F]{8}|\|r|\|T[^|]*\|t|\|H[^|]*\|h|\n")


def load(name):
    return json.loads(MEMORY[name].read_text(encoding="utf8"))


def save(name, memory):
    MEMORY[name].write_text(json.dumps(dict(sorted(memory.items())), ensure_ascii=False, indent=0) + "\n", encoding="utf8")


def keep_marks(en, cs):
    return sorted(MARKS.findall(en)) == sorted(MARKS.findall(cs))


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    BATCH.mkdir(parents=True, exist_ok=True)
    if cmd == "status":
        for name in MEMORY:
            m = load(name)
            done = sum(1 for v in m.values() if v)
            print(f"{name}: {done}/{len(m)} translated, {sum(len(k) for k, v in m.items() if not v)} characters left")
        return
    name = sys.argv[2]
    if cmd == "next":
        n = int(sys.argv[3]) if len(sys.argv) > 3 else 300
        m = load(name)
        todo = [k for k, v in m.items() if not v][:n]
        (BATCH / f"{name}.in.json").write_text(json.dumps([[i, k] for i, k in enumerate(todo)], ensure_ascii=False, indent=0) + "\n", encoding="utf8")
        print(f"{len(todo)} strings, {sum(len(k) for k in todo)} characters -> {BATCH / (name + '.in.json')}")
    elif cmd == "merge":
        todo = json.loads((BATCH / f"{name}.in.json").read_text(encoding="utf8"))
        out = json.loads((BATCH / f"{name}.out.json").read_text(encoding="utf8"))
        if len(out) != len(todo):
            raise SystemExit(f"{len(out)} translations for {len(todo)} strings")
        m = load(name)
        good, bad = 0, []
        for (i, en), cs in zip(todo, out):
            if not cs:
                continue
            if keep_marks(en, cs):
                m[en] = cs
                good += 1
            else:
                bad.append((i, en, cs))
        save(name, m)
        print(f"merged {good}, refused {len(bad)}")
        for i, en, cs in bad[:20]:
            print(f"  #{i}: {en!r} -> {cs!r}")
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()

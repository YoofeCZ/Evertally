"""Compact index of who trains which profession and who sells what, for the map's Trainers & vendors layer.

Derived only from data the database build already wrote (npcs/*.json, recipes.json); run it after build_db.py:
    python tools/build_services.py
Writes platform/public/media/db/services.json:
    professions  profession key -> NPC ids of its trainers (a trainer service plus a profession in the NPC's title)
    pos          NPC id -> up to 3 spawns [zone key, x %, y %]   (only NPCs that matter here)
    sells        item id -> NPC ids that sell it              (only NPCs that have a spawn)
    quick        reagent item ids that vendors sell, most used by recipes first
"""
from __future__ import annotations

import collections
import glob
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DB = ROOT / "platform" / "public" / "media" / "db"

# Titles of profession trainers: "Journeyman Alchemist", "Expert Blacksmith", "Mining Trainer", "Master Goblin Engineer" ...
PROFESSIONS = {
    "alchemy": r"alchem",
    "blacksmithing": r"blacksmith|weaponsmith|armorsmith|swordsmith|hammersmith|axesmith",
    "cooking": r"\bcook",
    "enchanting": r"enchant",
    "engineering": r"engineer",
    "first-aid": r"first aid",
    "fishing": r"fishing|fisherm",
    "herbalism": r"herbal",
    "leatherworking": r"leatherwork",
    "mining": r"\bmining\b|\bminer\b",
    "skinning": r"skinn",
    "tailoring": r"tailor",
}
# A shop that happens to carry the profession's name is not a trainer.
NOT_TRAINER = re.compile(r"suppl|vendor|recipe|goods|promoter|league|society|reagent|& ", re.I)
SPAWNS_PER_NPC = 3


def main() -> int:
    npcs: dict[int, dict] = {}
    for path in sorted(glob.glob(str(DB / "npcs" / "*.json"))):
        with open(path, encoding="utf8") as handle:
            for key, value in json.load(handle).items():
                npcs[int(key)] = value
    if not npcs:
        print("no npc shards found; run tools/build_db.py first", file=sys.stderr)
        return 1

    def spawns(npc: dict) -> list[list]:
        out: list[list] = []
        for zone, points in (npc.get("sp") or {}).items():
            for x, y in points[:SPAWNS_PER_NPC]:
                out.append([zone, round(x, 1), round(y, 1)])
        return out[:SPAWNS_PER_NPC]

    professions: dict[str, list[int]] = {key: [] for key in PROFESSIONS}
    for npc_id, npc in npcs.items():
        title = npc.get("sub") or ""
        if "trainer" not in (npc.get("services") or []) or NOT_TRAINER.search(title) or not npc.get("sp"):
            continue
        for key, pattern in PROFESSIONS.items():
            if re.search(pattern, title, re.I):
                professions[key].append(npc_id)
    for key in professions:
        professions[key].sort()

    sells: dict[int, list[int]] = collections.defaultdict(list)
    for npc_id, npc in npcs.items():
        if not npc.get("sp"):
            continue
        for item in npc.get("sells") or []:
            sells[int(item)].append(npc_id)

    uses: collections.Counter[int] = collections.Counter()
    recipes = json.load(open(DB / "recipes.json", encoding="utf8"))["recipes"]
    for recipe in recipes:
        for item, _qty in recipe.get("reagents", []):
            uses[int(item)] += 1
    quick = [item for item, _ in uses.most_common() if item in sells][:16]

    wanted = {npc for ids in professions.values() for npc in ids} | {npc for ids in sells.values() for npc in ids}
    pos = {str(npc): spawns(npcs[npc]) for npc in sorted(wanted)}
    out = {
        "professions": professions,
        "pos": pos,
        "sells": {str(item): sorted(set(ids)) for item, ids in sorted(sells.items())},
        "quick": quick,
    }
    target = DB / "services.json"
    target.write_text(json.dumps(out, separators=(",", ":"), ensure_ascii=False), encoding="utf8")
    print(f"{target.relative_to(ROOT)}: {target.stat().st_size / 1024:.0f} KiB")
    print("trainers per profession:", {key: len(ids) for key, ids in professions.items()})
    print(f"{len(sells)} items sold by {len({n for ids in sells.values() for n in ids})} vendors; quick list: {quick}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

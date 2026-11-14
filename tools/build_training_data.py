"""Build Evertally's standalone Forever training catalog from MIT data tables.

Only declarative Classes/Camelot files are evaluated; no third-party addon code,
SavedVariables, login state or network access is used. Trainer coordinates are
facts from the project's existing QuestieDB-derived NPC shards.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VENDOR = Path(r"C:\Users\domin\.codex\visualizations\2026\11\08\01a1bd6e-06a5-7b90-a316-c224aeeafc7c\questmaster-cs\vendor")
if VENDOR.exists():
    sys.path.insert(0, str(VENDOR))
from lupa.lua51 import LuaRuntime  # noqa: E402

CLASSES = ("WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID")


def native(value):
    if hasattr(value, "items"):
        values = dict(value.items())
        if values and set(values) == set(range(1, len(values) + 1)):
            return [native(values[i]) for i in range(1, len(values) + 1)]
        return {k: native(v) for k, v in values.items()}
    return value


def lua(value):
    if value is None:
        return "nil"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, list):
        return "{" + ",".join(lua(v) for v in value) + "}"
    return "{" + ",".join("[" + lua(k) + "]=" + lua(v) for k, v in value.items()) + "}"


def trainer_spots(db: Path, maps: dict, tome_vendors: dict) -> list[dict]:
    result = []
    pattern = re.compile(r"^(Druid|Hunter|Mage|Paladin|Priest|Rogue|Shaman|Warlock|Warrior|Pet) Trainer$", re.I)
    for path in sorted((db / "npcs").glob("*.json")):
        for npc in json.loads(path.read_text(encoding="utf8")).values():
            match = pattern.fullmatch(npc.get("sub") or "")
            grimoire = tome_vendors.get(npc.get("id")) is True
            if not grimoire and (not match or "trainer" not in (npc.get("services") or [])):
                continue
            # Unknown friendliness is not proof that a trainer is usable.
            side = {"A": "Alliance", "H": "Horde", "AH": "Both"}.get(npc.get("friendly"))
            if not side:
                continue
            for zone, points in (npc.get("sp") or {}).items():
                record = maps.get(zone)
                if not record or not record.get("ui"):
                    continue
                parent = record
                seen = set()
                while parent.get("parent") and parent["parent"] not in seen:
                    seen.add(parent["parent"])
                    parent = maps.get(parent["parent"], {})
                continent = next((k for k, v in maps.items() if v is parent), None)
                for x, y in points[:2]:
                    if 0 <= x <= 100 and 0 <= y <= 100:
                        result.append({"npcId": npc["id"], "name": npc["name"], "kind": "GRIMOIRE" if grimoire else match[1].upper(),
                                       "faction": side, "map": record["ui"], "x": round(x / 100, 5),
                                       "y": round(y / 100, 5), "zone": zone, "continent": continent})
    return sorted(result, key=lambda v: (v["kind"], v["npcId"], v["map"], v["x"]))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path(r"D:\World of Warcraft\_forever_\Interface\AddOns\WhatsTraining"))
    parser.add_argument("--db", type=Path, default=ROOT / "platform/public/media/db")
    parser.add_argument("--world", type=Path, default=ROOT / "platform/public/media/world/world.json")
    args = parser.parse_args()
    vm = LuaRuntime(unpack_returned_tuples=True)
    wt = vm.table()
    classes = {key: vm.table() for key in CLASSES}
    wt.forClass = lambda key: classes[key]
    for name in (*[c.title() for c in CLASSES], "HunterPets", "WarlockTomes", "QuestSpells", "TrainerFactions"):
        source = args.source / "Classes/Camelot" / (name + ".lua")
        fn = vm.eval("loadstring")(source.read_text(encoding="utf8"), name)
        if isinstance(fn, tuple):
            raise RuntimeError(f"Cannot parse {source.name}: {fn}")
        fn("TrainingData", wt)
    version = re.search(r"^## Version:\s*(.+)$", (args.source / "WhatsTraining.toc").read_text(encoding="utf8"), re.M)[1].strip()
    result = {"schema": 1, "product": "forever", "sourceVersion": version, "classes": {},
              "questSpells": native(wt.QuestSpells), "trainerFactions": native(wt.TrainerFactions)}
    for class_id, table in classes.items():
        source = native(table)
        rows = []
        for level, spells in source.get("spellsByLevel", {}).items():
            for original in spells:
                row = {"id": original["id"], "level": level, "baseCost": original.get("cost", 0)}
                for key in ("requiredIds", "requiredTalentId", "faction", "race", "races"):
                    if key in original:
                        row[key] = original[key]
                if source.get("petAbilityIds", {}).get(original["id"]):
                    row["pet"] = True
                rows.append(row)
        for level, tomes in source.get("tomesByLevel", {}).items():
            for tome in tomes:
                rows.append({"id": tome.get("id", "tome:" + str(tome["itemId"])), "level": level,
                             "itemId": tome["itemId"], "baseCost": tome.get("cost", 0), "family": tome.get("family"),
                             "taughtId": source.get("tomeTaughtSpells", {}).get(tome["itemId"]), "tome": True})
        result["classes"][class_id] = {"spells": sorted(rows, key=lambda s: (s["level"], str(s["id"]))),
                                         "overrides": source.get("overriddenGroups", [])}
    maps = json.loads(args.world.read_text(encoding="utf8"))["maps"]
    result["trainers"] = trainer_spots(args.db, maps, native(wt.WarlockTomeMerchantIds))
    out = ROOT / "addon/Evertally"
    lines = ["-- Generated by tools/build_training_data.py. Do not edit by hand.",
             "-- Forever spell facts: What's Training? " + version + " (MIT); see TrainingData-LICENSE.txt.",
             "-- Trainer coordinates: existing QuestieDB-derived reference shards; see THIRD_PARTY.md.",
             "local _, A = ...", "A.trainingData = " + lua(result)]
    (out / "TrainingData.lua").write_text("\n".join(lines) + "\n", encoding="utf8")
    (out / "TrainingData-LICENSE.txt").write_text("Training spell catalog source: What's Training? " + version +
          "\nhttps://www.curseforge.com/wow/addons/whats-training\n" +
          "Only the declarative Classes/Camelot data tables are used. Evertally's runtime and UI are its own.\n\n" +
          (args.source / "LICENSE").read_text(encoding="utf8"), encoding="utf8")
    print(json.dumps({"classes": len(result["classes"]), "spells": sum(len(v["spells"]) for v in result["classes"].values()),
                      "trainers": len(result["trainers"]), "version": version}))


if __name__ == "__main__":
    main()

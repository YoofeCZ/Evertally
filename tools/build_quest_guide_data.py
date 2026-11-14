"""Build Evertally's independent quest planner catalogue from local QuestieDB facts.

No game SavedVariables, network access or proprietary guide routes are used.
Static corrections are already folded into the installed Forever TOC. Quests with
character-dependent dynamic corrections are marked, never assumed available.
"""
from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT / ".tools/python-data"), str(ROOT / "tools")]
from db_sources import Questie, QUESTIE  # noqa: E402


def lua(value):
    if value is None: return "nil"
    if value is True: return "true"
    if value is False: return "false"
    if isinstance(value, str):
        return '"' + value.replace("\\", "\\\\").replace('"', '\\"').replace("\r", "").replace("\n", "\\n") + '"'
    if isinstance(value, (int, float)): return str(value)
    if isinstance(value, list): return "{" + ",".join(lua(v) for v in value) + "}"
    return "{" + ",".join((k if isinstance(k, str) and re.fullmatch(r"[A-Za-z_]\w*", k) else "[" + lua(k) + "]") + "=" + lua(v) for k, v in value.items() if v not in (None, [], {}, "")) + "}"


def part(value, index):
    if isinstance(value, list): return value[index - 1] if len(value) >= index else None
    if isinstance(value, dict): return value.get(index)
    return None


def ids(values):
    return [v for v in values or [] if isinstance(v, int) and not isinstance(v, bool)] if isinstance(values, list) else []


def main():
    source = Questie()
    media = ROOT / "platform/public/media"
    maps = json.loads((media / "maps/manifest.json").read_text(encoding="utf8"))["maps"]
    map_names = {ident: m["nameEn"] for m in maps for ident in m.get("uiMapIds", [])}
    enum_text = (QUESTIE / "src/corrections/enum/expansions.lua").read_text(encoding="utf8")
    race_section = enum_text.split("constants.raceMaskById = {", 1)[1].split("}", 1)[0]
    race_bits = {int(k): int(v) for k, v in re.findall(r"\[(\d+)\]\s*=\s*(\d+)", race_section)}
    alliance = sum(race_bits.get(r, 0) for r in (1, 3, 4, 7, 95))
    horde = sum(race_bits.get(r, 0) for r in (2, 5, 6, 8, 96))
    dynamic = set()
    for path in (QUESTIE / "src/corrections/Forever").rglob("*QuestFixes.lua"):
        text = path.read_text(encoding="utf8")
        if "LoadDynamic" in text:
            dynamic.update(int(v) for v in re.findall(r"^\s*\[(\d+)\]\s*=\s*\{", text.split("LoadDynamic", 1)[1], re.M))
    # Only associate dungeon IDs with quest facts, not any authored guide text.
    dungeon_for = {}
    dungeon_file = media / "db/dungeons.json"
    if dungeon_file.exists():
        raw = json.loads(dungeon_file.read_text(encoding="utf8"))
        rows = raw.get("entries", list(raw.values())) if isinstance(raw, dict) else raw
        for dungeon in rows:
            if not isinstance(dungeon, dict): continue
            for quest in dungeon.get("quests", []):
                if isinstance(quest, dict) and isinstance(quest.get("id"), int):
                    dungeon_for[quest["id"]] = dungeon.get("name") or "Dungeon"

    def spots(kind, ident):
        row = source.row(kind, ident)
        spawns = source.field(kind, ident, 7 if kind == "Npc" else 4, row)
        result = []
        if isinstance(spawns, dict):
            for area, coords in sorted(spawns.items()):
                map_id = source.area_to_ui.get(area)
                if not map_id: continue
                for point in coords if isinstance(coords, list) else []:
                    if isinstance(point, list) and len(point) >= 2 and all(isinstance(v, (int, float)) and 0 <= v <= 100 for v in point[:2]):
                        result.append({"map": map_id, "x": round(point[0] / 100, 4), "y": round(point[1] / 100, 4)})
                        break
                if len(result) >= 3: break
        return result

    def people(group):
        result = []
        for index, kind in ((1, "Npc"), (2, "Object")):
            for ident in ids(part(group, index))[:4]:
                row = source.row(kind, ident)
                result.append({"kind": kind.lower(), "id": ident, "name": row.get(1) or f"#{ident}", "spots": spots(kind, ident)})
        for ident in ids(part(group, 3))[:2]:
            result.append({"kind": "item", "id": ident, "name": source.row("Item", ident).get(1) or f"#{ident}"})
        return result

    quests = {}
    for ident in sorted(source.ids["Quest"]):
        row = source.row("Quest", ident)
        field = lambda index: source.field("Quest", ident, index, row)
        name = field(1)
        if not isinstance(name, str) or not name or name.startswith(("[DND]", "[DEPRECATED]", "OLD")): continue
        level, required = field(5), field(4)
        if not isinstance(level, int) or not isinstance(required, int) or required > 60: continue
        starters, finishers = people(field(2)), people(field(3))
        raw_obj = field(10)
        objectives = []
        for index, kind in ((1, "Npc"), (2, "Object"), (3, "Item")):
            for entry in (part(raw_obj, index) or [])[:8]:
                target = part(entry, 1)
                if not isinstance(target, int): continue
                target_row = source.row(kind, target)
                target_spots = spots(kind, target) if kind != "Item" else []
                if kind == "Item":
                    for npc in ids(source.field("Item", target, 2, target_row))[:3]: target_spots.extend(spots("Npc", npc))
                    for obj in ids(source.field("Item", target, 3, target_row))[:2]: target_spots.extend(spots("Object", obj))
                objectives.append({"kind": kind.lower(), "id": target, "name": part(entry, 2) or target_row.get(1) or f"#{target}", "count": part(entry, 3), "spots": target_spots[:4]})
        trigger = field(9)
        if isinstance(trigger, list) and isinstance(part(trigger, 2), dict):
            for area, points in part(trigger, 2).items():
                map_id = source.area_to_ui.get(area)
                point = points[0] if isinstance(points, list) and points else None
                if map_id and isinstance(point, list) and len(point) >= 2 and all(isinstance(v, (int, float)) and 0 <= v <= 100 for v in point[:2]):
                    objectives.append({"kind": "trigger", "name": part(trigger, 1) or name, "spots": [{"map": map_id, "x": round(point[0] / 100, 4), "y": round(point[1] / 100, 4)}]})
        zone = field(17)
        map_id = source.area_to_ui.get(zone) if isinstance(zone, int) and zone > 0 else None
        if not map_id:
            map_id = next((spot["map"] for p in starters + finishers for spot in p.get("spots", [])), None)
        race_mask = field(6) or 0
        faction = "Alliance" if race_mask & alliance and not race_mask & horde else "Horde" if race_mask & horde and not race_mask & alliance else None
        quests[ident] = {"id": ident, "title": name, "level": level, "minLevel": required, "map": map_id, "zone": map_names.get(map_id, "Other"),
            "raceMask": race_mask, "classMask": field(7) or 0, "faction": faction, "requiresAll": ids(field(12)), "requiresAny": ids(field(13)),
            "exclusive": ids(field(16)), "requiredSkill": field(18), "requiredMinRep": field(19), "requiredMaxRep": field(20),
            "sourceItems": ids(field(21)), "requiredSpell": field(30), "requiredSpec": field(31), "maxLevel": field(32),
            "untilCompleted": field(33), "startingWith": field(34), "requiredRanks": field(35), "disabledBy": field(36),
            "parentQuest": field(25), "nextQuest": field(22),
            "dynamic": ident in dynamic or None, "starts": starters, "ends": finishers, "objectives": objectives,
            "text": "\n".join(v for v in field(8) or [] if isinstance(v, str)), "dungeon": dungeon_for.get(ident), "flags": field(23)}
    toc = QUESTIE / "QuestieDB_Forever.toc"
    world = json.loads((media / "world/world.json").read_text(encoding="utf8"))
    zone_levels = {row["ui"]: row["level"] for row in world["maps"].values() if isinstance(row.get("level"), list)}
    zone_geometry = {row["ui"]: {"rect": row["rect"], "continent": row.get("parent")} for row in world["maps"].values()
                     if row.get("ui") and isinstance(row.get("rect"), list) and row.get("kind") in ("zone", "city")}
    payload = {"schema": 1, "source": "QuestieDB Forever baked static facts", "sourceSha256": hashlib.sha256(toc.read_bytes()).hexdigest(), "raceBits": race_bits, "zoneLevels": zone_levels, "zoneGeometry": zone_geometry, "quests": quests}
    target = ROOT / "addon/Evertally/QuestGuideData.lua"
    target.write_text("-- Generated factual catalogue; see QuestGuideData-NOTICE.txt. No authored levelling routes.\nlocal _, A = ...\nA.questGuideData=" + lua(payload) + "\n", encoding="utf8")
    print(json.dumps({"quests": len(quests), "dynamic": sum(bool(q.get("dynamic")) for q in quests.values()), "maps": len({q.get("map") for q in quests.values()}), "dungeonQuests": sum(bool(q.get("dungeon")) for q in quests.values()), "bytes": target.stat().st_size}))


if __name__ == "__main__": main()

"""Build Evertally's own dungeon journal data: addon/Evertally_DungeonJournal/DungeonData.lua.

    python -I tools/build_dungeon_data.py

Only facts, from licensed or game sources (see THIRD_PARTY.md):
  * AtlasLoot Forever (installed, GPL-2.0)  dungeons and raids, their level ranges, bosses in order, NPC IDs, loot item IDs
  * the client's Map table (shared/sources/Map.csv) + Wago LoadingScreens (build 1.60.1.70291)  the loading screen of each instance,
    drawn by the game by its file ID (no art is shipped)
  * the item cache (tools/db_sources.item_cache)  item names, quality and slot
  * QuestieDB Forever (installed) + CMaNGOS ClassicDB  boss levels, NPC IDs of Forever's own bosses, model (display) IDs for the
    portrait the game draws, spawn positions placed on the floor maps (tools/dungeon_facts.py), the level a raid's portal asks for
  * OpenMap DungeonMaps (MIT) + the client's UiMap tables  the floor maps as tile file IDs the game draws (no art is shipped)
Quests come at run time from QuestGuideData.lua (QuestieDB facts); the tactics and advice are Evertally's own (DungeonGuide*.lua).
Nothing is taken from the DungeonJournal add-on (All Rights Reserved).
"""
from __future__ import annotations

import csv
import html
import re
import sys
from pathlib import Path

import lupa

sys.path.insert(0, str(Path(__file__).resolve().parent))
import db_sources as D  # noqa: E402
import dungeon_facts as F  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "addon" / "Evertally_DungeonJournal" / "DungeonData.lua"  # (an add-on of its own since 2026-11-20)
LOADING = Path(sys.argv[1]) if len(sys.argv) > 1 else D.SOURCE / "wago-wowf-70938" / "LoadingScreens.csv"   # wago.tools, Forever's own build

# AtlasLoot key -> (journal name, client map ID for the loading screen or None, raid?)
DUNGEONS = {
    "TheHallOfThanes": ("Hall of Thanes", 3065, False), "Ragefire": ("Ragefire Chasm", 389, False),
    "TheRuinsOfLordaeron": ("Ruins of Lordaeron", 2999, False), "WailingCaverns": ("Wailing Caverns", 43, False),
    "TheDeadmines": ("The Deadmines", 36, False), "ShadowfangKeep": ("Shadowfang Keep", 33, False),
    "BlackfathomDeeps": ("Blackfathom Deeps", 48, False), "TheStockade": ("The Stockade", 34, False),
    "ExcavationSiteWetlands": ("Excavation Site: Wetlands", 2998, False), "TheCityOfDalaran": ("City of Dalaran", 2959, False),
    "Gnomeregan": ("Gnomeregan", 90, False), "RazorfenKraul": ("Razorfen Kraul", 47, False),
    "ScarletMonasteryGraveyard": ("Scarlet Monastery: Graveyard", 189, False), "ScarletMonasteryLibrary": ("Scarlet Monastery: Library", 189, False),
    "ScarletMonasteryArmory": ("Scarlet Monastery: Armory", 189, False), "ScarletMonasteryCathedral": ("Scarlet Monastery: Cathedral", 189, False),
    "TheDrownedCity": ("The Drowned City", None, False), "RazorfenDowns": ("Razorfen Downs", 129, False), "Uldaman": ("Uldaman", 70, False),
    "TheKrolDokStronghold": ("Krol'dok Stronghold", None, False), "Zul'Farrak": ("Zul'Farrak", 209, False), "Maraudon": ("Maraudon", 349, False),
    "TheAlcazPrison": ("Alcaz Prison", None, False), "TheTempleOfAtal'Hakkar": ("Sunken Temple", 109, False),
    "BlackrockDepths": ("Blackrock Depths", 230, False), "DireMaulEast": ("Dire Maul: East", 429, False),
    "TheBlackmawHold": ("Blackmaw Hold", None, False), "LowerBlackrockSpire": ("Lower Blackrock Spire", 229, False),
    "UpperBlackrockSpire": ("Upper Blackrock Spire", 229, False), "DireMaulWest": ("Dire Maul: West", 429, False),
    "DireMaulNorth": ("Dire Maul: North", 429, False), "ShapersTerrace": ("Shaper's Terrace", None, False),
    "Stratholme": ("Stratholme", 329, False), "Scholomance": ("Scholomance", 289, False),
    "MoltenCore": ("Molten Core", 409, True), "OnyxiasLairNew": ("Onyxia's Lair", 249, True), "BlackwingLair": ("Blackwing Lair", 469, True),
    "Zul'Gurub": ("Zul'Gurub", 309, True), "TheRuinsofAhnQiraj": ("Ruins of Ahn'Qiraj", 509, True),
    "TheTempleofAhnQiraj": ("Temple of Ahn'Qiraj", 531, True), "Naxxramas": ("Naxxramas", 533, True),
    "BarrowDeepsRaid": ("Barrow Deeps", None, True), "MountHyjal": ("Hyjal Summit", None, True),
}
# AtlasLoot keeps Stratholme as one; the journal shows its two sides
STRAT_UNDEAD = {"Magistrate Barthilas", "Stonespine", "Baroness Anastari", "Black Guard Swordsmith", "Nerub'enkan", "Maleki the Pallid",
                "Ramstein the Gorger", "Baron Rivendare"}
# groups in AtlasLoot's lists that are not a boss
NOT_A_BOSS = re.compile(r"^(Keys?|Plans|Books|Atiesh|Defias Gunpowder|Stratholme Courier|Quest Items?|Misc.*|Shared.*|Random.*|.*\bSets?\b.*"
                        r"|.*Heirlooms.*|.*Tier \d.*|.*\bQuest\b.*|.*Rewards.*|.*\b(Chest|Strongbox|Coffer|Cache|Urn|Tablet)\b.*|.*No drops.*"
                        r"|.*Provisioner|.*Book of .*|.*Smithing Hammer)$", re.I)


def lua_string(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def item_facts() -> dict[int, tuple[str, int, str]]:
    """item id -> (name, quality, slot text such as "Two-Hand, Axe") from the item cache's tooltip."""
    out = {}
    for row in D.item_cache():
        tip = row.get("tooltipHtml") or ""
        q = re.search(r'class="q(\d)"', tip)
        cells = re.search(r'<table width="100%"><tr><td>([^<]+)</td>(?:<th>(?:<!--[^>]*-->)?(?:<span[^>]*>)?([^<]*))?', tip)
        slot = ", ".join(v for v in ((cells.group(1), cells.group(2)) if cells else ()) if v and v.strip())
        out[int(row["itemId"])] = (html.unescape(row.get("name") or ""), int(q.group(1)) if q else 1, slot)
    # names of the rest from the site's item index (game data: id, name, ..., quality at index 4)
    import json
    index = json.loads((ROOT / "shared" / "assets" / "db" / "search.json").read_text(encoding="utf8"))
    for row in index.get("items", []):
        if isinstance(row, list) and len(row) > 4 and isinstance(row[0], int) and row[0] not in out and isinstance(row[1], str):
            out[row[0]] = (row[1], row[4] if isinstance(row[4], int) and 0 <= row[4] <= 7 else 1, "")
    return out


def loading_art() -> dict[int, int]:
    """client map ID -> loading screen file ID."""
    if not LOADING or not LOADING.exists():
        return {}
    screens = {r["ID"]: r for r in csv.DictReader(LOADING.open(encoding="utf8"))}
    out = {}
    for row in csv.DictReader((ROOT / "shared" / "sources" / "Map.csv").open(encoding="utf8")):
        screen = screens.get(row["LoadingScreenID"])
        if screen:
            file = int(screen["MainImageFileDataID"] or 0) or int(screen["NarrowScreenFileDataID"] or 0) or int(screen["WideScreenFileDataID"] or 0)
            if file:
                out[int(row["ID"])] = file
    return out


def main() -> None:
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    data = lua.execute(D._ATLAS_PRELUDE)((D.ATLASLOOT / "data.lua").read_text(encoding="utf8"), "data.lua")
    table = lambda v: v if lupa.lua_type(v) == "table" else None  # noqa: E731
    items, art = item_facts(), loading_art()
    questie = D.Questie()
    q_names: dict[str, list[int]] = {}
    for nid in questie.ids["Npc"]:
        n = questie.row("Npc", nid).get(1)
        if isinstance(n, str):
            q_names.setdefault(n, []).append(nid)
    classic = F.ClassicDB()
    floors = F.Floors()
    displays = F.forever_displays()
    used_floors: set[int] = set()

    def enrich(b: dict, map_id) -> None:
        """the NPC ID (Forever's own bosses: the only one of that name QuestieDB places somewhere), level, model and place"""
        if not b["npc"]:
            placed = [n for n in q_names.get(b["name"], []) if questie.field("Npc", n, 9) is not None]
            if len(placed) == 1:
                b["npc"] = placed[0]
        npc = b["npc"]
        if map_id:
            where = floors.journal_place(map_id, b["name"])
            if where:
                b["pos"] = list(where)
                used_floors.add(map_id)
        if not npc:
            return
        row = questie.row("Npc", npc)
        t = classic.templates.get(npc)
        low, high = row.get(4), row.get(5)
        if not (isinstance(low, int) and low > 0) and t:
            low, high = t["min"], t["max"]
        if isinstance(low, int) and 0 < low < 100:
            b["level"] = [low, high if isinstance(high, int) and high >= low else low]
        if t:
            model = next((m for m in t["models"] if m in displays), None)
            if model:
                b["display"] = model
        for spawn_map, x, y, z in classic.spawns.get(npc, []):
            if map_id and spawn_map == map_id:
                where = floors.place(map_id, x, y, z)
                if where:
                    b["pos"] = list(where)
                    used_floors.add(map_id)
                    break
    dungeons: dict[str, dict] = {}
    for key, (name, map_id, raid) in DUNGEONS.items():
        inst = table(data[key])
        if not inst:
            print(f"missing in AtlasLoot: {key}")
            continue
        levels = table(inst["LevelRange"])
        level = [int(levels[i]) for i in (1, 2, 3)] if levels else None
        bosses = []
        rows = table(inst["items"])
        for index in range(1, len(rows) + 1 if rows else 1):
            boss = table(rows[index])
            label = boss and boss["name"]
            label = label.strip() if isinstance(label, str) else label
            if label == "Chest of The Seven":   # the loot of The Seven, the event's chest
                label = "The Seven"
            if not isinstance(label, str) or NOT_A_BOSS.match(label):
                continue
            if re.match(r"^Trash", label, re.I):
                label = "Trash Drops"
            loot: list[int] = []
            for diff in boss.keys():
                lst = table(boss[diff])
                if lupa.lua_type(diff) != "table" or not lst:
                    continue
                for i in range(1, len(lst) + 1):
                    row = table(lst[i])
                    item = row[2] if row else None
                    if isinstance(item, (int, float)) and item >= 100 and int(item) not in loot:
                        loot.append(int(item))
            npc = boss["npcID"]
            bosses.append({"name": label, "npc": int(npc) if isinstance(npc, (int, float)) else None, "loot": loot})
        if not level and raid and map_id and classic.portal_level.get(map_id):
            level = [classic.portal_level[map_id], 60, 60]   # a vanilla raid: its portal's level, and level-60 content
        for b in bosses:
            enrich(b, map_id)
        entry = {"name": name, "level": level, "raid": raid, "art": art.get(map_id) if map_id else None, "bosses": bosses,
                 "floors": map_id if map_id in floors.floors else None}
        if key == "Stratholme":
            living = [b for b in bosses if b["name"] not in STRAT_UNDEAD]
            undead = [b for b in bosses if b["name"] in STRAT_UNDEAD]
            dungeons["Stratholme: Living"] = {**entry, "name": "Stratholme: Living", "bosses": living}
            dungeons["Stratholme: Undead"] = {**entry, "name": "Stratholme: Undead", "bosses": undead}
        else:
            dungeons[name] = entry
    lines = ["local _, M = ...",
             "-- Evertally's own dungeon journal data, generated by tools/build_dungeon_data.py (do not edit): AtlasLoot Forever (GPL-2.0) for",
             "-- levels, bosses, NPC IDs and loot item IDs; the client's Map/LoadingScreens tables for the art (a file ID the game draws); item",
             "-- names from the item cache. Facts only. Quests come from QuestGuideData.lua, tactics from DungeonGuide*.lua.",
             "M.dungeonData = {"]
    missing_items = 0
    for name, d in sorted(dungeons.items(), key=lambda kv: ((kv[1]["level"] or [99, 99])[1], kv[0])):
        parts = [f"name={lua_string(d['name'])}", f"raid={'true' if d['raid'] else 'false'}"]
        if d["level"]:
            parts.append("level={%d,%d,%d}" % tuple(d["level"]))
        if d["art"]:
            parts.append(f"art={d['art']}")
        if d["floors"] and d["floors"] in used_floors:
            parts.append(f"floors={d['floors']}")
        bosses = []
        for b in d["bosses"]:
            loot = []
            for item in b["loot"]:
                facts = items.get(item)
                if facts and facts[0]:
                    loot.append("{%d,%s,%s,%d}" % (item, lua_string(facts[0]), lua_string(facts[2]), facts[1]))
                else:
                    missing_items += 1
                    loot.append("{%d}" % item)
            npc = f",npc={b['npc']}" if b["npc"] else ""
            if b.get("level"):
                npc += ",level={%d,%d}" % tuple(b["level"])
            if b.get("display"):
                npc += f",display={b['display']}"
            if b.get("pos"):
                npc += ",pos={%d,%s,%s}" % (b["pos"][0] + 1, b["pos"][1], b["pos"][2])
            bosses.append("{name=%s%s,loot={%s}}" % (lua_string(b["name"]), npc, ",".join(loot)))
        parts.append("bosses={" + ",\n    ".join(bosses) + "}")
        lines.append(f"[{lua_string(name)}] = {{" + ", ".join(parts) + "},")
    lines.append("}")
    # the floors of each instance: {tiles = 12 file IDs (4 x 3 of 256 px, the picture is the top left 1002 x 668), name}
    lines.append("M.dungeonFloors = {")
    for map_id in sorted(used_floors):
        rows = []
        for floor in floors.floors[map_id]:
            name = f", name={lua_string(floor['name'])}" if floor.get("name") else ""
            rows.append("{tiles={%s}%s}" % (",".join(str(t) for t in floor["tiles"]), name))
        lines.append(f"[{map_id}] = {{" + ", ".join(rows) + "},")
    lines.append("}")
    OUT.write_text("\n".join(lines) + "\n", encoding="utf8")
    print(f"{len(dungeons)} dungeons and raids, {sum(len(d['bosses']) for d in dungeons.values())} bosses, "
          f"{sum(len(b['loot']) for d in dungeons.values() for b in d['bosses'])} loot rows ({missing_items} without a cached name), "
          f"{sum(1 for d in dungeons.values() if d['art'])} with art; bosses with a level {sum(1 for d in dungeons.values() for b in d['bosses'] if b.get('level'))}, "
          f"a portrait {sum(1 for d in dungeons.values() for b in d['bosses'] if b.get('display'))}, a place {sum(1 for d in dungeons.values() for b in d['bosses'] if b.get('pos'))}; "
          f"{len(used_floors)} instances with floor maps -> {OUT}")


if __name__ == "__main__":
    main()

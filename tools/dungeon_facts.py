"""Facts about dungeon bosses and floors for tools/build_dungeon_data.py. Local files only (download them once, see THIRD_PARTY.md):

  * shared/sources/ClassicDB_1_12_1_z2815.sql.gz  CMaNGOS ClassicDB (GPL-2.0): creature levels, rank and model (display) IDs,
    spawn positions in the instance, the level an instance's portal asks for
  * shared/assets/world/floors-src.json            OpenMap's DungeonMaps table (MIT): the 4 x 3 tile file IDs of each floor
  * shared/sources/wago-classic-5.5.4/              the client's UiMap tables (UiMapAssignment, UiMapXMapArt, UiMapArtTile),
    build 5.5.4.70631 from wago.tools: which floor a tile belongs to and the world rectangle each floor shows
  * shared/sources/wago-wowf-70938/CreatureDisplayInfo.csv  Forever's own display IDs (a model the client does not have is left out)
"""
from __future__ import annotations

import csv
import gzip
import json
import re
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "shared" / "sources"
CLASSICDB = SOURCE / "ClassicDB_1_12_1_z2815.sql.gz"
UIMAP = SOURCE / "wago-classic-5.5.4"
FOREVER = SOURCE / "wago-wowf-70938"
FLOORS = ROOT / "shared" / "assets" / "world" / "floors-src.json"


def _tuples(line: str):
    """The rows of one `INSERT INTO ... VALUES (...),(...);` line, as lists of str/None (quotes and escapes resolved)."""
    i, n = line.index("VALUES ") + 7, len(line)
    while i < n:
        if line[i] != "(":
            i += 1
            continue
        i += 1
        row, cur, quoted = [], [], False
        while i < n:
            c = line[i]
            if quoted:
                if c == "\\" and i + 1 < n:
                    cur.append(line[i + 1]); i += 2; continue
                if c == "'":
                    quoted = False
                else:
                    cur.append(c)
            elif c == "'":
                quoted = True
            elif c in ",)":
                value = "".join(cur)
                row.append(None if value == "NULL" else value)
                cur = []
                if c == ")":
                    i += 1
                    break
            else:
                cur.append(c)
            i += 1
        yield row


class ClassicDB:
    """creature_template, creature (spawns) and areatrigger_teleport, read once."""

    def __init__(self, wanted_spawns: set[int] | None = None) -> None:
        self.columns: dict[str, list[str]] = {}
        self.templates: dict[int, dict] = {}
        self.by_name: dict[str, list[int]] = defaultdict(list)
        self.spawns: dict[int, list[tuple[int, float, float, float]]] = defaultdict(list)
        self.portal_level: dict[int, int] = {}
        table = None
        with gzip.open(CLASSICDB, "rt", encoding="utf8", errors="replace") as sql:
            for line in sql:
                m = re.match(r"CREATE TABLE `(\w+)`", line)
                if m:
                    table = m.group(1); self.columns[table] = []; continue
                if table and re.match(r"\s+`(\w+)`", line):
                    self.columns[table].append(re.match(r"\s+`(\w+)`", line).group(1)); continue
                if table and not line.startswith("  "):
                    table = None
                if line.startswith("INSERT INTO `creature_template` VALUES "):
                    cols = self.columns["creature_template"]
                    for row in _tuples(line):
                        r = dict(zip(cols, row))
                        entry = int(r["Entry"])
                        models = [int(r[f"ModelId{k}"]) for k in (1, 2, 3, 4) if r.get(f"ModelId{k}") and int(r[f"ModelId{k}"]) > 0]
                        self.templates[entry] = {"name": r["Name"], "min": int(r["MinLevel"]), "max": int(r["MaxLevel"]), "rank": int(r["Rank"]), "models": models}
                        self.by_name[r["Name"]].append(entry)
                elif line.startswith("INSERT INTO `creature` VALUES "):
                    cols = self.columns["creature"]
                    for row in _tuples(line):
                        r = dict(zip(cols, row))
                        npc = int(r["id"])
                        if wanted_spawns is None or npc in wanted_spawns:
                            self.spawns[npc].append((int(r["map"]), float(r["position_x"]), float(r["position_y"]), float(r["position_z"])))
                elif line.startswith("INSERT INTO `areatrigger_teleport` VALUES "):
                    cols = self.columns["areatrigger_teleport"]
                    for row in _tuples(line):
                        r = dict(zip(cols, row))
                        target, level = int(r["target_map"]), int(r["required_level"])
                        if level > 0:
                            self.portal_level[target] = min(level, self.portal_level.get(target, level))


def _rows(path: Path) -> list[dict]:
    return list(csv.DictReader(path.open(encoding="utf8")))


def forever_displays() -> set[int]:
    return {int(r["ID"]) for r in _rows(FOREVER / "CreatureDisplayInfo.csv")}


class Floors:
    """The floors of each instance (OpenMap's order and tiles) with the UiMap each one is and the world rectangle it shows."""

    def __init__(self) -> None:
        self.floors: dict[int, list[dict]] = {int(k): v for k, v in json.loads(FLOORS.read_text(encoding="utf8"))["floors"].items()}
        art_tiles: dict[str, set[int]] = defaultdict(set)
        for t in _rows(UIMAP / "UiMapArtTile.csv"):
            art_tiles[t["UiMapArtID"]].add(int(t["FileDataID"]))
        tile_ui: dict[int, int] = {}
        for x in _rows(UIMAP / "UiMapXMapArt.csv"):
            for f in art_tiles.get(x["UiMapArtID"], ()):
                tile_ui[f] = int(x["UiMapID"])
        for floors in self.floors.values():
            for floor in floors:
                uis = {tile_ui[f] for f in floor["tiles"] if f in tile_ui}
                floor["ui"] = uis.pop() if len(uis) == 1 else None
        self.rects: dict[int, list[tuple]] = defaultdict(list)   # ui map -> [(map, minX, minY, minZ, maxX, maxY, maxZ, uiMin, uiMax)]
        for a in _rows(UIMAP / "UiMapAssignment.csv"):
            region = [float(a[f"Region_{k}"]) for k in range(6)]
            ui = (float(a["UiMin_0"]), float(a["UiMin_1"]), float(a["UiMax_0"]), float(a["UiMax_1"]))
            self.rects[int(a["UiMapID"])].append((int(a["MapID"]), *region, ui))

        # the client's encounter journal (5.5.4) marks its bosses on these same floors: used where the database has no spawn
        # (a boss summoned by a script); only a mark on a floor of the right instance counts
        self.journal: dict[str, list[tuple[int, float, float]]] = defaultdict(list)
        for e in _rows(UIMAP / "JournalEncounter.csv"):
            if int(e["UiMapID"] or 0) > 0 and (float(e["Map_0"]) or float(e["Map_1"])):
                self.journal[e["Name_lang"].casefold()].append((int(e["UiMapID"]), round(float(e["Map_0"]), 4), round(float(e["Map_1"]), 4)))

    def journal_place(self, map_id: int, name: str):
        for ui, u, v in self.journal.get(name.casefold(), []):
            for index, floor in enumerate(self.floors.get(map_id, [])):
                if floor.get("ui") == ui:
                    return index, u, v
        return None

    def place(self, map_id: int, x: float, y: float, z: float):
        """(floor index, u, v) of a world position on an instance's floors, or None. Of overlapping floors the smallest rectangle wins."""
        best = None
        for index, floor in enumerate(self.floors.get(map_id, [])):
            for m, x0, y0, z0, x1, y1, z1, (u0, v0, u1, v1) in self.rects.get(floor.get("ui"), []):
                if m != map_id or not (x0 <= x <= x1 and y0 <= y <= y1 and z0 <= z <= z1) or x1 == x0 or y1 == y0:
                    continue
                area = (x1 - x0) * (y1 - y0)
                # world x is north and y is west: the map's left is the largest y, its top the largest x
                u = u0 + (y1 - y) / (y1 - y0) * (u1 - u0)
                v = v0 + (x1 - x) / (x1 - x0) * (v1 - v0)
                if best is None or area < best[0]:
                    best = (area, index, round(u, 4), round(v, 4))
        return best and best[1:]

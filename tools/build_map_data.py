"""Seamless-world data for the web map. No network, no player data.

Reads (all inside shared/sources):
  UiMap*.csv + tools-uimap.py   where every game map lies on Azeroth's map (947), as C_Map.GetMapRectOnMap does
  openmap/*.lua                 OpenMap (MIT): zone levels, dungeon entrances, boats/zeppelins, dungeon floor tiles
  spf/Taxi.lua                  Shortest Path Forever (GPL-3): flight nodes, paths and measured flight seconds

Writes shared/assets/world/*.json and mirrors them to platform/public/media/world.
All coordinates leave this script as (u, v): normalised positions on Azeroth's map, so the web map can
draw every layer in one coordinate space.
"""
from __future__ import annotations

import importlib.util
import json
import shutil
import sys
from pathlib import Path

import lupa

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "shared" / "sources"
OUT = ROOT / "shared" / "assets" / "world"
PUBLIC = ROOT / "platform" / "public" / "media" / "world"
MANIFEST = ROOT / "platform" / "public" / "media" / "maps" / "manifest.json"
DB = ROOT / "platform" / "public" / "media" / "db"

CITIES = {"orgrimmar", "thunder-bluff", "darnassus", "stormwind-city", "ironforge", "undercity"}
CONTINENTS = {"kalimdor": 1414, "eastern-kingdoms": 1415}
FACTION = {"Alliance": "A", "Horde": "H"}


def _uimap():
    spec = importlib.util.spec_from_file_location("uimap", SRC / "tools-uimap.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.World(str(SRC))


def _lua(path: Path, table: str):
    """Run an addon data file in a bare Lua state and hand back one of the tables it fills in."""
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    ns = lua.eval("{ Docks = {} }")
    lua.eval("function(src, ns) local f = assert(load(src, '@data')); return f('addon', ns) end")(path.read_text(encoding="utf8"), ns)
    return _py(ns[table])


def _py(value):
    if lupa.lua_type(value) != "table":
        return value
    keys = list(value.keys())
    if keys and all(isinstance(k, int) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
        return [_py(value[k]) for k in sorted(keys)]
    return {str(k): _py(value[k]) for k in keys}


class Yards:
    """World yards on a game map -> (u, v) on Azeroth's map."""

    def __init__(self, world):
        self.world = world
        self.cache: dict[int, list] = {}

    def __call__(self, gamemap: int, x: float, y: float, margin: float = 0.2):
        regions = self.cache.setdefault(gamemap, self.world.yards(gamemap))
        for x0, x1, y0, y1, au, bu, av, bv in regions:
            mx, my = (x1 - x0) * margin, (y1 - y0) * margin
            if x0 - mx <= x <= x1 + mx and y0 - my <= y <= y1 + my:
                return round(au + bu * y, 5), round(av + bv * x, 5)
        return None


def r5(value: float) -> float:
    return round(value, 5)


def build_world(world, manifest) -> dict:
    levels = {int(k): v for k, v in _lua(SRC / "openmap" / "Levels.lua", "MapLevels").items()}
    maps: dict[str, dict] = {}
    for entry in manifest:
        ids = entry.get("uiMapIds") or []
        rect = world.rect(ids[0]) if ids else None
        if not rect or entry["width"] < 1000:
            continue
        bounds = entry.get("bounds") or {}
        key = entry["key"]
        kind = "world" if key == "azeroth" else "continent" if key in CONTINENTS else "city" if key in CITIES else "zone"
        maps[key] = {
            "ui": ids[0], "kind": kind, "rect": [r5(v) for v in rect], "parent": bounds.get("parentKey"),
            **({"level": levels[ids[0]]} if ids[0] in levels else {}),
        }
    return {"schema": 1, "size": [1002, 668], "maps": maps}


def build_flights(yards: Yards) -> dict:
    taxi = SRC / "spf" / "Taxi.lua"
    nodes_raw = _lua(taxi, "TaxiNodes")
    paths_raw = _lua(taxi, "TaxiPaths")
    nodes: dict[str, dict] = {}
    for key, node in nodes_raw.items():
        uv = yards(int(node["map"]), node["x"], node["y"])
        if uv:
            name, _, zone = node["name"].partition(", ")
            nodes[key] = {"n": node["name"], "z": zone or None, "f": FACTION.get(node.get("faction", ""), ""), "u": uv[0], "v": uv[1]}
    paths = []
    for path in paths_raw:
        if str(path["from"]) not in nodes or str(path["to"]) not in nodes:
            continue
        flat = path["points"]
        points = []
        for i in range(0, len(flat) - 2, 3):
            uv = yards(int(flat[i]), flat[i + 1], flat[i + 2], margin=0.3)
            if uv:
                points.append([uv[0], uv[1]])
        paths.append({"a": path["from"], "b": path["to"], "s": path["seconds"], "p": points})
    return {"schema": 1, "nodes": nodes, "paths": paths, "source": "Shortest Path Forever (GPL-3.0); flight seconds from InFlight (MIT); OpenMap (MIT)"}


def _entry(e) -> dict:
    """{ mapID, name, raid[, minLevel, maxLevel] }: the level range is missing for some raids"""
    at = lambda i: e[i] if len(e) > i else None
    return {"map": e[0], "name": e[1], "raid": bool(at(2)), "min": at(3), "max": at(4)}


def build_places(world, yards: Yards, manifest) -> dict:
    places = _lua(SRC / "openmap" / "Places.lua", "MapPlaces")
    by_ui = {m["uiMapIds"][0]: m["key"] for m in manifest if m.get("uiMapIds")}

    def spot(row):
        """(u, v) of an entry: world yards on continent 0/1, or a 0..1 spot on a zone's own map."""
        if isinstance(row, dict):
            ui = row.get("map")
            rect = world.rect(ui) if ui else None
            if not rect:
                return None
            return r5(rect[0] + float(row["2"]) * (rect[1] - rect[0])), r5(rect[2] + float(row["3"]) * (rect[3] - rect[2]))
        continent = int(row[0])
        return yards(continent, float(row[1]), float(row[2]))

    instances = []
    for row in places["instances"]:
        uv = spot(row)
        if not uv:
            continue
        entries = row["4"] if isinstance(row, dict) else row[3]
        instances.append({"u": uv[0], "v": uv[1], "list": [_entry(e) for e in entries]})
    unplaced = [_entry(e) for e in places["unplaced"]]

    transports = []
    for row in places["transports"]:
        faction = None
        if isinstance(row, dict):
            faction = row.get("faction")
            row = [row[str(i)] for i in range(1, 9)]
        kind, route, c0, x0, y0, c1, x1, y1 = row[:8]
        a, b = yards(int(c0), x0, y0), yards(int(c1), x1, y1)
        if a and b:
            transports.append({"kind": kind, "route": route, "a": list(a), "b": list(b), **({"faction": faction} if faction else {})})
    sailings = []
    for kind, route, pieces in places["sailings"]:
        line = []
        for continent, flat in pieces:
            piece = [yards(int(continent), flat[i], flat[i + 1], margin=0.4) for i in range(0, len(flat) - 1, 2)]
            line.append([list(p) for p in piece if p])
        sailings.append({"kind": kind, "route": route, "pieces": [p for p in line if p]})
    bosses = {str(k): v for k, v in places["bosses"].items()}
    return {"schema": 1, "instances": instances, "unplaced": unplaced, "transports": transports, "sailings": sailings, "bosses": bosses, "zones": by_ui}


def build_floors() -> dict:
    floors = _lua(SRC / "openmap" / "DungeonMaps.lua", "MapDungeonMaps")
    return {"schema": 1, "floors": {k: [{"tiles": f["tiles"], "name": f.get("name"), "wing": f.get("wing")} for f in v] for k, v in floors.items()}}


def write(name: str, data) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    text = json.dumps(data, ensure_ascii=False, separators=(",", ":"))
    (OUT / name).write_text(text, encoding="utf8")
    print(f"  {name:18s} {len(text) / 1024:7.1f} KB")


def main() -> None:
    manifest = json.loads(MANIFEST.read_text(encoding="utf8"))["maps"]
    world = _uimap()
    yards = Yards(world)
    print("building world data")
    write("world.json", build_world(world, manifest))
    write("flights.json", build_flights(yards))
    write("places.json", build_places(world, yards, manifest))
    write("floors-src.json", build_floors())
    PUBLIC.mkdir(parents=True, exist_ok=True)
    for f in OUT.glob("*.json"):
        if f.name != "floors-src.json":
            shutil.copy2(f, PUBLIC / f.name)
    print("mirrored to", PUBLIC.relative_to(ROOT))


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()

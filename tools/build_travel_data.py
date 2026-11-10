"""Data for the web travel planner (walking, flights, boats, zeppelins, lifts, the tram, portals). No network, no player data.

Reads, from the installed Shortest Path Forever addon (GPL-3.0; Blizzard client tables, cmangos classic-db, InFlight durations):
  Data/Walks.lua       running yards between fixed places (taxi nodes, docks, portal ends), baked from the game's terrain
  Data/Routes.lua      boat and zeppelin timetables
  Data/Transports.lua  lifts and the Deeprun Tram timetables
  Data/Portals.lua     portals and passages
  Data/Taxi.lua        flight nodes, paths and measured flight seconds (shared with flights.json)
and OpenMap's place names for docks (MIT). Only facts are used, written to shared/assets/world/travel.json.
Run after build_map_data.py:  python tools/build_travel_data.py
"""
from __future__ import annotations

import json
import math
import shutil
import sys
from pathlib import Path

import lupa

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_map_data as maps  # noqa: E402

ROOT = maps.ROOT
OUT = maps.OUT
PUBLIC = maps.PUBLIC
SPF = Path(r"D:\World of Warcraft\_forever_\Interface\AddOns\ShortestPathForever\Data")
FACTION = {"Alliance": "A", "Horde": "H"}


def lua_file(name: str, *tables: str) -> dict:
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    ns = lua.eval("{ Docks = {}, Routes = {}, Portals = {}, Entrances = {}, WalkPlaces = {}, Walks = {} }")
    lua.eval("function(src, ns) local f = assert(load(src, '@data')); return f('addon', ns) end")((SPF / name).read_text(encoding="utf8"), ns)
    return {table: maps._py(ns[table]) for table in tables}


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    world = maps._uimap()
    yards = maps.Yards(world)
    manifest = json.loads(maps.MANIFEST.read_text(encoding="utf8"))["maps"]

    walk_data = lua_file("Walks.lua", "WalkPlaces", "Walks")
    route_data = lua_file("Routes.lua", "Docks", "Routes")
    transport_data = lua_file("Transports.lua", "Docks", "Routes")
    portal_data = lua_file("Portals.lua", "Portals")
    taxi_data = lua_file("Taxi.lua", "TaxiNodes", "Landmasses")
    places = json.loads((OUT / "places.json").read_text(encoding="utf8"))
    flights = json.loads((OUT / "flights.json").read_text(encoding="utf8"))
    del manifest, places

    # ---- hubs: every fixed place the walking table knows, in yards on its continent ----
    hubs: dict[str, dict] = {}

    def add_hub(key: str, continent: int, x: float, y: float, name: str | None = None, faction: str = "", pin: tuple[float, float] | None = None):
        uv = yards(continent, x, y, margin=0.4)
        if pin:
            uv = yards(0, pin[0], pin[1], margin=0.4) or uv
        hubs[key] = {"c": continent, "x": round(x, 1), "y": round(y, 1), **({"u": uv[0], "v": uv[1]} if uv else {}), **({"n": name} if name else {}), **({"f": faction} if faction else {})}

    for continent, places_on in walk_data["WalkPlaces"].items():
        for key, (x, y) in places_on.items():
            add_hub(key, int(continent), x, y)

    # taxi hubs: names and factions
    for key, node in taxi_data["TaxiNodes"].items():
        hub = hubs.get(f"taxi{key}")
        if hub is not None:
            hub["n"] = node["name"]
            if node.get("faction") in FACTION:
                hub["f"] = FACTION[node["faction"]]

    # docks: boats and zeppelins take the town's name from the flight master standing nearby, falling back to OpenMap's route names;
    # lifts and the tram carry their own names
    taxi_hubs = [(h["c"], h["x"], h["y"], h.get("n", "").partition(", ")[0]) for k, h in hubs.items() if k.startswith("taxi") and h.get("n")]
    endpoints = []
    for row in maps._lua(maps.SRC / "openmap" / "Places.lua", "MapPlaces")["transports"]:
        if isinstance(row, dict):
            row = [row[str(i)] for i in range(1, 9)]
        kind, route, c0, x0, y0, c1, x1, y1 = row[:8]
        parts = route.split(" - ")
        endpoints.append((int(c0), x0, y0, route, parts))
    docks: dict[str, dict] = {}
    for index, dock in enumerate(route_data["Docks"], start=1):
        docks[str(index)] = dock
    for key, dock in transport_data["Docks"].items():
        docks[key] = dock
    names: dict[str, str] = {}
    for key, dock in docks.items():
        if dock.get("site"):
            names[key] = f"{dock['site']} ({dock['name']})" if dock.get("name") else dock["site"]
            continue
        near = min((t for t in taxi_hubs if t[0] == dock["map"]), key=lambda t: (t[1] - dock["x"]) ** 2 + (t[2] - dock["y"]) ** 2, default=None)
        if near and math.hypot(near[1] - dock["x"], near[2] - dock["y"]) < 1200:
            names[key] = near[3]
    # a dock still unnamed is the other end of a named one's route
    for route in list(route_data["Routes"].values()):
        ends = [str(stop["dock"]) for stop in route["stops"]]
        for end in ends:
            if end in names:
                continue
            here = docks[end]
            match = min((e for e in endpoints if e[0] == here["map"]), key=lambda e: (e[1] - here["x"]) ** 2 + (e[2] - here["y"]) ** 2, default=None)
            others = {names[o] for o in ends if o in names}
            if match:
                options = [p for p in match[4] if p not in others]
                names[end] = options[0] if options else match[3]
    for key, dock in docks.items():
        hub_key = f"dock{key}"
        name = names.get(key) or f"Dock {key}"
        if hub_key in hubs:
            hubs[hub_key]["n"] = name
        else:  # the tram's stations (map 369) are not on the walking tables: they pin to Ironforge / Stormwind
            pin = dock.get("pin")
            add_hub(hub_key, int(dock["map"]), dock["x"], dock["y"], name, pin=(pin["x"], pin["y"]) if pin else None)

    # ---- portals: portal 2i-1 is the entrance, 2i the exit ----
    portals = []
    for index, portal in enumerate(portal_data["Portals"], start=1):
        for side, number in (("from", index * 2 - 1), ("to", index * 2)):
            point = portal[side]
            key = f"portal{number}"
            if key not in hubs:
                add_hub(key, int(point["map"]), point["x"], point["y"])
            hubs[key]["n"] = portal["name"]
        portals.append({"n": portal["name"], "k": portal["kind"], "a": f"portal{index * 2 - 1}", "b": f"portal{index * 2}", "s": portal["seconds"]})

    # ---- timetables ----
    routes = []
    for source in (route_data["Routes"], transport_data["Routes"]):
        for route_id, route in source.items():
            routes.append({
                "id": int(route_id), "k": route["kind"], **({"f": FACTION[route["faction"]]} if route.get("faction") in FACTION else {}),
                **({"site": route["site"]} if route.get("site") else {}), "p": route["period"],
                "stops": [[f"dock{stop['dock']}", stop["arrive"], stop["depart"]] for stop in route["stops"]],
            })

    # ---- baked walking yards: "a b" with a < b, [forward, reverse], null where there is no way ----
    walks: dict[str, dict] = {}
    for continent, pairs in walk_data["Walks"].items():
        out = {}
        for key, cost in pairs.items():
            values = list(cost) if isinstance(cost, list) else [cost["1"], cost["2"]] + ([cost["3"], cost["4"]] if "3" in cost else [])
            forward = values[0]
            reverse = values[2] if len(values) > 2 else forward
            out[key] = [None if v is False or v is None else round(v) for v in (forward, reverse)]
            if out[key] == [None, None]:
                out[key] = None
        walks[continent] = out

    # ---- how yards and (u, v) convert back and forth ----
    regions = {}
    for continent in (0, 1):
        x0, x1, y0, y1, au, bu, av, bv = world.yards(continent)[0]
        regions[str(continent)] = [x0, x1, y0, y1, au, bu, av, bv]

    data = {
        "schema": 1, "yards": regions, "hubs": hubs, "walks": walks, "routes": routes, "portals": portals,
        "landmasses": [{"c": int(m["map"]), "n": m["name"], "x0": m["minX"], "x1": m["maxX"], "y0": m["minY"], "y1": m["maxY"]} for m in taxi_data["Landmasses"]],
        "flights": {"nodes": sorted(int(k) for k in flights["nodes"])},
        "source": "Shortest Path Forever (GPL-3.0): walking yards baked from the game's terrain, timetables from the game's transport tables and cmangos classic-db, measured flight seconds from InFlight (MIT); dock names from OpenMap (MIT)",
    }
    text = json.dumps(data, ensure_ascii=False, separators=(",", ":"))
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "travel.json").write_text(text, encoding="utf8")
    PUBLIC.mkdir(parents=True, exist_ok=True)
    (PUBLIC / "travel.json").write_text(text, encoding="utf8")
    print(f"travel.json {len(text) / 1024:.0f} KB: {len(hubs)} hubs, {sum(len(v) for v in walks.values())} walks, {len(routes)} routes, {len(portals)} portals")
    missing = [k for k, h in hubs.items() if "u" not in h]
    print("hubs without a world position:", missing)
    shutil.copy2(OUT / "travel.json", PUBLIC / "travel.json")


if __name__ == "__main__":
    main()

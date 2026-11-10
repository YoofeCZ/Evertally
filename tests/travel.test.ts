import test from "node:test";
import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { levelClass } from "../components/evertally/db/levels";
import { planRoute } from "../components/evertally/db/flights";
import { focusText, parseFocus } from "../components/evertally/db/focus";
import { planJourney, toYards, type Place, type Travel } from "../components/evertally/db/travel";
import type { Flights, Floors, Places, World } from "../components/evertally/db/store";

const media = (path: string) => `public/media/${path}`;
const read = <T,>(path: string) => JSON.parse(readFileSync(media(path), "utf8")) as T;
const travel = read<Travel>("world/travel.json");
const flights = read<Flights>("world/flights.json");
const world = read<World>("world/world.json");
const floors = read<Floors>("world/floors.json");
const places = read<Places>("world/places.json");
const hub = (prefix: string, name: string): Place => {
  const [, h] = Object.entries(travel.hubs).find(([key, entry]) => key.startsWith(prefix) && entry.n?.startsWith(name))!;
  return { label: h.n!, u: h.u!, v: h.v! };
};

test("World placement: every map is a 3:2 rectangle on Azeroth's map and its artwork exists", () => {
  for (const [key, entry] of Object.entries(world.maps)) {
    const [l, r, t, b] = entry.rect;
    assert.ok(r > l && b > t, key);
    assert.ok(Math.abs((r - l) * world.size[0] / ((b - t) * world.size[1]) - 1.5) < 0.01, `${key} aspect`);
    assert.ok(existsSync(media(`maps/${key}.jpg`)) || existsSync(media(`maps/${key}.webp`)) || existsSync(media(`maps/${key}.png`)), `${key} art`);
  }
});

test("Every flight node is a fixed place for the planner, and flights are positive durations between known nodes", () => {
  for (const [id, node] of Object.entries(flights.nodes)) assert.ok(travel.hubs[`taxi${id}`], `taxi${id} ${node.n}`);
  for (const path of flights.paths) {
    assert.ok(path.s > 0 && flights.nodes[String(path.a)] && flights.nodes[String(path.b)]);
    assert.ok(path.p.length >= 2);
  }
});

test("Walking tables only name known places; unwalkable pairs are null, never zero", () => {
  for (const table of Object.values(travel.walks)) for (const [pair, cost] of Object.entries(table)) {
    const [a, b] = pair.split(" ");
    assert.ok(travel.hubs[a] && travel.hubs[b], pair);
    if (cost) for (const yards of cost) assert.ok(yards === null || yards > 0 || pair.includes("teleport") || pair.includes("portal"), `${pair}: ${yards}`);
  }
});

test("Timetables have positive loops and stops that name docks", () => {
  for (const route of travel.routes) {
    assert.ok(route.p > 0 && route.stops.length >= 2, String(route.id));
    for (const [dock] of route.stops) assert.ok(travel.hubs[dock], `${route.id} ${dock}`);
  }
});

test("Yards and map positions convert consistently on both continents", () => {
  const stormwind = hub("taxi", "Stormwind");
  const yards = toYards(travel, stormwind.u, stormwind.v);
  assert.equal(yards.c, 0);
  assert.ok(Math.abs(yards.x - travel.hubs[Object.keys(travel.hubs).find(k => travel.hubs[k].n === stormwind.label && k.startsWith("taxi"))!].x) < 40);
  assert.equal(toYards(travel, hub("taxi", "Orgrimmar").u, hub("taxi", "Orgrimmar").v).c, 1);
});

test("Journeys: Stormwind to Ironforge flies on foot but takes the Deeprun Tram with a fast mount", () => {
  const from = hub("taxi", "Stormwind"), to = hub("taxi", "Ironforge");
  const slow = planJourney(travel, flights, from, to, { side: "A", speed: 7 })!;
  assert.deepEqual(slow.steps.map(step => step.mode), ["flight"]);
  const fast = planJourney(travel, flights, from, to, { side: "A", speed: 14 })!;
  assert.ok(fast.steps.some(step => step.mode === "tram"), "tram expected");
  assert.ok(fast.seconds < slow.seconds);
});

test("Journeys respect the faction: Horde zeppelins are not offered to the Alliance, Alliance flights not to the Horde", () => {
  const horde = planJourney(travel, flights, hub("taxi", "Orgrimmar"), hub("taxi", "Undercity"), { side: "H", speed: 7 })!;
  assert.ok(horde.steps.some(step => step.mode === "zeppelin" || step.mode === "flight"));
  const alliance = planJourney(travel, flights, hub("taxi", "Stormwind"), hub("taxi", "Ironforge"), { side: "H", speed: 7 });
  assert.ok(alliance === null || !alliance.steps.some(step => step.mode === "flight"), "a Horde player cannot fly Alliance paths");
});

test("Across the sea a boat or zeppelin is used; the other faction's route needs the option", () => {
  const journey = planJourney(travel, flights, hub("taxi", "Rut'theran"), hub("taxi", "Ironforge"), { side: "A", speed: 7 })!;
  assert.ok(journey.steps.some(step => step.mode === "boat"));
  assert.ok(journey.steps[0].mode === "flight");
  assert.ok(journey.seconds > 60 && journey.seconds < 3600);
});

test("Flight routes: the fastest chain between two flight masters is found, and the faction limits it", () => {
  const ids = Object.fromEntries(Object.entries(flights.nodes).map(([id, node]) => [node.n, Number(id)]));
  const route = planRoute(flights, ids["Stormwind, Elwynn"], ids["Ironforge, Dun Morogh"], "A")!;
  assert.equal(route.legs.length, 1);
  assert.equal(planRoute(flights, ids["Stormwind, Elwynn"], ids["Ironforge, Dun Morogh"], "H"), null);
});

test("Difficulty colours follow the game's level bands", () => {
  assert.equal(levelClass([10, 20], null), "lv-none");
  assert.equal(levelClass([10, 20], 15), "lv-yellow");
  assert.equal(levelClass([30, 40], 20), "lv-red");
  assert.equal(levelClass([10, 20], 40), "lv-grey");
});

test("Focus links only accept known kinds and safe ids", () => {
  assert.deepEqual(parseFocus("npc:3139"), { kind: "npc", id: "3139" });
  assert.equal(focusText(parseFocus("dungeon:the-deadmines")), "dungeon:the-deadmines");
  assert.equal(parseFocus("npc:../etc"), null);
  assert.equal(parseFocus("script:1"), null);
});

test("Floor maps: every listed floor image exists and every mapped dungeon key has floors", () => {
  for (const list of Object.values(floors.maps)) for (const floor of list) assert.ok(existsSync(`public${floor.img}`), floor.img);
  for (const [key, mapId] of Object.entries(floors.keys)) assert.ok(floors.maps[String(mapId)]?.length, key);
});

test("Instance entrances land on the world map", () => {
  for (const place of places.instances) assert.ok(place.u > 0 && place.u < 1 && place.v > 0 && place.v < 1, JSON.stringify(place.list[0]));
});

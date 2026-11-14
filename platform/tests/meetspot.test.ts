import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { suggestSpots } from "../components/evertally/db/meetspot";
import { reachTimes, planJourney, type Travel } from "../components/evertally/db/travel";
import type { Flights, World } from "../components/evertally/db/store";

const read = <T,>(name: string) => JSON.parse(readFileSync(`public/media/${name}`, "utf8")) as T;
const travel = read<Travel>("world/travel.json");
const flights = read<Flights>("world/flights.json");
const world = read<World>("world/world.json");
const at = (zone: string, x = 50, y = 50) => { const r = world.maps[zone].rect; return { u: r[0] + x / 100 * (r[1] - r[0]), v: r[2] + y / 100 * (r[3] - r[2]) }; };
const options = { side: "A" as const, speed: 7 };

test("Doba k pevnému místu z jednoho hledání odpovídá plánovači", () => {
  const from = { label: "Elwynn", ...at("elwynn-forest") };
  const reach = reachTimes(travel, flights, from, options);
  const [id, node] = Object.entries(flights.nodes).find(([, n]) => n.n.includes("Stormwind") && n.f !== "H")!;
  const direct = planJourney(travel, flights, from, { label: node.n, u: node.u, v: node.v }, options)!;
  const viaReach = reach.get(`taxi${id}`)!;
  assert.ok(viaReach > 0);
  // the planner also walks the last stretch to the exact spot, so it is never faster than the hub itself, and close to it
  assert.ok(direct.seconds >= viaReach - 1 && direct.seconds - viaReach < 120, `${direct.seconds} vs ${viaReach}`);
});
test("Návrh místa schůzky: nejdelší cesta je co nejkratší a výsledek je seřazený", () => {
  const people = [{ name: "A", label: "Elwynn", ...at("elwynn-forest") }, { name: "B", label: "Westfall", ...at("westfall") }, { name: "C", label: "Duskwood", ...at("duskwood") }];
  const spots = suggestSpots(travel, flights, people, options, 3);
  assert.equal(spots.length, 3);
  for (let i = 1; i < spots.length; i++) assert.ok(spots[i - 1].worst <= spots[i].worst);
  assert.equal(spots[0].times.length, 3);
  assert.equal(spots[0].worst, Math.max(...spots[0].times.map(t => t.seconds)));
  assert.ok(spots[0].worst < 3600, "three neighbouring zones are within an hour of a flight master");
});
test("Návrh potřebuje aspoň dva lidi a nenabízí letiště druhé frakce", () => {
  assert.deepEqual(suggestSpots(travel, flights, [{ name: "A", label: "x", ...at("elwynn-forest") }], options), []);
  const spots = suggestSpots(travel, flights, [{ name: "A", label: "x", ...at("elwynn-forest") }, { name: "B", label: "y", ...at("westfall") }], options, 50);
  for (const spot of spots) assert.notEqual(flights.nodes[spot.id].f, "H");
});

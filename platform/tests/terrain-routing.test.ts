import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { planJourney, type Travel } from "../components/evertally/db/travel";
import { planGroundJourney } from "../components/evertally/db/ground";
import { parseWalk } from "../components/evertally/db/terrain";
import type { Flights, World } from "../components/evertally/db/store";

test("Terrain costs can change the selected flight into a faster walk", () => {
  const travel: Travel = {
    schema: 1, source: "fixture", yards: { "0": [0,0,0,0,0.5,0.00001,0.5,0.00001] },
    hubs: {
      taxi1: { c: 0, x: 0, y: 200, u: 0.502, v: 0.5, n: "A" },
      taxi2: { c: 0, x: 0, y: 800, u: 0.508, v: 0.5, n: "B" },
    }, walks: {}, routes: [], portals: [], landmasses: [{ c: 0, n: "land", x0: -100, x1: 100, y0: -100, y1: 1100 }],
  };
  const flights: Flights = { nodes: { "1": { n: "A", z: null, f: "A", u: 0.502, v: 0.5 }, "2": { n: "B", z: null, f: "A", u: 0.508, v: 0.5 } }, paths: [{ a: 1, b: 2, s: 10, p: [[0.502, 0.5], [0.508, 0.5]] }], source: "fixture" };
  const a = { label: "start", u: 0.5, v: 0.5 }, b = { label: "finish", u: 0.51, v: 0.5 };
  const options = { side: "A" as const, speed: 7 };
  const estimated = planJourney(travel, flights, a, b, options)!;
  assert.ok(estimated.steps.some(step => step.mode === "flight"));
  const checked = planJourney(travel, flights, a, b, options, (from, to) => Math.abs(from[0] - to[0]) > 0.009 ? 1100 : 4000)!;
  assert.deepEqual(checked.steps.map(step => step.mode), ["walk"]);
  assert.ok(Math.abs(checked.seconds - 1100 / 7) < 1e-6);
});

test("A grounded journey can be planned from actual map and terrain data", async () => {
  const travel = JSON.parse(readFileSync("public/media/world/travel.json", "utf8")) as Travel;
  const flights = JSON.parse(readFileSync("public/media/world/flights.json", "utf8")) as Flights;
  const world = JSON.parse(readFileSync("public/media/world/world.json", "utf8")) as World;
  const data = readFileSync("public/media/world/walk.bin");
  const walk = await parseWalk(data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength) as ArrayBuffer);
  const at = (zone: string) => { const r = world.maps[zone].rect; return { label: zone, u: (r[0] + r[1]) / 2, v: (r[2] + r[3]) / 2 }; };
  const started = performance.now();
  const result = planGroundJourney(travel, flights, at("elwynn-forest"), at("westfall"), { side: "A", speed: 7 }, walk);
  assert.ok(result && result.steps.length);
  assert.ok(result.steps.some(step => step.mode === "walk" && step.ground));
  for (const [from, to] of [["darkshore", "mount-hyjal"], ["dun-morogh", "wetlands"], ["durotar", "the-barrens"]]) {
    assert.ok(planGroundJourney(travel, flights, at(from), at(to), { side: "A", speed: 7 }, walk), `${from} to ${to}`);
  }
  assert.ok(performance.now() - started < 15000, `Planning took ${(performance.now() - started).toFixed(0)} ms`);
});

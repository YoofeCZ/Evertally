import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { planJourney, type Travel } from "../components/evertally/db/travel";
import type { Flights } from "../components/evertally/db/store";

// tests/lua/fixtures/journeys.json is what the in-game (Lua) planner is checked against. This test keeps the file honest:
// if the TypeScript planner changes, regenerate it with `node tools/dump_journeys.mjs` and check the Lua port again.
type Case = { from: [string, number, number]; to: [string, number, number]; side: "A" | "H"; speed: number; seconds: number | null; steps: [string, string, string, number][] | null };
const cases = JSON.parse(readFileSync("../tests/lua/fixtures/journeys.json", "utf8")) as Case[];
const travel = JSON.parse(readFileSync("public/media/world/travel.json", "utf8")) as Travel;
const flights = JSON.parse(readFileSync("public/media/world/flights.json", "utf8")) as Flights;

test("Pevný soubor cest odpovídá plánovači na webu (Lua plánovač v addonu se porovnává s ním)", () => {
  assert.ok(cases.length > 1000);
  const different: string[] = [];
  for (const [index, c] of cases.entries()) {
    const journey = planJourney(travel, flights, { label: c.from[0], u: c.from[1], v: c.from[2] }, { label: c.to[0], u: c.to[1], v: c.to[2] }, { side: c.side, speed: c.speed });
    const same = c.seconds === null
      ? journey === null
      : journey !== null && Math.abs(journey.seconds - c.seconds) < 0.01 && JSON.stringify(journey.steps.map(s => [s.mode, s.from, s.to])) === JSON.stringify(c.steps!.map(s => s.slice(0, 3)));
    if (!same) different.push(`${index}: ${c.from[0]} -> ${c.to[0]} (${c.side}, ${c.speed})`);
  }
  assert.deepEqual(different.slice(0, 5), [], `${different.length} journeys changed: run node tools/dump_journeys.mjs`);
});

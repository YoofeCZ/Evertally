// Writes tests/lua/fixtures/journeys.json: what the TypeScript planner (the website) answers for a fixed set of trips.
// The Lua planner of the in-game map add-on must give the same answers (tests/lua/test_navigation.py), and
// platform/tests/planner-fixture.test.ts fails when this file no longer matches the TypeScript planner.
//   node tools/dump_journeys.mjs            (run from the repository root)
import { build } from "../platform/node_modules/esbuild/lib/main.js";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";
import path from "node:path";

const root = path.resolve(import.meta.dirname, "..");
const world = JSON.parse(await readFile(path.join(root, "platform/public/media/world/world.json"), "utf8"));
const travel = JSON.parse(await readFile(path.join(root, "platform/public/media/world/travel.json"), "utf8"));
const flights = JSON.parse(await readFile(path.join(root, "platform/public/media/world/flights.json"), "utf8"));

await mkdir(path.join(root, "platform/.test-artifacts"), { recursive: true });
const out = path.join(root, "platform/.test-artifacts/travel-dump.mjs");
await build({ entryPoints: [path.join(root, "platform/components/evertally/db/travel.ts")], outfile: out, bundle: true, format: "esm", platform: "node", target: "node22" });
const { planJourney } = await import(pathToFileURL(out).href + "?" + Date.now());

const zones = ["elwynn-forest", "westfall", "duskwood", "dun-morogh", "stormwind-city", "ironforge", "burning-steppes", "stranglethorn-vale", "wetlands", "tirisfal-glades", "undercity",
  "durotar", "orgrimmar", "mulgore", "thunder-bluff", "teldrassil", "darnassus", "ashenvale", "tanaris", "winterspring", "dustwallow-marsh", "the-barrens"];
const point = (key, x, y) => { const r = world.maps[key].rect; return { label: key, u: r[0] + x * (r[1] - r[0]), v: r[2] + y * (r[3] - r[2]) }; };
const cases = [];
for (const a of zones) for (const b of zones) {
  if (a === b) continue;
  for (const [side, speed] of [["A", 7], ["H", 7], ["A", 11.2]]) cases.push({ from: point(a, 0.5, 0.5), to: point(b, 0.4, 0.6), side, speed });
}
// a few free points close to each other, and a long haul that needs the sea
cases.push({ from: point("elwynn-forest", 0.2, 0.2), to: point("elwynn-forest", 0.8, 0.7), side: "A", speed: 7 });
cases.push({ from: point("durotar", 0.5, 0.5), to: point("durotar", 0.52, 0.5), side: "H", speed: 7 });

const rounded = n => Math.round(n * 1000) / 1000;
const result = cases.map(c => {
  const journey = planJourney(travel, flights, c.from, c.to, { side: c.side, speed: c.speed });
  return {
    from: [c.from.label, rounded(c.from.u), rounded(c.from.v)], to: [c.to.label, rounded(c.to.u), rounded(c.to.v)], side: c.side, speed: c.speed,
    seconds: journey ? rounded(journey.seconds) : null,
    steps: journey ? journey.steps.map(s => [s.mode, s.from, s.to, rounded(s.seconds)]) : null,
  };
});
// the inputs are rounded in the file, so the Lua side plans from exactly the same points
for (const [i, c] of cases.entries()) { c.from.u = result[i].from[1]; c.from.v = result[i].from[2]; c.to.u = result[i].to[1]; c.to.v = result[i].to[2]; }
const final = cases.map(c => {
  const journey = planJourney(travel, flights, c.from, c.to, { side: c.side, speed: c.speed });
  return {
    from: [c.from.label, c.from.u, c.from.v], to: [c.to.label, c.to.u, c.to.v], side: c.side, speed: c.speed,
    seconds: journey ? rounded(journey.seconds) : null,
    steps: journey ? journey.steps.map(s => [s.mode, s.from, s.to, rounded(s.seconds)]) : null,
  };
});
const dir = path.join(root, "tests/lua/fixtures");
await mkdir(dir, { recursive: true });
await writeFile(path.join(dir, "journeys.json"), JSON.stringify(final));
console.log(`${final.length} journeys, ${final.filter(j => j.seconds === null).length} without a route -> tests/lua/fixtures/journeys.json`);

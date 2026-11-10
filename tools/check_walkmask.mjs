// Compares walking distances on the walk mask with the ones Shortest Path Forever baked between fixed places
// (platform/public/media/world/travel.json "walks"), and times the search.   node tools/check_walkmask.mjs [pairs]
import { build } from "../platform/node_modules/esbuild/lib/main.js";
import { mkdir, readFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";
import path from "node:path";

const root = path.resolve(import.meta.dirname, "..");
const travel = JSON.parse(await readFile(path.join(root, "platform/public/media/world/travel.json"), "utf8"));
await mkdir(path.join(root, "platform/.test-artifacts"), { recursive: true });
const out = path.join(root, "platform/.test-artifacts/terrain-check.mjs");
await build({ entryPoints: [path.join(root, "platform/components/evertally/db/terrain.ts")], outfile: out, bundle: true, format: "esm", platform: "node", target: "node22" });
const { parseWalk, findPath, walkable } = await import(pathToFileURL(out).href + "?" + Date.now());
const bytes = await readFile(path.join(root, "platform/public/media/world/walk.bin"));
const walk = await parseWalk(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));

const pairs = [];
for (const table of Object.values(travel.walks)) for (const [pair, cost] of Object.entries(table)) {
  const [a, b] = pair.split(" ");
  const ha = travel.hubs[a], hb = travel.hubs[b];
  if (!cost || !ha || !hb || ha.c !== hb.c || ha.c > 1 || cost[0] == null) continue;
  pairs.push({ a, b, ha, hb, baked: cost[0] });
}
let seed = 12345;
const random = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648;
const wanted = Number(process.argv[2] ?? 300);
const sample = [];
while (sample.length < Math.min(wanted, pairs.length)) sample.push(pairs[Math.floor(random() * pairs.length)]);

const margin = process.argv[3] ? Number(process.argv[3]) : undefined;
const gridRatios = [], ratios = [], failures = [], straight = [], times = [], reasons = {};
for (const p of sample) {
  const t0 = performance.now();
  const map = walk.get(p.ha.c);
  const found = findPath(map, [p.ha.x, p.ha.y], [p.hb.x, p.hb.y], margin);
  times.push(performance.now() - t0);
  if (!found) {
    const wide = findPath(map, [p.ha.x, p.ha.y], [p.hb.x, p.hb.y], 1200);
    const why = wide ? "window too small" : (!walkable(map, p.ha.x, p.ha.y) || !walkable(map, p.hb.x, p.hb.y)) ? "an end is on blocked ground" : "not connected";
    reasons[why] = (reasons[why] ?? 0) + 1;
    failures.push(`${p.a} -> ${p.b}`); continue;
  }
  ratios.push(found.yards / p.baked);
  gridRatios.push(found.grid / p.baked);
  straight.push(Math.hypot(p.ha.x - p.hb.x, p.ha.y - p.hb.y) / p.baked);
}
const q = (list, f) => [...list].sort((a, b) => a - b)[Math.floor((list.length - 1) * f)];
const pct = n => (n * 100).toFixed(0) + "%";
console.log(`${sample.length} baked walks sampled, no path for ${failures.length}${failures.length ? " e.g. " + failures.slice(0, 4).join(", ") : ""}`);
console.log("failures by reason:", JSON.stringify(reasons));
console.log(`mask path / baked yards: p10 ${pct(q(ratios, 0.1))}, median ${pct(q(ratios, 0.5))}, p90 ${pct(q(ratios, 0.9))}`);
console.log(`median baked / grid path (the factor that makes free-point walks agree with SPF): ${(1 / q(gridRatios, 0.5)).toFixed(3)}`);
console.log(`grid path / baked     : p10 ${pct(q(gridRatios, 0.1))}, median ${pct(q(gridRatios, 0.5))}, p90 ${pct(q(gridRatios, 0.9))}`);
console.log(`straight line / baked  : p10 ${pct(q(straight, 0.1))}, median ${pct(q(straight, 0.5))}, p90 ${pct(q(straight, 0.9))}`);
console.log(`search time ms: median ${q(times, 0.5).toFixed(1)}, p90 ${q(times, 0.9).toFixed(1)}, max ${Math.max(...times).toFixed(0)}`);

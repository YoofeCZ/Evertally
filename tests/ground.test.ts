import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { findPath, parseWalk, walkable, type Pt, type Walk } from "../components/evertally/db/terrain";
import { GROUND_FACTOR, groundJourney } from "../components/evertally/db/ground";
import { fromYards, planJourney, toYards, type Travel } from "../components/evertally/db/travel";
import type { Flights, World } from "../components/evertally/db/store";

const read = <T,>(name: string) => JSON.parse(readFileSync(`public/media/world/${name}`, "utf8")) as T;
const travel = read<Travel>("travel.json");
const flights = read<Flights>("flights.json");
const world = read<World>("world.json");
const file = readFileSync("public/media/world/walk.bin");
const walk: Walk = await parseWalk(file.buffer.slice(file.byteOffset, file.byteOffset + file.byteLength) as ArrayBuffer);

const hubPoint = (id: string): Pt => { const h = travel.hubs[id]; return [h.x, h.y]; };
const hubByName = (part: string) => Object.entries(travel.hubs).find(([id, hub]) => id.startsWith("taxi") && hub.n?.includes(part))![0];
const at = (zone: string, x: number, y: number) => { const r = world.maps[zone].rect; return { label: zone, u: r[0] + x * (r[1] - r[0]), v: r[2] + y * (r[3] - r[2]) }; };
const options = { side: "A" as const, speed: 7 };

// every walk SPF baked between two fixed places on a continent, as [a, b, baked yards]
const baked: [string, string, number][] = [];
for (const table of Object.values(travel.walks)) for (const [pair, cost] of Object.entries(table)) {
  const [a, b] = pair.split(" ");
  const ha = travel.hubs[a], hb = travel.hubs[b];
  if (cost && cost[0] != null && ha && hb && ha.c === hb.c && ha.c <= 1) baked.push([a, b, cost[0]]);
}
function sample(count: number, seed = 4242) {
  let state = seed;
  const random = () => (state = (state * 1103515245 + 12345) % 2147483648) / 2147483648;
  return Array.from({ length: count }, () => baked[Math.floor(random() * baked.length)]);
}
const median = (list: number[]) => [...list].sort((x, y) => x - y)[Math.floor((list.length - 1) / 2)];

test("Maska chůze: tři mapy, rozumný podíl země a velikost buňky 16 yardů", () => {
  assert.deepEqual([...walk.keys()].sort((a, b) => a - b), [0, 1, 2991]);
  for (const map of walk.values()) {
    assert.equal(map.data.length, map.nx * map.ny);
    const counts = [0, 0, 0];
    for (let i = 0; i < map.data.length; i += 7) counts[map.data[i]]++;
    assert.ok(counts[1] / (counts[0] + counts[1] + counts[2]) > 0.05, `map ${map.id} has hardly any ground`);
    assert.ok(Math.abs(map.cell - 15.9) < 0.3, `cell ${map.cell}`);
  }
});
test("Poškozený soubor masky se odmítne a body mimo mapu nemají cestu", async () => {
  await assert.rejects(() => parseWalk(new Uint8Array(40).buffer));
  const truncated = file.buffer.slice(file.byteOffset, file.byteOffset + 200) as ArrayBuffer;
  await assert.rejects(() => parseWalk(truncated));
  const map = walk.get(0)!;
  assert.equal(findPath(map, [1e7, 1e7], hubPoint("taxi2")), null);
  assert.equal(walkable(map, 1e7, 1e7), false);
});
test("Převod mezi mapou Azerothu a yardy je v obou směrech tentýž", () => {
  for (const zone of ["elwynn-forest", "durotar", "winterspring", "tirisfal-glades"]) {
    const p = at(zone, 0.37, 0.61);
    const y = toYards(travel, p.u, p.v);
    const [u, v] = fromYards(travel, y.c, y.x, y.y);
    assert.ok(Math.abs(u - p.u) < 1e-9 && Math.abs(v - p.v) < 1e-9, zone);
  }
});
test("Cesta začíná a končí v zadaných bodech, vede po průchodné zemi a není kratší než vzdušná čára", () => {
  const a = hubPoint(hubByName("Stormwind")), b = hubPoint(hubByName("Sentinel Hill"));
  const found = findPath(walk.get(0)!, a, b)!;
  assert.ok(found);
  assert.deepEqual(found.points[0], a);
  assert.deepEqual(found.points.at(-1), b);
  assert.ok(found.yards >= Math.hypot(a[0] - b[0], a[1] - b[1]) - 1e-6);
  for (const [x, y] of found.points.slice(1, -1)) assert.ok(walkable(walk.get(0)!, x, y), `${x},${y} is blocked`);
  assert.ok(found.grid >= found.yards - 1e-6, "smoothing never makes the path longer");
});
test("Hora mezi body: cesta ji obchází (Darkshore → Mount Hyjal je mnohonásobně delší než vzdušná čára)", () => {
  const a = hubPoint(hubByName("Auberdine")), b = hubPoint(hubByName("Summit of Eternity"));
  const found = findPath(walk.get(1)!, a, b)!;
  assert.ok(found, "the mask connects them");
  assert.ok(found.yards > 3 * Math.hypot(a[0] - b[0], a[1] - b[1]), `${found.yards} yd for a straight line of ${Math.hypot(a[0] - b[0], a[1] - b[1])}`);
});
test("Každá cesta, kterou SPF upekl mezi pevnými místy, na masce existuje", () => {
  const missing = sample(250).filter(([a, b]) => !findPath(walk.get(travel.hubs[a].c)!, hubPoint(a), hubPoint(b))).map(([a, b]) => `${a} ${b}`);
  assert.deepEqual(missing, []);
});
test("Přepočet GROUND_FACTOR odpovídá naměřenému mediánu upečených cest (±4 %)", () => {
  const ratios = sample(250).map(([a, b, yards]) => yards / findPath(walk.get(travel.hubs[a].c)!, hubPoint(a), hubPoint(b))!.grid);
  const measured = median(ratios);
  assert.ok(Math.abs(measured / GROUND_FACTOR - 1) < 0.04, `measured ${measured.toFixed(3)}, constant ${GROUND_FACTOR}`);
});

test("Cesta se stejnými kroky, ale s terénem: pěší kroky dostanou ground, jiné zůstanou beze změny", () => {
  const from = at("elwynn-forest", 0.5, 0.5), to = at("westfall", 0.4, 0.6);
  const base = planJourney(travel, flights, from, to, options)!;
  const refined = groundJourney(base, travel, walk, options);
  assert.deepEqual(refined.steps.map(s => [s.mode, s.from, s.to]), base.steps.map(s => [s.mode, s.from, s.to]));
  refined.steps.forEach((step, i) => {
    if (step.mode === "walk") assert.equal(step.ground, true, `walk step ${i}`);
    else assert.deepEqual(step, base.steps[i], `step ${i} must not change`);
  });
  const delta = refined.steps.reduce((sum, s, i) => sum + (s.mode === "walk" ? s.seconds - base.steps[i].seconds : 0), 0);
  assert.ok(Math.abs(refined.seconds - base.seconds - delta) < 1e-6, "the total follows the walking steps");
});
test("Baked chůze mezi pevnými místy si drží upečený čas, odhadované úseky se přepočtou", () => {
  const from = at("elwynn-forest", 0.5, 0.5), to = at("elwynn-forest", 0.8, 0.7);
  const base = planJourney(travel, flights, from, to, options)!;
  const refined = groundJourney(base, travel, walk, options);
  for (const [i, step] of refined.steps.entries()) {
    for (const [j, leg] of (step.legs ?? []).entries()) {
      const before = base.steps[i].legs![j];
      if (!before.estimated) assert.equal(leg.seconds, before.seconds);
      else assert.ok(Math.abs(leg.seconds - leg.yards / options.speed) < 1e-9);
    }
  }
  assert.ok(refined.steps.every(s => s.mode !== "walk" || (s.points.length >= 2 && s.yards! > 0)));
});
test("Jízda tramem a průchody zůstanou netknuté: tam žádná maska není", () => {
  const base = planJourney(travel, flights, at("stormwind-city", 0.5, 0.5), at("ironforge", 0.5, 0.5), options)!;
  assert.ok(base.steps.some(s => s.mode === "tram"));
  const refined = groundJourney(base, travel, walk, options);
  assert.deepEqual(refined.steps.map(s => s.mode), base.steps.map(s => s.mode));
  base.steps.forEach((step, i) => { if (step.mode !== "walk") assert.deepEqual(refined.steps[i], step); });
});
test("Bez masky pro mapu zůstane úsek přímou čarou a odhadem, čas i body beze změny", () => {
  const base = planJourney(travel, flights, at("elwynn-forest", 0.5, 0.5), at("westfall", 0.4, 0.6), options)!;
  const refined = groundJourney(base, travel, new Map(), options);
  assert.ok(Math.abs(refined.seconds - base.seconds) < 1e-9);
  refined.steps.forEach((step, i) => {
    assert.deepEqual(step.points, base.steps[i].points);
    assert.ok(Math.abs(step.seconds - base.steps[i].seconds) < 1e-9);
    if (step.mode === "walk") assert.equal(step.ground, false);
  });
});
test("Plánování s terénem je dost rychlé na to, aby běželo při kreslení stránky", () => {
  const zones = ["elwynn-forest", "westfall", "duskwood", "dun-morogh", "stormwind-city", "ironforge", "burning-steppes", "wetlands", "tirisfal-glades"];
  const started = performance.now();
  let trips = 0;
  for (const a of zones) for (const b of zones) {
    if (a === b || trips >= 24) continue;
    const base = planJourney(travel, flights, at(a, 0.4, 0.5), at(b, 0.6, 0.4), options);
    if (base) { groundJourney(base, travel, walk, options); trips++; }
  }
  assert.ok(trips >= 20);
  assert.ok(performance.now() - started < 6000, `${(performance.now() - started).toFixed(0)} ms for ${trips} journeys`);
});

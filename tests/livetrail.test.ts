import test from "node:test";
import assert from "node:assert/strict";
import { extendLive, KEEP_SECONDS, lastFix, MAX_FIXES, MIN_STEP, pruneLive, restoreLive, splitAtJumps, type LiveFix, type LiveTrails } from "../components/evertally/db/liveTrail";

const fix = (at: number, x: number, y: number, extra: Partial<LiveFix> = {}): LiveFix => ({ profileId: "p1", mapId: 1426, x, y, at, ...extra });

test("Živá cesta: každá nová poloha prodlouží čáru a nehybná postava ji nepředlouží", () => {
  let trails: LiveTrails = {};
  trails = extendLive(trails, [fix(100, 0.5, 0.5)]);
  trails = extendLive(trails, [fix(103, 0.51, 0.5)]);
  assert.deepEqual(trails.p1, [{ mapId: 1426, points: [[100, 0.5, 0.5], [103, 0.51, 0.5]] }]);
  const same = extendLive(trails, [fix(106, 0.51, 0.5)]);
  assert.equal(same, trails, "stejné místo: nic se nezměnilo, takže i stejný objekt (žádné zbytečné překreslení)");
  const jitter = extendLive(trails, [fix(109, 0.51 + MIN_STEP / 2, 0.5)]);
  assert.equal(jitter, trails, "drobné chvění pod prahem není chůze");
});

test("Živá cesta: starší nebo opakovaný vzorek se zahodí, jiné postavy mají každá svou čáru", () => {
  let trails = extendLive({}, [fix(100, 0.5, 0.5), fix(100, 0.6, 0.6, { profileId: "p2" })]);
  trails = extendLive(trails, [fix(99, 0.7, 0.7), fix(100, 0.7, 0.7)]);
  assert.equal(trails.p1[0].points.length, 1, "vzorek se starším nebo stejným časem se nepřidá");
  assert.deepEqual(Object.keys(trails).sort(), ["p1", "p2"]);
});

test("Živá cesta: při změně mapy začne nový úsek a starý zůstane", () => {
  let trails = extendLive({}, [fix(100, 0.5, 0.5), fix(103, 0.52, 0.5)]);
  trails = extendLive(trails, [fix(106, 0.1, 0.1, { mapId: 1432 }), fix(109, 0.12, 0.1, { mapId: 1432 })]);
  assert.equal(trails.p1.length, 2);
  assert.deepEqual(trails.p1.map(segment => [segment.mapId, segment.points.length]), [[1426, 2], [1432, 2]]);
  // zpátky na první mapu: třetí úsek, ne spojení přes celý svět
  trails = extendLive(trails, [fix(112, 0.9, 0.9, { mapId: 1426 })]);
  assert.equal(trails.p1.length, 3);
});

test("Živá cesta: neplatné vzorky se nepřijmou a vstup se nemění na místě", () => {
  const before: LiveTrails = { p1: [{ mapId: 1426, points: [[100, 0.5, 0.5]] }] };
  const frozen = JSON.stringify(before);
  const out = extendLive(before, [fix(Number.NaN, 0.5, 0.5), fix(110, Number.POSITIVE_INFINITY, 0.5), fix(111, 0.6, 0.6, { profileId: "" }), fix(112, 0.6, 0.6, { mapId: "x" as unknown as number })]);
  assert.equal(out, before);
  extendLive(before, [fix(120, 0.8, 0.8)]);
  assert.equal(JSON.stringify(before), frozen, "původní objekt zůstal nedotčený");
});

test("Živá cesta: nejvýš MAX_FIXES bodů na postavu, mizí ty nejstarší", () => {
  const fixes = Array.from({ length: MAX_FIXES + 50 }, (_, index) => fix(100 + index, (index % 900) / 1000, 0.5 + Math.floor(index / 900) * 0.1));
  let trails: LiveTrails = {};
  for (let i = 0; i < fixes.length; i += 40) trails = extendLive(trails, fixes.slice(i, i + 40));
  const total = trails.p1.reduce((sum, segment) => sum + segment.points.length, 0);
  assert.ok(total <= MAX_FIXES, `${total} bodů`);
  assert.equal(trails.p1.at(-1)!.points.at(-1)![0], 100 + MAX_FIXES + 49, "nejnovější bod zůstal");
  assert.ok(trails.p1[0].points[0][0] > 100, "nejstarší body zmizely");
});

test("Živá cesta: stará data se při uložení a obnově ořežou a poškozená se přeskočí", () => {
  const now = 100000;
  const trails: LiveTrails = { p1: [{ mapId: 1426, points: [[now - KEEP_SECONDS - 5, 0.1, 0.1], [now - 10, 0.2, 0.2]] }, { mapId: 1432, points: [[now - KEEP_SECONDS - 1, 0.3, 0.3]] }], p2: [{ mapId: 1, points: [[now - KEEP_SECONDS - 9, 0.4, 0.4]] }] };
  assert.deepEqual(pruneLive(trails, now), { p1: [{ mapId: 1426, points: [[now - 10, 0.2, 0.2]] }] });
  const stored = JSON.parse(JSON.stringify({ p1: [{ mapId: 1426, points: [[now - 10, 0.2, 0.2]] }] }));
  assert.deepEqual(restoreLive(stored, now), stored);
  for (const garbage of [null, 5, "x", [], { p1: "x" }, { p1: [null] }, { p1: [{ mapId: "a", points: [] }] }, { p1: [{ mapId: 1, points: [[1, 2]] }] }, { p1: [{ mapId: 1, points: [[now, 5, 0.5]] }] }, { p1: [{ mapId: 1, points: [["a", 0.5, 0.5]] }] }]) {
    assert.deepEqual(restoreLive(garbage, now), {}, JSON.stringify(garbage));
  }
});

test("Čára se při skoku přeruší: teleport, hearthstone nebo běh z hřbitova nepřetne celou zónu", () => {
  const walk = (t: number, x: number): [number, number, number] => [t, x, 0.5];
  const normal = [walk(0, 0.1), walk(5, 0.11), walk(10, 0.12), walk(15, 0.13)];
  assert.deepEqual(splitAtJumps(normal), [normal], "obyčejná chůze zůstane celá");
  const flight = Array.from({ length: 12 }, (_, i) => walk(i * 5, 0.1 + i * 0.04));
  assert.equal(splitAtJumps(flight).length, 1, "let (0,04 mapy za 5 s) se nepřeruší");
  const teleported = [walk(0, 0.1), walk(5, 0.11), walk(10, 0.55), walk(15, 0.56)];
  assert.deepEqual(splitAtJumps(teleported), [teleported.slice(0, 2), teleported.slice(2)], "skok o 0,44 mapy za 5 s");
  const longGap = [walk(0, 0.1), walk(600, 0.6)];
  assert.equal(splitAtJumps(longGap).length, 1, "velká vzdálenost po dlouhé době není skok (poloha se jen neměřila)");
  assert.deepEqual(splitAtJumps([]), []);
  assert.deepEqual(splitAtJumps([walk(0, 0.1)]), [[walk(0, 0.1)]]);
  assert.equal(splitAtJumps([walk(5, 0.1), walk(5, 0.5)]).length, 2, "stejný čas dvou bodů se bere jako jedna sekunda");
});

test("Poslední známý bod živé cesty: nejnovější bod posledního úseku", () => {
  assert.equal(lastFix(undefined), null);
  assert.equal(lastFix([]), null);
  const trail = extendLive({}, [fix(100, 0.5, 0.5), fix(103, 0.52, 0.5), fix(106, 0.1, 0.1, { mapId: 1432 })]);
  assert.deepEqual(lastFix(trail.p1), { mapId: 1432, fix: [106, 0.1, 0.1] });
});

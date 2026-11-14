import test from "node:test";
import assert from "node:assert/strict";
import { farmRoute, type Pt } from "../components/evertally/db/farmRoute";

const flat = (a: Pt, b: Pt) => Math.hypot(a[0] - b[0], a[1] - b[1]);

test("Trasa projde body v rozumném pořadí: přímka bodů se nepřeskakuje", () => {
  const points: Pt[] = [[5, 0], [1, 0], [3, 0], [2, 0], [4, 0]];
  const route = farmRoute(points, [0, 0], flat);
  assert.deepEqual(route.order, [[1, 0], [2, 0], [3, 0], [4, 0], [5, 0]]);
  assert.equal(route.yards, 5);
});
test("Bez startu začne u prvního bodu a nepočítá cestu k němu", () => {
  const route = farmRoute([[0, 0], [10, 0], [5, 0]], null, flat);
  assert.equal(route.order.length, 3);
  assert.equal(route.yards, 10);
});
test("2-opt nikdy nezhorší nearest-neighbour a vrátí každý bod nejvýš jednou", () => {
  let seed = 7;
  const random = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648;
  const points: Pt[] = Array.from({ length: 30 }, () => [random() * 100, random() * 100]);
  const route = farmRoute(points, [50, 50], flat, 30);
  assert.equal(route.order.length, 30);
  assert.equal(new Set(route.order.map(p => p.join(","))).size, 30);
  // a naive nearest-neighbour walk, for comparison
  const rest = [...points]; let at: Pt = [50, 50]; let naive = 0;
  while (rest.length) { let k = 0; for (let i = 1; i < rest.length; i++) if (flat(at, rest[i]) < flat(at, rest[k])) k = i; naive += flat(at, rest[k]); at = rest.splice(k, 1)[0]; }
  assert.ok(route.yards <= naive + 1e-6, `${route.yards} vs ${naive}`);
});
test("Příliš mnoho bodů: bere se nejvýš maxStops nejbližších", () => {
  const points: Pt[] = Array.from({ length: 200 }, (_, i) => [i, 0] as Pt);
  const route = farmRoute(points, [0, 0], flat, 10);
  assert.equal(route.order.length, 10);
  assert.ok(route.order.every(p => p[0] < 30));
  assert.deepEqual(farmRoute([], [0, 0], flat), { order: [], yards: 0 });
});

import test from "node:test";
import assert from "node:assert/strict";
import { combatSpans, routePoints, routeSegments } from "../lib/chronicle-route";
import type { Chronicle, Fight } from "../lib/chronicle";

const recording = (path: Chronicle["path"], fights: Fight[] = []): Chronicle => ({
  v: 1, character: { name: "Recorded route", classId: 1, level: 1 }, startedAt: 1000, duration: 100, zones: ["mulgore", "barrens"], path, events: [], fights,
});
const fight = (t: number, d: number): Fight => ({ t, d, kind: "combat", name: "Plainstrider", result: "ended", me: { dealt: [], healed: [], took: [] } });

test("route retains earlier visits to the same map and never joins different maps or long unobserved gaps", () => {
  const c = recording([[0, 0, 0.1, 0.1], [10, 0, 0.2, 0.2], [20, 1, 0.3, 0.3], [30, 1, 0.4, 0.4], [40, 0, 0.5, 0.5], [50, 0, 0.6, 0.6], [80, 0, 0.7, 0.7], [90, 0, 0.8, 0.8]]);
  const zones = routeSegments(c);
  assert.deepEqual(zones.filter(x => x.zone === 0).map(x => [x.from, x.to]), [[0, 10], [40, 50], [80, 90]]);
  assert.deepEqual(zones.filter(x => x.zone === 1).map(x => [x.from, x.to]), [[20, 30]]);
});

test("combat colours only the actual interval, splitting sample edges at combat start and end", () => {
  const c = recording([[0, 0, 0, 0], [10, 0, 0.1, 0.1], [20, 0, 0.2, 0.2], [30, 0, 0.3, 0.3]], [fight(5, 10)]);
  const route = routeSegments(c);
  assert.deepEqual(route.map(x => [x.from, x.to, x.combat]), [[0, 5, false], [5, 15, true], [15, 30, false]]);
  assert.deepEqual(route[1].points.map(p => p[0]), [5, 10, 15]);
  assert.equal(route[1].points[0][2], 0.05);
});

test("route clipping never reveals future movement and includes the current interpolated position", () => {
  const segment = routeSegments(recording([[0, 0, 0, 0], [10, 0, 1, 1]]))[0];
  assert.deepEqual(routePoints(segment, -100, 5), [[0, 0, 0, 0], [5, 0, 0.5, 0.5]]);
  assert.deepEqual(routePoints(segment, 6, 8), [[6, 0, 0.6, 0.6], [8, 0, 0.8, 0.8]]);
  assert.deepEqual(routePoints(segment, 10, 20), []);
});

test("route never bridges two game sessions and overlapping fights remain one combat interval", () => {
  const c = recording([[0, 0, 0, 0], [10, 0, 0.1, 0.1], [20, 0, 0.2, 0.2], [30, 0, 0.3, 0.3]], [fight(3, 10), fight(8, 12)]);
  c.sessions = [{ t: 0, at: 1000 }, { t: 20, at: 9000 }];
  assert.deepEqual(combatSpans(c), [{ from: 3, to: 20 }]);
  assert.ok(!routeSegments(c).some(x => x.from < 20 && x.to >= 20));
});

test("long routes stay continuous while cached chunks remain bounded", () => {
  const c = recording(Array.from({ length: 400 }, (_, i) => [i / 4, 0, i / 1000, i / 1000]));
  const segments = routeSegments(c);
  assert.ok(segments.every(x => x.points.length <= 128));
  assert.equal(segments[0].from, 0);
  assert.equal(segments[segments.length - 1].to, 99.75);
  for (let i = 1; i < segments.length; i++) assert.deepEqual(segments[i - 1].points.at(-1), segments[i].points[0]);
});

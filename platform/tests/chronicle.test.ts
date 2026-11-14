import test from "node:test";
import assert from "node:assert/strict";
import { buildIndex, clock, countByCategory, demoChronicle, eventAt, moneyText, parseChronicle, pathWindow, positionAt, totalsAt, visits, type Chronicle } from "../lib/chronicle";

const small = (): Chronicle => ({
  v: 1, character: { name: "Aria", classId: 8, level: 10 }, startedAt: 1000, duration: 100, zones: ["darkshore", "ashenvale"],
  path: [[0, 0, 0.1, 0.1], [10, 0, 0.3, 0.1], [20, 0, 0.3, 0.5], [60, 1, 0.5, 0.5], [62, 1, 0.6, 0.5]],
  events: [
    { t: 5, k: "kill", text: "Wolf", xp: 40 }, { t: 6, k: "loot", text: "Pelt", n: 2 }, { t: 7, k: "money", text: "Money", n: 150 },
    { t: 15, k: "quest", a: "turnin", text: "Q", xp: 200 }, { t: 30, k: "level", text: "Level 11", n: 11 }, { t: 60, k: "zone", text: "Ashenvale", zone: 1 },
    { t: 70, k: "skill", text: "Skinning", n: 93, max: 150 },
  ],
});

test("a recording is accepted only when every part of it is sound", () => {
  assert.ok(parseChronicle(small()));
  assert.equal(parseChronicle(null), null);
  assert.equal(parseChronicle({ ...small(), v: 2 }), null);
  assert.equal(parseChronicle({ ...small(), duration: 0 }), null);
  assert.equal(parseChronicle({ ...small(), zones: ["Not A Key"] }), null, "map keys are plain");
  assert.equal(parseChronicle({ ...small(), path: [[0, 5, 0.1, 0.1]] }), null, "a zone that does not exist");
  assert.equal(parseChronicle({ ...small(), path: [[0, 0, 1.5, 0.1]] }), null, "a position outside the zone");
  assert.equal(parseChronicle({ ...small(), path: [[10, 0, 0.1, 0.1], [5, 0, 0.1, 0.1]] }), null, "time going backwards");
  assert.equal(parseChronicle({ ...small(), events: [{ t: 1, k: "teleport", text: "x" }] }), null, "an unknown kind of event");
  assert.equal(parseChronicle({ ...small(), events: [{ t: 1, k: "kill", text: "x".repeat(500) }] }), null, "a very long text");
});

test("the position is interpolated inside a zone and holds across a gap or a zone change", () => {
  const c = small();
  assert.deepEqual({ ...positionAt(c, 5)! }, { zone: 0, x: 0.2, y: 0.1, moving: true });
  assert.equal(positionAt(c, 40)!.zone, 0, "40 s gap: the character stays where it was last seen");
  assert.equal(positionAt(c, 40)!.y, 0.5);
  assert.equal(positionAt(c, 61)!.zone, 1);
  assert.equal(positionAt(c, -3)!.x, 0.1, "before the first sample");
  assert.equal(positionAt({ ...c, path: [] }, 5), null);
});

test("the trail window stops at the zone the character entered", () => {
  const c = small();
  assert.deepEqual(pathWindow(c, 25, 100).map(p => p[0]), [0, 10, 20]);
  assert.deepEqual(pathWindow(c, 61, 100).map(p => p[0]), [60], "the earlier zone is not part of this trail");
  assert.deepEqual(pathWindow(c, 25, 8).map(p => p[0]), [20], "only the last few seconds");
  assert.deepEqual(visits(c), [{ zone: 0, from: 0, to: 20 }, { zone: 1, from: 20, to: 100 }]);
});

test("the numbers so far add up event by event", () => {
  const i = buildIndex(small());
  assert.deepEqual({ ...totalsAt(i, 0), skills: {} }, { quests: 0, kills: 0, xp: 0, copper: 0, items: 0, places: 1, deaths: 0, level: 10, skills: {} });
  const mid = totalsAt(i, 16);
  assert.equal(mid.kills, 1); assert.equal(mid.items, 2); assert.equal(mid.copper, 150); assert.equal(mid.quests, 1); assert.equal(mid.xp, 240); assert.equal(mid.level, 10);
  const end = totalsAt(i, 100);
  assert.equal(end.level, 11); assert.equal(end.places, 2); assert.deepEqual(end.skills, { Skinning: [93, 150] });
  assert.equal(totalsAt(i, 29.9).level, 10, "the level changes at the moment of the event");
});

test("finding the newest moment honours the chosen categories", () => {
  const c = small();
  assert.equal(eventAt(c, 20), 3);
  assert.equal(eventAt(c, 20, new Set(["combat"] as const)), 0);
  assert.equal(eventAt(c, 1), -1);
  assert.deepEqual(countByCategory(c), { quests: 1, combat: 1, loot: 2, professions: 1, travel: 1, character: 1 });
});

test("times and money read the way the game shows them", () => {
  assert.equal(clock(12), "0:12"); assert.equal(clock(3604), "1:00:04"); assert.equal(clock(-5), "0:00");
  assert.equal(moneyText(44 * 100 + 91), "44s 91c"); assert.equal(moneyText(10000 * 3 + 5), "3g 0s 5c"); assert.equal(moneyText(-1739), "−17s 39c");
});

test("the demo recording is valid, repeatable and long enough to be worth playing", () => {
  const a = demoChronicle(), b = demoChronicle();
  assert.deepEqual(a, b, "the same seed gives the same journey");
  assert.ok(parseChronicle(a), "it passes the same check as a real file");
  assert.ok(a.duration > 1800, `at least half an hour, got ${a.duration}s`);
  assert.ok(a.events.length > 100 && a.path.length > 500);
  assert.ok(a.events.some(e => e.k === "level") && a.events.some(e => e.k === "quest" && e.a === "accept") && a.events.some(e => e.k === "skill"));
  assert.notDeepEqual(demoChronicle(8).path, a.path, "another seed is another journey");
});

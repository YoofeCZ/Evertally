import test from "node:test";
import assert from "node:assert/strict";
import { buildHighlights, type Board, type Subject } from "../lib/chronicle-highlights";
import type { Chronicle, ChronicleEvent } from "../lib/chronicle";

const BASE = 1_794_300_000;
const ev = (t: number, k: ChronicleEvent["k"], text: string, extra: Partial<ChronicleEvent> = {}): ChronicleEvent => ({ t, k, text, ...extra });
const subject = (id: string, events: ChronicleEvent[], duration = 6000, startLevel = 12): Subject => ({
  profileId: id, name: id.toUpperCase(), realm: "Forever", classId: 1, level: 12,
  c: {
    v: 1, character: { name: id, classId: 1, level: startLevel }, startedAt: BASE, duration, zones: ["azeroth"],
    path: Array.from({ length: 61 }, (_, i) => [i * 100, 0, 0.3 + i * 0.002, 0.4 + (i % 7) * 0.001] as [number, number, number, number]), events, sessions: [{ t: 0, at: BASE }],
  } as Chronicle,
});
/** One run of a dungeon: in at `from`, the last boss falls after `seconds`, out a little later. */
const run = (from: number, seconds: number, deaths = 0, bosses = 2): ChronicleEvent[] => [
  ev(from, "dungeon", "Deadmines", { a: "enter" }),
  ...Array.from({ length: bosses }, (_, i) => ev(from + (seconds * (i + 1)) / bosses, "boss", `Boss ${i + 1}`, { a: "kill" })),
  ...Array.from({ length: deaths }, (_, i) => ev(from + 10 + i, "death", "You died")),
  ev(from + seconds + 60, "dungeon", "Deadmines", { a: "leave" }),
];
const quest = (id: number, from: number, to: number, title = `Quest ${id}`): ChronicleEvent[] => [ev(from, "quest", title, { a: "accept", id }), ev(to, "quest", title, { a: "turnin", id })];
const board = (out: { boards: Board[] }, id: string) => out.boards.find(b => b.id === id)!;

test("a dungeon board is timed from the door to the last boss; the record, the podium and a personal best come from it", () => {
  const a = subject("a", [...run(100, 1800), ...run(3000, 1700)]);
  const b = subject("b", run(100, 1500));
  const c = subject("c", run(100, 2100));
  const out = buildHighlights([a, b, c]);
  const door = board(out, "d:Deadmines");
  assert.deepEqual(door.entries.map(e => [e.profileId, e.value]), [["b", 1500], ["a", 1700], ["c", 2100]], "the best run of each player, fastest first");
  assert.equal(door.entries[0].detail, 2, "two bosses");
  assert.equal(door.entries[0].at, BASE + 100); assert.equal(door.entries[0].to, BASE + 1600, "the stretch to replay: door in to the last boss");
  assert.ok(door.entries[0].trail.length >= 4 && door.entries[0].trail.every(n => n >= 0 && n <= 100), "the shape of the route, for the thumbnail");
  const mine = (kind: string) => out.feed.filter(h => h.boardId === "d:Deadmines" && h.kind === kind).map(h => [h.profileId, h.rank]);
  assert.deepEqual(mine("record"), [["b", 1]]);
  assert.deepEqual(mine("podium").sort(), [["a", 2], ["c", 3]]);
  assert.deepEqual(mine("best"), [["a", 0]], "a's faster run is a personal best; b has only one run");
});

test("the first to clear a dungeon is the earliest, with how long it took", () => {
  const late = subject("late", run(100, 900));
  const early = subject("early", run(100, 1500));
  early.c.startedAt = BASE - 5000; early.c.sessions = [{ t: 0, at: BASE - 5000 }];
  const first = board(buildHighlights([late, early]), "f:Deadmines");
  assert.deepEqual(first.entries.map(e => e.profileId), ["early", "late"]);
  assert.equal(first.entries[0].unit, "date"); assert.equal(first.entries[0].value, BASE - 5000 + 1600); assert.equal(first.entries[0].detail, 1500);
});

test("every quest has a board from accepting it to handing it in; an abandoned quest and a hand-in with no accept count for nothing", () => {
  const a = subject("a", [...quest(7, 100, 160), ...quest(8, 200, 203)]);
  const b = subject("b", [...quest(7, 100, 190), ev(300, "quest", "Q9", { a: "accept", id: 9 }), ev(310, "quest", "Q9", { a: "abandon", id: 9 }), ev(320, "quest", "Q9", { a: "turnin", id: 9 }), ev(400, "quest", "Q10", { a: "turnin", id: 10 })]);
  const out = buildHighlights([a, b]);
  assert.deepEqual(board(out, "q:7").entries.map(e => [e.profileId, e.value]), [["a", 60], ["b", 90]]);
  assert.equal(board(out, "q:7").total, 2);
  assert.equal(board(out, "q:8").entries[0].value, 3);
  assert.equal(out.boards.find(x => x.id === "q:9"), undefined); assert.equal(out.boards.find(x => x.id === "q:10"), undefined);
  assert.deepEqual(out.closeRaces, ["q:7"], "the only board with a second place");
});

test("levelling is timed ten levels at a time, level 1 only when the recording starts there", () => {
  const lvl = (t: number, n: number) => ev(t, "level", `Level ${n}`, { n });
  const fresh = subject("fresh", [lvl(1000, 5), lvl(3000, 10), lvl(9000, 20)], 20000, 1);
  const mid = subject("mid", [lvl(500, 11), lvl(4500, 20)], 20000, 10);
  const out = buildHighlights([fresh, mid]);
  assert.equal(board(out, "l:1").entries[0].value, 3000, "level 1 to 10 from the start of the recording");
  assert.deepEqual(board(out, "l:10").entries.map(e => [e.profileId, e.value]), [["fresh", 6000]], "10 to 20 needs both levels seen: only fresh saw level 10 happen (mid began there)");
});

test("professions are timed from tier to tier by the skill-ups that were recorded", () => {
  const up = (t: number, n: number) => ev(t, "skill", "Herbalism", { n, max: 300 });
  const a = subject("a", [up(100, 1), up(900, 40), up(2100, 75), up(5000, 150)]);
  const out = buildHighlights([a]);
  assert.equal(board(out, "p:Herbalism:1").entries[0].value, 2000);
  assert.equal(board(out, "p:Herbalism:75").entries[0].value, 2900);
  assert.equal(out.boards.find(b => b.id === "p:Herbalism:150"), undefined, "nothing recorded past 150");
  const late = subject("late", [up(100, 40), up(900, 75)]);
  assert.equal(buildHighlights([late]).boards.find(b => b.id === "p:Herbalism:1"), undefined, "a first skill-up at 40 is not the start of the profession");
});

test("deathless: the furthest a new character got before its first death", () => {
  const lvl = (t: number, n: number) => ev(t, "level", `Level ${n}`, { n });
  const a = subject("a", [lvl(500, 2), lvl(1000, 6), lvl(2000, 9), ev(2500, "death", "You died"), lvl(3000, 10)], 9000, 1);
  const b = subject("b", [lvl(400, 2), lvl(900, 6), lvl(1800, 9), ev(2400, "death", "You died")], 9000, 1);
  const old = subject("old", [lvl(100, 41)], 9000, 40);
  const out = buildHighlights([a, b, old]);
  const dead = board(out, "x:deathless");
  assert.deepEqual(dead.entries.map(e => [e.profileId, e.value]), [["b", 9], ["a", 9]], "both reached 9; the one that got there sooner is first");
  assert.equal(dead.entries.length, 2, "a character that began at level 40 is not a new character");
  assert.equal(dead.entries[0].unit, "level");
});

test("the feed is newest first, close races are the smallest gaps, and the record holders are counted", () => {
  const a = subject("a", [...quest(1, 100, 160), ...quest(2, 200, 290)]);
  const b = subject("b", [...quest(1, 100, 165), ...quest(2, 200, 260)]);
  const out = buildHighlights([a, b]);
  assert.ok(out.feed.every((h, i) => i === 0 || out.feed[i - 1].to >= h.to));
  assert.deepEqual(out.closeRaces, ["q:1", "q:2"], "65 against 60 is closer than 90 against 60");
  assert.deepEqual(out.holders.map(h => [h.profileId, h.records]).sort(), [["a", 1], ["b", 1]]);
  assert.equal(buildHighlights([a, b], 2).feed.length, 2, "the feed is cut to the asked length");
});

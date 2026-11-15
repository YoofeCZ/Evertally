import test from "node:test";
import assert from "node:assert/strict";
import { buildIndex, clock, countByCategory, demoChronicle, eventAt, moneyText, parseChronicle, pathWindow, positionAt, totalsAt, visits, type Chronicle, type ChronicleEvent } from "../lib/chronicle";

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

import { ALL_TYPES, countByType, daysOf, instanceAt, instanceSummary, instances, passes, sessionAt, statsAt, typeKey, whenOf } from "../lib/chronicle";

test("every moment has exactly one type, and the filter honours type and item quality", () => {
  const c = demoChronicle();
  const counts = countByType(c);
  assert.equal(Object.values(counts).reduce((a, b) => a + b, 0), c.events.length);
  assert.ok(Object.keys(counts).every(k => ALL_TYPES.includes(k)), "no type outside the known list");
  const all = new Set(ALL_TYPES);
  const poor = { t: 1, k: "loot" as const, text: "Rag", q: 0 }, rare = { t: 1, k: "loot" as const, text: "Blade", q: 3 };
  assert.equal(passes(poor, all, 2), false); assert.equal(passes(rare, all, 2), true); assert.equal(passes(poor, all, 0), true);
  assert.equal(passes({ t: 1, k: "kill", text: "Wolf" }, new Set(["quest.accept"]), 0), false, "a type that is off is hidden");
  assert.equal(typeKey({ t: 0, k: "quest", a: "abandon", text: "x" }), "quest.abandon");
});

test("the days played and the clock of the day follow the sessions", () => {
  const c: Chronicle = { ...small(), duration: 300, path: [[0, 0, 0.1, 0.1]], events: [{ t: 10, k: "kill", text: "a" }, { t: 150, k: "kill", text: "b" }, { t: 250, k: "kill", text: "c" }], sessions: [{ t: 0, at: 1_699_963_200 }, { t: 100, at: 1_699_963_200 + 86_400 * 2 }, { t: 200, at: 1_699_963_200 + 86_400 * 2 + 3600 }] };
  assert.equal(sessionAt(c, 99), 0); assert.equal(sessionAt(c, 100), 1); assert.equal(sessionAt(c, 999), 2);
  assert.equal(whenOf(c, 50), 1_699_963_250); assert.equal(whenOf(c, 130), 1_699_963_200 + 86_400 * 2 + 30);
  const days = daysOf(c);
  assert.equal(days.length, 2, "two sessions on the same day are one day");
  assert.deepEqual(days.map(d => [d.from, d.to, d.events]), [[0, 100, 1], [100, 300, 2]]);
  assert.equal(whenOf(small(), 7), 1007, "without sessions the recording starts at startedAt");
});

test("a dungeon visit is summed up with its attempts on the bosses", () => {
  const c = demoChronicle();
  const list = instances(c);
  assert.equal(list.length, 2, "the dungeon and then the battleground"); assert.equal(list[0].name, "Blackfathom Deeps"); assert.equal(list[1].name, "Warsong Gulch"); assert.ok(list[0].to !== null);
  assert.equal(instanceAt(list, list[0].from - 5), null); assert.equal(instanceAt(list, list[0].from + 5)?.name, "Blackfathom Deeps"); assert.equal(instanceAt(list, list[0].to! + 5), null);
  const done = instanceSummary(c, list[0], c.duration);
  assert.equal(done.bosses.filter(b => b.a === "kill").length, 3); assert.equal(done.bosses.filter(b => b.a === "wipe").length, 1);
  assert.ok(done.kills > 20 && done.deaths >= 1 && done.items > 5);
  const early = instanceSummary(c, list[0], list[0].from + 30);
  assert.ok(early.kills < done.kills && early.bosses.length === 0, "only what happened by then");
});

test("the character sheet is the latest snapshot at or before the moment", () => {
  const c: Chronicle = { ...small(), stats: [{ t: 0, ilvl: 10 }, { t: 50, ilvl: 20 }] };
  assert.equal(statsAt(c, 49)?.ilvl, 10); assert.equal(statsAt(c, 50)?.ilvl, 20); assert.equal(statsAt(c, -1)?.ilvl, 10);
  assert.equal(statsAt(small(), 5), null);
});

test("the new parts of a recording are checked as strictly as the old ones", () => {
  const c = small();
  assert.ok(parseChronicle({ ...c, sessions: [{ t: 0, at: 1 }, { t: 10, at: 2 }], stats: [{ t: 0, ilvl: 5, attrs: [["Strength", 3]], enh: [["Haste", "2%"]] }], skills0: { Fishing: [5, 150] } }));
  assert.equal(parseChronicle({ ...c, sessions: [{ t: 10, at: 1 }, { t: 5, at: 2 }] }), null, "sessions in time order");
  assert.equal(parseChronicle({ ...c, stats: [{ t: 0, attrs: [["Strength", "many"]] }] }), null);
  assert.equal(parseChronicle({ ...c, skills0: { Fishing: [5] } }), null);
  assert.equal(parseChronicle({ ...c, events: [{ t: 1, k: "boss", text: "x", d: -3 }] }), null, "a negative fight time");
  assert.equal(parseChronicle({ ...c, events: [{ t: 1, k: "boss", text: "x", detail: "y".repeat(400) }] }), null);
});

test("item and race ids are plain positive numbers, and the demo's loot has real ids", () => {
  const c = small();
  assert.ok(parseChronicle({ ...c, character: { ...c.character, raceId: 4 }, events: [{ t: 1, k: "loot", text: "Linen Cloth", id: 2589, q: 1 }] }));
  assert.equal(parseChronicle({ ...c, events: [{ t: 1, k: "loot", text: "x", id: 0 }] }), null);
  assert.equal(parseChronicle({ ...c, events: [{ t: 1, k: "loot", text: "x", id: 1.5 }] }), null);
  assert.equal(parseChronicle({ ...c, character: { ...c.character, raceId: 4.5 } }), null);
  const loot = demoChronicle().events.filter(e => e.k === "loot");
  assert.ok(loot.length > 10 && loot.every(e => Number.isInteger(e.id) && (e.id ?? 0) > 0), "every demo item can show its icon");
});

import { fightAt, fightProgress } from "../lib/chronicle";

test("the demo's fights are consistent: each event opens its own fight, fights do not overlap and the series add up", () => {
  const c = demoChronicle();
  const fights = c.fights!;
  assert.equal(fights.filter(f => f.kind === "boss").length, 4, "three bosses and one wipe");
  assert.equal(fights.filter(f => f.kind === "pvp").length, 1);
  for (let i = 1; i < fights.length; i++) assert.ok(fights[i].t >= fights[i - 1].t + fights[i - 1].d - 1e-6, "no overlap");
  const opening = c.events.filter(e => e.f !== undefined);
  assert.equal(opening.length, fights.length);
  for (const e of opening) { const f = fights[e.f!]; assert.equal(f.name, e.text); assert.ok(Math.abs(e.t - (f.t + f.d)) < 2, "the moment closes its fight"); }
  for (const f of fights) {
    const sum = (a?: number[]) => (a ?? []).reduce((x, y) => x + y, 0);
    assert.equal(sum(f.series?.dmg), f.me.dmg); assert.equal(sum(f.series?.heal), f.me.heal); assert.equal(sum(f.series?.taken), f.me.taken);
    assert.equal(f.me.dmg, f.me.dealt.reduce((x, r) => x + r.total, 0), "the spells add up to the damage");
    assert.equal(f.group!.filter(m => m.me).length, 1, "exactly one member is the character");
  }
});

test("the fight in progress and its running counters follow the playhead", () => {
  const c = demoChronicle();
  const f = c.fights![0];
  assert.equal(fightAt(c, f.t - 1), -1); assert.equal(fightAt(c, f.t + f.d / 2), 0); assert.equal(fightAt(c, f.t + f.d + 1), -1);
  const half = fightProgress(f, f.d / 2), end = fightProgress(f, f.d);
  assert.ok(half.dmg > 0 && half.dmg < f.me.dmg, "partway through");
  assert.equal(end.dmg, f.me.dmg); assert.equal(end.taken, f.me.taken);
  assert.equal(fightProgress(f, 0).dmg, 0);
});

test("a file that points at a fight that is not there, or carries a broken one, is refused", () => {
  const demo = demoChronicle();
  assert.equal(parseChronicle({ ...demo, events: [...demo.events, { t: demo.duration, k: "boss", text: "x", f: 99 }] }), null, "no such fight");
  const { fights, ...without } = demo;
  assert.equal(parseChronicle({ ...without, events: [{ t: 1, k: "boss", text: "x", f: 0 }] }), null, "an event points at fights, but the file has none");
  assert.ok(fights && parseChronicle({ ...demo }));
  const bad = (change: (f: NonNullable<typeof demo.fights>[number]) => void) => { const copy = JSON.parse(JSON.stringify(demo)) as typeof demo; change(copy.fights![0]); return parseChronicle(copy); };
  assert.equal(bad(f => { f.me.dmg = -5; }), null, "negative damage");
  assert.equal(bad(f => { f.result = "draw" as never; }), null, "an unknown result");
  assert.equal(bad(f => { f.me.dealt[0].name = "x".repeat(200); }), null, "a long spell name");
  assert.equal(bad(f => { f.group![0].classId = 1.5; }), null);
  assert.equal(bad(f => { f.series!.step = 0; }), null);
});

import { MAX_SOUND_SPEED, cueFor, pickCues } from "../lib/chronicle-sound";

test("each moment has a sound or none, and a crowd of moments gives a few sounds, the most important first", () => {
  const e = (k: ChronicleEvent["k"], extra: Partial<ChronicleEvent> = {}): ChronicleEvent => ({ t: 1, k, text: "x", ...extra });
  assert.equal(cueFor(e("quest", { a: "accept" })), "quest-accept"); assert.equal(cueFor(e("quest", { a: "turnin" })), "quest-done"); assert.equal(cueFor(e("quest", { a: "abandon" })), null);
  assert.equal(cueFor(e("loot", { q: 1 })), null, "plain loot is silent"); assert.equal(cueFor(e("loot", { q: 2 })), "item"); assert.equal(cueFor(e("loot", { q: 4 })), "item-rare");
  assert.equal(cueFor(e("money", { n: 12 })), "coin"); assert.equal(cueFor(e("money", { n: 0 })), null);
  assert.equal(cueFor(e("boss", { a: "wipe" })), "boss-wipe"); assert.equal(cueFor(e("boss", { a: "kill" })), "boss-kill");
  assert.equal(cueFor(e("pvp", { a: "win" })), "pvp-win"); assert.equal(cueFor(e("pvp", { a: "loss" })), "pvp-loss");
  assert.equal(cueFor(e("dungeon", { a: "leave" })), null); assert.equal(cueFor(e("emote")), null);
  const crowd = [e("kill"), e("kill"), e("money", { n: 5 }), e("level", { n: 20 }), e("kill"), e("boss", { a: "kill" }), e("skill", { n: 5 })];
  assert.deepEqual(pickCues(crowd), ["boss-kill", "level", "skill"], "three at most, each kind once");
  assert.deepEqual(pickCues([]), []); assert.deepEqual(pickCues([e("emote")]), []);
  assert.ok(MAX_SOUND_SPEED >= 20 && MAX_SOUND_SPEED < 200, "no sounds at the fastest speeds");
});

import { LOG_KINDS } from "../lib/chronicle";

test("every fight has a combat log, and everything the window shows is added up from it", () => {
  const c = demoChronicle();
  const dmg = LOG_KINDS.indexOf("dmg"), heal = LOG_KINDS.indexOf("heal"), death = LOG_KINDS.indexOf("death");
  for (const f of c.fights!) {
    const log = f.log!, actors = f.actors!, spells = f.spells!;
    assert.ok(log.length > 200, `${f.name} has plenty of moves`);
    assert.ok(log.every((l, i) => i === 0 || l[0] >= log[i - 1][0]), "in time order");
    assert.ok(log.every(l => l[1] < actors.length && l[2] < actors.length && l[4] < spells.length), "every index points at something");
    assert.deepEqual([...new Set(actors.map(a => a.side))].sort(), ["enemy", "me", "party"], "the character, a group and enemies");
    const by = (pred: (l: (typeof log)[number]) => boolean) => log.filter(pred).reduce((a, l) => a + l[5], 0);
    assert.equal(f.me.dmg, by(l => l[1] === 0 && l[3] === dmg)); assert.equal(f.me.heal, by(l => l[1] === 0 && l[3] === heal)); assert.equal(f.me.taken, by(l => l[2] === 0 && l[3] === dmg));
    assert.equal(f.me.deaths, log.filter(l => l[3] === death && l[2] === 0).length);
    for (const [i, a] of actors.entries()) if (a.side !== "enemy") { const m = f.group!.find(x => x.name === a.name)!; assert.equal(m.dmg, by(l => l[1] === i && l[3] === dmg)); assert.equal(m.heal, by(l => l[1] === i && l[3] === heal)); }
  }
  const boss = c.fights!.find(f => f.kind === "boss")!;
  assert.ok(boss.me.interrupts! >= 1 && boss.log!.some(l => l[3] === LOG_KINDS.indexOf("interrupt")), "an interrupt is in the log");
  assert.ok(boss.log!.filter(l => boss.actors![l[1]].side === "enemy" && l[3] === dmg).length > 20, "the enemy acts too");
  assert.ok(boss.log!.filter(l => boss.actors![l[1]].side === "party" && l[3] === heal).length > 5, "so does the group");
});

test("a combat log with a wrong index or a wrong order is refused", () => {
  const demo = demoChronicle();
  const bad = (change: (f: NonNullable<typeof demo.fights>[number]) => void) => { const copy = JSON.parse(JSON.stringify(demo)) as typeof demo; change(copy.fights![0]); return parseChronicle(copy); };
  assert.equal(bad(f => { f.log![3][1] = 99; }), null, "a fighter that is not there");
  assert.equal(bad(f => { f.log![3][4] = 999; }), null, "a spell that is not there");
  assert.equal(bad(f => { f.log![3][3] = 42; }), null, "a kind that does not exist");
  assert.equal(bad(f => { f.log![5][0] = 0; }), null, "time going backwards");
  assert.equal(bad(f => { f.log![2][6] = 2 as never; }), null);
  assert.equal(bad(f => { f.log![2].pop(); }), null, "a short line");
  assert.equal(bad(f => { delete f.spells; }), null, "a log without its spell names");
  assert.ok(bad(f => { delete f.log; delete f.actors; delete f.spells; }), "a fight without a log is still fine (older recordings)");
});

import { findProblem } from "../lib/chronicle";

test("a refused file is traced to the part that is wrong, so a recorder can be fixed without guessing", () => {
  const demo = demoChronicle();
  const copy = () => JSON.parse(JSON.stringify(demo)) as Chronicle & Record<string, unknown>;
  assert.equal(findProblem(demo), null);
  assert.equal(findProblem(null), "the file is not a JSON object"); assert.equal(findProblem([]), "the file is not a JSON object");
  assert.equal(findProblem({ ...copy(), v: 2 }), '"v" must be 1');
  assert.equal(findProblem({ ...copy(), duration: 0 }), "the header: character, startedAt, duration or zones");
  let c = copy(); c.events[77].t = -5; assert.equal(findProblem(c), "events[77]");
  c = copy(); c.path[1234][2] = 7; assert.equal(findProblem(c), "path[1234]");
  c = copy(); c.fights![2].me.dmg = -1; assert.equal(findProblem(c), "fights[2]");
  c = copy(); c.fights![1].log![10][1] = 99; assert.equal(findProblem(c), "fights[1]");
  c = copy(); c.sessions = [{ t: 9, at: 1 }, { t: 3, at: 2 }]; assert.equal(findProblem(c), '"sessions"');
  c = copy(); c.events[5].f = 999; assert.equal(findProblem(c), "events[5]", "a fight that is not there");
  c = copy(); (c as Record<string, unknown>).events = "no"; assert.equal(findProblem(c), '"events" must be a list');
});

import { readFileSync } from "node:fs";
test("the example files of the format specification are valid recordings", () => {
  for (const name of ["priklad-minimalni.json", "priklad-souboj.json"]) {
    const raw = JSON.parse(readFileSync(`../docs/kronika/${name}`, "utf8"));
    assert.equal(findProblem(raw), null, name);
    assert.ok(parseChronicle(raw), name);
  }
  const fight = parseChronicle(JSON.parse(readFileSync("../docs/kronika/priklad-souboj.json", "utf8")))!;
  const f = fight.fights![0], log = f.log!;
  assert.equal(f.me.dmg, log.filter(l => l[1] === 0 && l[3] === 0).reduce((a, l) => a + l[5], 0), "the example's totals really are the sum of its log");
  assert.equal(f.series!.dmg.reduce((a, b) => a + b, 0), f.me.dmg);
});

test("the table of map keys and uiMapIDs in the specification is the website's own catalogue", () => {
  const manifest = JSON.parse(readFileSync("public/media/maps/manifest.json", "utf8")) as { maps: { key: string; nameEn: string; uiMapIds: number[] }[] };
  const table = JSON.parse(readFileSync("../docs/kronika/mapy.json", "utf8")) as { maps: { key: string; name: string; uiMapIds: number[] }[] };
  const want = manifest.maps.map(m => ({ key: m.key, name: m.nameEn, uiMapIds: [...m.uiMapIds].sort((a, b) => a - b) })).sort((a, b) => a.key.localeCompare(b.key));
  assert.deepEqual(table.maps, want, "out of date: run `node scripts/write-chronicle-maps.mjs` in platform/");
  assert.ok(table.maps.every(m => /^[a-z0-9][a-z0-9-]{0,79}$/.test(m.key)), "every key is a valid zone key of a recording");
});

test("a real time is found again inside the session it was played in, and never past it", async () => {
  const { journeyTimeOf, whenOf } = await import("../lib/chronicle");
  const c = { v: 1, character: { name: "A", classId: 1, level: 5 }, startedAt: 1000, duration: 900, zones: ["azeroth"], path: [], events: [],
    sessions: [{ t: 0, at: 1000 }, { t: 300, at: 50_000 }] } as never;
  assert.equal(journeyTimeOf(c, 1100), 100);
  assert.equal(journeyTimeOf(c, 50_100), 400);
  assert.equal(journeyTimeOf(c, 20_000), 300, "a gap between sessions ends at the start of the next one");
  assert.equal(journeyTimeOf(c, 10), 0, "before the first session");
  assert.equal(journeyTimeOf(c, 99_999), 900, "and after the last");
  assert.equal(journeyTimeOf(c, whenOf(c, 450)), 450);
});

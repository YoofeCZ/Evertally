import test from "node:test";
import assert from "node:assert/strict";
import { fixture } from "./sqlite-db";
import { SESSION_GAP, composeChronicle, myChronicle, type MapKey, type Observation } from "../lib/chronicle-build";
import { findProblem } from "../lib/chronicle";

const MAPS: MapKey[] = [{ key: "darkshore", uiMapIds: [1439] }, { key: "ashenvale", uiMapIds: [1440, 1441] }];
const BASE = 1_794_300_000;
const subject = { name: "Aria", classId: 11, raceId: 4, realm: "Forever", level: 12 };
const ob = (kind: string, at: number, payload: Record<string, unknown>): Observation => ({ kind, observedAt: at, payload });

const journey = (): Observation[] => [
  ob("track.path", BASE + 60, { mapId: 1439, startedAt: BASE, points: [[0, 0.4, 0.8], [4, 0.41, 0.79], [8, 0.42, 0.78], [60, 0.45, 0.75]] }),
  ob("zone.visited", BASE + 2, { mapId: 1439, mapSystem: "ui_map", mapName: "Darkshore" }),
  ob("quest.accepted", BASE + 10, { questId: 3524, title: "A Lost Master", mapId: 1439, x: 0.41, y: 0.79 }),
  ob("loot.received", BASE + 20, { itemId: 17056, name: "Light Feather", quantity: 2 }),
  ob("character.level", BASE + 30, { level: 12 }),
  ob("quest.turned_in", BASE + 50, { questId: 3524, title: "A Lost Master", xp: 180, money: 250, mapId: 1439, x: 0.46, y: 0.74 }),
  ob("character.level", BASE + 55, { level: 13 }),
  // a long break, then the second evening
  ob("track.path", BASE + 5000, { mapId: 1440, startedAt: BASE + 4990, points: [[0, 0.2, 0.3], [6, 0.21, 0.31], [10, 0.22, 0.32]] }),
  ob("instance.entered", BASE + 5003, { runId: "run-1", name: "Blackfathom Deeps", instanceType: "party", startedAt: BASE + 5003 }),
  ob("raid.encounter_finished", BASE + 5100, { encounterId: 1, name: "Ghamoo-ra", success: false, durationMs: 74000, instanceName: "Blackfathom Deeps" }),
  ob("raid.encounter_finished", BASE + 5200, { encounterId: 1, name: "Ghamoo-ra", success: true, durationMs: 150500, instanceName: "Blackfathom Deeps" }),
  ob("run.finished", BASE + 5300, { runId: "run-1", name: "Blackfathom Deeps", startedAt: BASE + 5003 }),
];

test("a recording is composed from stored events: the route, the zones, quests, loot, levels, dungeons and bosses", () => {
  const c = composeChronicle(subject, journey(), MAPS)!;
  assert.ok(c, "valid recording");
  assert.equal(findProblem(c), null);
  assert.deepEqual(c.zones, ["darkshore", "ashenvale"], "zones in the order they appear");
  assert.equal(c.sessions!.length, 2, "a break longer than the gap is a new session");
  assert.equal(c.sessions![0].at, BASE); assert.equal(c.sessions![1].at, BASE + 4990);
  assert.equal(c.sessions![1].t, c.sessions![0].t + 60, "the night away is not part of the recording");
  assert.ok(c.duration >= 60 + 310 && c.duration < 60 + 311 + 1, `duration ${c.duration}`);
  assert.equal(c.character.level, 12, "the level it started at");
  assert.deepEqual(c.path.slice(0, 2), [[0, 0, 0.4, 0.8], [4, 0, 0.41, 0.79]]);
  assert.ok(c.path.every((p, i) => i === 0 || p[0] >= c.path[i - 1][0]), "the route runs forward in time");
  assert.equal(c.path.at(-1)![1], 1, "the second stretch is in the second zone");

  const kinds = c.events.map(e => `${e.k}${e.a ? `:${e.a}` : ""}`);
  assert.deepEqual(kinds.filter(k => k.startsWith("quest")), ["quest:accept", "quest:turnin"]);
  const accept = c.events.find(e => e.a === "accept")!;
  assert.deepEqual({ text: accept.text, id: accept.id, zone: accept.zone, x: accept.x, y: accept.y }, { text: "A Lost Master", id: 3524, zone: 0, x: 0.41, y: 0.79 });
  const turnin = c.events.find(e => e.a === "turnin")!;
  assert.equal(turnin.xp, 180);
  assert.equal(c.events.find(e => e.k === "money")!.n, 250, "the reward becomes money");
  const loot = c.events.find(e => e.k === "loot")!;
  assert.deepEqual({ text: loot.text, n: loot.n, id: loot.id, q: loot.q }, { text: "Light Feather", n: 2, id: 17056, q: undefined }, "the quality is not stored, so it is not invented");
  assert.deepEqual(c.events.filter(e => e.k === "level").map(e => e.n), [13], "only a rise in level is an event");
  const bosses = c.events.filter(e => e.k === "boss");
  assert.deepEqual(bosses.map(b => [b.a, b.n, b.d]), [["wipe", 1, 74], ["kill", 2, 150.5]], "the second attempt is attempt 2");
  assert.deepEqual(c.events.filter(e => e.k === "dungeon").map(e => e.a), ["enter", "leave"]);
  assert.ok(c.events.every((e, i) => i === 0 || e.t >= c.events[i - 1].t), "events in order");
  assert.equal(c.fights, undefined, "there are no per-fight numbers to show, so no fight windows");
});

test("nothing recorded is no recording, and damaged or unknown data is left out instead of breaking it", () => {
  assert.equal(composeChronicle(subject, [], MAPS), null);
  const mess: Observation[] = [
    ob("track.path", BASE, { mapId: 9999, startedAt: BASE, points: [[0, 0.1, 0.1]] }),
    ob("track.path", BASE + 5, { mapId: 1439, startedAt: BASE, points: [[0, 2, 0.1], [1, "x", 0.1], [2, 0.3, 0.3]] }),
    ob("quest.accepted", BASE + 3, { questId: -4 }),
    ob("quest.accepted", BASE + 4, { questId: 77 }),
    ob("loot.received", BASE + 5, { itemId: 5, quantity: 0 }),
    ob("zone.visited", BASE + 6, { mapId: 4242 }),
    ob("run.finished", BASE + 7, { runId: "never-entered" }),
    ob("raid.encounter_finished", BASE + 8, { name: "no id", success: true }),
  ];
  const c = composeChronicle(subject, mess, MAPS)!;
  assert.ok(c && findProblem(c) === null);
  assert.deepEqual(c.path, [[2, 0, 0.3, 0.3]], "only the one good point of a known map");
  assert.deepEqual(c.events.map(e => e.text), ["Quest 77"], "a quest without a title gets its number");
  assert.deepEqual(c.zones, ["darkshore"], "an unknown map is not a zone");
  const only = composeChronicle(subject, [ob("loot.received", BASE, { itemId: 1, quantity: 1 })], MAPS)!;
  assert.ok(only && only.path.length === 0 && only.events.length === 1, "events without any route still make a recording");
  assert.ok(SESSION_GAP > 0);
});

test("the website reads only what the character's owner allows, for the characters of the account itself", async () => {
  const { sql, db } = fixture();
  const put = (id: string, user: string, profile: string, kind: string, at: number, payload: unknown) =>
    sql.prepare("INSERT INTO atlas_observations(id,user_id,producer_id,event_id,grant_id,kind,scope,observed_at,profile_id,payload,game,evidence) VALUES(?,?,?,?,?,?,'x',?,?,?,'{}','api_snapshot')")
      .run(id, user, "src-" + user, "e-" + id, "grant-" + user, kind, at, profile, JSON.stringify(payload));
  const now = BASE + 100_000;
  put("1", "gm", "p-gm", "track.path", now - 50, { mapId: 1439, startedAt: now - 60, points: [[0, 0.4, 0.8], [5, 0.41, 0.8]] });
  put("2", "gm", "p-gm", "quest.accepted", now - 40, { questId: 9, title: "Mine" });
  put("3", "gm", "p-gm", "raid.encounter_finished", now - 30, { encounterId: 1, name: "Boss", success: true });
  put("4", "gm", "p-gm", "quest.accepted", now - 20 * 86400, { questId: 8, title: "Too old for a week" });
  put("5", "bob", "p-bob", "quest.accepted", now - 40, { questId: 7, title: "Someone else's" });
  put("6", "gm", "p-gm", "quest.accepted", now - 70 * 86400, { questId: 6, title: "Older than any period" });

  const week = await myChronicle(db, "gm", "p-gm", 7, MAPS, now);
  assert.equal(week!.observations, 2, "route and quest; the boss needs 'My runs', the old quest is outside the week");
  assert.deepEqual(week!.chronicle!.events.map(e => e.text), ["Mine"]);
  assert.equal(week!.chronicle!.character.name, "Aria");

  sql.exec(`UPDATE atlas_grants SET scopes='["own_track","guild_share","own_character","own_runs"]' WHERE user_id='gm'`);
  assert.deepEqual((await myChronicle(db, "gm", "p-gm", 7, MAPS, now))!.chronicle!.events.map(e => e.k), ["quest", "boss"], "with 'My runs' the boss is there");
  assert.equal((await myChronicle(db, "gm", "p-gm", 90, MAPS, now))!.observations, 4, "90 days is capped to 60: the 20-day-old quest is in, the 70-day-old one is not");
  sql.exec(`UPDATE atlas_grants SET scopes='["own_character"]' WHERE user_id='gm'`);
  assert.equal((await myChronicle(db, "gm", "p-gm", 7, MAPS, now))!.chronicle!.path.length, 0, "without 'My route' there is no route");

  assert.equal(await myChronicle(db, "gm", "p-bob", 7, MAPS, now), null, "another account's character is not available");
  assert.equal(await myChronicle(db, "gm", "no-such", 7, MAPS, now), null);
  sql.exec("UPDATE atlas_grants SET revoked_at=1 WHERE user_id='gm'");
  assert.equal((await myChronicle(db, "gm", "p-gm", 7, MAPS, now))!.chronicle, null, "a revoked consent shows nothing");
});

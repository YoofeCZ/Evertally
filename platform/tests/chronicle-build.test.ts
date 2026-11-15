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
  assert.equal((await myChronicle(db, "gm", "p-gm", 90, MAPS, now))!.observations, 5, "90 days is 90 days: the 20-day-old quest is in and the 70-day-old one too");
  assert.equal((await myChronicle(db, "gm", "p-gm", 0, MAPS, now))!.observations, 5, "no period: the whole history");
  sql.exec(`UPDATE atlas_grants SET scopes='["own_character"]' WHERE user_id='gm'`);
  assert.equal((await myChronicle(db, "gm", "p-gm", 7, MAPS, now))!.chronicle!.path.length, 0, "without 'My route' there is no route");

  assert.equal(await myChronicle(db, "gm", "p-bob", 7, MAPS, now), null, "another account's character is not available");
  assert.equal(await myChronicle(db, "gm", "no-such", 7, MAPS, now), null);
  sql.exec("UPDATE atlas_grants SET revoked_at=1 WHERE user_id='gm'");
  assert.equal((await myChronicle(db, "gm", "p-gm", 7, MAPS, now))!.chronicle, null, "a revoked consent shows nothing");
});

import { eventSchema, scopeFor, JOURNEY_MAX_MOMENTS } from "../lib/contracts";

test("batches of journey moments (kills, money, skills, deaths, groups, flights) become moments of the recording", () => {
  const obs: Observation[] = [
    ob("track.path", BASE + 20, { mapId: 1439, startedAt: BASE, points: [[0, 0.4, 0.8], [10, 0.45, 0.75], [20, 0.5, 0.7]] }),
    ob("journey.chunk", BASE + 40, { startedAt: BASE, events: [
      { t: 5, k: "kill", text: "Thistle Bear", xp: 42, mapId: 1439, x: 0.42, y: 0.78 },
      { t: 6, k: "money", n: 36 },
      { t: 8, k: "money", text: "Spent", n: -120 },
      { t: 12, k: "skill", text: "Herbalism", n: 93, max: 150 },
      { t: 15, k: "skill", text: "Fishing", n: 12 },
      { t: 18, k: "group", a: "join", text: "Joined a group of 3" },
      { t: 30, k: "travel", a: "flight", text: "Took a flight" },
      { t: 32, k: "death" },
      { t: 33, k: "teleport", text: "no such moment" },
      { t: "x", k: "kill" },
    ] }),
    ob("loot.received", BASE + 11, { itemId: 3, name: "Blue Thing", quantity: 1, quality: 3 }),
    ob("loot.received", BASE + 11, { itemId: 4, name: "Odd Thing", quantity: 1, quality: 9 }),
    ob("quest.turned_in", BASE + 14, { questId: 5, title: "No Place Kept" }),
    ob("quest.turned_in", BASE + 400, { questId: 6, title: "Too Long After The Route" }),
  ];
  const c = composeChronicle(subject, obs, MAPS)!;
  assert.ok(c && findProblem(c) === null);
  const by = (k: string) => c.events.filter(e => e.k === k);
  assert.deepEqual(by("kill").map(e => [e.text, e.xp, e.x, e.y]), [["Thistle Bear", 42, 0.42, 0.78]], "the place of a kill comes from the batch");
  assert.deepEqual(by("money").map(e => e.n), [36, -120], "money, also what was spent");
  assert.deepEqual(by("skill").map(e => [e.text, e.n, e.max]), [["Herbalism", 93, 150], ["Fishing", 12, undefined]], "a skill without a known maximum has none");
  assert.equal(by("death")[0].text, "You died", "a moment without a text gets its own");
  assert.equal(by("group")[0].a, "join"); assert.equal(by("travel")[0].a, "flight");
  assert.equal(c.events.some(e => (e.k as string) === "teleport"), false, "a kind the website does not know is dropped, not shown");
  assert.deepEqual(by("loot").map(e => [e.text, e.q]), [["Blue Thing", 3], ["Odd Thing", undefined]], "quality only when it is a real quality");
  const kept = c.events.find(e => e.text === "No Place Kept")!;
  assert.deepEqual([kept.zone, kept.x, kept.y], [0, 0.45, 0.75], "a quest the website keeps no place of takes the place of the route at that time");
  const far = c.events.find(e => e.text === "Too Long After The Route")!;
  assert.equal(far.x, undefined, "but not from a route that ended minutes before");
});

test("the contract accepts a batch of moments and refuses what could swamp or deceive the database", () => {
  const event = (payload: unknown, kind = "journey.chunk") => ({ schemaVersion: 1, eventId: "p:s:1", producerId: "p", origin: "local_observation", kind, observedAt: BASE, game: { product: "forever", build: "1.60.1.70862", interface: 11507, region: "eu", realm: "Blesky" }, evidence: "api_snapshot", payload });
  const good = { startedAt: BASE - 100, events: [{ t: 1, k: "kill", text: "Wolf", xp: 10, mapId: 1439, x: 0.5, y: 0.5 }, { t: 2, k: "money", n: -50 }] };
  assert.equal(eventSchema.safeParse(event(good)).success, true);
  assert.equal(scopeFor("journey.chunk"), "own_track", "it needs the same consent as the route");
  const refused = (payload: unknown) => eventSchema.safeParse(event(payload)).success === false;
  assert.ok(refused({ ...good, events: [] }), "an empty batch");
  assert.ok(refused({ ...good, events: Array.from({ length: JOURNEY_MAX_MOMENTS + 1 }, (_, t) => ({ t, k: "kill" })) }), "too many moments in one batch");
  assert.ok(refused({ startedAt: BASE, events: [{ t: 1, k: "quest" }] }), "a kind that other events already carry");
  assert.ok(refused({ startedAt: BASE, events: [{ t: 1, k: "kill", x: 2 }] }), "a place outside the map");
  assert.ok(refused({ startedAt: BASE, events: [{ t: 1, k: "kill", secret: "x" }] }), "an unknown field");
  assert.ok(refused({ startedAt: BASE, events: [{ t: 100000, k: "kill" }] }), "a moment more than a day after the start");
  assert.ok(refused({ startedAt: BASE + 100000, events: [{ t: 1, k: "kill" }] }), "a batch that starts after it was observed");
  const loot = (quality: number) => eventSchema.safeParse(event({ itemId: 5, name: "x", quantity: 1, quality }, "loot.received")).success;
  assert.equal(loot(3), true); assert.equal(loot(6), false, "an item quality is 0 to 5");
});

import { listChronicles, readChronicle, summarize } from "../lib/chronicle-build";

test("a chronicle is public only when the character is public AND its player turned the public chronicle on; the owner always sees their own", async () => {
  const { sql, db } = fixture();
  const now = BASE + 100_000;
  const put = (id: string, user: string, profile: string, kind: string, at: number, payload: unknown) =>
    sql.prepare("INSERT INTO atlas_observations(id,user_id,producer_id,event_id,grant_id,kind,scope,observed_at,profile_id,payload,game,evidence) VALUES(?,?,?,?,?,?,'x',?,?,?,'{}','api_snapshot')")
      .run(id, user, "src-" + user, "e-" + id, "grant-" + user, kind, at, profile, JSON.stringify(payload));
  for (const [user, profile, from] of [["gm", "p-gm", 4000], ["bob", "p-bob", 100]] as const) {
    put(`t-${user}`, user, profile, "track.path", now - from, { mapId: 1439, startedAt: now - from - 120, points: [[0, 0.4, 0.8], [60, 0.5, 0.8], [120, 0.6, 0.8]] });
    put(`q-${user}`, user, profile, "quest.accepted", now - from - 60, { questId: 9, title: `Quest of ${user}` });
  }
  const read = (viewer: string | null, profile: string) => readChronicle(db, viewer, profile, 14, MAPS, now);
  // nothing is public yet
  assert.equal(await read("eve", "p-gm"), null, "a stranger gets nothing, and not even a hint that it exists");
  assert.equal(await read(null, "p-gm"), null, "a visitor who is not signed in neither");
  assert.equal((await read("gm", "p-gm"))!.own, true, "the owner always");
  // the character is public, the chronicle is not
  sql.exec("UPDATE atlas_profiles SET public=1 WHERE id='p-gm'");
  assert.equal(await read("eve", "p-gm"), null, "a public character is not a public chronicle");
  // both on
  sql.exec("UPDATE atlas_profiles SET show_chronicle=1 WHERE id='p-gm'");
  const shared = (await read(null, "p-gm"))!;
  assert.deepEqual([shared.shared, shared.own, shared.chronicle!.character.name], [true, false, "Aria"]);
  // the chronicle on, but the character hidden again: not public
  sql.exec("UPDATE atlas_profiles SET public=0 WHERE id='p-gm'");
  assert.equal(await read("eve", "p-gm"), null, "hiding the character hides its chronicle");
  sql.exec("UPDATE atlas_profiles SET public=1 WHERE id='p-gm'");
  // a revoked consent: nothing left to show
  sql.exec("UPDATE atlas_grants SET revoked_at=1 WHERE user_id='gm'");
  assert.equal((await read("eve", "p-gm"))!.chronicle, null);
  sql.exec("UPDATE atlas_grants SET revoked_at=NULL WHERE user_id='gm'");

  // the list: only what is shared, plus the viewer's own, each with its time
  const list = await listChronicles(db, "bob", 14, MAPS, now);
  assert.deepEqual(list.map(l => [l.name, l.shared, l.own]), [["Bran", false, true], ["Aria", true, false]], "the viewer's own (not shared) and the shared one, newest played first");
  const aria = list.find(l => l.name === "Aria")!;
  assert.equal(aria.summary.seconds >= 120, true); assert.equal(aria.summary.sessions, 1);
  assert.ok(aria.summary.from > 0 && aria.summary.to >= aria.summary.from, "when it was played");
  assert.deepEqual((await listChronicles(db, null, 14, MAPS, now)).map(l => l.name), ["Aria"], "a visitor sees only the shared one");
  sql.exec("UPDATE atlas_profiles SET show_chronicle=0 WHERE id='p-gm'");
  assert.deepEqual((await listChronicles(db, null, 14, MAPS, now + 10)).map(l => l.name), [], "turning the public chronicle off takes effect at once, whatever was remembered");
});

test("the time of a recording is written from its length and its sessions", () => {
  const c = composeChronicle(subject, journey(), MAPS)!;
  const s = summarize(c);
  assert.equal(s.seconds, c.duration); assert.equal(s.sessions, 2);
  assert.equal(s.from, BASE); assert.ok(s.to >= BASE + 5300 && s.to <= BASE + 5303, `to ${s.to}`);
  assert.equal(summarize({ ...c, sessions: undefined }).sessions, 1, "without sessions it is one");
});

test("the whole history is composed when no period is asked for, and a remembered chronicle is replaced as soon as new data arrives", async () => {
  const { sql, db } = fixture();
  const now = BASE + 400 * 86400;
  const put = (id: string, at: number, kind: string, payload: unknown) =>
    sql.prepare("INSERT INTO atlas_observations(id,user_id,producer_id,event_id,grant_id,kind,scope,observed_at,profile_id,payload,game,evidence) VALUES(?,?,?,?,?,?,'x',?,?,?,'{}','api_snapshot')")
      .run(id, "gm", "src-gm", "e-" + id, "grant-gm", kind, at, "p-gm", JSON.stringify(payload));
  put("old", now - 300 * 86400, "quest.accepted", { questId: 1, title: "A year ago" });
  put("recent", now - 100, "quest.accepted", { questId: 2, title: "Just now" });
  sql.exec("UPDATE atlas_profiles SET public=1, show_chronicle=1, last_seen=" + (now - 100) + " WHERE id='p-gm'");
  const titles = async (days: number) => ((await readChronicle(db, null, "p-gm", days, MAPS, now))!.chronicle?.events ?? []).map(e => e.text);
  assert.deepEqual(await titles(0), ["A year ago", "Just now"], "no period: everything, however old");
  assert.deepEqual(await titles(30), ["Just now"], "a period still cuts");
  assert.equal((await listChronicles(db, null, 0, MAPS, now)).find(l => l.name === "Aria")!.summary.events, 2);
  // new data arrives: the next look shows it at once, though only a second passed
  put("fresh", now + 1, "quest.accepted", { questId: 3, title: "Hours later" });
  assert.equal((await listChronicles(db, null, 0, MAPS, now + 1)).find(l => l.name === "Aria")!.summary.events, 2, "nothing new is known yet: the remembered one");
  sql.exec("UPDATE atlas_profiles SET last_seen=" + (now + 1) + " WHERE id='p-gm'");
  assert.equal((await listChronicles(db, null, 0, MAPS, now + 2)).find(l => l.name === "Aria")!.summary.events, 3, "the character was seen again: composed anew");
});

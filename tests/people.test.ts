import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { DatabaseSync, type SQLInputValue } from "node:sqlite";
import { exportSchema, scopeFor, type AtlasEvent, type ExportEnvelope } from "../lib/contracts";
import { projectExport } from "../lib/import";
import { sanitizedPayload, validateUpload } from "../lib/policy";
import { applyGuildSnapshots, baseName, eraseMyTrail, guildOverview, guildTrail, myTrail, pruneTracks, releaseStatements, setMembership, type Db, type Stmt } from "../lib/people";

const code = (expected: string) => (error: unknown) => (error as { code?: string }).code === expected;
const t0 = Math.floor(Date.now() / 1000) - 600;
const game = { product: "forever" as const, build: "test", interface: 16001, region: "test", realm: "Test" };
const base = { schemaVersion: 1 as const, producerId: "source", origin: "local_observation" as const, game, evidence: "api_snapshot" as const };
const character = { id: "guid-1", name: "Aria", realm: "Test", classId: 8, raceId: 1, level: 30 };
const track = (overrides: Partial<AtlasEvent["payload"]> = {}, extra: Partial<AtlasEvent> = {}): AtlasEvent => ({
  ...base, eventId: "source:1:1", kind: "track.path", observedAt: t0 + 100, character,
  payload: { mapId: 1429, startedAt: t0, points: [[0, 0.5, 0.5], [10, 0.51, 0.5]], ...overrides }, ...extra,
});
const guild = (payload: Record<string, unknown>, extra: Partial<AtlasEvent> = {}): AtlasEvent => ({ ...base, eventId: "source:1:2", kind: "guild.snapshot", observedAt: t0 + 100, character, payload, ...extra });
const envelope = (events: AtlasEvent[], scopes: ExportEnvelope["scopes"]): ExportEnvelope => ({ schemaVersion: 1, enabled: true, producerId: "source", consentEpoch: 1, since: t0 - 10, scopes, events });
const policy = (scopes: ExportEnvelope["scopes"]) => ({ producerId: "source", consentEpoch: 1, since: t0 - 10, scopes, revokedAt: null });

// --- contracts and projection ---
test("Trasa a cech mají vlastní oblasti a ne světová fakta", () => {
  assert.equal(scopeFor("track.path"), "own_track");
  assert.equal(scopeFor("guild.snapshot"), "guild_share");
  assert.equal(exportSchema.safeParse(envelope([track()], ["own_track", "own_character"])).success, true);
});
test("Trasa: neplatné body, příliš dlouhá cesta a start v budoucnu se odmítnou", () => {
  const ok = (e: AtlasEvent) => exportSchema.safeParse(envelope([e], ["own_track", "own_character"])).success;
  assert.equal(ok(track({ points: [[0, 1.2, 0.5]] })), false);
  assert.equal(ok(track({ points: [] })), false);
  assert.equal(ok(track({ points: Array.from({ length: 121 }, () => [0, 0.5, 0.5]) })), false);
  assert.equal(ok(track({ startedAt: t0 + 5000 })), false);
  assert.equal(ok(track({ unknown: 1 })), false);
});
test("Soupis cechu smí poslat jen guildmaster a jen s názvem cechu", () => {
  const ok = (e: AtlasEvent) => exportSchema.safeParse(envelope([e], ["guild_share", "own_character"])).success;
  const roster = [{ name: "Bran", rankIndex: 1, level: 20, classId: 3 }];
  assert.equal(ok(guild({ guildName: "Dawn", rankIndex: 0, roster })), true);
  assert.equal(ok(guild({ guildName: "Dawn", rankIndex: 2, roster })), false);
  assert.equal(ok(guild({ rankIndex: 0, roster })), false);
  assert.equal(ok(guild({ guildName: "Dawn", rankIndex: 2 })), true);
  assert.equal(ok(guild({ roster })), false);
});
test("Odchod z cechu se posílá jako {left:true}; prázdný payload ani left:false neprojdou", () => {
  const ok = (payload: Record<string, unknown>) => exportSchema.safeParse(envelope([guild(payload)], ["guild_share", "own_character"])).success;
  assert.equal(ok({ left: true }), true);
  assert.equal(ok({ left: false }), false);
  assert.equal(ok({}), true); // valid for the schema, but the addon never sends it: an empty Lua table reads back as an array
});
test("Cech se bez oblasti postavy nikdy nepošle a trasa zůstane pseudonymní", () => {
  const env = envelope([track(), guild({ guildName: "Dawn", rankIndex: 1 })], ["own_track", "guild_share", "own_character"]);
  const clean = projectExport(env, ["own_track", "guild_share"]);
  assert.deepEqual(clean.scopes, ["own_track"]);
  assert.equal(clean.events.length, 1);
  assert.deepEqual(clean.events[0].character, { id: "source:own", classId: 8, raceId: 1, level: 30 });
  assert.doesNotThrow(() => validateUpload(policy(["own_track"]), clean));
  assert.equal(JSON.stringify(clean).includes("Aria"), false);
});
test("Server odmítne cech bez postavy a jméno schované v pseudonymní trase", () => {
  assert.throws(() => validateUpload(policy(["guild_share"]), envelope([guild({ guildName: "Dawn", rankIndex: 1 })], ["guild_share"])), code("identity_scope_denied"));
  assert.throws(() => validateUpload(policy(["own_track"]), envelope([track()], ["own_track"])), code("identity_scope_denied"));
});
test("Soupis cechu se neukládá do pozorování; trasa zůstane beze změny", () => {
  const ev = guild({ guildName: "Dawn", rankIndex: 0, roster: [{ name: "Bran", rankIndex: 1 }] });
  assert.deepEqual(sanitizedPayload(ev), { guildName: "Dawn", rankIndex: 0 });
  assert.deepEqual(sanitizedPayload(track()).points, [[0, 0.5, 0.5], [10, 0.51, 0.5]]);
});
test("Jména ze soupisu se porovnávají bez realmu a velikosti písmen", () => {
  assert.equal(baseName("Bran-Test"), "bran");
  assert.equal(baseName(" ARIA "), "aria");
});

// --- the real SQL, against SQLite ---
function adapter(db: DatabaseSync): Db {
  const make = (sql: string, params: unknown[] = []): Stmt => ({
    bind: (...values) => make(sql, values),
    all: async <T,>() => ({ results: db.prepare(sql).all(...(params as SQLInputValue[])) as T[] }),
    first: async <T,>() => ((db.prepare(sql).get(...(params as SQLInputValue[])) as T | undefined) ?? null),
    run: async () => ({ meta: { changes: Number(db.prepare(sql).run(...(params as SQLInputValue[])).changes) } }),
  });
  return {
    prepare: (sql) => make(sql),
    batch: async (statements) => { db.exec("BEGIN"); try { const out = []; for (const s of statements) out.push(await s.run()); db.exec("COMMIT"); return out; } catch (error) { db.exec("ROLLBACK"); throw error; } },
  };
}
function fixture() {
  const sql = new DatabaseSync(":memory:");
  for (const name of readdirSync("drizzle").filter((n) => n.endsWith(".sql")).sort()) sql.exec(readFileSync("drizzle/" + name, "utf8"));
  const grant = sql.prepare("INSERT INTO atlas_grants(id,user_id,producer_id,consent_epoch,since,scopes,created_at) VALUES(?,?,?,?,?,?,0)");
  const profile = sql.prepare('INSERT INTO atlas_profiles(id,user_id,producer_id,character_key,name,realm,class_id,level,"public",last_seen) VALUES(?,?,?,?,?,?,?,?,0,?)');
  const people: [string, string, string[]][] = [["gm", "Aria", ["own_track", "guild_share", "own_character"]], ["bob", "Bran", ["own_track", "guild_share", "own_character"]], ["eve", "Eve", ["own_track", "guild_share", "own_character"]]];
  for (const [user, name, scopes] of people) { grant.run("grant-" + user, user, "src-" + user, 1, 0, JSON.stringify(scopes)); profile.run("p-" + user, user, "src-" + user, "k-" + user, name, "Test", 8, 30, t0); }
  return { sql, db: adapter(sql), addTrack };
  function addTrack(user: string, at: number, mapId = 1429, x = 0.4, y = 0.6, grantId = "grant-" + user, n = 1) {
    sql.prepare("INSERT INTO atlas_observations(id,user_id,producer_id,event_id,grant_id,kind,scope,observed_at,profile_id,payload,game,evidence) VALUES(?,?,?,?,?,'track.path','own_track',?,?,?,'{}','api_snapshot')")
      .run(`t-${user}-${at}-${n}`, user, "src-" + user, `e-${user}-${at}-${n}`, grantId, at, "p-" + user, JSON.stringify({ mapId, startedAt: at - 20, points: [[0, 0.1, 0.1], [20, x, y]] }));
  }
}
const snap = (user: string, name: string, extra: Record<string, unknown> = {}, observedAt = t0 + 10) => ({ profileId: "p-" + user, name, realm: "Test", observedAt, guildName: "Dawn", rankIndex: 1, ...extra });
const roster = [{ name: "Aria-Test", rankIndex: 0, level: 30, classId: 8 }, { name: "Bran", rankIndex: 1, level: 25, classId: 3 }];
async function joined() {
  const f = fixture();
  await applyGuildSnapshots(f.db, "bob", [snap("bob", "Bran")]);
  await applyGuildSnapshots(f.db, "gm", [snap("gm", "Aria", { rankIndex: 0, roster })]);
  return f;
}

test("Člen vidí cech až po potvrzení na webu; dřív jen informaci, kdo soupis nahrál", async () => {
  const f = await joined();
  let view = (await guildOverview(f.db, "bob")).guilds[0];
  assert.equal(view.name, "Dawn");
  assert.equal(view.ownerName, "Aria");
  assert.equal(view.members, null);
  assert.equal(view.mine[0].status, "pending");
  assert.equal(view.mine[0].eligible, true);
  await setMembership(f.db, "bob", view.id, "p-bob", "join");
  view = (await guildOverview(f.db, "bob")).guilds[0];
  assert.equal(view.members?.length, 2);
  assert.equal(view.members?.find((m) => m.name === "Bran")?.onMap, true);
  assert.equal(view.members?.find((m) => m.name === "Aria")?.onMap, false);
});
test("Bez nahraného soupisu a pro cizího hráče se do cechu nikdo nepřipojí", async () => {
  const f = fixture();
  await applyGuildSnapshots(f.db, "bob", [snap("bob", "Bran")]);
  const id = (await guildOverview(f.db, "bob")).guilds[0].id;
  await assert.rejects(() => setMembership(f.db, "bob", id, "p-bob", "join"), code("guild_not_verified"));
  await applyGuildSnapshots(f.db, "gm", [snap("gm", "Aria", { rankIndex: 0, roster })]);
  await applyGuildSnapshots(f.db, "eve", [snap("eve", "Eve")]);
  await assert.rejects(() => setMembership(f.db, "eve", id, "p-eve", "join"), code("guild_not_verified"));
  assert.equal((await guildOverview(f.db, "eve")).guilds[0].members, null);
});
test("První guildmaster soupis vlastní; druhý ho nepřepíše", async () => {
  const f = await joined();
  const result = await applyGuildSnapshots(f.db, "eve", [snap("eve", "Eve", { rankIndex: 0, roster: [{ name: "Eve", rankIndex: 0 }] })]);
  assert.equal(result.contested, 1);
  const view = (await guildOverview(f.db, "bob")).guilds[0];
  assert.equal(view.ownerName, "Aria");
  assert.equal(view.rosterSize, 2);
});
test("Poloha je vidět jen když oba potvrdili, člen sdílí a souhlas ještě platí", async () => {
  const f = await joined();
  const id = (await guildOverview(f.db, "bob")).guilds[0].id;
  f.addTrack("bob", t0 + 100, 1429, 0.42, 0.61);
  await setMembership(f.db, "gm", id, "p-gm", "join");
  const asGm = async () => (await guildOverview(f.db, "gm")).guilds[0].members?.find((m) => m.name === "Bran");
  assert.equal((await asGm())?.position, null); // Bob has not confirmed yet.
  await setMembership(f.db, "bob", id, "p-bob", "join");
  assert.deepEqual((await asGm())?.position, { mapId: 1429, x: 0.42, y: 0.61, at: t0 + 100 });
  await setMembership(f.db, "bob", id, "p-bob", "share", "off");
  assert.equal((await asGm())?.position, null);
  await setMembership(f.db, "bob", id, "p-bob", "share", "last");
  f.sql.prepare("UPDATE atlas_grants SET scopes='[\"own_track\",\"own_character\"]' WHERE id='grant-bob'").run();
  assert.equal((await asGm())?.position, null); // guild_share left the grant that holds the route.
  f.sql.prepare("UPDATE atlas_grants SET scopes='[\"own_track\",\"guild_share\",\"own_character\"]',revoked_at=5 WHERE id='grant-bob'").run();
  assert.equal((await asGm())?.position, null);
});
test("Nesdílená trasa cechu: cizinec ani člen s režimem poslední poloha ji nedostane", async () => {
  const f = await joined();
  const id = (await guildOverview(f.db, "bob")).guilds[0].id;
  f.addTrack("bob", t0 + 100);
  await setMembership(f.db, "gm", id, "p-gm", "join");
  await setMembership(f.db, "bob", id, "p-bob", "join");
  await assert.rejects(() => guildTrail(f.db, "gm", id, "p-bob", 24), code("forbidden"));
  await assert.rejects(() => guildTrail(f.db, "eve", id, "p-bob", 24), code("forbidden"));
  await setMembership(f.db, "bob", id, "p-bob", "share", "trail");
  const trail = await guildTrail(f.db, "gm", id, "p-bob", 24);
  assert.equal(trail.name, "Bran");
  assert.equal(trail.paths.length, 1);
  await assert.rejects(() => guildTrail(f.db, "eve", id, "p-bob", 24), code("forbidden"));
});
test("Odchod z cechu ve hře a vyřazení ze soupisu ukončí viditelnost", async () => {
  const f = await joined();
  const id = (await guildOverview(f.db, "bob")).guilds[0].id;
  await setMembership(f.db, "bob", id, "p-bob", "join");
  await setMembership(f.db, "gm", id, "p-gm", "join");
  await applyGuildSnapshots(f.db, "gm", [snap("gm", "Aria", { rankIndex: 0, roster: [{ name: "Aria", rankIndex: 0 }] }, t0 + 50)]);
  assert.equal((await guildOverview(f.db, "bob")).guilds[0].members, null); // Bob is no longer in the imported roster.
  await applyGuildSnapshots(f.db, "bob", [{ profileId: "p-bob", name: "Bran", realm: "Test", observedAt: t0 + 60 }]);
  assert.equal((await guildOverview(f.db, "bob")).guilds.length, 0);
});
test("Starší snímek cech nevrátí zpět a odchod nepřepíše novější stav", async () => {
  const f = await joined();
  await applyGuildSnapshots(f.db, "bob", [{ profileId: "p-bob", name: "Bran", realm: "Test", observedAt: t0 + 60 }]);
  await applyGuildSnapshots(f.db, "bob", [snap("bob", "Bran", {}, t0 + 20)]);
  assert.equal((await guildOverview(f.db, "bob")).guilds.length, 0);
});
test("Vlastní trasa: jen moje, podle postavy a času; smazání odstraní jen mé záznamy", async () => {
  const f = fixture();
  f.addTrack("bob", t0 + 100);
  f.addTrack("gm", t0 + 100);
  f.addTrack("bob", t0 - 5 * 86400, 1429, 0.3, 0.3, "grant-bob", 2);
  const mine = await myTrail(f.db, "bob", { since: t0 - 3600 });
  assert.equal(mine.paths.length, 1);
  assert.equal(mine.paths[0].profileId, "p-bob");
  assert.equal(mine.characters.length, 1);
  assert.equal((await myTrail(f.db, "bob", { since: t0 - 10 * 86400 })).paths.length, 2);
  assert.equal((await myTrail(f.db, "bob", { since: 0, profileId: "p-gm" })).paths.length, 0);
  f.sql.prepare("UPDATE atlas_grants SET revoked_at=1 WHERE id='grant-bob'").run();
  assert.equal((await myTrail(f.db, "bob", { since: 0 })).paths.length, 0);
  f.sql.prepare("UPDATE atlas_grants SET revoked_at=NULL WHERE id='grant-bob'").run();
  assert.deepEqual(await eraseMyTrail(f.db, "bob"), { erased: 2 });
  assert.equal((await myTrail(f.db, "gm", { since: 0 })).paths.length, 1);
});
test("Trasy starší než 30 dní se při nahrání nových zahodí", async () => {
  const f = fixture();
  const old = Math.floor(Date.now() / 1000) - 31 * 86400;
  f.addTrack("bob", old);
  f.addTrack("bob", t0 + 100, 1429, 0.4, 0.4, "grant-bob", 2);
  await pruneTracks(f.db, "bob");
  assert.equal(f.sql.prepare("SELECT COUNT(*) AS n FROM atlas_observations").get()?.n, 1);
});
test("Smazání účtu uvolní cech i členství", async () => {
  const f = await joined();
  const id = (await guildOverview(f.db, "bob")).guilds[0].id;
  await f.db.batch(releaseStatements(f.db, "gm"));
  const view = (await guildOverview(f.db, "bob")).guilds[0];
  assert.equal(view.ownerName, null);
  assert.equal(view.rosterSize, 0);
  await assert.rejects(() => setMembership(f.db, "bob", id, "p-bob", "join"), code("guild_not_verified"));
  assert.equal(f.sql.prepare("SELECT COUNT(*) AS n FROM et_guild_members WHERE user_id='gm'").get()?.n, 0);
});

import test from "node:test";
import assert from "node:assert/strict";
import { exportSchema, scopeFor, type AtlasEvent, type ExportEnvelope } from "../lib/contracts";
import { projectExport } from "../lib/import";
import { sanitizedPayload, validateUpload } from "../lib/policy";
import { armoryOverview, ARMORY_VIEW_DAYS, subjectKey } from "../lib/armory";
import { fixture } from "./sqlite-db";

const t0 = Math.floor(Date.now() / 1000) - 600;
const game = { product: "forever" as const, build: "test", interface: 16001, region: "test", realm: "Test" };
const character = { id: "guid-1", name: "Aria", realm: "Test", classId: 8, raceId: 1, level: 30 };
const base = { schemaVersion: 1 as const, producerId: "source", origin: "local_observation" as const, game, evidence: "api_snapshot" as const, character };
const body = { equipped: [{ slot: 1, itemId: 12640 }], bags: [{ itemId: 2589, count: 20 }], stats: { str: 151, crit: 5.3 }, talents: [{ name: "Fire", spent: 5, ranks: [[100, 5, "Impact"]] }], professions: [{ id: 171, name: "Alchemy", skill: 225, max: 300 }] };
const view = (payload: Record<string, unknown> = {}): AtlasEvent => ({ ...base, eventId: "source:1:1", kind: "armory.view", observedAt: t0 + 100,
  payload: { subject: { name: "Bran", realm: "Test Realm", classId: 7, level: 40 }, mode: "once", kinds: "istp", ...body, ...payload } });
const snapshot = (payload: Record<string, unknown> = {}): AtlasEvent => ({ ...base, eventId: "source:1:2", kind: "armory.snapshot", observedAt: t0 + 100, payload: { ...body, ...payload } });
const envelope = (events: AtlasEvent[], scopes: ExportEnvelope["scopes"] = ["own_character"]): ExportEnvelope => ({ schemaVersion: 1, enabled: true, producerId: "source", consentEpoch: 1, since: t0 - 10, scopes, events });
const ok = (e: AtlasEvent, scopes?: ExportEnvelope["scopes"]) => exportSchema.safeParse(envelope([e], scopes)).success;

// --- contract ---
test("Armory: patří do rozsahu postavy, ne do světových faktů", () => {
  for (const kind of ["armory.snapshot", "armory.view", "armory.revoked"] as const) assert.equal(scopeFor(kind), "own_character");
  assert.throws(() => validateUpload({ producerId: "source", consentEpoch: 1, since: t0 - 10, scopes: ["world_facts"], revokedAt: null }, envelope([view()], ["own_character"])), (e: unknown) => (e as { code?: string }).code === "scope_denied");
});

test("Armory: smlouva přijme celé tělo, prázdné staty z Lua i jméno talentu", () => {
  assert.equal(ok(view()), true);
  assert.equal(ok(snapshot()), true);
  assert.equal(ok(snapshot({ stats: [] })), true, "prázdná Lua tabulka se exportuje jako prázdný seznam");
  assert.equal(ok(snapshot({ talents: [{ name: "Fire", spent: 1, ranks: [[100, 1]] }] })), true, "starší tvar bez jména");
  assert.equal(ok({ ...view(), kind: "armory.revoked", payload: { name: "Bran" } }), true);
});

test("Armory: zlato ani cizí pole nejdou přes smlouvu, a pohled musí říct, kdo to je", () => {
  assert.equal(ok(view({ gold: 123456 })), false, "zlato není součástí armory");
  assert.equal(ok(snapshot({ gold: 1 })), false);
  assert.equal(ok(view({ kinds: "istpgw" })), false, "ani příznak zlata ani webu v uložené kopii");
  assert.equal(ok(view({ subject: { realm: "x" } })), false);
  assert.equal(ok(view({ stats: { secret: 1 } })), false);
  assert.equal(ok(view({ equipped: [{ slot: 20, itemId: 1 }] })), false);
  assert.equal(ok(view({ bags: Array.from({ length: 401 }, (_, i) => ({ itemId: i + 1, count: 1 })) })), false);
});

test("Armory: pohled projde nahráním jen s rozsahem postavy a payload se neořezává", () => {
  const events = [view()];
  assert.deepEqual(projectExport(envelope(events), ["own_character"]).events.map(e => e.kind), ["armory.view"]);
  assert.deepEqual(projectExport(envelope(events), ["world_facts"]).events, [], "bez rozsahu postavy se kopie cizí postavy nenahraje");
  assert.deepEqual((sanitizedPayload(view()) as { subject: { name: string } }).subject.name, "Bran");
});

// --- what the website returns ---
function world() {
  const f = fixture([["me", "Aria"], ["other", "Eve"]]);
  let n = 0;
  const put = (user: string, kind: string, observedAt: number, payload: Record<string, unknown>, profile: string | null = null, grant = "grant-" + user) => {
    n++;
    f.sql.prepare("INSERT INTO atlas_observations(id,user_id,producer_id,event_id,grant_id,kind,scope,observed_at,profile_id,payload,game,evidence) VALUES(?,?,?,?,?,?,'own_character',?,?,?,'{}','api_snapshot')")
      .run(`o${n}`, user, "src-" + user, `e${n}`, grant, kind, observedAt, profile, JSON.stringify(payload));
  };
  return { ...f, put };
}
const viewPayload = (name: string, extra: Record<string, unknown> = {}, realm = "Test Realm") => ({ subject: { name, realm, classId: 7, level: 40 }, mode: "once", kinds: "istp", ...body, ...extra });
const now = Math.floor(Date.now() / 1000);

test("Armory: vlastní postava se vrací jen vlastníkovi a ukazuje se nejnovější snímek", async () => {
  const w = world();
  w.put("me", "armory.snapshot", now - 500, { ...body, stats: { str: 1 } }, "p-me");
  w.put("me", "armory.snapshot", now - 100, { ...body, stats: { str: 2 } }, "p-me");
  w.put("other", "armory.snapshot", now - 100, body, "p-other");
  const mine = await armoryOverview(w.db, "me", now);
  assert.equal(mine.own.length, 1);
  assert.equal(mine.own[0].character.name, "Aria");
  assert.equal(mine.own[0].character.realm, "Test");
  assert.equal(mine.own[0].armory.stats.str, 2);
  assert.deepEqual(mine.viewed, []);
  assert.deepEqual((await armoryOverview(w.db, "stranger", now)).own, [], "cizí účet nevidí nic");
});

test("Armory: pohled na cizí postavu vidí jen ten účet, který ho smí mít, s celým jménem a realmem", async () => {
  const w = world();
  w.put("me", "armory.view", now - 100, viewPayload("Bran"));
  const mine = await armoryOverview(w.db, "me", now);
  assert.equal(mine.viewed.length, 1);
  assert.deepEqual([mine.viewed[0].character.name, mine.viewed[0].character.realm, mine.viewed[0].mode], ["Bran", "Test Realm", "once"]);
  assert.equal(mine.viewed[0].armory.talents[0].ranks[0][2], "Impact");
  assert.deepEqual((await armoryOverview(w.db, "other", now)).viewed, [], "pohled patří účtu, jehož addon se ptal");
});

test("Armory: odvolání skryje pohled hned, nový pohled po odvolání ho vrátí", async () => {
  const w = world();
  w.put("me", "armory.view", now - 300, viewPayload("Bran"));
  w.put("me", "armory.view", now - 300, viewPayload("Cara"));
  w.put("me", "armory.revoked", now - 100, { name: "Bran" });
  assert.deepEqual((await armoryOverview(w.db, "me", now)).viewed.map(v => v.character.name), ["Cara"]);
  w.put("me", "armory.view", now - 50, viewPayload("Bran"));
  assert.deepEqual((await armoryOverview(w.db, "me", now)).viewed.map(v => v.character.name).sort(), ["Bran", "Cara"]);
});

test("Armory: odvolání s realmem platí jen pro tentýž realm, jméno bez realmu pro všechny se stejným jménem", async () => {
  const w = world();
  w.put("me", "armory.view", now - 300, viewPayload("Bran", {}, "Alpha"));
  w.put("me", "armory.view", now - 300, viewPayload("Bran", {}, "Beta"));
  w.put("me", "armory.revoked", now - 100, { name: "bran", realm: "Alpha" });
  assert.deepEqual((await armoryOverview(w.db, "me", now)).viewed.map(v => v.character.realm), ["Beta"]);
  w.put("me", "armory.revoked", now - 90, { name: "Bran" });
  assert.deepEqual((await armoryOverview(w.db, "me", now)).viewed, []);
});

test("Armory: pohled po lhůtě zmizí a nejnovější pohled na hráče nahradí starší", async () => {
  const w = world();
  w.put("me", "armory.view", now - (ARMORY_VIEW_DAYS + 1) * 86400, viewPayload("Old"));
  w.put("me", "armory.view", now - 900, viewPayload("Bran", { stats: { str: 1 } }));
  w.put("me", "armory.view", now - 100, viewPayload("bran", { stats: { str: 9 }, mode: "always" }, "TestRealm"));
  const list = (await armoryOverview(w.db, "me", now)).viewed;
  assert.equal(list.length, 1, "Bran na Test Realm a bran na TestRealm je tentýž hráč");
  assert.deepEqual([list[0].armory.stats.str, list[0].mode], [9, "always"]);
  assert.equal(subjectKey("Bran", "Test Realm"), subjectKey("bran", "TestRealm"));
});

test("Armory: odvolaný souhlas s nahráváním skryje i vlastní armory i pohledy", async () => {
  const w = world();
  w.put("me", "armory.snapshot", now - 100, body, "p-me");
  w.put("me", "armory.view", now - 100, viewPayload("Bran"));
  w.sql.prepare("UPDATE atlas_grants SET revoked_at=? WHERE id='grant-me'").run(now);
  const after = await armoryOverview(w.db, "me", now);
  assert.deepEqual([after.own.length, after.viewed.length], [0, 0]);
});

test("Armory: poškozená data v databázi neshodí stránku", async () => {
  const w = world();
  w.put("me", "armory.view", now - 100, { subject: { name: "Bran" }, mode: "forever" });
  w.put("me", "armory.snapshot", now - 100, { gold: 5 }, "p-me");
  assert.deepEqual(await armoryOverview(w.db, "me", now), { own: [], viewed: [], viewDays: ARMORY_VIEW_DAYS });
});

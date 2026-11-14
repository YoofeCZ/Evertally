import test from "node:test";
import assert from "node:assert/strict";
import { circleAction, circlesOverview, circleTrail, createCircle, joinCircle, formatCode, newInviteCode, normalizeCode, CIRCLE_MAX_MEMBERS } from "../lib/circles";
import { releaseStatements } from "../lib/people";
import { fixture, t0 } from "./sqlite-db";

const code = (expected: string) => (error: unknown) => (error as { code?: string }).code === expected;

test("Kód pozvánky má 10 jednoznačných znaků a normalizuje se z uživatelského zápisu", () => {
  for (let i = 0; i < 200; i++) assert.match(newInviteCode(), /^[A-HJ-KM-NP-Z2-9]{10}$/);
  assert.equal(normalizeCode(" k7qx-4mwd2 "), "K7QX4MWD2");
  assert.equal(formatCode("ABCDEFGHJK"), "ABCDE-FGHJK");
});

async function party() {
  const f = fixture();
  const made = await createCircle(f.db, "gm", { name: "Pátek raid", profileId: "p-gm", share: "trail" });
  await joinCircle(f.db, "bob", made.code, "p-bob", "last");
  return { ...f, id: made.id, code: made.code };
}

test("Skupinu založí jen majitel vlastní postavy; kód vidí jen majitel", async () => {
  const f = fixture();
  await assert.rejects(() => createCircle(f.db, "gm", { name: "X", profileId: "p-bob" }), code("not_found"));
  await assert.rejects(() => createCircle(f.db, "gm", { name: "  ", profileId: "p-gm" }), code("invalid_name"));
  const made = await createCircle(f.db, "gm", { name: "Pátek raid", profileId: "p-gm" });
  await joinCircle(f.db, "bob", made.code, "p-bob");
  const owner = (await circlesOverview(f.db, "gm")).circles[0];
  const member = (await circlesOverview(f.db, "bob")).circles[0];
  assert.equal(owner.inviteCode, formatCode(made.code));
  assert.equal(member.inviteCode, null);
  assert.equal(owner.members.length, 2);
  assert.equal(member.isOwner, false);
  assert.equal((await circlesOverview(f.db, "eve")).circles.length, 0);
});
test("Pozvánka: špatný kód, cizí postava a plná skupina", async () => {
  const f = await party();
  await assert.rejects(() => joinCircle(f.db, "eve", "AAAAAAAAAA", "p-eve"), code("invalid_code"));
  await assert.rejects(() => joinCircle(f.db, "eve", f.code, "p-bob"), code("not_found"));
  for (let i = 0; i < CIRCLE_MAX_MEMBERS; i++) f.sql.prepare("INSERT OR IGNORE INTO et_circle_members(circle_id,user_id,profile_id,share,joined_at) VALUES(?,?,?,?,?)").run(f.id, "filler" + i, "p-filler" + i, "off", 1);
  await assert.rejects(() => joinCircle(f.db, "eve", f.code, "p-eve"), code("circle_full"));
});
test("Polohu člena vidí ostatní jen při sdílení a platném souhlasu; trasu jen při sdílení trasy", async () => {
  const f = await party();
  f.addTrack("gm", t0 + 100, 1429, 0.31, 0.32);
  f.addTrack("bob", t0 + 100, 1429, 0.52, 0.53);
  const at = async (viewer: string, name: string) => (await circlesOverview(f.db, viewer)).circles[0].members.find(m => m.name === name);
  assert.deepEqual((await at("gm", "Bran"))?.position, { mapId: 1429, x: 0.52, y: 0.53, at: t0 + 100 });
  assert.deepEqual((await at("bob", "Aria"))?.position, { mapId: 1429, x: 0.31, y: 0.32, at: t0 + 100 });
  await circleAction(f.db, "bob", f.id, "share", { share: "off" });
  assert.equal((await at("gm", "Bran"))?.position, null);
  await circleAction(f.db, "bob", f.id, "share", { share: "last" });
  f.sql.prepare("UPDATE atlas_grants SET scopes='[\"own_track\"]' WHERE id='grant-bob'").run(); // no character scope any more
  assert.equal((await at("gm", "Bran"))?.position, null);
  f.sql.prepare("UPDATE atlas_grants SET scopes='[\"own_track\",\"own_character\"]',revoked_at=5 WHERE id='grant-bob'").run();
  assert.equal((await at("gm", "Bran"))?.position, null);
  f.sql.prepare("UPDATE atlas_grants SET revoked_at=NULL WHERE id='grant-bob'").run();
  await assert.rejects(() => circleTrail(f.db, "gm", f.id, "p-bob", 24), code("forbidden")); // Bran shares only the last position
  await circleAction(f.db, "bob", f.id, "share", { share: "trail" });
  assert.equal((await circleTrail(f.db, "gm", f.id, "p-bob", 24)).paths.length, 1);
  await assert.rejects(() => circleTrail(f.db, "eve", f.id, "p-bob", 24), code("forbidden")); // not in the group
});
test("Odchod majitele předá skupinu nejdéle přítomnému členovi; poslední odchod ji zavře", async () => {
  const f = await party();
  f.sql.prepare("UPDATE et_circle_members SET joined_at=? WHERE user_id='bob'").run(t0 + 50);
  await circleAction(f.db, "gm", f.id, "leave", {});
  const view = (await circlesOverview(f.db, "bob")).circles[0];
  assert.equal(view.isOwner, true);
  assert.ok(view.inviteCode);
  await circleAction(f.db, "bob", f.id, "leave", {});
  assert.equal((await circlesOverview(f.db, "bob")).circles.length, 0);
  await assert.rejects(() => joinCircle(f.db, "eve", f.code, "p-eve"), code("invalid_code"));
});
test("Majitel otočí kód, vyhodí člena a skupinu zavře; ostatní to nesmí", async () => {
  const f = await party();
  await assert.rejects(() => circleAction(f.db, "bob", f.id, "rotate", {}), code("forbidden"));
  await assert.rejects(() => circleAction(f.db, "bob", f.id, "kick", { target: "p-gm" }), code("forbidden"));
  const rotated = await circleAction(f.db, "gm", f.id, "rotate", {}) as { code: string };
  await assert.rejects(() => joinCircle(f.db, "eve", f.code, "p-eve"), code("invalid_code"));
  await joinCircle(f.db, "eve", rotated.code, "p-eve");
  await assert.rejects(() => circleAction(f.db, "gm", f.id, "kick", { target: "p-gm" }), code("invalid_request"));
  await circleAction(f.db, "gm", f.id, "kick", { target: "p-eve" });
  assert.equal((await circlesOverview(f.db, "eve")).circles.length, 0);
  await circleAction(f.db, "gm", f.id, "close", {});
  assert.equal((await circlesOverview(f.db, "bob")).circles.length, 0);
});
test("Člen si může změnit postavu, jen na vlastní", async () => {
  const f = await party();
  f.sql.prepare('INSERT INTO atlas_profiles(id,user_id,producer_id,character_key,name,realm,class_id,level,"public",last_seen) VALUES(?,?,?,?,?,?,?,?,0,?)').run("p-bob2", "bob", "src-bob", "k-bob2", "Bran Druhý", "Test", 11, 12, t0);
  await circleAction(f.db, "bob", f.id, "character", { profileId: "p-bob2" });
  assert.ok((await circlesOverview(f.db, "gm")).circles[0].members.some(m => m.name === "Bran Druhý"));
  await assert.rejects(() => circleAction(f.db, "bob", f.id, "character", { profileId: "p-gm" }), code("not_found"));
});
test("Smazání účtu odvede z členství a zavře vlastní skupiny", async () => {
  const f = await party();
  await f.db.batch(releaseStatements(f.db, "gm"));
  assert.equal((await circlesOverview(f.db, "bob")).circles.length, 0);
  assert.equal(f.sql.prepare("SELECT COUNT(*) AS n FROM et_circle_members WHERE user_id='gm'").get()?.n, 0);
});

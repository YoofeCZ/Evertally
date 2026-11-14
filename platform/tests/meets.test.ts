import test from "node:test";
import assert from "node:assert/strict";
import { createCircle, joinCircle, circleAction } from "../lib/circles";
import { createMeet, listMeets, meetInput, meetPatch, respondToMeet, updateMeet, MEET_MAX_ACTIVE } from "../lib/meets";
import { applyGuildSnapshots, guildOverview, releaseStatements, setMembership } from "../lib/people";
import { fixture, t0 } from "./sqlite-db";

const code = (expected: string) => (error: unknown) => (error as { code?: string }).code === expected;
const base = { kind: "meet" as const, title: "Sraz u hostince", note: "", mapId: 1429, x: 0.42, y: 0.65, durationMin: 120 };
const input = (audience: unknown, extra: Record<string, unknown> = {}) => meetInput.parse({ ...base, audience, ...extra });
const ids = async (f: ReturnType<typeof fixture>, user: string) => (await listMeets(f.db, user)).meets.map(m => m.title);

async function world() {
  const f = fixture();
  const roster = [{ name: "Aria", rankIndex: 0 }, { name: "Bran", rankIndex: 3 }];
  await applyGuildSnapshots(f.db, "gm", [{ profileId: "p-gm", name: "Aria", realm: "Test", observedAt: t0, guildName: "Dawn", rankIndex: 0, roster }]);
  await applyGuildSnapshots(f.db, "bob", [{ profileId: "p-bob", name: "Bran", realm: "Test", observedAt: t0, guildName: "Dawn", rankIndex: 3 }]);
  const guild = (await guildOverview(f.db, "gm")).guilds[0];
  await setMembership(f.db, "gm", guild.id, "p-gm", "join");
  const circle = await createCircle(f.db, "gm", { name: "Pátek", profileId: "p-gm" });
  return { ...f, guildId: guild.id, circleId: circle.id, circleCode: circle.code };
}

test("Vstup meetu: neznámé pole, souřadnice mimo mapu a příliš mnoho předmětů se odmítnou", () => {
  const ok = (extra: Record<string, unknown>) => meetInput.safeParse({ ...base, audience: { kind: "link" }, ...extra }).success;
  assert.equal(ok({}), true);
  assert.equal(ok({ sneaky: 1 }), false);
  assert.equal(ok({ x: 1.2 }), false);
  assert.equal(ok({ title: "" }), false);
  assert.equal(ok({ capacity: 1 }), false);
  assert.equal(ok({ data: { wanted: Array.from({ length: 13 }, () => ({ item: 1, qty: 1 })) } }), false);
  assert.equal(ok({ data: { wanted: [{ item: 2318, qty: 5 }], offered: [{ item: 2589, qty: 20 }], roles: { tank: 1, healer: 1, dps: 3 }, ref: "deadmines" } }), true);
  assert.equal(meetPatch.safeParse({ cancel: true }).success, true);
  assert.equal(meetPatch.safeParse({ audience: { kind: "link" } }).success, false);
});
test("Cechový meet vidí potvrzení členové cechu, ne nepotvrzení ani cizí", async () => {
  const f = await world();
  await createMeet(f.db, "gm", input({ kind: "guild", id: f.guildId }));
  assert.deepEqual(await ids(f, "gm"), ["Sraz u hostince"]);
  assert.deepEqual(await ids(f, "bob"), []); // in the guild list, but has not confirmed it on the map
  const guild = (await guildOverview(f.db, "bob")).guilds[0];
  await setMembership(f.db, "bob", guild.id, "p-bob", "join");
  assert.deepEqual(await ids(f, "bob"), ["Sraz u hostince"]);
  assert.deepEqual(await ids(f, "eve"), []);
});
test("Meet pro cech ani skupinu nezaloží ten, kdo v ní není", async () => {
  const f = await world();
  await assert.rejects(() => createMeet(f.db, "bob", input({ kind: "guild", id: f.guildId })), code("forbidden"));
  await assert.rejects(() => createMeet(f.db, "eve", input({ kind: "circle", id: f.circleId })), code("forbidden"));
});
test("Meet pro skupinu vidí jen členové; po odchodu zmizí a po návratu se objeví", async () => {
  const f = await world();
  await createMeet(f.db, "gm", input({ kind: "circle", id: f.circleId }, { title: "Farma" }));
  assert.deepEqual(await ids(f, "bob"), []);
  await joinCircle(f.db, "bob", f.circleCode, "p-bob");
  assert.deepEqual(await ids(f, "bob"), ["Farma"]);
  await circleAction(f.db, "bob", f.circleId, "leave", {});
  assert.deepEqual(await ids(f, "bob"), []);
  assert.deepEqual(await ids(f, "eve"), []);
});
test("Kdo odpověděl a pak ze skupiny odešel nebo byl odebrán, meet už nevidí a jeho odpověď zmizí", async () => {
  const f = await world();
  const meet = await createMeet(f.db, "gm", input({ kind: "circle", id: f.circleId }));
  await joinCircle(f.db, "bob", f.circleCode, "p-bob");
  await joinCircle(f.db, "eve", f.circleCode, "p-eve");
  await respondToMeet(f.db, "bob", meet.id, { status: "going" });
  await respondToMeet(f.db, "eve", meet.id, { status: "maybe" });
  await circleAction(f.db, "bob", f.circleId, "leave", {});
  assert.deepEqual(await ids(f, "bob"), []);
  await circleAction(f.db, "gm", f.circleId, "kick", { target: "p-eve" });
  assert.deepEqual(await ids(f, "eve"), []);
  const own = (await listMeets(f.db, "gm")).meets[0];
  assert.equal(own.going, 1);
  assert.equal(own.maybe, 0);
});
test("Meet s odkazem: kdo kód nezná, nevidí; s kódem se přidá do seznamu; špatný kód je chyba", async () => {
  const f = await world();
  const made = await createMeet(f.db, "gm", input({ kind: "link" }, { title: "Veřejný sraz" }));
  assert.match(made.linkCode ?? "", /^[A-HJ-KM-NP-Z2-9]{10}$/);
  assert.deepEqual(await ids(f, "eve"), []);
  await assert.rejects(() => listMeets(f.db, "eve", { code: "AAAAAAAAAA" }), code("invalid_code"));
  assert.deepEqual((await listMeets(f.db, "eve", { code: made.linkCode! })).meets.map(m => [m.title, m.linkCode]), [["Veřejný sraz", null]]);
  assert.deepEqual(await ids(f, "eve"), ["Veřejný sraz"]); // remembered
  assert.equal((await listMeets(f.db, "gm")).meets[0].linkCode, made.linkCode); // only the creator gets the code back
});
test("Odpověď: jdu / možná / nejdu, jméno, kapacita a viditelnost", async () => {
  const f = await world();
  const meet = await createMeet(f.db, "gm", input({ kind: "circle", id: f.circleId }, { capacity: 2, kind: "group", data: { ref: "deadmines", roles: { tank: 1, healer: 1, dps: 3 } } }));
  assert.equal(meet.going, 1);
  await assert.rejects(() => respondToMeet(f.db, "bob", meet.id, { status: "going" }), code("not_found")); // not in the group yet
  await joinCircle(f.db, "bob", f.circleCode, "p-bob");
  const going = await respondToMeet(f.db, "bob", meet.id, { status: "going" });
  assert.equal(going.going, 2);
  assert.equal(going.myRsvp, "going");
  assert.deepEqual(going.rsvps.map(r => r.name).sort(), ["Aria", "Bran"]);
  await joinCircle(f.db, "eve", f.circleCode, "p-eve");
  await assert.rejects(() => respondToMeet(f.db, "eve", meet.id, { status: "going" }), code("meet_full"));
  assert.equal((await respondToMeet(f.db, "eve", meet.id, { status: "maybe", name: "Evička" })).maybe, 1);
  assert.equal((await respondToMeet(f.db, "bob", meet.id, { status: "none" })).going, 1);
  assert.equal((await respondToMeet(f.db, "gm", meet.id, { status: "none" })).going, 1); // the host stays in
  assert.equal((await respondToMeet(f.db, "eve", meet.id, { status: "going" })).going, 2); // room again
});
test("Úprava a zrušení jen autorem; kapacita nejde pod počet přihlášených", async () => {
  const f = await world();
  const meet = await createMeet(f.db, "gm", input({ kind: "circle", id: f.circleId }, { capacity: 5 }));
  await joinCircle(f.db, "bob", f.circleCode, "p-bob");
  await respondToMeet(f.db, "bob", meet.id, { status: "going" });
  await assert.rejects(() => updateMeet(f.db, "bob", meet.id, { title: "Hacknuto" }), code("not_found"));
  await assert.rejects(() => updateMeet(f.db, "gm", meet.id, { capacity: 1 }), code("meet_full")); // two are going already
  const edited = await updateMeet(f.db, "gm", meet.id, { title: "Jinde", x: 0.1, y: 0.2, startsAt: Math.floor(Date.now() / 1000) + 3600, durationMin: 30 });
  assert.equal(edited?.title, "Jinde");
  assert.equal((edited?.endsAt ?? 0) - (edited?.startsAt ?? 0), 1800);
  assert.deepEqual([edited?.x, edited?.y], [0.1, 0.2]);
  assert.equal(await updateMeet(f.db, "gm", meet.id, { cancel: true }), null);
  assert.deepEqual(await ids(f, "gm"), []);
  assert.deepEqual(await ids(f, "bob"), []);
});
test("Skončené meety zmizí; začátek jen v rozumném okně; nejvýš 20 otevřených", async () => {
  const f = await world();
  const now = Math.floor(Date.now() / 1000);
  await assert.rejects(() => createMeet(f.db, "gm", input({ kind: "link" }, { startsAt: now - 7200 })), code("invalid_time"));
  await assert.rejects(() => createMeet(f.db, "gm", input({ kind: "link" }, { startsAt: now + 40 * 86400 })), code("invalid_time"));
  const old = await createMeet(f.db, "gm", input({ kind: "link" }, { title: "Včera" }));
  f.sql.prepare("UPDATE et_meets SET ends_at=? WHERE id=?").run(now - 7200, old.id);
  assert.deepEqual(await ids(f, "gm"), []);
  for (let i = 0; i < MEET_MAX_ACTIVE; i++) await createMeet(f.db, "gm", input({ kind: "link" }, { title: "M" + i }));
  await assert.rejects(() => createMeet(f.db, "gm", input({ kind: "link" })), code("too_many_meets"));
});
test("Meet v budoucnu se ukáže i před začátkem a je seřazený podle času", async () => {
  const f = await world();
  const now = Math.floor(Date.now() / 1000);
  await createMeet(f.db, "gm", input({ kind: "link" }, { title: "Později", startsAt: now + 7200 }));
  await createMeet(f.db, "gm", input({ kind: "link" }, { title: "Brzy", startsAt: now + 600 }));
  assert.deepEqual(await ids(f, "gm"), ["Brzy", "Později"]);
});
test("Smazání účtu odstraní jeho meety a odpovědi", async () => {
  const f = await world();
  const meet = await createMeet(f.db, "gm", input({ kind: "circle", id: f.circleId }));
  await joinCircle(f.db, "bob", f.circleCode, "p-bob");
  await respondToMeet(f.db, "bob", meet.id, { status: "going" });
  await f.db.batch(releaseStatements(f.db, "gm"));
  assert.equal(f.sql.prepare("SELECT COUNT(*) AS n FROM et_meets").get()?.n, 0);
  assert.equal(f.sql.prepare("SELECT COUNT(*) AS n FROM et_meet_rsvps").get()?.n, 0);
});

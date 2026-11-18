import test from "node:test";
import assert from "node:assert/strict";
import { demoChronicle, instances, type Chronicle, type Fight } from "../lib/chronicle";
import { instanceInfo, instanceReport } from "../lib/chronicle-instance";

const me = (): Fight["me"] => ({ dealt: [], healed: [], took: [] });
// Ragefire Chasm as the addon records it: the group on entering, trash, one boss killed, one boss fought and lost, a death
const rfc = (): Chronicle => ({
  v: 1, character: { name: "Holywar", classId: 1, level: 14 }, startedAt: 1000, duration: 900, zones: ["orgrimmar"], path: [],
  events: [
    { t: 10, k: "dungeon", a: "enter", text: "Ragefire Chasm", detail: "Dungeon", id: 389 },
    { t: 40, k: "kill", text: "Ragefire Trogg", xp: 49, f: 0 }, { t: 41, k: "kill", text: "Ragefire Trogg", xp: 49, f: 0 },
    { t: 45, k: "loot", text: "Linen Cloth", n: 2, q: 1 }, { t: 46, k: "money", text: "Money", n: 120 },
    { t: 200, k: "kill", text: "Oggleflint", xp: 120, f: 1 }, { t: 201, k: "loot", text: "Cavedweller Bracers", q: 2, id: 14149 },
    { t: 400, k: "death", text: "You died", f: 2 },
    { t: 800, k: "dungeon", a: "leave", text: "Ragefire Chasm" },
  ],
  fights: [
    { t: 30, d: 12, kind: "combat", name: "Ragefire Trogg", result: "ended", me: me() },
    { t: 170, d: 30, kind: "combat", name: "Oggleflint", result: "ended", me: me() },
    { t: 380, d: 25, kind: "boss", name: "Taragaman the Hungerer", result: "wipe", me: me() },
  ],
  stats: [{ t: 10, roster: [{ name: "Holywar", classId: 1, level: 14, role: "TANK" }, { name: "Perla-Blu", classId: 11, level: 16, role: "HEALER" }, { name: "Jakt-Galen", classId: 3, level: 16, role: "DAMAGER" }] }],
});

test("a visit finds its place in the dungeon journal by map id or by name", () => {
  assert.equal(instanceInfo({ name: "Ragefire Chasm", id: 389 })?.key, "ragefire-chasm");
  assert.equal(instanceInfo({ name: "ragefire chasm" })?.key, "ragefire-chasm");
  assert.equal(instanceInfo({ name: "Somewhere Unknown" }), undefined);
});

test("bosses are apart from the ordinary enemies, each with how it went", () => {
  const c = rfc();
  const r = instanceReport(c, instances(c)[0]);
  assert.deepEqual(r.bosses.map(b => b.name).sort(), ["Bazzalan", "Jergosh the Invoker", "Oggleflint", "Taragaman the Hungerer"]);
  const by = Object.fromEntries(r.bosses.map(b => [b.name, b]));
  assert.equal(by.Oggleflint.status, "killed", "a boss killed in a fight the recorder called an ordinary one");
  assert.deepEqual(by.Oggleflint.fights, [1]);
  assert.equal(by["Taragaman the Hungerer"].status, "wiped");
  assert.equal(by["Taragaman the Hungerer"].wipes, 1);
  assert.equal(by.Bazzalan.status, "unseen", "a boss the recording never met stays not met");
  assert.equal(r.bossKills, 1);
  assert.deepEqual(r.enemies, [{ name: "Ragefire Trogg", count: 2, xp: 98, first: 40, fights: [0] }]);
  assert.deepEqual(r.trash.map(x => x.index), [0], "only the trash fight, the boss fights are with their bosses");
  assert.equal(r.deaths.length, 1);
  assert.equal(r.copper, 120);
  assert.equal(r.xp, 98 + 120);
  assert.equal(r.loot[0].name, "Cavedweller Bracers", "the better items first");
  assert.equal(r.to - r.from, 790);
});

test("the group comes from the roster on entering, the character first, then by role", () => {
  const c = rfc();
  const r = instanceReport(c, instances(c)[0]);
  assert.deepEqual(r.party.map(p => [p.name, p.role, p.me ?? false]), [["Holywar", "tank", true], ["Perla-Blu", "healer", false], ["Jakt-Galen", "dps", false]]);
});

test("the demo's dungeon has a journal entry, a map and its boss kills", () => {
  const c = demoChronicle();
  const bfd = instances(c).find(x => x.name === "Blackfathom Deeps")!;
  const r = instanceReport(c, bfd);
  assert.ok(r.info?.floors?.length, "the floors of the map");
  assert.ok(r.bossKills >= 1);
});

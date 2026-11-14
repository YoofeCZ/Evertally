import test from "node:test";
import assert from "node:assert/strict";
import { rolesFor, specOf } from "../lib/spec";
import { rankPublicLevels, statistics } from "../lib/run-rankings";
import { guildDetail, hallOfFame } from "../lib/guilds";
import { applyPublishChoices } from "../lib/publish";
import { payloadSchemas } from "../lib/contracts";
import { fixture } from "./sqlite-db";

test("the specialisation is the tree with the most points; the role comes from its name, else from its place", () => {
  const resto = specOf([{ name: "Balance", spent: 11 }, { name: "Feral Combat", spent: 0 }, { name: "Restoration", spent: 40 }]);
  assert.deepEqual(resto, { index: 3, name: "Restoration", points: "11/0/40" });
  assert.deepEqual(rolesFor(11, resto), ["healer"]);
  assert.deepEqual(rolesFor(11, { index: 2, name: "Feral Combat" }), ["tank", "dps"], "a feral druid tanks and deals damage");
  // a client in another language: the name is unknown, the place decides (Warrior's third tree is Protection)
  assert.deepEqual(rolesFor(1, { index: 3, name: "Schutz" }), ["tank"]);
  assert.deepEqual(rolesFor(5, specOf([{ name: "Disziplin", spent: 31 }, { name: "Heilig", spent: 20 }, { name: "Schatten", spent: 0 }])), ["healer"]);
  assert.equal(specOf([{ name: "Arms", spent: 0 }]), null, "no points, no specialisation");
  assert.equal(specOf("nonsense"), null);
  assert.deepEqual(specOf([{ name: "Arms", spent: 10 }, { name: "Fury", spent: 10 }])?.name, "Arms", "a tie keeps the first tree");
});

// Ayla (druid, healer) shows gear and talents; Bram (warrior, tank) shows only the item level; Cora (priest) shows nothing.
function world() {
  const f = fixture([["a", "Ayla"], ["b", "Bram"], ["c", "Cora"]]);
  f.sql.exec(`UPDATE atlas_grants SET scopes='["own_track","guild_share","own_character","own_runs"]';
    UPDATE atlas_profiles SET public=1, show_guild=1, level=60, race_id=1, realm='Firemaw';
    UPDATE atlas_profiles SET class_id=11, show_gear=1 WHERE user_id='a';
    UPDATE atlas_profiles SET class_id=1, show_item_level=1, realm='Golemagg' WHERE user_id='b';
    UPDATE atlas_profiles SET class_id=5 WHERE user_id='c';`);
  const observe = f.sql.prepare("INSERT INTO atlas_observations(id,user_id,producer_id,event_id,grant_id,kind,scope,observed_at,profile_id,payload,game,evidence) VALUES(?,?,?,?,?,?,?,?,?,?,'{}','api_snapshot')");
  let n = 0;
  const add = (user: string, kind: string, scope: string, at: number, payload: unknown) => observe.run(`o${++n}`, user, "src-" + user, `e${n}`, "grant-" + user, kind, scope, at, "p-" + user, JSON.stringify(payload));
  const armory = (talents: { name: string; spent: number }[]) => ({ equipped: [], bags: [], stats: {}, talents: talents.map(t => ({ ...t, ranks: [] })), professions: [] });
  add("a", "armory.snapshot", "own_character", 100, armory([{ name: "Balance", spent: 11 }, { name: "Feral Combat", spent: 0 }, { name: "Restoration", spent: 40 }]));
  add("b", "armory.snapshot", "own_character", 100, armory([{ name: "Arms", spent: 5 }, { name: "Fury", spent: 5 }, { name: "Protection", spent: 41 }]));
  add("c", "armory.snapshot", "own_character", 100, armory([{ name: "Discipline", spent: 31 }, { name: "Holy", spent: 20 }, { name: "Shadow", spent: 0 }]));
  const guild = (user: string, name: string) => add(user, "guild.snapshot", "guild_share", 100, { guildName: name, rankIndex: 1 });
  guild("a", "Dawn Watch"); guild("b", "Iron Tusk"); guild("c", "Night Owls");
  const boss = (user: string, at: number, encounterId: number, name: string) => add(user, "raid.encounter_finished", "own_runs", at, { encounterId, name, success: true, instanceId: 409, instanceName: "Molten Core" });
  return { ...f, add, boss };
}

test("the specialisation travels only with gear and talents; the role filter keeps only those who show it", async () => {
  const w = world();
  const board = await rankPublicLevels(w.db, new URLSearchParams());
  const by = new Map(board.entries.map(e => [e.character.name, e]));
  assert.deepEqual([by.get("Ayla")?.spec, by.get("Ayla")?.specPoints, by.get("Ayla")?.roles], ["Restoration", "11/0/40", ["healer"]]);
  assert.equal(by.get("Bram")?.spec, undefined, "the item level switch does not reveal talents");
  assert.equal(by.get("Cora")?.spec, undefined);
  const healers = await rankPublicLevels(w.db, new URLSearchParams({ role: "healer" }));
  assert.deepEqual(healers.entries.map(e => e.character.name), ["Ayla"]);
  assert.equal((await rankPublicLevels(w.db, new URLSearchParams({ role: "tank" }))).total, 0, "Bram tanks, but does not show it");
  const stats = await statistics(w.db, [], new URLSearchParams());
  assert.deepEqual(stats.roles, { tank: 0, healer: 1, dps: 0, unknown: 2 });
});

test("the hall of fame lists the guilds that defeated each boss first, filtered by realm", async () => {
  const w = world();
  w.boss("b", 100, 663, "Lucifron"); w.boss("a", 150, 663, "Lucifron"); w.boss("c", 120, 663, "Lucifron");
  w.boss("a", 300, 664, "Magmadar");
  const fame = await hallOfFame(w.db, [], new URLSearchParams());
  assert.equal(fame.guilds, 3);
  assert.deepEqual(fame.raids.map(r => [r.instanceName, r.bosses.map(b => [b.name, b.firsts.map(f => [f.guild, f.at])])]),
    [["Molten Core", [["Lucifron", [["Iron Tusk", 100], ["Night Owls", 120], ["Dawn Watch", 150]]], ["Magmadar", [["Dawn Watch", 300]]]]]]);
  const firemaw = await hallOfFame(w.db, [], new URLSearchParams({ realm: "Firemaw" }));
  assert.deepEqual(firemaw.raids[0].bosses[0].firsts.map(f => f.guild), ["Night Owls", "Dawn Watch"]);
});

test("a guild knows its place on its own realm", async () => {
  const w = world();
  w.boss("a", 150, 663, "Lucifron");
  const owls = await guildDetail(w.db, [], "Firemaw", "Night Owls");
  assert.deepEqual([owls?.rank, owls?.realmRank, owls?.realmTotal], [3, 2, 2]);
  const dawn = await guildDetail(w.db, [], "Firemaw", "Dawn Watch");
  assert.deepEqual([dawn?.rank, dawn?.realmRank], [1, 1]);
});

test("gear and talents can be chosen in the game as well; an older choice never overrides a newer one", async () => {
  const w = world();
  assert.ok(payloadSchemas["character.publish"].safeParse({ public: true, showGear: true, chosenAt: 10 }).success);
  await applyPublishChoices(w.db, "c", [{ profileId: "p-c", observedAt: 500, public: true, showGear: true }]);
  await applyPublishChoices(w.db, "c", [{ profileId: "p-c", observedAt: 400, public: true, showGear: false }]);
  const row = w.sql.prepare("SELECT show_gear FROM atlas_profiles WHERE id='p-c'").get() as { show_gear: number };
  assert.equal(row.show_gear, 1);
  await applyPublishChoices(w.db, "c", [{ profileId: "p-c", observedAt: 600, public: true }]);
  assert.equal((w.sql.prepare("SELECT show_gear FROM atlas_profiles WHERE id='p-c'").get() as { show_gear: number }).show_gear, 1, "an older addon that does not send it leaves it");
});

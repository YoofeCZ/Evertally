import test from "node:test";
import assert from "node:assert/strict";
import { guildBoard, guildDetail, guildKey, publicBossKills, raidProgress } from "../lib/guilds";
import { fixture } from "./sqlite-db";
import type { Run } from "../components/evertally/types";

// Five players: Ayla and Bram show the guild Dawn Watch, Cora shows Night Owls, Dag is in Dawn Watch but does not show it,
// Eir shows Dawn Watch but her character is private.
function world() {
  const f = fixture([["a", "Ayla"], ["b", "Bram"], ["c", "Cora"], ["d", "Dag"], ["e", "Eir"]]);
  f.sql.exec(`UPDATE atlas_grants SET scopes='["own_track","guild_share","own_character","own_runs"]';
    UPDATE atlas_profiles SET public=1, show_guild=1, level=60, race_id=1;
    UPDATE atlas_profiles SET level=58 WHERE user_id='b';
    UPDATE atlas_profiles SET race_id=2 WHERE user_id='c';
    UPDATE atlas_profiles SET show_guild=0 WHERE user_id='d';
    UPDATE atlas_profiles SET public=0 WHERE user_id='e';`);
  const observe = f.sql.prepare("INSERT INTO atlas_observations(id,user_id,producer_id,event_id,grant_id,kind,scope,observed_at,profile_id,payload,game,evidence) VALUES(?,?,?,?,?,?,?,?,?,?,'{}','api_snapshot')");
  let n = 0;
  const add = (user: string, kind: string, scope: string, at: number, payload: unknown) => observe.run(`o${++n}`, user, "src-" + user, `e${n}`, "grant-" + user, kind, scope, at, "p-" + user, JSON.stringify(payload));
  const guild = (user: string, name: string) => add(user, "guild.snapshot", "guild_share", 100, { guildName: name, rankIndex: 2 });
  const boss = (user: string, at: number, encounterId: number, success = true, instanceName = "Molten Core", instanceId = 409) =>
    add(user, "raid.encounter_finished", "own_runs", at, { encounterId, name: `Boss ${encounterId}`, success, instanceId, instanceName });
  guild("a", "Dawn Watch"); guild("b", "dawn watch"); guild("c", "Night Owls"); guild("d", "Dawn Watch"); guild("e", "Dawn Watch");
  return { ...f, add, boss };
}
const run = (id: string, who: string, at: number, done = true): Run => ({ id, name: "The Deadmines", instanceId: 36, startedAt: at, status: done ? "completed" : "interrupted",
  completion: done ? "last_boss" : undefined, character: { id: "p-" + who } });

test("a guild is made of public characters that show it; private and hidden members never count", async () => {
  const w = world();
  w.boss("a", 200, 663); w.boss("b", 150, 663); w.boss("b", 210, 664); w.boss("b", 220, 665, false);
  w.boss("d", 230, 666);   // Dag kills a boss but does not show the guild
  w.boss("e", 240, 667);   // Eir's character is private
  const board = await guildBoard(w.db, [run("r1", "a", 300), run("r2", "c", 300), run("r3", "c", 310)], new URLSearchParams());
  assert.deepEqual(board.guilds.map(g => [g.rank, g.name, g.members, g.bosses, g.completions]), [[1, "Dawn Watch", 2, 2, 1], [2, "Night Owls", 1, 0, 2]],
    "the same guild in other capitals is one guild; bosses rank before completions; the failed attempt does not count");
  assert.equal(board.sampleSize, 3);
  const dawn = board.guilds[0];
  assert.equal(dawn.faction, "alliance"); assert.equal(dawn.maxLevel, 60); assert.equal(dawn.avgLevel, 59);
  assert.deepEqual(dawn.raids, [{ instanceName: "Molten Core", killed: 2 }]);
});

test("the guild board filters faction and search and ranks after filtering", async () => {
  const w = world();
  w.boss("a", 200, 663);
  const horde = await guildBoard(w.db, [], new URLSearchParams({ faction: "horde" }));
  assert.deepEqual(horde.guilds.map(g => [g.rank, g.name]), [[1, "Night Owls"]]);
  const search = await guildBoard(w.db, [], new URLSearchParams({ q: "owl" }));
  assert.deepEqual(search.guilds.map(g => g.name), ["Night Owls"]);
  assert.equal((await guildBoard(w.db, [], new URLSearchParams({ q: "nobody" }))).total, 0);
});

test("a guild page lists its shown members, raid progress with first kills and their latest runs", async () => {
  const w = world();
  w.boss("a", 200, 663); w.boss("b", 150, 663); w.boss("b", 210, 664);
  const runs = [run("r1", "a", 300), run("r2", "b", 400, false), run("r3", "c", 500), run("r4", "d", 600)];
  const guild = await guildDetail(w.db, runs, "Test", "DAWN WATCH");
  assert.ok(guild);
  assert.equal(guild.rank, 1);
  assert.deepEqual(guild.roster.map(m => [m.character.name, m.character.level, m.completions, m.bosses]), [["Ayla", 60, 1, 1], ["Bram", 58, 0, 2]]);
  assert.deepEqual(guild.progress.map(r => [r.instanceName, r.bosses.map(b => [b.encounterId, b.firstAt, b.kills])]), [["Molten Core", [[663, 150, 2], [664, 210, 1]]]],
    "the earliest first kill of any member, and how many kills");
  assert.deepEqual(guild.recent.map(r => r.id), ["r2", "r1"], "only members' runs, newest first; Dag is not a shown member");
  assert.equal(await guildDetail(w.db, runs, "Test", "Hidden Guild"), null);
});

test("a revoked grant or a character made private removes its boss kills", async () => {
  const w = world();
  w.boss("a", 200, 663); w.boss("b", 210, 664);
  w.sql.exec(`UPDATE atlas_grants SET revoked_at=1 WHERE user_id='a'`);
  w.sql.exec(`UPDATE atlas_profiles SET public=0 WHERE user_id='b'`);
  const kills = await publicBossKills(w.db);
  assert.equal(kills.size, 0);
});

test("raid progress merges characters, keeps the earliest kill and puts the furthest raid first", () => {
  const progress = raidProgress([
    { encounterId: 1, name: "A", instanceId: 1, instanceName: "Onyxia's Lair", firstAt: 50, kills: 1 },
    { encounterId: 2, name: "B", instanceId: 2, instanceName: "Molten Core", firstAt: 90, kills: 1 },
    { encounterId: 3, name: "C", instanceId: 2, instanceName: "Molten Core", firstAt: 80, kills: 2 },
    { encounterId: 2, name: "B", instanceId: 2, instanceName: "Molten Core", firstAt: 70, kills: 1 },
  ]);
  assert.deepEqual(progress.map(r => [r.instanceName, r.bosses.map(b => [b.encounterId, b.firstAt, b.kills])]),
    [["Molten Core", [[2, 70, 2], [3, 80, 2]]], ["Onyxia's Lair", [[1, 50, 1]]]]);
  assert.equal(guildKey("Golem Agg", "Dawn Watch"), guildKey("golemagg", "dawn watch"));
});

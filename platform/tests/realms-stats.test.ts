import test from "node:test";
import assert from "node:assert/strict";
import { rankPublicLevels, realmKey, realmSummary, statistics } from "../lib/run-rankings";
import { guildBoard } from "../lib/guilds";
import { fixture } from "./sqlite-db";
import type { Run } from "../components/evertally/types";

// Four public characters on two realms (one written two ways) and one private character.
function world() {
  const f = fixture([["a", "Ayla"], ["b", "Bram"], ["c", "Cora"], ["d", "Dag"], ["e", "Eir"]]);
  f.sql.exec(`UPDATE atlas_grants SET scopes='["own_track","guild_share","own_character","own_runs"]';
    UPDATE atlas_profiles SET public=1, show_guild=1;
    UPDATE atlas_profiles SET realm='Golem Agg', class_id=1, race_id=1, level=60 WHERE user_id='a';
    UPDATE atlas_profiles SET realm='GolemAgg', class_id=8, race_id=3, level=42 WHERE user_id='b';
    UPDATE atlas_profiles SET realm='Firemaw', class_id=8, race_id=2, level=60 WHERE user_id='c';
    UPDATE atlas_profiles SET realm='Firemaw', class_id=5, race_id=5, level=7 WHERE user_id='d';
    UPDATE atlas_profiles SET realm='Firemaw', class_id=5, race_id=5, level=60, public=0 WHERE user_id='e';`);
  const observe = f.sql.prepare("INSERT INTO atlas_observations(id,user_id,producer_id,event_id,grant_id,kind,scope,observed_at,profile_id,payload,game,evidence) VALUES(?,?,?,?,?,?,?,?,?,?,'{}','api_snapshot')");
  let n = 0;
  for (const [user, guild] of [["a", "Dawn Watch"], ["b", "Dawn Watch"], ["c", "Iron Tusk"], ["d", "Iron Tusk"], ["e", "Iron Tusk"]])
    observe.run(`o${++n}`, user, "src-" + user, `e${n}`, "grant-" + user, "guild.snapshot", "guild_share", 100, "p-" + user, JSON.stringify({ guildName: guild, rankIndex: 1 }));
  return f;
}
const run = (id: string, who: string, classId: number, instanceType: string, raceId = 1): Run => ({ id, name: "X", instanceId: 1, instanceType, status: "completed", completion: "last_boss",
  character: { id: "p-" + who, classId, raceId, realm: who === "a" ? "Golem Agg" : "Firemaw" } });

test("one realm however it is written; the level board and the guild board filter by it", async () => {
  const w = world();
  assert.equal(realmKey("Golem Agg"), realmKey("golem-agg"));
  const golem = await rankPublicLevels(w.db, new URLSearchParams({ realm: "golemagg" }));
  assert.deepEqual(golem.entries.map(e => e.character.name), ["Ayla", "Bram"]);
  const fire = await guildBoard(w.db, [], new URLSearchParams({ realm: "Firemaw" }));
  assert.deepEqual(fire.guilds.map(g => [g.name, g.members]), [["Iron Tusk", 2]], "the private character never counts");
});

test("the realm list counts public characters, the highest level and shown guilds", async () => {
  const { realms } = await realmSummary(world().db);
  assert.deepEqual(realms.map(r => [r.realm, r.characters, r.maxLevel, r.guilds]), [["Firemaw", 2, 60, 1], ["Golem Agg", 2, 60, 1]]);
});

test("statistics count classes, races, factions and level brackets of public characters, and who finishes runs", async () => {
  const w = world();
  const runs = [run("r1", "a", 1, "party"), run("r2", "c", 8, "raid", 2), run("r3", "c", 8, "raid", 2), run("r4", "d", 5, "party", 5)];
  const all = await statistics(w.db, runs, new URLSearchParams());
  assert.equal(all.characters, 4);
  assert.deepEqual(all.classes, [{ id: 8, count: 2 }, { id: 1, count: 1 }, { id: 5, count: 1 }]);
  assert.deepEqual(all.factions, { alliance: 2, horde: 2, unknown: 0 });
  assert.deepEqual(all.levels.filter(b => b.count).map(b => [b.from, b.count]), [[1, 1], [40, 1], [60, 2]]);
  assert.deepEqual(all.runs, { total: 4, party: [{ id: 1, count: 1 }, { id: 5, count: 1 }], raid: [{ id: 8, count: 2 }] });
  const horde = await statistics(w.db, runs, new URLSearchParams({ faction: "horde" }));
  assert.equal(horde.characters, 2);
  assert.deepEqual(horde.runs.raid, [{ id: 8, count: 2 }]);
  assert.deepEqual(horde.runs.party, [{ id: 5, count: 1 }]);
  const golem = await statistics(w.db, runs, new URLSearchParams({ realm: "Golem Agg" }));
  assert.deepEqual([golem.characters, golem.runs.total], [2, 1]);
});

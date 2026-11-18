import test from "node:test";
import assert from "node:assert/strict";
import { publicArmory, publicArmoryList } from "../lib/armory";
import { fixture } from "./sqlite-db";

// Since 2026-11-18 every character is public (lib/publish.ts ALL_PUBLIC): the armory lists them all and opens any of them,
// gear, stats, talents and professions; the bags never leave this way (only by the player's permission in the game).
function world() {
  const f = fixture([["a", "Ayla"], ["b", "Bram"]]);
  f.sql.exec(`UPDATE atlas_profiles SET "public"=1`);
  const snapshot = { equipped: [{ slot: 1, itemId: 100 }], bags: [{ itemId: 200, count: 3 }], stats: { str: 50 }, talents: [], professions: [{ id: 171, skill: 120, max: 150 }] };
  f.sql.prepare("INSERT INTO atlas_observations(id,user_id,producer_id,event_id,grant_id,kind,scope,observed_at,profile_id,payload,game,evidence) VALUES(?,?,?,?,?,'armory.snapshot','own_character',?,?,?,'{}','api_snapshot')")
    .run("arm-a", "a", "src-a", "e-arm-a", "grant-a", 1000, "p-a", JSON.stringify(snapshot));
  return f;
}

test("the public armory lists every character with a snapshot and finds them by name", async () => {
  const f = world();
  const all = await publicArmoryList(f.db);
  assert.deepEqual(all.characters.map(c => c.character.name), ["Ayla"], "Bram has no snapshot yet");
  assert.equal((await publicArmoryList(f.db, "ayl")).characters.length, 1);
  assert.equal((await publicArmoryList(f.db, "zzz")).characters.length, 0);
});

test("one character's public armory has the gear, stats and professions but never the bags", async () => {
  const f = world();
  const entry = await publicArmory(f.db, "p-a");
  assert.ok(entry);
  assert.equal(entry.kind, "public");
  assert.deepEqual(entry.armory.equipped, [{ slot: 1, itemId: 100 }]);
  assert.equal(entry.armory.stats.str, 50);
  assert.equal(entry.armory.professions.length, 1);
  assert.deepEqual(entry.armory.bags, [], "the bags only by permission in the game");
  assert.equal(await publicArmory(f.db, "p-b"), null, "no snapshot, no armory");
});

test("a revoked consent takes the armory away", async () => {
  const f = world();
  f.sql.exec("UPDATE atlas_grants SET revoked_at=5 WHERE id='grant-a'");
  assert.equal(await publicArmory(f.db, "p-a"), null);
  assert.equal((await publicArmoryList(f.db)).characters.length, 0);
});

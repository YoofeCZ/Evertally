import test from "node:test";
import assert from "node:assert/strict";
import { publicGear } from "../lib/public-gear";
import { fixture } from "./sqlite-db";

function world() {
  const f = fixture([["a", "Ayla"], ["b", "Bram"]]);
  const observe = f.sql.prepare("INSERT INTO atlas_observations(id,user_id,producer_id,event_id,grant_id,kind,scope,observed_at,profile_id,payload,game,evidence) VALUES(?,?,?,?,?,?,?,?,?,?,'{}','api_snapshot')");
  let n = 0;
  const add = (user: string, scope: string, at: number, payload: unknown, profile = "p-" + user) =>
    observe.run(`o${++n}`, user, "src-" + user, `e${n}`, "grant-" + user, "armory.snapshot", scope, at, profile, JSON.stringify(payload));
  return { ...f, add };
}
const snapshot = (itemId: number) => ({ equipped: [{ slot: 1, itemId }, { slot: 16, itemId: itemId + 1 }], bags: [{ itemId: 6948, count: 1 }],
  stats: { str: 50 }, talents: [{ name: "Arms", spent: 31, ranks: [[1, 5, "Deflection"]] }], professions: [{ id: 164, name: "Blacksmithing", skill: 300, max: 300 }] });

test("the newest armory snapshot of the character itself: gear, stats and talents, never bags or professions", async () => {
  const w = world();
  w.add("a", "own_character", 100, snapshot(10));
  w.add("a", "own_character", 200, snapshot(20));
  const gear = await publicGear(w.db, "p-a");
  assert.ok(gear);
  assert.equal(gear.observedAt, 200);
  assert.deepEqual(gear.equipped, [{ slot: 1, itemId: 20 }, { slot: 16, itemId: 21 }]);
  assert.deepEqual(gear.stats, { str: 50 });
  assert.equal(gear.talents[0].spent, 31);
  assert.deepEqual(Object.keys(gear).sort(), ["equipped", "observedAt", "stats", "talents"], "no bags, no professions");
});

test("a revoked grant, a grant without the character scope or another character gives nothing", async () => {
  const w = world();
  w.add("a", "own_character", 100, snapshot(10));
  w.add("b", "own_character", 100, snapshot(30));
  w.sql.exec(`UPDATE atlas_grants SET revoked_at=1 WHERE user_id='a'; UPDATE atlas_grants SET scopes='["own_track"]' WHERE user_id='b';`);
  assert.equal(await publicGear(w.db, "p-a"), null);
  assert.equal(await publicGear(w.db, "p-b"), null);
  assert.equal(await publicGear(w.db, "p-nobody"), null);
});

test("the switch is a column of its own and starts off for every character", () => {
  const w = world();
  const rows = w.sql.prepare("SELECT show_gear FROM atlas_profiles").all() as { show_gear: number }[];
  assert.deepEqual(rows.map(r => r.show_gear), [0, 0]);
});

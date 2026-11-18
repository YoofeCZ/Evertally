import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { applyAccountChoice } from "../lib/publish";
import { fixture } from "./sqlite-db";

// One player, two WoW accounts: Dva, Velky and Mar share one addon (src-a); Alt is on the other account (src-b).
function world() {
  const f = fixture([["a", "Dva"]]);
  f.sql.exec(`INSERT INTO atlas_grants(id,user_id,producer_id,consent_epoch,since,scopes,created_at) VALUES('grant-b','a','src-b',1,0,'["own_character"]',0);
    INSERT INTO atlas_profiles(id,user_id,producer_id,character_key,name,realm,class_id,level,"public",last_seen) VALUES
      ('p-velky','a','src-a','k-velky','Velky','Blesky',1,20,0,1),('p-mar','a','src-a','k-mar','Mar','Blesky',8,12,0,1),
      ('p-alt','a','src-b','k-alt','Alt','Blesky',5,9,0,1);`);
  const observe = f.sql.prepare("INSERT INTO atlas_observations(id,user_id,producer_id,event_id,grant_id,kind,scope,observed_at,profile_id,payload,game,evidence) VALUES(?,?,?,?,?,?,?,?,?,?,'{}','api_snapshot')");
  let n = 0;
  const choose = (at: number, payload: Record<string, unknown>, profile = "p-a", producer = "src-a", grant = "grant-a") =>
    observe.run(`c${++n}`, "a", producer, `e${n}`, grant, "character.publish", "own_character", at + 5, profile, JSON.stringify({ chosenAt: at, ...payload }));
  const state = () => Object.fromEntries((f.sql.prepare('SELECT id,"public" AS pub,show_guild,show_gear,visibility_at FROM atlas_profiles ORDER BY id').all() as Record<string, unknown>[])
    .map(r => [String(r.id), [Number(r.pub), Number(r.show_guild), Number(r.show_gear), r.visibility_at]]));
  return { ...f, choose, state };
}




test("the one-off backfill (migration 0012) does what applyAccountChoice does", () => {
  const w = world();
  w.choose(1000, { public: true, showGuild: true });
  w.sql.exec(`UPDATE atlas_profiles SET visibility_at=2000 WHERE id='p-mar';`);
  w.sql.exec(readFileSync("drizzle/0012_publish_whole_account.sql", "utf8"));
  const s = w.state();
  assert.deepEqual([s["p-a"], s["p-velky"], s["p-mar"], s["p-alt"]], [[1, 1, 0, 1000], [1, 1, 0, 1000], [0, 0, 0, 2000], [0, 0, 0, null]]);
  w.sql.exec(readFileSync("drizzle/0012_publish_whole_account.sql", "utf8"));
  assert.deepEqual(w.state()["p-velky"], [1, 1, 0, 1000], "safe to run again");
});

test("the account's choice from the game changes nothing any more: every character is public (2026-11-18)", async () => {
  const w = world();
  w.choose(1000, { public: false });
  assert.equal(await applyAccountChoice(w.db, "a", "src-a"), 0);
});

test("migration 0015 makes every character public with everything shown and every live consent carry every scope", () => {
  const w = world();
  w.sql.exec(readFileSync("drizzle/0015_all_public.sql", "utf8"));
  for (const [id, values] of Object.entries(w.state())) assert.deepEqual(values.slice(0, 3), [1, 1, 1], id);
  const scopes = (w.sql.prepare("SELECT scopes FROM atlas_grants WHERE revoked_at IS NULL").all() as { scopes: string }[]).map(r => JSON.parse(r.scopes));
  for (const list of scopes) assert.ok(list.includes("own_track") && list.includes("own_character"));
});

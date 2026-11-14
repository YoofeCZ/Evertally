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

test("the game's choice reaches every character of that WoW account, not the other account", async () => {
  const w = world();
  w.choose(1000, { public: true, showGuild: true });
  assert.equal(await applyAccountChoice(w.db, "a", "src-a"), 3, "Dva, Velky and Mar");
  const s = w.state();
  for (const id of ["p-a", "p-velky", "p-mar"]) assert.deepEqual(s[id], [1, 1, 0, 1000], id);
  assert.deepEqual(s["p-alt"], [0, 0, 0, null], "another addon (another WoW account) keeps its own choice");
  assert.equal(await applyAccountChoice(w.db, "a", "src-a"), 0, "nothing changes the second time");
});

test("a later choice on the website for one character still wins; an older one does not", async () => {
  const w = world();
  w.sql.exec(`UPDATE atlas_profiles SET visibility_at=2000 WHERE id='p-mar'; UPDATE atlas_profiles SET visibility_at=500, "public"=0 WHERE id='p-velky';`);
  w.choose(1000, { public: true });
  await applyAccountChoice(w.db, "a", "src-a");
  const s = w.state();
  assert.deepEqual(s["p-mar"], [0, 0, 0, 2000], "Mar was made private on the website after the game's choice");
  assert.deepEqual(s["p-velky"], [1, 0, 0, 1000]);
});

test("the newest choice counts, a character seen later inherits it, and a revoked consent applies nothing", async () => {
  const w = world();
  w.choose(1000, { public: true });
  w.choose(3000, { public: false });
  await applyAccountChoice(w.db, "a", "src-a");
  assert.deepEqual(w.state()["p-velky"], [0, 0, 0, 3000]);
  w.choose(4000, { public: true, showGear: true });
  w.sql.exec(`INSERT INTO atlas_profiles(id,user_id,producer_id,character_key,name,realm,class_id,level,"public",last_seen) VALUES('p-new','a','src-a','k-new','Nova','Blesky',11,5,0,1);`);
  await applyAccountChoice(w.db, "a", "src-a");
  assert.deepEqual(w.state()["p-new"], [1, 0, 1, 4000], "a character the website sees for the first time");
  w.choose(5000, { public: true }, "p-alt", "src-b", "grant-b");
  w.sql.exec(`UPDATE atlas_grants SET revoked_at=1 WHERE id='grant-b'`);
  assert.equal(await applyAccountChoice(w.db, "a", "src-b"), 0);
});

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

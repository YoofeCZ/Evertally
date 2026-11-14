import test from "node:test";
import assert from "node:assert/strict";
import { fixture } from "./sqlite-db";
import { ownLast } from "../lib/people";

// An event-based position (zone change, /reload, "Where are you?") instead of a live feed: a free database only takes 100k written rows a day.
test("the last known position of a character is read only for its own account and only while its route consent is live", async () => {
  const { sql, db } = fixture();
  sql.prepare("INSERT INTO et_last_positions(profile_id,user_id,observed_at,map_id,x,y) VALUES(?,?,?,?,?,?)").run("p-gm", "gm", 100, 1429, 0.4, 0.6);
  sql.prepare("INSERT INTO et_last_positions(profile_id,user_id,observed_at,map_id,x,y) VALUES(?,?,?,?,?,?)").run("p-bob", "bob", 200, 1429, 0.1, 0.2);
  const mine = await ownLast(db, "gm");
  assert.equal(mine.length, 1);
  assert.deepEqual({ ...mine[0] }, { profileId: "p-gm", name: "Aria", classId: 8, mapId: 1429, x: 0.4, y: 0.6, at: 100 });
  sql.exec("UPDATE atlas_grants SET revoked_at=300 WHERE user_id='gm'");
  assert.equal((await ownLast(db, "gm")).length, 0);
  sql.exec("UPDATE atlas_grants SET revoked_at=NULL,scopes='[\"own_character\"]' WHERE user_id='gm'");
  assert.equal((await ownLast(db, "gm")).length, 0, "without the route scope no position is shown");
});

test("a request for a position is written at most once per half minute and is cleared by the answer", () => {
  const { sql } = fixture();
  const ask = sql.prepare("INSERT INTO et_locate_requests(user_id,requested_at) VALUES(?,?) ON CONFLICT(user_id) DO UPDATE SET requested_at=excluded.requested_at WHERE excluded.requested_at>=et_locate_requests.requested_at+30");
  ask.run("gm", 1000);
  ask.run("gm", 1010);
  assert.equal(sql.prepare("SELECT requested_at FROM et_locate_requests WHERE user_id='gm'").get()?.requested_at, 1000, "a request 10 s later is not written again");
  ask.run("gm", 1031);
  assert.equal(sql.prepare("SELECT requested_at FROM et_locate_requests WHERE user_id='gm'").get()?.requested_at, 1031);
  sql.prepare("DELETE FROM et_locate_requests WHERE user_id=? AND requested_at<=?").run("gm", 1040);
  assert.equal(sql.prepare("SELECT COUNT(*) AS n FROM et_locate_requests").get()?.n, 0);
});

import { requestLocate } from "../lib/locate";
const code = (expected: string) => (error: unknown) => (error as { code?: string }).code === expected;

test("anyone signed in may ask about a player, but only the player's own sharing choice lets it through", async () => {
  const { sql, db } = fixture();
  const requests = () => sql.prepare("SELECT user_id FROM et_locate_requests ORDER BY user_id").all().map(r => String(r.user_id));
  // bob shares with nobody (no choice stored): nothing is written and the answer does not say whether he exists
  await assert.rejects(() => requestLocate(db, "gm", { profileId: "p-bob" }), code("not_found"));
  await assert.rejects(() => requestLocate(db, "gm", { profileId: "no-such-profile" }), code("not_found"));
  assert.deepEqual(requests(), []);
  // bob shows himself to signed-in visitors: eve may ask, and asking is written once for bob
  sql.prepare("INSERT INTO et_sharing(user_id,friends,signed_in,public,updated_at) VALUES('bob',0,1,0,0)").run();
  assert.deepEqual(await requestLocate(db, "eve", { profileId: "p-bob" }), { requested: true, own: false });
  assert.deepEqual(requests(), ["bob"]);
});

test("a player who shares only with friends is asked only by confirmed friends", async () => {
  const { sql, db } = fixture();
  sql.prepare("INSERT INTO et_sharing(user_id,friends,signed_in,public,updated_at) VALUES('bob',1,0,0,0)").run();
  await assert.rejects(() => requestLocate(db, "eve", { userId: "bob" }), code("not_found"));
  sql.prepare("INSERT INTO et_friends(user_a,user_b,status,requested_by,created_at) VALUES('bob','gm','accepted','gm',0)").run();
  assert.equal((await requestLocate(db, "gm", { userId: "bob" })).requested, true);
});

test("one account may ask about other players once a minute, and about itself always", async () => {
  const { sql, db } = fixture();
  sql.prepare("INSERT INTO et_sharing(user_id,friends,signed_in,public,updated_at) VALUES('bob',0,0,1,0),('eve',0,0,1,0)").run();
  await requestLocate(db, "gm", { profileId: "p-bob" });
  await assert.rejects(() => requestLocate(db, "gm", { profileId: "p-eve" }), code("rate_limited"));
  assert.deepEqual(await requestLocate(db, "gm"), { requested: true, own: true });
  assert.deepEqual(await requestLocate(db, "gm", { profileId: "p-gm" }), { requested: true, own: true }, "own character needs no sharing choice");
});

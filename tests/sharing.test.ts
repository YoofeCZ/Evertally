import test from "node:test";
import assert from "node:assert/strict";
import { answerFriend, getSharing, listFriends, MAX_OUTGOING, pair, requestFriend, setSharing, SHOWN_SECONDS, visiblePlayers } from "../lib/sharing";
import { releaseStatements } from "../lib/people";
import { fixture } from "./sqlite-db";

const code = (expected: string) => (error: unknown) => (error as { code?: string }).code === expected;
const at = Math.floor(Date.now() / 1000);

/** Accounts gm, bob, eve, each with a Discord name, a device and a live position on the same map. */
function world() {
  const f = fixture();
  for (const [user, name] of [["gm", "Aria"], ["bob", "Bran"], ["eve", "Eve"]]) {
    f.sql.prepare("INSERT INTO et_users(id,username,display_name,created_at,last_login_at) VALUES(?,?,?,0,0)").run(user, name.toLowerCase() + "#discord", name);
    f.sql.prepare("INSERT INTO et_devices(id,user_id,name,token_hash,scopes,created_at) VALUES(?,?,?,?,?,0)").run("dev-" + user, user, "PC", "hash-" + user, JSON.stringify(["own_track", "own_character"]));
  }
  const place = (user: string, extra: { observed?: number; expires?: number } = {}) =>
    f.sql.prepare("INSERT OR REPLACE INTO et_live_positions(profile_id,user_id,grant_id,device_id,observed_at,expires_at,map_id,x,y) VALUES(?,?,?,?,?,?,?,?,?)")
      .run("p-" + user, user, "grant-" + user, "dev-" + user, extra.observed ?? at - 2, extra.expires ?? at + 28, 1426, 0.4, 0.6);
  for (const user of ["gm", "bob", "eve"]) place(user);
  return { ...f, place };
}
const names = async (f: ReturnType<typeof world>, viewer: string | null) => (await visiblePlayers(f.db, viewer)).map(p => `${p.name}:${p.audience}`).sort();

test("Viditelnost: výchozí stav je všechno vypnuto a nikdo nic nevidí", async () => {
  const f = world();
  assert.deepEqual(await getSharing(f.db, "gm"), { friends: false, signedIn: false, public: false });
  assert.deepEqual(await names(f, "bob"), []);
  assert.deepEqual(await names(f, null), []);
});

test("Viditelnost: změní se jen to, co přišlo, a vypnutí platí hned", async () => {
  const f = world();
  assert.deepEqual(await setSharing(f.db, "gm", { public: true }), { friends: false, signedIn: false, public: true });
  assert.deepEqual(await setSharing(f.db, "gm", { friends: true }), { friends: true, signedIn: false, public: true });
  assert.deepEqual(await names(f, null), ["Aria:public"]);
  await setSharing(f.db, "gm", { public: false });
  assert.deepEqual(await names(f, null), [], "nepřihlášený už nic nevidí");
});

test("Úplně všem: vidí i nepřihlášený, ale ne vlastní postavy; bez čehokoli dalšího, jen živou polohu", async () => {
  const f = world();
  await setSharing(f.db, "gm", { public: true });
  const anonymous = await visiblePlayers(f.db, null);
  assert.deepEqual(anonymous.map(p => [p.name, p.audience, p.mapId, p.x, p.y]), [["Aria", "public", 1426, 0.4, 0.6]]);
  assert.deepEqual(await names(f, "bob"), ["Aria:public"]);
  assert.deepEqual(await names(f, "gm"), [], "svou vlastní postavu nevidíš jako cizí");
});

test("Všem přihlášeným: nepřihlášený nevidí nic, přihlášený ano", async () => {
  const f = world();
  await setSharing(f.db, "gm", { signedIn: true });
  assert.deepEqual(await names(f, null), []);
  assert.deepEqual(await names(f, "bob"), ["Aria:signed_in"]);
  assert.deepEqual(await names(f, "eve"), ["Aria:signed_in"]);
});

test("Přátelé: jen schválený přítel a jen když to vlastník zapnul", async () => {
  const f = world();
  await setSharing(f.db, "gm", { friends: true });
  assert.deepEqual(await names(f, "bob"), [], "ještě nejsou přátelé");
  assert.deepEqual(await requestFriend(f.db, "bob", "Aria#Discord"), { status: "sent" });
  assert.deepEqual(await names(f, "bob"), [], "čekající žádost nestačí");
  assert.deepEqual(await requestFriend(f.db, "gm", "@bran#discord"), { status: "accepted" }, "dvě žádosti se potkají");
  assert.deepEqual(await names(f, "bob"), ["Aria:friends"]);
  assert.deepEqual(await names(f, "eve"), [], "třetí osoba nic nevidí");
  await setSharing(f.db, "gm", { friends: false });
  assert.deepEqual(await names(f, "bob"), [], "vypnuto: přítel nevidí nic");
});

test("Přátelství je oboustranné: přítel, který polohu nesdílí, nic neukáže, a ten, kdo sdílí, nevidí zpět nic navíc", async () => {
  const f = world();
  await requestFriend(f.db, "bob", "aria#discord");
  await answerFriend(f.db, "gm", "bob", "accept");
  await setSharing(f.db, "gm", { friends: true });
  assert.deepEqual(await names(f, "bob"), ["Aria:friends"]);
  assert.deepEqual(await names(f, "gm"), [], "bob nic nesdílí, takže ho gm nevidí");
});

test("Seznam přátel rozliší nesdílení, přerušený přenos a autorizovanou živou polohu", async () => {
  const f = world();
  await requestFriend(f.db, "bob", "aria#discord");
  await answerFriend(f.db, "gm", "bob", "accept");
  const friend = async () => (await listFriends(f.db, "bob")).friends[0];
  assert.deepEqual(await friend(), { userId: "gm", name: "Aria", since: (await friend()).since, sharing: false, live: false, position: null });
  await setSharing(f.db, "gm", { friends: true });
  const live = await friend();
  assert.equal(live.sharing, true);
  assert.equal(live.live, true);
  assert.deepEqual(live.position, (await visiblePlayers(f.db, "bob")).find(p => p.profileId === "p-gm"));
  assert.equal(live.position?.audience, "friends");
  assert.equal("userId" in live.position!, false, "map position exposes no owner account id");
  f.place("gm", { observed: at - SHOWN_SECONDS - 5, expires: at + 20 });
  assert.deepEqual(await friend(), { userId: "gm", name: "Aria", since: live.since, sharing: true, live: false, position: null });
  f.place("gm");
  f.sql.prepare("UPDATE et_devices SET revoked_at=? WHERE id='dev-gm'").run(at);
  assert.equal((await friend()).position, null);
  assert.equal((await friend()).live, false);
  f.sql.prepare("UPDATE et_devices SET revoked_at=NULL WHERE id='dev-gm'").run();
  f.sql.prepare("UPDATE atlas_grants SET scopes=? WHERE id='grant-gm'").run(JSON.stringify(["own_character"]));
  assert.equal((await friend()).position, null, "a missing route grant blocks the friend list too");
});

test("Žádosti neobsahují stav přenosu a veřejná poloha neobejde vypnuté sdílení přátelům", async () => {
  const f = world();
  await setSharing(f.db, "gm", { friends: true, public: true });
  await requestFriend(f.db, "bob", "aria#discord");
  const pending = (await listFriends(f.db, "bob")).outgoing[0];
  assert.deepEqual(Object.keys(pending).sort(), ["name", "since", "userId"]);
  const incoming = (await listFriends(f.db, "gm")).incoming[0];
  assert.deepEqual(Object.keys(incoming).sort(), ["name", "since", "userId"]);
  await answerFriend(f.db, "gm", "bob", "accept");
  await setSharing(f.db, "gm", { friends: false });
  assert.equal((await visiblePlayers(f.db, "bob"))[0].audience, "public");
  const friend = (await listFriends(f.db, "bob")).friends[0];
  assert.deepEqual([friend.sharing, friend.live, friend.position], [false, false, null]);
});

test("Seznam přátel zvolí nejnovější autorizovanou postavu daného přítele", async () => {
  const f = world();
  await requestFriend(f.db, "bob", "aria#discord");
  await answerFriend(f.db, "gm", "bob", "accept");
  await setSharing(f.db, "gm", { friends: true });
  f.sql.exec(`INSERT INTO atlas_profiles(id,user_id,producer_id,character_key,name,class_id,level,"public",last_seen)
    VALUES('p-alt','gm','src-gm','alt','Alt',1,12,0,0)`);
  f.sql.prepare("INSERT INTO et_live_positions(profile_id,user_id,grant_id,device_id,observed_at,expires_at,map_id,x,y) VALUES('p-alt','gm','grant-gm','dev-gm',?,?,1429,.2,.3)")
    .run(at, at + 30);
  const friend = (await listFriends(f.db, "bob")).friends[0];
  assert.equal(friend.live, true);
  assert.equal(friend.position?.profileId, "p-alt");
  assert.equal(friend.position?.name, "Alt");
});

test("Nejužší důvod je první: přítel je přítel, i když je poloha zároveň veřejná", async () => {
  const f = world();
  await requestFriend(f.db, "bob", "aria#discord");
  await answerFriend(f.db, "gm", "bob", "accept");
  await setSharing(f.db, "gm", { friends: true, signedIn: true, public: true });
  assert.deepEqual(await names(f, "bob"), ["Aria:friends"]);
  assert.deepEqual(await names(f, "eve"), ["Aria:signed_in"]);
  assert.deepEqual(await names(f, null), ["Aria:public"]);
});

test("Poloha, která už neplatí, se nikomu neukáže: stará, prošlá, odvolaný souhlas nebo zařízení", async () => {
  const f = world();
  await setSharing(f.db, "gm", { public: true });
  assert.equal((await visiblePlayers(f.db, null)).length, 1);
  f.place("gm", { observed: at - SHOWN_SECONDS - 5, expires: at + 20 });
  assert.equal((await visiblePlayers(f.db, null)).length, 0, "starší než 30 s");
  f.place("gm", { observed: at - 2, expires: at - 1 });
  assert.equal((await visiblePlayers(f.db, null)).length, 0, "prošlá");
  f.place("gm");
  f.sql.prepare("UPDATE atlas_grants SET revoked_at=? WHERE id='grant-gm'").run(at);
  assert.equal((await visiblePlayers(f.db, null)).length, 0, "souhlas odvolán");
  f.sql.prepare("UPDATE atlas_grants SET revoked_at=NULL WHERE id='grant-gm'").run();
  assert.equal((await visiblePlayers(f.db, null)).length, 1);
  f.sql.prepare("UPDATE et_devices SET revoked_at=? WHERE id='dev-gm'").run(at);
  assert.equal((await visiblePlayers(f.db, null)).length, 0, "zařízení odpojeno");
  f.sql.prepare("UPDATE et_devices SET revoked_at=NULL, scopes=? WHERE id='dev-gm'").run(JSON.stringify(["own_character"]));
  assert.equal((await visiblePlayers(f.db, null)).length, 0, "zařízení nemá oprávnění ke trase");
});

test("Žádosti: neexistující jméno vypadá stejně jako existující, sám sobě nejde, odmítnutí a zrušení fungují", async () => {
  const f = world();
  assert.deepEqual(await requestFriend(f.db, "bob", "nikdo#nikde"), { status: "sent" });
  assert.deepEqual((await listFriends(f.db, "bob")).outgoing, [], "nic se nezapsalo");
  await assert.rejects(() => requestFriend(f.db, "bob", "bran#discord"), code("invalid_name"));
  await assert.rejects(() => requestFriend(f.db, "bob", " "), code("invalid_name"));
  assert.deepEqual(await requestFriend(f.db, "bob", "aria#discord"), { status: "sent" });
  assert.deepEqual(await requestFriend(f.db, "bob", "aria#discord"), { status: "sent" }, "opakovaná žádost nic nenadělá");
  const gm = await listFriends(f.db, "gm");
  assert.deepEqual(gm.incoming.map(e => [e.userId, e.name]), [["bob", "Bran"]]);
  assert.deepEqual((await listFriends(f.db, "bob")).outgoing.map(e => e.userId), ["gm"]);
  await assert.rejects(() => answerFriend(f.db, "bob", "gm", "accept"), code("not_found"), "svou žádost si nepotvrdíš sám");
  await answerFriend(f.db, "bob", "gm", "decline"); // zrušení vlastní žádosti
  assert.deepEqual((await listFriends(f.db, "gm")).incoming, []);
  await requestFriend(f.db, "bob", "aria#discord");
  await answerFriend(f.db, "gm", "bob", "decline");
  assert.deepEqual((await listFriends(f.db, "bob")).outgoing, []);
  await assert.rejects(() => answerFriend(f.db, "gm", "bob", "remove"), code("not_found"), "není co odebírat");
  await requestFriend(f.db, "bob", "aria#discord");
  await answerFriend(f.db, "gm", "bob", "accept");
  assert.deepEqual((await listFriends(f.db, "gm")).friends.map(e => e.name), ["Bran"]);
  assert.deepEqual((await listFriends(f.db, "bob")).friends.map(e => e.name), ["Aria"]);
  await answerFriend(f.db, "bob", "gm", "remove");
  assert.deepEqual((await listFriends(f.db, "gm")).friends, []);
});

test("Žádosti: nejvýš MAX_OUTGOING otevřených", async () => {
  const f = world();
  for (let i = 0; i < MAX_OUTGOING + 2; i++) f.sql.prepare("INSERT INTO et_users(id,username,created_at,last_login_at) VALUES(?,?,0,0)").run("u" + i, "user" + i);
  for (let i = 0; i < MAX_OUTGOING; i++) await requestFriend(f.db, "bob", "user" + i);
  await assert.rejects(() => requestFriend(f.db, "bob", "user" + MAX_OUTGOING), code("too_many_requests"));
});

test("Smazání dat účtu odstraní jeho volby i přátelství; pár je vždy seřazený", async () => {
  const f = world();
  await requestFriend(f.db, "bob", "aria#discord");
  await answerFriend(f.db, "gm", "bob", "accept");
  await setSharing(f.db, "gm", { public: true });
  await f.db.batch(releaseStatements(f.db, "gm"));
  assert.deepEqual(await getSharing(f.db, "gm"), { friends: false, signedIn: false, public: false });
  assert.deepEqual((await listFriends(f.db, "bob")).friends, []);
  assert.deepEqual(pair("b", "a"), ["a", "b"]);
});

import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fixture } from "./sqlite-db";
import { gameConnectionStatements, gameVisiblePlayers, identityToken, rosterKey, tokenRosterKey, type GameConnection, type GameToken } from "../lib/game-connections";
import { setSharing, visiblePlayers } from "../lib/sharing";

const at = Math.floor(Date.now() / 1000);
function world() {
  const f = fixture();
  for (const user of ["gm", "bob", "eve"]) {
    f.sql.prepare("INSERT INTO et_users(id,username,created_at,last_login_at) VALUES(?,?,0,0)").run(user,user);
    f.sql.prepare("INSERT INTO et_devices(id,user_id,name,token_hash,scopes,created_at) VALUES(?,?,?,?,?,0)")
      .run("dev-"+user,user,"test","hash-"+user,JSON.stringify(["own_track","own_character"]));
    f.sql.prepare("INSERT INTO et_live_positions(profile_id,user_id,grant_id,device_id,observed_at,expires_at,map_id,x,y) VALUES(?,?,?,?,?,?,1429,.4,.6)")
      .run("p-"+user,user,"grant-"+user,"dev-"+user,at,at+30);
  }
  const claim = (user:string,entries?:GameConnection[],time=at,region="3",product="forever") => f.db.batch(gameConnectionStatements(f.db,{
    profileId:"p-"+user,userId:user,grantId:"grant-"+user,deviceId:"dev-"+user,observedAt:time,expiresAt:time+30,
    game:{region,product},character:{name:user==="gm"?"Aria":user==="bob"?"Bran":"Eve",realm:"Test"},roster:entries?{key:rosterKey(entries),entries}:undefined,
  }));
  const claimTokens = (user:string,tokens:GameToken[],time=at) => f.db.batch(gameConnectionStatements(f.db,{
    profileId:"p-"+user,userId:user,grantId:"grant-"+user,deviceId:"dev-"+user,observedAt:time,expiresAt:time+30,
    game:{region:"3",product:"forever"},character:{name:user==="gm"?"Aria":user==="bob"?"Bran":"Eve",realm:"Test"},roster:{key:tokenRosterKey(tokens),tokens},
  }));
  return {...f,claim,claimTokens};
}
const bran = (kind:GameConnection["kind"]):GameConnection[] => [{name:"BRAN",realm:" Test ",kind}];
const aria = (kind:GameConnection["kind"]):GameConnection[] => [{name:"Aria",realm:"test",kind}];

test("Herní parta: jednostranné tvrzení nestačí, vzájemná čerstvá sestava funguje bez webové skupiny či přátelství",async()=>{
  const f=world();await f.claim("gm",bran("group"));
  assert.deepEqual(await gameVisiblePlayers(f.db,"gm",at),[]);
  await f.claim("bob",aria("group"));
  const shown=await gameVisiblePlayers(f.db,"gm",at);
  assert.equal(shown.length,1);assert.equal(shown[0].profileId,"p-bob");assert.equal(shown[0].audience,"group");
  assert.equal("userId" in shown[0],false);
  assert.ok((await visiblePlayers(f.db,"gm",at)).some(p=>p.profileId==="p-bob"));
  assert.deepEqual(await visiblePlayers(f.db,null,at),[]);
  assert.deepEqual(await gameVisiblePlayers(f.db,"eve",at),[]);
});

test("Herní přátelé: vzájemné záznamy a souhlas přátelům na obou účtech, bez ručního webového přátelství",async()=>{
  const f=world();await f.claim("gm",bran("friend"));await f.claim("bob",aria("friend"));
  await setSharing(f.db,"gm",{friends:true});
  assert.deepEqual(await gameVisiblePlayers(f.db,"gm",at),[]);
  await setSharing(f.db,"bob",{friends:true});
  assert.equal((await gameVisiblePlayers(f.db,"gm",at))[0].audience,"friends");
  await setSharing(f.db,"gm",{friends:false});
  assert.deepEqual(await gameVisiblePlayers(f.db,"gm",at),[]);
});

test("Herní vztahy nemíchají druh vztahu, realm, produkt ani region",async()=>{
  const f=world();await f.claim("gm",bran("group"));await f.claim("bob",aria("friend"));
  assert.deepEqual(await gameVisiblePlayers(f.db,"gm",at),[]);
  await f.claim("bob",aria("group"),at,"1");assert.deepEqual(await gameVisiblePlayers(f.db,"gm",at),[]);
  await f.claim("bob",aria("group"),at,"3","retail");assert.deepEqual(await gameVisiblePlayers(f.db,"gm",at),[]);
  await f.claim("bob",[{name:"Aria",realm:"Other",kind:"group"}]);assert.deepEqual(await gameVisiblePlayers(f.db,"gm",at),[]);
  await f.claim("bob",aria("group"));assert.equal((await gameVisiblePlayers(f.db,"gm",at)).length,1);
});

test("Expirace, odvolané zařízení i chybějící scope na kterékoli straně ihned ukončí herní viditelnost",async()=>{
  const f=world();await f.claim("gm",bran("group"));await f.claim("bob",aria("group"));
  assert.equal((await gameVisiblePlayers(f.db,"gm",at)).length,1);
  assert.deepEqual(await gameVisiblePlayers(f.db,"gm",at+31),[]);
  for(const user of ["gm","bob"]){
    f.sql.prepare("UPDATE et_devices SET revoked_at=? WHERE user_id=?").run(at,user);
    assert.deepEqual(await gameVisiblePlayers(f.db,"gm",at),[]);
    f.sql.prepare("UPDATE et_devices SET revoked_at=NULL WHERE user_id=?").run(user);
    f.sql.prepare("UPDATE atlas_grants SET scopes=? WHERE user_id=?").run('["own_character"]',user);
    assert.deepEqual(await gameVisiblePlayers(f.db,"gm",at),[]);
    f.sql.prepare("UPDATE atlas_grants SET scopes=? WHERE user_id=?").run('["own_character","own_track"]',user);
  }
});

test("Chybějící nebo prázdná sestava zruší claim, starší paket ho neobnoví",async()=>{
  const f=world();await f.claim("gm",bran("group"));await f.claim("bob",aria("group"));
  await f.claim("gm",undefined,at+1);
  assert.deepEqual(await gameVisiblePlayers(f.db,"gm",at+1),[]);
  await f.claim("gm",bran("group"),at);
  assert.deepEqual(await gameVisiblePlayers(f.db,"gm",at+1),[]);
  await f.claim("gm",bran("group"),at+2);
  assert.equal((await gameVisiblePlayers(f.db,"gm",at+2)).length,1);
  await f.claim("gm",[],at+2);
  assert.deepEqual(await gameVisiblePlayers(f.db,"gm",at+2),[]);
  f.sql.prepare("UPDATE et_live_positions SET observed_at=? WHERE profile_id='p-gm'").run(at+4);
  await f.claim("gm",bran("group"),at+3);
  assert.deepEqual(await gameVisiblePlayers(f.db,"gm",at+4),[],"an older point cannot replace roster state after a newer live point");
});

test("Hash sestavy je kanonický, poškozený hash a cizí profil nelze použít",async()=>{
  const f=world();assert.equal(rosterKey(bran("friend")),rosterKey([{name:"bran",realm:"test",kind:"friend"}]));
  const entries=bran("group");
  const input={profileId:"p-gm",userId:"gm",grantId:"grant-gm",deviceId:"dev-gm",observedAt:at,expiresAt:at+30,game:{product:"forever",region:"3"},character:{name:"Aria",realm:"Test"}};
  assert.throws(()=>gameConnectionStatements(f.db,{...input,roster:{key:rosterKey(entries)^1,entries}}));
  await f.db.batch(gameConnectionStatements(f.db,{...input,profileId:"p-bob",roster:{key:rosterKey(entries),entries}}));
  assert.equal(f.sql.prepare("SELECT COUNT(*) n FROM et_game_connections").get()!.n,0);
});

test("Hash sestavy souhlasí s přímým výstupem Lua včetně mezer v realmu a UTF-8 jména",()=>{
  const snapshot=JSON.parse(readFileSync("../tests/lua/fixtures/game-connections.json","utf8")) as {key:number;entries:GameConnection[]};
  assert.equal(rosterKey(snapshot.entries),snapshot.key);
});

test("Přímé tokeny nové party fungují bez uložených jmen či webové pozvánky a opuštění partu ihned zruší",async()=>{
  const f=world();
  const mine:GameToken[]=[{key:identityToken("BRAN"," Test "),kind:"group"}];
  const theirs:GameToken[]=[{key:identityToken("Aria","test"),kind:"group"}];
  await f.claimTokens("gm",mine);assert.deepEqual(await gameVisiblePlayers(f.db,"gm",at),[]);
  await f.claimTokens("bob",theirs);assert.equal((await gameVisiblePlayers(f.db,"gm",at))[0].profileId,"p-bob");
  const stored=JSON.parse(String(f.sql.prepare("SELECT entries FROM et_game_connections WHERE user_id='gm'").get()!.entries));
  assert.deepEqual(stored,mine);assert.equal("name" in stored[0],false);
  await f.claimTokens("bob",[],at+1);assert.deepEqual(await gameVisiblePlayers(f.db,"gm",at+1),[]);
  await f.claimTokens("bob",theirs,at+2);assert.equal((await gameVisiblePlayers(f.db,"gm",at+2)).length,1);
  f.sql.prepare("UPDATE et_devices SET scopes='[\"own_character\"]' WHERE user_id='bob'").run();
  assert.deepEqual(await gameVisiblePlayers(f.db,"gm",at+2),[]);
});

test("Přímé herní přátelské tokeny vyžadují obě přátelské volby a checksum",async()=>{
  const f=world();await f.claimTokens("gm",[{key:identityToken("Bran","Test"),kind:"friend"}]);
  await f.claimTokens("bob",[{key:identityToken("Aria","Test"),kind:"friend"}]);
  await setSharing(f.db,"gm",{friends:true});assert.deepEqual(await gameVisiblePlayers(f.db,"gm",at),[]);
  await setSharing(f.db,"bob",{friends:true});assert.equal((await gameVisiblePlayers(f.db,"gm",at))[0].audience,"friends");
  await setSharing(f.db,"bob",{friends:false});assert.deepEqual(await gameVisiblePlayers(f.db,"gm",at),[]);
  assert.throws(()=>gameConnectionStatements(f.db,{profileId:"p-gm",userId:"gm",grantId:"grant-gm",deviceId:"dev-gm",observedAt:at,expiresAt:at+30,
    game:{region:"3",product:"forever"},character:{name:"Aria",realm:"Test"},roster:{key:99,tokens:[{key:123,kind:"group"}]}}));
});

test("Nejednoznačný aktivní identity hash skryje polohu, prošlá kolize ji neblokuje",async()=>{
  const f=world();await f.claimTokens("gm",[{key:identityToken("Bran","Test"),kind:"group"}]);
  await f.claimTokens("bob",[{key:identityToken("Aria","Test"),kind:"group"}]);
  await f.claimTokens("eve",[]);
  assert.equal((await gameVisiblePlayers(f.db,"gm",at)).length,1);
  f.sql.prepare("UPDATE et_game_connections SET self_key=? WHERE user_id='eve'").run(identityToken("Bran","Test"));
  assert.deepEqual(await gameVisiblePlayers(f.db,"gm",at),[],"different active characters share the same token");
  f.sql.prepare("UPDATE et_game_connections SET expires_at=? WHERE user_id='eve'").run(at-1);
  assert.equal((await gameVisiblePlayers(f.db,"gm",at)).length,1);
});

test("V4 token hash souhlasí se snapshotem přímo vytvořeným Lua addonem",()=>{
  const snapshot=JSON.parse(readFileSync("../tests/lua/fixtures/game-connections-v4.json","utf8")) as {key:number;tokens:GameToken[]};
  assert.equal(tokenRosterKey(snapshot.tokens),snapshot.key);
});

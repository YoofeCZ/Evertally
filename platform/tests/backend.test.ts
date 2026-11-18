import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync,readdirSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";
import { parseExport,projectExport } from "../lib/import";
import { exportSchema, type AtlasEvent, type ExportEnvelope } from "../lib/contracts";
import { validateUpload,sanitizedPayload } from "../lib/policy";

const quest:AtlasEvent={schemaVersion:1,eventId:"source:1:1",producerId:"source",origin:"local_observation",kind:"quest.turned_in",observedAt:1000,game:{product:"forever",build:"test",interface:16001,region:"test",realm:"test"},character:{id:"own-guid",name:"Hráč",realm:"Test",classId:7,raceId:6,level:20},payload:{questId:182,title:"Trollí jeskyně",xp:100},evidence:"api_event"};
const run:AtlasEvent={...quest,eventId:"source:1:2",kind:"run.finished",payload:{runId:"own-run",instanceId:36,name:"Deadmines",startedAt:500,endedAt:1000,durationMs:500000,status:"completed",completion:"last_boss",rankEligible:true}};
const envelope=(events:AtlasEvent[]=[quest]):ExportEnvelope=>({schemaVersion:1,enabled:true,producerId:"source",consentEpoch:1,since:500,scopes:["world_facts","own_character","own_runs"],events});
const grant={producerId:"source",consentEpoch:1,since:500,scopes:["world_facts","own_character","own_runs"] as const,revokedAt:null};
const policy=()=>({...grant,scopes:[...grant.scopes]});
// Assert on stable API error codes, not on (translatable) messages.
const code=(expected:string)=>(error:unknown)=>(error as {code?:string}).code===expected;
function lua(value:unknown):string{
  if(value===null)return "nil";
  if(Array.isArray(value))return "{"+value.map(lua).join(",")+"}";
  if(typeof value==="object")return "{"+Object.entries(value as object).map(([key,val])=>`[${JSON.stringify(key)}]=${lua(val)}`).join(",")+"}";
  return JSON.stringify(value);
}

test("JSON roundtrip zachová data a UTF-8",()=>assert.deepEqual(parseExport(JSON.stringify(envelope())),envelope()));
test("Kontakty pro živý most se nepřidají do ručního ani komunitního importu",()=>{
  const original=envelope();
  const input={...original,connections:{key:7,entries:[{name:"PrivateFriend",realm:"Realm",kind:"friend"}]}};
  assert.deepEqual(parseExport(JSON.stringify(input)),original);
  assert.equal("connections" in parseExport(JSON.stringify(input)),false);
});
test("Skutečný tvar SavedVariables: indexed arrays, comments, BOM",()=>assert.deepEqual(parseExport("\uFEFF-- snapshot\nEvertallyExportDB = "+lua(envelope())+";\n-- end"),envelope()));
test("Prázdné Lua arrays scopes/events u vypnutého exportu",()=>assert.deepEqual(parseExport('EvertallyExportDB={schemaVersion=1,enabled=false,producerId="source",consentEpoch=0,since=0,scopes={},events={}}'),{schemaVersion:1,enabled:false,producerId:"source",consentEpoch:0,since:0,scopes:[],events:[]}));
test("České UTF-8 decimal byte escape sekvence",()=>{const data=lua(envelope());assert.equal(parseExport('EvertallyExportDB='+data.replace("Trollí","Troll\\195\\173")).events[0].payload.title,"Trollí jeskyně");});
test("Nepovolí Lua funkci nebo výraz",()=>{assert.throws(()=>parseExport('EvertallyExportDB = (function() return {} end)()'));assert.throws(()=>parseExport('EvertallyExportDB = os.execute("test")'));});
test("Nepovolí druhé přiřazení nebo jiný root",()=>{assert.throws(()=>parseExport('OtherDB='+lua(envelope())));assert.throws(()=>parseExport('EvertallyExportDB='+lua(envelope())+'; OtherDB={}'));});
test("Nepovolí duplicitní klíč a díry v poli",()=>{assert.throws(()=>parseExport('EvertallyExportDB={enabled=true,enabled=false}'));assert.throws(()=>parseExport('EvertallyExportDB={events={[2]=1}}'));});
test("Nepovolí prototype-pollution klíče",()=>assert.throws(()=>parseExport('EvertallyExportDB={__proto__={}}')));
test("Poškozený nebo nedopsaný soubor se neimportuje",()=>assert.throws(()=>parseExport('EvertallyExportDB={schemaVersion=1,enabled=true')));
test("Prázdný soubor a nekonečná čísla neprojdou",()=>{assert.throws(()=>parseExport(""));assert.throws(()=>parseExport('EvertallyExportDB={since=1e999}'));});
test("Zpráva od peers se nikdy nepovažuje za own observation",()=>{const bad={...envelope(),events:[{...quest,origin:"peer"}]};assert.equal(exportSchema.safeParse(bad).success,false);});
test("Cizí producerId uvnitř exportu se odmítne",()=>assert.equal(exportSchema.safeParse(envelope([{...quest,producerId:"other"}])).success,false));
test("Neznámá payload pole a spoluhráčská identita se odmítnou",()=>assert.equal(exportSchema.safeParse(envelope([{...run,payload:{...run.payload,players:[{name:"Someone"}]}}])).success,false));
test("Záporná délka a konec před začátkem nejsou platné",()=>{assert.equal(exportSchema.safeParse(envelope([{...run,payload:{...run.payload,durationMs:-1}}])).success,false);assert.equal(exportSchema.safeParse(envelope([{...run,payload:{...run.payload,endedAt:100}}])).success,false);});
test("World facts request bez own_character neobsahuje vlastní identitu",()=>{const clean=projectExport(envelope(),["world_facts"]);assert.equal(clean.events[0].character,undefined);assert.deepEqual(clean.scopes,["world_facts"]);assert.equal(JSON.stringify(clean).includes("Hráč"),false);});
test("Run bez own_character zachová jen pseudonym a class/race/level",()=>{const clean=projectExport(envelope([run]),["own_runs"]);assert.deepEqual(clean.events[0].character,{id:"source:own",classId:7,raceId:6,level:20});assert.doesNotThrow(()=>validateUpload({...policy(),scopes:["own_runs"]},clean));});
test("Frontend projekce neumožní přidat scope, který addon nepovolil",()=>assert.deepEqual(projectExport({...envelope(),scopes:["world_facts"]},["own_character"]).events,[]));
test("Server přijme explicitně povolená vlastní data",()=>assert.deepEqual(validateUpload(policy(),envelope()),envelope()));
test("Server revokaci nebo změněnou epoch vždy odmítne",()=>{assert.throws(()=>validateUpload({...policy(),revokedAt:1001},envelope()),code("consent_revoked"));assert.throws(()=>validateUpload({...policy(),consentEpoch:2},envelope()),code("source_conflict"));});
test("Server odmítne vypnutý export",()=>assert.throws(()=>validateUpload(policy(),{...envelope(),enabled:false,events:[]}),code("export_disabled")));
test("Server nezamění povolení souboru za povolení scope",()=>assert.throws(()=>validateUpload({...policy(),scopes:["world_facts"]},envelope()),code("scope_denied")));
test("Server odmítne nepovolenou identitu už na příjmu",()=>assert.throws(()=>validateUpload({...policy(),scopes:["world_facts"]},{...envelope(),scopes:["world_facts"]}),code("identity_scope_denied")));
test("Souhlas s own_runs neumožní jméno skryté v pseudonymním character",()=>assert.throws(()=>validateUpload({...policy(),scopes:["own_runs"]},{...envelope([run]),scopes:["own_runs"]}),code("identity_scope_denied")));
test("Data před obdobím souhlasu nejsou zpětně schválena",()=>assert.throws(()=>validateUpload({...policy(),since:1001},envelope()),code("scope_denied")));
test("Scope musí odpovídat typu události",()=>assert.throws(()=>validateUpload({...policy(),scopes:["world_facts"]},{...envelope([run]),scopes:["world_facts"]}),code("scope_denied")));
test("Server nikdy nepřevezme klientské tvrzení rankEligible",()=>assert.equal(sanitizedPayload(run).rankEligible,false));
test("Pozorování a počátek souhlasu nemohou ležet daleko v budoucnu",()=>{const future=Math.floor(Date.now()/1000)+1000;assert.equal(exportSchema.safeParse(envelope([{...quest,observedAt:future}])).success,false);assert.equal(exportSchema.safeParse({...envelope([]),since:future}).success,false);});
test("Délka známého běhu musí odpovídat časovým hranicím",()=>assert.equal(exportSchema.safeParse(envelope([{...run,payload:{...run.payload,durationMs:1000}}])).success,false));

// Execute the exact production SQL against SQLite, rather than emulating D1
// with an object map. Root additionally exercises the real D1 HTTP endpoint.
function uploadSql(name:"PROFILE_BATCH_SQL"|"OBSERVATION_BATCH_SQL"){
  const source=readFileSync("lib/store.ts","utf8");
  const found=source.match(new RegExp("export const "+name+" = String\\.raw`([\\s\\S]*?)`;"));
  assert.ok(found,"Production bulk SQL must exist");assert.equal(found[1].includes("${"),false);
  return found[1];
}
function sqliteFixture(){
  const db=new DatabaseSync(":memory:");
  for(const name of readdirSync("drizzle").filter(name=>name.endsWith(".sql")).sort())db.exec(readFileSync("drizzle/"+name,"utf8"));
  db.prepare("INSERT INTO atlas_grants(id,user_id,producer_id,consent_epoch,since,scopes,created_at) VALUES(?,?,?,?,?,?,?)").run("grant","user","source",1,0,'["world_facts","own_character"]',0);
  return db;
}
function rows500(){
  return Array.from({length:500},(_,i)=>({id:"observation-"+i,userId:"user",producerId:"source",eventId:"event-"+i,grantId:"grant",kind:"quest.turned_in",scope:"world_facts",observedAt:1000+i,profileId:"profile",characterData:{id:"own-guid",name:"Hráč",classId:7,raceId:6,level:20},payload:{questId:182,title:"Trollí jeskyně",xp:100},game:{product:"forever",build:"test",interface:16001,region:"test",realm:"test"},evidence:"api_event"}));
}
function profileRows(rows:ReturnType<typeof rows500>){return rows.map(row=>({id:"profile",userId:row.userId,producerId:row.producerId,characterKey:"own-guid",name:"Hráč",realm:"Test",classId:7,raceId:6,level:20,lastSeen:row.observedAt,observationId:row.id}));}
test("500 událostí se uloží dvěma setovými SQL příkazy s pouze 3 parametry každý",()=>{
  const db=sqliteFixture();try{
    const rows=rows500(),profileSql=uploadSql("PROFILE_BATCH_SQL"),observationSql=uploadSql("OBSERVATION_BATCH_SQL");
    assert.equal((profileSql.match(/\?/g)??[]).length,3);assert.equal((observationSql.match(/\?/g)??[]).length,3);
    db.exec("BEGIN");db.prepare(profileSql).run(JSON.stringify(profileRows(rows)),"grant","user");
    const inserted=db.prepare(observationSql).run(JSON.stringify(rows),"grant","user");db.exec("COMMIT");
    assert.equal(Number(inserted.changes),500);assert.equal(db.prepare("SELECT COUNT(*) AS count FROM atlas_observations").get()?.count,500);
    assert.equal(db.prepare("SELECT COUNT(*) AS count FROM atlas_profiles").get()?.count,1);
    const record=db.prepare("SELECT payload,character_data FROM atlas_observations WHERE id='observation-0'").get();
    assert.deepEqual(JSON.parse(String(record?.payload)),rows[0].payload);assert.deepEqual(JSON.parse(String(record?.character_data)),rows[0].characterData);
  }finally{db.close();}
});
test("Opakovaná 500event dávka nepřičítá záznamy ani nemění snapshot přes duplicitní event",()=>{
  const db=sqliteFixture();try{
    const rows=rows500();const p=db.prepare(uploadSql("PROFILE_BATCH_SQL")),o=db.prepare(uploadSql("OBSERVATION_BATCH_SQL"));
    p.run(JSON.stringify(profileRows(rows)),"grant","user");o.run(JSON.stringify(rows),"grant","user");
    p.run(JSON.stringify(profileRows(rows).map(row=>({...row,name:"Podvržená změna"}))),"grant","user");
    assert.equal(Number(o.run(JSON.stringify(rows),"grant","user").changes),0);
    assert.equal(db.prepare("SELECT name FROM atlas_profiles WHERE id='profile'").get()?.name,"Hráč");
    assert.equal(db.prepare("SELECT COUNT(*) AS count FROM atlas_observations").get()?.count,500);
  }finally{db.close();}
});
test("Setové příkazy stále odmítají odvolaný a cizí grant v okamžiku zápisu",()=>{
  const db=sqliteFixture();try{
    const rows=rows500(),p=db.prepare(uploadSql("PROFILE_BATCH_SQL")),o=db.prepare(uploadSql("OBSERVATION_BATCH_SQL"));
    assert.equal(Number(p.run(JSON.stringify(profileRows(rows)),"grant","different-user").changes),0);
    assert.equal(Number(o.run(JSON.stringify(rows),"grant","different-user").changes),0);
    db.prepare("UPDATE atlas_grants SET revoked_at=100 WHERE id='grant'").run();
    assert.equal(Number(p.run(JSON.stringify(profileRows(rows)),"grant","user").changes),0);
    assert.equal(Number(o.run(JSON.stringify(rows),"grant","user").changes),0);
    assert.equal(db.prepare("SELECT COUNT(*) AS count FROM atlas_observations").get()?.count,0);
    assert.equal(db.prepare("SELECT COUNT(*) AS count FROM atlas_profiles").get()?.count,0);
  }finally{db.close();}
});


// --- Accounts and desktop pairing (pure helpers) ---
import { deviceGrantScopes, fromBase64url, base64url, newUserCode, normalizeUserCode, readCookie, safeEqual, safeReturnPath, sanitizeDeviceName, isLoopbackHost } from "../lib/auth-core";
test("Pairing codes are 8 unambiguous characters and normalize from user input", () => {
  for (let i = 0; i < 200; i++) assert.match(newUserCode(), /^[A-HJ-KM-NP-Z2-9]{4}-[A-HJ-KM-NP-Z2-9]{4}$/);
  assert.equal(normalizeUserCode(" abcd-efgh "), "ABCD-EFGH");
  assert.equal(normalizeUserCode("abcdefgh"), "ABCD-EFGH");
  assert.equal(normalizeUserCode("ABCD-EFG0"), null);
  assert.equal(normalizeUserCode("ABC"), null);
});
test("Login return path never leaves the site or re-enters auth routes", () => {
  assert.equal(safeReturnPath("/link?code=ABCD-EFGH"), "/link?code=ABCD-EFGH");
  for (const bad of ["https://evil.example/", "//evil.example", "/\\evil.example", "/auth/discord", "javascript:alert(1)", null]) assert.equal(safeReturnPath(bad), "/");
});
test("Cookie parsing picks the exact cookie name", () => {
  assert.equal(readCookie("a=1; et_session=abc; et_session_x=2", "et_session"), "abc");
  assert.equal(readCookie("xet_session=abc", "et_session"), null);
  assert.equal(readCookie(null, "et_session"), null);
});
test("A device sends what the addon export carries: the pairing no longer narrows it (everything is public, 2026-11-18)", () => {
  assert.deepEqual(deviceGrantScopes(["world_facts", "own_runs"], ["own_runs", "own_character"]), ["own_runs", "own_character"]);
  assert.deepEqual(deviceGrantScopes(["own_character"], ["world_facts"]), ["world_facts"]);
  assert.deepEqual(deviceGrantScopes(["own_character"], []), []);
});
test("Device names are trimmed, stripped of control characters and capped", () => {
  assert.equal(sanitizeDeviceName("  PC\u0000-\u001fHERO  "), "PC-HERO");
  assert.equal(sanitizeDeviceName(""), "Evertally Sync");
  assert.equal(sanitizeDeviceName(42), "Evertally Sync");
  assert.equal(sanitizeDeviceName("x".repeat(500)).length, 60);
});
test("Helpers: constant-time compare, base64url roundtrip, loopback detection", () => {
  assert.ok(safeEqual("abc", "abc"));
  assert.ok(!safeEqual("abc", "abd"));
  assert.ok(!safeEqual("abc", "abcd"));
  assert.equal(fromBase64url(base64url(new TextEncoder().encode("/link?code=Ž"))), "/link?code=Ž");
  assert.ok(isLoopbackHost("127.0.0.1") && isLoopbackHost("localhost") && !isLoopbackHost("evertally.gg"));
});

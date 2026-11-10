import test from "node:test";
import assert from "node:assert/strict";
import {worldPayload} from "../lib/world-privacy";
import {atlasEntities} from "../lib/atlas";
import {activitySnapshot} from "../lib/activity";
import {ACTIVITY_SQL} from "../lib/activity";
import {DatabaseSync} from "node:sqlite";
import {payloadSchemas} from "../lib/contracts";
import {PUBLIC_PROFILE_ACCESS_SQL} from "../lib/profiles";
test("Player interaction coordinates are removed, NPC unit positions remain world facts",()=>{
 for(const kind of ["quest.accepted","vendor.snapshot","loot.received","zone.visited","npc.observed"]){const raw={mapId:1426,x:.4,y:.7,z:10,positionMethod:"player_interaction"};const clean=worldPayload(kind,raw);assert.equal(clean.x,undefined);assert.equal(clean.y,undefined);assert.equal(raw.x,.4)}
 assert.equal(worldPayload("npc.observed",{x:.4,y:.7,positionMethod:"unit_position"}).x,.4);
});
test("Zone activity SQL counts distinct consenting accounts and suppresses small or revoked groups",()=>{
 const db=new DatabaseSync(":memory:");db.exec("CREATE TABLE atlas_observations(id TEXT,user_id TEXT,producer_id TEXT,grant_id TEXT,kind TEXT,scope TEXT,observed_at INTEGER,payload TEXT);CREATE TABLE atlas_grants(id TEXT,user_id TEXT,producer_id TEXT,revoked_at INTEGER,scopes TEXT)");
 for(let i=0;i<3;i++){db.prepare("INSERT INTO atlas_grants VALUES(?,?,?,NULL,?)").run('g'+i,'u'+i,'p'+i,JSON.stringify(['world_facts']));db.prepare("INSERT INTO atlas_observations VALUES(?,?,?,?,?,?,?,?)").run('o'+i,'u'+i,'p'+i,'g'+i,'zone.visited','world_facts',100000,JSON.stringify({mapId:1426,mapSystem:'ui_map',name:'Never copied'}));}
 assert.equal(db.prepare(ACTIVITY_SQL).all(90000,100100).length,1);
 db.exec("UPDATE atlas_grants SET revoked_at=100001 WHERE id='g2'");assert.equal(db.prepare(ACTIVITY_SQL).all(90000,100100).length,0);db.close();
});
test("Atlas retains multiple NPC world positions while historical interaction locations stay zone-only",()=>{
 const row=(payload:Record<string,unknown>,at:number)=>({kind:"npc.observed",payload:JSON.stringify({npcId:706,name:"Troll",...payload}),observed_at:at});
 const result=atlasEntities([row({mapId:1426,x:.4,y:.7,positionMethod:"player_interaction"},100000),row({mapId:1426,x:.2,y:.3,positionMethod:"unit_position"},99900),row({mapId:1426,x:.25,y:.35,positionMethod:"unit_position"},99800)]);
 assert.equal(result[0].count,3);assert.equal(result[0].payload.x,undefined);assert.equal(result[0].locations.length,3);assert.equal(result[0].locations[0].x,undefined);assert.equal(result[0].locations[1].x,.2);assert.equal(result[0].lastSeen,86400);
});
test("Visited-zone schema rejects exact positions and activity output exposes thresholded anonymous zone totals only",()=>{
 assert.equal(payloadSchemas["zone.visited"].safeParse({mapId:1426,mapSystem:"ui_map",x:.4,y:.7}).success,false);
 const value=activitySnapshot([{mapId:1426,contributors:2,observations:5,lastSeen:100000},{mapId:1411,contributors:3,observations:7,lastSeen:100000,userId:"private",x:.5,y:.5}],100000);
 assert.equal(value.zones.length,1);assert.deepEqual(value.zones[0],{mapId:1411,mapSystem:"ui_map",contributors:3,observations:7,lastSeen:86400});assert.equal(JSON.stringify(value).includes("private"),false);
});
test("Published profile identity is unavailable after its only character grant is revoked",()=>{
 const db=new DatabaseSync(":memory:");db.exec("CREATE TABLE atlas_observations(profile_id TEXT,user_id TEXT,producer_id TEXT,grant_id TEXT,scope TEXT);CREATE TABLE atlas_grants(id TEXT,user_id TEXT,producer_id TEXT,revoked_at INTEGER,scopes TEXT)");
 db.prepare("INSERT INTO atlas_grants VALUES('g','u','p',NULL,?)").run(JSON.stringify(['world_facts','own_character']));
 db.exec("INSERT INTO atlas_observations VALUES('profile','u','p','g','world_facts')");
 assert.equal(db.prepare(PUBLIC_PROFILE_ACCESS_SQL).all('profile').length,1);
 db.exec("UPDATE atlas_grants SET revoked_at=1");assert.equal(db.prepare(PUBLIC_PROFILE_ACCESS_SQL).all('profile').length,0);
 db.exec("UPDATE atlas_grants SET revoked_at=NULL,scopes='[\"world_facts\"]'");assert.equal(db.prepare(PUBLIC_PROFILE_ACCESS_SQL).all('profile').length,0);db.close();
});

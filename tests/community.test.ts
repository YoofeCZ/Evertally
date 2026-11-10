import test from "node:test";
import assert from "node:assert/strict";
import {DatabaseSync} from "node:sqlite";
import {buildCommunitySnapshot,COMMUNITY_OBSERVATIONS_SQL,COMMUNITY_MAX_BYTES} from "../lib/community";
const now=1794236400;
const row=(id=1)=>({kind:"npc.observed",payload:JSON.stringify({npcId:id,name:"Trollí jeskyně",mapId:1,x:.4,y:.5,positionMethod:"player_interaction",character:"PRIVATE"}),observed_at:now-1,game:JSON.stringify({product:"forever",realm:"PRIVATE"})});
test("Community projection is anonymous, UTF-8 safe and distinguishes interaction from unit position",()=>{
 const snapshot=buildCommunitySnapshot([row()],now);
 assert.equal(snapshot.entities[0].name,"Trollí jeskyně");assert.equal(snapshot.entities[0].x,undefined);
 assert.ok(!JSON.stringify(snapshot).includes("PRIVATE"));assert.equal(snapshot.provenance.observationCount,1);
 const exact=buildCommunitySnapshot([{...row(),payload:{npcId:1,name:"NPC",mapId:1,x:.4,y:.5,positionMethod:"unit_position"}}],now);
 assert.equal(exact.entities[0].x,.4);
});
test("Community output obeys both entity and UTF-8 byte budgets, with explicit truncation",()=>{
 const snapshot=buildCommunitySnapshot(Array.from({length:500},(_,i)=>({...row(i+1),payload:{npcId:i+1,name:"ě".repeat(200)}})),now);
 assert.equal(snapshot.entities.length,150);assert.equal(snapshot.provenance.entityCount,500);assert.equal(snapshot.provenance.truncated,true);
 assert.ok(Buffer.byteLength(JSON.stringify(snapshot))<=COMMUNITY_MAX_BYTES);
 assert.ok(snapshot.entities.every(e=>Buffer.byteLength(e.name)<=160&&!e.name.includes("\uFFFD")));
});
test("Community rejects unsupported rows, removes game markup and counts repeated observations once per row",()=>{
 const r={...row(),payload:{npcId:1,name:"|Hbad\u0000name"}};
 const s=buildCommunitySnapshot([r,r,{...row(2),game:{product:"retail"}}],now);
 assert.equal(s.entities.length,1);assert.equal(s.entities[0].count,2);assert.ok(!/[|\u0000]/.test(s.entities[0].name));
 assert.equal(s.expiresAt-s.generatedAt,604800);
});
test("Community SQL excludes revoked, foreign and ungranted world facts",()=>{
 const db=new DatabaseSync(":memory:");
 db.exec("CREATE TABLE atlas_grants(id TEXT,user_id TEXT,producer_id TEXT,scopes TEXT,revoked_at INTEGER);CREATE TABLE atlas_observations(id TEXT,grant_id TEXT,user_id TEXT,producer_id TEXT,scope TEXT,kind TEXT,payload TEXT,game TEXT,observed_at INTEGER)");
 const g=db.prepare("INSERT INTO atlas_grants VALUES(?,?,?,?,?)"),o=db.prepare("INSERT INTO atlas_observations VALUES(?,?,?,?,?,?,?,?,?)");
 for(const [id,scopes,revoked] of [["good",'["world_facts"]',null],["revoked",'["world_facts"]',1],["private",'["own_runs"]',null]] as const)g.run(id,"u","p",scopes,revoked);
 for(const [id,grant,user] of [["a","good","u"],["b","revoked","u"],["c","private","u"],["d","good","stranger"]])o.run(id,grant,user,"p","world_facts","npc.observed","{}","{}",now);
 assert.equal(db.prepare(COMMUNITY_OBSERVATIONS_SQL).all().length,1);db.close();
});

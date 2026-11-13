import test from "node:test";
import assert from "node:assert/strict";
import {eventSchema, type AtlasEvent, type ExportEnvelope} from "../lib/contracts";
import {projectExport} from "../lib/import";
import {validateUpload} from "../lib/policy";
import {projectRunActors} from "../lib/run-combat";
import {rankObservedRuns} from "../lib/run-rankings";
import {observedCombatRate,combatDisplayRows} from "../components/evertally/Details";
import type {Run,RunCombat} from "../components/evertally/types";

const combat:RunCombat={source:"damage_meter",coverage:"observed",coveredMs:120000,activeMs:10000,damage:6000,healing:800,players:[
  {guid:"own",name:"Owner",classId:11,raceId:4,damage:1000,healing:0,activeMs:10000},
  {guid:"other",name:"Healer",classId:5,raceId:1,damage:5000,healing:800,activeMs:10000}]};
const event:AtlasEvent={schemaVersion:1,eventId:"source:1:1",producerId:"source",origin:"local_observation",kind:"run.finished",observedAt:1000,
  game:{product:"forever",build:"test",interface:16001,region:"3",realm:"Test"},character:{id:"own",name:"Owner",classId:11,raceId:4},evidence:"api_event",
  payload:{runId:"run",instanceId:36,name:"Deadmines",instanceType:"party",startedAt:880,endedAt:1000,durationMs:120000,status:"completed",completion:"last_boss",
    combat,roster:combat.players.map(({guid,name,classId,raceId})=>({guid,name,classId,raceId})),bosses:[{encounterId:639,name:"VanCleef",durationMs:12000,splitMs:120000,killedAt:1000}]}};
const envelope:ExportEnvelope={schemaVersion:1,enabled:true,producerId:"source",consentEpoch:1,since:0,scopes:["own_runs","own_character"],events:[event]};

test("new combat/roster/boss payload is additive and old runs remain valid",()=>{
  assert.equal(eventSchema.safeParse(event).success,true);
  const legacy={...event.payload};delete legacy.combat;delete legacy.roster;
  assert.equal(eventSchema.safeParse({...event,payload:legacy}).success,true);
});
test("negative combat, invalid actors and unbounded rosters are rejected",()=>{
  assert.equal(eventSchema.safeParse({...event,payload:{...event.payload,combat:{...combat,damage:-1}}}).success,false);
  assert.equal(eventSchema.safeParse({...event,payload:{...event.payload,combat:{...combat,players:[{guid:"",damage:1}]}}}).success,false);
  assert.equal(eventSchema.safeParse({...event,payload:{...event.payload,roster:Array(81).fill({guid:"actor"})}}).success,false);
});
test("private projection removes roster and names and only retains pseudonymous owner metrics",()=>{
  const projected=projectExport(envelope,["own_runs"]);
  assert.equal(projected.events[0].payload.roster,undefined);
  const c=projected.events[0].payload.combat as RunCombat;
  assert.deepEqual(c.players,[{guid:"source:own",classId:11,raceId:4,damage:1000,healing:0,activeMs:10000}]);
  assert.doesNotThrow(()=>validateUpload({producerId:"source",consentEpoch:1,since:0,scopes:["own_runs"],revokedAt:null},projected));
  assert.throws(()=>validateUpload({producerId:"source",consentEpoch:1,since:0,scopes:["own_runs"],revokedAt:null},{...projected,events:[{...projected.events[0],payload:{...projected.events[0].payload,roster:[{guid:"other",name:"Leak"}]}}]}));
});
test("public run participants map the owner to the profile and exclude other identities",()=>{
  const projected=projectRunActors(combat,combat.players,"own","public-profile",false);
  assert.equal(projected.roster.length,0);
  assert.deepEqual(projected.combat?.players.map(p=>p.guid),["public-profile"]);
  assert.equal(projectRunActors(combat,combat.players,"own","public-profile",true).combat?.players.length,2);
});
test("missing and partial measurements stay unknown; measured zero is zero",()=>{
  assert.equal(observedCombatRate(combat,0),0);
  assert.equal(observedCombatRate(combat,undefined),null);
  assert.equal(observedCombatRate({...combat,coverage:"partial"},1000),null);
  assert.equal(combatDisplayRows({id:"r",name:"r",roster:[{guid:"missing",name:"Unmeasured"}],combat})[0].damage,undefined);
});
test("leaderboards filter instance/category/class/race and attribute DPS to owner, not group",()=>{
  const run:Run={id:"r",name:"Deadmines",instanceId:36,instanceType:"party",status:"completed",completion:"last_boss",evidence:"api_event",durationMs:120000,character:{id:"own",name:"Owner",classId:11,raceId:4},combat};
  const params=new URLSearchParams({metric:"dps",instanceId:"36",instanceType:"party",classId:"11",raceId:"4"});
  assert.equal(rankObservedRuns([run],params).entries[0].value,100);
  assert.equal(rankObservedRuns([{...run,combat:{...combat,coverage:"partial"}}],params).entries.length,0);
  params.set("instanceType","raid");assert.equal(rankObservedRuns([run],params).entries.length,0);
  params.set("instanceType","party");params.delete("instanceId");assert.equal(rankObservedRuns([run],params).entries.length,0);
});

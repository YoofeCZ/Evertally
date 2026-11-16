import test from "node:test";
import assert from "node:assert/strict";
import { composeChronicle, myChronicle, type Observation } from "../lib/chronicle-build";
import { parseChronicle, statsAt, fightProgress, fightAt, instances, instanceAt, instanceSummary, typeKey, type Chronicle } from "../lib/chronicle";
import { eventSchema, type ExportEnvelope } from "../lib/contracts";
import { projectExport } from "../lib/import";
import { validateUpload } from "../lib/policy";
import { fixture } from "./sqlite-db";

const AT = 1_794_300_000;
const subject = { id:"own", name:"Aria", realm:"Forever", classId:11, level:12 };
const maps = [{key:"mulgore",uiMapIds:[1412]}];
const ob = (kind:string, at:number, payload:Record<string,unknown>):Observation => ({kind,observedAt:at,payload});
const chunk = (startedAt:number, events:Record<string,unknown>[]) => ob("journey.chunk",startedAt+100,{startedAt,events});
const summary = {source:"damage_meter",coverage:"partial",coveredMs:20000,activeMs:20000,players:[
  {guid:"own",name:"Aria",classId:11,damage:48,damageTaken:12,dealt:[{id:6603,name:"Attack",total:48}]},
  {guid:"friend",name:"A friend",classId:5,healing:24},
]};
const envelope = (events:Record<string,unknown>[]):ExportEnvelope => ({schemaVersion:1,enabled:true,producerId:"source",consentEpoch:1,since:0,scopes:["own_track","own_character"],events:[{
  schemaVersion:1,eventId:"source:s:1",producerId:"source",origin:"local_observation",kind:"journey.chunk",observedAt:AT+100,game:{product:"forever",build:"test",interface:16001,region:"3",realm:"Test"},character:{id:"own",name:"Aria"},evidence:"api_snapshot",payload:{startedAt:AT,events},
}]});

test("ordinary combat spans batches, links observed own actions and retains missing meter values",()=>{
  const c = composeChronicle(subject,[
    chunk(AT,[{t:0,k:"combat",a:"start",fightId:"f1",text:"Plainstrider",encounterKind:"combat",mapId:1412,x:.4,y:.5},
      {t:3,k:"action",a:"cast",id:78,text:"Heroic Strike",fightId:"f1"}]),
    chunk(AT+10,[{t:4,k:"action",a:"jump",text:"Jumped",fightId:"f1"},{t:10,k:"combat",a:"end",fightId:"f1",text:"Plainstrider",encounterKind:"combat",d:20,result:"kill",summary}]),
  ],maps)!;
  assert.ok(parseChronicle(c));
  assert.equal(c.fights?.length,1);
  const f = c.fights![0];
  assert.deepEqual([f.t,f.d,f.kind,f.name,f.result],[0,20,"combat","Plainstrider","kill"]);
  assert.equal(f.me.dmg,48); assert.equal(f.me.taken,12); assert.equal(f.me.heal,undefined); assert.equal(f.me.deaths,undefined);
  assert.equal(f.me.dealt[0].casts,undefined,"native total does not invent a cast count");
  assert.equal(f.log,undefined); assert.equal(f.series,undefined,"final meter totals do not invent a timeline");
  assert.ok(c.events.every(e=>e.f===0));
  assert.equal(f.group?.find(m=>m.name==="A friend")?.dmg,undefined);
  assert.deepEqual(fightProgress(f,5),{dmg:undefined,heal:undefined,taken:undefined});
  assert.deepEqual(fightProgress(f,20),{dmg:48,heal:undefined,taken:12});
});

test("a continuous long combat interval is not compressed as offline; incomplete capture remains honest",()=>{
  const c = composeChronicle(subject,[chunk(AT,[{t:0,k:"combat",a:"start",fightId:"long",text:"Enemy"}]),chunk(AT+700,[{t:0,k:"combat",a:"end",fightId:"long",text:"Enemy",d:700,result:"ended"}])],maps)!;
  assert.equal(c.sessions?.length,1); assert.equal(c.fights?.[0].d,700);
  assert.equal(c.fights?.[0].me.dmg,undefined); assert.equal(c.fights?.[0].coverage,"unavailable");
  const partial = composeChronicle(subject,[chunk(AT,[{t:0,k:"combat",a:"start",fightId:"open",text:"Enemy"},{t:6,k:"action",a:"cast",text:"A spell",fightId:"open"}])],maps)!;
  assert.equal(partial.fights?.[0].result,"interrupted"); assert.equal(partial.fights?.[0].d,6);
  const killOnly = composeChronicle(subject,[chunk(AT,[{t:0,k:"kill",text:"Plainstrider",xp:52}])],maps)!;
  assert.equal(killOnly.fights,undefined,"a historic XP message cannot recover a combat start");
});

test("recorded state is time-correct, partial snapshots merge, known empty clears, and expired auras disappear",()=>{
  const c:Chronicle={v:1,character:{name:"A",classId:1,level:1},startedAt:AT,duration:100,zones:["mulgore"],path:[],events:[],stats:[
    {t:5,attrs:[["Strength",20]],aurasKnown:true,auras:[{id:1,text:"A buff",helpful:true,expiresAt:AT+15}],roster:[{name:"A"}],groupType:"solo"},
    {t:10,roster:[{name:"A"},{name:"Friend"}],groupType:"party"},
    {t:20,aurasKnown:false},
    {t:25,aurasKnown:true,auras:[],roster:[],groupType:"solo"},
  ]};
  assert.ok(parseChronicle(c)); assert.equal(statsAt(c,4),null);
  const at10=statsAt(c,10)!; assert.deepEqual(at10.attrs,[["Strength",20]]); assert.equal(at10.sheetAt,5); assert.equal(at10.roster?.length,2); assert.equal(at10.auras?.length,1);
  assert.deepEqual(statsAt(c,16)?.auras,[]); assert.equal(statsAt(c,20)?.auras,undefined); assert.equal(statsAt(c,20)?.aurasKnown,false);
  assert.deepEqual(statsAt(c,25)?.auras,[]); assert.deepEqual(statsAt(c,25)?.roster,[]);
  assert.equal(c.stats![0].auras!.length,1,"seeking never mutates raw recorded state");
});

test("historical attributes and dungeon aggregates are recovered without passing the whole run off as one fight",()=>{
  const c=composeChronicle(subject,[
    ob("armory.snapshot",AT,{stats:{str:30,armor:120,unknown:99}}),
    ob("instance.entered",AT+5,{runId:"r",name:"A dungeon",startedAt:AT+5,instanceType:"party",roster:[{guid:"own",name:"Aria",classId:11}]}),
    ob("raid.encounter_finished",AT+30,{encounterId:1,name:"Boss",success:true,durationMs:10000}),
    ob("run.finished",AT+50,{runId:"r",name:"A dungeon",startedAt:AT+5,endedAt:AT+50,combat:{...summary,coverage:"unavailable",players:[]}}),
    ob("run.finished",AT+50,{runId:"r",name:"A dungeon",startedAt:AT+5,endedAt:AT+50,combat:summary}),
  ],maps)!;
  assert.deepEqual(c.stats?.find(s=>s.attrs)?.attrs,[["Strength",30],["Armor",120]]);
  assert.equal(c.fights?.length,1); assert.equal(c.fights?.[0].kind,"boss"); assert.equal(c.fights?.[0].d,10); assert.equal(c.fights?.[0].me.dmg,undefined);
  const leave=c.events.find(e=>e.k==="dungeon"&&e.a==="leave")!;
  assert.equal(leave.summary?.me.dmg,48); assert.equal(leave.summary?.coverage,"partial"); assert.equal(leave.summary?.t,50);
  assert.equal(instances(c)[0].summary?.me.dmg,48);
  assert.equal(instanceAt(instances(c),20)?.summary,undefined,"a later final run aggregate does not leak into the live playback state");
  assert.equal(c.events.filter(e=>e.k==="dungeon"&&e.a==="leave").length,1,"final same-time snapshot replaces provisional totals");
});

test("sidebar records hold actual wallet, played time, identity, complete skills and equipment at their own times",()=>{
  const c=composeChronicle(subject,[chunk(AT,[
    {t:0,k:"state",copper:123456,played:144000,race:"Night Elf",faction:"Alliance",guild:"Recorded Guild",spec:"Arms",attrs:[["Strength",30]],enh:[["Critical strike","12.5%"]],skills:{Herbalism:[54,75],Defense:[20,100]},professions:["Herbalism"],equipped:[{slot:16,itemId:117}]},
    {t:10,k:"state",aurasKnown:true,auras:[]},
    {t:20,k:"state",copper:120000,played:144020,guild:"",skills:{Herbalism:[55,75]}}]),
  ],maps)!;
  assert.ok(c&&parseChronicle(c));
  const first=statsAt(c,15)!;
  assert.equal(first.copper,123456);assert.equal(first.played,144000);assert.equal(first.playedAt,0);
  assert.equal(first.guild,"Recorded Guild");assert.equal(first.spec,"Arms");assert.equal(first.skills?.Herbalism[0],54);
  assert.deepEqual(first.equipped,[{slot:16,itemId:117}]);assert.deepEqual(first.enh,[["Critical strike","12.5%"]]);
  assert.equal(statsAt(c,20)?.guild,"");assert.equal(statsAt(c,20)?.playedAt,20);assert.equal(statsAt(c,20)?.skills?.Herbalism[0],55);
  const input=envelope([{t:0,k:"state",copper:123456,played:144000,race:"Elf",faction:"Alliance",guild:"Private Guild",spec:"Arms",skills:{Herbalism:[54,75]},professions:["Herbalism"],equipped:[{slot:16,itemId:117}]}]);
  const projected=projectExport(input,["own_track"]);
  const state=(projected.events[0].payload.events as Record<string,unknown>[])[0];
  for(const field of ['copper','played','race','faction','guild','spec','skills','professions','equipped'])assert.equal(state[field],undefined);
  const grant={producerId:"source",consentEpoch:1,since:0,scopes:["own_track" as const],revokedAt:null};
  assert.doesNotThrow(()=>validateUpload(grant,projected));
  assert.throws(()=>validateUpload(grant,{...input,scopes:["own_track"],events:input.events.map(e=>({...e,character:{id:"source:own"}}))}),/does not allow combat participant/);
});

test("nested encounter intervals remain active and duplicate end notifications open one fight",()=>{
  const c=composeChronicle(subject,[
    ob("instance.entered",AT,{runId:"r",name:"Dungeon",startedAt:AT}),
    chunk(AT,[{t:0,k:"combat",a:"start",fightId:"outer",text:"Combat"},{t:5,k:"combat",a:"start",fightId:"boss",text:"Boss",encounterKind:"boss"},{t:10,k:"combat",a:"end",fightId:"boss",text:"Boss",encounterKind:"boss",d:5,result:"kill"},{t:20,k:"combat",a:"end",fightId:"outer",text:"Combat",d:20,result:"ended"}]),
    ob("raid.encounter_finished",AT+10,{encounterId:1,name:"Boss",success:true}),
  ],maps)!;
  assert.equal(c.fights?.length,2);
  assert.equal(c.fights?.[fightAt(c,12)].name,"Combat","the earlier combat is still active after the nested boss ends");
  const bossEvents=instanceSummary(c,instances(c)[0],20).bosses.filter(e=>e.text==="Boss");
  assert.equal(bossEvents.length,1);assert.equal(bossEvents[0].k,"boss");
});

test("full NPC dialogue and fight context survive composition without entering anonymous uploads",()=>{
  const message="The NPC says something with more detail than a short label. ".repeat(8);
  const input=envelope([{t:0,k:"combat",a:"start",fightId:"dialogue-fight",text:"Boss",encounterKind:"boss",difficulty:"Heroic",size:5},
    {t:2,k:"speech",a:"say",text:"Speaker",speaker:"Speaker",message,fightId:"dialogue-fight"},
    {t:5,k:"combat",a:"end",fightId:"dialogue-fight",text:"Boss",encounterKind:"boss",d:5,result:"kill",difficulty:"Heroic",size:5,summary}]);
  assert.ok(eventSchema.safeParse(input.events[0]).success);
  const c=composeChronicle(subject,input.events,maps)!;
  assert.ok(c&&parseChronicle(c));
  assert.equal(c.fights?.[0].difficulty,"Heroic");assert.equal(c.fights?.[0].size,5);
  const speech=c.events.find(e=>e.k==='speech')!;
  assert.equal(speech.message,message);assert.equal(speech.speaker,"Speaker");assert.equal(speech.f,0);
  const projected=projectExport(input,["own_track"]);
  assert.ok(!(projected.events[0].payload.events as {k:string}[]).some(e=>e.k==='speech'));
  const onlySpeech=projectExport(envelope([{t:0,k:"speech",a:"say",speaker:"NPC",message:"hello"}]),["own_track"]);
  assert.deepEqual(onlySpeech.events,[],"removing dialogue never leaves an invalid empty batch");
});

test("timeline keys distinguish raids, dungeons, ordinary fights, bosses, PvP and deaths",()=>{
  const c=composeChronicle(subject,[ob("instance.entered",AT,{runId:"raid",name:"Recorded raid",instanceType:"raid",startedAt:AT}),
    chunk(AT,[{t:1,k:"combat",a:"start",fightId:"pvp",encounterKind:"pvp",text:"Opponent"},{t:3,k:"combat",a:"end",fightId:"pvp",encounterKind:"pvp",text:"Opponent",d:2,result:"ended"},{t:4,k:"death",text:"Death"},
      {t:6,k:"combat",a:"start",fightId:"boss",encounterKind:"boss",text:"Boss"},{t:8,k:"combat",a:"end",fightId:"boss",encounterKind:"boss",text:"Boss",d:2,result:"kill"},
      {t:9,k:"combat",a:"start",fightId:"mob",text:"Mob"},{t:10,k:"combat",a:"end",fightId:"mob",text:"Mob",d:1,result:"ended"}])],maps)!;
  const keys=c.events.map(typeKey);
  for(const key of ["travel.raid","combat.pvp","combat.boss","combat.fight","combat.death"])assert.ok(keys.includes(key),key);
  assert.equal(typeKey({t:0,k:"dungeon",a:"enter",text:"Dungeon",detail:"Dungeon"}),"travel.instance");
});

test("detailed journey contract bounds nested data and rejects misleading or wrong-kind fields",()=>{
  const valid=[{t:0,k:"combat",a:"end",fightId:"f",text:"Enemy",summary},{t:1,k:"action",a:"cast",id:78,text:"Heroic Strike"},{t:2,k:"aura",a:"gain",id:1,text:"A buff",helpful:true},{t:3,k:"state",attrs:[["Strength",10]],aurasKnown:true,auras:[],roster:[],groupType:"solo"}];
  const accepted=(events:Record<string,unknown>[])=>eventSchema.safeParse(envelope(events).events[0]).success;
  assert.equal(accepted(valid),true);
  assert.equal(accepted([{t:0,k:"combat",a:"start"}]),false);
  assert.equal(accepted([{t:0,k:"aura",a:"gain",helpful:"yes"}]),false);
  assert.equal(accepted([{t:0,k:"kill",attrs:[["Strength",10]]}]),false);
  assert.equal(accepted([{t:0,k:"state",aurasKnown:false,auras:[{text:"hidden",helpful:true}]}]),false);
  assert.equal(accepted([{t:0,k:"combat",a:"end",fightId:"f",summary:{...summary,players:[{guid:"own",dealt:[{name:"Attack",total:3,casts:-1}]}]}}]),false);
  assert.equal(accepted([{t:0,k:"state",auras:Array(161).fill({text:"Buff",helpful:true})}]),false);
  const roster=Array.from({length:80},(_,i)=>({guid:`g${i}`,name:"x".repeat(240)}));
  assert.equal(accepted(Array.from({length:20},(_,t)=>({t,k:"state",roster}))),false,"bounded moment count alone does not bound a large nested chunk");
});

test("removing character consent redacts all nested state and participant identities before upload",()=>{
  const input=envelope([{t:0,k:"state",attrs:[["Strength",10]],enh:[["Crit","1%"]],ilvl:10,roster:[{guid:"own",name:"Aria"},{guid:"friend",name:"A friend"}],groupType:"party"},{t:1,k:"combat",a:"end",fightId:"f",summary}]);
  const projected=projectExport(input,["own_track"]);
  const moments=projected.events[0].payload.events as Record<string,unknown>[];
  for(const key of ['attrs','enh','ilvl','roster'])assert.equal(moments[0][key],undefined);
  const players=(moments[1].summary as {players:Record<string,unknown>[]}).players;
  assert.equal(players.length,1); assert.equal(players[0].guid,"source:own"); assert.equal(players[0].name,undefined);
  assert.equal((input.events[0].payload.events as Record<string,unknown>[])[0].ilvl,10,"projection does not mutate the source");
  const grant={producerId:"source",consentEpoch:1,since:0,scopes:["own_track"] as const,revokedAt:null};
  assert.doesNotThrow(()=>validateUpload({...grant,scopes:[...grant.scopes]},projected));
  const unredacted={...input,scopes:["own_track"],events:input.events.map(e=>({...e,character:{id:"source:own"}}))};
  assert.throws(()=>validateUpload({...grant,scopes:[...grant.scopes]},unredacted),/does not allow combat participant identities/);
  const noEnvelopeIdentity=projectExport({...input,events:input.events.map(({character,...e})=>e)},["own_track"]);
  assert.deepEqual(((noEnvelopeIdentity.events[0].payload.events as Record<string,unknown>[])[1].summary as {players:unknown[]}).players,[]);
});

test("new combat actors and creature IDs survive composition with identities removed when consent is revoked",()=>{
  const moments=[{t:0,k:"combat",a:"start",fightId:"actor",text:"Plainstrider",npcId:2955},
    {t:2,k:"action",a:"cast",text:"Fireball",id:133,icon:135812,actor:"Plainstrider",actorSide:"enemy",target:"Aria",fightId:"actor"},
    {t:3,k:"action",a:"cast",text:"Heroic Strike",id:78,icon:132282,actor:"Aria",actorSide:"me",target:"Plainstrider",fightId:"actor"},
    {t:5,k:"combat",a:"end",fightId:"actor",text:"Plainstrider",npcId:2955,d:5,result:"kill"}];
  assert.ok(eventSchema.safeParse(envelope(moments).events[0]).success);
  const c=composeChronicle(subject,[chunk(AT,moments)],maps)!;
  assert.ok(parseChronicle(c));
  assert.equal(c.fights![0].npcId,2955);
  assert.equal(c.events.find(e=>e.text==="Fireball")?.actor,"Plainstrider");
  assert.equal(c.events.find(e=>e.text==="Heroic Strike")?.target,"Plainstrider");
  const projected=projectExport(envelope(moments),["own_track"]);
  const clean=projected.events[0].payload.events as Record<string,unknown>[];
  assert.equal(clean.some(e=>e.actorSide==="enemy"),false);
  const own=clean.find(e=>e.actorSide==="me")!;
  assert.equal(own.actor,undefined);assert.equal(own.target,undefined);assert.equal(own.icon,132282);
});

test("historical armory rows are read only with current character consent and no revoked grant",async()=>{
  const {db,sql}=fixture();
  sql.prepare("INSERT INTO atlas_observations(id,user_id,producer_id,event_id,grant_id,kind,scope,observed_at,profile_id,payload,game,evidence) VALUES('detail','gm','src-gm','d','grant-gm','armory.snapshot','own_character',?,'p-gm',?,'{}','api_snapshot')").run(AT,JSON.stringify({stats:{str:29}}));
  assert.equal((await myChronicle(db,"gm","p-gm",0,maps,AT+10))?.chronicle?.stats?.[0].attrs?.[0][1],29);
  sql.exec(`UPDATE atlas_grants SET scopes='["own_track"]' WHERE id='grant-gm'`);
  assert.equal((await myChronicle(db,"gm","p-gm",0,maps,AT+10))?.chronicle,null);
  sql.exec(`UPDATE atlas_grants SET scopes='["own_character"]', revoked_at=1 WHERE id='grant-gm'`);
  assert.equal((await myChronicle(db,"gm","p-gm",0,maps,AT+10))?.chronicle,null);
});

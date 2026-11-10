// Full synthetic loop: Lua export -> Rust client -> local D1/API -> community JSON -> Lua cache.
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
const root=fileURLToPath(new URL('../',import.meta.url));
const base=process.env.EVERTALLY_TEST_BASE??'http://127.0.0.1:5184';
const url=new URL(base);
assert(url.hostname==='127.0.0.1'&&url.port==='5184','Only the isolated loopback test server on port 5184 is allowed');
const dir=path.join(root,'platform/.test-artifacts/complete-flow');await mkdir(dir,{recursive:true});
let cookie='';const checks=[];
function check(label,ok){assert(ok,label);checks.push(label);console.log('PASS '+label);}
async function call(p,{method='GET',body,token,anonymous=false}={}){
 const headers={Origin:base};if(body!==undefined)headers['Content-Type']='application/json';
 if(cookie&&!anonymous)headers.Cookie=cookie;if(token)headers.Authorization='Bearer '+token;
 const response=await fetch(base+p,{method,headers,body:body===undefined?undefined:JSON.stringify(body),redirect:'manual'});
 const text=await response.text();let data;try{data=JSON.parse(text);}catch{data={text:text.slice(0,120)};}
 return {status:response.status,data,headers:response.headers};
}
const post=(p,body,token)=>call(p,{method:'POST',body,token});
check('Private professions require a session',(await call('/api/professions')).status===401);
const login=await call('/auth/dev?return_to=%2F');
cookie=login.headers.getSetCookie().map(value=>value.split(';')[0]).join('; ');
check('Isolated development session created',login.status===302&&Boolean(cookie));
check('Fresh isolated database required',(await call('/api/me')).data.eventCount===0);
const now=Math.floor(Date.now()/1000);
const template=JSON.parse(await readFile(path.join(root,'tests/lua/fixtures/export.json'),'utf8'));
function makeEnvelope(){
 const exportData=structuredClone(template),producerId='integration-'+crypto.randomUUID();
 exportData.producerId=producerId;exportData.since=now-3600;exportData.consentEpoch=1;
 for(const [i,event] of exportData.events.entries()){
  event.producerId=producerId;event.eventId=producerId+':'+i;event.observedAt=now;
  if(event.character){event.character.id=producerId+':self';event.character.name='Synthetic Hero';event.character.realm='Synthetic Realm';}
  if(event.kind==='run.finished')Object.assign(event.payload,{runId:producerId+':run',startedAt:now-1800,endedAt:now,durationMs:1800000,deaths:1,bossCount:2,rankEligible:true,bosses:[{encounterId:900001,name:'Synthetic first boss',killedAt:now-1200},{encounterId:900002,name:'Synthetic last boss',killedAt:now}]});
 }
 const reference=exportData.events[0];
 for(const [kind,payload] of [
  ['craft.result',{recipeId:999002,itemId:2136,quantity:3,professionId:171}],
  ['cooldown.snapshot',{recipeId:999002,readyAt:now+3600}],
  ['vendor.snapshot',{npcId:999001,name:'Synthetic vendor',items:[{itemId:2136,name:'Synthetic water',price:100,quantity:4}],mapId:1426,x:.5,y:.6}],
  ['loot.received',{itemId:2136,name:'Synthetic water',quantity:2,sourceKind:'quest',sourceCertain:false}],
 ])exportData.events.push({...structuredClone(reference),eventId:producerId+':'+exportData.events.length,kind,payload});
 return exportData;
}
function lua(value){if(value===null)return'nil';if(Array.isArray(value))return'{'+value.map(lua).join(',')+'}';if(typeof value==='object')return'{'+Object.entries(value).map(([key,v])=>'['+JSON.stringify(key)+']='+lua(v)).join(',')+'}';return JSON.stringify(value);}
let changed=false;
try{
 const env=makeEnvelope();
 const start=await post('/api/device/start',{name:'Synthetic integration PC'});check('Desktop pairing starts',start.status===201);
 check('Pairing is pending before approval',(await post('/api/device/poll',{deviceCode:start.data.deviceCode})).data.status==='pending');
 check('Explicit local approval succeeds',(await post('/api/pairing',{userCode:start.data.userCode,scopes:env.scopes,approve:true})).status===200);
 const paired=await post('/api/device/poll',{deviceCode:start.data.deviceCode});check('One-time device token issued',paired.data.status==='approved');
 const fixture=path.join(dir,'Evertally_Export.lua');await writeFile(fixture,'EvertallyExportDB='+lua(env),'utf8');
 const rust=spawnSync(path.join(root,'sync/target/debug/examples/verify_local.exe'),[fixture],{encoding:'utf8',env:{...process.env,EVERTALLY_TEST_BASE:base,EVERTALLY_TEST_TOKEN:paired.data.token},windowsHide:true});
 assert.equal(rust.status,0,rust.stderr);const rustResult=JSON.parse(rust.stdout.trim());changed=true;
 check('Real Rust parser/client uploaded every synthetic observation',rustResult.accepted===env.events.length);
 check('Real Rust client handles duplicates and advances its cursor',rustResult.duplicates===env.events.length&&rustResult.pending===0);
 let me=(await call('/api/me')).data;check('Private profile stays private by default',me.profiles.length===1&&(await call('/api/runs',{anonymous:true})).data.runs.length===0);
 const professions=(await call('/api/professions')).data;const owner=professions.characters[0];
 check('Profession snapshot and recipe are readable only by their owner',owner.professions[0].skill===75&&owner.professions[0].recipes[0].recipeId===999002);
 check('Craft quantity and cooldown survive end to end',owner.crafts[0].quantity===3&&owner.cooldowns[0].readyAt===now+3600);
 check('Anonymous profession request remains denied',(await call('/api/professions',{anonymous:true})).status===401);
 const ownRuns=(await call('/api/runs?mine=1')).data.runs;
 check('Run detail preserves boss timeline, end, difficulty, death count and game snapshot',ownRuns[0].bosses.length===2&&ownRuns[0].endedAt===now&&ownRuns[0].difficultyId===1&&ownRuns[0].deaths===1&&ownRuns[0].game.product==='forever');
 check('Client cannot promote a run into verified ranking',ownRuns[0].rankEligible===false);
 check('Explicit publishing is required',(await call('/api/profiles/'+me.profiles[0].id,{method:'PATCH',body:{public:true}})).status===200);
 check('Public run becomes visible only after publication',(await call('/api/runs',{anonymous:true})).data.runs.length===1);
 check('Count leaderboard includes observed participation',(await call('/api/leaderboards?metric=count',{anonymous:true})).data.entries[0].count===1);
 check('Speed leaderboard stays unavailable without verified rulesets',(await call('/api/leaderboards?metric=time',{anonymous:true})).data.entries.length===0);
 const snapshot=(await call('/api/community',{anonymous:true})).data;
 check('Community snapshot exposes bounded anonymous facts',snapshot.entities.length>=3&&Buffer.byteLength(JSON.stringify(snapshot))<=49152&&!JSON.stringify(snapshot).includes('Synthetic Hero'));
 const snapshotFile=path.join(dir,'community.json');await writeFile(snapshotFile,JSON.stringify(snapshot),'utf8');
 const python=process.env.EVERTALLY_PYTHON??'C:\\Users\\domin\\AppData\\Local\\Programs\\Python\\Python312\\python.exe';
 const roundtrip=spawnSync(python,[path.join(root,'tools/verify_community_roundtrip.py'),snapshotFile],{encoding:'utf8',windowsHide:true});
 assert.equal(roundtrip.status,0,roundtrip.stderr);const result=JSON.parse(roundtrip.stdout);
 check('Actual Lua addon imports web JSON and keeps cache after reload',result.imported===snapshot.entities.length&&result.survivesReload);
 check('Imported community facts never become own observations or peer relay',result.ownEventsAdded===0&&result.peerRelay===false);
 check('Grant can be revoked',(await call('/api/consents/'+me.grants[0].id,{method:'DELETE'})).status===200);
 check('Revoked world facts disappear from atlas and new community snapshots',(await call('/api/community',{anonymous:true})).data.entities.length===0&&(await call('/api/atlas',{anonymous:true})).data.entities.length===0);
 check('Revoked run disappears from public projection',(await call('/api/runs',{anonymous:true})).data.runs.length===0);
 check('Revoked grant cannot be uploaded again',(await post('/api/uploads',{grantId:me.grants[0].id,export:env})).status===403);
 check('Private profession history remains accessible to its owner',(await call('/api/professions')).data.characters.length===1);
 await call('/api/me/data',{method:'DELETE'});changed=false;
 if(process.env.EVERTALLY_KEEP_FIXTURE==='1'){
  const fixture=makeEnvelope();const grant=(await post('/api/consents',{producerId:fixture.producerId,consentEpoch:1,since:fixture.since,scopes:fixture.scopes})).data.grant;
  await post('/api/uploads',{grantId:grant.id,export:fixture});me=(await call('/api/me')).data;
  await call('/api/profiles/'+me.profiles[0].id,{method:'PATCH',body:{public:true}});
 }
 await writeFile(path.join(root,'releases/complete-flow-verification.json'),JSON.stringify({scope:'isolated local database, synthetic fixtures only',base,checks,keptSyntheticFixture:process.env.EVERTALLY_KEEP_FIXTURE==='1'},null,2));
}finally{if(changed)await call('/api/me/data',{method:'DELETE'});}

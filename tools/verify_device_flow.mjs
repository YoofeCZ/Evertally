// Local integration check for desktop-app pairing and upload. Synthetic data only;
// never targets a hosted site. Usage: node tools/verify_device_flow.mjs tests/lua/fixtures/export.json
// Requires the local dev server (npm run dev) and a fresh local database.
import { readFile } from 'node:fs/promises';
const base='http://127.0.0.1:5173'; let cookie=''; const out=[];
const ok=(label,cond,extra='')=>{out.push(`${cond?'PASS':'FAIL'} ${label}${extra?' — '+extra:''}`); if(!cond) process.exitCode=1;};
async function call(path,{method='GET',body,headers={},auth}={}){const h={...headers};if(body!==undefined)h['Content-Type']='application/json';if(cookie)h.Cookie=cookie;if(auth)h.Authorization='Bearer '+auth;const r=await fetch(base+path,{method,headers:h,body:body!==undefined?JSON.stringify(body):undefined,redirect:'manual'});let data=null;const t=await r.text();try{data=JSON.parse(t)}catch{data={raw:t.slice(0,120)}}return {status:r.status,data,headers:r.headers};}
const st=await call('/api/status'); ok('status reports auth options',st.status===200&&st.data.auth?.devLogin===true,JSON.stringify(st.data.auth));
const start=await call('/api/device/start',{method:'POST',body:{name:'Test PC'}}); ok('pairing starts without account',start.status===201&&/^[A-Z2-9]{4}-[A-Z2-9]{4}$/.test(start.data.userCode),start.data.userCode);
const pend=await call('/api/device/poll',{method:'POST',body:{deviceCode:start.data.deviceCode}}); ok('poll is pending before approval',pend.data.status==='pending');
const anon=await call('/api/pairing?code='+start.data.userCode); ok('approval page needs sign-in',anon.status===401);
const login=await call('/auth/dev?return_to=%2Flink'); cookie=login.headers.getSetCookie().map(c=>c.split(';')[0]).join('; '); ok('dev login sets session',login.status===302&&cookie.includes('et_session='),login.headers.get('location'));
const desc=await call('/api/pairing?code='+start.data.userCode.toLowerCase()); ok('pending pairing is described',desc.status===200&&desc.data.name==='Test PC');
const xorigin=await call('/api/pairing',{method:'POST',body:{userCode:start.data.userCode,scopes:['world_facts'],approve:true},headers:{Origin:'https://evil.example'}}); ok('cross-site approval rejected',xorigin.status===403);
const appr=await call('/api/pairing',{method:'POST',body:{userCode:start.data.userCode,scopes:['world_facts','own_runs'],approve:true},headers:{Origin:base}}); ok('approval with scopes',appr.status===200&&appr.data.approved===true);
const tok=await call('/api/device/poll',{method:'POST',body:{deviceCode:start.data.deviceCode}}); ok('token issued after approval',tok.data.status==='approved'&&tok.data.token?.startsWith('etd_'));
const again=await call('/api/device/poll',{method:'POST',body:{deviceCode:start.data.deviceCode}}); ok('token is issued only once',again.status===400&&again.data.error?.code==='expired_token');
const env=JSON.parse(await readFile(process.argv[2],'utf8'));
// A fresh source per run, so a previous run's revoked consent never interferes.
const source='integration-'+crypto.randomUUID();
env.producerId=source;
for(const e of env.events){e.producerId=source;e.eventId=e.eventId.replace(/^[^:]+/,source);}
const up=await call('/api/device/upload',{method:'POST',body:{export:env},auth:tok.data.token}); ok('device upload accepted',up.status===200&&up.data.accepted>0,JSON.stringify(up.data));
const up2=await call('/api/device/upload',{method:'POST',body:{export:env},auth:tok.data.token}); ok('re-upload is idempotent',up2.status===200&&up2.data.accepted===0&&up2.data.duplicates===up.data.accepted,JSON.stringify(up2.data));
const me=await call('/api/me'); ok('device listed for user',me.status===200&&me.data.devices?.length===1&&me.data.devices[0].scopes.join()==='world_facts,own_runs');
const runs=await call('/api/runs?mine=1'); const r0=runs.data.runs?.[0]; ok('own_character not granted: run kept pseudonymous',!!r0&&r0.character&&r0.character.name===undefined&&r0.character.id===source+':own',JSON.stringify(r0?.character));
ok('no public profile created without own_character',(me.data.profiles??[]).length===0);
const bad=await call('/api/device/upload',{method:'POST',body:{export:env},auth:'etd_wrong'}); ok('wrong token rejected',bad.status===401);
const rv=await call('/api/devices/'+me.data.devices[0].id,{method:'DELETE',headers:{Origin:base}}); ok('device revoked',rv.status===200);
const after=await call('/api/device/upload',{method:'POST',body:{export:env},auth:tok.data.token}); ok('revoked device rejected',after.status===401);
const del=await call('/api/me/data',{method:'DELETE',headers:{Origin:base}}); ok('test data deleted',del.status===200);
const lo=await call('/auth/logout',{method:'POST',headers:{Origin:base}}); ok('logout',lo.status===303);
console.log(out.join('\n'));

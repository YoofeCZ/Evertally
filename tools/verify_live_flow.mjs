// Loopback-only live-position integration test. Never reads player files or credentials.
import assert from 'node:assert/strict';
import {createHash,randomBytes} from 'node:crypto';
import {DatabaseSync} from 'node:sqlite';
import {readdirSync,readFileSync} from 'node:fs';
import path from 'node:path';
const endpoint=new URL(process.env.EVERTALLY_TEST_URL||'http://127.0.0.1:5173');
if(endpoint.protocol!=='http:'||endpoint.hostname!=='127.0.0.1')throw Error('This fixture test only supports loopback HTTP.');
const base=endpoint.origin;
const dir='platform/.wrangler/state/v3/d1/miniflare-D1DatabaseObject';
const file=path.join(dir,readdirSync(dir).find(n=>n.endsWith('.sqlite')&&n!=='metadata.sqlite'));
const db=new DatabaseSync(file);for(const name of ['0005_live_positions.sql','0006_sharing.sql','0007_game_connections.sql'])db.exec(readFileSync('platform/drizzle/'+name,'utf8'));
const run=randomBytes(5).toString('hex');const users=[];const at=()=>Math.floor(Date.now()/1000);
const hash=s=>createHash('sha256').update(s).digest('hex');
function account(name){const id=`ltest-${run}-${name}`,cookie=randomBytes(24).toString('hex'),token='etd_'+randomBytes(32).toString('hex');
 db.prepare('INSERT INTO et_users(id,username,created_at,last_login_at) VALUES(?,?,?,?)').run(id,id,at(),at());
 db.prepare('INSERT INTO et_sessions(token_hash,user_id,created_at,expires_at) VALUES(?,?,?,?)').run(hash(cookie),id,at(),at()+3600);
 db.prepare('INSERT INTO et_devices(id,user_id,name,token_hash,scopes,created_at) VALUES(?,?,?,?,?,?)').run(id,id,'test',hash(token),JSON.stringify(['own_track','own_character']),at());
 const u={id,cookie:`et_session=${cookie}`,token,producer:id,since:at()-60};users.push(u);return u;}
async function call(u,method,url,body,device=false,attempt=0){const r=await fetch(base+url,{method,headers:{Origin:base,...(device?{Authorization:`Bearer ${u.token}`}:{Cookie:u.cookie}),'Content-Type':'application/json'},body:body?JSON.stringify(body):undefined});const text=await r.text();if(r.status===503&&text.includes("Your worker restarted mid-request")&&attempt<2)return call(u,method,url,body,device,attempt+1);try{return {status:r.status,data:JSON.parse(text)};}catch{throw Error(`${method} ${url} returned ${r.status}: ${text.slice(0,150)}`);}}
const packet=u=>({v:1,p:u.producer,e:1,s:u.since,b:20,t:at(),c:{id:'Player-'+u.id,name:'LiveFixture',realm:'Test',classId:8,raceId:1,level:20},g:{product:'forever',build:'test',interface:16001,region:'test',realm:'Test'},m:1429,x:42000,y:65000});
try{
 const me=account('me'),other=account('other');let p=packet(me);
 let result=await call(me,'POST','/api/device/live',p,true);assert.equal(result.status,200,JSON.stringify(result));assert.equal(result.data.accepted,1);
 let live=await call(me,'GET','/api/live');assert.equal(live.status,200,JSON.stringify(live));assert.equal(live.data.own.length,1);assert.equal(live.data.own[0].x,.42);
 assert.equal((await call(other,'GET','/api/live')).data.own.length,0);
 assert.equal((await fetch(base+'/api/live')).status,401);
 // Explicit group membership and each member's sharing control live visibility as well.
 assert.equal((await call(other,'POST','/api/device/live',packet(other),true)).status,200);
 const otherProfile=(await call(other,'GET','/api/live')).data.own[0].profileId;
 const myProfile=live.data.own[0].profileId;
 const made=await call(me,'POST','/api/circles',{name:'Live test',profileId:myProfile,share:'last'});assert.equal(made.status,201,JSON.stringify(made));
 assert.equal((await call(other,'POST','/api/circles/join',{code:made.data.code,profileId:otherProfile,share:'last'})).status,200);
 assert.ok((await call(me,'GET','/api/live')).data.peers.some(p=>p.profileId===otherProfile));
 assert.equal((await call(other,'POST',`/api/circles/${made.data.id}`,{action:'share',share:'off'})).status,200);
 assert.ok(!(await call(me,'GET','/api/live')).data.peers.some(p=>p.profileId===otherProfile));
 // Current game group proves both memberships directly; no circle join or web friendship is needed.
 const adler=text=>{let a=1,b=0;for(const byte of Buffer.from(text)){a=(a+byte)%65521;b=(b+a)%65521;}return b*65536+a;};
 const token=name=>adler(name.toLowerCase()+'\0test');
 const roster=(name,kind='group')=>{const tokens=[{key:token(name),kind}];return {key:adler(kind+'\0'+tokens[0].key+'\n'),tokens};};
 let mine={...p,c:{...p.c,name:'LiveOwner'},r:roster('LivePartner')};
 let partner={...packet(other),c:{...packet(other).c,name:'LivePartner'},r:roster('LiveOwner')};
 assert.equal((await call(me,'POST','/api/device/live',mine,true)).status,200);
 assert.ok(!(await call(me,'GET','/api/live')).data.others.some(p=>p.profileId===otherProfile),'a unilateral game party claim grants no access');
 assert.equal((await call(other,'POST','/api/device/live',partner,true)).status,200);
 assert.ok((await call(me,'GET','/api/live')).data.others.some(p=>p.profileId===otherProfile&&p.audience==='group'),'game party automatic visibility');
 assert.equal(db.prepare('SELECT COUNT(*) n FROM et_friends WHERE user_a=? OR user_b=?').get(me.id,me.id).n,0,'no website friendship created');
 assert.equal((await call(other,'POST','/api/device/live',{...partner,r:{key:1,tokens:[]}},true)).status,200);
 assert.ok(!(await call(me,'GET','/api/live')).data.others.some(p=>p.profileId===otherProfile),'leaving the party hides the point immediately');
 mine={...mine,r:roster('LivePartner','friend')};partner={...partner,r:roster('LiveOwner','friend')};
 assert.equal((await call(me,'POST','/api/device/live',mine,true)).status,200);assert.equal((await call(other,'POST','/api/device/live',partner,true)).status,200);
 assert.equal((await call(me,'POST','/api/sharing',{friends:true})).status,200);
 assert.ok(!(await call(me,'GET','/api/live')).data.others.some(p=>p.profileId===otherProfile),'one friends-sharing switch alone grants no access');
 assert.equal((await call(other,'POST','/api/sharing',{friends:true})).status,200);
 assert.ok((await call(me,'GET','/api/live')).data.others.some(p=>p.profileId===otherProfile&&p.audience==='friends'),'game friends automatic visibility');
 await call(other,'POST','/api/sharing',{friends:false});
 assert.ok(!(await call(me,'GET','/api/live')).data.others.some(p=>p.profileId===otherProfile),'friend opt out hides immediately');
 // A newer point replaces the first one without writing route observations or history.
 p={...p,t:at()+1,x:43000};result=await call(me,'POST','/api/device/live',p,true);assert.equal(result.status,200);assert.equal((await call(me,'GET','/api/live')).data.own[0].x,.43);
 assert.equal(db.prepare('SELECT COUNT(*) n FROM et_live_positions WHERE user_id=?').get(me.id).n,1);
 assert.equal(db.prepare('SELECT COUNT(*) n FROM atlas_observations WHERE user_id=?').get(me.id).n,0);
 assert.equal((await call(me,'POST','/api/device/live',{...p,t:at()-60},true)).status,400);
 assert.equal((await call(me,'POST','/api/device/live',{...p,b:4},true)).status,403);
 db.prepare('UPDATE et_devices SET revoked_at=? WHERE id=?').run(at(),me.id);
 assert.equal((await call(me,'GET','/api/live')).data.own.length,0);
 assert.equal((await call(me,'POST','/api/device/live',{...p,t:at()},true)).status,401);
 console.log('PASS live HTTP: point replacement, private visibility, automatic mutual game party/friends without website friendship, departure and opt-out revocation, no historical events, timestamp, scope, device revocation');
}finally{
 for(const u of users){const erased=await call(u,'DELETE','/api/me/data').catch(e=>({status:0,data:{message:e.message}}));assert.equal(erased.status,200,JSON.stringify(erased));for(const table of ['et_circle_members','et_live_positions','atlas_profiles','atlas_observations','atlas_sources','atlas_grants','et_sessions','et_devices'])db.prepare(`DELETE FROM ${table} WHERE user_id=?`).run(u.id);db.prepare('DELETE FROM et_circles WHERE owner_user_id=?').run(u.id);db.prepare('DELETE FROM et_users WHERE id=?').run(u.id);}
 db.close();
}

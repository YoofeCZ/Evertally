import {z} from "zod";
import {getBinding} from "@/db";
import {characterSchema,gameSchema,SCOPES,type Scope} from "./contracts";
import {createGrant,serializeGrant,stableId} from "./store";
import {ApiError} from "./policy";
import {LIVE_TTL} from "./live-query";
import {gameConnectionStatements} from "./game-connections";
type Row=Record<string,unknown>;
export const LIVE_MIN_GAP=8;
export const LIVE_HEARTBEAT=300;
const rosterSchema=z.union([
  z.object({key:z.number().int().min(0).max(4294967295),entries:z.array(z.object({name:z.string().min(1).max(120),realm:z.string().min(1).max(120),kind:z.enum(["friend","group"])}).strict()).max(100)}).strict(),
  z.object({key:z.number().int().min(0).max(4294967295),tokens:z.array(z.object({key:z.number().int().min(0).max(4294967295),kind:z.enum(["friend","group"])}).strict()).max(100)}).strict(),
]);
export const liveInput=z.object({v:z.literal(1),p:z.string().min(1).max(180),e:z.number().int().nonnegative(),s:z.number().int().nonnegative(),b:z.number().int().min(0).max(63),t:z.number().int().nonnegative(),c:characterSchema,g:gameSchema,m:z.number().int().positive().max(100000),x:z.number().int().min(0).max(100000),y:z.number().int().min(0).max(100000),r:rosterSchema.optional()}).strict();
export function liveScopes(bits:number,deviceScopes:unknown):Scope[] {
  let allowed:unknown=[];try{allowed=JSON.parse(String(deviceScopes));}catch{/* invalid device grants allow nothing */}
  return SCOPES.filter((scope,i)=>Boolean(bits&(1<<i))&&Array.isArray(allowed)&&allowed.includes(scope));
}
export async function deviceLive(device:Row,raw:unknown) {
  const parsed=liveInput.safeParse(raw);if(!parsed.success)throw new ApiError("invalid_live","Invalid live position.",400);
  const p=parsed.data;const at=Math.floor(Date.now()/1000);
  if(p.t<at-15||p.t>at+5||p.t<p.s||p.s>at+5)throw new ApiError("stale_live","Live sample is stale or has an invalid time.",400);
  const scopes=liveScopes(p.b,device.scopes);
  if(!scopes.includes("own_track")||!scopes.includes("own_character"))throw new ApiError("scope_denied","Live position needs My route and My character for this device.",403);
  const user=String(device.user_id);const db=getBinding();
  const existing=await db.prepare("SELECT * FROM atlas_grants WHERE user_id=? AND producer_id=? AND consent_epoch=?").bind(user,p.p,p.e).first<Row>();
  const grant=existing?serializeGrant(existing):await createGrant(user,{producerId:p.p,consentEpoch:p.e,since:p.s,scopes});
  if(grant.revokedAt!==null||grant.since!==p.s||!grant.scopes.includes("own_track")||!grant.scopes.includes("own_character"))throw new ApiError("consent_revoked","This live sharing consent is not active.",403);
  const profile=await stableId(user,p.p,p.c.id);
  // D1 free tier = 100k rows written per day, and every stored sample rewrites several rows. A sample is stored only when it
  // says something new: the first one, another map, a heartbeat now and then, or the website asked "where are you?".
  // Older apps that still send every few seconds are dropped here after one cheap read.
  const last=await db.prepare("SELECT observed_at,map_id FROM et_last_positions WHERE profile_id=? AND user_id=?").bind(profile,user).first<Row>();
  if(last){
    const gap=p.t-Number(last.observed_at);
    const asked=await db.prepare("SELECT requested_at FROM et_locate_requests WHERE user_id=?").bind(user).first<Row>();
    const wanted=asked!==null&&Number(asked.requested_at)>Number(last.observed_at);
    if(!wanted&&(gap<LIVE_MIN_GAP||(gap<LIVE_HEARTBEAT&&Number(last.map_id)===p.m)))return {accepted:0,expiresAt:at+LIVE_TTL};
  }
  const guard=`EXISTS(SELECT 1 FROM atlas_grants WHERE id=? AND user_id=? AND revoked_at IS NULL) AND EXISTS(SELECT 1 FROM et_devices WHERE id=? AND user_id=? AND revoked_at IS NULL)`;
  const auth=[grant.id,user,String(device.id),user];
  const results=await db.batch([
    db.prepare(`INSERT INTO atlas_profiles(id,user_id,producer_id,character_key,name,realm,class_id,race_id,level,"public",last_seen)
      SELECT ?,?,?,?,?,?,?,?,?,0,? WHERE ${guard}
      ON CONFLICT(id) DO UPDATE SET name=excluded.name,realm=excluded.realm,class_id=excluded.class_id,race_id=excluded.race_id,level=excluded.level,last_seen=MAX(last_seen,excluded.last_seen)
      WHERE excluded.last_seen>=atlas_profiles.last_seen+300 OR atlas_profiles.name IS NOT excluded.name OR atlas_profiles.realm IS NOT excluded.realm
        OR atlas_profiles.class_id IS NOT excluded.class_id OR atlas_profiles.race_id IS NOT excluded.race_id OR atlas_profiles.level IS NOT excluded.level`)
      .bind(profile,user,p.p,p.c.id,p.c.name??null,p.c.realm??null,p.c.classId??null,p.c.raceId??null,p.c.level??null,p.t,...auth),
    db.prepare(`INSERT INTO et_live_positions(profile_id,user_id,grant_id,device_id,observed_at,expires_at,map_id,x,y)
      SELECT ?,?,?,?,?,?,?,?,? WHERE ${guard}
      ON CONFLICT(profile_id) DO UPDATE SET grant_id=excluded.grant_id,device_id=excluded.device_id,observed_at=excluded.observed_at,expires_at=excluded.expires_at,map_id=excluded.map_id,x=excluded.x,y=excluded.y WHERE excluded.observed_at>et_live_positions.observed_at`)
      .bind(profile,user,grant.id,String(device.id),p.t,at+LIVE_TTL,p.m,p.x/100000,p.y/100000,...auth),
    db.prepare("DELETE FROM et_live_positions WHERE expires_at<?").bind(at),
    db.prepare(`INSERT INTO et_last_positions(profile_id,user_id,observed_at,map_id,x,y)
      SELECT ?,?,?,?,?,? WHERE ${guard}
      ON CONFLICT(profile_id) DO UPDATE SET observed_at=excluded.observed_at,map_id=excluded.map_id,x=excluded.x,y=excluded.y WHERE excluded.observed_at>et_last_positions.observed_at`)
      .bind(profile,user,p.t,p.m,p.x/100000,p.y/100000,...auth),
    db.prepare("DELETE FROM et_locate_requests WHERE user_id=? AND requested_at<=?").bind(user,at),
    ...(gameConnectionStatements(db,{profileId:profile,userId:user,grantId:grant.id,deviceId:String(device.id),observedAt:p.t,expiresAt:at+LIVE_TTL,game:p.g,character:p.c,roster:p.r}) as unknown as D1PreparedStatement[]),
  ]);
  return {accepted:Number(results[1].meta.changes??0),expiresAt:at+LIVE_TTL};
}

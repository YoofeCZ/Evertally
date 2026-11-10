import { getBinding, getDb } from "@/db";
import { profiles as profileTable } from "@/db/schema";
import { eq } from "drizzle-orm";
import { scopeFor, type Scope } from "./contracts";
import { ApiError, sanitizedPayload, validateUpload } from "./policy";
import { COMMUNITY_OBSERVATIONS_SQL } from "./community";
import { atlasEntities } from "./atlas";
import { PUBLIC_PROFILE_ACCESS_SQL } from "./profiles";
import { applyGuildSnapshots, pruneTracks, releaseStatements, type Db as PeopleDb, type GuildSnapshot } from "./people";

type Row=Record<string,unknown>;
const now=()=>Math.floor(Date.now()/1000);
export async function stableId(...parts:string[]){const digest=await crypto.subtle.digest("SHA-256",new TextEncoder().encode(JSON.stringify(parts)));return Array.from(new Uint8Array(digest)).map(b=>b.toString(16).padStart(2,"0")).join("");}
async function all(sql:string,params:unknown[]=[]):Promise<Row[]>{const result=await getBinding().prepare(sql).bind(...params).all<Row>();return result.results;}
async function first(sql:string,params:unknown[]=[]):Promise<Row|null>{return getBinding().prepare(sql).bind(...params).first<Row>();}
function decode<T>(value:unknown,fallback:T):T{try{return JSON.parse(String(value)) as T;}catch{return fallback;}}
const bool=(v:unknown)=>v===1||v===true;
const nullableNum=(v:unknown)=>typeof v==="number"?v:null;
const nullableText=(v:unknown)=>typeof v==="string"?v:null;

export function serializeGrant(row:Row){return {id:String(row.id),producerId:String(row.producer_id),consentEpoch:Number(row.consent_epoch),since:Number(row.since),scopes:decode<Scope[]>(row.scopes,[]),revokedAt:nullableNum(row.revoked_at),createdAt:Number(row.created_at)};}
export function serializeProfile(row:Row){return {id:String(row.id),name:nullableText(row.name),realm:nullableText(row.realm),classId:nullableNum(row.class_id),raceId:nullableNum(row.race_id),level:nullableNum(row.level),public:bool(row.public),lastSeen:Number(row.last_seen)};}

export async function createGrant(userId:string,input:{producerId:string;consentEpoch:number;since:number;scopes:Scope[]}){
  const existing=await first("SELECT * FROM atlas_grants WHERE user_id=? AND producer_id=? AND consent_epoch=?",[userId,input.producerId,input.consentEpoch]);
  if(existing){const grant=serializeGrant(existing);if(grant.revokedAt!==null)throw new ApiError("consent_revoked","This consent version was revoked. Re-enable web export in the addon.",409);if(grant.since!==input.since||[...grant.scopes].sort().join()!==[...input.scopes].sort().join())throw new ApiError("consent_conflict","This consent version has a different scope. Create a new export version in the addon.",409);return grant;}
  const source=await first("SELECT * FROM atlas_sources WHERE user_id=? AND producer_id=?",[userId,input.producerId]);
  if(source&&Number(source.max_epoch)>=input.consentEpoch)throw new ApiError("consent_revoked","An older consent version cannot be reused.",409);
  const id=crypto.randomUUID(),createdAt=now(),sourceId=await stableId(userId,input.producerId);
  const db=getBinding();
  await db.batch([
    db.prepare("INSERT INTO atlas_sources(id,user_id,producer_id,max_epoch,created_at) VALUES(?,?,?,?,?) ON CONFLICT(user_id,producer_id) DO UPDATE SET max_epoch=excluded.max_epoch WHERE atlas_sources.max_epoch < excluded.max_epoch").bind(sourceId,userId,input.producerId,input.consentEpoch,createdAt),
    db.prepare("UPDATE atlas_grants SET revoked_at=? WHERE user_id=? AND producer_id=? AND revoked_at IS NULL AND consent_epoch < ?").bind(createdAt,userId,input.producerId,input.consentEpoch),
    db.prepare("INSERT INTO atlas_grants(id,user_id,producer_id,consent_epoch,since,scopes,created_at) SELECT ?,?,?,?,?,?,? WHERE EXISTS(SELECT 1 FROM atlas_sources WHERE id=? AND max_epoch=?)").bind(id,userId,input.producerId,input.consentEpoch,input.since,JSON.stringify(input.scopes),createdAt,sourceId,input.consentEpoch),
  ]);
  const grant=await first("SELECT * FROM atlas_grants WHERE id=? AND user_id=?",[id,userId]);if(!grant)throw new ApiError("consent_conflict","The consent changed in the meantime.",409);return serializeGrant(grant);
}
export async function revokeGrant(userId:string,id:string){const row=await first("SELECT id FROM atlas_grants WHERE id=? AND user_id=?",[id,userId]);if(!row)throw new ApiError("not_found","Consent not found.",404);await getBinding().prepare("UPDATE atlas_grants SET revoked_at=COALESCE(revoked_at,?) WHERE id=? AND user_id=?").bind(now(),id,userId).run();}

// One statement per set, regardless of event count. JSON parameters also avoid
// expanding a 500-event batch into hundreds of SQL bind parameters or queries.
export const PROFILE_BATCH_SQL = String.raw`
INSERT INTO atlas_profiles(id,user_id,producer_id,character_key,name,realm,class_id,race_id,level,"public",last_seen)
SELECT json_extract(j.value,'$.id'),json_extract(j.value,'$.userId'),json_extract(j.value,'$.producerId'),
       json_extract(j.value,'$.characterKey'),json_extract(j.value,'$.name'),json_extract(j.value,'$.realm'),
       json_extract(j.value,'$.classId'),json_extract(j.value,'$.raceId'),json_extract(j.value,'$.level'),0,
       json_extract(j.value,'$.lastSeen')
FROM json_each(?) AS j
WHERE EXISTS(SELECT 1 FROM atlas_grants WHERE id=? AND user_id=? AND revoked_at IS NULL)
  AND NOT EXISTS(SELECT 1 FROM atlas_observations WHERE id=json_extract(j.value,'$.observationId'))
ON CONFLICT(id) DO UPDATE SET
 name=CASE WHEN excluded.last_seen>=atlas_profiles.last_seen THEN COALESCE(excluded.name,atlas_profiles.name) ELSE atlas_profiles.name END,
 realm=CASE WHEN excluded.last_seen>=atlas_profiles.last_seen THEN COALESCE(excluded.realm,atlas_profiles.realm) ELSE atlas_profiles.realm END,
 class_id=CASE WHEN excluded.last_seen>=atlas_profiles.last_seen THEN COALESCE(excluded.class_id,atlas_profiles.class_id) ELSE atlas_profiles.class_id END,
 race_id=CASE WHEN excluded.last_seen>=atlas_profiles.last_seen THEN COALESCE(excluded.race_id,atlas_profiles.race_id) ELSE atlas_profiles.race_id END,
 level=CASE WHEN excluded.last_seen>=atlas_profiles.last_seen THEN COALESCE(excluded.level,atlas_profiles.level) ELSE atlas_profiles.level END,
 last_seen=MAX(atlas_profiles.last_seen,excluded.last_seen)
`;

export const OBSERVATION_BATCH_SQL = String.raw`
INSERT INTO atlas_observations(id,user_id,producer_id,event_id,grant_id,kind,scope,observed_at,profile_id,character_data,payload,game,evidence)
SELECT json_extract(j.value,'$.id'),json_extract(j.value,'$.userId'),json_extract(j.value,'$.producerId'),
       json_extract(j.value,'$.eventId'),json_extract(j.value,'$.grantId'),json_extract(j.value,'$.kind'),
       json_extract(j.value,'$.scope'),json_extract(j.value,'$.observedAt'),json_extract(j.value,'$.profileId'),
       json_extract(j.value,'$.characterData'),json_extract(j.value,'$.payload'),json_extract(j.value,'$.game'),
       json_extract(j.value,'$.evidence')
FROM json_each(?) AS j
WHERE EXISTS(SELECT 1 FROM atlas_grants WHERE id=? AND user_id=? AND revoked_at IS NULL)
ON CONFLICT(user_id,producer_id,event_id) DO NOTHING
`;

export async function uploadEvents(userId:string,grantId:string,raw:unknown){
  const row=await first("SELECT * FROM atlas_grants WHERE id=? AND user_id=?",[grantId,userId]);if(!row)throw new ApiError("scope_denied","No consent exists for this source.",403);
  const grant=serializeGrant(row);const envelope=validateUpload(grant,raw);
  if(envelope.events.length>500)throw new ApiError("batch_too_large","One batch may contain at most 500 events.",413);
  const db=getBinding(),profileRows:Row[]=[],observationRows:Row[]=[];const uploadId=crypto.randomUUID();
  const guildSnapshots:GuildSnapshot[]=[];let hasTracks=false;
  for(const event of envelope.events){
    const eventId=await stableId(userId,event.producerId,event.eventId);
    const profileId=event.character&&envelope.scopes.includes("own_character")?await stableId(userId,event.producerId,event.character.id):null;
    if(profileId&&event.character){const c=event.character;
      profileRows.push({id:profileId,userId,producerId:event.producerId,characterKey:c.id,name:c.name??null,realm:c.realm??null,classId:c.classId??null,raceId:c.raceId??null,level:c.level??null,lastSeen:event.observedAt,observationId:eventId});
    }
    if(event.kind==="track.path")hasTracks=true;
    if(event.kind==="guild.snapshot"&&profileId&&event.character?.name){
      const p=event.payload as {guildName?:string;rankIndex?:number;roster?:GuildSnapshot["roster"]};
      guildSnapshots.push({profileId,name:event.character.name,realm:event.character.realm??event.game.realm,observedAt:event.observedAt,guildName:p.guildName,rankIndex:p.rankIndex,roster:p.roster});
    }
    observationRows.push({id:eventId,userId,producerId:event.producerId,eventId:event.eventId,grantId,kind:event.kind,scope:scopeFor(event.kind),observedAt:event.observedAt,profileId,characterData:event.character??null,payload:sanitizedPayload(event),game:event.game,evidence:event.evidence});
  }
  if(!observationRows.length)return {accepted:0,duplicates:0,rejected:0,uploadId};
  // Both set-based inserts check the live grant within one D1 batch transaction.
  const results=await db.batch([
    db.prepare(PROFILE_BATCH_SQL).bind(JSON.stringify(profileRows),grantId,userId),
    db.prepare(OBSERVATION_BATCH_SQL).bind(JSON.stringify(observationRows),grantId,userId),
  ]);
  const accepted=Number(results[1]?.meta?.changes??0);
  const current=await first("SELECT revoked_at FROM atlas_grants WHERE id=? AND user_id=?",[grantId,userId]);
  if(!current||current.revoked_at!==null)throw new ApiError("consent_revoked","The consent was revoked during the upload.",403);
  const people=db as unknown as PeopleDb;
  if(guildSnapshots.length)await applyGuildSnapshots(people,userId,guildSnapshots);
  if(hasTracks)await pruneTracks(people,userId);
  const duplicates=envelope.events.length-accepted;
  await db.prepare("INSERT INTO atlas_uploads(id,user_id,grant_id,created_at,accepted,duplicates,rejected) VALUES(?,?,?,?,?,?,0)").bind(uploadId,userId,grantId,now(),accepted,duplicates).run();
  return {accepted,duplicates,rejected:0,uploadId};
}

export async function meData(userId:string){
  const [grants,profiles,count,runs]=await Promise.all([all("SELECT * FROM atlas_grants WHERE user_id=? ORDER BY created_at DESC",[userId]),all("SELECT * FROM atlas_profiles WHERE user_id=? ORDER BY last_seen DESC",[userId]),first("SELECT COUNT(*) AS count FROM atlas_observations WHERE user_id=?",[userId]),getRuns(userId)]);
  return {grants:grants.map(serializeGrant),profiles:profiles.map(serializeProfile),eventCount:Number(count?.count??0),runCount:runs.length};
}

export async function setProfileVisibility(userId:string,id:string,published:boolean){
  const existing=await first("SELECT * FROM atlas_profiles WHERE id=? AND user_id=?",[id,userId]);if(!existing)throw new ApiError("not_found","Character not found.",404);
  await getDb().update(profileTable).set({public:published}).where(eq(profileTable.id,id));
  return serializeProfile({...existing,public:published});
}

export async function deleteMyData(userId:string){const db=getBinding();await db.batch([
  db.prepare("UPDATE atlas_grants SET revoked_at=COALESCE(revoked_at,?) WHERE user_id=?").bind(now(),userId),
  db.prepare("DELETE FROM atlas_observations WHERE user_id=?").bind(userId),
  db.prepare("DELETE FROM atlas_profiles WHERE user_id=?").bind(userId),
  db.prepare("DELETE FROM atlas_uploads WHERE user_id=?").bind(userId),
  ...(releaseStatements(db as unknown as PeopleDb,userId) as unknown as D1PreparedStatement[]),
  db.prepare("UPDATE et_devices SET revoked_at=COALESCE(revoked_at,?) WHERE user_id=?").bind(now(),userId),
]);}

export async function getRuns(userId?:string){
  const filter=userId?"o.user_id=?":`p.public=1 AND EXISTS(SELECT 1 FROM atlas_grants g WHERE g.id=o.grant_id AND g.user_id=o.user_id AND g.producer_id=o.producer_id AND g.revoked_at IS NULL AND EXISTS(SELECT 1 FROM json_each(g.scopes) WHERE value='own_runs'))`;
  const rows=await all(`SELECT o.*,p.id AS p_id,p.name AS p_name,p.realm AS p_realm,p.class_id AS p_class_id,p.race_id AS p_race_id,p.level AS p_level FROM atlas_observations o LEFT JOIN atlas_profiles p ON p.id=o.profile_id WHERE ${filter} AND o.kind IN ('instance.entered','run.finished','run.interrupted') ORDER BY o.observed_at DESC,CASE o.kind WHEN 'run.finished' THEN 3 WHEN 'run.interrupted' THEN 2 ELSE 1 END DESC LIMIT 5000`,userId?[userId]:[]);
  const runs=new Map<string,Record<string,unknown>>();
  for(const row of rows){const p=decode<Record<string,unknown>>(row.payload,{});const key=String(row.user_id)+":"+String(row.producer_id)+":"+String(p.runId);if(runs.has(key))continue;
    const snapshot=decode<Record<string,unknown>|null>(row.character_data,null);
    runs.set(key,{id:String(row.id),name:p.name??"Unknown instance",instanceId:p.instanceId??null,instanceType:p.instanceType??"party",startedAt:p.startedAt,endedAt:p.endedAt??null,durationMs:p.durationMs??null,difficultyId:p.difficultyId??null,deaths:p.deaths??null,game:decode<Record<string,unknown>|null>(row.game,null),status:p.status,completion:p.completion??"unknown",rankEligible:false,rulesetId:p.rulesetId??null,bossCount:p.bossCount??null,bosses:p.bosses??[],groupSize:p.groupSize??null,maxLevel:p.maxLevel??null,minLevel:p.minLevel??null,evidence:row.evidence,character:row.p_id?{id:row.p_id,name:snapshot?.name??row.p_name,realm:snapshot?.realm??row.p_realm,classId:snapshot?.classId??row.p_class_id,raceId:snapshot?.raceId??row.p_race_id,level:snapshot?.level??row.p_level}:userId?snapshot:null});}
  return [...runs.values()];
}

export async function getAtlas(kind="",search=""){
  const rows=await all(COMMUNITY_OBSERVATIONS_SQL);
  return atlasEntities(rows,kind,search);
}

export async function profileHistory(id:string,userId?:string){
  const row=await first("SELECT * FROM atlas_profiles WHERE id=?",[id]);
  if(!row||(!bool(row.public)&&row.user_id!==userId))throw new ApiError("not_found","Profile is private or unavailable.",404);
  const owner=row.user_id===userId;
  if(!owner&&!(await first(PUBLIC_PROFILE_ACCESS_SQL,[id])))throw new ApiError("not_found","Profile is private or unavailable.",404);
  const rows=await all(`SELECT CAST(json_extract(o.payload,'$.mapId') AS INTEGER) AS mapId,
    MAX(json_extract(o.payload,'$.mapName')) AS mapName,COUNT(*) AS visits,
    CAST(MAX(o.observed_at)/86400 AS INTEGER)*86400 AS lastVisited
    FROM atlas_observations o JOIN atlas_grants g ON g.id=o.grant_id AND g.user_id=o.user_id AND g.producer_id=o.producer_id
    WHERE o.profile_id=? AND o.kind='zone.visited' AND o.scope='world_facts'
    AND g.revoked_at IS NULL AND EXISTS(SELECT 1 FROM json_each(g.scopes) WHERE value='world_facts')
    AND EXISTS(SELECT 1 FROM json_each(g.scopes) WHERE value='own_character')
    GROUP BY mapId ORDER BY lastVisited DESC LIMIT 200`,[id]);
  const runs=(await getRuns(owner?userId:undefined)).filter(r=>(r.character as Record<string,unknown>|null)?.id===id).slice(0,100);
  const profile=serializeProfile(row);
  if(!owner)profile.lastSeen=Math.floor(profile.lastSeen/86400)*86400;
  return {profile,zones:rows.map(r=>({mapId:r.mapId,mapName:r.mapName,visits:r.visits,lastVisited:r.lastVisited})),runs};
}

export async function statusData(){
  const [events,runs]=await Promise.all([first(`SELECT COUNT(*) AS count,MAX(o.observed_at) AS latest,
  COUNT(DISTINCT CASE WHEN p.public=1 THEN p.id END) AS characters
  FROM atlas_observations o JOIN atlas_grants g ON g.id=o.grant_id AND g.user_id=o.user_id AND g.producer_id=o.producer_id
  LEFT JOIN atlas_profiles p ON p.id=o.profile_id
  WHERE g.revoked_at IS NULL AND EXISTS(SELECT 1 FROM json_each(g.scopes) WHERE value=o.scope)
  AND (o.scope='world_facts' OR (p.public=1 AND o.scope IN ('own_runs','own_character')))`),getRuns()]);
  return {totalEvents:Number(events?.count??0),totalCharacters:Number(events?.characters??0),totalRuns:runs.length,latestAt:nullableNum(events?.latest)};
}

export async function getLeaderboards(params:URLSearchParams){
  const metric=params.get("metric")==="time"?"time":"count";const runs=await getRuns();
  const filtered=runs.filter(run=>{const c=run.character as Record<string,unknown>|null;return c&&(!params.get("classId")||String(c.classId)===params.get("classId"))&&(!params.get("raceId")||String(c.raceId)===params.get("raceId"))&&(!params.get("instanceId")||String(run.instanceId)===params.get("instanceId"))&&run.status==="completed"&&run.completion!=="unknown"&&run.evidence!=="manual";});
  // No runtime-validated ruleset exists yet: never promote client eligibility to speed records.
  if(metric==="time")return {entries:[],sampleSize:0,countingUnit:"participation",rulesLabel:"Speed rankings wait for a ruleset verified in the game. Personal times stay in your history."};
  const grouped=new Map<string,{character:Record<string,unknown>;count:number;bestMs:number|null;instanceId:unknown;name:string}>();
  for(const run of filtered){const c=run.character as Record<string,unknown>;const key=String(c.id);let entry=grouped.get(key);if(!entry){entry={character:c,count:0,bestMs:null,instanceId:params.get("instanceId")??null,name:String(c.name??"Postava")};grouped.set(key,entry);}entry.count++;if(typeof run.durationMs==="number")entry.bestMs=entry.bestMs===null?run.durationMs:Math.min(entry.bestMs,run.durationMs);}
  return {entries:[...grouped.values()].sort((a,b)=>b.count-a.count||String(a.character.id).localeCompare(String(b.character.id))).map((entry,index)=>({rank:index+1,...entry})),sampleSize:filtered.length,countingUnit:"participation",rulesLabel:"Recorded completed participations of public characters; several members of one group can each report their own. This is not a count of unique group runs."};
}

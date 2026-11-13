import type { Run, Entry } from "../components/evertally/types";
import type { Db } from "./people";
// A final meter snapshot can arrive in the same whole second as run.finished.
// The later insertion must win over the provisional record of the same kind.
export const RUN_OBSERVATION_ORDER="o.observed_at DESC,CASE o.kind WHEN 'run.finished' THEN 3 WHEN 'run.interrupted' THEN 2 ELSE 1 END DESC,o.rowid DESC";

// Rankings read every permitted observation in batches instead of silently
// restricting the result to the latest 5,000 events used by the runs page.
export async function publicRankingObservations(db: Db): Promise<Record<string, unknown>[]> {
  const rows: Record<string, unknown>[] = [];
  const size = 1000;
  for (;;) {
    const batch = await db.prepare(`SELECT o.*,p.id AS p_id,p.name AS p_name,p.realm AS p_realm,p.class_id AS p_class_id,p.race_id AS p_race_id,p.level AS p_level
      FROM atlas_observations o LEFT JOIN atlas_profiles p ON p.id=o.profile_id
      WHERE p.public=1 AND p.user_id=o.user_id AND p.producer_id=o.producer_id AND EXISTS(SELECT 1 FROM atlas_grants g WHERE g.id=o.grant_id AND g.user_id=o.user_id AND g.producer_id=o.producer_id AND g.revoked_at IS NULL AND EXISTS(SELECT 1 FROM json_each(g.scopes) WHERE value='own_runs'))
      AND o.kind IN ('instance.entered','run.finished','run.interrupted') ORDER BY ${RUN_OBSERVATION_ORDER} LIMIT ? OFFSET ?`).bind(size, rows.length).all<Record<string, unknown>>();
    rows.push(...batch.results);
    if (batch.results.length < size) return rows;
  }
}

const PAGE_SIZE=40;
function paginate(entries: Entry[], params: URLSearchParams) {
  const search=(params.get("q")??"").trim().slice(0,80).toLocaleLowerCase("cs-CZ");
  const ranked=entries.map((entry,index)=>({...entry,rank:index+1}));
  const matches=search?ranked.filter(({character})=>`${character.name??""} ${character.realm??""} ${character.name??""}-${character.realm??""}`.toLocaleLowerCase("cs-CZ").includes(search)):ranked;
  const raw=Number(params.get("page"));
  const page=Number.isFinite(raw)?Math.max(0,Math.min(10000,Math.floor(raw))):0;
  return {entries:matches.slice(page*PAGE_SIZE,(page+1)*PAGE_SIZE),total:matches.length,page,pageSize:PAGE_SIZE,hasMore:(page+1)*PAGE_SIZE<matches.length};
}

/** Level ranking includes public profiles even when they have no recorded run. */
export async function rankPublicLevels(db: Db, params: URLSearchParams) {
  const rows:Record<string,unknown>[]=[];
  for (;;) {
    const batch=await db.prepare(`SELECT p.id,p.name,p.realm,p.class_id,p.race_id,p.level FROM atlas_profiles p
    WHERE p.public=1 AND p.level IS NOT NULL AND p.level>0 AND EXISTS(SELECT 1 FROM atlas_observations o
    JOIN atlas_grants g ON g.id=o.grant_id AND g.user_id=o.user_id AND g.producer_id=o.producer_id
    WHERE o.profile_id=p.id AND o.user_id=p.user_id AND o.producer_id=p.producer_id AND g.revoked_at IS NULL AND EXISTS(SELECT 1 FROM json_each(g.scopes) WHERE value='own_character')
    AND EXISTS(SELECT 1 FROM json_each(g.scopes) WHERE value=o.scope)) ORDER BY p.id ASC LIMIT ? OFFSET ?`).bind(1000,rows.length).all<Record<string, unknown>>();
    rows.push(...batch.results);
    if(batch.results.length<1000) break;
  }
  const filtered=rows.filter(r=>(!params.get("classId")||String(r.class_id)===params.get("classId"))&&(!params.get("raceId")||String(r.race_id)===params.get("raceId")))
    .map(r=>({rank:0,count:0,value:Number(r.level),character:{id:String(r.id),name:typeof r.name==="string"?r.name:null,realm:typeof r.realm==="string"?r.realm:null,classId:typeof r.class_id==="number"?r.class_id:null,raceId:typeof r.race_id==="number"?r.race_id:null,level:Number(r.level)}}));
  filtered.sort((a,b)=>b.value-a.value||a.character.id.localeCompare(b.character.id));
  return {...paginate(filtered,params),sampleSize:filtered.length,countingUnit:"character",rulesLabel:"Public character levels; ties ordered by profile ID. Item level is not available."};
}

export function rankObservedRuns(runs: readonly Run[], params: URLSearchParams) {
  const wanted=params.get("metric");
  const metric=wanted==="time"||wanted==="dps"||wanted==="hps"?wanted:"count";
  const filtered=runs.filter(run=>{
    const c=run.character;
    return c&&run.status==="completed"&&["last_boss","full_clear"].includes(run.completion??"")&&run.evidence!=="manual"&&
      (!params.get("classId")||String(c.classId)===params.get("classId"))&&
      (!params.get("raceId")||String(c.raceId)===params.get("raceId"))&&
      (!params.get("instanceId")||String(run.instanceId)===params.get("instanceId"))&&
      (!params.get("instanceType")||run.instanceType===params.get("instanceType"))&&
      (!params.get("difficultyId")||String(run.difficultyId)===params.get("difficultyId"))&&
      (!params.get("completion")||run.completion===params.get("completion"));
  });
  const note="Observed public participations, not verified competitive scores or unique group runs. DPS/HPS use attributable recorded combat seconds; partial data is excluded.";
  if(metric!=="count"&&!params.get("instanceId"))return {...paginate([],params),sampleSize:filtered.length,countingUnit:"participation",rulesLabel:"Select one instance to compare times or combat rates. "+note};
  const grouped=new Map<string,Entry>();
  for(const run of filtered){
    const c=run.character!;
    let value:number|undefined;
    if(metric==="time")value=typeof run.durationMs==="number"&&run.durationMs>0?run.durationMs:undefined;
    if(metric==="dps"||metric==="hps"){
      const combat=run.combat;
      if(combat?.coverage!=="observed"||!["damage_meter","combat_log"].includes(combat.source))continue;
      const player=combat.players.find(p=>p.guid===c.id);
      const amount=metric==="dps"?player?.damage:player?.healing;
      const ms=player?.activeMs??combat.activeMs;
      if(amount==null||!Number.isFinite(amount)||amount<0||!Number.isFinite(ms)||ms<=0)continue;
      value=amount/(ms/1000);
    }
    if(metric!=="count"&&value===undefined)continue;
    let entry=grouped.get(c.id);
    if(!entry){entry={rank:0,character:c,count:0,bestMs:null};grouped.set(c.id,entry);}
    entry.count++;
    if(typeof run.durationMs==="number"&&run.durationMs>0)entry.bestMs=entry.bestMs==null?run.durationMs:Math.min(entry.bestMs,run.durationMs);
    if(value!==undefined&&(entry.value==null||(metric==="time"?value<entry.value:value>entry.value))){entry.value=value;entry.runId=run.id;entry.instanceName=run.name;}
  }
  const entries=[...grouped.values()].sort((a,b)=>metric==="count"?b.count-a.count||a.character.id.localeCompare(b.character.id):metric==="time"?(a.value??Infinity)-(b.value??Infinity):(b.value??0)-(a.value??0));
  return {...paginate(entries,params),sampleSize:filtered.length,countingUnit:"participation",rulesLabel:note};
}

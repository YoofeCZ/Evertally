import type { Run, Entry } from "../components/evertally/types";
import type { Db } from "./people";
import { factionOf } from "../components/evertally/data";
import { averageItemLevel } from "./item-level";

const factionMatches=(params:URLSearchParams,raceId:unknown)=>{const wanted=params.get("faction");return !wanted||factionOf(typeof raceId==="number"?raceId:null)===wanted;};
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

export type RankingExtras = { itemLevel?: number; guild?: string };

const decode = (value: unknown): Record<string, unknown> | null => { try { const v = JSON.parse(String(value)); return v && typeof v === "object" ? v as Record<string, unknown> : null; } catch { return null; } };
// The latest observation of one kind per profile, only for a public character whose player turned the detail on,
// and only while the grant that carried it is live and still includes its scope.
const latestPerProfile = (kind: string, flag: string, scope: string, count: number) => `SELECT profile_id,payload FROM (
  SELECT o.profile_id,o.payload,ROW_NUMBER() OVER (PARTITION BY o.profile_id ORDER BY o.observed_at DESC,o.id DESC) AS n
  FROM atlas_observations o JOIN atlas_profiles p ON p.id=o.profile_id AND p.user_id=o.user_id AND p.producer_id=o.producer_id
  JOIN atlas_grants g ON g.id=o.grant_id AND g.user_id=o.user_id AND g.producer_id=o.producer_id
  WHERE o.profile_id IN (${Array(count).fill("?").join(",")}) AND o.kind='${kind}' AND p.public=1 AND p.${flag}=1
  AND g.revoked_at IS NULL AND EXISTS(SELECT 1 FROM json_each(g.scopes) WHERE value='${scope}')
) WHERE n=1`;

/**
 * Item level and guild name of public characters whose players chose to show them in the leaderboard.
 * Only the computed average leaves the armory, never the gear; a character that left its guild shows none.
 */
export async function rankingExtras(db: Db, ids: readonly string[]): Promise<Map<string, RankingExtras>> {
  const out = new Map<string, RankingExtras>();
  const unique = [...new Set(ids)];
  for (let at = 0; at < unique.length; at += 90) {
    const chunk = unique.slice(at, at + 90);
    const [armory, guild] = await Promise.all([
      db.prepare(latestPerProfile("armory.snapshot", "show_item_level", "own_character", chunk.length)).bind(...chunk).all<Record<string, unknown>>(),
      db.prepare(latestPerProfile("guild.snapshot", "show_guild", "guild_share", chunk.length)).bind(...chunk).all<Record<string, unknown>>(),
    ]);
    for (const row of armory.results) {
      const equipped = decode(row.payload)?.equipped;
      const level = Array.isArray(equipped) ? averageItemLevel(equipped as { slot: number; itemId: number }[]) : null;
      if (level != null) out.set(String(row.profile_id), { ...out.get(String(row.profile_id)), itemLevel: level });
    }
    for (const row of guild.results) {
      const payload = decode(row.payload);
      const name = payload && payload.left !== true && typeof payload.guildName === "string" ? payload.guildName.trim().slice(0, 48) : "";
      if (name) out.set(String(row.profile_id), { ...out.get(String(row.profile_id)), guild: name });
    }
  }
  return out;
}

/** Adds the opted-in item level and guild to the entries of one page. */
export async function withRankingExtras<T extends { entries: Entry[] }>(db: Db, result: T): Promise<T> {
  const extras = await rankingExtras(db, result.entries.map(e => e.character.id));
  return extras.size ? { ...result, entries: result.entries.map(e => ({ ...e, ...extras.get(e.character.id) })) } : result;
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
    const batch=await db.prepare(`SELECT p.id,p.name,p.realm,p.class_id,p.race_id,p.level,p.show_item_level,p.show_guild FROM atlas_profiles p
    WHERE p.public=1 AND p.level IS NOT NULL AND p.level>0 AND EXISTS(SELECT 1 FROM atlas_observations o
    JOIN atlas_grants g ON g.id=o.grant_id AND g.user_id=o.user_id AND g.producer_id=o.producer_id
    WHERE o.profile_id=p.id AND o.user_id=p.user_id AND o.producer_id=p.producer_id AND g.revoked_at IS NULL AND EXISTS(SELECT 1 FROM json_each(g.scopes) WHERE value='own_character')
    AND EXISTS(SELECT 1 FROM json_each(g.scopes) WHERE value=o.scope)) ORDER BY p.id ASC LIMIT ? OFFSET ?`).bind(1000,rows.length).all<Record<string, unknown>>();
    rows.push(...batch.results);
    if(batch.results.length<1000) break;
  }
  const filtered=rows.filter(r=>(!params.get("classId")||String(r.class_id)===params.get("classId"))&&(!params.get("raceId")||String(r.race_id)===params.get("raceId"))&&factionMatches(params,r.race_id))
    .map(r=>({rank:0,count:0,value:Number(r.level),character:{id:String(r.id),name:typeof r.name==="string"?r.name:null,realm:typeof r.realm==="string"?r.realm:null,classId:typeof r.class_id==="number"?r.class_id:null,raceId:typeof r.race_id==="number"?r.race_id:null,level:Number(r.level)}}));
  // like Raider.IO: level first, then the item level of those who show it, then a stable order
  const extras=await rankingExtras(db,rows.filter(r=>Number(r.show_item_level)===1||Number(r.show_guild)===1).map(r=>String(r.id)));
  const ranked:Entry[]=filtered.map(e=>({...e,...extras.get(e.character.id)}));
  ranked.sort((a,b)=>(b.value??0)-(a.value??0)||(b.itemLevel??-1)-(a.itemLevel??-1)||a.character.id.localeCompare(b.character.id));
  return {...paginate(ranked,params),sampleSize:ranked.length,countingUnit:"character",rulesLabel:"Public character levels; equal levels by the item level of players who show it, then by profile ID."};
}

export function rankObservedRuns(runs: readonly Run[], params: URLSearchParams) {
  const wanted=params.get("metric");
  const metric=wanted==="time"||wanted==="dps"||wanted==="hps"?wanted:"count";
  const filtered=runs.filter(run=>{
    const c=run.character;
    return c&&run.status==="completed"&&["last_boss","full_clear"].includes(run.completion??"")&&run.evidence!=="manual"&&
      (!params.get("classId")||String(c.classId)===params.get("classId"))&&
      (!params.get("raceId")||String(c.raceId)===params.get("raceId"))&&
      factionMatches(params,c.raceId)&&
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

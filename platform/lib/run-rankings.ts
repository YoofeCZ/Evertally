import type { Run, Entry } from "../components/evertally/types";
import type { Db } from "./people";
import { completed, factionOf } from "../components/evertally/data";
import { averageItemLevel } from "./item-level";
import { rolesFor, specOf, type Role } from "./spec";

const factionMatches=(params:URLSearchParams,raceId:unknown)=>{const wanted=params.get("faction");return !wanted||factionOf(typeof raceId==="number"?raceId:null)===wanted;};
/** One key for a realm however it is written ("Golem Agg", "GolemAgg", "golem-agg"). */
export const realmKey=(realm:unknown)=>String(realm??"").replace(/[\s'-]/g,"").toLowerCase();
const realmMatches=(params:URLSearchParams,realm:unknown)=>{const wanted=params.get("realm");return !wanted||realmKey(realm)===realmKey(wanted);};
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

export type RankingExtras = { itemLevel?: number; guild?: string; spec?: string; specIndex?: number; specPoints?: string };

const decode = (value: unknown): Record<string, unknown> | null => { try { const v = JSON.parse(String(value)); return v && typeof v === "object" ? v as Record<string, unknown> : null; } catch { return null; } };
// The latest observation of one kind per profile, only for a public character whose player turned the detail on,
// and only while the grant that carried it is live and still includes its scope.
const latestPerProfile = (kind: string, flag: string, scope: string, count: number) => `SELECT profile_id,payload,show_item_level,show_gear FROM (
  SELECT o.profile_id,o.payload,p.show_item_level,p.show_gear,ROW_NUMBER() OVER (PARTITION BY o.profile_id ORDER BY o.observed_at DESC,o.id DESC) AS n
  FROM atlas_observations o JOIN atlas_profiles p ON p.id=o.profile_id AND p.user_id=o.user_id AND p.producer_id=o.producer_id
  JOIN atlas_grants g ON g.id=o.grant_id AND g.user_id=o.user_id AND g.producer_id=o.producer_id
  WHERE o.profile_id IN (${Array(count).fill("?").join(",")}) AND o.kind='${kind}' AND p.public=1 AND (${flag})
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
      db.prepare(latestPerProfile("armory.snapshot", "p.show_item_level=1 OR p.show_gear=1", "own_character", chunk.length)).bind(...chunk).all<Record<string, unknown>>(),
      db.prepare(latestPerProfile("guild.snapshot", "p.show_guild=1", "guild_share", chunk.length)).bind(...chunk).all<Record<string, unknown>>(),
    ]);
    for (const row of armory.results) {
      const payload = decode(row.payload);
      const id = String(row.profile_id);
      // the average item level only with its own switch; the specialisation only with "gear and talents"
      if (Number(row.show_item_level) === 1) {
        const equipped = payload?.equipped;
        const level = Array.isArray(equipped) ? averageItemLevel(equipped as { slot: number; itemId: number }[]) : null;
        if (level != null) out.set(id, { ...out.get(id), itemLevel: level });
      }
      const spec = Number(row.show_gear) === 1 ? specOf(payload?.talents) : null;
      if (spec) out.set(id, { ...out.get(id), spec: spec.name, specIndex: spec.index, specPoints: spec.points });
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
  // the guild counts only where the player chose to show it (it is on the entry only then)
  const matches=search?ranked.filter(({character,guild})=>`${character.name??""} ${character.realm??""} ${character.name??""}-${character.realm??""} ${guild??""}`.toLocaleLowerCase("cs-CZ").includes(search)):ranked;
  const raw=Number(params.get("page"));
  const page=Number.isFinite(raw)?Math.max(0,Math.min(10000,Math.floor(raw))):0;
  return {entries:matches.slice(page*PAGE_SIZE,(page+1)*PAGE_SIZE),total:matches.length,page,pageSize:PAGE_SIZE,hasMore:(page+1)*PAGE_SIZE<matches.length};
}

/** Level ranking includes public profiles even when they have no recorded run. The whole board, ranked. */
export async function levelBoard(db: Db, params: URLSearchParams): Promise<Entry[]> {
  const rows:Record<string,unknown>[]=[];
  for (;;) {
    const batch=await db.prepare(`SELECT p.id,p.name,p.realm,p.class_id,p.race_id,p.level,p.show_item_level,p.show_guild,p.show_gear FROM atlas_profiles p
    WHERE p.public=1 AND p.level IS NOT NULL AND p.level>0 AND EXISTS(SELECT 1 FROM atlas_observations o
    JOIN atlas_grants g ON g.id=o.grant_id AND g.user_id=o.user_id AND g.producer_id=o.producer_id
    WHERE o.profile_id=p.id AND o.user_id=p.user_id AND o.producer_id=p.producer_id AND g.revoked_at IS NULL AND EXISTS(SELECT 1 FROM json_each(g.scopes) WHERE value='own_character')
    AND EXISTS(SELECT 1 FROM json_each(g.scopes) WHERE value=o.scope)) ORDER BY p.id ASC LIMIT ? OFFSET ?`).bind(1000,rows.length).all<Record<string, unknown>>();
    rows.push(...batch.results);
    if(batch.results.length<1000) break;
  }
  const filtered=rows.filter(r=>(!params.get("classId")||String(r.class_id)===params.get("classId"))&&(!params.get("raceId")||String(r.race_id)===params.get("raceId"))&&factionMatches(params,r.race_id)&&realmMatches(params,r.realm))
    .map(r=>({rank:0,count:0,value:Number(r.level),character:{id:String(r.id),name:typeof r.name==="string"?r.name:null,realm:typeof r.realm==="string"?r.realm:null,classId:typeof r.class_id==="number"?r.class_id:null,raceId:typeof r.race_id==="number"?r.race_id:null,level:Number(r.level)}}));
  // like Raider.IO: level first, then the item level of those who show it, then a stable order
  const extras=await rankingExtras(db,rows.filter(r=>Number(r.show_item_level)===1||Number(r.show_guild)===1||Number(r.show_gear)===1).map(r=>String(r.id)));
  const withRoles:Entry[]=filtered.map(e=>{const x=extras.get(e.character.id);const roles=x?.specIndex?rolesFor(e.character.classId,{index:x.specIndex,name:x.spec??""}):[];return {...e,...x,...(roles.length?{roles}:{})};});
  // a role filter keeps only characters whose players show their talents
  const role=params.get("role");
  const ranked:Entry[]=role?withRoles.filter(e=>(e.roles??[]).includes(role as Role)):withRoles;
  ranked.sort((a,b)=>(b.value??0)-(a.value??0)||(b.itemLevel??-1)-(a.itemLevel??-1)||a.character.id.localeCompare(b.character.id));
  return ranked;
}

export async function rankPublicLevels(db: Db, params: URLSearchParams) {
  const ranked=await levelBoard(db,params);
  return {...paginate(ranked,params),sampleSize:ranked.length,countingUnit:"character",rulesLabel:"Public character levels; equal levels by the item level of players who show it, then by profile ID."};
}

export const RANKING_PACKAGE_MAX = 2000;
export const RANKING_PACKAGE_DAYS = 3;
/**
 * The public leaderboard as the game reads it (Evertally Sync writes it into RankingData.lua for the unit tooltip).
 * Only what the website already shows to everyone: name, realm, level, class, race, place on the level board and in
 * the class, completed public runs, and item level and guild only where the player chose to show them. No account or
 * profile identifiers.
 */
export async function rankingPackage(db: Db, runs: readonly Run[], at = Math.floor(Date.now() / 1000)) {
  const board = await levelBoard(db, new URLSearchParams());
  const done = new Map<string, number>();
  for (const run of runs) if (run.character && completed(run)) done.set(run.character.id, (done.get(run.character.id) ?? 0) + 1);
  const inClass = new Map<number, number>();
  const players = [];
  for (let i = 0; i < board.length; i++) {
    const e = board[i], c = e.character, cls = c.classId ?? 0;
    const classRank = (inClass.get(cls) ?? 0) + 1;
    inClass.set(cls, classRank);
    if (players.length >= RANKING_PACKAGE_MAX || !c.name || !c.realm) continue;
    players.push({ name: c.name, realm: c.realm, level: c.level ?? null, classId: c.classId ?? null, raceId: c.raceId ?? null, rank: i + 1, classRank,
      completed: done.get(c.id) ?? 0, ...(e.itemLevel != null ? { itemLevel: e.itemLevel } : {}), ...(e.guild ? { guild: e.guild } : {}) });
  }
  return { schemaVersion: 1, kind: "evertally-ranking", game: { product: "forever" }, generatedAt: at, expiresAt: at + RANKING_PACKAGE_DAYS * 86400,
    total: board.length, truncated: board.length > players.length, players };
}

/** Finished public runs that count for a board, with the board's filters applied. */
function rankableRuns(runs: readonly Run[], params: URLSearchParams): Run[] {
  return runs.filter(run=>{
    const c=run.character;
    return c&&run.status==="completed"&&["last_boss","full_clear"].includes(run.completion??"")&&run.evidence!=="manual"&&
      (!params.get("classId")||String(c.classId)===params.get("classId"))&&
      (!params.get("raceId")||String(c.raceId)===params.get("raceId"))&&
      factionMatches(params,c.raceId)&&realmMatches(params,c.realm)&&
      (!params.get("instanceId")||String(run.instanceId)===params.get("instanceId"))&&
      (!params.get("instanceType")||run.instanceType===params.get("instanceType"))&&
      (!params.get("difficultyId")||String(run.difficultyId)===params.get("difficultyId"))&&
      (!params.get("completion")||run.completion===params.get("completion"));
  });
}

export type InstanceSummary = { instanceId: number; name: string; instanceType: string | null; runs: number; players: number; bestMs: number | null; holder: Entry["character"] | null; lastAt: number | null };
/** One card per instance for the dungeon overview: how often it was finished, by how many characters, and the record. */
export function instanceSummary(runs: readonly Run[], params: URLSearchParams): { instances: InstanceSummary[]; sampleSize: number } {
  const filtered = rankableRuns(runs, params);
  const byInstance = new Map<number, InstanceSummary & { ids: Set<string> }>();
  for (const run of filtered) {
    if (typeof run.instanceId !== "number" || run.instanceId <= 0) continue;
    let row = byInstance.get(run.instanceId);
    if (!row) { row = { instanceId: run.instanceId, name: run.name, instanceType: run.instanceType ?? null, runs: 0, players: 0, bestMs: null, holder: null, lastAt: null, ids: new Set() }; byInstance.set(run.instanceId, row); }
    row.runs++;
    row.ids.add(run.character!.id);
    if (typeof run.durationMs === "number" && run.durationMs > 0 && (row.bestMs === null || run.durationMs < row.bestMs)) { row.bestMs = run.durationMs; row.holder = run.character!; }
    if (typeof run.startedAt === "number" && (row.lastAt === null || run.startedAt > row.lastAt)) row.lastAt = run.startedAt;
  }
  const instances = [...byInstance.values()].map(({ ids, ...row }) => ({ ...row, players: ids.size }))
    .sort((a, b) => b.runs - a.runs || a.name.localeCompare(b.name));
  return { instances, sampleSize: filtered.length };
}

export function rankObservedRuns(runs: readonly Run[], params: URLSearchParams) {
  const wanted=params.get("metric");
  const metric=wanted==="time"||wanted==="dps"||wanted==="hps"?wanted:"count";
  const filtered=rankableRuns(runs,params);
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

export type RealmSummary = { realm: string; characters: number; maxLevel: number | null; guilds: number };
/** Every realm with public characters on the level board: how many, the highest level, and how many guilds they show. */
export async function realmSummary(db: Db): Promise<{ realms: RealmSummary[] }> {
  const board = await levelBoard(db, new URLSearchParams());
  const by = new Map<string, RealmSummary & { guildNames: Set<string> }>();
  for (const e of board) {
    const realm = e.character.realm?.trim();
    if (!realm) continue;
    const key = realmKey(realm);
    const row = by.get(key) ?? { realm, characters: 0, maxLevel: null, guilds: 0, guildNames: new Set<string>() };
    row.characters++;
    if (typeof e.character.level === "number") row.maxLevel = Math.max(row.maxLevel ?? 0, e.character.level);
    if (e.guild) row.guildNames.add(e.guild.trim().toLowerCase());
    by.set(key, row);
  }
  return { realms: [...by.values()].map(({ guildNames, ...row }) => ({ ...row, guilds: guildNames.size }))
    .sort((a, b) => b.characters - a.characters || (b.maxLevel ?? 0) - (a.maxLevel ?? 0) || a.realm.localeCompare(b.realm)) };
}

export type Count = { id: number; count: number };
export type Statistics = {
  characters: number; classes: Count[]; races: Count[]; factions: { alliance: number; horde: number; unknown: number };
  levels: { from: number; to: number; count: number }[];
  /** Completed public runs by the class of the character, apart for dungeons and raids. */
  runs: { total: number; party: Count[]; raid: Count[] };
  /** Only characters whose players show their talents; `unknown` are the others. */
  roles: { tank: number; healer: number; dps: number; unknown: number };
};
const LEVEL_BRACKETS: readonly [number, number][] = [[1, 9], [10, 19], [20, 29], [30, 39], [40, 49], [50, 59], [60, 69], [70, 80]];
const counted = (map: Map<number, number>): Count[] => [...map].map(([id, count]) => ({ id, count })).sort((a, b) => b.count - a.count || a.id - b.id);
/** Classes, races, factions and levels of the public characters, and who finishes the runs; the faction and realm filters apply. */
export async function statistics(db: Db, runs: readonly Run[], params: URLSearchParams): Promise<Statistics> {
  const board = await levelBoard(db, params);
  const classes = new Map<number, number>(), races = new Map<number, number>();
  const factions = { alliance: 0, horde: 0, unknown: 0 };
  const roles = { tank: 0, healer: 0, dps: 0, unknown: 0 };
  const levels = LEVEL_BRACKETS.map(([from, to]) => ({ from, to, count: 0 }));
  for (const e of board) {
    const c = e.character;
    if (c.classId) classes.set(c.classId, (classes.get(c.classId) ?? 0) + 1);
    if (c.raceId) races.set(c.raceId, (races.get(c.raceId) ?? 0) + 1);
    factions[factionOf(c.raceId ?? null) ?? "unknown"]++;
    if (e.roles?.length) for (const r of e.roles) roles[r]++; else roles.unknown++;
    const bracket = levels.find(b => (c.level ?? 0) >= b.from && (c.level ?? 0) <= b.to);
    if (bracket) bracket.count++;
  }
  const party = new Map<number, number>(), raid = new Map<number, number>();
  const finished = rankableRuns(runs, params);
  for (const run of finished) {
    const id = run.character?.classId;
    if (!id) continue;
    const into = run.instanceType === "raid" ? raid : party;
    into.set(id, (into.get(id) ?? 0) + 1);
  }
  return { characters: board.length, classes: counted(classes), races: counted(races), factions,
    levels: levels.filter(b => b.count > 0 || b.to <= 60), runs: { total: finished.length, party: counted(party), raid: counted(raid) }, roles };
}

import type { Db } from "./people";
export type Position = {mapId:number;x:number;y:number;at:number;live?:boolean};
export const LIVE_TTL=30;
/** Only named, authorized profiles requested by the caller; never a public location feed. */
export async function livePositions(db:Db,ids:string[],needs:string[],at=Math.floor(Date.now()/1000)):Promise<Map<string,Position>> {
  if(!ids.length)return new Map();
  const scopes=[...new Set(["own_track","own_character",...needs])];
  if(scopes.some(s=>!["world_facts","own_runs","own_character","own_professions","own_track","guild_share"].includes(s)))throw new Error("Unknown live position scope");
  const rows=await db.prepare(`SELECT l.* FROM et_live_positions l
    JOIN atlas_grants g ON g.id=l.grant_id AND g.user_id=l.user_id
    JOIN et_devices d ON d.id=l.device_id AND d.user_id=l.user_id
    WHERE l.profile_id IN (SELECT value FROM json_each(?)) AND l.expires_at>? AND g.revoked_at IS NULL AND d.revoked_at IS NULL
    AND ${scopes.map(s=>`EXISTS(SELECT 1 FROM json_each(g.scopes) WHERE value='${s}') AND EXISTS(SELECT 1 FROM json_each(d.scopes) WHERE value='${s}')`).join(" AND ")}`)
    .bind(JSON.stringify(ids),at).all();
  return new Map(rows.results.map(row=>[String(row.profile_id),{mapId:Number(row.map_id),x:Number(row.x),y:Number(row.y),at:Number(row.observed_at),live:true}]));
}

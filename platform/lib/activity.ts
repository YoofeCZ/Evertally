export const ACTIVITY_SQL=`SELECT CAST(json_extract(o.payload,'$.mapId') AS INTEGER) AS mapId,
 COUNT(DISTINCT o.user_id) AS contributors,COUNT(*) AS observations,
 CAST(MAX(o.observed_at)/86400 AS INTEGER)*86400 AS lastSeen
 FROM atlas_observations o
 JOIN atlas_grants g ON g.id=o.grant_id AND g.user_id=o.user_id AND g.producer_id=o.producer_id
 WHERE o.kind='zone.visited' AND o.scope='world_facts' AND o.observed_at>=? AND o.observed_at<=?
 AND g.revoked_at IS NULL AND EXISTS(SELECT 1 FROM json_each(g.scopes) WHERE value='world_facts')
 AND json_extract(o.payload,'$.mapSystem')='ui_map'
 AND json_type(o.payload,'$.mapId')='integer' AND json_extract(o.payload,'$.mapId')>0
 GROUP BY mapId HAVING COUNT(DISTINCT o.user_id)>=3
 ORDER BY contributors DESC,mapId LIMIT 1000`;
export function activitySnapshot(rows:Record<string,unknown>[],now:number){
 return {generatedAt:now,windowHours:24,minContributors:3,zones:rows.filter(r=>typeof r.mapId==="number"&&Number.isSafeInteger(r.mapId)&&r.mapId>0&&Number(r.contributors)>=3).map(r=>({mapId:Number(r.mapId),mapSystem:"ui_map" as const,contributors:Number(r.contributors),observations:Number(r.observations),lastSeen:Math.floor(Number(r.lastSeen)/86400)*86400}))};
}

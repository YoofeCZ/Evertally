import {characterSchema,payloadSchemas} from "./contracts";

export const PROFESSION_ROWS_SQL = `WITH recent AS (
 SELECT id,producer_id,kind,payload,character_data,observed_at FROM atlas_observations
 WHERE user_id=? AND scope='own_professions' ORDER BY observed_at DESC,id DESC LIMIT 2000
), sized AS (
 SELECT *,SUM(length(CAST(payload AS BLOB))+COALESCE(length(CAST(character_data AS BLOB)),0))
 OVER(ORDER BY observed_at DESC,id DESC) AS bytes FROM recent
)
SELECT id,producer_id,kind,payload,character_data,observed_at FROM sized
WHERE bytes<=2097152 ORDER BY observed_at DESC,id DESC`;
export const PROFESSION_COUNT_SQL="SELECT COUNT(*) AS count FROM atlas_observations WHERE user_id=? AND scope='own_professions'";
type Row=Record<string,unknown>;
type Character=ReturnType<typeof characterSchema.parse>;
type Profession={professionId:number;name?:string;skill:number|null;maxSkill:number|null;observedAt:number;recipes:{recipeId:number;name?:string;learned?:boolean}[]};
type Craft={recipeId:number;itemId?:number;quantity?:number;professionId?:number;observedAt:number};
type Cooldown={recipeId:number;readyAt:number;observedAt:number};
type Bucket={id:string;character:Character|null;professions:Profession[];crafts:Craft[];cooldowns:Cooldown[]};
function decode(value:unknown):unknown {if(typeof value!=="string")return value;try{return JSON.parse(value);}catch{return null;}}

/** Owner-only observations; absent identity remains absent instead of inventing an alt. */
export function buildProfessionData(rows:readonly Row[],totalObservations:number,generatedAt:number) {
 const buckets=new Map<string,Bucket>();
 const seenProfessions=new Set<string>(),seenCooldowns=new Set<string>();
 const sorted=[...rows].sort((a,b)=>Number(b.observed_at)-Number(a.observed_at)||String(b.id).localeCompare(String(a.id)));
 for(const row of sorted){
  if(typeof row.producer_id!=="string"||typeof row.observed_at!=="number"||!Number.isFinite(row.observed_at)||row.observed_at<0)continue;
  const kind=row.kind;if(kind!=="profession.snapshot"&&kind!=="craft.result"&&kind!=="cooldown.snapshot")continue;
  const parsed=payloadSchemas[kind].safeParse(decode(row.payload));if(!parsed.success)continue;
  const identity=characterSchema.safeParse(decode(row.character_data));const character=identity.success?identity.data:null;
  const id=JSON.stringify([row.producer_id,character?.id??null]);
  let bucket=buckets.get(id);if(!bucket){bucket={id,character,professions:[],crafts:[],cooldowns:[]};buckets.set(id,bucket);}
  const observedAt=row.observed_at;
  if(kind==="profession.snapshot"){
   const p=payloadSchemas[kind].parse(parsed.data);const key=JSON.stringify([id,p.professionId]);
   if(seenProfessions.has(key))continue;seenProfessions.add(key);
   bucket.professions.push({...p,skill:p.skill??null,maxSkill:p.maxSkill??null,observedAt});
  }else if(kind==="craft.result"){
   const p=payloadSchemas[kind].parse(parsed.data);bucket.crafts.push({...p,observedAt});
  }else{
   const p=payloadSchemas[kind].parse(parsed.data);const key=JSON.stringify([id,p.recipeId]);
   if(seenCooldowns.has(key))continue;seenCooldowns.add(key);bucket.cooldowns.push({...p,observedAt});
  }
 }
 return {generatedAt,totalObservations,sampledObservations:rows.length,truncated:rows.length<totalObservations,characters:[...buckets.values()]};
}

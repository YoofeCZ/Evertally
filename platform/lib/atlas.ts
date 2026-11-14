import { worldPayload } from "./world-privacy";
type Row=Record<string,unknown>;
type Location={mapId:number;mapSystem:"ui_map";positionMethod:string;x?:number;y?:number;count:number;lastSeen:number};
type Entity={id:string;kind:string;name:string;count:number;lastSeen:number;payload:Record<string,unknown>;locations:Location[]};
const coordinate=(v:unknown):v is number=>typeof v==="number"&&Number.isFinite(v)&&v>=0&&v<=1;
export function atlasEntities(rows:Row[],kind="",search=""):Entity[]{
 const entities=new Map<string,Entity>();
 for(const row of rows){
  let raw:Record<string,unknown>;try{raw=JSON.parse(String(row.payload))}catch{continue}
  const eventKind=String(row.kind);
  if(!/^(quest\.|npc\.observed$|vendor\.snapshot$|loot\.received$)/.test(eventKind))continue;
  const k=eventKind.startsWith("quest.")?"quest":eventKind.startsWith("npc.")||eventKind.startsWith("vendor.")?"npc":"item";
  const id=raw.questId??raw.npcId??raw.itemId;if(typeof id!=="number"||!Number.isSafeInteger(id)||id<=0)continue;
  const key=k+":"+id,payload=worldPayload(eventKind,raw),seen=Math.floor(Number(row.observed_at)/86400)*86400;
  if(!Number.isFinite(seen))continue;
  let entity=entities.get(key);
  if(!entity){entity={id:String(id),kind:k,name:String(raw.title??raw.name??`${k} #${id}`),count:0,lastSeen:seen,payload,locations:[]};entities.set(key,entity)}
  entity.count++;
  // Preserve the newest actual vendor inventory even if a later interaction only
  // observes the same NPC's name/zone. It remains reference stock, never live stock.
  if(eventKind==="vendor.snapshot"&&!Array.isArray(entity.payload.items)&&Array.isArray(payload.items)){
    entity.payload.items=payload.items;entity.payload.sourceKind="vendor";entity.payload.inventoryObservedAt=seen;
  }
  if(typeof payload.mapId==="number"&&Number.isSafeInteger(payload.mapId)&&payload.mapId>0){
   const exact=eventKind==="npc.observed"&&payload.positionMethod==="unit_position"&&coordinate(payload.x)&&coordinate(payload.y);
   const point:Location={mapId:payload.mapId,mapSystem:"ui_map",positionMethod:exact?"unit_position":"zone_only",count:1,lastSeen:seen,...(exact?{x:payload.x as number,y:payload.y as number}:{})};
   const prior=entity.locations.find(p=>p.mapId===point.mapId&&p.x===point.x&&p.y===point.y&&p.positionMethod===point.positionMethod);
   if(prior)prior.count++;else if(entity.locations.length<100)entity.locations.push(point);
  }
 }
 const query=search.toLocaleLowerCase();return [...entities.values()].filter(e=>(!kind||e.kind===kind)&&(!query||`${e.name} ${e.id}`.toLocaleLowerCase().includes(query))).slice(0,1000);
}

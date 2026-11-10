import { z } from "zod";

// own_track = the player's own route (private to the account); guild_share = guild identity, and for a guild
// master the roster, so that members confirmed on the website can see each other. Both are off by default.
export const SCOPES = ["world_facts", "own_runs", "own_character", "own_professions", "own_track", "guild_share"] as const;
export type Scope = typeof SCOPES[number];
const id = z.string().min(1).max(180);
const text = z.string().max(240);
const num = z.number().finite().nonnegative();
const integer = num.int();
const entityId = integer.positive();
const coordinate = z.number().finite().min(0).max(1);
export const characterSchema = z.object({id, name:text.optional(),realm:text.optional(),classId:entityId.optional(),raceId:entityId.optional(),level:integer.max(1000).optional()}).strict();
const location = {mapId:entityId.optional(),mapSystem:z.literal("ui_map").optional(),mapName:text.optional(),x:coordinate.optional(),y:coordinate.optional()};
const characterPayload = z.object({level:integer.max(1000).optional(),classId:entityId.optional(),raceId:entityId.optional(),name:text.optional(),realm:text.optional()}).strict();
const questPayload=z.object({questId:entityId,title:text.optional(),xp:num.optional(),money:num.optional(),npcId:entityId.optional(),...location}).strict();
const npcPayload=z.object({npcId:entityId,name:text.optional(),...location,positionMethod:z.enum(["player_interaction","unit_position","unknown"]).optional(),level:integer.max(1000).optional()}).strict();
const vendorPayload=z.object({npcId:entityId,name:text.optional(),items:z.array(z.object({itemId:entityId,name:text.optional(),price:num.optional(),quantity:z.number().finite().min(-1).optional()}).strict()).max(1000),...location}).strict();
const lootPayload=z.object({itemId:entityId,name:text.optional(),quantity:integer.positive().max(1000000),sourceNpcId:entityId.optional(),sourceKind:z.enum(["corpse","object","gathering","craft","quest","unknown"]).optional(),sourceCertain:z.boolean().optional()}).strict();
const professionPayload=z.object({professionId:entityId,name:text.optional(),skill:integer.optional(),maxSkill:integer.optional(),recipes:z.array(z.object({recipeId:entityId,name:text.optional(),learned:z.boolean().optional()}).strict()).max(10000)}).strict();
const craftPayload=z.object({recipeId:entityId,itemId:entityId.optional(),quantity:integer.positive().optional(),professionId:entityId.optional()}).strict();
const cooldownPayload=z.object({recipeId:entityId,readyAt:num}).strict();
const runPayload=z.object({runId:id,instanceId:integer.optional(),name:text.optional(),instanceType:z.enum(["party","raid"]).optional(),difficultyId:integer.optional(),startedAt:num,endedAt:num.optional(),durationMs:num.max(604800000).optional(),status:z.enum(["visiting","completed","interrupted","manual","abandoned"]),completion:z.enum(["unknown","last_boss","full_clear"]).optional(),rankEligible:z.boolean().optional(),rulesetId:text.optional(),groupSize:integer.max(80).optional(),maxLevel:integer.max(1000).optional(),minLevel:integer.max(1000).optional(),deaths:integer.optional(),bossCount:integer.max(1000).optional(),bosses:z.array(z.object({encounterId:integer.optional(),name:text.optional(),killedAt:num.optional()}).strict()).max(1000).optional()}).strict().superRefine((p,ctx)=>{if(p.endedAt!==undefined&&p.endedAt<p.startedAt)ctx.addIssue({code:z.ZodIssueCode.custom,message:"Run end precedes its start."});});
const encounterPayload=z.object({encounterId:entityId,name:text.optional(),success:z.boolean(),durationMs:num.max(86400000).optional(),instanceId:integer.optional(),instanceName:text.optional()}).strict();
const zonePayload=z.object({mapId:entityId,mapSystem:z.literal("ui_map"),mapName:text.optional()}).strict();
// One walked stretch inside a single map: points are [seconds since startedAt, x, y] with x,y as 0..1 map fractions.
export const TRACK_MAX_POINTS=120;
const trackPayload=z.object({mapId:entityId,mapSystem:z.literal("ui_map").optional(),startedAt:num,points:z.array(z.tuple([integer.max(86400),coordinate,coordinate])).min(1).max(TRACK_MAX_POINTS)}).strict();
// Guild identity of the own character. Only a guild master (rankIndex 0) may send the roster.
export const GUILD_ROSTER_MAX=1000;
const guildPayload=z.object({left:z.literal(true).optional(),guildName:text.optional(),rankIndex:integer.max(100).optional(),rankName:text.optional(),
  roster:z.array(z.object({name:z.string().min(1).max(60),rankIndex:integer.max(100),level:integer.max(1000).optional(),classId:entityId.optional()}).strict()).max(GUILD_ROSTER_MAX).optional()}).strict()
  .superRefine((p,ctx)=>{
    if(p.roster!==undefined&&p.rankIndex!==0)ctx.addIssue({code:z.ZodIssueCode.custom,path:["roster"],message:"Only the guild master (rank 0) may send the roster."});
    if(p.roster!==undefined&&!p.guildName)ctx.addIssue({code:z.ZodIssueCode.custom,path:["roster"],message:"A roster needs a guild name."});
  });

export const payloadSchemas = {
  "character.snapshot":characterPayload,"character.level":characterPayload,
  "quest.accepted":questPayload,"quest.turned_in":questPayload,"quest.abandoned":questPayload,
  "npc.observed":npcPayload,"vendor.snapshot":vendorPayload,"loot.received":lootPayload,
  "profession.snapshot":professionPayload,"craft.result":craftPayload,"cooldown.snapshot":cooldownPayload,
  "instance.entered":runPayload,"run.finished":runPayload,"run.interrupted":runPayload,
  "raid.encounter_finished":encounterPayload,
  "zone.visited":zonePayload,
  "track.path":trackPayload,"guild.snapshot":guildPayload,
} as const;
export type EventKind = keyof typeof payloadSchemas;
export const eventKinds=Object.keys(payloadSchemas) as EventKind[];
export const gameSchema=z.object({product:z.literal("forever"),build:text,interface:integer,region:text,realm:text}).strict();
export const eventSchema=z.object({schemaVersion:z.literal(1),eventId:id,producerId:id,origin:z.literal("local_observation"),kind:z.enum(eventKinds as [EventKind,...EventKind[]]),observedAt:num,game:gameSchema,character:characterSchema.optional(),payload:z.record(z.unknown()),evidence:z.enum(["api_event","api_snapshot","manual"])}).strict().superRefine((event,ctx)=>{
  const result=payloadSchemas[event.kind].safeParse(event.payload);
  if(!result.success) for(const issue of result.error.issues)ctx.addIssue({...issue,path:["payload",...issue.path]});
  const latest=Math.floor(Date.now()/1000)+300;
  if(event.observedAt>latest)ctx.addIssue({code:z.ZodIssueCode.custom,path:["observedAt"],message:"Observation lies in the future."});
  if(event.kind==="track.path"&&typeof event.payload.startedAt==="number"&&event.payload.startedAt>event.observedAt+300)ctx.addIssue({code:z.ZodIssueCode.custom,path:["payload","startedAt"],message:"Track starts after the observation."});
  if(event.kind.startsWith("run.")||event.kind==="instance.entered"){
    const p=event.payload;
    if(typeof p.startedAt==="number"&&p.startedAt>event.observedAt+300)ctx.addIssue({code:z.ZodIssueCode.custom,path:["payload","startedAt"],message:"Run starts after the observation."});
    if(typeof p.endedAt==="number"&&p.endedAt>event.observedAt+300)ctx.addIssue({code:z.ZodIssueCode.custom,path:["payload","endedAt"],message:"Run ends after the observation."});
    if(typeof p.startedAt==="number"&&typeof p.endedAt==="number"&&typeof p.durationMs==="number"&&Math.abs((p.endedAt-p.startedAt)*1000-p.durationMs)>5000)ctx.addIssue({code:z.ZodIssueCode.custom,path:["payload","durationMs"],message:"Duration does not match start and end (5 s tolerance)."});
  }
});
export type AtlasEvent=z.infer<typeof eventSchema>;
export const exportSchema=z.object({schemaVersion:z.literal(1),enabled:z.boolean(),producerId:id,consentEpoch:integer,since:num,scopes:z.array(z.enum(SCOPES)).max(SCOPES.length),events:z.array(eventSchema).max(10000)}).strict().superRefine((value,ctx)=>{
  if(new Set(value.scopes).size!==value.scopes.length)ctx.addIssue({code:z.ZodIssueCode.custom,message:"Duplicate scope."});
  if(!value.enabled&&value.events.length)ctx.addIssue({code:z.ZodIssueCode.custom,message:"A disabled export must not contain events."});
  if(value.since>Math.floor(Date.now()/1000)+300)ctx.addIssue({code:z.ZodIssueCode.custom,path:["since"],message:"Period start lies in the future."});
  for(let i=0;i<value.events.length;i++){
    if(value.events[i].producerId!==value.producerId)ctx.addIssue({code:z.ZodIssueCode.custom,path:["events",i],message:"Event is not an own observation of this source."});
    if(value.events[i].observedAt<value.since)ctx.addIssue({code:z.ZodIssueCode.custom,path:["events",i],message:"Event is older than the allowed period."});
  }
});
export type ExportEnvelope=z.infer<typeof exportSchema>;
export function scopeFor(kind:EventKind):Scope{
  if(kind.startsWith("character."))return "own_character";
  if(kind.startsWith("run.")||kind.startsWith("instance.")||kind.startsWith("raid."))return "own_runs";
  if(kind.startsWith("profession.")||kind.startsWith("craft.")||kind.startsWith("cooldown."))return "own_professions";
  if(kind.startsWith("track."))return "own_track";
  if(kind.startsWith("guild."))return "guild_share";
  return "world_facts";
}
export function safeError(error:unknown):string{return error instanceof Error?error.message:"Invalid data.";}

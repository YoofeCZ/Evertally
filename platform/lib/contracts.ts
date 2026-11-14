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
const combatAmount=num.max(1e15);
const combatMetrics={damage:combatAmount.optional(),healing:combatAmount.optional(),overhealing:combatAmount.optional(),absorbs:combatAmount.optional(),damageTaken:combatAmount.optional(),interrupts:combatAmount.optional(),dispels:combatAmount.optional(),deaths:combatAmount.optional()};
const runMember={guid:z.string().min(1).max(100),name:text.optional(),classId:entityId.max(100).optional(),raceId:entityId.max(100).optional(),level:integer.max(1000).optional(),role:z.string().max(20).optional()};
const combatPayload=z.object({source:z.enum(["damage_meter","combat_log","unavailable"]),coverage:z.enum(["observed","partial","unavailable"]),coveredMs:num.max(604800000),activeMs:num.max(604800000),players:z.array(z.object({...runMember,...combatMetrics,activeMs:num.max(604800000).optional()}).strict()).max(80),...combatMetrics}).strict();
const runPayload=z.object({runId:id,instanceId:integer.optional(),name:text.optional(),instanceType:z.enum(["party","raid"]).optional(),difficultyId:integer.optional(),startedAt:num,endedAt:num.optional(),durationMs:num.max(604800000).optional(),status:z.enum(["visiting","completed","interrupted","manual","abandoned"]),completion:z.enum(["unknown","last_boss","full_clear"]).optional(),rankEligible:z.boolean().optional(),rulesetId:text.optional(),groupSize:integer.max(80).optional(),maxLevel:integer.max(1000).optional(),minLevel:integer.max(1000).optional(),deaths:integer.optional(),bossCount:integer.max(1000).optional(),bosses:z.array(z.object({encounterId:integer.optional(),name:text.optional(),killedAt:num.optional(),durationMs:num.max(86400000).optional(),splitMs:num.max(604800000).optional()}).strict()).max(1000).optional(),roster:z.array(z.object(runMember).strict()).max(80).optional(),combat:combatPayload.optional()}).strict().superRefine((p,ctx)=>{if(p.endedAt!==undefined&&p.endedAt<p.startedAt)ctx.addIssue({code:z.ZodIssueCode.custom,message:"Run end precedes its start."});});
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

// The armory of a character: what its owner sees in the character window. The owner's own snapshot (armory.snapshot) and what
// another player allowed this account to keep (armory.view) share one body. A view also names its subject; the name comes
// from the whisper that carried it, never from the data. Gold is never part of either. armory.revoked withdraws views of one player.
export const ARMORY_STAT_KEYS=["str","agi","sta","int","spi","armor","ap","rap","crit","scrit","dodge","parry","block","hp","mana","holy","fire","nature","frost","shadow","arcane"] as const;
const statValue=z.number().finite().min(0).max(1e7);
// an empty Lua table is exported as an empty list
const armoryStats=z.preprocess(v=>Array.isArray(v)&&v.length===0?undefined:v,z.object(Object.fromEntries(ARMORY_STAT_KEYS.map(k=>[k,statValue.optional()])) as Record<typeof ARMORY_STAT_KEYS[number],z.ZodOptional<z.ZodNumber>>).strict().optional());
const armoryBody={
  equipped:z.array(z.object({slot:integer.min(1).max(19),itemId:entityId}).strict()).max(25).optional(),
  bags:z.array(z.object({itemId:entityId,count:integer.positive().max(100000)}).strict()).max(400).optional(),
  stats:armoryStats,
  talents:z.array(z.object({name:text,spent:integer.max(1000),ranks:z.array(z.tuple([integer.positive().max(1e9),integer.positive().max(100)]).rest(text)).max(80)}).strict()).max(4).optional(),
  professions:z.array(z.object({id:entityId,name:text.optional(),skill:integer.max(10000).optional(),max:integer.max(10000).optional()}).strict()).max(12).optional(),
};
const armorySnapshotPayload=z.object(armoryBody).strict();
const armoryViewPayload=z.object({
  subject:z.object({name:z.string().min(1).max(60),realm:text.optional(),classId:entityId.max(100).optional(),raceId:entityId.max(100).optional(),level:integer.max(1000).optional()}).strict(),
  mode:z.enum(["once","always"]),kinds:z.string().max(8).regex(/^[istp]*$/),...armoryBody,
}).strict();
const armoryRevokedPayload=z.object({name:z.string().min(1).max(60),realm:text.optional()}).strict();
// The player's leaderboard choice for this character, made in the game (Settings or the setup guide).
// chosenAt = when the player made the choice; one choice is sent again for every character the player logs in with.
const publishPayload=z.object({public:z.boolean(),showItemLevel:z.boolean().optional(),showGuild:z.boolean().optional(),showGear:z.boolean().optional(),chosenAt:num.optional()}).strict();

export const payloadSchemas = {
  "character.snapshot":characterPayload,"character.level":characterPayload,"character.publish":publishPayload,
  "quest.accepted":questPayload,"quest.turned_in":questPayload,"quest.abandoned":questPayload,
  "npc.observed":npcPayload,"vendor.snapshot":vendorPayload,"loot.received":lootPayload,
  "profession.snapshot":professionPayload,"craft.result":craftPayload,"cooldown.snapshot":cooldownPayload,
  "instance.entered":runPayload,"run.finished":runPayload,"run.interrupted":runPayload,
  "raid.encounter_finished":encounterPayload,
  "zone.visited":zonePayload,
  "track.path":trackPayload,"guild.snapshot":guildPayload,
  "armory.snapshot":armorySnapshotPayload,"armory.view":armoryViewPayload,"armory.revoked":armoryRevokedPayload,
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
  if(kind.startsWith("character.")||kind.startsWith("armory."))return "own_character";
  if(kind.startsWith("run.")||kind.startsWith("instance.")||kind.startsWith("raid."))return "own_runs";
  if(kind.startsWith("profession.")||kind.startsWith("craft.")||kind.startsWith("cooldown."))return "own_professions";
  if(kind.startsWith("track."))return "own_track";
  if(kind.startsWith("guild."))return "guild_share";
  return "world_facts";
}
export function safeError(error:unknown):string{return error instanceof Error?error.message:"Invalid data.";}

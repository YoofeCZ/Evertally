import { exportSchema, scopeFor, type AtlasEvent, type ExportEnvelope, type Scope } from "./contracts";
import { projectExport } from "./import";
import { worldPayload } from "./world-privacy";

export type GrantPolicy={producerId:string;consentEpoch:number;since:number;scopes:Scope[];revokedAt:number|null};
const PSEUDONYMOUS=new Set<Scope>(["own_runs","own_track"]);
export class ApiError extends Error{constructor(public code:string,message:string,public status=400){super(message);}}

export function validateUpload(grant:GrantPolicy,raw:unknown):ExportEnvelope{
  if(grant.revokedAt!==null)throw new ApiError("consent_revoked","The consent was revoked.",403);
  const result=exportSchema.safeParse(raw);if(!result.success)throw new ApiError("invalid_export",`Invalid export: ${result.error.issues.slice(0,2).map(i=>i.path.join(".")+": "+i.message).join("; ")}`);
  const value=result.data;
  if(value.events.some(event=>event.kind==="track.path"))throw new ApiError("player_location_disabled","Player location uploads are disabled.",403);
  if(!value.enabled)throw new ApiError("export_disabled","Web export is turned off in the addon.",403);
  if(value.producerId!==grant.producerId||value.consentEpoch!==grant.consentEpoch)throw new ApiError("source_conflict","The export does not match the source and current consent version.",403);
  if(value.scopes.some(scope=>!grant.scopes.includes(scope)))throw new ApiError("scope_denied","The export contains a scope that is not allowed.",403);
  if(value.events.some(event=>event.observedAt<grant.since||event.observedAt<value.since))throw new ApiError("scope_denied","The export contains data from before the allowed period.",403);
  if(value.events.some(event=>!value.scopes.includes(scopeFor(event.kind))))throw new ApiError("scope_denied","An event is outside the allowed scopes.",403);
  // Reject identities at the network boundary, rather than quietly persisting them.
  if(value.scopes.includes("guild_share")&&!value.scopes.includes("own_character"))throw new ApiError("identity_scope_denied","Guild sharing needs the character scope, so the guild can recognise you.",403);
  // Runs and tracks may carry a pseudonymous source-wide character, never a name or realm.
  if(!value.scopes.includes("own_character")&&value.events.some(event=>event.character!==undefined&&(!PSEUDONYMOUS.has(scopeFor(event.kind))||event.character.id!==value.producerId+":own"||event.character.name!==undefined||event.character.realm!==undefined)))throw new ApiError("identity_scope_denied","This upload does not allow character details.",403);
  return projectExport(value,value.scopes);
}

export function sanitizedPayload(event:AtlasEvent):Record<string,unknown>{
  if(event.kind.startsWith("run.")||event.kind==="instance.entered")return {...event.payload,rankEligible:false};
  // Route points and guild details are kept exactly as validated; they are never world facts.
  if(event.kind.startsWith("track."))return {...event.payload};
  // The roster lives in the guild tables; the observation keeps only which guild the character was in.
  if(event.kind.startsWith("guild.")){const rest={...event.payload};delete rest.roster;return rest;}
  return worldPayload(event.kind,event.payload);
}

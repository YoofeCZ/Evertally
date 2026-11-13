import type { RunCombat, RunMember } from "../components/evertally/types";

/** Public records expose the profile owner, rather than publishing the other
 * actors' identities merely because one participant made their profile public. */
export function projectRunActors(combat:RunCombat|undefined,roster:RunMember[]|undefined,originalId:string|undefined,profileId:string|undefined,includeGroup:boolean){
  const project=<T extends RunMember>(actor:T):T=>actor.guid===originalId&&profileId?{...actor,guid:profileId}:actor;
  return {roster:includeGroup?(roster??[]).map(project):[],combat:combat?{...combat,players:combat.players.filter(p=>includeGroup||p.guid===originalId).map(project)}:null};
}

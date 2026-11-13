import type { Run, Entry } from "../components/evertally/types";

export function rankObservedRuns(runs: readonly Run[], params: URLSearchParams) {
  const wanted=params.get("metric");
  const metric=wanted==="time"||wanted==="dps"||wanted==="hps"?wanted:"count";
  const filtered=runs.filter(run=>{
    const c=run.character;
    return c&&run.status==="completed"&&["last_boss","full_clear"].includes(run.completion??"")&&run.evidence!=="manual"&&
      (!params.get("classId")||String(c.classId)===params.get("classId"))&&
      (!params.get("raceId")||String(c.raceId)===params.get("raceId"))&&
      (!params.get("instanceId")||String(run.instanceId)===params.get("instanceId"))&&
      (!params.get("instanceType")||run.instanceType===params.get("instanceType"))&&
      (!params.get("difficultyId")||String(run.difficultyId)===params.get("difficultyId"))&&
      (!params.get("completion")||run.completion===params.get("completion"));
  });
  const note="Observed public participations, not verified competitive scores or unique group runs. DPS/HPS use attributable recorded combat seconds; partial data is excluded.";
  if(metric!=="count"&&!params.get("instanceId"))return {entries:[],sampleSize:filtered.length,countingUnit:"participation",rulesLabel:"Select one instance to compare times or combat rates. "+note};
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
  return {entries:entries.map((entry,index)=>({...entry,rank:index+1})),sampleSize:filtered.length,countingUnit:"participation",rulesLabel:note};
}

import { getBinding } from "@/db";
import { json } from "@/lib/api";
import { ACTIVITY_SQL,activitySnapshot } from "@/lib/activity";
export const dynamic="force-dynamic";
export async function GET(){
 try{const now=Math.floor(Date.now()/1000);const rows=await getBinding().prepare(ACTIVITY_SQL).bind(now-86400,now).all<Record<string,unknown>>();return json(activitySnapshot(rows.results,now))}
 catch{return json({error:{code:"service_unavailable",message:"Zone activity is temporarily unavailable."}},503)}
}

import {getBinding} from "@/db";
import {getSessionUser} from "@/lib/auth";
import {buildProfessionData,PROFESSION_ROWS_SQL,PROFESSION_COUNT_SQL} from "@/lib/professions";
import {json} from "@/lib/api";
export const dynamic="force-dynamic";
export async function GET(request:Request){
 try{
  const user=await getSessionUser(request);
  if(!user)return json({error:{code:"unauthorized",message:"Sign in to see your own professions."}},401);
  const db=getBinding();
  const [rows,total]=await Promise.all([db.prepare(PROFESSION_ROWS_SQL).bind(user.id).all<Record<string,unknown>>(),db.prepare(PROFESSION_COUNT_SQL).bind(user.id).first<{count:number}>()]);
  return json(buildProfessionData(rows.results,Number(total?.count??0),Math.floor(Date.now()/1000)));
 }catch{return json({error:{code:"service_unavailable",message:"Profession history is temporarily unavailable."}},503);}
}

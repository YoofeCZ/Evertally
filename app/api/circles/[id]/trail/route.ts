import { handleApi } from "@/lib/api";
export const dynamic="force-dynamic";
export async function GET(request:Request,context:{params:Promise<{id:string}>}){return handleApi(request,"circle-trail",(await context.params).id);}

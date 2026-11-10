import { handleApi } from "@/lib/api";
export const dynamic="force-dynamic";
export async function GET(request:Request,context:{params:Promise<{id:string}>}){return handleApi(request,"profile-read",(await context.params).id);}
export async function PATCH(request:Request,context:{params:Promise<{id:string}>}){return handleApi(request,"profile",(await context.params).id);}

import { handleApi } from "@/lib/api";
export const dynamic="force-dynamic";
export async function PATCH(request:Request,context:{params:Promise<{id:string}>}){return handleApi(request,"meet",(await context.params).id);}

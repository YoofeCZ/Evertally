import { handleApi } from "@/lib/api";
export const dynamic="force-dynamic";
export async function DELETE(request:Request,context:{params:Promise<{id:string}>}){return handleApi(request,"revoke",(await context.params).id);}

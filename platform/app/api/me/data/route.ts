import { handleApi } from "@/lib/api";
export const dynamic="force-dynamic";
export async function DELETE(request:Request){return handleApi(request,"delete");}

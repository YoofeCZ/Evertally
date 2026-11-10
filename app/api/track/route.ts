import { handleApi } from "@/lib/api";
export const dynamic="force-dynamic";
export async function GET(request:Request){return handleApi(request,"track");}
export async function DELETE(request:Request){return handleApi(request,"track");}

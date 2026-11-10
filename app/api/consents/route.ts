import { handleApi } from "@/lib/api";
export const dynamic="force-dynamic";
export async function POST(request:Request){return handleApi(request,"consents");}

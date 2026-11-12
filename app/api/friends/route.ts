import { handleApi } from "@/lib/api";
export const dynamic="force-dynamic";
export async function GET(request:Request){return handleApi(request,"friends");}
export async function POST(request:Request){return handleApi(request,"friends");}

import { handleApi } from "@/lib/api";
export const dynamic="force-dynamic";
export async function POST(request:Request,context:{params:Promise<{id:string}>}){return handleApi(request,"meet-rsvp",(await context.params).id);}

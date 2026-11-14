import { handleApi } from "@/lib/api";
export const dynamic = "force-dynamic";
export async function GET(request: Request, context: { params: Promise<{ id: string }> }) { return handleApi(request, "forum-thread", (await context.params).id); }
export async function PATCH(request: Request, context: { params: Promise<{ id: string }> }) { return handleApi(request, "forum-thread-moderate", (await context.params).id); }

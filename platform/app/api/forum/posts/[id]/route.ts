import { handleApi } from "@/lib/api";
export const dynamic = "force-dynamic";
export async function DELETE(request: Request, context: { params: Promise<{ id: string }> }) { return handleApi(request, "forum-post-delete", (await context.params).id); }
export async function PATCH(request: Request, context: { params: Promise<{ id: string }> }) { return handleApi(request, "forum-post-edit", (await context.params).id); }

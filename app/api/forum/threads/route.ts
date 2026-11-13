import { handleApi } from "@/lib/api";
export const dynamic = "force-dynamic";
export function POST(request: Request) { return handleApi(request, "forum-thread-create"); }

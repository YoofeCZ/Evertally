import { handleApi } from "@/lib/api";
export const dynamic = "force-dynamic";
// one public character's armory: gear, stats, talents and professions (never the bags)
export async function GET(request: Request, context: { params: Promise<{ id: string }> }) {
  return handleApi(request, "armory-character", (await context.params).id);
}

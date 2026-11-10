import { getBinding } from "@/db";
import { buildCommunitySnapshot, COMMUNITY_OBSERVATIONS_SQL, type CommunityKind, type CommunityRow } from "@/lib/community";

export const dynamic = "force-dynamic";
const headers = { "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff" };

/** Public, anonymous world facts for an explicit, bounded addon import. */
export async function GET(request: Request) {
  const params = new URL(request.url).searchParams;
  const kind = params.get("kind") || undefined;
  if (kind && !["quest", "npc", "item"].includes(kind)) {
    return Response.json({ error: { code: "invalid_filter", message: "Choose quest, npc or item." } }, { status: 400, headers });
  }
  try {
    const rows = await getBinding().prepare(COMMUNITY_OBSERVATIONS_SQL).all<CommunityRow>();
    const snapshot = buildCommunitySnapshot(rows.results, Math.floor(Date.now() / 1000), {
      kind: kind as CommunityKind | undefined, search: (params.get("search") ?? "").slice(0, 200),
    });
    return Response.json(snapshot, { headers });
  } catch {
    return Response.json({ error: { code: "service_unavailable", message: "The community snapshot is not available right now." } }, { status: 503, headers });
  }
}

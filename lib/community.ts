/** A bounded, anonymous world-fact snapshot for explicit import into the addon. */
export const COMMUNITY_MAX_BYTES = 48 * 1024;
export const COMMUNITY_MAX_ENTITIES = 150;
export const COMMUNITY_MAX_OBSERVATIONS = 10_000;
export const COMMUNITY_TTL = 7 * 24 * 60 * 60;

/** Only observations whose owner still has an active world-facts grant. */
export const COMMUNITY_OBSERVATIONS_SQL = `WITH candidates AS (SELECT o.id,o.observed_at,
 length(CAST(o.payload AS BLOB))+length(CAST(o.game AS BLOB)) AS size
FROM atlas_observations o
JOIN atlas_grants g ON g.id=o.grant_id AND g.user_id=o.user_id AND g.producer_id=o.producer_id
WHERE o.scope='world_facts' AND g.revoked_at IS NULL
AND EXISTS(SELECT 1 FROM json_each(g.scopes) WHERE value='world_facts')
ORDER BY o.observed_at DESC,o.id DESC LIMIT 10000), sized AS (
 SELECT *,COUNT(*) OVER() AS sample_size,SUM(size) OVER(ORDER BY observed_at DESC,id DESC) AS bytes FROM candidates
)
SELECT o.kind,o.payload,o.observed_at,o.game,s.sample_size FROM sized s
JOIN atlas_observations o ON o.id=s.id WHERE s.bytes<=2097152
ORDER BY o.observed_at DESC,o.id DESC`;

export type CommunityKind = "quest" | "npc" | "item";
export type CommunityEntity = {
  kind: CommunityKind; id: number; name: string; count: number; lastSeen: number;
  mapId?: number; x?: number; y?: number;
};
export type CommunitySnapshot = {
  schemaVersion: 1; kind: "evertally-community"; scope: "world_facts";
  generatedAt: number; expiresAt: number; game: { product: "forever" };
  provenance: {
    source: "community"; countingUnit: "observations"; truncated: boolean;
    observationCount: number; entityCount: number;
  };
  entities: CommunityEntity[];
};
export type CommunityFilters = { kind?: CommunityKind; search?: string };
export type CommunityRow = { kind?: unknown; payload?: unknown; observed_at?: unknown; game?: unknown;sample_size?:unknown };

const encoder = new TextEncoder();
const kindFor: Record<string, CommunityKind> = {
  "quest.accepted": "quest", "quest.turned_in": "quest", "quest.abandoned": "quest",
  "npc.observed": "npc", "vendor.snapshot": "npc", "loot.received": "item",
};
const labels: Record<CommunityKind, string> = { quest: "Quest", npc: "NPC", item: "Item" };

function object(value: unknown): Record<string, unknown> | null {
  if (typeof value === "string") {
    try { value = JSON.parse(value); } catch { return null; }
  }
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown> : null;
}

function integer(value: unknown, min: number, max: number): number | undefined {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= min && value <= max ? value : undefined;
}

/** Limit UTF-8 bytes without splitting Czech letters or supplementary codepoints. */
function plainName(value: unknown, fallback: string): string {
  if (typeof value !== "string") return fallback;
  const clean = value.replace(/[\u0000-\u001f\u007f|]/g, " ")
    .replace(/[\uD800-\uDFFF]/gu, "").replace(/\s+/g, " ").trim();
  let name = "", bytes = 0;
  for (const character of clean) {
    const size = encoder.encode(character).byteLength;
    if (bytes + size > 160) break;
    name += character; bytes += size;
  }
  return name.trim() || fallback;
}

function projection(row: CommunityRow, generatedAt: number): CommunityEntity | null {
  const kind = typeof row.kind === "string" && Object.hasOwn(kindFor, row.kind) ? kindFor[row.kind] : undefined;
  const payload = object(row.payload);
  const game = object(row.game);
  const lastSeen = integer(row.observed_at, 0, generatedAt + 300);
  if (!kind || !payload || game?.product !== "forever" || lastSeen === undefined) return null;
  const id = integer(payload[kind === "quest" ? "questId" : kind === "npc" ? "npcId" : "itemId"], 1, 2_147_483_647);
  if (!id) return null;
  const entity: CommunityEntity = {
    kind, id, name: plainName(kind === "quest" ? payload.title : payload.name, `${labels[kind]} #${id}`), count: 1, lastSeen,
  };
  const mapId = integer(payload.mapId, 1, 2_147_483_647);
  if (mapId !== undefined) entity.mapId = mapId;
  // Interacting with an NPC reports the player's location, not the NPC's exact
  // position. Only an explicitly observed unit-position pair can become a pin.
  const { x, y } = payload;
  if (kind === "npc" && mapId !== undefined && payload.positionMethod === "unit_position"
      && typeof x === "number" && Number.isFinite(x) && x >= 0 && x <= 1
      && typeof y === "number" && Number.isFinite(y) && y >= 0 && y <= 1) {
    entity.x = x; entity.y = y;
  }
  return entity;
}

/** No row identity, character, full payload or arbitrary caller field survives. */
export function buildCommunitySnapshot(
  sourceRows: readonly CommunityRow[], generatedAt: number, filters: CommunityFilters = {},
): CommunitySnapshot {
  if (!Number.isSafeInteger(generatedAt) || generatedAt < 0 || generatedAt > 253_402_300_799 - COMMUNITY_TTL) {
    throw new Error("Invalid community snapshot time");
  }
  const byId = new Map<string, CommunityEntity>();
  for (const row of sourceRows.slice(0, COMMUNITY_MAX_OBSERVATIONS)) {
    const entity = projection(row, generatedAt);
    if (!entity) continue;
    const key = `${entity.kind}:${entity.id}`;
    const previous = byId.get(key);
    if (!previous) byId.set(key, entity);
    else if (entity.lastSeen > previous.lastSeen) byId.set(key, { ...entity, count: previous.count + 1 });
    else previous.count++;
  }
  const query = filters.search?.trim().slice(0, 200).toLocaleLowerCase() ?? "";
  const matches = [...byId.values()].filter(entity => (!filters.kind || entity.kind === filters.kind)
    && (!query || entity.name.toLocaleLowerCase().includes(query) || String(entity.id).includes(query)))
    .sort((a, b) => b.lastSeen - a.lastSeen || a.kind.localeCompare(b.kind) || a.id - b.id);
  const snapshot: CommunitySnapshot = {
    schemaVersion: 1, kind: "evertally-community", scope: "world_facts", generatedAt,
    expiresAt: generatedAt + COMMUNITY_TTL, game: { product: "forever" },
    provenance: {
      source: "community", countingUnit: "observations", truncated: false,
      observationCount: matches.reduce((total, entity) => total + entity.count, 0), entityCount: matches.length,
    }, entities: matches.slice(0, COMMUNITY_MAX_ENTITIES),
  };
  snapshot.provenance.truncated = sourceRows.length >= COMMUNITY_MAX_OBSERVATIONS || matches.length > snapshot.entities.length
    || sourceRows.some(row=>typeof row.sample_size==="number"&&row.sample_size>sourceRows.length);
  // Preserve whole entities; never produce a cut string or partial JSON object.
  while (encoder.encode(JSON.stringify(snapshot)).byteLength > COMMUNITY_MAX_BYTES) {
    if (snapshot.entities.length === 0) throw new Error("Community snapshot metadata exceeds the byte limit");
    snapshot.entities.pop(); snapshot.provenance.truncated = true;
  }
  return snapshot;
}

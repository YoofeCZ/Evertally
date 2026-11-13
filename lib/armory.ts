// The armory of a character: gear, stats, talents, professions and bags.
//
// Two sources only, and nothing else is ever returned:
//  1. the account's OWN characters (armory.snapshot, uploaded by the owner's own addon under the character scope);
//  2. what another player allowed THIS account to keep (armory.view). The other player decided in game, once or for good, and
//     the request that was answered came from this account's own addon. A view disappears when
//       - the player revokes it (an armory.revoked notice for that player is newer than the view),
//       - the upload's consent (grant) is revoked or no longer carries the character scope,
//       - or it is older than ARMORY_VIEW_DAYS (a snapshot is not a standing feed).
// A character that nobody allowed is simply not in the list: there is no way to ask the server for it.
import { payloadSchemas } from "./contracts";
import { now, type Db } from "./people";

export const ARMORY_VIEW_DAYS = 30;
export type ArmoryBody = NonNullable<ReturnType<typeof parseBody>>;
export interface ArmoryCharacter { id: string; name: string | null; realm: string | null; classId: number | null; raceId: number | null; level: number | null }
export interface OwnArmory { kind: "own"; id: string; character: ArmoryCharacter; observedAt: number; armory: ArmoryBody }
export interface ViewedArmory { kind: "viewed"; id: string; character: ArmoryCharacter; observedAt: number; mode: "once" | "always"; kinds: string; armory: ArmoryBody }
export interface ArmoryOverview { own: OwnArmory[]; viewed: ViewedArmory[]; viewDays: number }

const realmKey = (realm: unknown) => String(realm ?? "").replace(/\s+/g, "").toLowerCase();
export const subjectKey = (name: unknown, realm: unknown) => `${String(name ?? "").trim().toLowerCase()}|${realmKey(realm)}`;
const decode = (value: unknown): unknown => { try { return JSON.parse(String(value)); } catch { return null; } };

function parseBody(payload: Record<string, unknown>) {
  return {
    equipped: (payload.equipped ?? []) as { slot: number; itemId: number }[],
    bags: (payload.bags ?? []) as { itemId: number; count: number }[],
    stats: (payload.stats ?? {}) as Record<string, number>,
    talents: (payload.talents ?? []) as { name: string; spent: number; ranks: [number, number, ...string[]][] }[],
    professions: (payload.professions ?? []) as { id: number; name?: string; skill?: number; max?: number }[],
  };
}

const GRANT_CHARACTER = `g.revoked_at IS NULL AND EXISTS(SELECT 1 FROM json_each(g.scopes) WHERE value='own_character')`;

export async function armoryOverview(db: Db, userId: string, at = now()): Promise<ArmoryOverview> {
  const ownRows = await db.prepare(`SELECT profile_id,observed_at,payload,name,realm,class_id,race_id,level FROM (
      SELECT o.profile_id,o.observed_at,o.payload,p.name,p.realm,p.class_id,p.race_id,p.level,
        ROW_NUMBER() OVER (PARTITION BY o.profile_id ORDER BY o.observed_at DESC,o.id DESC) AS n
      FROM atlas_observations o
      JOIN atlas_profiles p ON p.id=o.profile_id AND p.user_id=o.user_id
      JOIN atlas_grants g ON g.id=o.grant_id AND g.user_id=o.user_id
      WHERE o.user_id=? AND o.kind='armory.snapshot' AND ${GRANT_CHARACTER}
    ) WHERE n=1 ORDER BY observed_at DESC LIMIT 100`).bind(userId).all<Record<string, unknown>>();
  const own: OwnArmory[] = [];
  for (const row of ownRows.results) {
    const parsed = payloadSchemas["armory.snapshot"].safeParse(decode(row.payload));
    if (!parsed.success) continue;
    own.push({
      kind: "own", id: String(row.profile_id), observedAt: Number(row.observed_at), armory: parseBody(parsed.data),
      character: { id: String(row.profile_id), name: (row.name as string | null) ?? null, realm: (row.realm as string | null) ?? null,
        classId: row.class_id == null ? null : Number(row.class_id), raceId: row.race_id == null ? null : Number(row.race_id), level: row.level == null ? null : Number(row.level) },
    });
  }

  // newest view per player (name + realm), and the newest revoke notice per player name
  const viewRows = await db.prepare(`SELECT observed_at,payload FROM (
      SELECT o.observed_at,o.payload,o.id,
        ROW_NUMBER() OVER (PARTITION BY lower(json_extract(o.payload,'$.subject.name')),replace(lower(COALESCE(json_extract(o.payload,'$.subject.realm'),'')),' ','')
          ORDER BY o.observed_at DESC,o.id DESC) AS n
      FROM atlas_observations o JOIN atlas_grants g ON g.id=o.grant_id AND g.user_id=o.user_id
      WHERE o.user_id=? AND o.kind='armory.view' AND o.observed_at>? AND ${GRANT_CHARACTER}
    ) WHERE n=1 ORDER BY observed_at DESC LIMIT 200`).bind(userId, at - ARMORY_VIEW_DAYS * 86400).all<Record<string, unknown>>();
  const revokeRows = await db.prepare(`SELECT o.observed_at,o.payload FROM atlas_observations o JOIN atlas_grants g ON g.id=o.grant_id AND g.user_id=o.user_id
      WHERE o.user_id=? AND o.kind='armory.revoked' AND ${GRANT_CHARACTER} ORDER BY o.observed_at DESC LIMIT 500`).bind(userId).all<Record<string, unknown>>();
  const revoked: { name: string; realm: string | null; at: number }[] = [];
  for (const row of revokeRows.results) {
    const parsed = payloadSchemas["armory.revoked"].safeParse(decode(row.payload));
    if (parsed.success) revoked.push({ name: parsed.data.name.trim().toLowerCase(), realm: parsed.data.realm ? realmKey(parsed.data.realm) : null, at: Number(row.observed_at) });
  }
  const viewed: ViewedArmory[] = [];
  for (const row of viewRows.results) {
    const parsed = payloadSchemas["armory.view"].safeParse(decode(row.payload));
    if (!parsed.success) continue;
    const { subject, mode, kinds, ...body } = parsed.data;
    const observedAt = Number(row.observed_at);
    const name = subject.name.trim().toLowerCase();
    // a revoke notice carries the name and, when the whisper had one, the realm; the later of the two wins
    if (revoked.some(r => r.name === name && (r.realm === null || r.realm === realmKey(subject.realm)) && r.at >= observedAt)) continue;
    viewed.push({
      kind: "viewed", id: `v:${subjectKey(subject.name, subject.realm)}`, observedAt, mode, kinds, armory: parseBody(body),
      character: { id: `v:${subjectKey(subject.name, subject.realm)}`, name: subject.name, realm: subject.realm ?? null, classId: subject.classId ?? null, raceId: subject.raceId ?? null, level: subject.level ?? null },
    });
  }
  return { own, viewed, viewDays: ARMORY_VIEW_DAYS };
}

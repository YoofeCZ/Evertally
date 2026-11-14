// Gear, stats and talents of one character for its page. The caller decides whether they may be shown (a public
// character whose player turned on "show gear", or the owner); this reads only the latest armory snapshot of the
// character itself, from a grant that is live and still includes the character scope. Bags and professions never leave.
import type { Db } from "./people";

export type PublicGear = {
  observedAt: number;
  equipped: { slot: number; itemId: number }[];
  stats: Record<string, number>;
  talents: { name: string; spent: number; ranks: [number, number, ...string[]][] }[];
};

export async function publicGear(db: Db, profileId: string): Promise<PublicGear | null> {
  const row = await db.prepare(`SELECT o.observed_at,o.payload FROM atlas_observations o
    JOIN atlas_profiles p ON p.id=o.profile_id AND p.user_id=o.user_id AND p.producer_id=o.producer_id
    JOIN atlas_grants g ON g.id=o.grant_id AND g.user_id=o.user_id AND g.producer_id=o.producer_id
    WHERE o.profile_id=? AND o.kind='armory.snapshot' AND o.scope='own_character' AND g.revoked_at IS NULL
    AND EXISTS(SELECT 1 FROM json_each(g.scopes) WHERE value='own_character')
    ORDER BY o.observed_at DESC,o.id DESC LIMIT 1`).bind(profileId).first<Record<string, unknown>>();
  if (!row) return null;
  let payload: Record<string, unknown>;
  try { payload = JSON.parse(String(row.payload)) as Record<string, unknown>; } catch { return null; }
  const equipped = Array.isArray(payload.equipped) ? (payload.equipped as { slot: number; itemId: number }[]).filter(e => Number.isInteger(e?.slot) && Number.isInteger(e?.itemId)) : [];
  const stats = payload.stats && typeof payload.stats === "object" ? payload.stats as Record<string, number> : {};
  const talents = Array.isArray(payload.talents) ? payload.talents as PublicGear["talents"] : [];
  if (!equipped.length && !talents.length && !Object.keys(stats).length) return null;
  return { observedAt: Number(row.observed_at) || 0, equipped, stats, talents };
}

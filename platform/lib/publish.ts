import type { Db } from "./people";

/** A leaderboard choice the player made in the game for one of their characters (event `character.publish`). */
export type PublishChoice = { profileId: string; observedAt: number; public: boolean; showItemLevel?: boolean; showGuild?: boolean; showGear?: boolean };

/**
 * Applies the choices of one upload, oldest first. A choice changes a character only when it is newer than the
 * last choice made for it on the website or in the game (`visibility_at`), so replaying an old export never
 * undoes a later change on the website, and the website never silently loses to a stale game setting. Two choices
 * made in the same second both apply, in the order they were made (the sort is stable).
 */
export async function applyPublishChoices(db: Db, userId: string, choices: readonly PublishChoice[]): Promise<number> {
  let changed = 0;
  for (const c of [...choices].sort((a, b) => a.observedAt - b.observedAt)) {
    const result = await db.prepare(`UPDATE atlas_profiles SET "public"=?,
        show_item_level=COALESCE(?,show_item_level),show_guild=COALESCE(?,show_guild),show_gear=COALESCE(?,show_gear),visibility_at=?
      WHERE id=? AND user_id=? AND COALESCE(visibility_at,0)<=?`)
      .bind(c.public ? 1 : 0, c.showItemLevel === undefined ? null : c.showItemLevel ? 1 : 0, c.showGuild === undefined ? null : c.showGuild ? 1 : 0,
        c.showGear === undefined ? null : c.showGear ? 1 : 0,
        c.observedAt, c.profileId, userId, c.observedAt)
      .run();
    changed += Number(result.meta?.changes ?? 0);
  }
  return changed;
}

// The newest in-game choice of one addon (one WoW account), only from a live grant that still carries the character scope.
const LATEST_CHOICE = `SELECT o.payload,MIN(o.observed_at,COALESCE(CAST(json_extract(o.payload,'$.chosenAt') AS INTEGER),o.observed_at)) AS at FROM atlas_observations o JOIN atlas_grants g ON g.id=o.grant_id AND g.user_id=o.user_id AND g.producer_id=o.producer_id WHERE o.user_id=? AND o.producer_id=? AND o.kind='character.publish' AND g.revoked_at IS NULL AND EXISTS(SELECT 1 FROM json_each(g.scopes) WHERE value='own_character') ORDER BY MIN(o.observed_at,COALESCE(CAST(json_extract(o.payload,'$.chosenAt') AS INTEGER),o.observed_at)) DESC,o.observed_at DESC,o.rowid DESC LIMIT 1`;
const flag = (value: unknown) => typeof value === "boolean" ? (value ? 1 : 0) : null;

/**
 * The game's choice is one choice for the whole WoW account: the addon sends it with whichever character is logged in,
 * so it applies to every character of that addon (producer) whose own last choice is older: characters that were not
 * played since the choice, and characters the website sees for the first time later. A later choice made on the website
 * for one character still wins. Run after every upload of that producer.
 */
export async function applyAccountChoice(db: Db, userId: string, producerId: string): Promise<number> {
  const latest = await db.prepare(LATEST_CHOICE).bind(userId, producerId).first<{ payload: unknown; at: unknown }>();
  if (!latest) return 0;
  let choice: Record<string, unknown>;
  try { choice = JSON.parse(String(latest.payload)) as Record<string, unknown>; } catch { return 0; }
  const at = Number(latest.at);
  if (typeof choice?.public !== "boolean" || !Number.isFinite(at)) return 0;
  const result = await db.prepare(`UPDATE atlas_profiles SET "public"=?,show_item_level=COALESCE(?,show_item_level),show_guild=COALESCE(?,show_guild),
      show_gear=COALESCE(?,show_gear),visibility_at=?
    WHERE user_id=? AND producer_id=? AND COALESCE(visibility_at,0)<?`)
    .bind(choice.public ? 1 : 0, flag(choice.showItemLevel), flag(choice.showGuild), flag(choice.showGear), at, userId, producerId, at)
    .run();
  return Number(result.meta?.changes ?? 0);
}

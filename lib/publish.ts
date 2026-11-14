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

/** Game-style difficulty colour of a level range against the player's level (lv-* classes, see db.css). */
export function levelClass(range: [number, number] | null | undefined, level: number | null): string {
  if (!range || !level) return "lv-none";
  if (level > range[1] + 8) return "lv-grey";
  if (level > range[1] + 2) return "lv-green";
  if (level >= range[0] - 2) return "lv-yellow";
  if (level >= range[0] - 6) return "lv-orange";
  return "lv-red";
}

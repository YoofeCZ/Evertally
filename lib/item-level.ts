import { ITEM_LEVELS } from "./item-levels.data";

export type ItemLevelInfo = { level: number; twoHand: boolean };

/** Gear slots that count, numbered as the game numbers them: all but the shirt (4) and the tabard (19). */
export const ITEM_LEVEL_SLOTS = [1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18] as const;
const MAIN_HAND = 16, OFF_HAND = 17;

let table: Map<number, ItemLevelInfo> | null = null;
/** Parsed once per worker from the generated table (tools/build_item_levels.py). */
export function itemLevels(): Map<number, ItemLevelInfo> {
  if (table) return table;
  const parsed = new Map<number, ItemLevelInfo>();
  for (const entry of ITEM_LEVELS.split(",")) {
    const twoHand = entry.endsWith("*");
    const [id, level] = (twoHand ? entry.slice(0, -1) : entry).split(".");
    parsed.set(parseInt(id, 36), { level: parseInt(level, 36), twoHand });
  }
  table = parsed;
  return parsed;
}

/**
 * Average item level of the equipped gear: the 17 gear slots, an empty slot counts as 0, and a two-handed
 * weapon also fills an empty off hand. Rounded down. Null when nothing is equipped or any equipped item is
 * missing from the table, so a partly known set never shows a number that is too low.
 */
export function averageItemLevel(equipped: readonly { slot: number; itemId: number }[], lookup: ReadonlyMap<number, ItemLevelInfo> = itemLevels()): number | null {
  const bySlot = new Map<number, number>();
  for (const e of equipped) if (Number.isInteger(e?.slot) && Number.isInteger(e?.itemId) && e.itemId > 0) bySlot.set(e.slot, e.itemId);
  let sum = 0, worn = 0;
  for (const slot of ITEM_LEVEL_SLOTS) {
    const id = bySlot.get(slot);
    if (!id) continue;
    const item = lookup.get(id);
    if (!item) return null;
    sum += item.level;
    worn++;
    if (slot === MAIN_HAND && item.twoHand && !bySlot.has(OFF_HAND)) sum += item.level;
  }
  return worn ? Math.floor(sum / ITEM_LEVEL_SLOTS.length) : null;
}

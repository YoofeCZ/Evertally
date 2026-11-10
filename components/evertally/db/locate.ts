// A point on Azeroth's map back to the map a game client knows it by: the smallest zone or city map around it, with the
// point as a 0..1 position on that map. This is the form the addon and the meets API use (UiMap id, x, y).
import type { World, WorldMapEntry } from "./store";

export type Located = { key: string; mapId: number; x: number; y: number };
const area = (entry: WorldMapEntry) => (entry.rect[1] - entry.rect[0]) * (entry.rect[3] - entry.rect[2]);

export function locate(world: World, u: number, v: number): Located | null {
  let best: [string, WorldMapEntry] | null = null;
  for (const [key, entry] of Object.entries(world.maps)) {
    if (entry.kind !== "zone" && entry.kind !== "city") continue;
    const [l, r, t, b] = entry.rect;
    if (u < l || u > r || v < t || v > b) continue;
    if (!best || area(entry) < area(best[1])) best = [key, entry];
  }
  if (!best) return null;
  const [l, r, t, b] = best[1].rect;
  const clamp = (n: number) => Math.min(1, Math.max(0, Math.round(n * 10000) / 10000));
  return { key: best[0], mapId: best[1].ui, x: clamp((u - l) / (r - l)), y: clamp((v - t) / (b - t)) };
}

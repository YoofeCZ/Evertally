// Drawings live in localStorage and outlive the code that wrote them: the first version stored no width and no zoom.
// Whatever is read back is checked here, so one bad entry can never take the whole map down.
import type { Drawing } from "./MapCanvas";

const KINDS = new Set(["free", "line", "arrow", "circle", "mark"]);
export const DEFAULT_WIDTH = 4;
const finite = (value: unknown): value is number => typeof value === "number" && Number.isFinite(value);

/** `fallbackZoom` is the zoom a stroke without a recorded zoom is treated as drawn at. */
export function sanitizeDrawings(raw: unknown, fallbackZoom = 2): Drawing[] {
  if (!Array.isArray(raw)) return [];
  const out: Drawing[] = [];
  raw.forEach((entry, index) => {
    if (!entry || typeof entry !== "object") return;
    const item = entry as Partial<Drawing>;
    if (!item.kind || !KINDS.has(item.kind) || !Array.isArray(item.points)) return;
    const points = item.points.filter((point): point is [number, number] => Array.isArray(point) && finite(point[0]) && finite(point[1]));
    if (!points.length || (item.kind !== "mark" && points.length < 2)) return;
    out.push({
      id: typeof item.id === "string" ? item.id : `legacy-${index}`,
      kind: item.kind, points,
      color: typeof item.color === "string" && /^#[0-9a-f]{3,8}$/i.test(item.color) ? item.color : "#ffd24a",
      width: finite(item.width) && item.width > 0 ? Math.min(item.width, 40) : DEFAULT_WIDTH,
      zoom: finite(item.zoom) ? item.zoom : fallbackZoom,
    });
  });
  return out;
}

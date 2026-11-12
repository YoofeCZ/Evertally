// Floating map panels can be dragged by their header. This is the arithmetic of it, apart from the component so it can be tested.
export type Offset = { x: number; y: number };

/** How much of a panel has to stay on screen (pixels), so it can always be grabbed again. */
export const MIN_VISIBLE = 80;
/** The height of the strip at the bottom of the window where a header would be hard to reach. */
const BOTTOM_MARGIN = 44;

/**
 * The offset after dragging by (dx, dy). `rect` is the panel's box when the drag began (with the offset `base` already applied),
 * so the result keeps the panel's header inside the window whatever the pointer does.
 */
export function clampDrag(base: Offset, dx: number, dy: number, rect: { left: number; top: number; width: number }, viewport: { width: number; height: number }): Offset {
  const left = Math.min(Math.max(rect.left + dx, MIN_VISIBLE - rect.width), viewport.width - MIN_VISIBLE);
  const top = Math.min(Math.max(rect.top + dy, 0), viewport.height - BOTTOM_MARGIN);
  return { x: Math.round(base.x + (left - rect.left)), y: Math.round(base.y + (top - rect.top)) };
}

/** True when a panel's box has left the window so far that it can no longer be grabbed (after the window was made smaller). */
export function outOfReach(rect: { left: number; right: number; top: number; bottom: number; width: number }, viewport: { width: number; height: number }): boolean {
  if (rect.width === 0) return false; // not shown
  return rect.right < MIN_VISIBLE || rect.left > viewport.width - MIN_VISIBLE || rect.top > viewport.height - BOTTOM_MARGIN || rect.bottom < BOTTOM_MARGIN;
}

/** What `JSON.stringify(offset)` stored, or null when it is missing or not a sane offset. */
export function parseOffset(raw: string | null): Offset | null {
  if (!raw) return null;
  try {
    const value = JSON.parse(raw) as { x?: unknown; y?: unknown } | null;
    if (!value || typeof value.x !== "number" || typeof value.y !== "number") return null;
    if (!Number.isFinite(value.x) || !Number.isFinite(value.y) || Math.abs(value.x) > 20000 || Math.abs(value.y) > 20000) return null;
    return { x: Math.round(value.x), y: Math.round(value.y) };
  } catch { return null; }
}

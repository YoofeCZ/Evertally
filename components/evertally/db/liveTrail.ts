// The stretch a character walked while the map page was open. The game saves the recorded route (/api/track) only on /reload or
// logout, so a character that moves live would be a dot without a line behind it; the page therefore keeps the live fixes it
// receives (/api/live, every three seconds) and draws them as a line. Only the account's own characters are kept this way.
export type LiveFix = { profileId: string; mapId: number; x: number; y: number; at: number };
/** [seconds, x, y] with x and y as fractions of the zone map, the same shape as the recorded route. */
export type Fix = [seconds: number, x: number, y: number];
/** One zone's worth of walking; a new segment starts when the character changes map. */
export type Segment = { mapId: number; points: Fix[] };
export type LiveTrails = Record<string, Segment[]>;

/** Most fixes kept per character (about 45 minutes of walking). */
export const MAX_FIXES = 900;
/** Smaller moves than this (a fraction of the map, a few yards) are jitter, not walking. */
export const MIN_STEP = 0.0004;
/** Fixes older than this are dropped when the trail is stored or restored. */
export const KEEP_SECONDS = 2 * 3600;

const finite = (value: unknown): value is number => typeof value === "number" && Number.isFinite(value);

function cap(segments: Segment[]): Segment[] {
  let total = segments.reduce((sum, segment) => sum + segment.points.length, 0);
  if (total <= MAX_FIXES) return segments;
  const out = segments.map(segment => ({ mapId: segment.mapId, points: [...segment.points] }));
  while (total > MAX_FIXES && out.length) {
    out[0].points.shift();
    total--;
    if (!out[0].points.length) out.shift();
  }
  return out;
}

/** Adds the new fixes to the trails. Returns the same object when nothing was added, so React does not redraw for nothing. */
export function extendLive(previous: LiveTrails, fixes: LiveFix[]): LiveTrails {
  let next = previous;
  for (const fix of fixes) {
    if (typeof fix.profileId !== "string" || !fix.profileId || ![fix.mapId, fix.x, fix.y, fix.at].every(finite)) continue;
    const segments = next[fix.profileId] ?? [];
    const tail = segments[segments.length - 1];
    const sameMap = tail !== undefined && tail.mapId === fix.mapId;
    const last = sameMap ? tail.points[tail.points.length - 1] : undefined;
    if (last && (fix.at <= last[0] || Math.hypot(fix.x - last[1], fix.y - last[2]) < MIN_STEP)) continue;
    const point: Fix = [fix.at, fix.x, fix.y];
    const updated = sameMap
      ? [...segments.slice(0, -1), { mapId: tail.mapId, points: [...tail.points, point] }]
      : [...segments, { mapId: fix.mapId, points: [point] }];
    next = { ...next, [fix.profileId]: cap(updated) };
  }
  return next;
}

/** Drops fixes older than `KEEP_SECONDS` and everything that is left empty. */
export function pruneLive(trails: LiveTrails, now: number): LiveTrails {
  const out: LiveTrails = {};
  for (const [profileId, segments] of Object.entries(trails)) {
    const kept = segments
      .map(segment => ({ mapId: segment.mapId, points: segment.points.filter(point => now - point[0] <= KEEP_SECONDS) }))
      .filter(segment => segment.points.length > 0);
    if (kept.length) out[profileId] = cap(kept);
  }
  return out;
}

/** Reads what `JSON.stringify(trails)` stored; anything that does not look like a trail is left out. */
export function restoreLive(raw: unknown, now: number): LiveTrails {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return {};
  const out: LiveTrails = {};
  for (const [profileId, value] of Object.entries(raw as Record<string, unknown>)) {
    if (!Array.isArray(value)) continue;
    const segments: Segment[] = [];
    for (const entry of value) {
      const candidate = entry as { mapId?: unknown; points?: unknown } | null;
      if (!candidate || !finite(candidate.mapId) || !Array.isArray(candidate.points)) continue;
      const points: Fix[] = [];
      for (const point of candidate.points) {
        if (Array.isArray(point) && point.length === 3 && point.every(finite) && point[1] >= 0 && point[1] <= 1 && point[2] >= 0 && point[2] <= 1) points.push([point[0], point[1], point[2]]);
      }
      if (points.length) segments.push({ mapId: candidate.mapId, points });
    }
    if (segments.length) out[profileId] = segments;
  }
  return pruneLive(out, now);
}

/** The newest fix of a character's trail, with the map it was on. */
export function lastFix(segments: Segment[] | undefined): { mapId: number; fix: Fix } | null {
  const tail = segments?.[segments.length - 1];
  const fix = tail?.points[tail.points.length - 1];
  return tail && fix ? { mapId: tail.mapId, fix } : null;
}

/**
 * Cuts a walked line where the character did not walk: a teleport, a hearthstone or a graveyard run inside one zone shows up as
 * a jump of a tenth of the map or more in a few seconds, and drawn as a line it would cross the whole zone. The speeds seen
 * when walking, riding and flying stay well below the limit (a flight path is about 0.01 of a map per second).
 * Works on [seconds, x, y] with any consistent unit of time (relative to the start of a path or absolute).
 */
export const JUMP_DISTANCE = 0.08;
export const JUMP_SPEED = 0.015;
export function splitAtJumps<T extends readonly [number, number, number]>(points: readonly T[]): T[][] {
  const runs: T[][] = [];
  let run: T[] = [];
  for (const point of points) {
    const previous = run[run.length - 1];
    if (previous) {
      const distance = Math.hypot(point[1] - previous[1], point[2] - previous[2]);
      const seconds = Math.max(1, point[0] - previous[0]);
      if (distance >= JUMP_DISTANCE && distance / seconds >= JUMP_SPEED) { runs.push(run); run = []; }
    }
    run.push(point);
  }
  if (run.length) runs.push(run);
  return runs;
}

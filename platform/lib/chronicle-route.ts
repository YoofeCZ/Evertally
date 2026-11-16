// Historical route geometry: keep every recorded visit to a map, split only where location is unknown,
// and colour actual combat intervals without treating the rest of a dungeon visit as combat.
import { sessionAt, type Chronicle, type PathPoint } from "./chronicle";

export type CombatSpan = { from: number; to: number };
export type RouteSegment = CombatSpan & { zone: number; combat: boolean; points: PathPoint[] };

export function combatSpans(c: Chronicle): CombatSpan[] {
  const ranges = (c.fights ?? []).filter(f => f.d > 0).map(f => ({ from: Math.max(0, f.t), to: Math.min(c.duration, f.t + f.d) })).sort((a, b) => a.from - b.from);
  const out: CombatSpan[] = [];
  for (const range of ranges) {
    if (range.to <= range.from) continue;
    const last = out[out.length - 1];
    if (last && range.from <= last.to) last.to = Math.max(last.to, range.to);
    else out.push({ ...range });
  }
  return out;
}

const between = (a: PathPoint, b: PathPoint, t: number): PathPoint => {
  if (t === a[0]) return a;
  if (t === b[0]) return b;
  const f = (t - a[0]) / (b[0] - a[0]);
  return [t, a[1], a[2] + (b[2] - a[2]) * f, a[3] + (b[3] - a[3]) * f];
};

/** Small segments allow the canvas to cache all completed geometry and redraw only the changing end. */
export function routeSegments(c: Chronicle): RouteSegment[] {
  const fights = combatSpans(c), out: RouteSegment[] = [];
  let fight = 0, previous: RouteSegment | null = null;
  const append = (a: PathPoint, b: PathPoint, combat: boolean) => {
    if (previous && previous.zone === a[1] && previous.combat === combat && previous.to === a[0] && previous.points.length < 128) {
      previous.points.push(b); previous.to = b[0];
    } else {
      previous = { from: a[0], to: b[0], zone: a[1], combat, points: [a, b] };
      out.push(previous);
    }
  };
  for (let i = 1; i < c.path.length; i++) {
    const a = c.path[i - 1], b = c.path[i];
    if (a[1] !== b[1] || b[0] <= a[0] || b[0] - a[0] > 15 || sessionAt(c, a[0]) !== sessionAt(c, b[0])) { previous = null; continue; }
    while (fight < fights.length && fights[fight].to <= a[0]) fight++;
    let cursor = a[0], at = fight;
    while (cursor < b[0]) {
      while (at < fights.length && fights[at].to <= cursor) at++;
      const range = fights[at], combat = !!range && range.from <= cursor && range.to > cursor;
      const end = Math.min(b[0], range ? (combat ? range.to : range.from) : b[0]);
      append(between(a, b, cursor), between(a, b, end), combat);
      cursor = end;
    }
  }
  return out;
}

/** Clip recorded geometry to a playback window, including the interpolated position between samples. */
export function routePoints(segment: RouteSegment, from: number, to: number): PathPoint[] {
  const lo = Math.max(from, segment.from), hi = Math.min(to, segment.to);
  if (hi <= lo) return [];
  if (lo === segment.from && hi === segment.to) return segment.points;
  const points = segment.points;
  const at = (t: number) => {
    let i = 0;
    while (i < points.length - 2 && points[i + 1][0] < t) i++;
    return between(points[i], points[i + 1], t);
  };
  return [at(lo), ...points.filter(p => p[0] > lo && p[0] < hi), at(hi)];
}

// A farming route: from where you are, visit the chosen resource nodes of one zone in a sensible order.
// Nearest-neighbour start, then 2-opt until nothing improves (a few dozen stops is all the map can use anyway).
export type Pt = [number, number];
export type FarmRoute = { order: Pt[]; yards: number };

/** Distances are in yards, supplied by the caller (the planner knows how Azeroth's map maps to yards). */
export function farmRoute(points: Pt[], start: Pt | null, yards: (a: Pt, b: Pt) => number, maxStops = 40): FarmRoute {
  if (!points.length) return { order: [], yards: 0 };
  const nearest = (from: Pt, pool: Pt[]) => pool.reduce((best, p, i) => (yards(from, p) < yards(from, pool[best]) ? i : best), 0);
  // too many candidates: keep the ones closest to the start, so the route stays a walk and not a tour of the zone
  const anchor = start ?? points[0];
  const pool = [...points].sort((a, b) => yards(anchor, a) - yards(anchor, b)).slice(0, Math.max(maxStops * 3, maxStops));
  const order: Pt[] = [];
  let at = start ?? pool.splice(nearest(anchor, pool), 1)[0];
  if (!start) order.push(at);
  while (pool.length && order.length < maxStops) {
    const [next] = pool.splice(nearest(at, pool), 1);
    order.push(next);
    at = next;
  }
  const total = (list: Pt[]) => list.reduce((sum, p, i) => sum + (i ? yards(list[i - 1], p) : start ? yards(start, p) : 0), 0);
  // 2-opt on the open path: reversing a stretch is kept when it shortens the walk
  let improved = true;
  for (let rounds = 0; improved && rounds < 30; rounds++) {
    improved = false;
    for (let i = 0; i < order.length - 1; i++) for (let j = i + 1; j < order.length; j++) {
      const candidate = [...order.slice(0, i), ...order.slice(i, j + 1).reverse(), ...order.slice(j + 1)];
      if (total(candidate) + 1e-9 < total(order)) { order.splice(0, order.length, ...candidate); improved = true; }
    }
  }
  return { order, yards: total(order) };
}

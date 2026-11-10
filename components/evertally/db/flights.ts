// Flight network: shortest route by measured flight seconds (Dijkstra over the directed paths).
import type { Flights } from "./store";

export type Leg = { a: number; b: number; seconds: number; points: [number, number][] };
export type Plan = { legs: Leg[]; seconds: number };

export function planRoute(flights: Flights, from: number, to: number, faction: "A" | "H" | ""): Plan | null {
  const allowed = (id: number) => { const f = flights.nodes[String(id)]?.f; return Boolean(flights.nodes[String(id)]) && (!f || !faction || f === faction); };
  if (!allowed(from) || !allowed(to)) return null;
  const edges = new Map<number, Leg[]>();
  for (const path of flights.paths) {
    if (!allowed(path.a) || !allowed(path.b)) continue;
    const list = edges.get(path.a) ?? [];
    list.push({ a: path.a, b: path.b, seconds: path.s, points: path.p });
    edges.set(path.a, list);
  }
  const best = new Map<number, number>([[from, 0]]);
  const via = new Map<number, Leg>();
  const queue: [number, number][] = [[0, from]];
  while (queue.length) {
    queue.sort((x, y) => x[0] - y[0]);
    const [cost, node] = queue.shift()!;
    if (cost > (best.get(node) ?? Infinity)) continue;
    if (node === to) break;
    for (const leg of edges.get(node) ?? []) {
      const next = cost + leg.seconds + 10; // a short layover per hop
      if (next < (best.get(leg.b) ?? Infinity)) { best.set(leg.b, next); via.set(leg.b, leg); queue.push([next, leg.b]); }
    }
  }
  if (!via.has(to)) return null;
  const legs: Leg[] = [];
  for (let node = to; node !== from;) { const leg = via.get(node)!; legs.unshift(leg); node = leg.a; }
  return { legs, seconds: legs.reduce((sum, leg) => sum + leg.seconds, 0) };
}

export const clock = (seconds: number) => `${Math.floor(seconds / 60)}:${String(Math.round(seconds % 60)).padStart(2, "0")}`;

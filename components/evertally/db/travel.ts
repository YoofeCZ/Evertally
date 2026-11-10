// Journey planner: walking, flights, boats, zeppelins, lifts, the Deeprun Tram and portals, as one shortest-path search.
// The model follows Shortest Path Forever (GPL-3.0): fixed places ("hubs") joined by baked walking yards, measured flight
// seconds and transport timetables; where you start and where you go join the nearest hubs by straight-line estimates.
import type { Flights } from "./store";

export type Hub = { c: number; x: number; y: number; u?: number; v?: number; n?: string; f?: "A" | "H" };
export type TravelRoute = { id: number; k: "boat" | "zeppelin" | "lift" | "tram"; f?: "A" | "H"; site?: string; p: number; stops: [dock: string, arrive: number, depart: number][] };
export type TravelPortal = { n: string; k: "portal" | "passage"; a: string; b: string; s: number };
export type Landmass = { c: number; n: string; x0: number; x1: number; y0: number; y1: number };
export type Travel = {
  schema: 1; yards: Record<string, [number, number, number, number, number, number, number, number]>; hubs: Record<string, Hub>;
  walks: Record<string, Record<string, [number | null, number | null] | null>>; routes: TravelRoute[]; portals: TravelPortal[]; landmasses: Landmass[]; source: string;
};

export type Place = { label: string; u: number; v: number };
export type Mode = "walk" | "flight" | "boat" | "zeppelin" | "lift" | "tram" | "portal" | "passage";
/** One stretch of a walk between two points: a baked walk between fixed places, or a straight-line estimate from or to a free point. */
export type Leg = { points: [number, number][]; seconds: number; yards: number; estimated: boolean };
export type Step = {
  mode: Mode; from: string; to: string; seconds: number; wait?: number; yards?: number; estimated?: boolean;
  points: [number, number][];
  /** Walk steps only: the stretches the step is made of (ground.ts follows real ground along each). */
  legs?: Leg[];
  /** The line follows the walk mask (terrain.ts), not straight lines. */
  ground?: boolean;
};
export type Journey = { steps: Step[]; seconds: number };
export type Options = { side: "A" | "H"; speed: number; otherSide?: boolean };

export const SPEEDS = [7, 11.2, 14] as const;
/** A straight line is the shortest a walk can be; roads and hills add to it. */
const DETOUR = 1.3;
const BOARDING = 3;
const START_RADIUS = 9000;

// ---- yards <-> (u, v) ------------------------------------------------------------------------------------
/** The other way: yards on a continent -> Azeroth's map (u, v). */
export function fromYards(travel: Travel, c: number, x: number, y: number): [number, number] {
  const [, , , , au, bu, av, bv] = travel.yards[String(c)];
  return [au + bu * y, av + bv * x];
}
export function toYards(travel: Travel, u: number, v: number): { c: number; x: number; y: number } {
  // Kalimdor's map lies in the left of Azeroth's map, the Eastern Kingdoms in the right
  const c = u < 0.46 ? 1 : 0;
  const [, , , , au, bu, av, bv] = travel.yards[String(c)];
  return { c, x: (v - av) / bv, y: (u - au) / bu };
}

const landmass = (travel: Travel, c: number, x: number, y: number) => {
  const index = travel.landmasses.findIndex(l => l.c === c && x >= l.x0 && x <= l.x1 && y >= l.y0 && y <= l.y1);
  return index < 0 ? -1 : index;
};
const dist = (ax: number, ay: number, bx: number, by: number) => Math.hypot(ax - bx, ay - by);

// ---- graph ------------------------------------------------------------------------------------------------
type Edge = { to: string; mode: Mode; seconds: number; wait?: number; yards?: number; route?: number; estimated?: boolean; points?: [number, number][] };
type GroundEdge = Edge & { lowerYards: number; refined: boolean };
/** Real walking distance for a free leg: null means no traversable route, undefined means terrain is unavailable. */
export type GroundCost = (from: [number, number], to: [number, number]) => number | null | undefined;
type Graph = Map<string, Edge[]>;
const graphs = new WeakMap<Travel, WeakMap<Flights, Map<string, Graph>>>();

function buildGraph(travel: Travel, flights: Flights, options: Options): Graph {
  const key = `${options.side}:${options.speed}:${options.otherSide ? 1 : 0}`;
  let byFlights = graphs.get(travel);
  if (!byFlights) { byFlights = new WeakMap(); graphs.set(travel, byFlights); }
  let byOptions = byFlights.get(flights);
  if (!byOptions) { byOptions = new Map(); byFlights.set(flights, byOptions); }
  const cached = byOptions.get(key);
  if (cached) return cached;
  const graph: Graph = new Map();
  const add = (from: string, edge: Edge) => { const list = graph.get(from); if (list) list.push(edge); else graph.set(from, [edge]); };
  const allowed = (side: string | undefined) => !side || side === options.side || Boolean(options.otherSide);
  const hubPoint = (id: string) => { const hub = travel.hubs[id]; return hub && hub.u != null && hub.v != null ? [hub.u, hub.v] as [number, number] : null; };

  // baked walks between fixed places; "a b" is sorted, [forward, reverse]
  for (const table of Object.values(travel.walks)) {
    for (const [pair, cost] of Object.entries(table)) {
      if (!cost) continue;
      const [a, b] = pair.split(" ");
      if (!travel.hubs[a] || !travel.hubs[b]) continue;
      const pa = hubPoint(a), pb = hubPoint(b);
      if (cost[0] != null) add(a, { to: b, mode: "walk", yards: cost[0], seconds: cost[0] / options.speed, points: pa && pb ? [pa, pb] : [] });
      if (cost[1] != null) add(b, { to: a, mode: "walk", yards: cost[1], seconds: cost[1] / options.speed, points: pa && pb ? [pb, pa] : [] });
    }
  }
  // the Deeprun Tram's stations and passages sit on a map the baked walks do not cover: join places on the same map by straight lines
  const unwalked = Object.entries(travel.hubs).filter(([, hub]) => hub.c !== 0 && hub.c !== 1 && hub.c !== 2991);
  for (const [a, ha] of unwalked) for (const [b, hb] of unwalked) {
    if (a !== b && ha.c === hb.c) add(a, { to: b, mode: "walk", yards: dist(ha.x, ha.y, hb.x, hb.y), seconds: dist(ha.x, ha.y, hb.x, hb.y) / options.speed, estimated: true, points: [] });
  }
  // flights
  for (const path of flights.paths) {
    const na = flights.nodes[String(path.a)], nb = flights.nodes[String(path.b)];
    if (!na || !nb || !allowed(na.f) || !allowed(nb.f)) continue;
    add(`taxi${path.a}`, { to: `taxi${path.b}`, mode: "flight", seconds: path.s + BOARDING, points: path.p });
  }
  // portals and passages
  for (const portal of travel.portals) add(portal.a, { to: portal.b, mode: portal.k, seconds: portal.s, points: [hubPoint(portal.a), hubPoint(portal.b)].filter((p): p is [number, number] => Boolean(p)) });
  // boats, zeppelins, lifts and the tram: expected wait is half a loop, then the ride
  for (const route of travel.routes) {
    if (!allowed(route.f)) continue;
    const n = route.stops.length;
    route.stops.forEach(([dock, , depart], i) => {
      for (let offset = 1; offset < n; offset++) {
        const [onward, arrive] = route.stops[(i + offset) % n];
        if (onward === dock) continue;
        const ride = (((arrive - depart) % route.p) + route.p) % route.p / 1000;
        const pa = hubPoint(dock), pb = hubPoint(onward);
        add(dock, { to: onward, mode: route.k, route: route.id, wait: route.p / 2000, seconds: route.p / 2000 + ride, points: pa && pb ? [pa, pb] : [] });
      }
    });
  }
  byOptions.set(key, graph);
  return graph;
}

// ---- search ------------------------------------------------------------------------------------------------
export function planJourney(travel: Travel, flights: Flights, from: Place, to: Place, options: Options, groundCost?: GroundCost): Journey | null {
  const base = buildGraph(travel, flights, options);
  const a = toYards(travel, from.u, from.v), b = toYards(travel, to.u, to.v);
  const aMass = landmass(travel, a.c, a.x, a.y), bMass = landmass(travel, b.c, b.x, b.y);
  const extra = new Map<string, Edge[]>();
  const link = (list: Edge[], edge: Edge) => list.push(edge);
  const start: Edge[] = [];
  const startKey = "@start", goalKey = "@goal";
  const freeLeg = (edge: Edge, straight: number): Edge => {
    if (!groundCost) return edge;
    // Straight-line distance is an optimistic bound. Refine only candidates that
    // can actually win the shortest-path search, then search again.
    return { ...edge, yards: straight, seconds: straight / options.speed, lowerYards: straight, refined: false } as GroundEdge;
  };

  // joining a free point to the nearby fixed places (walking, straight line estimate)
  const nearby = (p: { c: number; x: number; y: number }, mass: number, into: (hub: string, yards: number) => void) => {
    for (const [id, hub] of Object.entries(travel.hubs)) {
      if (hub.c !== p.c || hub.c > 1) continue;
      if (landmass(travel, hub.c, hub.x, hub.y) !== mass) continue;
      const d = dist(p.x, p.y, hub.x, hub.y);
      if (d <= START_RADIUS) into(id, d * DETOUR);
    }
  };
  nearby(a, aMass, (hub, yards) => link(start, freeLeg({ to: hub, mode: "walk", yards, seconds: yards / options.speed, estimated: true, points: [[from.u, from.v], travel.hubs[hub].u != null ? [travel.hubs[hub].u!, travel.hubs[hub].v!] : [from.u, from.v]] }, yards / DETOUR)));
  if (a.c === b.c && aMass === bMass) {
    const d = dist(a.x, a.y, b.x, b.y) * DETOUR;
    link(start, freeLeg({ to: goalKey, mode: "walk", yards: d, seconds: d / options.speed, estimated: true, points: [[from.u, from.v], [to.u, to.v]] }, d / DETOUR));
  }
  nearby(b, bMass, (hub, yards) => {
    const list = extra.get(hub) ?? [];
    list.push(freeLeg({ to: goalKey, mode: "walk", yards, seconds: yards / options.speed, estimated: true, points: [travel.hubs[hub].u != null ? [travel.hubs[hub].u!, travel.hubs[hub].v!] : [to.u, to.v], [to.u, to.v]] }, yards / DETOUR));
    extra.set(hub, list);
  });

  const edgesOf = (id: string): Edge[] => id === startKey ? start : [...(base.get(id) ?? []), ...(extra.get(id) ?? [])];
  let best: Map<string, number>;
  let chain: { from: string; edge: Edge }[];
  for (;;) {
    best = new Map([[startKey, 0]]);
    const via = new Map<string, { from: string; edge: Edge }>();
    const queue: [number, string][] = [[0, startKey]];
    while (queue.length) {
      queue.sort((x, y) => x[0] - y[0]);
      const [cost, node] = queue.shift()!;
      if (cost > (best.get(node) ?? Infinity)) continue;
      if (node === goalKey) break;
      for (const edge of edgesOf(node)) {
        const next = cost + edge.seconds;
        if (next < (best.get(edge.to) ?? Infinity)) { best.set(edge.to, next); via.set(edge.to, { from: node, edge }); queue.push([next, edge.to]); }
      }
    }
    if (!via.has(goalKey)) return null;
    chain = [];
    for (let node = goalKey; node !== startKey;) { const step = via.get(node)!; chain.unshift({ from: step.from, edge: step.edge }); node = step.from; }
    const candidate = chain.map(step => step.edge).find(edge => "refined" in edge && !(edge as GroundEdge).refined) as GroundEdge | undefined;
    if (!candidate || !groundCost) break;
    const points = candidate.points!;
    const distance = groundCost(points[0], points[points.length - 1]);
    const yards = distance === null ? Infinity : distance === undefined ? candidate.lowerYards * DETOUR : Math.max(candidate.lowerYards, distance);
    candidate.yards = yards;
    candidate.seconds = yards / options.speed;
    candidate.refined = true;
  }

  // Name the places and merge neighbouring walks into one step.
  const label = (id: string) => id === startKey ? from.label : id === goalKey ? to.label : travel.hubs[id]?.n ?? id;
  const steps: Step[] = [];
  for (const { from: f, edge } of chain) {
    const last = steps[steps.length - 1];
    if (edge.mode === "walk" && last?.mode === "walk") {
      last.to = label(edge.to);
      last.seconds += edge.seconds;
      last.yards = (last.yards ?? 0) + (edge.yards ?? 0);
      last.estimated = last.estimated || edge.estimated;
      last.points.push(...(edge.points ?? []).slice(1));
      last.legs!.push({ points: [...(edge.points ?? [])], seconds: edge.seconds, yards: edge.yards ?? 0, estimated: Boolean(edge.estimated) });
      continue;
    }
    steps.push({ mode: edge.mode, from: label(f), to: label(edge.to), seconds: edge.seconds, wait: edge.wait, yards: edge.yards, estimated: edge.estimated, points: [...(edge.points ?? [])],
      ...(edge.mode === "walk" ? { legs: [{ points: [...(edge.points ?? [])], seconds: edge.seconds, yards: edge.yards ?? 0, estimated: Boolean(edge.estimated) }] } : {}) });
  }
  // a walk between two places that are the same spot (a portal's exit and the next flight master) costs nothing worth showing
  const meaningful = steps.filter(step => !(step.mode === "walk" && step.seconds < 2));
  return { steps: meaningful, seconds: best.get(goalKey)! };
}

/**
 * Seconds from a free point to every fixed place (flight masters, docks, portals ...) in one search, by the same rules as
 * planJourney; places that cannot be reached are absent. This is what a fair meeting place is picked from.
 */
export function reachTimes(travel: Travel, flights: Flights, from: Place, options: Options): Map<string, number> {
  const base = buildGraph(travel, flights, options);
  const a = toYards(travel, from.u, from.v);
  const mass = landmass(travel, a.c, a.x, a.y);
  const start: Edge[] = [];
  for (const [id, hub] of Object.entries(travel.hubs)) {
    if (hub.c !== a.c || hub.c > 1 || landmass(travel, hub.c, hub.x, hub.y) !== mass) continue;
    const d = dist(a.x, a.y, hub.x, hub.y);
    if (d <= START_RADIUS) start.push({ to: id, mode: "walk", yards: d * DETOUR, seconds: d * DETOUR / options.speed, estimated: true });
  }
  const best = new Map<string, number>();
  const queue: [number, string][] = start.map(edge => [edge.seconds, edge.to] as [number, string]);
  for (const [cost, id] of queue) best.set(id, Math.min(cost, best.get(id) ?? Infinity));
  while (queue.length) {
    queue.sort((x, y) => x[0] - y[0]);
    const [cost, node] = queue.shift()!;
    if (cost > (best.get(node) ?? Infinity)) continue;
    for (const edge of base.get(node) ?? []) {
      const next = cost + edge.seconds;
      if (next < (best.get(edge.to) ?? Infinity)) { best.set(edge.to, next); queue.push([next, edge.to]); }
    }
  }
  return best;
}

export const clockText = (seconds: number) => {
  const total = Math.round(seconds);
  const h = Math.floor(total / 3600), m = Math.floor((total % 3600) / 60), s = total % 60;
  return h ? `${h}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}` : `${m}:${String(s).padStart(2, "0")}`;
};

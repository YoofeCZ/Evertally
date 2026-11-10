// Walking on real ground: a walk mask of the continents (tools/build_walkmask.py, from Shortest Path Forever's terrain bake) and a
// path search over it. Points are in the game's yard frame (x north, y west), the same frame as travel.ts. The mask only knows
// where you can stand (0 blocked, 1 ground, 2 water); it does not know cliffs between neighbouring cells or the floors of tunnels
// and cities, so a route can be a little optimistic. Everything is plain arithmetic; there is no network after the mask is loaded.

export type WalkMap = { id: number; x0: number; y0: number; cell: number; nx: number; ny: number; data: Uint8Array };
export type Walk = Map<number, WalkMap>;
export type Pt = [number, number];
/** `yards` is the length of the drawn (smoothed) line; `grid` the length along the cells, which is what a walker covers on rough ground. */
export type Found = { points: Pt[]; yards: number; grid: number; snapped: boolean };

const WATER = 3; // swimming is slow: the search prefers land unless the shore is far
const SNAP_CELLS = 14; // an endpoint in a blocked cell moves to the nearest open one within this many cells
const SQRT2 = Math.SQRT2;

async function inflate(bytes: Uint8Array): Promise<Uint8Array> {
  const stream = new Blob([bytes as BlobPart]).stream().pipeThrough(new DecompressionStream("deflate"));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

/** Reads walk.bin (see tools/build_walkmask.py for the format). */
export async function parseWalk(buffer: ArrayBuffer): Promise<Walk> {
  const view = new DataView(buffer);
  const bytes = new Uint8Array(buffer);
  if (String.fromCharCode(...bytes.subarray(0, 4)) !== "EVWM" || view.getUint8(4) !== 1) throw new Error("not a walk mask");
  const count = view.getUint8(5);
  const out: Walk = new Map();
  let at = 6;
  for (let i = 0; i < count; i++) {
    const id = view.getInt16(at, true), x0 = view.getFloat32(at + 2, true), y0 = view.getFloat32(at + 6, true), cell = view.getFloat32(at + 10, true);
    const nx = view.getUint16(at + 14, true), ny = view.getUint16(at + 16, true), length = view.getUint32(at + 18, true);
    at += 22;
    const data = await inflate(bytes.subarray(at, at + length));
    if (data.length !== nx * ny) throw new Error(`walk mask ${id}: ${data.length} bytes, expected ${nx * ny}`);
    out.set(id, { id, x0, y0, cell, nx, ny, data });
    at += length;
  }
  return out;
}

const cellOf = (map: WalkMap, x: number, y: number): [number, number] => [Math.floor((x - map.x0) / map.cell), Math.floor((y - map.y0) / map.cell)];
const centre = (map: WalkMap, cx: number, cy: number): Pt => [map.x0 + (cx + 0.5) * map.cell, map.y0 + (cy + 0.5) * map.cell];
const inside = (map: WalkMap, cx: number, cy: number) => cx >= 0 && cy >= 0 && cx < map.nx && cy < map.ny;

/** True when the place can be stood on. */
export function walkable(map: WalkMap, x: number, y: number): boolean {
  const [cx, cy] = cellOf(map, x, y);
  return inside(map, cx, cy) && map.data[cx * map.ny + cy] !== 0;
}

function snap(map: WalkMap, cx: number, cy: number): [number, number] | null {
  if (inside(map, cx, cy) && map.data[cx * map.ny + cy] !== 0) return [cx, cy];
  for (let r = 1; r <= SNAP_CELLS; r++) {
    let best: [number, number] | null = null, bestD = Infinity;
    for (let dx = -r; dx <= r; dx++) for (let dy = -r; dy <= r; dy++) {
      if (Math.max(Math.abs(dx), Math.abs(dy)) !== r) continue;
      const x = cx + dx, y = cy + dy;
      if (inside(map, x, y) && map.data[x * map.ny + y] !== 0 && dx * dx + dy * dy < bestD) { best = [x, y]; bestD = dx * dx + dy * dy; }
    }
    if (best) return best;
  }
  return null;
}

// a binary min-heap on (priority, node) pairs held in typed arrays
class Heap {
  private priority: Float32Array;
  private node: Int32Array;
  size = 0;
  constructor(capacity: number) { this.priority = new Float32Array(capacity); this.node = new Int32Array(capacity); }
  push(p: number, n: number) {
    if (this.size === this.priority.length) {
      const bigger = new Float32Array(this.size * 2); bigger.set(this.priority); this.priority = bigger;
      const nodes = new Int32Array(this.size * 2); nodes.set(this.node); this.node = nodes;
    }
    let i = this.size++;
    while (i > 0) {
      const parent = (i - 1) >> 1;
      if (this.priority[parent] <= p) break;
      this.priority[i] = this.priority[parent]; this.node[i] = this.node[parent]; i = parent;
    }
    this.priority[i] = p; this.node[i] = n;
  }
  pop(): number {
    const top = this.node[0];
    const p = this.priority[--this.size], n = this.node[this.size];
    let i = 0;
    for (;;) {
      let child = 2 * i + 1;
      if (child >= this.size) break;
      if (child + 1 < this.size && this.priority[child + 1] < this.priority[child]) child++;
      if (this.priority[child] >= p) break;
      this.priority[i] = this.priority[child]; this.node[i] = this.node[child]; i = child;
    }
    this.priority[i] = p; this.node[i] = n;
    return top;
  }
}

// Greedy string pulling over dry land: drop every point the next-but-one can be seen from. Water stretches keep their points.
function lineClear(map: WalkMap, a: [number, number], b: [number, number]): boolean {
  let x = a[0], y = a[1];
  const dx = Math.abs(b[0] - a[0]), dy = Math.abs(b[1] - a[1]);
  const sx = a[0] < b[0] ? 1 : -1, sy = a[1] < b[1] ? 1 : -1;
  let err = dx - dy;
  for (;;) {
    if (map.data[x * map.ny + y] !== 1) return false;
    if (x === b[0] && y === b[1]) return true;
    const e2 = 2 * err;
    // a diagonal step must not squeeze between two blocked corners
    if (e2 > -dy && e2 < dx) {
      if (map.data[(x + sx) * map.ny + y] !== 1 || map.data[x * map.ny + y + sy] !== 1) return false;
    }
    if (e2 > -dy) { err -= dy; x += sx; }
    if (e2 < dx) { err += dx; y += sy; }
  }
}
function pull(map: WalkMap, cells: [number, number][]): [number, number][] {
  if (cells.length < 3) return cells;
  const out: [number, number][] = [cells[0]];
  let anchor = 0;
  for (let i = 2; i < cells.length; i++) {
    if (!lineClear(map, cells[anchor], cells[i])) { out.push(cells[i - 1]); anchor = i - 1; }
  }
  out.push(cells[cells.length - 1]);
  return out;
}

/**
 * The cheapest way on foot between two points of one continent, or null (an end that is nowhere near open ground, or no
 * connection). Most walks stay near the straight line, so the search first looks only at a window around the two points and
 * widens it when that finds nothing (a bay or a mountain range in between): 90 cells, 400 cells, the whole map.
 */
export function findPath(map: WalkMap, from: Pt, to: Pt, margin?: number): Found | null {
  for (const m of margin === undefined ? [90, 400, Math.max(map.nx, map.ny)] : [margin]) {
    const found = search(map, from, to, m);
    if (found) return found;
  }
  return null;
}

function search(map: WalkMap, from: Pt, to: Pt, margin: number): Found | null {
  const [fx, fy] = cellOf(map, from[0], from[1]);
  const [tx, ty] = cellOf(map, to[0], to[1]);
  const a = snap(map, fx, fy), b = snap(map, tx, ty);
  if (!a || !b) return null;
  const snapped = a[0] !== fx || a[1] !== fy || b[0] !== tx || b[1] !== ty;
  const x0 = Math.max(0, Math.min(a[0], b[0]) - margin), x1 = Math.min(map.nx - 1, Math.max(a[0], b[0]) + margin);
  const y0 = Math.max(0, Math.min(a[1], b[1]) - margin), y1 = Math.min(map.ny - 1, Math.max(a[1], b[1]) + margin);
  const w = y1 - y0 + 1, h = x1 - x0 + 1;
  const total = w * h;
  const g = new Float32Array(total).fill(Infinity);
  const from_ = new Int32Array(total).fill(-1);
  const closed = new Uint8Array(total);
  const index = (cx: number, cy: number) => (cx - x0) * w + (cy - y0);
  const start = index(a[0], a[1]), goal = index(b[0], b[1]);
  const heuristic = (cx: number, cy: number) => {
    const dx = Math.abs(cx - b[0]), dy = Math.abs(cy - b[1]);
    return (dx + dy) + (SQRT2 - 2) * Math.min(dx, dy);
  };
  const heap = new Heap(4096);
  g[start] = 0; heap.push(heuristic(a[0], a[1]), start);
  const DX = [1, -1, 0, 0, 1, 1, -1, -1], DY = [0, 0, 1, -1, 1, -1, 1, -1];
  let found = false;
  while (heap.size) {
    const here = heap.pop();
    if (closed[here]) continue;
    closed[here] = 1;
    if (here === goal) { found = true; break; }
    const cx = x0 + Math.floor(here / w), cy = y0 + (here % w);
    for (let d = 0; d < 8; d++) {
      const nx = cx + DX[d], ny = cy + DY[d];
      if (nx < x0 || nx > x1 || ny < y0 || ny > y1) continue;
      const value = map.data[nx * map.ny + ny];
      if (value === 0) continue;
      if (d >= 4 && (map.data[(cx + DX[d]) * map.ny + cy] === 0 || map.data[cx * map.ny + cy + DY[d]] === 0)) continue; // no cutting corners
      const next = index(nx, ny);
      if (closed[next]) continue;
      const cost = g[here] + (d >= 4 ? SQRT2 : 1) * (value === 2 ? WATER : 1);
      if (cost < g[next]) { g[next] = cost; from_[next] = here; heap.push(cost + heuristic(nx, ny), next); }
    }
  }
  if (!found) return null;
  const cells: [number, number][] = [];
  for (let at = goal; at !== -1; at = from_[at]) cells.push([x0 + Math.floor(at / w), y0 + (at % w)]);
  cells.reverse();
  let grid = 0;
  for (let i = 1; i < cells.length; i++) grid += (cells[i][0] !== cells[i - 1][0] && cells[i][1] !== cells[i - 1][1] ? SQRT2 : 1) * map.cell;
  const pulled = pull(map, cells);
  const points: Pt[] = pulled.map(([cx, cy]) => centre(map, cx, cy));
  // the drawn line starts and ends exactly where the caller said; an end that had to be moved onto open ground gets a short stub
  if (!snapped) { points[0] = [from[0], from[1]]; points[points.length - 1] = [to[0], to[1]]; }
  else { points.unshift([from[0], from[1]]); points.push([to[0], to[1]]); }
  let yards = 0;
  for (let i = 1; i < points.length; i++) yards += Math.hypot(points[i][0] - points[i - 1][0], points[i][1] - points[i - 1][1]);
  return { points, yards, grid, snapped };
}

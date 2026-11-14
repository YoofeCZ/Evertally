// A recorded journey ("kronika") and everything the player needs to replay it. Pure functions, no browser and no server:
// the recording is one file that is played back entirely in the visitor's browser.

export type EventKind = "quest" | "kill" | "loot" | "money" | "level" | "skill" | "zone" | "death" | "dungeon" | "travel";
/** The groups shown as filter chips next to the list of moments. */
export type Category = "quests" | "combat" | "loot" | "professions" | "travel" | "character";
export const CATEGORIES: readonly Category[] = ["quests", "combat", "loot", "professions", "travel", "character"];
const CATEGORY_OF: Record<EventKind, Category> = {
  quest: "quests", kill: "combat", death: "combat", loot: "loot", money: "loot", skill: "professions",
  zone: "travel", travel: "travel", dungeon: "travel", level: "character",
};
export const categoryOf = (kind: EventKind): Category => CATEGORY_OF[kind];

export type ChronicleEvent = {
  /** Seconds from the start of the recording. */
  t: number; k: EventKind;
  /** Short text shown in the list and above the character. */
  text: string;
  /** quest: accept | done | turnin; dungeon: enter | leave; travel: flight | hearth | portal. */
  a?: string;
  /** Quantity (loot), copper (money, may be negative), new level (level), skill value (skill). */
  n?: number; max?: number;
  /** Experience gained (kill, quest turn-in). */
  xp?: number;
  /** Item quality 0 to 5. */
  q?: number;
  /** Where it happened: index into `zones` and the position 0 to 1 inside that zone. */
  zone?: number; x?: number; y?: number;
};
/** One position sample: seconds, index into `zones`, x and y from 0 to 1 inside the zone. */
export type PathPoint = [t: number, zone: number, x: number, y: number];
export type Chronicle = {
  v: 1;
  character: { name: string; classId: number; race?: string; faction?: string; realm?: string; guild?: string; level: number };
  /** Unix time of the start of the recording, seconds. */
  startedAt: number;
  /** Length of the recording, seconds. */
  duration: number;
  /** Map keys of /media/maps (for example "darkshore"). */
  zones: string[];
  path: PathPoint[];
  events: ChronicleEvent[];
};

export const MAX_EVENTS = 200_000;
export const MAX_PATH = 400_000;
const KINDS = new Set<string>(Object.keys(CATEGORY_OF));
const finite = (v: unknown): v is number => typeof v === "number" && Number.isFinite(v);
const unit = (v: unknown): v is number => finite(v) && v >= 0 && v <= 1;
const short = (v: unknown, max = 160): v is string => typeof v === "string" && v.length <= max;

/** Checks a loaded file. Returns the recording, or null when anything in it cannot be trusted. Nothing is repaired. */
export function parseChronicle(raw: unknown): Chronicle | null {
  const c = raw as Partial<Chronicle> | null;
  if (!c || typeof c !== "object" || c.v !== 1) return null;
  const who = c.character;
  if (!who || !short(who.name, 64) || !finite(who.classId) || !finite(who.level)) return null;
  for (const key of ["race", "faction", "realm", "guild"] as const) if (who[key] !== undefined && !short(who[key], 80)) return null;
  if (!finite(c.startedAt) || !finite(c.duration) || c.duration <= 0) return null;
  if (!Array.isArray(c.zones) || !c.zones.length || c.zones.length > 500 || !c.zones.every(z => typeof z === "string" && /^[a-z0-9][a-z0-9-]{0,79}$/.test(z))) return null;
  if (!Array.isArray(c.path) || c.path.length > MAX_PATH || !Array.isArray(c.events) || c.events.length > MAX_EVENTS) return null;
  const zones = c.zones.length;
  let last = -Infinity;
  for (const p of c.path) {
    if (!Array.isArray(p) || p.length !== 4 || !finite(p[0]) || p[0] < last || p[0] > c.duration + 1 || !Number.isInteger(p[1]) || p[1] < 0 || p[1] >= zones || !unit(p[2]) || !unit(p[3])) return null;
    last = p[0];
  }
  last = -Infinity;
  for (const e of c.events) {
    if (!e || !finite(e.t) || e.t < last || e.t > c.duration + 1 || !KINDS.has(e.k) || !short(e.text)) return null;
    if ((e.a !== undefined && !short(e.a, 24)) || (e.n !== undefined && !finite(e.n)) || (e.max !== undefined && !finite(e.max)) || (e.xp !== undefined && !finite(e.xp)) || (e.q !== undefined && !(Number.isInteger(e.q) && e.q >= 0 && e.q <= 5))) return null;
    if (e.zone !== undefined && !(Number.isInteger(e.zone) && e.zone >= 0 && e.zone < zones)) return null;
    if ((e.x !== undefined && !unit(e.x)) || (e.y !== undefined && !unit(e.y))) return null;
    last = e.t;
  }
  return c as Chronicle;
}

/** The first index whose time is greater than `t` (so `index - 1` is the last one at or before it). */
function upper<T>(items: readonly T[], t: number, at: (item: T) => number): number {
  let lo = 0, hi = items.length;
  while (lo < hi) { const mid = (lo + hi) >> 1; if (at(items[mid]) <= t) lo = mid + 1; else hi = mid; }
  return lo;
}

export type Position = { zone: number; x: number; y: number; /** moved during the last few seconds */ moving: boolean };
/** Where the character is at `t`: between two samples of the same zone it is interpolated, across a gap or a zone change it holds. */
export function positionAt(c: Chronicle, t: number): Position | null {
  const path = c.path;
  if (!path.length) return null;
  const i = upper(path, t, p => p[0]) - 1;
  if (i < 0) return { zone: path[0][1], x: path[0][2], y: path[0][3], moving: false };
  const a = path[i], b = path[i + 1];
  if (!b || b[1] !== a[1] || b[0] - a[0] > 15 || b[0] <= a[0]) return { zone: a[1], x: a[2], y: a[3], moving: !!b && b[1] === a[1] && t - a[0] < 3 };
  const f = Math.min(1, Math.max(0, (t - a[0]) / (b[0] - a[0])));
  return { zone: a[1], x: a[2] + (b[2] - a[2]) * f, y: a[3] + (b[3] - a[3]) * f, moving: a[2] !== b[2] || a[3] !== b[3] };
}

/** The samples of the zone the character is in at `t`, from `since` seconds before it, back to the moment it entered the zone. */
export function pathWindow(c: Chronicle, t: number, since: number): PathPoint[] {
  const end = upper(c.path, t, p => p[0]);
  if (end <= 0) return [];
  const zone = c.path[end - 1][1];
  let start = end - 1;
  const from = t - since;
  while (start > 0 && c.path[start - 1][1] === zone && c.path[start - 1][0] >= from) start--;
  return c.path.slice(start, end);
}

/** Zone visits in order: each is one run of samples in the same zone. */
export type Visit = { zone: number; from: number; to: number };
export function visits(c: Chronicle): Visit[] {
  const out: Visit[] = [];
  for (const [t, zone] of c.path) {
    const last = out[out.length - 1];
    if (last && last.zone === zone) last.to = t; else out.push({ zone, from: out.length ? out[out.length - 1].to : 0, to: t });
  }
  if (out.length) { out[0].from = 0; out[out.length - 1].to = c.duration; }
  return out;
}

export type Totals = { quests: number; kills: number; xp: number; copper: number; items: number; places: number; deaths: number; level: number; skills: Record<string, [number, number]> };
export type Index = { c: Chronicle; totals: Totals[] };
const ZERO = (level: number): Totals => ({ quests: 0, kills: 0, xp: 0, copper: 0, items: 0, places: 0, deaths: 0, level, skills: {} });

/** Running totals after each event, so the "so far" numbers at any moment are one binary search away. */
export function buildIndex(c: Chronicle): Index {
  const totals: Totals[] = [];
  const seen = new Set<number>();
  if (c.path.length) seen.add(c.path[0][1]);
  let now = ZERO(c.character.level);
  now.places = seen.size;
  for (const e of c.events) {
    const next = { ...now };
    if (e.k === "quest" && e.a === "turnin") next.quests++;
    if (e.k === "kill") next.kills++;
    if (e.k === "death") next.deaths++;
    if (e.xp) next.xp += e.xp;
    if (e.k === "money" && e.n) next.copper += e.n;
    if (e.k === "loot") next.items += e.n ?? 1;
    if (e.k === "level" && e.n) next.level = e.n;
    if (e.k === "skill" && e.n !== undefined) next.skills = { ...now.skills, [e.text]: [e.n, e.max ?? e.n] };
    if (e.k === "zone" && e.zone !== undefined && !seen.has(e.zone)) { seen.add(e.zone); next.places = seen.size; }
    totals.push(next); now = next;
  }
  return { c, totals };
}
export function totalsAt(index: Index, t: number): Totals {
  const n = upper(index.c.events, t, e => e.t);
  if (n > 0) return index.totals[n - 1];
  const zero = ZERO(index.c.character.level);
  zero.places = index.c.path.length ? 1 : 0;
  return zero;
}

/** The newest event at or before `t` that matches `allowed` (every category when omitted), and its index. */
export function eventAt(c: Chronicle, t: number, allowed?: ReadonlySet<Category>): number {
  let i = upper(c.events, t, e => e.t) - 1;
  while (i >= 0 && allowed && !allowed.has(categoryOf(c.events[i].k))) i--;
  return i;
}

export function countByCategory(c: Chronicle): Record<Category, number> {
  const out: Record<Category, number> = { quests: 0, combat: 0, loot: 0, professions: 0, travel: 0, character: 0 };
  for (const e of c.events) out[categoryOf(e.k)]++;
  return out;
}

/** 1h 02m 03s style, or 2:03 for short spans. */
export function clock(seconds: number): string {
  const s = Math.max(0, Math.floor(seconds));
  const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), r = s % 60;
  const two = (n: number) => String(n).padStart(2, "0");
  return h ? `${h}:${two(m)}:${two(r)}` : `${m}:${two(r)}`;
}
export function moneyText(copper: number): string {
  const sign = copper < 0 ? "−" : "";
  const v = Math.abs(Math.trunc(copper));
  const g = Math.floor(v / 10000), s = Math.floor((v % 10000) / 100), c = v % 100;
  return `${sign}${g ? `${g}g ` : ""}${g || s ? `${s}s ` : ""}${c}c`;
}

// ---- demo recording ---------------------------------------------------------------------------------------------
// The addon does not write this kind of recording yet. This generates a believable one (not a real player's), so the player
// can be seen working. The same seed always gives the same journey.
function rng(seed: number) {
  let a = seed >>> 0;
  return () => { a = (a + 0x6d2b79f5) >>> 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
}
type Leg = { zone: string; route: [number, number][]; mobs: string[]; quests: string[]; ore?: string };
const LEGS: Leg[] = [
  { zone: "teldrassil", route: [[0.55, 0.78], [0.5, 0.65], [0.42, 0.55], [0.5, 0.42], [0.62, 0.36], [0.55, 0.24]], mobs: ["Mangy Nightsaber", "Thistle Boar", "Webwood Spider", "Strigid Owl"], quests: ["The Balance of Nature", "Etched Sigil", "Webwood Venom"], ore: "Herbalism" },
  { zone: "darkshore", route: [[0.4, 0.82], [0.42, 0.7], [0.46, 0.58], [0.4, 0.46], [0.45, 0.34], [0.5, 0.22]], mobs: ["Foreststrider Fledgling", "Thistle Bear", "Vile Sprite", "Wild Grell"], quests: ["Thresher Eye", "Tools of the Highborne", "The Fall of Ameth'Aran"], ore: "Skinning" },
  { zone: "ashenvale", route: [[0.3, 0.7], [0.4, 0.62], [0.52, 0.55], [0.6, 0.45], [0.7, 0.36], [0.62, 0.25]], mobs: ["Elder Ashenvale Bear", "Dryad Warden", "Satyr Rogue", "Ghostpaw Alpha"], quests: ["Raene's Cleansing", "The Zoram Strand", "Orendil's Cure"], ore: "Mining" },
];
const LOOT: [string, number][] = [["Ruined Leather Scraps", 1], ["Light Feather", 1], ["Strider Meat", 1], ["Thistle Bear Pelt", 2], ["Linen Cloth", 1], ["Spider Silk", 2], ["Copper Bar", 1], ["Heavy Hide", 2], ["Mageweave Cloth", 3]];

export function demoChronicle(seed = 7): Chronicle {
  const rand = rng(seed);
  const zones = LEGS.map(l => l.zone);
  const path: PathPoint[] = [];
  const events: ChronicleEvent[] = [];
  let t = 0, xpTotal = 0, level = 14;
  const skill: Record<string, number> = { Herbalism: 41, Skinning: 88, Mining: 57 };
  const push = (e: ChronicleEvent) => events.push({ ...e, t: Math.round(e.t * 10) / 10 });
  const need = (l: number) => 600 + l * 140;
  LEGS.forEach((leg, zi) => {
    if (zi) { push({ t, k: "zone", text: `Entered ${leg.zone.replace(/-/g, " ")}`, zone: zi, x: leg.route[0][0], y: leg.route[0][1] }); }
    const quests = leg.quests.map((name, i) => ({ name, at: i * 2, got: false, done: false, x: 0, y: 0 }));
    leg.route.forEach(([wx, wy], wi) => {
      const [px, py] = wi ? leg.route[wi - 1] : [wx, wy];
      const dist = Math.hypot(wx - px, wy - py);
      const steps = wi ? Math.max(8, Math.round(dist / 0.0009)) : 1;
      for (let s = 1; s <= steps; s++) {
        const f = s / steps;
        const x = Math.min(0.97, Math.max(0.03, px + (wx - px) * f + (rand() - 0.5) * 0.006));
        const y = Math.min(0.97, Math.max(0.03, py + (wy - py) * f + (rand() - 0.5) * 0.006));
        t += 2; path.push([t, zi, Math.round(x * 1e4) / 1e4, Math.round(y * 1e4) / 1e4]);
        if (wi === 0 && s === 1) continue;
        const here = { zone: zi, x: Math.round(x * 1e4) / 1e4, y: Math.round(y * 1e4) / 1e4 };
        const roll = rand();
        if (roll < 0.075) {
          // a fight: a few kills, loot and a little money
          const kills = 1 + Math.floor(rand() * 3);
          for (let k = 0; k < kills; k++) {
            const xp = 38 + Math.floor(rand() * 30) + level * 2;
            xpTotal += xp;
            push({ t: t + k * 3, k: "kill", text: leg.mobs[Math.floor(rand() * leg.mobs.length)], xp, ...here });
            if (rand() < 0.65) { const [name, q] = LOOT[Math.floor(rand() * LOOT.length)]; push({ t: t + k * 3 + 1, k: "loot", text: name, n: 1 + Math.floor(rand() * 2), q: q > 2 ? 2 : q === 2 ? 1 : 0, ...here }); }
            if (rand() < 0.5) push({ t: t + k * 3 + 1.2, k: "money", text: "Money", n: 4 + Math.floor(rand() * 60), ...here });
          }
          t += kills * 3;
          if (xpTotal >= need(level)) { xpTotal -= need(level); level++; push({ t, k: "level", text: `Reached level ${level}`, n: level, ...here }); }
          if (rand() < 0.012) push({ t: t + 2, k: "death", text: "You died", ...here });
        } else if (roll < 0.095 && leg.ore) {
          const name = leg.ore;
          skill[name] = Math.min(150, skill[name] + (rand() < 0.7 ? 1 : 0));
          push({ t, k: "skill", text: name, n: skill[name], max: 150, ...here });
          t += 4;
        }
        for (const q of quests) {
          const progress = wi / leg.route.length;
          if (!q.got && progress >= q.at / 8) { q.got = true; q.x = here.x; q.y = here.y; push({ t, k: "quest", a: "accept", text: q.name, ...here }); }
          else if (q.got && !q.done && progress >= (q.at / 8) + 0.35) {
            q.done = true;
            const xp = 120 + level * 22; xpTotal += xp;
            push({ t, k: "quest", a: "turnin", text: q.name, xp, ...here });
            push({ t: t + 0.8, k: "money", text: "Quest reward", n: 100 + Math.floor(rand() * 400), ...here });
          }
        }
      }
    });
    if (zi < LEGS.length - 1) {
      // a few quiet minutes of riding on to the next zone
      push({ t, k: "travel", a: "flight", text: "Took the flight to the next zone", zone: zi, x: leg.route[leg.route.length - 1][0], y: leg.route[leg.route.length - 1][1] });
      t += 6;
    }
  });
  events.sort((a, b) => a.t - b.t);
  const duration = Math.ceil(t + 8);
  return {
    v: 1,
    character: { name: "Demo Wanderer", classId: 11, race: "Night Elf", faction: "Alliance", realm: "Demo", guild: "Evertally", level: 14 },
    startedAt: 1_794_300_000, duration, zones, path, events,
  };
}

/** The events with `from < t <= to`, oldest first. */
export function eventsBetween(c: Chronicle, from: number, to: number): ChronicleEvent[] {
  const a = upper(c.events, from, e => e.t), b = upper(c.events, to, e => e.t);
  return c.events.slice(a, b);
}

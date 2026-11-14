// A recorded journey ("kronika") and everything the player needs to replay it. Pure functions, no browser and no server:
// the recording is one file that is played back entirely in the visitor's browser.

export type EventKind = "quest" | "kill" | "loot" | "money" | "level" | "skill" | "zone" | "death" | "dungeon" | "travel" | "boss" | "group" | "emote" | "pvp";
/** The groups shown as filter chips next to the list of moments. */
export type Category = "quests" | "combat" | "loot" | "professions" | "travel" | "character";
export const CATEGORIES: readonly Category[] = ["quests", "combat", "loot", "professions", "travel", "character"];
const CATEGORY_OF: Record<EventKind, Category> = {
  quest: "quests", kill: "combat", death: "combat", loot: "loot", money: "loot", skill: "professions",
  zone: "travel", travel: "travel", dungeon: "travel", level: "character", boss: "combat", group: "character", emote: "character", pvp: "combat",
};
export const categoryOf = (kind: EventKind): Category => CATEGORY_OF[kind];

export type ChronicleEvent = {
  /** Seconds from the start of the recording. */
  t: number; k: EventKind;
  /** Short text shown in the list and above the character. */
  text: string;
  /** quest: accept | done | turnin | abandon; dungeon: enter | leave; boss: kill | wipe; group: join | leave; travel: flight | hearth | portal. */
  a?: string;
  /** Quantity (loot), copper (money, may be negative), new level (level), skill value (skill). */
  n?: number; max?: number;
  /** Experience gained (kill, quest turn-in). */
  xp?: number;
  /** Item quality 0 to 5. */
  q?: number;
  /** The game id of the item (loot) or of the quest, for icons and links. */
  id?: number;
  /** boss and pvp: the index into `fights` of the fight this moment closes, which opens the window of the event. */
  f?: number;
  /** Where it happened: index into `zones` and the position 0 to 1 inside that zone. */
  zone?: number; x?: number; y?: number;
  /** boss: seconds the fight lasted (n is the number of the attempt). */
  d?: number;
  /** A line of detail under the text (for example the damage of a fight, or the difficulty of a dungeon). */
  detail?: string;
};
/** One line of a damage or healing meter: how often a spell was used and what it did. */
export type SpellRow = { name: string; total: number; casts: number; hits?: number; crits?: number; max?: number; /** physical | nature | fire | frost | shadow | arcane | holy */ school?: string };
export type Member = { name: string; classId: number; role?: "tank" | "healer" | "dps"; dmg: number; heal: number; taken: number; deaths?: number; me?: boolean };
export type FightMark = { /** seconds from the start of the fight */ t: number; kind: "death" | "cooldown" | "phase" | "interrupt" | "lust"; text: string };
/** A boss fight, an arena or a battleground: everything the window of the event shows. Times are journey seconds. */
export type Fight = {
  t: number; d: number; kind: "boss" | "pvp"; name: string; result: "kill" | "wipe" | "win" | "loss";
  zone?: number; difficulty?: string; size?: number; attempt?: number;
  me: { dmg: number; heal: number; taken: number; deaths: number; interrupts?: number; dispels?: number; dealt: SpellRow[]; healed: SpellRow[]; took: SpellRow[] };
  group?: Member[];
  /** Damage, healing and damage taken of the character in steps of `step` seconds, for the graph and the live counters. */
  series?: { step: number; dmg: number[]; heal?: number[]; taken?: number[] };
  marks?: FightMark[];
  pvp?: { score?: [number, number]; kills: number; deaths: number; assists?: number; objectives?: number; honor?: number };
};
/** What the character sheet showed from `t` on. */
export type StatSnapshot = { t: number; ilvl?: number; attrs?: [name: string, value: number][]; enh?: [name: string, value: string][] };
/** One play session: from journey time `t` on, the clock of the day is `at` (unix seconds). */
export type Session = { t: number; at: number };
/** One position sample: seconds, index into `zones`, x and y from 0 to 1 inside the zone. */
export type PathPoint = [t: number, zone: number, x: number, y: number];
export type Chronicle = {
  v: 1;
  character: { name: string; classId: number; raceId?: number; race?: string; faction?: string; realm?: string; guild?: string; level: number };
  /** Unix time of the start of the recording, seconds. */
  startedAt: number;
  /** Length of the recording, seconds. */
  duration: number;
  /** Map keys of /media/maps (for example "darkshore"). */
  zones: string[];
  path: PathPoint[];
  events: ChronicleEvent[];
  /** The days played. Without it the whole recording is one session starting at `startedAt`. */
  sessions?: Session[];
  stats?: StatSnapshot[];
  /** Skills known at the start: name to [value, maximum]. */
  skills0?: Record<string, [number, number]>;
  fights?: Fight[];
};

export const MAX_EVENTS = 200_000;
export const MAX_PATH = 400_000;
const KINDS = new Set<string>(Object.keys(CATEGORY_OF));
const finite = (v: unknown): v is number => typeof v === "number" && Number.isFinite(v);
const unit = (v: unknown): v is number => finite(v) && v >= 0 && v <= 1;
const short = (v: unknown, max = 160): v is string => typeof v === "string" && v.length <= max;

const num = (v: unknown): v is number => finite(v) && v >= 0;
const spellList = (v: unknown): boolean => Array.isArray(v) && v.length <= 300 && v.every(r => !!r && short(r.name, 60) && num(r.total) && num(r.casts)
  && (r.hits === undefined || num(r.hits)) && (r.crits === undefined || num(r.crits)) && (r.max === undefined || num(r.max)) && (r.school === undefined || short(r.school, 16)));
const series = (v: unknown): boolean => v === undefined || (Array.isArray(v) && v.length <= 5000 && v.every(num));
function validFights(list: unknown, zones: number, events: readonly ChronicleEvent[]): boolean {
  if (!Array.isArray(list) || list.length > 5000) return false;
  let at = -Infinity;
  for (const f of list as Fight[]) {
    if (!f || !num(f.t) || f.t < at || !num(f.d) || (f.kind !== "boss" && f.kind !== "pvp") || !["kill", "wipe", "win", "loss"].includes(f.result) || !short(f.name, 80)) return false;
    at = f.t;
    if ((f.zone !== undefined && !(Number.isInteger(f.zone) && f.zone >= 0 && f.zone < zones)) || (f.difficulty !== undefined && !short(f.difficulty, 40)) || (f.size !== undefined && !num(f.size)) || (f.attempt !== undefined && !num(f.attempt))) return false;
    const me = f.me;
    if (!me || !num(me.dmg) || !num(me.heal) || !num(me.taken) || !num(me.deaths) || !spellList(me.dealt) || !spellList(me.healed) || !spellList(me.took)) return false;
    if (f.group !== undefined && (!Array.isArray(f.group) || f.group.length > 80 || !f.group.every(m => !!m && short(m.name, 40) && Number.isInteger(m.classId) && num(m.dmg) && num(m.heal) && num(m.taken) && (m.deaths === undefined || num(m.deaths)) && (m.role === undefined || ["tank", "healer", "dps"].includes(m.role))))) return false;
    if (f.series !== undefined && (!f.series || !(finite(f.series.step) && f.series.step > 0) || !Array.isArray(f.series.dmg) || !series(f.series.dmg) || !series(f.series.heal) || !series(f.series.taken))) return false;
    if (f.marks !== undefined && (!Array.isArray(f.marks) || f.marks.length > 500 || !f.marks.every(m => !!m && num(m.t) && ["death", "cooldown", "phase", "interrupt", "lust"].includes(m.kind) && short(m.text, 80)))) return false;
    if (f.pvp !== undefined && (!f.pvp || !num(f.pvp.kills) || !num(f.pvp.deaths) || (f.pvp.score !== undefined && !(Array.isArray(f.pvp.score) && f.pvp.score.length === 2 && f.pvp.score.every(num))))) return false;
  }
  return events.every(e => e.f === undefined || (Number.isInteger(e.f) && e.f >= 0 && e.f < list.length));
}

/** Checks a loaded file. Returns the recording, or null when anything in it cannot be trusted. Nothing is repaired. */
export function parseChronicle(raw: unknown): Chronicle | null {
  const c = raw as Partial<Chronicle> | null;
  if (!c || typeof c !== "object" || c.v !== 1) return null;
  const who = c.character;
  if (!who || !short(who.name, 64) || !finite(who.classId) || !finite(who.level) || (who.raceId !== undefined && !Number.isInteger(who.raceId))) return null;
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
    if (e.id !== undefined && !(Number.isInteger(e.id) && e.id > 0)) return null;
    if ((e.d !== undefined && !(finite(e.d) && e.d >= 0)) || (e.detail !== undefined && !short(e.detail, 300))) return null;
    if ((e.x !== undefined && !unit(e.x)) || (e.y !== undefined && !unit(e.y))) return null;
    last = e.t;
  }
  if (c.fights !== undefined && !validFights(c.fights, zones, c.events)) return null;
  if (c.fights === undefined && c.events.some(e => e.f !== undefined)) return null;
  if (c.sessions !== undefined) {
    if (!Array.isArray(c.sessions) || c.sessions.length > 100_000) return null;
    let at = -Infinity;
    for (const x of c.sessions) { if (!x || !finite(x.t) || !finite(x.at) || x.t < at) return null; at = x.t; }
  }
  if (c.stats !== undefined) {
    if (!Array.isArray(c.stats) || c.stats.length > 100_000) return null;
    let at = -Infinity;
    for (const x of c.stats) {
      if (!x || !finite(x.t) || x.t < at || (x.ilvl !== undefined && !finite(x.ilvl))) return null;
      at = x.t;
      if (x.attrs !== undefined && (!Array.isArray(x.attrs) || x.attrs.length > 40 || !x.attrs.every(a => Array.isArray(a) && short(a[0], 40) && finite(a[1])))) return null;
      if (x.enh !== undefined && (!Array.isArray(x.enh) || x.enh.length > 40 || !x.enh.every(a => Array.isArray(a) && short(a[0], 40) && short(a[1], 60)))) return null;
    }
  }
  if (c.skills0 !== undefined) {
    const entries = c.skills0 && typeof c.skills0 === "object" ? Object.entries(c.skills0) : null;
    if (!entries || entries.length > 100 || !entries.every(([k, v]) => short(k, 40) && Array.isArray(v) && finite(v[0]) && finite(v[1]))) return null;
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
  now.skills = { ...(c.skills0 ?? {}) };
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
  zero.skills = { ...(index.c.skills0 ?? {}) };
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

// ---- types of moments, days, dungeons and the character sheet --------------------------------------------------
/** The finer kind of a moment, what the filter panel switches on and off. */
export function typeKey(e: ChronicleEvent): string {
  switch (e.k) {
    case "quest": return e.a === "accept" ? "quest.accept" : e.a === "abandon" ? "quest.abandon" : "quest.turnin";
    case "kill": return "combat.kill";
    case "death": return "combat.death";
    case "boss": return "combat.boss";
    case "pvp": return "combat.pvp";
    case "loot": return "loot.item";
    case "money": return "loot.money";
    case "skill": return "prof.skill";
    case "zone": return "travel.zone";
    case "travel": return "travel.flight";
    case "dungeon": return "travel.instance";
    case "level": return "char.level";
    case "group": return "char.group";
    default: return "char.emote";
  }
}
export const TYPE_KEYS: Record<Category, string[]> = {
  quests: ["quest.accept", "quest.turnin", "quest.abandon"], combat: ["combat.kill", "combat.death", "combat.boss", "combat.pvp"], loot: ["loot.item", "loot.money"],
  professions: ["prof.skill"], travel: ["travel.flight", "travel.instance", "travel.zone"], character: ["char.level", "char.group", "char.emote"],
};
export const ALL_TYPES: string[] = Object.values(TYPE_KEYS).flat();
export function countByType(c: Chronicle): Record<string, number> {
  const out: Record<string, number> = {};
  for (const e of c.events) { const k = typeKey(e); out[k] = (out[k] ?? 0) + 1; }
  return out;
}
/** Whether a moment passes a filter: its type is on and, for loot, the item is of the chosen quality or better. */
export const passes = (e: ChronicleEvent, types: ReadonlySet<string>, minQuality: number): boolean => types.has(typeKey(e)) && (e.k !== "loot" || (e.q ?? 1) >= minQuality);

export function sessionAt(c: Chronicle, t: number): number {
  const s = c.sessions;
  return s?.length ? Math.max(0, upper(s, t, x => x.t) - 1) : 0;
}
/** The clock of the day (unix seconds) at journey time `t`. */
export function whenOf(c: Chronicle, t: number): number {
  const s = c.sessions;
  if (!s?.length) return c.startedAt + t;
  const x = s[sessionAt(c, t)];
  return x.at + (t - x.t);
}
export type Day = { key: string; from: number; to: number; events: number };
/** The days played, oldest first: the stretch of journey time of each and how much happened in it. */
export function daysOf(c: Chronicle): Day[] {
  const s = c.sessions?.length ? c.sessions : [{ t: 0, at: c.startedAt }];
  const days = new Map<string, Day>();
  s.forEach((x, i) => {
    const end = s[i + 1]?.t ?? c.duration;
    const d = new Date(x.at * 1000);
    const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
    const n = eventsBetween(c, x.t - 1e-6, end).length;
    const now = days.get(key);
    if (now) { now.from = Math.min(now.from, x.t); now.to = Math.max(now.to, end); now.events += n; } else days.set(key, { key, from: x.t, to: end, events: n });
  });
  return [...days.values()].sort((a, b) => a.from - b.from);
}

export type Instance = { name: string; detail?: string; from: number; to: number | null; zone?: number };
/** The dungeon and raid visits: from the moment of entering to the moment of leaving (open when the recording ends inside). */
export function instances(c: Chronicle): Instance[] {
  const out: Instance[] = [];
  for (const e of c.events) {
    if (e.k !== "dungeon") continue;
    if (e.a === "enter") out.push({ name: e.text, detail: e.detail, from: e.t, to: null, zone: e.zone });
    else if (e.a === "leave") { const last = out[out.length - 1]; if (last && last.to === null) last.to = e.t; }
  }
  return out;
}
export function instanceAt(list: readonly Instance[], t: number): Instance | null {
  for (let i = list.length - 1; i >= 0; i--) {
    const x = list[i];
    if (x.from <= t) return x.to === null || t < x.to ? x : null;
  }
  return null;
}
/** The fight in progress at journey time `t`, or -1. */
export function fightAt(c: Chronicle, t: number): number {
  const list = c.fights;
  if (!list?.length) return -1;
  const i = upper(list, t, f => f.t) - 1;
  return i >= 0 && t <= list[i].t + list[i].d ? i : -1;
}
/** What the character had done, taken and healed `local` seconds into a fight (from the series, interpolated inside a step). */
export function fightProgress(f: Fight, local: number): { dmg: number; heal: number; taken: number } {
  const sr = f.series;
  const sum = (a: number[] | undefined, total: number) => {
    if (!a?.length || !sr) return total * Math.min(1, Math.max(0, local / Math.max(1, f.d)));
    const x = Math.max(0, local) / sr.step, whole = Math.min(a.length, Math.floor(x));
    let out = 0;
    for (let i = 0; i < whole; i++) out += a[i];
    if (whole < a.length) out += a[whole] * (x - whole);
    return out;
  };
  return { dmg: sum(sr?.dmg, f.me.dmg), heal: sum(sr?.heal, f.me.heal), taken: sum(sr?.taken, f.me.taken) };
}

export type InstanceSummary = { kills: number; deaths: number; items: number; copper: number; bosses: ChronicleEvent[] };
export function instanceSummary(c: Chronicle, inst: Instance, t: number): InstanceSummary {
  const out: InstanceSummary = { kills: 0, deaths: 0, items: 0, copper: 0, bosses: [] };
  for (const e of eventsBetween(c, inst.from - 1e-6, Math.min(t, inst.to ?? t))) {
    if (e.k === "kill") out.kills++; else if (e.k === "death") out.deaths++; else if (e.k === "loot") out.items += e.n ?? 1;
    else if (e.k === "money") out.copper += e.n ?? 0; else if (e.k === "boss" || e.k === "pvp") out.bosses.push(e);
  }
  return out;
}
export function statsAt(c: Chronicle, t: number): StatSnapshot | null {
  const s = c.stats;
  if (!s?.length) return null;
  const i = upper(s, t, x => x.t) - 1;
  return s[Math.max(0, i)];
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
const LOOT: [string, number, number][] = [["Ruined Leather Scraps", 0, 2934], ["Light Feather", 1, 17056], ["Strider Meat", 1, 5469], ["Linen Cloth", 1, 2589], ["Copper Bar", 1, 2840], ["Heavy Hide", 1, 4235], ["Mageweave Cloth", 1, 4338], ["Strider Stew", 1, 5477]];

type SpellDef = [name: string, school: string, perSecond: number, average: number];
const DEALT: SpellDef[] = [["Wrath", "nature", 0.34, 64], ["Starfire", "arcane", 0.12, 96], ["Moonfire", "arcane", 0.1, 52], ["Insect Swarm", "nature", 0.07, 70]];
const HEALED: SpellDef[] = [["Rejuvenation", "nature", 0.05, 95], ["Regrowth", "nature", 0.03, 150], ["Healing Touch", "nature", 0.02, 210]];
const BOSS_SPELLS: SpellDef[][] = [
  [["Melee", "physical", 0.4, 25], ["Trample", "physical", 0.05, 40], ["Bash", "physical", 0.02, 70]],
  [["Melee", "physical", 0.35, 28], ["Forked Lightning", "nature", 0.06, 55], ["Frost Nova", "frost", 0.03, 60], ["Slow", "frost", 0.03, 10]],
  [["Melee", "physical", 0.3, 30], ["Shadow Bolt", "shadow", 0.07, 70], ["Mind Blast", "shadow", 0.05, 95]],
];
const ENEMY_PLAYERS: SpellDef[] = [["Melee", "physical", 0.5, 22], ["Sinister Strike", "physical", 0.12, 48], ["Frostbolt", "frost", 0.08, 58], ["Shadow Word: Pain", "shadow", 0.05, 30]];
function spellRows(rand: () => number, d: number, defs: SpellDef[]): SpellRow[] {
  return defs.map(([name, school, perSecond, average]) => {
    const casts = Math.max(1, Math.round(d * perSecond * (0.8 + rand() * 0.4)));
    const crits = Math.round(casts * (0.04 + rand() * 0.12));
    return { name, school, casts, hits: casts, crits, max: Math.round(average * (1.7 + rand() * 0.5)), total: Math.round(casts * average * (0.9 + rand() * 0.2) + crits * average * 0.5) };
  }).sort((a, b) => b.total - a.total);
}
/** `total` spread over the steps of a fight with a random but smooth shape, adding up exactly. */
function buckets(rand: () => number, d: number, total: number, step = 5): number[] {
  const n = Math.max(1, Math.ceil(d / step));
  const phase = rand() * 6;
  const weights = Array.from({ length: n }, (_, i) => 0.55 + 0.45 * Math.sin(phase + i * 0.7) + rand() * 0.5);
  const sum = weights.reduce((a, b) => a + b, 0);
  const out = weights.map(x => Math.round((x / sum) * total));
  out[out.length - 1] += total - out.reduce((a, b) => a + b, 0);
  return out.map(x => Math.max(0, x));
}
function makeFight(rand: () => number, o: { kind: "boss" | "pvp"; name: string; result: Fight["result"]; t: number; d: number; size: number; attempt?: number; difficulty?: string; zone: number; took: SpellDef[]; deaths: number; pvp?: Fight["pvp"] }): Fight {
  const dealt = spellRows(rand, o.d, DEALT), healed = spellRows(rand, o.d, HEALED), took = spellRows(rand, o.d, o.took);
  const sumOf = (rows: SpellRow[]) => rows.reduce((a, r) => a + r.total, 0);
  const me = { dmg: sumOf(dealt), heal: sumOf(healed), taken: sumOf(took), deaths: o.deaths, interrupts: Math.floor(rand() * 3), dispels: Math.floor(rand() * 2), dealt, healed, took };
  const others: [string, number, "tank" | "healer" | "dps", number, number, number][] = [["Thornwick", 1, "tank", 0.55, 0.05, 3.2], ["Lumi", 5, "healer", 0.12, 7, 0.8], ["Kragg", 4, "dps", 1.4, 0.02, 1.1], ["Selene", 8, "dps", 1.2, 0.03, 0.9]];
  const group: Member[] = [
    ...others.slice(0, Math.max(0, Math.min(4, o.size - 1))).map(([name, classId, role, dmg, heal, taken]) => ({ name, classId, role, dmg: Math.round(me.dmg * dmg * (0.9 + rand() * 0.2)), heal: Math.round(Math.max(me.heal, 60) * heal * (0.9 + rand() * 0.2)), taken: Math.round(me.taken * taken * (0.9 + rand() * 0.2)), deaths: o.result === "wipe" && rand() < 0.4 ? 1 : 0 })),
    { name: "Demo Wanderer", classId: 11, role: "dps" as const, dmg: me.dmg, heal: me.heal, taken: me.taken, deaths: o.deaths, me: true },
  ].sort((a, b) => b.dmg - a.dmg);
  const marks: FightMark[] = [{ t: Math.round(o.d * 0.22), kind: "cooldown", text: "Innervate" }];
  if (o.kind === "boss") marks.push({ t: Math.round(o.d * 0.55), kind: "phase", text: "Phase 2" }, { t: Math.round(o.d * 0.38), kind: "interrupt", text: "Interrupted Frost Nova" });
  if (o.deaths) marks.push({ t: Math.round(o.d * 0.92), kind: "death", text: "You died" });
  return {
    t: o.t, d: o.d, kind: o.kind, name: o.name, result: o.result, zone: o.zone, difficulty: o.difficulty, size: o.size, attempt: o.attempt, me, group,
    series: { step: 5, dmg: buckets(rand, o.d, me.dmg), heal: buckets(rand, o.d, me.heal), taken: buckets(rand, o.d, me.taken) },
    marks: marks.sort((a, b) => a.t - b.t), pvp: o.pvp,
  };
}
const fightLine = (f: Fight) => `Dealt ${f.me.dmg.toLocaleString("en-US")} (${Math.round((f.me.dmg / Math.max(1, (f.group ?? []).reduce((a, m) => a + m.dmg, 0) || f.me.dmg)) * 100)}% of the group), took ${f.me.taken.toLocaleString("en-US")}, healed ${f.me.heal.toLocaleString("en-US")}`;

export function demoChronicle(seed = 7): Chronicle {
  const rand = rng(seed);
  const zones = LEGS.map(l => l.zone);
  const path: PathPoint[] = [];
  const events: ChronicleEvent[] = [];
  const fights: Fight[] = [];
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
            if (rand() < 0.65) { const [name, q, id] = LOOT[Math.floor(rand() * LOOT.length)]; push({ t: t + k * 3 + 1, k: "loot", text: name, n: 1 + Math.floor(rand() * 2), q, id, ...here }); }
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
  // a dungeon at the end: a group, trash, a wipe on the second boss and then the kill
  const last = LEGS.length - 1, ex = 0.14, ey = 0.86;
  const wait = (seconds: number) => { for (let i = 0; i < seconds / 2; i++) { t += 2; path.push([t, last, Math.round((ex + (rand() - 0.5) * 0.01) * 1e4) / 1e4, Math.round((ey + (rand() - 0.5) * 0.01) * 1e4) / 1e4]); } };
  const spot = { zone: last, x: ex, y: ey };
  t += 20; // the way to the dungeon is not recorded: the character is simply there afterwards
  push({ t, k: "group", a: "join", text: "Joined a group of 5", ...spot });
  push({ t: t + 1, k: "dungeon", a: "enter", text: "Blackfathom Deeps", detail: "Dungeon · Normal", ...spot });
  const trash = ["Blackfathom Tide Priestess", "Aku'mai Snapjaw", "Twilight Aquamancer", "Murkshallow Soothsayer", "Blindlight Murloc"];
  const boss: [string, number][] = [["Ghamoo-ra", 5], ["Lady Sarevess", 5], ["Twilight Lord Kelris", 5]];
  boss.forEach(([name, size], bi) => {
    for (let k = 0; k < 9; k++) {
      wait(8);
      const xp = 90 + level * 3; xpTotal += xp;
      push({ t, k: "kill", text: trash[Math.floor(rand() * trash.length)], xp, ...spot });
      if (rand() < 0.5) { const [name, q, id] = LOOT[Math.floor(rand() * LOOT.length)]; push({ t: t + 1, k: "loot", text: name, n: 1, q, id, ...spot }); }
      if (rand() < 0.6) push({ t: t + 1.2, k: "money", text: "Money", n: 30 + Math.floor(rand() * 120), ...spot });
    }
    wait(20);
    const close = (result: "kill" | "wipe", d: number, attempt: number) => {
      const start = t;
      wait(d); // the fight takes its time, so fights never overlap
      const fight = makeFight(rand, { kind: "boss", name, result, t: start, d: t - start, size, attempt, difficulty: "Normal", zone: last, took: BOSS_SPELLS[bi], deaths: result === "wipe" ? 1 : 0 });
      fights.push(fight);
      push({ t, k: "boss", a: result, text: name, n: attempt, d: fight.d, f: fights.length - 1, detail: fightLine(fight), ...spot });
      return fight;
    };
    if (bi === 1) {
      close("wipe", 74, 1);
      push({ t: t + 1, k: "death", text: "You died", ...spot });
      wait(40);
    }
    close("kill", 150 + bi * 40, bi === 1 ? 2 : 1);
    xpTotal += 300; push({ t: t + 0.5, k: "loot", text: ["Tortoise Armor", "Naga Heartpiercer", "Twilight Maul"][bi], n: 1, q: 3, id: [6907, 3078, 273841][bi], ...spot });
    if (xpTotal >= need(level)) { xpTotal -= need(level); level++; push({ t: t + 1, k: "level", text: `Reached level ${level}`, n: level, ...spot }); }
    if (bi === 2) push({ t: t + 2, k: "emote", text: "You cheer", ...spot });
  });
  push({ t: t + 3, k: "dungeon", a: "leave", text: "Blackfathom Deeps", ...spot });
  push({ t: t + 4, k: "group", a: "leave", text: "Left the group", ...spot });
  wait(10);
  // a battleground: a ten-minute match with kills, a flag and the result
  const bg = zones.length;
  zones.push("warsong-gulch");
  t += 30;
  push({ t, k: "zone", text: "Entered Warsong Gulch", zone: bg, x: 0.5, y: 0.5 });
  push({ t: t + 1, k: "dungeon", a: "enter", text: "Warsong Gulch", detail: "Battleground · 10 vs 10", zone: bg, x: 0.5, y: 0.5 });
  const matchStart = t;
  let bx = 0.3, by = 0.5, honor = 0, pvpKills = 0;
  const enemies = ["Skarn", "Gorrik", "Vexa", "Murdok", "Tazra", "Brogg"];
  for (let i = 0; i < 300; i++) {
    t += 2;
    bx = Math.min(0.85, Math.max(0.15, bx + (rand() - 0.46) * 0.025)); by = Math.min(0.85, Math.max(0.15, by + (rand() - 0.5) * 0.03));
    path.push([t, bg, Math.round(bx * 1e4) / 1e4, Math.round(by * 1e4) / 1e4]);
    const here = { zone: bg, x: Math.round(bx * 1e4) / 1e4, y: Math.round(by * 1e4) / 1e4 };
    if (i % 17 === 5) { pvpKills++; honor += 14; push({ t, k: "kill", text: `${enemies[pvpKills % enemies.length]} (Horde player)`, detail: "Honorable kill", ...here }); }
    if (i === 120 || i === 240) push({ t, k: "quest", a: "done", text: "Captured the flag", ...here });
    if (i === 90) push({ t, k: "death", text: "You died", ...here });
  }
  const pvpFight = makeFight(rand, { kind: "pvp", name: "Warsong Gulch", result: "win", t: matchStart, d: t - matchStart, size: 10, zone: bg, took: ENEMY_PLAYERS, deaths: 1, pvp: { score: [3, 2], kills: pvpKills, deaths: 1, assists: 4, objectives: 2, honor } });
  fights.push(pvpFight);
  push({ t: t + 1, k: "pvp", a: "win", text: "Warsong Gulch", n: 1, d: pvpFight.d, f: fights.length - 1, detail: `Won 3 : 2 · ${pvpKills} honorable kills · ${honor} honor`, zone: bg, x: 0.5, y: 0.5 });
  push({ t: t + 4, k: "dungeon", a: "leave", text: "Warsong Gulch", zone: bg, x: 0.5, y: 0.5 });
  wait(10);
  push({ t: 400, k: "quest", a: "abandon", text: "The Zoram Strand", zone: 1, x: 0.4, y: 0.7 });
  events.sort((a, b) => a.t - b.t);
  const duration = Math.ceil(t + 8);
  const days = [0, 0.22, 0.5, 0.78].map((f, i) => ({ t: Math.round(duration * f), at: 1_794_300_000 - (3 - i) * 86_400 + i * 3_600 }));
  const stats = [{ t: 0, level: 14 }, ...events.filter(e => e.k === "level").map(e => ({ t: e.t, level: e.n ?? 15 }))].map(({ t: at, level: l }) => ({
    t: at, ilvl: 8 + l * 3,
    attrs: [["Strength", 30 + l * 2], ["Agility", 34 + l * 2], ["Stamina", 36 + l * 3], ["Intellect", 38 + l * 2], ["Spirit", 32 + l * 2]] as [string, number][],
    enh: [["Critical Strike", `${(3 + l * 0.15).toFixed(1)}%`], ["Haste", `${(1.5 + l * 0.05).toFixed(1)}%`], ["Mastery", `${(2 + l * 0.12).toFixed(1)}%`]] as [string, string][],
  }));
  return {
    v: 1,
    character: { name: "Demo Wanderer", classId: 11, raceId: 4, race: "Night Elf", faction: "Alliance", realm: "Demo", guild: "Evertally", level: 14 },
    startedAt: days[0].at, duration, zones, path, events, sessions: days, stats, fights,
    skills0: { Herbalism: [41, 150], Skinning: [88, 150], Mining: [57, 150], Cooking: [75, 150], Fishing: [54, 150] },
  };
}

/** The events with `from < t <= to`, oldest first. */
export function eventsBetween(c: Chronicle, from: number, to: number): ChronicleEvent[] {
  const a = upper(c.events, from, e => e.t), b = upper(c.events, to, e => e.t);
  return c.events.slice(a, b);
}

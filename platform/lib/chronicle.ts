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
/** Who takes part in a fight: the character, the people of the group, and the enemies. */
export type Actor = { name: string; side: "me" | "party" | "enemy"; classId?: number; role?: "tank" | "healer" | "dps"; boss?: boolean };
export type LogKind = "dmg" | "heal" | "cast" | "aura" | "interrupt" | "dispel" | "death";
export const LOG_KINDS: readonly LogKind[] = ["dmg", "heal", "cast", "aura", "interrupt", "dispel", "death"];
/** One action of the combat log: seconds into the fight, who (index into `actors`), at whom (-1 for nobody), kind (index into LOG_KINDS), spell (index into `spells`, -1 for none), amount, critical. */
export type LogLine = [t: number, source: number, target: number, kind: number, spell: number, amount: number, crit: 0 | 1];
/** A boss fight, an arena or a battleground: everything the window of the event shows. Times are journey seconds. */
export type Fight = {
  t: number; d: number; kind: "boss" | "pvp"; name: string; result: "kill" | "wipe" | "win" | "loss";
  zone?: number; difficulty?: string; size?: number; attempt?: number;
  me: { dmg: number; heal: number; taken: number; deaths: number; interrupts?: number; dispels?: number; dealt: SpellRow[]; healed: SpellRow[]; took: SpellRow[] };
  group?: Member[];
  /** Damage, healing and damage taken of the character in steps of `step` seconds, for the graph and the live counters. */
  series?: { step: number; dmg: number[]; heal?: number[]; taken?: number[] };
  marks?: FightMark[];
  /** The combat log, move by move: who used what on whom. Sums in `me` and `group` should come from it. */
  actors?: Actor[]; spells?: { name: string; school?: string }[]; log?: LogLine[];
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
  let at = -Infinity, lines = 0;
  for (const f of list as Fight[]) {
    if (!f || !num(f.t) || f.t < at || !num(f.d) || (f.kind !== "boss" && f.kind !== "pvp") || !["kill", "wipe", "win", "loss"].includes(f.result) || !short(f.name, 80)) return false;
    at = f.t;
    if ((f.zone !== undefined && !(Number.isInteger(f.zone) && f.zone >= 0 && f.zone < zones)) || (f.difficulty !== undefined && !short(f.difficulty, 40)) || (f.size !== undefined && !num(f.size)) || (f.attempt !== undefined && !num(f.attempt))) return false;
    const me = f.me;
    if (!me || !num(me.dmg) || !num(me.heal) || !num(me.taken) || !num(me.deaths) || !spellList(me.dealt) || !spellList(me.healed) || !spellList(me.took)) return false;
    if (f.group !== undefined && (!Array.isArray(f.group) || f.group.length > 80 || !f.group.every(m => !!m && short(m.name, 40) && Number.isInteger(m.classId) && num(m.dmg) && num(m.heal) && num(m.taken) && (m.deaths === undefined || num(m.deaths)) && (m.role === undefined || ["tank", "healer", "dps"].includes(m.role))))) return false;
    if (f.series !== undefined && (!f.series || !(finite(f.series.step) && f.series.step > 0) || !Array.isArray(f.series.dmg) || !series(f.series.dmg) || !series(f.series.heal) || !series(f.series.taken))) return false;
    if (f.marks !== undefined && (!Array.isArray(f.marks) || f.marks.length > 500 || !f.marks.every(m => !!m && num(m.t) && ["death", "cooldown", "phase", "interrupt", "lust"].includes(m.kind) && short(m.text, 80)))) return false;
    if (f.actors !== undefined || f.spells !== undefined || f.log !== undefined) {
      const { actors, spells, log } = f;
      if (!Array.isArray(actors) || actors.length > 100 || !actors.every(a => !!a && short(a.name, 40) && ["me", "party", "enemy"].includes(a.side) && (a.classId === undefined || Number.isInteger(a.classId)))) return false;
      if (!Array.isArray(spells) || spells.length > 1000 || !spells.every(x => !!x && short(x.name, 60) && (x.school === undefined || short(x.school, 16)))) return false;
      if (!Array.isArray(log) || log.length > 50_000 || (lines += log.length) > 300_000) return false;
      let when = -Infinity;
      for (const l of log) {
        if (!Array.isArray(l) || l.length !== 7 || !num(l[0]) || l[0] < when || l[0] > f.d + 1 || !Number.isInteger(l[1]) || l[1] < 0 || l[1] >= actors.length
          || !Number.isInteger(l[2]) || l[2] < -1 || l[2] >= actors.length || !Number.isInteger(l[3]) || l[3] < 0 || l[3] >= LOG_KINDS.length
          || !Number.isInteger(l[4]) || l[4] < -1 || l[4] >= spells.length || !num(l[5]) || (l[6] !== 0 && l[6] !== 1)) return false;
        when = l[0];
      }
    }
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
export const passes = (e: ChronicleEvent, types: ReadonlySet<string>, minQuality: number): boolean => types.has(typeKey(e)) && (e.k !== "loot" || e.q === undefined || e.q >= minQuality);

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
/** The other way round: the moment of the journey that was played at a real time (inside its own session, never past it). */
export function journeyTimeOf(c: Chronicle, at: number): number {
  const s = c.sessions;
  if (!s?.length) return Math.min(c.duration, Math.max(0, at - c.startedAt));
  let i = 0;
  for (let k = 0; k < s.length; k++) if (s[k].at <= at) i = k;
  const end = s[i + 1]?.t ?? c.duration;
  return Math.min(end, Math.max(s[i].t, s[i].t + (at - s[i].at)));
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
type Kit = [name: string, school: string, kind: "dmg" | "heal", perSecond: number, average: number][];
const KITS: Record<string, Kit> = {
  me: [["Wrath", "nature", "dmg", 0.34, 64], ["Starfire", "arcane", "dmg", 0.12, 96], ["Moonfire", "arcane", "dmg", 0.1, 52], ["Insect Swarm", "nature", "dmg", 0.07, 70],
    ["Rejuvenation", "nature", "heal", 0.05, 95], ["Regrowth", "nature", "heal", 0.03, 150], ["Healing Touch", "nature", "heal", 0.02, 210]],
  tank: [["Melee", "physical", "dmg", 0.45, 22], ["Heroic Strike", "physical", "dmg", 0.15, 48], ["Sunder Armor", "physical", "dmg", 0.1, 12]],
  healer: [["Flash Heal", "holy", "heal", 0.14, 160], ["Renew", "holy", "heal", 0.08, 110], ["Greater Heal", "holy", "heal", 0.05, 300], ["Smite", "holy", "dmg", 0.03, 35]],
  rogue: [["Melee", "physical", "dmg", 0.6, 30], ["Sinister Strike", "physical", "dmg", 0.25, 55], ["Eviscerate", "physical", "dmg", 0.06, 140]],
  mage: [["Frostbolt", "frost", "dmg", 0.3, 70], ["Fireball", "fire", "dmg", 0.2, 95], ["Arcane Missiles", "arcane", "dmg", 0.08, 60]],
};
const BOSS_SPELLS: SpellDef[][] = [
  [["Melee", "physical", 0.4, 25], ["Trample", "physical", 0.05, 40], ["Bash", "physical", 0.02, 70]],
  [["Melee", "physical", 0.35, 28], ["Forked Lightning", "nature", 0.06, 55], ["Frost Nova", "frost", 0.03, 60], ["Slow", "frost", 0.03, 10]],
  [["Melee", "physical", 0.3, 30], ["Shadow Bolt", "shadow", 0.07, 70], ["Mind Blast", "shadow", 0.05, 95]],
];
const ENEMY_PLAYERS: SpellDef[] = [["Melee", "physical", 0.5, 22], ["Sinister Strike", "physical", 0.12, 48], ["Frostbolt", "frost", 0.08, 58], ["Shadow Word: Pain", "shadow", 0.05, 30]];
const asKit = (defs: SpellDef[]): Kit => defs.map(([name, school, perSecond, average]) => [name, school, "dmg", perSecond, average]);

/**
 * One fight played out move by move: everybody uses their spells at random but steady rates, and the combat log is written as it
 * goes. Everything the window shows (the spell tables, the meters, the graph) is then added up from that log, so the parts agree.
 */
function makeFight(rand: () => number, o: { kind: "boss" | "pvp"; name: string; result: Fight["result"]; t: number; d: number; size: number; attempt?: number; difficulty?: string; zone: number; enemy: SpellDef[]; enemies?: string[]; deaths: number; pvp?: Fight["pvp"] }): Fight {
  const helpers: [string, number, "tank" | "healer" | "dps", string][] = [["Thornwick", 1, "tank", "tank"], ["Lumi", 5, "healer", "healer"], ["Kragg", 4, "dps", "rogue"], ["Selene", 8, "dps", "mage"]];
  const allies = helpers.slice(0, Math.max(0, Math.min(4, o.size - 1)));
  const foes = (o.enemies ?? [o.name]);
  const actors: Actor[] = [
    { name: "Demo Wanderer", side: "me", classId: 11, role: "dps" },
    ...allies.map(([name, classId, role]): Actor => ({ name, classId, role, side: "party" })),
    ...foes.map((name, i): Actor => ({ name, side: "enemy", boss: o.kind === "boss" && i === 0 })),
  ];
  const friendIx = actors.flatMap((a, i) => (a.side === "enemy" ? [] : [i])), foeIx = actors.flatMap((a, i) => (a.side === "enemy" ? [i] : []));
  const tank = friendIx.find(i => actors[i].role === "tank") ?? friendIx[0];
  const spells: { name: string; school?: string }[] = [];
  const spell = (name: string, school?: string) => { let i = spells.findIndex(x => x.name === name && x.school === school); if (i < 0) { spells.push({ name, school }); i = spells.length - 1; } return i; };
  const KIND = Object.fromEntries(LOG_KINDS.map((k, i) => [k, i])) as Record<LogKind, number>;
  const log: LogLine[] = [];
  const pick = (list: number[]) => list[Math.floor(rand() * list.length)];
  const expo = (rate: number) => -Math.log(1 - rand()) / rate;
  const add = (t: number, source: number, target: number, kind: LogKind, sp: number, amount = 0, crit: 0 | 1 = 0) => log.push([Math.round(t * 10) / 10, source, target, KIND[kind], sp, Math.round(amount), crit]);
  const act = (source: number, kit: Kit, enemy: boolean) => {
    for (const [name, school, kind, rate, avg] of kit) {
      const sp = spell(name, school);
      for (let t = expo(rate); t < o.d; t += expo(rate)) {
        const crit = rand() < (kind === "heal" ? 0.08 : 0.1) ? 1 : 0;
        const target = kind === "heal" ? (rand() < 0.4 ? tank : pick(friendIx)) : enemy ? (rand() < 0.55 ? tank : pick(friendIx)) : pick(foeIx);
        add(t, source, target, kind, sp, avg * (0.75 + rand() * 0.5) * (crit ? 1.6 : 1), crit);
      }
    }
  };
  act(0, KITS.me, false);
  allies.forEach(([, , , kit], i) => act(1 + i, KITS[kit], false));
  for (const i of foeIx) act(i, asKit(o.enemy), true);
  const boss = foeIx[0], last = o.enemy[o.enemy.length - 1][0];
  add(0.5, 0, 0, "cast", spell("Thorns", "nature"));
  add(o.d * 0.22, 0, 0, "cast", spell("Innervate", "nature"));
  if (o.kind === "boss") {
    add(o.d * 0.38, boss, 0, "cast", spell(last, o.enemy[o.enemy.length - 1][1]));
    add(o.d * 0.38 + 0.6, 0, boss, "interrupt", spell(last, o.enemy[o.enemy.length - 1][1]));
    add(o.d * 0.55, boss, boss, "cast", spell("Enrage", "physical"));
    add(o.d * 0.7, 0, tank, "dispel", spell("Remove Curse", "arcane"));
  }
  if (o.deaths) add(o.kind === "pvp" ? o.d * 0.15 : o.d * 0.92, boss, 0, "death", -1);
  if (o.result === "wipe") add(o.d * 0.95, boss, pick(friendIx.filter(i => i !== 0)), "death", -1);
  log.sort((a, b) => a[0] - b[0]);

  const rows = (match: (l: LogLine) => boolean): SpellRow[] => {
    const by = new Map<number, SpellRow>();
    for (const l of log) {
      if (!match(l)) continue;
      const row = by.get(l[4]) ?? { name: spells[l[4]].name, school: spells[l[4]].school, total: 0, casts: 0, hits: 0, crits: 0, max: 0 };
      row.total += l[5]; row.casts++; row.hits = (row.hits ?? 0) + 1; row.crits = (row.crits ?? 0) + l[6]; row.max = Math.max(row.max ?? 0, l[5]);
      by.set(l[4], row);
    }
    return [...by.values()].sort((a, b) => b.total - a.total);
  };
  const sumOf = (list: SpellRow[]) => list.reduce((a, r) => a + r.total, 0);
  const dealt = rows(l => l[1] === 0 && l[3] === KIND.dmg), healed = rows(l => l[1] === 0 && l[3] === KIND.heal), took = rows(l => l[2] === 0 && l[3] === KIND.dmg);
  const me = {
    dmg: sumOf(dealt), heal: sumOf(healed), taken: sumOf(took), deaths: log.filter(l => l[3] === KIND.death && l[2] === 0).length,
    interrupts: log.filter(l => l[3] === KIND.interrupt && l[1] === 0).length, dispels: log.filter(l => l[3] === KIND.dispel && l[1] === 0).length, dealt, healed, took,
  };
  const group: Member[] = friendIx.map(i => ({
    name: actors[i].name, classId: actors[i].classId ?? 0, role: actors[i].role, me: i === 0 || undefined,
    dmg: sumOf(rows(l => l[1] === i && l[3] === KIND.dmg)), heal: sumOf(rows(l => l[1] === i && l[3] === KIND.heal)), taken: sumOf(rows(l => l[2] === i && l[3] === KIND.dmg)),
    deaths: log.filter(l => l[3] === KIND.death && l[2] === i).length,
  })).sort((a, b) => b.dmg - a.dmg);
  const step = 5, n = Math.max(1, Math.ceil(o.d / step));
  const bucket = (match: (l: LogLine) => boolean) => { const out = new Array<number>(n).fill(0); for (const l of log) if (match(l)) out[Math.min(n - 1, Math.floor(l[0] / step))] += l[5]; return out; };
  const marks: FightMark[] = [{ t: Math.round(o.d * 0.22), kind: "cooldown", text: "Innervate" }];
  if (o.kind === "boss") marks.push({ t: Math.round(o.d * 0.55), kind: "phase", text: "Phase 2" }, { t: Math.round(o.d * 0.38 + 0.6), kind: "interrupt", text: `Interrupted ${last}` });
  for (const l of log) if (l[3] === KIND.death && l[2] === 0) marks.push({ t: Math.round(l[0]), kind: "death", text: "You died" });
  return {
    t: o.t, d: o.d, kind: o.kind, name: o.name, result: o.result, zone: o.zone, difficulty: o.difficulty, size: o.size, attempt: o.attempt, me, group,
    series: { step, dmg: bucket(l => l[1] === 0 && l[3] === KIND.dmg), heal: bucket(l => l[1] === 0 && l[3] === KIND.heal), taken: bucket(l => l[2] === 0 && l[3] === KIND.dmg) },
    marks: marks.sort((x, y) => x.t - y.t), actors, spells, log, pvp: o.pvp,
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
      const fight = makeFight(rand, { kind: "boss", name, result, t: start, d: t - start, size, attempt, difficulty: "Normal", zone: last, enemy: BOSS_SPELLS[bi], deaths: result === "wipe" ? 1 : 0 });
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
  const pvpFight = makeFight(rand, { kind: "pvp", name: "Warsong Gulch", result: "win", t: matchStart, d: t - matchStart, size: 10, zone: bg, enemy: ENEMY_PLAYERS, enemies: ["Skarn", "Gorrik", "Vexa", "Murdok", "Tazra"], deaths: 1, pvp: { score: [3, 2], kills: pvpKills, deaths: 1, assists: 4, objectives: 2, honor } });
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

/**
 * Where a rejected file goes wrong, as far as it can be told ("events[1432]", "fights[2]", "sessions"), for the people who write a
 * recorder. A valid file gives null. It relies on the checks being sequential: a list that is valid up to element n and invalid with
 * element n + 1 has its fault at n.
 */
export function findProblem(raw: unknown): string | null {
  if (parseChronicle(raw)) return null;
  const c = raw as Record<string, unknown> | null;
  if (!c || typeof c !== "object" || Array.isArray(c)) return "the file is not a JSON object";
  if (c.v !== 1) return '"v" must be 1';
  const base: Record<string, unknown> = { ...c, path: [], events: [] };
  for (const key of ["fights", "sessions", "stats", "skills0"]) delete base[key];
  if (!parseChronicle(base)) return "the header: character, startedAt, duration or zones";
  for (const key of ["skills0", "sessions", "stats"]) if (c[key] !== undefined && !parseChronicle({ ...base, [key]: c[key] })) return `"${key}"`;
  const firstBad = (list: readonly unknown[], make: (n: number) => unknown): number => {
    let lo = 0, hi = list.length;
    while (lo < hi) { const mid = (lo + hi) >> 1; if (parseChronicle(make(mid + 1))) lo = mid + 1; else hi = mid; }
    return lo;
  };
  if (!Array.isArray(c.path)) return '"path" must be a list';
  if (!parseChronicle({ ...base, path: c.path })) return `path[${firstBad(c.path, n => ({ ...base, path: (c.path as unknown[]).slice(0, n) }))}]`;
  if (c.fights !== undefined) {
    const fights = c.fights as unknown[];
    if (!Array.isArray(fights)) return '"fights" must be a list';
    if (!parseChronicle({ ...base, fights })) return `fights[${firstBad(fights, n => ({ ...base, fights: fights.slice(0, n) }))}]`;
  }
  if (!Array.isArray(c.events)) return '"events" must be a list';
  const withFights = { ...base, path: c.path, ...(c.fights !== undefined ? { fights: c.fights } : {}) };
  if (!parseChronicle({ ...withFights, events: c.events })) return `events[${firstBad(c.events, n => ({ ...withFights, events: (c.events as unknown[]).slice(0, n) }))}]`;
  return "something in the file (every part passes on its own, so it is a combination)";
}

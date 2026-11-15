// What happened lately in the public chronicles and who did it best: boards (every quest, levelling brackets, dungeons from the door to the last
// boss and who cleared them first, professions from tier to tier, the furthest a new character got without dying) and the feed of records and
// placings that comes from them. Everything is read from the chronicles players chose to share; nothing is measured by a stopwatch in the game,
// so every time is "time played" between two events of the recording (the time offline is not in it).
import { instances, whenOf, type Chronicle } from "./chronicle";

export type Subject = { profileId: string; name: string; realm?: string | null; classId: number | null; level: number | null; c: Chronicle };
export type Section = "quests" | "levelling" | "dungeons" | "professions" | "deathless";
export type Metric = "quest" | "levelling" | "door" | "first" | "profession" | "deathless";
export type Who = { profileId: string; name: string; realm: string | null; classId: number | null; level: number | null };
/** `value` is seconds, a level, or (for the first to clear) the real time in seconds since 1970. `trail` is the shape of the route, x,y pairs 0 to 100. */
export type Entry = Who & { value: number; unit: "seconds" | "level" | "date"; at: number; to: number; detail?: number; trail: number[] };
export type Board = { id: string; section: Section; metric: Metric; title: string; from?: number; upTo?: number; entries: Entry[]; total: number };
export type Highlight = Who & {
  id: string; kind: "record" | "podium" | "best"; rank: number; boardId: string; section: Section; metric: Metric; title: string; from?: number; upTo?: number;
  value: number; unit: Entry["unit"]; at: number; to: number; detail?: number; trail: number[];
};
export type Holder = Who & { records: number; sections: Section[] };
export type Highlights = { feed: Highlight[]; boards: Board[]; closeRaces: string[]; holders: Holder[] };

const MIN_QUEST = 3, MIN_DOOR = 30, MIN_TIER = 60, TOP = 10, MAX_QUEST_BOARDS = 60, BRACKET = 10;
const TIERS: readonly [number, number][] = [[1, 75], [75, 150], [150, 225], [225, 300]];

type Cand = {
  board: string; section: Section; metric: Metric; title: string; from?: number; upTo?: number; unit: Entry["unit"]; value: number; tie: number;
  subject: Subject; at: number; to: number; detail?: number; trail: number[];
};
const who = (s: Subject): Who => ({ profileId: s.profileId, name: s.name, realm: s.realm ?? null, classId: s.classId, level: s.level });

/** The shape of the route between two moments of the journey, thinned to a couple of dozen points and fitted into 0 to 100. */
function trailOf(c: Chronicle, from: number, to: number): number[] {
  const points = c.path.filter(p => p[0] >= from && p[0] <= to);
  if (points.length < 2) return [];
  const step = Math.max(1, Math.ceil(points.length / 24));
  const kept = points.filter((_, i) => i % step === 0 || i === points.length - 1);
  const xs = kept.map(p => p[2]), ys = kept.map(p => p[3]);
  const x0 = Math.min(...xs), y0 = Math.min(...ys), scale = Math.max(Math.max(...xs) - x0, Math.max(...ys) - y0) || 1;
  return kept.flatMap(p => [Math.round(((p[2] - x0) / scale) * 100), Math.round(((p[3] - y0) / scale) * 100)]);
}
const lowerIsBetter = (unit: Entry["unit"]) => unit !== "level";
const better = (a: Cand, b: Cand) => (lowerIsBetter(a.unit) ? a.value - b.value || a.tie - b.tie : b.value - a.value || a.tie - b.tie);

function candidatesOf(s: Subject): Cand[] {
  const c = s.c, out: Cand[] = [];
  const make = (fields: Omit<Cand, "subject" | "at" | "to" | "trail" | "tie"> & { t0: number; t1: number; tie?: number }) => {
    const { t0, t1, tie, ...rest } = fields;
    out.push({ ...rest, tie: tie ?? 0, subject: s, at: whenOf(c, t0), to: whenOf(c, t1), trail: trailOf(c, t0, t1) });
  };

  // every quest: from accepting it to handing it in
  const accepted = new Map<string, number>();
  for (const e of c.events) {
    if (e.k !== "quest") continue;
    const key = String(e.id ?? e.text);
    if (e.a === "accept") accepted.set(key, e.t);
    else if (e.a === "abandon") accepted.delete(key);
    else if (e.a === "turnin" && accepted.has(key)) {
      const t0 = accepted.get(key)!;
      accepted.delete(key);
      if (e.t - t0 >= MIN_QUEST) make({ board: `q:${key}`, section: "quests", metric: "quest", title: e.text, unit: "seconds", value: Math.round(e.t - t0), t0, t1: e.t });
    }
  }

  // levelling: ten levels at a time (level 1 only when the recording starts there)
  const levelAt = new Map<number, number>();
  for (const e of c.events) if (e.k === "level" && e.n !== undefined && !levelAt.has(e.n)) levelAt.set(e.n, e.t);
  for (let lo = 1; lo + BRACKET <= 80; lo += lo === 1 ? BRACKET - 1 : BRACKET) {
    const hi = lo + BRACKET - (lo === 1 ? 1 : 0);
    const t0 = lo === 1 ? (c.character.level <= 1 ? 0 : undefined) : levelAt.get(lo);
    const t1 = levelAt.get(hi);
    if (t0 !== undefined && t1 !== undefined && t1 > t0) make({ board: `l:${lo}`, section: "levelling", metric: "levelling", title: `${lo}-${hi}`, from: lo, upTo: hi, unit: "seconds", value: Math.round(t1 - t0), t0, t1 });
  }

  // dungeons: from the door to the last boss, and who cleared it first
  for (const inst of instances(c)) {
    const end = inst.to ?? c.duration;
    const bosses = c.events.filter(e => e.k === "boss" && e.a !== "wipe" && e.t >= inst.from && e.t <= end);
    if (!bosses.length) continue;
    const last = bosses[bosses.length - 1];
    if (last.t - inst.from < MIN_DOOR) continue;
    make({ board: `d:${inst.name}`, section: "dungeons", metric: "door", title: inst.name, unit: "seconds", value: Math.round(last.t - inst.from), detail: bosses.length, t0: inst.from, t1: last.t });
    make({ board: `f:${inst.name}`, section: "dungeons", metric: "first", title: inst.name, unit: "date", value: Math.round(whenOf(c, last.t)), detail: Math.round(last.t - inst.from), t0: inst.from, t1: last.t });
  }

  // professions: from tier to tier, by the skill-ups the addon recorded
  const skills = new Map<string, { t: number; n: number }[]>();
  for (const e of c.events) if (e.k === "skill" && e.n !== undefined && e.max) { const list = skills.get(e.text) ?? []; list.push({ t: e.t, n: e.n }); skills.set(e.text, list); }
  for (const [name, list] of skills) {
    for (const [lo, hi] of TIERS) {
      const start = lo === 1 ? list.find(x => x.n <= 15) : list.find(x => x.n >= lo && x.n <= lo + 3);
      const end = start && list.find(x => x.t > start.t && x.n >= hi && x.n <= hi + 4);
      if (start && end && end.t - start.t >= MIN_TIER) make({ board: `p:${name}:${lo}`, section: "professions", metric: "profession", title: name, from: lo, upTo: hi, unit: "seconds", value: Math.round(end.t - start.t), t0: start.t, t1: end.t });
    }
  }

  // deathless: how far a new character got before it died for the first time
  if (c.character.level <= 5) {
    const death = c.events.find(e => e.k === "death")?.t ?? Infinity;
    let level = c.character.level, reached = 0;
    for (const e of c.events) if (e.k === "level" && e.n !== undefined && e.t < death && e.n > level) { level = e.n; reached = e.t; }
    if (level >= 5 && reached > 0) make({ board: "x:deathless", section: "deathless", metric: "deathless", title: "", unit: "level", value: level, tie: Math.round(reached), detail: Math.round(reached), t0: 0, t1: reached });
  }
  return out;
}

const toEntry = (x: Cand): Entry => ({ ...who(x.subject), value: x.value, unit: x.unit, at: x.at, to: x.to, ...(x.detail !== undefined ? { detail: x.detail } : {}), trail: x.trail });

export function buildHighlights(subjects: readonly Subject[], limit = 60): Highlights {
  const all = subjects.flatMap(candidatesOf);
  const byBoard = new Map<string, Cand[]>();
  for (const x of all) { const list = byBoard.get(x.board) ?? []; list.push(x); byBoard.set(x.board, list); }

  let boards: Board[] = [];
  const own = new Map<Cand, Cand[]>();   // a candidate -> every attempt of the same player on the same board
  for (const [id, list] of byBoard) {
    const best = new Map<string, Cand>();
    for (const x of list) { const had = best.get(x.subject.profileId); if (!had || better(x, had) < 0) best.set(x.subject.profileId, x); }
    for (const x of list) own.set(x, list.filter(y => y.subject.profileId === x.subject.profileId));
    const ranked = [...best.values()].sort(better);
    const head = ranked[0];
    boards.push({ id, section: head.section, metric: head.metric, title: head.title, ...(head.from !== undefined ? { from: head.from, upTo: head.upTo } : {}), entries: ranked.slice(0, TOP).map(toEntry), total: ranked.length });
  }
  // every quest has a board, but only the busiest ones are sent
  const quests = boards.filter(b => b.section === "quests").sort((a, b) => b.total - a.total || b.entries[0].to - a.entries[0].to).slice(0, MAX_QUEST_BOARDS);
  boards = [...boards.filter(b => b.section !== "quests"), ...quests];
  const order: Section[] = ["levelling", "quests", "dungeons", "professions", "deathless"];
  boards.sort((a, b) => order.indexOf(a.section) - order.indexOf(b.section) || (a.from ?? 0) - (b.from ?? 0) || b.total - a.total || a.title.localeCompare(b.title));

  // the boards where second place is closest to the record
  const closeRaces = boards
    .filter(b => b.entries.length >= 2 && b.entries[0].unit === "seconds")
    .map(b => ({ id: b.id, gap: b.entries[1].value / Math.max(1, b.entries[0].value) }))
    .sort((a, b) => a.gap - b.gap).slice(0, 3).map(x => x.id);

  // the feed: records and placings, and a dungeon run that is the best of the player's own
  const feed: Highlight[] = [];
  const line = (board: Board, e: Entry, kind: Highlight["kind"], rank: number, id: string): Highlight => ({
    ...e, id, kind, rank, boardId: board.id, section: board.section, metric: board.metric, title: board.title, ...(board.from !== undefined ? { from: board.from, upTo: board.upTo } : {}),
  });
  for (const b of boards) {
    b.entries.slice(0, 3).forEach((e, i) => feed.push(line(b, e, i === 0 ? "record" : "podium", i + 1, `${i === 0 ? "r" : "p"}-${b.id}-${e.profileId}`)));
  }
  for (const [, list] of byBoard) {
    const head = list[0];
    if (head.metric !== "door") continue;
    const board = boards.find(b => b.id === head.board)!;
    for (const x of list) {
      const mine = own.get(x) ?? [];
      if (mine.length >= 2 && mine.every(y => better(x, y) <= 0)) feed.push(line(board, toEntry(x), "best", 0, `b-${x.board}-${x.subject.profileId}-${Math.round(x.to)}`));
    }
  }
  feed.sort((a, b) => b.to - a.to || (a.kind === "record" ? 0 : 1) - (b.kind === "record" ? 0 : 1));

  const counts = new Map<string, Holder>();
  for (const b of boards) {
    const e = b.entries[0];
    const had = counts.get(e.profileId) ?? { profileId: e.profileId, name: e.name, realm: e.realm, classId: e.classId, level: e.level, records: 0, sections: [] };
    had.records++; if (!had.sections.includes(b.section)) had.sections.push(b.section);
    counts.set(e.profileId, had);
  }
  const holders = [...counts.values()].sort((a, b) => b.records - a.records).slice(0, 5);
  return { feed: feed.slice(0, limit), boards, closeRaces, holders };
}

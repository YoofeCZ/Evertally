// One dungeon or raid visit taken apart for its own window: the bosses of the place (from the dungeon journal) and how each
// went, the ordinary enemies apart from them, the trash fights, the deaths, the loot, the group and what happened in order.
// Pure functions over a recording; nothing is invented: a boss the recording never met stays "not met".
import { eventsBetween, statsAt, type Chronicle, type ChronicleEvent, type Fight, type Instance, type Member, type RosterMember } from "./chronicle";
import { INSTANCES, type InstanceInfo } from "./chronicle-instances.data";

const low = (s: string) => s.trim().toLowerCase();

/** The journal's entry for a visit: by the instance's map id, else by its name (a wing such as "Scarlet Monastery - Library"
 * finds "Scarlet Monastery …" by the longest name it starts with). */
export function instanceInfo(inst: Pick<Instance, "name" | "id">): InstanceInfo | undefined {
  const name = low(inst.name);
  const byName = INSTANCES.find(x => low(x.name) === name);
  if (byName) return byName;
  if (inst.id !== undefined) {
    const byMap = INSTANCES.filter(x => x.mapId === inst.id);
    if (byMap.length === 1) return byMap[0];
    if (byMap.length > 1) return byMap.find(x => name.includes(low(x.name))) ?? byMap[0];
  }
  return [...INSTANCES].sort((a, b) => b.name.length - a.name.length).find(x => name.startsWith(low(x.name)) || low(x.name).startsWith(name));
}

export type BossStatus = "killed" | "wiped" | "unseen";
export type BossRow = {
  name: string; npc?: number; rare?: boolean; status: BossStatus;
  /** journey second of the kill (or of the last attempt) */ t?: number;
  /** the fights against this boss, in order (indices into c.fights) */ fights: number[];
  /** how long the killing fight lasted */ d?: number;
  wipes: number;
  /** not in the journal's list (a boss fight the recording names) */ extra?: boolean;
};
export type EnemyRow = { name: string; count: number; xp: number; first: number; fights: number[] };
export type TrashFight = { index: number; fight: Fight; kills: number };
export type LootRow = { name: string; n: number; q: number; id?: number; t: number };
export type PartyRow = { name: string; classId?: number; raceId?: number; level?: number; role?: "tank" | "healer" | "dps"; me?: boolean; meter?: Member };

export type InstanceReport = {
  inst: Instance; info?: InstanceInfo; from: number; to: number; open: boolean;
  bosses: BossRow[]; enemies: EnemyRow[]; trash: TrashFight[];
  deaths: ChronicleEvent[]; loot: LootRow[]; copper: number; xp: number; quests: ChronicleEvent[];
  party: PartyRow[];
  /** what happened inside, in order: bosses, fights, deaths, loot of uncommon or better, levels, quests */
  story: ChronicleEvent[];
  kills: number; bossKills: number;
};

const ROLE: Record<string, PartyRow["role"]> = { TANK: "tank", HEALER: "healer", DAMAGER: "dps", tank: "tank", healer: "healer", dps: "dps" };

export function instanceReport(c: Chronicle, inst: Instance): InstanceReport {
  const info = instanceInfo(inst);
  const from = inst.from, open = inst.to === null, to = inst.to ?? c.duration;
  const events = eventsBetween(c, from - 1e-6, to + 1e-6).filter(e => e.k !== "state");
  const fights = (c.fights ?? []).map((fight, index) => ({ fight, index })).filter(({ fight }) => fight.t >= from - 1 && fight.t <= to);
  const bossNames = new Map((info?.bosses ?? []).map(b => [low(b.name), b]));

  // the bosses: the journal's list in its order, each with the fights fought against it
  const rows = new Map<string, BossRow>();
  for (const b of info?.bosses ?? []) rows.set(low(b.name), { name: b.name, npc: b.npc, rare: b.rare, status: "unseen", fights: [], wipes: 0 });
  const killsIn = new Map<number, ChronicleEvent[]>();
  for (const e of events) if (e.k === "kill" && e.f !== undefined) killsIn.set(e.f, [...(killsIn.get(e.f) ?? []), e]);
  const bossOf = (fight: Fight, index: number): string | undefined => {
    const own = low(fight.name);
    if (bossNames.has(own)) return own;
    for (const k of killsIn.get(index) ?? []) if (bossNames.has(low(k.text))) return low(k.text);
    return fight.kind === "boss" ? own : undefined;
  };
  const trash: TrashFight[] = [];
  for (const { fight, index } of fights) {
    if (fight.kind === "pvp") continue;
    const key = bossOf(fight, index);
    if (!key) { trash.push({ index, fight, kills: killsIn.get(index)?.length ?? 0 }); continue; }
    const row = rows.get(key) ?? { name: fight.name, status: "unseen" as BossStatus, fights: [], wipes: 0, extra: true };
    rows.set(key, row);
    row.fights.push(index);
    const won = fight.result === "kill" || fight.result === "win" || (killsIn.get(index) ?? []).some(k => low(k.text) === key);
    if (won) { row.status = "killed"; row.t = fight.t + fight.d; row.d = fight.d; }
    else if (fight.result === "wipe" || fight.result === "loss") { row.wipes++; if (row.status !== "killed") { row.status = "wiped"; row.t = fight.t + fight.d; } }
  }
  // a boss killed with no fight recorded around it (only the kill and its experience)
  for (const e of events) {
    if (e.k === "boss") {
      const key = low(e.text), row = rows.get(key) ?? { name: e.text, status: "unseen" as BossStatus, fights: [], wipes: 0, extra: true };
      rows.set(key, row);
      if (e.f !== undefined && !row.fights.includes(e.f)) row.fights.push(e.f);
      if (e.a === "kill") { row.status = "killed"; row.t = e.t; row.d ??= e.d; }
      else if (row.status !== "killed") { row.status = "wiped"; row.t = e.t; if (e.f === undefined) row.wipes++; }
    } else if (e.k === "kill" && bossNames.has(low(e.text))) {
      const row = rows.get(low(e.text))!;
      if (row.status !== "killed") { row.status = "killed"; row.t = e.t; }
    }
  }
  const bosses = [...rows.values()];

  // the ordinary enemies: every kill that is not one of the bosses, by name
  const enemies = new Map<string, EnemyRow>();
  let kills = 0, xp = 0, copper = 0;
  const deaths: ChronicleEvent[] = [], quests: ChronicleEvent[] = [], story: ChronicleEvent[] = [];
  const loot = new Map<string, LootRow>();
  for (const e of events) {
    if (e.xp) xp += e.xp;
    if (e.k === "kill") {
      kills++;
      if (rows.has(low(e.text))) continue;
      const row = enemies.get(e.text) ?? { name: e.text, count: 0, xp: 0, first: e.t, fights: [] };
      row.count++; row.xp += e.xp ?? 0;
      if (e.f !== undefined && !row.fights.includes(e.f)) row.fights.push(e.f);
      enemies.set(e.text, row);
    } else if (e.k === "death") deaths.push(e);
    else if (e.k === "loot") {
      const row = loot.get(e.text) ?? { name: e.text, n: 0, q: e.q ?? 1, id: e.id, t: e.t };
      row.n += e.n ?? 1; loot.set(e.text, row);
    } else if (e.k === "money") copper += e.n ?? 0;
    else if (e.k === "quest" && (e.a === "turnin" || e.a === "done" || e.a === "accept")) quests.push(e);
    if (e.k === "boss" || e.k === "death" || e.k === "level" || e.k === "quest" || e.k === "dungeon"
      || e.k === "loot" && (e.q ?? 1) >= 2 || e.k === "kill" && rows.has(low(e.text)) || e.k === "combat" && e.a !== "start") story.push(e);
  }

  // the group: who came in (the roster seen on entering), with the run's meters when the recorder had them
  const meters = inst.summary?.group ?? [];
  const roster: RosterMember[] = statsAt(c, from + 1e-3)?.roster ?? [];
  const party: PartyRow[] = [];
  const seen = new Set<string>();
  const base = (n: string) => low(n.split("-")[0]);
  for (const r of roster) {
    if (!r.name) continue;
    const meter = meters.find(m => base(m.name) === base(r.name!));
    party.push({ name: r.name, classId: r.classId ?? meter?.classId, raceId: r.raceId, level: r.level, role: ROLE[r.role ?? ""] ?? meter?.role, me: meter?.me || base(r.name) === base(c.character.name), meter });
    seen.add(base(r.name));
  }
  for (const m of meters) if (!seen.has(base(m.name))) party.push({ name: m.name, classId: m.classId, role: m.role, me: m.me, meter: m });
  if (!party.some(p => p.me)) party.unshift({ name: c.character.name, classId: c.character.classId, level: c.character.level, me: true });
  const order = { tank: 0, healer: 1, dps: 2 } as const;
  party.sort((a, b) => (a.me ? -1 : 0) - (b.me ? -1 : 0) || (order[a.role ?? "dps"] - order[b.role ?? "dps"]) || a.name.localeCompare(b.name));

  return {
    inst, info, from, to, open, bosses,
    enemies: [...enemies.values()].sort((a, b) => b.count - a.count || a.first - b.first),
    trash, deaths, loot: [...loot.values()].sort((a, b) => b.q - a.q || a.t - b.t), copper, xp, quests, party, story,
    kills, bossKills: bosses.filter(b => b.status === "killed").length,
  };
}

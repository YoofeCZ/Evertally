// A journey recording composed from what the website already stores about a character: the walked routes, the zones visited, the quests,
// the loot, levels, dungeons and bosses, and the detailed journey batches. Missing measurements are never invented.
import type { Db } from "./people";
import { buildHighlights, type Highlights, type Subject as HighlightSubject } from "./chronicle-highlights";
import { parseChronicle, type Chronicle, type ChronicleEvent, type PathPoint, type Fight, type CombatSummary, type StatSnapshot, type Aura } from "./chronicle";
import { combatSummarySchema, journeyMomentSchema } from "./contracts";

export type Observation = { kind: string; observedAt: number; payload: Record<string, unknown> };
export type MapKey = { key: string; uiMapIds: readonly number[] };
export type Subject = { id?: string; name: string; classId: number; raceId?: number; realm?: string; level: number };

/** Silence longer than this (seconds) ends a play session, so a night away is not part of the recording. */
export const SESSION_GAP = 300;
const MAX_PATH = 400_000, MAX_EVENTS = 200_000;
const finite = (v: unknown): v is number => typeof v === "number" && Number.isFinite(v);
const unit = (v: unknown): v is number => finite(v) && v >= 0 && v <= 1;
const positive = (v: unknown): v is number => typeof v === "number" && Number.isInteger(v) && v > 0;
const words = (v: unknown, fallback: string, max = 160): string => (typeof v === "string" && v.trim() ? v.trim().slice(0, max) : fallback);
const round = (v: number, d: number) => Math.round(v * 10 ** d) / 10 ** d;
const JOURNEY_TEXT = { kill: "Kill", money: "Money", skill: "Skill", death: "You died", group: "Group", travel: "Travel", pvp: "PvP", combat: "Combat", action: "Action", aura: "Effect", state: "Character state", speech: "NPC" } as const;
const STAT_NAMES: Record<string,string> = {str:"Strength",agi:"Agility",sta:"Stamina",int:"Intellect",spi:"Spirit",armor:"Armor",ap:"Attack power",rap:"Ranged attack power",crit:"Melee crit %",scrit:"Spell crit %",dodge:"Dodge %",parry:"Parry %",block:"Block %",hp:"Health",mana:"Mana",holy:"Holy resistance",fire:"Fire resistance",nature:"Nature resistance",frost:"Frost resistance",shadow:"Shadow resistance",arcane:"Arcane resistance"};

/** A final, observed summary. Its run totals are never used as a single boss's totals. */
function summaryOf(raw: unknown, subject: Subject, t: number): CombatSummary | undefined {
  const parsed = combatSummarySchema.safeParse(raw);
  if (!parsed.success) return undefined;
  const p = parsed.data;
  const owner = subject.id !== undefined ? p.players.find(m => m.guid === subject.id)
    : p.players.find(m => m.name === subject.name || subject.realm && m.name === `${subject.name}-${subject.realm}`);
  const role = (value: string | undefined): "tank" | "healer" | "dps" | undefined => value?.toLowerCase() === "tank" ? "tank" : value?.toLowerCase() === "healer" ? "healer" : ["damager","damage","dps"].includes(value?.toLowerCase() ?? "") ? "dps" : undefined;
  return {t, source:p.source, coverage:p.coverage,
    me:{dmg:owner?.damage,heal:owner?.healing,taken:owner?.damageTaken,deaths:owner?.deaths,interrupts:owner?.interrupts,dispels:owner?.dispels,dealt:owner?.dealt??[],healed:owner?.healed??[],took:owner?.took??[]},
    ...(p.players.length ? {group:p.players.map(m=>({name:words(m.name,"Unknown player",80),classId:m.classId??0,role:role(m.role),dmg:m.damage,heal:m.healing,taken:m.damageTaken,deaths:m.deaths,me:m===owner||undefined}))}:{}),
  };
}

export function composeChronicle(subject: Subject, observations: readonly Observation[], maps: readonly MapKey[]): Chronicle | null {
  const keyOf = new Map<number, string>();
  for (const m of maps) for (const id of m.uiMapIds) keyOf.set(id, m.key);

  // ---- when anything happened: the stretches of play
  const stamps: number[] = [];
  const span = (from: number, to: number) => {
    if (!finite(from) || !finite(to) || to < from || to - from > 604800) return;
    // A measured continuous combat/run interval must not be mistaken for a period offline.
    const steps = Math.ceil((to-from)/SESSION_GAP);
    for (let i = 0; i < steps; i++) stamps.push(from+i*SESSION_GAP);
    stamps.push(to);
  };
  for (const o of observations) {
    if (!finite(o.observedAt)) continue;
    const p = o.payload;
    if (o.kind === "track.path" && finite(p.startedAt) && Array.isArray(p.points)) { for (const pt of p.points) if (Array.isArray(pt) && finite(pt[0])) stamps.push(p.startedAt + pt[0]); }
    else if (o.kind === "journey.chunk" && finite(p.startedAt) && Array.isArray(p.events)) {
      for (const raw of p.events) {
        const m = raw as Record<string,unknown>;
        if (!m || typeof m !== "object" || !finite(m.t)) continue;
        const at = p.startedAt + m.t;
        stamps.push(at);
        if (m.k === "combat" && m.a === "end" && finite(m.d) && m.d >= 0 && m.d <= 86400) span(at - m.d, at);
      }
    } else {
      stamps.push(o.observedAt);
      if (o.kind === "raid.encounter_finished" && finite(p.durationMs) && p.durationMs >= 0 && p.durationMs <= 86400000) span(o.observedAt-p.durationMs/1000,o.observedAt);
      if ((o.kind === "instance.entered" || o.kind === "run.finished" || o.kind === "run.interrupted") && finite(p.startedAt)) span(p.startedAt,finite(p.endedAt)?p.endedAt:o.observedAt);
    }
  }
  // Pair explicit boundaries across separate batches before constructing sessions.
  const boundary = new Map<string,{from?:number;to?:number}>();
  for (const o of observations) if (o.kind === "journey.chunk" && finite(o.payload.startedAt) && Array.isArray(o.payload.events)) for (const raw of o.payload.events) {
    const m = raw as Record<string,unknown>;
    if (!m || m.k !== "combat" || typeof m.fightId !== "string" || !finite(m.t)) continue;
    const entry = boundary.get(m.fightId) ?? {};
    if (m.a === "start") entry.from = o.payload.startedAt + m.t;
    if (m.a === "end") entry.to = o.payload.startedAt + m.t;
    boundary.set(m.fightId,entry);
  }
  for (const b of boundary.values()) if (b.from !== undefined && b.to !== undefined) span(b.from,b.to);
  if (!stamps.length) return null;
  stamps.sort((a, b) => a - b);
  const sessions: { start: number; end: number; t0: number }[] = [];
  for (const u of stamps) {
    const last = sessions[sessions.length - 1];
    if (last && u - last.end <= SESSION_GAP) last.end = u;
    else sessions.push({ start: u, end: u, t0: 0 });
  }
  let total = 0;
  for (const s of sessions) { s.end = Math.max(s.end, s.start + 2); s.t0 = total; total += s.end - s.start; }
  const duration = Math.max(1, Math.ceil(total));
  const tOf = (u: number): number => {
    let lo = 0, hi = sessions.length - 1;
    while (lo < hi) { const mid = (lo + hi + 1) >> 1; if (sessions[mid].start <= u) lo = mid; else hi = mid - 1; }
    const s = sessions[lo];
    return round(Math.min(duration, Math.max(0, s.t0 + Math.min(Math.max(u, s.start), s.end) - s.start)), 1);
  };

  // ---- zones, in the order they first appear
  const zones: string[] = [];
  const zoneIx = (key: string) => { let i = zones.indexOf(key); if (i < 0) { zones.push(key); i = zones.length - 1; } return i; };
  const where = (p: Record<string, unknown>): { zone: number; x: number; y: number } | null => {
    const key = positive(p.mapId) ? keyOf.get(p.mapId) : undefined;
    return key && unit(p.x) && unit(p.y) ? { zone: zoneIx(key), x: round(p.x, 4), y: round(p.y, 4) } : null;
  };

  // ---- the route
  const path: PathPoint[] = [];
  const pathAt: number[] = []; // the real time (unix) of every point of the route
  const tracks = observations.filter(o => o.kind === "track.path").sort((a, b) => (finite(a.payload.startedAt) ? a.payload.startedAt : 0) - (finite(b.payload.startedAt) ? b.payload.startedAt : 0));
  for (const o of tracks) {
    const p = o.payload;
    const key = positive(p.mapId) ? keyOf.get(p.mapId) : undefined;
    if (!key || !finite(p.startedAt) || !Array.isArray(p.points)) continue;
    const zi = zoneIx(key);
    for (const pt of p.points) {
      if (!Array.isArray(pt) || !finite(pt[0]) || !unit(pt[1]) || !unit(pt[2]) || path.length >= MAX_PATH) continue;
      const t = tOf(p.startedAt + pt[0]);
      const last = path[path.length - 1];
      if (last && t < last[0]) continue;
      path.push([t, zi, round(pt[1], 4), round(pt[2], 4)]);
      pathAt.push(p.startedAt + pt[0]);
    }
  }

  // ---- what happened
  const events: ChronicleEvent[] = [];
  const stats: StatSnapshot[] = [];
  const linked = new Map<ChronicleEvent,string>();
  const fightParts = new Map<string,{start?:{at:number;m:Record<string,unknown>};end?:{at:number;m:Record<string,unknown>}}>();
  const historicalBosses: {event:ChronicleEvent;from?:number;to:number}[] = [];
  const realTime = new Map<ChronicleEvent, number>(); // when (unix) each moment really happened
  let now = 0;
  const add = (e: ChronicleEvent, at = now) => { if (events.length < MAX_EVENTS) { events.push(e); realTime.set(e, at); } };
  const lastRun = new Map<string,Observation>();
  for (const o of observations) if (finite(o.observedAt) && (o.kind === "run.finished" || o.kind === "run.interrupted") && typeof o.payload.runId === "string") {
    const previous = lastRun.get(o.payload.runId);
    const quality = (row: Observation) => ({observed:2,partial:1,unavailable:0})[String((row.payload.combat as {coverage?:unknown}|undefined)?.coverage) as "observed"] ?? 0;
    if (!previous || o.observedAt > previous.observedAt || o.observedAt === previous.observedAt && quality(o) >= quality(previous)) lastRun.set(o.payload.runId,o);
  }
  const sorted = [...observations].filter(o => finite(o.observedAt) && !((o.kind === "run.finished" || o.kind === "run.interrupted") && typeof o.payload.runId === "string" && lastRun.get(o.payload.runId) !== o)).sort((a, b) => a.observedAt - b.observedAt);
  let level = 0;
  const firstLevel = sorted.find(o => o.kind === "character.level" && positive(o.payload.level));
  const startLevel = firstLevel && positive(firstLevel.payload.level) ? firstLevel.payload.level : undefined;
  const attempts = new Map<string, number>();
  const runs = new Map<string, string>();
  for (const o of sorted) {
    const p = o.payload, t = tOf(o.observedAt), spot = where(p) ?? {};
    now = o.observedAt;
    switch (o.kind) {
      case "zone.visited": {
        const key = positive(p.mapId) ? keyOf.get(p.mapId) : undefined;
        if (key) add({ t, k: "zone", text: `Entered ${words(p.mapName, key.replace(/-/g, " "), 100)}`, zone: zoneIx(key) });
        break;
      }
      case "quest.accepted": case "quest.turned_in": case "quest.abandoned": {
        if (!positive(p.questId)) break;
        const a = o.kind === "quest.accepted" ? "accept" : o.kind === "quest.abandoned" ? "abandon" : "turnin";
        add({ t, k: "quest", a, text: words(p.title, `Quest ${p.questId}`), id: p.questId, ...(a === "turnin" && finite(p.xp) && p.xp > 0 ? { xp: Math.round(p.xp) } : {}), ...spot });
        if (a === "turnin" && finite(p.money) && p.money > 0) add({ t: t + 0.1, k: "money", text: "Quest reward", n: Math.round(p.money), ...spot });
        break;
      }
      case "loot.received":
        if (positive(p.itemId) && positive(p.quantity)) add({ t, k: "loot", text: words(p.name, `Item ${p.itemId}`), n: p.quantity, id: p.itemId, ...(Number.isInteger(p.quality) && (p.quality as number) >= 0 && (p.quality as number) <= 5 ? { q: p.quality as number } : {}) });
        break;
      case "character.level":
        if (positive(p.level)) { if (level && p.level > level) add({ t, k: "level", text: `Reached level ${p.level}`, n: p.level }); level = Math.max(level, p.level); }
        break;
      case "armory.snapshot": case "character.snapshot": {
        const snapshot: StatSnapshot = {t};
        const raw = p.stats;
        if (raw && typeof raw === "object" && !Array.isArray(raw)) {
          const attrs: [string,number][] = [];
          const enh: [string,string][] = [];
          for (const [key,label] of Object.entries(STAT_NAMES)) {
            const value = (raw as Record<string,unknown>)[key];
            if (finite(value) && value >= 0 && value <= 1e7) {
              if (["crit","scrit","dodge","parry","block"].includes(key)) enh.push([label,`${value}%`]); else attrs.push([label,value]);
            }
          }
          if (attrs.length) snapshot.attrs=attrs;
          if (enh.length) snapshot.enh=enh;
        }
        const extra: Record<string,unknown> = {t:0,k:"state"};
        if (Array.isArray(p.equipped)) extra.equipped=p.equipped;
        if (Array.isArray(p.professions)) {
          const lines=p.professions as {name?:string;skill?:number;max?:number}[];
          const valid=lines.filter(x=>x&&typeof x.name==="string"&&finite(x.skill)&&finite(x.max));
          if (valid.length) {extra.skills=Object.fromEntries(valid.map(x=>[x.name!.slice(0,40),[x.skill,x.max]]));extra.professions=valid.map(x=>x.name!.slice(0,40));}
        }
        const parsed=journeyMomentSchema.safeParse(extra);
        if (parsed.success) for (const key of ["skills","professions","equipped"] as const) if(parsed.data[key]!==undefined)Object.assign(snapshot,{[key]:parsed.data[key]});
        if (Object.keys(snapshot).length>1)stats.push(snapshot);
        break;
      }
      case "instance.entered": {
        const name = words(p.name, "Instance", 100);
        if (typeof p.runId === "string") runs.set(p.runId, name);
        add({ t, k: "dungeon", a: "enter", text: name, detail: p.instanceType === "raid" ? "Raid" : "Dungeon" });
        if (Array.isArray(p.roster)) {
          const state = journeyMomentSchema.safeParse({t:0,k:"state",roster:p.roster,groupType:p.instanceType==="raid"?"raid":"party"});
          if (state.success) stats.push({t,roster:state.data.roster,groupType:state.data.groupType});
        }
        break;
      }
      case "run.finished": case "run.interrupted": {
        let name = typeof p.runId === "string" ? runs.get(p.runId) : undefined;
        const end = finite(p.endedAt) ? p.endedAt : o.observedAt;
        if (!name && typeof p.runId === "string" && typeof p.name === "string" && finite(p.startedAt) && p.startedAt <= end) {
          name = words(p.name,"Instance",100);
          add({t:tOf(p.startedAt),k:"dungeon",a:"enter",text:name,detail:p.instanceType==="raid"?"Raid":"Dungeon"},p.startedAt);
        }
        const summary = summaryOf(p.combat,subject,tOf(end));
        if (name && typeof p.runId === "string") { add({ t:tOf(end), k: "dungeon", a: "leave", text: name, ...(p.instanceType === "raid" ? {detail:"Raid"} : {}), ...(summary?{summary}:{}) },end); runs.delete(p.runId); }
        break;
      }
      case "journey.chunk": {
        if (!finite(p.startedAt) || !Array.isArray(p.events)) break;
        for (const raw of p.events) {
          let m = raw as Record<string, unknown>;
          if (!m || typeof m !== "object" || !finite(m.t) || typeof m.k !== "string" || !(m.k in JOURNEY_TEXT)) continue;
          if (["combat","action","aura","state","speech"].includes(m.k)) {
            const parsed = journeyMomentSchema.safeParse(m);
            if (!parsed.success) continue;
            m = parsed.data;
          }
          const kind = m.k as keyof typeof JOURNEY_TEXT;
          const at = p.startedAt + (m.t as number), time = tOf(at);
          const event: ChronicleEvent = { t: time, k: kind, text: words(m.text, JOURNEY_TEXT[kind], 120), ...(typeof m.a === "string" ? { a: m.a.slice(0, 24) } : {}),
            ...(finite(m.n) ? { n: Math.round(m.n) } : {}), ...(finite(m.max) && m.max > 0 ? { max: Math.round(m.max) } : {}), ...(finite(m.xp) && m.xp > 0 ? { xp: Math.round(m.xp) } : {}),
            ...(positive(m.id) ? {id:m.id} : {}), ...(finite(m.d) && m.d >= 0 ? { d: round(m.d, 1) } : {}), ...(typeof m.detail === "string" ? { detail: m.detail.slice(0, 300) } : {}), ...(where(m) ?? {}) };
          if (kind === "aura") for (const key of ["helpful","stacks","duration","expiresAt","icon"] as const) if (m[key] !== undefined) Object.assign(event,{[key]:m[key]});
          if (kind === "speech") {if(typeof m.message==='string')event.message=m.message;if(typeof m.speaker==='string')event.speaker=m.speaker;}
          if (typeof m.actor === "string") event.actor=m.actor;
          if (typeof m.target === "string") event.target=m.target;
          if (typeof m.actorClassId === "number") event.actorClassId=m.actorClassId;
          if (m.actorSide === "me" || m.actorSide === "party" || m.actorSide === "enemy") event.actorSide=m.actorSide;
          add(event, at);
          if (typeof m.fightId === "string") linked.set(event,m.fightId);
          if (kind === "combat" && typeof m.fightId === "string") {
            const parts = fightParts.get(m.fightId) ?? {};
            if (m.a === "start" && !parts.start) parts.start = {at,m};
            if (m.a === "end") parts.end = {at,m};
            fightParts.set(m.fightId,parts);
          }
          if (kind === "state") {
            const snapshot: StatSnapshot = {t:time};
            for (const key of ["attrs","enh","ilvl","roster","groupType","auras","aurasKnown","copper","played","race","faction","guild","spec","skills","professions","equipped"] as const) if (m[key] !== undefined) Object.assign(snapshot,{[key]:m[key]});
            stats.push(snapshot);
          }
        }
        break;
      }
      case "raid.encounter_finished": {
        if (!positive(p.encounterId)) break;
        const slot = `${p.instanceName ?? ""}:${p.encounterId}`;
        const attempt = (attempts.get(slot) ?? 0) + 1;
        attempts.set(slot, attempt);
        const event: ChronicleEvent = { t, k: "boss", a: p.success === true ? "kill" : "wipe", text: words(p.name, `Encounter ${p.encounterId}`, 100), n: attempt,
          ...(finite(p.durationMs) ? { d: round(p.durationMs / 1000, 1) } : {}), ...(typeof p.instanceName === "string" ? { detail: p.instanceName.slice(0, 200) } : {}) };
        add(event);
        historicalBosses.push({event,...(finite(p.durationMs) && p.durationMs > 0 ? {from:o.observedAt-p.durationMs/1000} : {}),to:o.observedAt});
        break;
      }
    }
  }
  const fights: Fight[] = [];
  const byId = new Map<string,Fight>();
  const eventFights = new Map<ChronicleEvent,Fight>();
  const unknownMe = (): Fight["me"] => ({dealt:[],healed:[],took:[]});
  for (const [id,parts] of fightParts) {
    if (fights.length >= 5000) break;
    const end = parts.end, start = parts.start;
    if (!end && !start) continue;
    const last = end ?? start!;
    const d = end && finite(end.m.d) && end.m.d >= 0 ? end.m.d : undefined;
    let from = start?.at ?? (end && d !== undefined ? end.at-d : end!.at);
    const to = end?.at ?? sessions[sessions.length-1].end;
    if (d !== undefined && (from >= to && d > 0 || Math.abs(to-from-d)>2)) from = to-d;
    if (to < from) continue;
    const summary = summaryOf(end?.m.summary,subject,tOf(to));
    const kind = last.m.encounterKind === "boss" ? "boss" : last.m.encounterKind === "pvp" ? "pvp" : "combat";
    const result = end && typeof end.m.result === "string" && ["kill","wipe","win","loss","ended","interrupted"].includes(end.m.result) ? end.m.result as Fight["result"] : end ? "ended" : "interrupted";
    const f: Fight = {...(summary??{me:unknownMe(),source:"unavailable" as const,coverage:"unavailable" as const}),t:tOf(from),d:round(tOf(to)-tOf(from),1),kind,name:words(last.m.text,words(start?.m.text,"Combat",80),80),result,...(where(start?.m??last.m)??{})};
    const context={...start?.m,...end?.m};
    if(typeof context.difficulty==='string')f.difficulty=context.difficulty.slice(0,80);
    if(positive(context.size)&&context.size<=80)f.size=context.size;
    if(positive(context.npcId)&&(!start?.m.text||last.m.text===start.m.text||end?.m.npcId))f.npcId=context.npcId;
    // Coordinates belong to moments/path; a fight keeps only its zone.
    delete (f as unknown as Record<string,unknown>).x; delete (f as unknown as Record<string,unknown>).y;
    fights.push(f);byId.set(id,f);
  }
  for (const b of historicalBosses) {
    const existing = fights.find(f=>f.kind==="boss"&&f.name===b.event.text.slice(0,80)&&Math.abs(f.t+f.d-b.event.t)<=2);
    if (existing) {eventFights.set(b.event,existing);continue;}
    if (b.from === undefined || fights.length >= 5000) continue;
    const f: Fight = {t:tOf(b.from),d:round(tOf(b.to)-tOf(b.from),1),kind:"boss",name:b.event.text.slice(0,80),result:b.event.a==="kill"?"kill":"wipe",attempt:b.event.n,me:unknownMe(),source:"unavailable",coverage:"unavailable"};
    fights.push(f);eventFights.set(b.event,f);
  }
  fights.sort((a,b)=>a.t-b.t);
  const fightIndices = new Map(fights.map((f,i)=>[f,i]));
  for (const [event,id] of linked) { const f=byId.get(id);if(f)eventFights.set(event,f); }
  for (const [event,f] of eventFights) {event.f=fightIndices.get(f);if(event.k==="combat")event.encounterKind=f.kind;}
  events.sort((a, b) => a.t - b.t);
  stats.sort((a,b)=>a.t-b.t);
  // the website keeps no coordinates of quests and loot, so these moments take the place of the route at that time: the last point of the
  // route before the moment, but only when it is close in REAL time (the recording leaves out the breaks, so its own clock would not tell)
  const HEARTBEAT = 130;
  for (const e of events) {
    if (e.zone !== undefined && e.x !== undefined) continue;
    const at = realTime.get(e) ?? 0;
    let lo = 0, hi = pathAt.length;
    while (lo < hi) { const mid = (lo + hi) >> 1; if (pathAt[mid] <= at) lo = mid + 1; else hi = mid; }
    const i = lo - 1;
    if (i >= 0 && at - pathAt[i] <= HEARTBEAT && (e.zone === undefined || e.zone === path[i][1])) { e.zone = path[i][1]; e.x = path[i][2]; e.y = path[i][3]; }
  }

  const chronicle: Chronicle = {
    v: 1,
    character: { name: subject.name.slice(0, 64), classId: subject.classId, ...(subject.raceId ? { raceId: subject.raceId } : {}), ...(subject.realm ? { realm: subject.realm.slice(0, 80) } : {}), level: startLevel ?? subject.level },
    startedAt: sessions[0].start, duration, zones: zones.length ? zones : ["azeroth"], path, events,
    sessions: sessions.map(s => ({ t: s.t0, at: s.start })),
    ...(fights.length ? {fights} : {}),...(stats.length ? {stats} : {}),
  };
  return parseChronicle(chronicle);
}

type Row = Record<string, unknown>;
const HAS = (scope: string) => `EXISTS(SELECT 1 FROM json_each(g.scopes) WHERE value='${scope}')`;

/** How long a recording is, written the way a visitor reads it, and when it was played. */
export type ChronicleSummary = { seconds: number; sessions: number; from: number; to: number; events: number; zones: number };
export function summarize(c: Chronicle): ChronicleSummary {
  const sessions = c.sessions ?? [{ t: 0, at: c.startedAt }];
  const last = sessions[sessions.length - 1];
  return { seconds: c.duration, sessions: sessions.length, from: sessions[0].at, to: Math.round(last.at + (c.duration - last.t)), events: c.events.length, zones: c.zones.length };
}
export type ChronicleListing = { profileId: string; name: string; realm: string | null; classId: number | null; raceId: number | null; level: number | null; shared: boolean; own: boolean; summary: ChronicleSummary };

/** The most events one chronicle is composed from (a very long history keeps its newest part). */
const MAX_ROWS = 100_000;
const PROFILE_COLUMNS = "id,user_id,character_key,name,realm,class_id,race_id,level,public,show_chronicle,last_seen";
/** The recording of a character for the last `days` days, composed from what the owner's consents allow. */
async function compose(db: Db, profile: Row, days: number, maps: readonly MapKey[], at: number): Promise<{ chronicle: Chronicle | null; observations: number }> {
  const userId = String(profile.user_id), profileId = String(profile.id);
  // days <= 0 (or none): the whole history, however long it is
  const span = days > 0 ? Math.min(3650, Math.floor(days)) : 0;
  const rows = await db.prepare(`SELECT o.kind,o.observed_at,o.payload FROM atlas_observations o JOIN atlas_grants g ON g.id=o.grant_id AND g.user_id=o.user_id
    WHERE o.user_id=? AND o.profile_id=? AND o.observed_at>=? AND g.revoked_at IS NULL AND (
      (o.kind IN ('track.path','journey.chunk') AND ${HAS("own_track")})
      OR (o.kind IN ('instance.entered','run.finished','run.interrupted','raid.encounter_finished') AND ${HAS("own_runs")})
      OR (o.kind IN ('character.level','character.snapshot','armory.snapshot','quest.accepted','quest.turned_in','quest.abandoned','loot.received','zone.visited') AND ${HAS("own_character")}))
    ORDER BY o.observed_at DESC LIMIT ${MAX_ROWS}`).bind(userId, profileId, span ? at - span * 86400 : 0).all<Row>();
  const observations: Observation[] = [];
  // the newest rows are kept when a history is longer than the limit; they are put back in the order of time
  for (const r of rows.results.reverse()) {
    try { const payload = JSON.parse(String(r.payload)); if (payload && typeof payload === "object" && !Array.isArray(payload)) observations.push({ kind: String(r.kind), observedAt: Number(r.observed_at), payload }); } catch { /* a damaged row is skipped */ }
  }
  const subject: Subject = {
    ...(typeof profile.character_key === "string" ? {id:profile.character_key} : {}),
    name: typeof profile.name === "string" && profile.name ? profile.name : "?", classId: Number(profile.class_id) || 1, level: Number(profile.level) || 1,
    ...(profile.race_id ? { raceId: Number(profile.race_id) } : {}), ...(typeof profile.realm === "string" && profile.realm ? { realm: profile.realm } : {}),
  };
  return { chronicle: composeChronicle(subject, observations, maps), observations: observations.length };
}

/**
 * The recording of one character. Its owner may always read it; everybody else only when the player made the character public AND
 * turned the public chronicle on (in the game or on the website). Anything else is "not there", so nothing tells a stranger it exists.
 */
export async function readChronicle(db: Db, viewerId: string | null, profileId: string, days: number, maps: readonly MapKey[], at = Math.floor(Date.now() / 1000)): Promise<{ chronicle: Chronicle | null; observations: number; shared: boolean; own: boolean } | null> {
  const profile = await db.prepare(`SELECT ${PROFILE_COLUMNS} FROM atlas_profiles WHERE id=?`).bind(profileId).first<Row>();
  if (!profile) return null;
  const own = viewerId !== null && String(profile.user_id) === viewerId;
  const shared = Number(profile.public) === 1 && Number(profile.show_chronicle) === 1;
  if (!own && !shared) return null;
  return { ...await compose(db, profile, days, maps, at), shared, own };
}
/** The older name: the owner's own character only. */
export async function myChronicle(db: Db, userId: string, profileId: string, days: number, maps: readonly MapKey[], at = Math.floor(Date.now() / 1000)): Promise<{ chronicle: Chronicle | null; observations: number } | null> {
  const profile = await db.prepare(`SELECT ${PROFILE_COLUMNS} FROM atlas_profiles WHERE id=? AND user_id=?`).bind(profileId, userId).first<Row>();
  if (!profile) return null;
  const { chronicle, observations } = await compose(db, profile, days, maps, at);
  return { chronicle, observations };
}

const memo = new WeakMap<object, Map<string, { at: number; version: string; value: Chronicle | null }>>();
/** A remembered chronicle is used again until the character has new data or a consent changed; this is only the longest it is kept. */
const REMEMBER = 3600;
/** The chronicle of a character that is shared, composed from the stored events and remembered until something new arrives for it. */
async function composeShared(db: Db, profile: Row, days: number, maps: readonly MapKey[], at: number): Promise<Chronicle | null> {
  let cache = memo.get(db);
  if (!cache) { cache = new Map(); memo.set(db, cache); }
  const key = `${profile.id}:${days > 0 ? Math.floor(days) : 0}`;
  // new data moves the last time the character was seen; a revoked consent changes the number of revoked ones
  const revoked = await db.prepare("SELECT COUNT(*) AS n FROM atlas_grants WHERE user_id=? AND revoked_at IS NOT NULL").bind(String(profile.user_id)).first<Row>();
  const version = `${profile.last_seen}:${profile.level}:${revoked?.n ?? 0}`;
  const hit = cache.get(key);
  if (hit && hit.version === version && at - hit.at <= REMEMBER) return hit.value;
  const { chronicle } = await compose(db, profile, days, maps, at);
  const value = chronicle && (chronicle.path.length || chronicle.events.length) ? chronicle : null;
  cache.set(key, { at, version, value });
  return value;
}
const isShared = (profile: Row) => Number(profile.public) === 1 && Number(profile.show_chronicle) === 1;
const listing = (profile: Row, chronicle: Chronicle, own: boolean): ChronicleListing => ({
  profileId: String(profile.id), name: String(profile.name ?? "?"), realm: typeof profile.realm === "string" ? profile.realm : null,
  classId: profile.class_id == null ? null : Number(profile.class_id), raceId: profile.race_id == null ? null : Number(profile.race_id), level: profile.level == null ? null : Number(profile.level),
  shared: isShared(profile), own, summary: summarize(chronicle),
});

/**
 * The public chronicles, newest played first, each with how long it is and when it was played; the viewer's own characters are in it
 * too (marked as not shared when they are not). Who is in the list is read every time, so turning a chronicle off takes effect at once;
 * only the composing of the shared ones is remembered, and only until new data arrives for them.
 */
export async function listChronicles(db: Db, viewerId: string | null, days: number, maps: readonly MapKey[], at = Math.floor(Date.now() / 1000)): Promise<ChronicleListing[]> {
  const profiles = await db.prepare(`SELECT ${PROFILE_COLUMNS} FROM atlas_profiles WHERE (public=1 AND show_chronicle=1) OR user_id=? ORDER BY last_seen DESC LIMIT 40`).bind(viewerId ?? "").all<Row>();
  const out: ChronicleListing[] = [];
  for (const profile of profiles.results) {
    const own = viewerId !== null && String(profile.user_id) === viewerId;
    const chronicle = isShared(profile) ? await composeShared(db, profile, days, maps, at) : (await compose(db, profile, days, maps, at)).chronicle;
    if (chronicle && (chronicle.path.length || chronicle.events.length)) out.push(listing(profile, chronicle, own));
  }
  return out.sort((a, b) => b.summary.to - a.summary.to);
}

/** What happened lately in the shared chronicles, and the boards of the best of them (only what players chose to share). */
export async function publicHighlights(db: Db, days: number, maps: readonly MapKey[], at = Math.floor(Date.now() / 1000)): Promise<Highlights> {
  const profiles = await db.prepare(`SELECT ${PROFILE_COLUMNS} FROM atlas_profiles WHERE public=1 AND show_chronicle=1 ORDER BY last_seen DESC LIMIT 40`).all<Row>();
  const subjects: HighlightSubject[] = [];
  for (const profile of profiles.results) {
    const c = await composeShared(db, profile, days, maps, at);
    if (c) subjects.push({ profileId: String(profile.id), name: String(profile.name ?? "?"), realm: typeof profile.realm === "string" ? profile.realm : null, classId: profile.class_id == null ? null : Number(profile.class_id), level: profile.level == null ? null : Number(profile.level), c });
  }
  return buildHighlights(subjects);
}

// A journey recording composed from what the website already stores about a character: the walked routes, the zones visited, the quests,
// the loot, the levels, the dungeons and the bosses. No new data from the addon is needed. What is not stored (kills, money, skills,
// deaths, spells) is not invented: the recording simply has none of it. See docs/KRONIKA-FORMAT.md, section 3b.
import type { Db } from "./people";
import { parseChronicle, type Chronicle, type ChronicleEvent, type PathPoint } from "./chronicle";

export type Observation = { kind: string; observedAt: number; payload: Record<string, unknown> };
export type MapKey = { key: string; uiMapIds: readonly number[] };
export type Subject = { name: string; classId: number; raceId?: number; realm?: string; level: number };

/** Silence longer than this (seconds) ends a play session, so a night away is not part of the recording. */
export const SESSION_GAP = 300;
const MAX_PATH = 400_000, MAX_EVENTS = 200_000;
const finite = (v: unknown): v is number => typeof v === "number" && Number.isFinite(v);
const unit = (v: unknown): v is number => finite(v) && v >= 0 && v <= 1;
const positive = (v: unknown): v is number => typeof v === "number" && Number.isInteger(v) && v > 0;
const words = (v: unknown, fallback: string, max = 160): string => (typeof v === "string" && v.trim() ? v.trim().slice(0, max) : fallback);
const round = (v: number, d: number) => Math.round(v * 10 ** d) / 10 ** d;

export function composeChronicle(subject: Subject, observations: readonly Observation[], maps: readonly MapKey[]): Chronicle | null {
  const keyOf = new Map<number, string>();
  for (const m of maps) for (const id of m.uiMapIds) keyOf.set(id, m.key);

  // ---- when anything happened: the stretches of play
  const stamps: number[] = [];
  for (const o of observations) {
    if (!finite(o.observedAt)) continue;
    const p = o.payload;
    if (o.kind === "track.path" && finite(p.startedAt) && Array.isArray(p.points)) { for (const pt of p.points) if (Array.isArray(pt) && finite(pt[0])) stamps.push(p.startedAt + pt[0]); }
    else stamps.push(o.observedAt);
  }
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
    }
  }

  // ---- what happened
  const events: ChronicleEvent[] = [];
  const add = (e: ChronicleEvent) => { if (events.length < MAX_EVENTS) events.push(e); };
  const sorted = [...observations].filter(o => finite(o.observedAt)).sort((a, b) => a.observedAt - b.observedAt);
  let level = 0;
  const firstLevel = sorted.find(o => o.kind === "character.level" && positive(o.payload.level));
  const startLevel = firstLevel && positive(firstLevel.payload.level) ? firstLevel.payload.level : undefined;
  const attempts = new Map<string, number>();
  const runs = new Map<string, string>();
  for (const o of sorted) {
    const p = o.payload, t = tOf(o.observedAt), spot = where(p) ?? {};
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
        if (positive(p.itemId) && positive(p.quantity)) add({ t, k: "loot", text: words(p.name, `Item ${p.itemId}`), n: p.quantity, id: p.itemId });
        break;
      case "character.level":
        if (positive(p.level)) { if (level && p.level > level) add({ t, k: "level", text: `Reached level ${p.level}`, n: p.level }); level = Math.max(level, p.level); }
        break;
      case "instance.entered": {
        const name = words(p.name, "Instance", 100);
        if (typeof p.runId === "string") runs.set(p.runId, name);
        add({ t, k: "dungeon", a: "enter", text: name, detail: p.instanceType === "raid" ? "Raid" : "Dungeon" });
        break;
      }
      case "run.finished": case "run.interrupted": {
        const name = typeof p.runId === "string" ? runs.get(p.runId) : undefined;
        if (name && typeof p.runId === "string") { add({ t, k: "dungeon", a: "leave", text: name }); runs.delete(p.runId); }
        break;
      }
      case "raid.encounter_finished": {
        if (!positive(p.encounterId)) break;
        const slot = `${p.instanceName ?? ""}:${p.encounterId}`;
        const attempt = (attempts.get(slot) ?? 0) + 1;
        attempts.set(slot, attempt);
        add({ t, k: "boss", a: p.success === true ? "kill" : "wipe", text: words(p.name, `Encounter ${p.encounterId}`, 100), n: attempt,
          ...(finite(p.durationMs) ? { d: round(p.durationMs / 1000, 1) } : {}), ...(typeof p.instanceName === "string" ? { detail: p.instanceName.slice(0, 200) } : {}) });
        break;
      }
    }
  }
  events.sort((a, b) => a.t - b.t);

  const chronicle: Chronicle = {
    v: 1,
    character: { name: subject.name.slice(0, 64), classId: subject.classId, ...(subject.raceId ? { raceId: subject.raceId } : {}), ...(subject.realm ? { realm: subject.realm.slice(0, 80) } : {}), level: startLevel ?? subject.level },
    startedAt: sessions[0].start, duration, zones: zones.length ? zones : ["azeroth"], path, events,
    sessions: sessions.map(s => ({ t: s.t0, at: s.start })),
  };
  return parseChronicle(chronicle);
}

type Row = Record<string, unknown>;
const HAS = (scope: string) => `EXISTS(SELECT 1 FROM json_each(g.scopes) WHERE value='${scope}')`;
/**
 * The recording of one of the account's characters for the last `days` days. Only what the owner's consents allow is read: the route
 * needs "My route", the dungeons and bosses need "My runs", the rest "My character". Returns null when the character is not theirs.
 */
export async function myChronicle(db: Db, userId: string, profileId: string, days: number, maps: readonly MapKey[], at = Math.floor(Date.now() / 1000)): Promise<{ chronicle: Chronicle | null; observations: number } | null> {
  const profile = await db.prepare("SELECT name,realm,class_id,race_id,level FROM atlas_profiles WHERE id=? AND user_id=?").bind(profileId, userId).first<Row>();
  if (!profile) return null;
  const span = Math.min(60, Math.max(1, Math.floor(days) || 14));
  const rows = await db.prepare(`SELECT o.kind,o.observed_at,o.payload FROM atlas_observations o JOIN atlas_grants g ON g.id=o.grant_id AND g.user_id=o.user_id
    WHERE o.user_id=? AND o.profile_id=? AND o.observed_at>=? AND g.revoked_at IS NULL AND (
      (o.kind='track.path' AND ${HAS("own_track")})
      OR (o.kind IN ('instance.entered','run.finished','run.interrupted','raid.encounter_finished') AND ${HAS("own_runs")})
      OR (o.kind IN ('character.level','quest.accepted','quest.turned_in','quest.abandoned','loot.received','zone.visited') AND ${HAS("own_character")}))
    ORDER BY o.observed_at LIMIT 20000`).bind(userId, profileId, at - span * 86400).all<Row>();
  const observations: Observation[] = [];
  for (const r of rows.results) {
    try { const payload = JSON.parse(String(r.payload)); if (payload && typeof payload === "object" && !Array.isArray(payload)) observations.push({ kind: String(r.kind), observedAt: Number(r.observed_at), payload }); } catch { /* a damaged row is skipped */ }
  }
  const subject: Subject = {
    name: typeof profile.name === "string" && profile.name ? profile.name : "?", classId: Number(profile.class_id) || 1, level: Number(profile.level) || 1,
    ...(profile.race_id ? { raceId: Number(profile.race_id) } : {}), ...(typeof profile.realm === "string" && profile.realm ? { realm: profile.realm } : {}),
  };
  return { chronicle: composeChronicle(subject, observations, maps), observations: observations.length };
}

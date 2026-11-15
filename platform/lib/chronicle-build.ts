// A journey recording composed from what the website already stores about a character: the walked routes, the zones visited, the quests,
// the loot, the levels, the dungeons and the bosses. No new data from the addon is needed. What is not stored (kills, money, skills,
// deaths, spells) is not invented: the recording simply has none of it. See docs/KRONIKA-FORMAT.md, section 3b.
import type { Db } from "./people";
import { buildHighlights, type Highlights, type Subject as HighlightSubject } from "./chronicle-highlights";
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
const JOURNEY_TEXT = { kill: "Kill", money: "Money", skill: "Skill", death: "You died", group: "Group", travel: "Travel", pvp: "PvP" } as const;

export function composeChronicle(subject: Subject, observations: readonly Observation[], maps: readonly MapKey[]): Chronicle | null {
  const keyOf = new Map<number, string>();
  for (const m of maps) for (const id of m.uiMapIds) keyOf.set(id, m.key);

  // ---- when anything happened: the stretches of play
  const stamps: number[] = [];
  for (const o of observations) {
    if (!finite(o.observedAt)) continue;
    const p = o.payload;
    if (o.kind === "track.path" && finite(p.startedAt) && Array.isArray(p.points)) { for (const pt of p.points) if (Array.isArray(pt) && finite(pt[0])) stamps.push(p.startedAt + pt[0]); }
    else if (o.kind === "journey.chunk" && finite(p.startedAt) && Array.isArray(p.events)) { for (const m of p.events) if (m && typeof m === "object" && finite((m as { t?: unknown }).t)) stamps.push(p.startedAt + (m as { t: number }).t); }
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
  const realTime = new Map<ChronicleEvent, number>(); // when (unix) each moment really happened
  let now = 0;
  const add = (e: ChronicleEvent, at = now) => { if (events.length < MAX_EVENTS) { events.push(e); realTime.set(e, at); } };
  const sorted = [...observations].filter(o => finite(o.observedAt)).sort((a, b) => a.observedAt - b.observedAt);
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
      case "journey.chunk": {
        if (!finite(p.startedAt) || !Array.isArray(p.events)) break;
        for (const raw of p.events) {
          const m = raw as Record<string, unknown>;
          if (!m || typeof m !== "object" || !finite(m.t) || typeof m.k !== "string" || !(m.k in JOURNEY_TEXT)) continue;
          const kind = m.k as keyof typeof JOURNEY_TEXT;
          add({ t: tOf(p.startedAt + m.t), k: kind, text: words(m.text, JOURNEY_TEXT[kind], 120), ...(typeof m.a === "string" ? { a: m.a.slice(0, 24) } : {}),
            ...(finite(m.n) ? { n: Math.round(m.n) } : {}), ...(finite(m.max) && m.max > 0 ? { max: Math.round(m.max) } : {}), ...(finite(m.xp) && m.xp > 0 ? { xp: Math.round(m.xp) } : {}),
            ...(finite(m.d) && m.d >= 0 ? { d: round(m.d, 1) } : {}), ...(typeof m.detail === "string" ? { detail: m.detail.slice(0, 300) } : {}), ...(where(m) ?? {}) }, p.startedAt + m.t);
        }
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
const PROFILE_COLUMNS = "id,user_id,name,realm,class_id,race_id,level,public,show_chronicle,last_seen";
/** The recording of a character for the last `days` days, composed from what the owner's consents allow. */
async function compose(db: Db, profile: Row, days: number, maps: readonly MapKey[], at: number): Promise<{ chronicle: Chronicle | null; observations: number }> {
  const userId = String(profile.user_id), profileId = String(profile.id);
  // days <= 0 (or none): the whole history, however long it is
  const span = days > 0 ? Math.min(3650, Math.floor(days)) : 0;
  const rows = await db.prepare(`SELECT o.kind,o.observed_at,o.payload FROM atlas_observations o JOIN atlas_grants g ON g.id=o.grant_id AND g.user_id=o.user_id
    WHERE o.user_id=? AND o.profile_id=? AND o.observed_at>=? AND g.revoked_at IS NULL AND (
      (o.kind IN ('track.path','journey.chunk') AND ${HAS("own_track")})
      OR (o.kind IN ('instance.entered','run.finished','run.interrupted','raid.encounter_finished') AND ${HAS("own_runs")})
      OR (o.kind IN ('character.level','quest.accepted','quest.turned_in','quest.abandoned','loot.received','zone.visited') AND ${HAS("own_character")}))
    ORDER BY o.observed_at DESC LIMIT ${MAX_ROWS}`).bind(userId, profileId, span ? at - span * 86400 : 0).all<Row>();
  const observations: Observation[] = [];
  // the newest rows are kept when a history is longer than the limit; they are put back in the order of time
  for (const r of rows.results.reverse()) {
    try { const payload = JSON.parse(String(r.payload)); if (payload && typeof payload === "object" && !Array.isArray(payload)) observations.push({ kind: String(r.kind), observedAt: Number(r.observed_at), payload }); } catch { /* a damaged row is skipped */ }
  }
  const subject: Subject = {
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

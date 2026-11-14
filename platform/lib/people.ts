// People on the map: the player's own route and the guild they belong to.
//
// Consent is layered, and every layer can say no on its own:
//  1. the addon records and exports positions only with the own_track scope, guild identity only with guild_share;
//  2. a route is private to the account that uploaded it;
//  3. a guild member sees another member only when BOTH confirmed the guild on the website (status "active"),
//     both appear in the roster a guild master imported, and the other member chose to share ("last" or "trail").
//
// The server cannot verify a guild rank (the addon is the only witness), so the first importer of a roster owns it
// and every member sees who that is before confirming. Leaving the guild in game, or being dropped from the next
// roster import, ends visibility automatically.
//
// Everything here takes the database as a parameter so the exact SQL can be exercised against SQLite in tests.
import { ApiError } from "./policy";
import { livePositions } from "./live-query";

export interface Stmt {
  bind(...values: unknown[]): Stmt;
  all<T = Record<string, unknown>>(): Promise<{ results: T[] }>;
  first<T = Record<string, unknown>>(): Promise<T | null>;
  run(): Promise<{ meta: { changes?: number } }>;
}
export interface Db { prepare(sql: string): Stmt; batch(statements: Stmt[]): Promise<unknown[]> }

type Row = Record<string, unknown>;
export const now = () => Math.floor(Date.now() / 1000);

export const TRACK_RETENTION_SECONDS = 30 * 86400;
export const GUILD_TRAIL_MAX_HOURS = 72;
export const MY_TRAIL_MAX_PATHS = 1500;
export const SHARE_MODES = ["off", "last", "trail"] as const;
export type ShareMode = typeof SHARE_MODES[number];

/** The in-game roster lists "Name" or "Name-Realm"; membership is matched on the bare, lower-cased name. */
export const baseName = (name: string) => name.split("-")[0].trim().toLowerCase();

async function hash(...parts: string[]) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(JSON.stringify(parts)));
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}
export const guildId = (realm: string, name: string) => hash("guild", realm.trim().toLowerCase(), name.trim().toLowerCase());

export const decode = <T,>(value: unknown, fallback: T): T => { try { return JSON.parse(String(value)) as T; } catch { return fallback; } };

export type RosterEntry = [name: string, rankIndex: number, level: number | null, classId: number | null];

export interface GuildSnapshot {
  profileId: string; name: string; realm: string; observedAt: number;
  guildName?: string; rankIndex?: number;
  roster?: { name: string; rankIndex: number; level?: number; classId?: number }[];
}

/** Applies the guild.snapshot events of one upload. Idempotent: replaying an older snapshot changes nothing. */
export async function applyGuildSnapshots(db: Db, userId: string, snapshots: GuildSnapshot[]): Promise<{ contested: number }> {
  let contested = 0;
  for (const item of [...snapshots].sort((a, b) => a.observedAt - b.observedAt)) {
    if (!item.guildName) {
      await db.prepare("UPDATE et_guild_members SET status='left',seen_at=? WHERE profile_id=? AND user_id=? AND seen_at<=? AND status<>'left'")
        .bind(item.observedAt, item.profileId, userId, item.observedAt).run();
      continue;
    }
    const id = await guildId(item.realm, item.guildName);
    const statements = [
      db.prepare("INSERT INTO et_guilds(id,name,realm,owner_user_id,owner_name,roster,roster_at,created_at) VALUES(?,?,?,NULL,NULL,'[]',NULL,?) ON CONFLICT(id) DO NOTHING")
        .bind(id, item.guildName, item.realm, now()),
      db.prepare(`INSERT INTO et_guild_members(guild_id,profile_id,user_id,name,rank_index,status,share,seen_at) VALUES(?,?,?,?,?,'pending','last',?)
        ON CONFLICT(guild_id,profile_id) DO UPDATE SET name=excluded.name,rank_index=excluded.rank_index,seen_at=excluded.seen_at,
          status=CASE WHEN et_guild_members.status='left' THEN 'pending' ELSE et_guild_members.status END
        WHERE excluded.seen_at>=et_guild_members.seen_at AND et_guild_members.user_id=excluded.user_id`)
        .bind(id, item.profileId, userId, item.name, item.rankIndex ?? null, item.observedAt),
      db.prepare("UPDATE et_guild_members SET status='left' WHERE profile_id=? AND user_id=? AND guild_id<>? AND seen_at<=? AND status<>'left'")
        .bind(item.profileId, userId, id, item.observedAt),
    ];
    if (item.rankIndex === 0 && item.roster) {
      const roster: RosterEntry[] = item.roster.map((r) => [r.name, r.rankIndex, r.level ?? null, r.classId ?? null]);
      // The condition makes the claim atomic: the first master to import owns the roster, later ones cannot overwrite it.
      statements.push(db.prepare(`UPDATE et_guilds SET owner_user_id=?,owner_name=?,roster=?,roster_at=?
        WHERE id=? AND (owner_user_id IS NULL OR owner_user_id=?) AND (roster_at IS NULL OR roster_at<=?)`)
        .bind(userId, item.name, JSON.stringify(roster), item.observedAt, id, userId, item.observedAt));
    }
    await db.batch(statements);
    if (item.rankIndex === 0 && item.roster) {
      const owner = await db.prepare("SELECT owner_user_id FROM et_guilds WHERE id=?").bind(id).first<{ owner_user_id: string | null }>();
      if (owner && owner.owner_user_id !== userId) contested++;
    }
  }
  return { contested };
}

function eligibleFor(guild: { owner_user_id: unknown; roster: unknown }, userId: string, name: string) {
  if (guild.owner_user_id === null || guild.owner_user_id === undefined) return false;
  if (guild.owner_user_id === userId) return true;
  const target = baseName(name);
  return decode<RosterEntry[]>(guild.roster, []).some((entry) => baseName(String(entry[0])) === target);
}

/** The guilds this account is confirmed in (active, and still listed by the master's roster): who a guild meet may be shown to. */
export async function myGuildIds(db: Db, userId: string): Promise<string[]> {
  const rows = await db.prepare(`SELECT m.guild_id,m.name,g.owner_user_id,g.roster FROM et_guild_members m JOIN et_guilds g ON g.id=m.guild_id WHERE m.user_id=? AND m.status='active'`).bind(userId).all();
  return [...new Set(rows.results.filter(row => eligibleFor(row as { owner_user_id: unknown; roster: unknown }, userId, String(row.name))).map(row => String(row.guild_id)))];
}

export type Point = [seconds: number, x: number, y: number];
export interface TrackPath { id: string; profileId: string | null; mapId: number; startedAt: number; endedAt: number; points: Point[] }

export function toPath(row: Row): TrackPath | null {
  const payload = decode<{ mapId?: number; startedAt?: number; points?: Point[] }>(row.payload, {});
  if (typeof payload.mapId !== "number" || typeof payload.startedAt !== "number" || !Array.isArray(payload.points) || !payload.points.length) return null;
  const last = payload.points[payload.points.length - 1];
  return { id: String(row.id), profileId: typeof row.profile_id === "string" ? row.profile_id : null, mapId: payload.mapId, startedAt: payload.startedAt, endedAt: payload.startedAt + last[0], points: payload.points };
}

// A route observation only counts while its grant is live and still carries the scopes it needs.
export const GRANT_OK = (needs: string[]) => `g.revoked_at IS NULL AND ${needs.map((scope) => `EXISTS(SELECT 1 FROM json_each(g.scopes) WHERE value='${scope}')`).join(" AND ")}`;
export async function ownLive(db:Db,userId:string) {
  const profiles=await db.prepare("SELECT id,name,class_id FROM atlas_profiles WHERE user_id=?").bind(userId).all();
  const positions=await livePositions(db,profiles.results.map(p=>String(p.id)),["own_track"]);
  return profiles.results.flatMap(p=>{const position=positions.get(String(p.id));return position?[{profileId:String(p.id),name:typeof p.name==="string"?p.name:null,classId:typeof p.class_id==="number"?p.class_id:null,...position}]:[];});
}

export async function myTrail(db: Db, userId: string, options: { profileId?: string; since: number }) {
  const rows = await db.prepare(`SELECT o.id,o.profile_id,o.payload FROM atlas_observations o
    JOIN atlas_grants g ON g.id=o.grant_id AND g.user_id=o.user_id
    WHERE o.user_id=? AND o.kind='track.path' AND o.observed_at>=? ${options.profileId ? "AND o.profile_id=?" : ""} AND ${GRANT_OK(["own_track"])}
    ORDER BY o.observed_at DESC LIMIT ${MY_TRAIL_MAX_PATHS + 1}`)
    .bind(...[userId, options.since, ...(options.profileId ? [options.profileId] : [])]).all();
  const truncated = rows.results.length > MY_TRAIL_MAX_PATHS;
  const paths = rows.results.slice(0, MY_TRAIL_MAX_PATHS).map(toPath).filter((p): p is TrackPath => p !== null);
  const characters = await db.prepare("SELECT id,name,realm,class_id,level FROM atlas_profiles WHERE user_id=? ORDER BY last_seen DESC").bind(userId).all();
  return {
    paths, truncated,
    live: [...await livePositions(db,characters.results.map(c=>String(c.id)),["own_track"])].map(([profileId,position])=>({profileId,...position})),
    characters: characters.results.map((c) => ({ id: String(c.id), name: typeof c.name === "string" ? c.name : null, realm: typeof c.realm === "string" ? c.realm : null, classId: typeof c.class_id === "number" ? c.class_id : null, level: typeof c.level === "number" ? c.level : null })),
  };
}

export async function eraseMyTrail(db: Db, userId: string, profileId?: string) {
  const result = await db.prepare(`DELETE FROM atlas_observations WHERE user_id=? AND kind='track.path' ${profileId ? "AND profile_id=?" : ""}`)
    .bind(...[userId, ...(profileId ? [profileId] : [])]).run();
  return { erased: Number(result.meta.changes ?? 0) };
}

/** Routes older than the retention window are dropped whenever new ones arrive. */
export async function pruneTracks(db: Db, userId: string) {
  await db.prepare("DELETE FROM atlas_observations WHERE user_id=? AND kind='track.path' AND observed_at<?").bind(userId, now() - TRACK_RETENTION_SECONDS).run();
}

export interface GuildMember {
  name: string; rankIndex: number; level: number | null; classId: number | null;
  /** Has an Evertally account that confirmed the guild. */
  onMap: boolean; share: ShareMode | null; profileId: string | null;
  position: { mapId: number; x: number; y: number; at: number } | null;
}
export interface GuildView {
  id: string; name: string; realm: string; ownerName: string | null; rosterAt: number | null; rosterSize: number;
  mine: { profileId: string; name: string; status: string; share: ShareMode; eligible: boolean }[];
  /** Present only for a viewer who confirmed this guild. */
  members: GuildMember[] | null;
}

export async function guildOverview(db: Db, userId: string): Promise<{ guilds: GuildView[] }> {
  const mine = await db.prepare(`SELECT m.guild_id,m.profile_id,m.name,m.status,m.share,g.name AS guild_name,g.realm,g.owner_user_id,g.owner_name,g.roster,g.roster_at
    FROM et_guild_members m JOIN et_guilds g ON g.id=m.guild_id WHERE m.user_id=? AND m.status<>'left' ORDER BY g.name`).bind(userId).all();
  const grouped = new Map<string, Row[]>();
  for (const row of mine.results) grouped.set(String(row.guild_id), [...(grouped.get(String(row.guild_id)) ?? []), row]);
  const guilds: GuildView[] = [];
  for (const [id, rows] of grouped) {
    const head = rows[0];
    const roster = decode<RosterEntry[]>(head.roster, []);
    const own = rows.map((row) => ({ profileId: String(row.profile_id), name: String(row.name), status: String(row.status), share: String(row.share) as ShareMode, eligible: eligibleFor(head as { owner_user_id: unknown; roster: unknown }, userId, String(row.name)) }));
    const confirmed = own.some((row) => row.status === "active" && row.eligible);
    guilds.push({ id, name: String(head.guild_name), realm: String(head.realm), ownerName: typeof head.owner_name === "string" ? head.owner_name : null, rosterAt: typeof head.roster_at === "number" ? head.roster_at : null, rosterSize: roster.length, mine: own, members: confirmed ? await guildMembers(db, id, roster, head as { owner_user_id: unknown; roster: unknown }) : null });
  }
  return { guilds };
}

async function guildMembers(db: Db, id: string, roster: RosterEntry[], guild: { owner_user_id: unknown; roster: unknown }): Promise<GuildMember[]> {
  const accounts = await db.prepare("SELECT profile_id,user_id,name,share FROM et_guild_members WHERE guild_id=? AND status='active'").bind(id).all();
  const active = accounts.results.filter((row) => eligibleFor(guild, String(row.user_id), String(row.name)));
  const shared = active.filter((row) => row.share !== "off");
  const positions = await latestPositions(db,shared.map(row=>String(row.profile_id)),["own_track","guild_share"]);
  const byName = new Map(active.map((row) => [baseName(String(row.name)), row]));
  const members = roster.map<GuildMember>(([name, rankIndex, level, classId]) => {
    const account = byName.get(baseName(String(name)));
    const profileId = account ? String(account.profile_id) : null;
    const share = account ? String(account.share) as ShareMode : null;
    return { name: String(name).split("-")[0], rankIndex, level, classId, onMap: Boolean(account), share, profileId, position: profileId && share && share !== "off" ? positions.get(profileId) ?? null : null };
  });
  // The master and members whose name the roster spells differently still belong in the list.
  for (const row of active) if (!members.some((m) => m.profileId === String(row.profile_id))) {
    members.push({ name: String(row.name), rankIndex: 99, level: null, classId: null, onMap: true, share: String(row.share) as ShareMode, profileId: String(row.profile_id), position: row.share !== "off" ? positions.get(String(row.profile_id)) ?? null : null });
  }
  return members.sort((a, b) => Number(b.onMap) - Number(a.onMap) || a.rankIndex - b.rankIndex || a.name.localeCompare(b.name));
}

export async function setMembership(db: Db, userId: string, id: string, profileId: string, action: "join" | "share" | "leave", share?: ShareMode) {
  const row = await db.prepare(`SELECT m.*,g.owner_user_id,g.roster FROM et_guild_members m JOIN et_guilds g ON g.id=m.guild_id
    WHERE m.guild_id=? AND m.profile_id=? AND m.user_id=?`).bind(id, profileId, userId).first();
  if (!row || row.status === "left") throw new ApiError("not_found", "This guild is not linked to your character.", 404);
  if (action === "leave") {
    await db.prepare("UPDATE et_guild_members SET status='declined',share='off' WHERE guild_id=? AND profile_id=? AND user_id=?").bind(id, profileId, userId).run();
    return { status: "declined", share: "off" as ShareMode };
  }
  if (action === "join") {
    if (!eligibleFor(row as { owner_user_id: unknown; roster: unknown }, userId, String(row.name))) throw new ApiError("guild_not_verified", "A guild master has not imported a roster that includes this character yet.", 409);
    const mode: ShareMode = share === "trail" ? "trail" : "last";
    await db.prepare("UPDATE et_guild_members SET status='active',share=? WHERE guild_id=? AND profile_id=? AND user_id=?").bind(mode, id, profileId, userId).run();
    return { status: "active", share: mode };
  }
  if (row.status !== "active") throw new ApiError("guild_not_joined", "Join the guild on the map first.", 409);
  const mode: ShareMode = share ?? "last";
  await db.prepare("UPDATE et_guild_members SET share=? WHERE guild_id=? AND profile_id=? AND user_id=?").bind(mode, id, profileId, userId).run();
  return { status: "active", share: mode };
}

/** The route of one guild member, only if the viewer is confirmed in the same guild and the member chose to share routes. */
export async function guildTrail(db: Db, userId: string, id: string, profileId: string, hours: number) {
  const guild = await db.prepare("SELECT owner_user_id,roster FROM et_guilds WHERE id=?").bind(id).first();
  if (!guild) throw new ApiError("not_found", "Guild not found.", 404);
  const viewers = await db.prepare("SELECT name FROM et_guild_members WHERE guild_id=? AND user_id=? AND status='active'").bind(id, userId).all();
  if (!viewers.results.some((row) => eligibleFor(guild as { owner_user_id: unknown; roster: unknown }, userId, String(row.name)))) throw new ApiError("forbidden", "Confirm this guild on the map first.", 403);
  const target = await db.prepare("SELECT user_id,name,share FROM et_guild_members WHERE guild_id=? AND profile_id=? AND status='active'").bind(id, profileId).first();
  if (!target || target.share !== "trail" || !eligibleFor(guild as { owner_user_id: unknown; roster: unknown }, String(target.user_id), String(target.name))) throw new ApiError("forbidden", "This member does not share their route with the guild.", 403);
  const since = now() - Math.min(Math.max(1, Math.floor(hours)), GUILD_TRAIL_MAX_HOURS) * 3600;
  const rows = await db.prepare(`SELECT o.id,o.profile_id,o.payload FROM atlas_observations o JOIN atlas_grants g ON g.id=o.grant_id AND g.user_id=o.user_id
    WHERE o.profile_id=? AND o.kind='track.path' AND o.observed_at>=? AND ${GRANT_OK(["own_track", "guild_share"])} ORDER BY o.observed_at DESC LIMIT ${MY_TRAIL_MAX_PATHS}`).bind(profileId, since).all();
  return { name: String(target.name), paths: rows.results.map(toPath).filter((p): p is TrackPath => p !== null) };
}

/** The newest route point of each character, only from routes whose grant still carries every scope in `needs`. */
export async function latestPositions(db: Db, profileIds: string[], needs: string[]): Promise<Map<string, { mapId: number; x: number; y: number; at: number }>> {
  const out = new Map<string, { mapId: number; x: number; y: number; at: number }>();
  if (!profileIds.length) return out;
  const rows = await db.prepare(`SELECT p.value AS profile_id,o.payload FROM json_each(?) p
    JOIN atlas_observations o ON o.id=(SELECT o2.id FROM atlas_observations o2 JOIN atlas_grants g ON g.id=o2.grant_id AND g.user_id=o2.user_id
      WHERE o2.profile_id=p.value AND o2.kind='track.path' AND ${GRANT_OK(needs)} ORDER BY o2.observed_at DESC LIMIT 1)`).bind(JSON.stringify(profileIds)).all();
  for (const row of rows.results) {
    const path = toPath({ id: "", payload: row.payload, profile_id: row.profile_id });
    if (!path) continue;
    const last = path.points[path.points.length - 1];
    out.set(String(row.profile_id), { mapId: path.mapId, x: last[1], y: last[2], at: path.startedAt + last[0] });
  }
  for(const [id,position] of await livePositions(db,profileIds,needs))out.set(id,position);
  return out;
}

/** Called when an account deletes its data: it stops sharing, releases any guild roster, leaves or closes groups, and drops its meets. */
export function releaseStatements(db: Db, userId: string): Stmt[] {
  const t = now();
  return [
    db.prepare("DELETE FROM et_game_connections WHERE user_id=?").bind(userId),
    db.prepare("DELETE FROM et_live_positions WHERE user_id=?").bind(userId),
    db.prepare("DELETE FROM et_guild_members WHERE user_id=?").bind(userId),
    db.prepare("UPDATE et_guilds SET owner_user_id=NULL,owner_name=NULL,roster='[]',roster_at=NULL WHERE owner_user_id=?").bind(userId),
    db.prepare("DELETE FROM et_circle_members WHERE user_id=?").bind(userId),
    db.prepare("UPDATE et_circles SET closed_at=? WHERE owner_user_id=? AND closed_at IS NULL").bind(t, userId),
    db.prepare("DELETE FROM et_meet_rsvps WHERE meet_id IN (SELECT id FROM et_meets WHERE user_id=?) OR user_id=?").bind(userId, userId),
    db.prepare("DELETE FROM et_meet_access WHERE meet_id IN (SELECT id FROM et_meets WHERE user_id=?) OR user_id=?").bind(userId, userId),
    db.prepare("DELETE FROM et_meets WHERE user_id=?").bind(userId),
    db.prepare("DELETE FROM et_sharing WHERE user_id=?").bind(userId),
    db.prepare("DELETE FROM et_friends WHERE user_a=? OR user_b=?").bind(userId, userId),
  ];
}

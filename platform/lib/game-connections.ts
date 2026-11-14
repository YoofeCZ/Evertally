// Current in-game friend/group claims, bound to the character that supplied its own live point.
// A unilateral name claim never grants access: both current clients must name one another.
import { ApiError } from "./policy";
import { now, type Db, type Stmt } from "./people";
import type { VisiblePlayer } from "./sharing";

export type GameConnection = { name: string; realm: string; kind: "friend" | "group" };
export type GameToken = { key: number; kind: "friend" | "group" };
export type GameRoster = { key: number; entries?: GameConnection[]; tokens?: GameToken[] };
export const MAX_GAME_CONNECTIONS = 100;
export const connectionName = (name: string) => name.replace(/[A-Z]/g, c => c.toLowerCase());
export const connectionRealm = (realm: string) => connectionName(realm.replace(/[\t\n\v\f\r ]/g, ""));
const line = (e: GameConnection) => `${e.kind}\0${connectionName(e.name)}\0${connectionRealm(e.realm)}\n`;
function adler(bytes: Uint8Array): number { let a=1,b=0; for(const value of bytes){a=(a+value)%65521;b=(b+a)%65521;}return b*65536+a; }
export const identityToken = (name: string, realm: string): number => adler(new TextEncoder().encode(`${connectionName(name)}\0${connectionRealm(realm)}`));
export const tokenRosterKey = (tokens: GameToken[]): number => adler(new TextEncoder().encode([...new Set(tokens.map(token=>`${token.kind}\0${token.key}\n`))].sort().join("")));
export function rosterKey(entries: GameConnection[]): number {
  let a = 1, b = 0;
  const encoder = new TextEncoder();
  const lines = [...new Set(entries.map(line))].map(value => encoder.encode(value));
  lines.sort((a, b) => { for (let i = 0; i < Math.min(a.length, b.length); i++) if (a[i] !== b[i]) return a[i] - b[i]; return a.length - b.length; });
  for (const encoded of lines) for (const value of encoded) { a = (a + value) % 65521; b = (b + a) % 65521; }
  return b * 65536 + a;
}

export function gameConnectionStatements(db: Db, input: {
  profileId: string; userId: string; grantId: string; deviceId: string; observedAt: number; expiresAt: number;
  game: { product: string; region: string }; character: { name?: string | null; realm?: string | null }; roster?: GameRoster;
}): Stmt[] {
  const { roster } = input;
  const u32=(key:number)=>Number.isInteger(key)&&key>=0&&key<=0xffffffff;
  if (roster && (!u32(roster.key) || (roster.entries===undefined)===(roster.tokens===undefined)
    || (roster.entries!==undefined && (!Array.isArray(roster.entries) || roster.entries.length > MAX_GAME_CONNECTIONS || roster.entries.some(e => !e || !["friend", "group"].includes(e.kind)
      || typeof e.name !== "string" || !e.name.length || new TextEncoder().encode(e.name).length > 120 || /[\x00-\x1f]/.test(e.name)
      || typeof e.realm !== "string" || !connectionRealm(e.realm).length || new TextEncoder().encode(e.realm).length > 120 || /[\x00-\x1f]/.test(e.realm))
      || (roster.entries.length > 0 && roster.key !== rosterKey(roster.entries))))
    || (roster.tokens!==undefined && (!Array.isArray(roster.tokens) || roster.tokens.length>MAX_GAME_CONNECTIONS
      || roster.tokens.some(t=>!t||!u32(t.key)||!["friend","group"].includes(t.kind))
      || (roster.tokens.length>0 && roster.key!==tokenRosterKey(roster.tokens)))))) {
    throw new ApiError("invalid_roster", "Invalid in-game connections snapshot.", 400);
  }
  const self = input.character.name && input.character.realm ? identityToken(input.character.name,input.character.realm) : 0;
  const tokens = self ? roster?.tokens ?? roster?.entries?.map(e=>({key:identityToken(e.name,e.realm),kind:e.kind})) ?? [] : [];
  // An empty row is a timestamped tombstone: v2 clients and changed rosters immediately revoke old claims.
  return [db.prepare(`INSERT INTO et_game_connections(source_profile_id,user_id,grant_id,device_id,observed_at,expires_at,roster_key,product,region,self_key,entries)
    SELECT ?,?,?,?,?,?,?,?,?,?,? WHERE EXISTS(SELECT 1 FROM atlas_profiles WHERE id=? AND user_id=?)
      AND EXISTS(SELECT 1 FROM atlas_grants WHERE id=? AND user_id=? AND revoked_at IS NULL)
      AND EXISTS(SELECT 1 FROM et_devices WHERE id=? AND user_id=? AND revoked_at IS NULL)
      AND EXISTS(SELECT 1 FROM et_live_positions WHERE profile_id=? AND user_id=? AND grant_id=? AND device_id=? AND observed_at<=?)
    ON CONFLICT(source_profile_id) DO UPDATE SET grant_id=excluded.grant_id,device_id=excluded.device_id,
      observed_at=excluded.observed_at,expires_at=excluded.expires_at,roster_key=excluded.roster_key,
      product=excluded.product,region=excluded.region,self_key=excluded.self_key,entries=excluded.entries
    WHERE excluded.observed_at>=et_game_connections.observed_at`)
    .bind(input.profileId, input.userId, input.grantId, input.deviceId, input.observedAt, Math.min(input.expiresAt, input.observedAt + 30),
      roster?.key ?? 0, input.game.product, input.game.region, self, JSON.stringify(tokens), input.profileId, input.userId,
      input.grantId, input.userId, input.deviceId, input.userId, input.profileId, input.userId, input.grantId, input.deviceId, input.observedAt)];
}

const realmSql = (value: string) => `lower(replace(replace(replace(replace(replace(replace(${value},' ',''),char(9),''),char(10),''),char(11),''),char(12),''),char(13),''))`;
const allowed = (grant: string, device: string) => `${grant}.revoked_at IS NULL AND ${device}.revoked_at IS NULL AND ${["own_track", "own_character"].map(scope =>
  `EXISTS(SELECT 1 FROM json_each(${grant}.scopes) WHERE value='${scope}') AND EXISTS(SELECT 1 FROM json_each(${device}.scopes) WHERE value='${scope}')`).join(" AND ")}`;
const unambiguous = (subject: string, profile: string) => `NOT EXISTS(
  SELECT 1 FROM et_game_connections collision
    JOIN atlas_profiles cp ON cp.id=collision.source_profile_id AND cp.user_id=collision.user_id
    JOIN atlas_grants cg ON cg.id=collision.grant_id AND cg.user_id=collision.user_id
    JOIN et_devices cd ON cd.id=collision.device_id AND cd.user_id=collision.user_id
    JOIN et_live_positions cl ON cl.profile_id=collision.source_profile_id AND cl.user_id=collision.user_id
      AND cl.grant_id=collision.grant_id AND cl.device_id=collision.device_id
  WHERE collision.self_key=${subject}.self_key AND collision.product=${subject}.product AND collision.region=${subject}.region
    AND collision.expires_at>? AND cl.expires_at>? AND collision.observed_at>? AND cl.observed_at>?
    AND ${allowed("cg", "cd")}
    AND (lower(cp.name)<>lower(${profile}.name) OR ${realmSql("cp.realm")}<>${realmSql(`${profile}.realm`)}))`;

export async function gameVisiblePlayers(db: Db, viewerId: string, at = now()): Promise<VisiblePlayer[]> {
  const rows = await db.prepare(`SELECT DISTINCT target.source_profile_id AS profile_id,p.name,p.class_id,p.level,l.map_id,l.x,l.y,l.observed_at,json_extract(m.value,'$.kind') AS kind
    FROM et_game_connections mine
    JOIN atlas_profiles own ON own.id=mine.source_profile_id AND own.user_id=mine.user_id
    JOIN atlas_grants og ON og.id=mine.grant_id AND og.user_id=mine.user_id
    JOIN et_devices od ON od.id=mine.device_id AND od.user_id=mine.user_id
    JOIN et_live_positions ol ON ol.profile_id=mine.source_profile_id AND ol.user_id=mine.user_id AND ol.grant_id=mine.grant_id AND ol.device_id=mine.device_id
    JOIN json_each(mine.entries) m
    JOIN et_game_connections target ON target.user_id<>mine.user_id AND target.product=mine.product AND target.region=mine.region
      AND target.self_key=json_extract(m.value,'$.key')
    JOIN atlas_profiles p ON p.id=target.source_profile_id AND p.user_id=target.user_id
    JOIN json_each(target.entries) t ON json_extract(t.value,'$.kind')=json_extract(m.value,'$.kind')
      AND json_extract(t.value,'$.key')=mine.self_key
    JOIN atlas_grants tg ON tg.id=target.grant_id AND tg.user_id=target.user_id
    JOIN et_devices td ON td.id=target.device_id AND td.user_id=target.user_id
    JOIN et_live_positions l ON l.profile_id=target.source_profile_id AND l.user_id=target.user_id AND l.grant_id=target.grant_id AND l.device_id=target.device_id
    LEFT JOIN et_sharing os ON os.user_id=mine.user_id
    LEFT JOIN et_sharing ts ON ts.user_id=target.user_id
    WHERE mine.user_id=? AND mine.expires_at>? AND target.expires_at>? AND ol.expires_at>? AND l.expires_at>?
      AND mine.observed_at>? AND target.observed_at>? AND ol.observed_at>? AND l.observed_at>?
      AND mine.self_key<>0 AND target.self_key<>0
      AND ${allowed("og", "od")} AND ${allowed("tg", "td")}
      AND ${unambiguous("mine", "own")} AND ${unambiguous("target", "p")}
      AND (json_extract(m.value,'$.kind')='group' OR (json_extract(m.value,'$.kind')='friend' AND os.friends=1 AND ts.friends=1))
    ORDER BY l.observed_at DESC LIMIT 300`).bind(viewerId, at, at, at, at, at - 30, at - 30, at - 30, at - 30,
      at,at,at-30,at-30,at,at,at-30,at-30).all<{
      profile_id: string; name: string | null; class_id: number | null; level: number | null; map_id: number; x: number; y: number; observed_at: number; kind: string;
    }>();
  const unique = new Map<string, VisiblePlayer>();
  for (const row of rows.results) if (!unique.has(row.profile_id)) unique.set(row.profile_id, {
    profileId: row.profile_id, name: row.name, classId: row.class_id, level: row.level,
    mapId: row.map_id, x: row.x, y: row.y, at: row.observed_at, audience: row.kind === "group" ? "group" : "friends",
  });
  return [...unique.values()];
}

export async function gameFriends(db: Db, viewerId: string, at = now()): Promise<VisiblePlayer[]> {
  return (await gameVisiblePlayers(db, viewerId, at)).filter(player => player.audience === "friends");
}

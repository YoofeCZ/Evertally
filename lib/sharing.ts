// Who may see a character's LIVE position, beyond the guild and groups: mutual friends, every signed-in visitor, or anyone at
// all, including people who are not signed in. Each of the three is its own opt-in per account and off until the owner turns
// it on. Only the live position is ever shown this way (the last point the bridge sent, never a route), and only while the
// route's consent and the device still carry own_track and own_character, exactly as for guilds and groups.
//
// Friends are mutual and explicit: one account asks by Discord name, the other accepts, either can end it. Asking never tells
// the asker whether the name exists.
import { ApiError } from "./policy";
import { now, type Db } from "./people";
import { gameVisiblePlayers } from "./game-connections";

export interface Sharing { friends: boolean; signedIn: boolean; public: boolean }
export const SHARING_KEYS = ["friends", "signedIn", "public"] as const;
export const MAX_FRIENDS = 100;
export const MAX_OUTGOING = 30;
/** A position older than this is not shown to these audiences, whatever the row says. */
export const SHOWN_SECONDS = 30;

export async function getSharing(db: Db, userId: string): Promise<Sharing> {
  const row = await db.prepare("SELECT friends,signed_in,public FROM et_sharing WHERE user_id=?").bind(userId).first<{ friends: number; signed_in: number; public: number }>();
  return { friends: Boolean(row?.friends), signedIn: Boolean(row?.signed_in), public: Boolean(row?.public) };
}

/** Changes only the choices that were given. Turning a choice off takes effect at once: nothing is cached here. */
export async function setSharing(db: Db, userId: string, input: Partial<Sharing>): Promise<Sharing> {
  const next = { ...(await getSharing(db, userId)) };
  for (const key of SHARING_KEYS) if (typeof input[key] === "boolean") next[key] = input[key];
  await db.prepare(`INSERT INTO et_sharing(user_id,friends,signed_in,public,updated_at) VALUES(?,?,?,?,?)
    ON CONFLICT(user_id) DO UPDATE SET friends=excluded.friends,signed_in=excluded.signed_in,public=excluded.public,updated_at=excluded.updated_at`)
    .bind(userId, next.friends ? 1 : 0, next.signedIn ? 1 : 0, next.public ? 1 : 0, now()).run();
  return next;
}

export const pair = (a: string, b: string): [string, string] => (a < b ? [a, b] : [b, a]);
export const cleanName = (name: string) => name.trim().replace(/^@/, "").toLowerCase();

export interface FriendEntry { userId: string; name: string; since: number }
export interface SharedFriend extends FriendEntry { sharing: boolean; live: boolean; position: VisiblePlayer | null }
export interface Friends { friends: SharedFriend[]; incoming: FriendEntry[]; outgoing: FriendEntry[] }

export async function listFriends(db: Db, userId: string): Promise<Friends> {
  const rows = await db.prepare(`SELECT f.user_a,f.user_b,f.requested_by,f.status,f.created_at,f.answered_at,COALESCE(u.display_name,u.username) AS name,COALESCE(s.friends,0) AS sharing
    FROM et_friends f JOIN et_users u ON u.id=CASE WHEN f.user_a=? THEN f.user_b ELSE f.user_a END
    LEFT JOIN et_sharing s ON s.user_id=u.id
    WHERE f.user_a=? OR f.user_b=? ORDER BY f.created_at DESC`).bind(userId, userId, userId).all<{ user_a: string; user_b: string; requested_by: string; status: string; created_at: number; answered_at: number | null; name: string; sharing: number }>();
  const accepted = rows.results.filter(row => row.status === "accepted" && row.sharing)
    .map(row => row.user_a === userId ? row.user_b : row.user_a);
  // Reuse the map's authorization, restricted to these friends before its result limit.
  // A public position alone does not count as sharing with friends in this list.
  const positions = new Map<string, VisiblePlayer>();
  if (accepted.length) for (const row of await visiblePlayerRows(db, userId, now(), accepted)) {
    if (row.s_friends && row.is_friend && !positions.has(row.user_id)) positions.set(row.user_id, visiblePlayer(row, userId));
  }
  const out: Friends = { friends: [], incoming: [], outgoing: [] };
  for (const row of rows.results) {
    const other = row.user_a === userId ? row.user_b : row.user_a;
    const entry = { userId: other, name: row.name, since: Number(row.answered_at ?? row.created_at) };
    if (row.status === "accepted") {
      const position = row.sharing ? positions.get(other) ?? null : null;
      out.friends.push({ ...entry, sharing: Boolean(row.sharing), live: position !== null, position });
    }
    else if (row.requested_by === userId) out.outgoing.push(entry);
    else out.incoming.push(entry);
  }
  return out;
}

/**
 * Asks the account with this Discord name to be friends. The answer is the same whether or not the name exists. If that account
 * already asked this one, the two requests meet and the friendship is made.
 */
export async function requestFriend(db: Db, userId: string, rawName: string): Promise<{ status: "sent" | "accepted" }> {
  const name = cleanName(rawName);
  if (name.length < 2 || name.length > 64) throw new ApiError("invalid_name", "Type the Discord name of the person, 2 to 64 characters.");
  const target = await db.prepare("SELECT id FROM et_users WHERE lower(username)=?").bind(name).first<{ id: string }>();
  if (!target) return { status: "sent" };
  if (target.id === userId) throw new ApiError("invalid_name", "That is you.");
  const [a, b] = pair(userId, target.id);
  const existing = await db.prepare("SELECT requested_by,status FROM et_friends WHERE user_a=? AND user_b=?").bind(a, b).first<{ requested_by: string; status: string }>();
  if (existing?.status === "accepted") return { status: "accepted" };
  if (existing) {
    if (existing.requested_by === userId) return { status: "sent" };
    await db.prepare("UPDATE et_friends SET status='accepted',answered_at=? WHERE user_a=? AND user_b=?").bind(now(), a, b).run();
    return { status: "accepted" };
  }
  const counts = await db.prepare(`SELECT
    SUM(CASE WHEN status='accepted' THEN 1 ELSE 0 END) AS friends,
    SUM(CASE WHEN status='pending' AND requested_by=? THEN 1 ELSE 0 END) AS outgoing
    FROM et_friends WHERE user_a=? OR user_b=?`).bind(userId, userId, userId).first<{ friends: number | null; outgoing: number | null }>();
  if (Number(counts?.friends ?? 0) >= MAX_FRIENDS) throw new ApiError("too_many_friends", `You can have up to ${MAX_FRIENDS} friends.`, 409);
  if (Number(counts?.outgoing ?? 0) >= MAX_OUTGOING) throw new ApiError("too_many_requests", `You can have up to ${MAX_OUTGOING} open requests. Wait for answers or cancel some.`, 409);
  await db.prepare("INSERT INTO et_friends(user_a,user_b,requested_by,status,created_at) VALUES(?,?,?,'pending',?)").bind(a, b, userId, now()).run();
  return { status: "sent" };
}

/** accept: answer a request made to you. decline: refuse one made to you or cancel one you made. remove: end a friendship. */
export async function answerFriend(db: Db, userId: string, otherId: string, action: "accept" | "decline" | "remove"): Promise<{ done: boolean }> {
  const [a, b] = pair(userId, otherId);
  const row = await db.prepare("SELECT requested_by,status FROM et_friends WHERE user_a=? AND user_b=?").bind(a, b).first<{ requested_by: string; status: string }>();
  if (!row) throw new ApiError("not_found", "There is no such request or friend.", 404);
  if (action === "accept") {
    if (row.status !== "pending" || row.requested_by === userId) throw new ApiError("not_found", "There is no request for you to accept.", 404);
    await db.prepare("UPDATE et_friends SET status='accepted',answered_at=? WHERE user_a=? AND user_b=?").bind(now(), a, b).run();
    return { done: true };
  }
  if (action === "decline" && row.status !== "pending") throw new ApiError("not_found", "There is no open request.", 404);
  if (action === "remove" && row.status !== "accepted") throw new ApiError("not_found", "You are not friends.", 404);
  await db.prepare("DELETE FROM et_friends WHERE user_a=? AND user_b=?").bind(a, b).run();
  return { done: true };
}

export type Audience = "friends" | "group" | "signed_in" | "public";
export interface VisiblePlayer { profileId: string; name: string | null; classId: number | null; level: number | null; mapId: number; x: number; y: number; at: number; audience: Audience }
type VisibleRow = {
  profile_id: string; user_id: string; map_id: number; x: number; y: number; observed_at: number; name: string | null; class_id: number | null; level: number | null;
  s_friends: number; s_signed: number; s_public: number; is_friend: number;
};

/**
 * The live positions this viewer may see because their owners chose to show them to friends, to signed-in visitors or to
 * everyone. `viewerId` null is a visitor who is not signed in: only what is shown to everyone. Never the viewer's own characters
 * (those come from their own route), never a position whose consent, device or age no longer allows it.
 */
export async function visiblePlayers(db: Db, viewerId: string | null, at = now()): Promise<VisiblePlayer[]> {
  const explicit = (await visiblePlayerRows(db, viewerId, at)).map(row => visiblePlayer(row, viewerId));
  if (!viewerId) return explicit;
  const game = await gameVisiblePlayers(db, viewerId, at);
  return [...new Map([...explicit, ...game].map(player => [player.profileId, player])).values()];
}

async function visiblePlayerRows(db: Db, viewerId: string | null, at: number, owners?: string[]): Promise<VisibleRow[]> {
  const viewer = viewerId ?? "";
  const rows = await db.prepare(`SELECT l.profile_id,l.user_id,l.map_id,l.x,l.y,l.observed_at,p.name,p.class_id,p.level,s.friends AS s_friends,s.signed_in AS s_signed,s.public AS s_public,
      EXISTS(SELECT 1 FROM et_friends f WHERE f.status='accepted' AND f.user_a=MIN(l.user_id,?) AND f.user_b=MAX(l.user_id,?)) AS is_friend
    FROM et_live_positions l
    JOIN et_sharing s ON s.user_id=l.user_id
    JOIN atlas_profiles p ON p.id=l.profile_id AND p.user_id=l.user_id
    JOIN atlas_grants g ON g.id=l.grant_id AND g.user_id=l.user_id
    JOIN et_devices d ON d.id=l.device_id AND d.user_id=l.user_id
    WHERE l.expires_at>? AND l.observed_at>? AND g.revoked_at IS NULL AND d.revoked_at IS NULL AND l.user_id<>?
      AND EXISTS(SELECT 1 FROM json_each(g.scopes) WHERE value='own_track') AND EXISTS(SELECT 1 FROM json_each(g.scopes) WHERE value='own_character')
      AND EXISTS(SELECT 1 FROM json_each(d.scopes) WHERE value='own_track') AND EXISTS(SELECT 1 FROM json_each(d.scopes) WHERE value='own_character')
      AND (s.public=1 OR (?<>'' AND (s.signed_in=1 OR (s.friends=1 AND is_friend=1))))
      ${owners ? "AND l.user_id IN (SELECT value FROM json_each(?))" : ""}
    ORDER BY l.observed_at DESC LIMIT 300`).bind(viewer, viewer, at, at - SHOWN_SECONDS, viewer, viewer, ...(owners ? [JSON.stringify(owners)] : [])).all<VisibleRow>();
  return rows.results;
}

function visiblePlayer(row: VisibleRow, viewerId: string | null): VisiblePlayer {
  return {
    profileId: String(row.profile_id), name: row.name ?? null, classId: row.class_id == null ? null : Number(row.class_id), level: row.level == null ? null : Number(row.level),
    mapId: Number(row.map_id), x: Number(row.x), y: Number(row.y), at: Number(row.observed_at),
    // the narrowest reason first: a friend is shown as a friend even when the position is also public
    audience: viewerId && row.s_friends && row.is_friend ? "friends" : viewerId && row.s_signed ? "signed_in" : "public",
  };
}

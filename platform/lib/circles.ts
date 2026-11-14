// Groups ("circles"): a party, a raid, a few friends. Unlike a guild there is no roster to check, so trust is mutual and
// explicit: a group is created on the website, others join with its invite code, and every member chooses what to share
// (nothing, last position, last position and route). Nobody sees anything of a member who chose "nothing"; leaving, being
// removed by the owner or revoking the consent ends it at once. A position only counts while the route's grant still
// carries own_track and own_character, exactly as for guilds.
import { ApiError } from "./policy";
import { GRANT_OK, GUILD_TRAIL_MAX_HOURS, MY_TRAIL_MAX_PATHS, SHARE_MODES, latestPositions, now, toPath, type Db, type ShareMode, type TrackPath } from "./people";

export const CIRCLE_MAX_MEMBERS = 40;
export const CIRCLE_MAX_OWNED = 5;
export const CIRCLE_MAX_JOINED = 12;
const ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
const CODE_LENGTH = 10;

/** An unambiguous bearer code: 10 characters of a 31-letter alphabet. */
export function newInviteCode(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(CODE_LENGTH));
  return Array.from(bytes, b => ALPHABET[b % ALPHABET.length]).join("");
}
export const normalizeCode = (code: string) => code.toUpperCase().replace(/[^A-Z0-9]/g, "");
export const formatCode = (code: string) => `${code.slice(0, 5)}-${code.slice(5)}`;

export interface CircleMember { profileId: string; name: string; classId: number | null; level: number | null; share: ShareMode; isMe: boolean; isOwner: boolean; position: { mapId: number; x: number; y: number; at: number } | null }
export interface CircleView { id: string; name: string; isOwner: boolean; inviteCode: string | null; mine: { profileId: string; name: string; share: ShareMode }; members: CircleMember[] }

async function ownProfile(db: Db, userId: string, profileId: string) {
  const row = await db.prepare("SELECT id,name FROM atlas_profiles WHERE id=? AND user_id=?").bind(profileId, userId).first<{ id: string; name: string | null }>();
  if (!row) throw new ApiError("not_found", "Choose one of your own characters. They appear after the addon uploaded the character scope.", 404);
  return { id: String(row.id), name: row.name ?? "Player" };
}
const mode = (share: unknown): ShareMode => (SHARE_MODES as readonly string[]).includes(String(share)) ? String(share) as ShareMode : "last";

export async function createCircle(db: Db, userId: string, input: { name: string; profileId: string; share?: ShareMode }) {
  const name = input.name.trim();
  if (!name || name.length > 40) throw new ApiError("invalid_name", "A group name has 1 to 40 characters.");
  const profile = await ownProfile(db, userId, input.profileId);
  const owned = await db.prepare("SELECT COUNT(*) AS n FROM et_circles WHERE owner_user_id=? AND closed_at IS NULL").bind(userId).first<{ n: number }>();
  if (Number(owned?.n ?? 0) >= CIRCLE_MAX_OWNED) throw new ApiError("too_many_circles", `You can own up to ${CIRCLE_MAX_OWNED} groups. Close one first.`, 409);
  const id = crypto.randomUUID(), t = now(), share = mode(input.share ?? "last");
  for (let attempt = 0; attempt < 3; attempt++) {
    const code = newInviteCode();
    const taken = await db.prepare("SELECT 1 AS x FROM et_circles WHERE invite_code=?").bind(code).first();
    if (taken) continue;
    await db.batch([
      db.prepare("INSERT INTO et_circles(id,name,owner_user_id,invite_code,created_at) VALUES(?,?,?,?,?)").bind(id, name, userId, code, t),
      db.prepare("INSERT INTO et_circle_members(circle_id,user_id,profile_id,share,joined_at) VALUES(?,?,?,?,?)").bind(id, userId, profile.id, share, t),
    ]);
    return { id, name, code };
  }
  throw new ApiError("service_unavailable", "Could not create the group, try again.", 503);
}

export async function joinCircle(db: Db, userId: string, rawCode: string, profileId: string, share?: ShareMode) {
  const code = normalizeCode(rawCode);
  const circle = code.length === CODE_LENGTH ? await db.prepare("SELECT id,name FROM et_circles WHERE invite_code=? AND closed_at IS NULL").bind(code).first<{ id: string; name: string }>() : null;
  if (!circle) throw new ApiError("invalid_code", "This invite code is not valid, or the group was closed.", 404);
  const profile = await ownProfile(db, userId, profileId);
  const existing = await db.prepare("SELECT 1 AS x FROM et_circle_members WHERE circle_id=? AND user_id=?").bind(circle.id, userId).first();
  if (!existing) {
    const members = await db.prepare("SELECT COUNT(*) AS n FROM et_circle_members WHERE circle_id=?").bind(circle.id).first<{ n: number }>();
    if (Number(members?.n ?? 0) >= CIRCLE_MAX_MEMBERS) throw new ApiError("circle_full", `A group has at most ${CIRCLE_MAX_MEMBERS} members.`, 409);
    const joined = await db.prepare("SELECT COUNT(*) AS n FROM et_circle_members m JOIN et_circles c ON c.id=m.circle_id WHERE m.user_id=? AND c.closed_at IS NULL").bind(userId).first<{ n: number }>();
    if (Number(joined?.n ?? 0) >= CIRCLE_MAX_JOINED) throw new ApiError("too_many_circles", `You can be in up to ${CIRCLE_MAX_JOINED} groups. Leave one first.`, 409);
  }
  await db.prepare(`INSERT INTO et_circle_members(circle_id,user_id,profile_id,share,joined_at) VALUES(?,?,?,?,?)
    ON CONFLICT(circle_id,user_id) DO UPDATE SET profile_id=excluded.profile_id,share=excluded.share`).bind(circle.id, userId, profile.id, mode(share ?? "last"), now()).run();
  return { id: circle.id, name: circle.name };
}

/** Whoever leaves or is removed takes their answers to the group's meets with them: they are no longer part of it. */
async function dropAnswers(db: Db, circleId: string, userId: string) {
  await db.prepare("DELETE FROM et_meet_rsvps WHERE user_id=? AND meet_id IN (SELECT id FROM et_meets WHERE audience_kind='circle' AND audience_id=?)").bind(userId, circleId).run();
}

export type CircleAction = "share" | "character" | "leave" | "rotate" | "close" | "kick";
export async function circleAction(db: Db, userId: string, id: string, action: CircleAction, input: { share?: ShareMode; profileId?: string; target?: string }) {
  const circle = await db.prepare("SELECT id,owner_user_id FROM et_circles WHERE id=? AND closed_at IS NULL").bind(id).first<{ id: string; owner_user_id: string }>();
  const me = circle && await db.prepare("SELECT profile_id FROM et_circle_members WHERE circle_id=? AND user_id=?").bind(id, userId).first<{ profile_id: string }>();
  if (!circle || !me) throw new ApiError("not_found", "This group does not exist, or you are not in it.", 404);
  const owner = circle.owner_user_id === userId;
  if (action === "share") {
    await db.prepare("UPDATE et_circle_members SET share=? WHERE circle_id=? AND user_id=?").bind(mode(input.share), id, userId).run();
    return { share: mode(input.share) };
  }
  if (action === "character") {
    const profile = await ownProfile(db, userId, input.profileId ?? "");
    await db.prepare("UPDATE et_circle_members SET profile_id=? WHERE circle_id=? AND user_id=?").bind(profile.id, id, userId).run();
    return { profileId: profile.id };
  }
  if (action === "leave") {
    await db.prepare("DELETE FROM et_circle_members WHERE circle_id=? AND user_id=?").bind(id, userId).run();
    await dropAnswers(db, id, userId);
    if (owner) {
      // the group lives on with the member who has been in it longest; with nobody left it closes
      const next = await db.prepare("SELECT user_id FROM et_circle_members WHERE circle_id=? ORDER BY joined_at,user_id LIMIT 1").bind(id).first<{ user_id: string }>();
      if (next) await db.prepare("UPDATE et_circles SET owner_user_id=? WHERE id=?").bind(next.user_id, id).run();
      else await db.prepare("UPDATE et_circles SET closed_at=? WHERE id=?").bind(now(), id).run();
    }
    return { left: true };
  }
  if (!owner) throw new ApiError("forbidden", "Only the owner of a group can do this.", 403);
  if (action === "rotate") {
    const code = newInviteCode();
    await db.prepare("UPDATE et_circles SET invite_code=? WHERE id=?").bind(code, id).run();
    return { code };
  }
  if (action === "close") {
    await db.batch([
      db.prepare("UPDATE et_circles SET closed_at=? WHERE id=?").bind(now(), id),
      db.prepare("DELETE FROM et_circle_members WHERE circle_id=?").bind(id),
    ]);
    return { closed: true };
  }
  // kick
  const target = await db.prepare("SELECT user_id FROM et_circle_members WHERE circle_id=? AND profile_id=?").bind(id, input.target ?? "").first<{ user_id: string }>();
  if (!target) throw new ApiError("not_found", "This member is not in the group.", 404);
  if (target.user_id === userId) throw new ApiError("invalid_request", "Use Leave to leave your own group.", 400);
  await db.prepare("DELETE FROM et_circle_members WHERE circle_id=? AND user_id=?").bind(id, target.user_id).run();
  await dropAnswers(db, id, target.user_id);
  return { removed: true };
}

export async function circlesOverview(db: Db, userId: string): Promise<{ circles: CircleView[] }> {
  const mine = await db.prepare(`SELECT c.id,c.name,c.owner_user_id,c.invite_code,m.profile_id,m.share FROM et_circle_members m JOIN et_circles c ON c.id=m.circle_id
    WHERE m.user_id=? AND c.closed_at IS NULL ORDER BY c.name`).bind(userId).all();
  const circles: CircleView[] = [];
  for (const head of mine.results) {
    const members = await db.prepare(`SELECT m.user_id,m.profile_id,m.share,m.joined_at,p.name,p.class_id,p.level FROM et_circle_members m
      LEFT JOIN atlas_profiles p ON p.id=m.profile_id WHERE m.circle_id=? ORDER BY m.joined_at,m.user_id`).bind(String(head.id)).all();
    const positions = await latestPositions(db, members.results.filter(row => row.share !== "off" && row.user_id !== userId).map(row => String(row.profile_id)), ["own_track", "own_character"]);
    const owner = String(head.owner_user_id);
    const own = members.results.find(row => row.user_id === userId);
    circles.push({
      id: String(head.id), name: String(head.name), isOwner: owner === userId, inviteCode: owner === userId ? formatCode(String(head.invite_code)) : null,
      mine: { profileId: String(head.profile_id), name: typeof own?.name === "string" ? own.name : "Player", share: mode(head.share) },
      members: members.results.map(row => ({
        profileId: String(row.profile_id), name: typeof row.name === "string" ? row.name : "Player", classId: typeof row.class_id === "number" ? row.class_id : null, level: typeof row.level === "number" ? row.level : null,
        share: mode(row.share), isMe: row.user_id === userId, isOwner: row.user_id === owner,
        position: row.user_id !== userId && row.share !== "off" ? positions.get(String(row.profile_id)) ?? null : null,
      })),
    });
  }
  return { circles };
}

/** The route of a group member, only for a member of the same group who chose to share routes (never longer than 72 h). */
export async function circleTrail(db: Db, userId: string, id: string, profileId: string, hours: number): Promise<{ name: string; paths: TrackPath[] }> {
  const viewer = await db.prepare("SELECT 1 AS x FROM et_circle_members m JOIN et_circles c ON c.id=m.circle_id WHERE m.circle_id=? AND m.user_id=? AND c.closed_at IS NULL").bind(id, userId).first();
  if (!viewer) throw new ApiError("forbidden", "Join this group first.", 403);
  const target = await db.prepare("SELECT m.share,p.name FROM et_circle_members m LEFT JOIN atlas_profiles p ON p.id=m.profile_id WHERE m.circle_id=? AND m.profile_id=?").bind(id, profileId).first<{ share: string; name: string | null }>();
  if (!target || target.share !== "trail") throw new ApiError("forbidden", "This member does not share their route with the group.", 403);
  const since = now() - Math.min(Math.max(1, Math.floor(hours)), GUILD_TRAIL_MAX_HOURS) * 3600;
  const rows = await db.prepare(`SELECT o.id,o.profile_id,o.payload FROM atlas_observations o JOIN atlas_grants g ON g.id=o.grant_id AND g.user_id=o.user_id
    WHERE o.profile_id=? AND o.kind='track.path' AND o.observed_at>=? AND ${GRANT_OK(["own_track", "own_character"])} ORDER BY o.observed_at DESC LIMIT ${MY_TRAIL_MAX_PATHS}`).bind(profileId, since).all();
  return { name: target.name ?? "Player", paths: rows.results.map(toPath).filter((p): p is TrackPath => p !== null) };
}

/** Ids of the groups the account is currently in (used to decide who may see a meet). */
export async function myCircleIds(db: Db, userId: string): Promise<string[]> {
  const rows = await db.prepare("SELECT m.circle_id FROM et_circle_members m JOIN et_circles c ON c.id=m.circle_id WHERE m.user_id=? AND c.closed_at IS NULL").bind(userId).all();
  return rows.results.map(row => String(row.circle_id));
}

// Meets: a point on the map and a time that somebody proposes. Who sees it is the creator's explicit choice, made per meet:
// a guild they are confirmed in, a group they are in, or anyone who has the link. A meet shows the place the creator
// picked, never where they are. Responding ("going", "maybe") is also explicit, under a name the responder can change.
import { z } from "zod";
import { ApiError } from "./policy";
import { myCircleIds, newInviteCode, normalizeCode } from "./circles";
import { decode, myGuildIds, now, type Db } from "./people";

export const MEET_KINDS = ["meet", "group", "farm", "trade", "event", "note"] as const;
export type MeetKind = typeof MEET_KINDS[number];
export const MEET_MAX_ACTIVE = 20;
export const MEET_MAX_MEMBERS = 40;
const GRACE_SECONDS = 3600;

const itemQty = z.object({ item: z.number().int().positive().max(10_000_000), qty: z.number().int().min(1).max(1000) }).strict();
const role = z.number().int().min(0).max(40).optional();
export const meetData = z.object({
  ref: z.string().trim().max(60).optional(),
  roles: z.object({ tank: role, healer: role, dps: role }).strict().optional(),
  wanted: z.array(itemQty).max(12).optional(),
  offered: z.array(itemQty).max(12).optional(),
}).strict();
export type MeetData = z.infer<typeof meetData>;

const place = { mapId: z.number().int().positive().max(100000), x: z.number().min(0).max(1), y: z.number().min(0).max(1) };
const common = {
  kind: z.enum(MEET_KINDS), title: z.string().trim().min(1).max(80), note: z.string().trim().max(400).default(""),
  startsAt: z.number().int().nonnegative().nullable().optional(), durationMin: z.number().int().min(15).max(1440).default(120),
  capacity: z.number().int().min(2).max(MEET_MAX_MEMBERS).nullable().optional(), host: z.string().trim().max(40).optional(),
  data: meetData.optional(),
};
export const meetInput = z.object({
  ...common, ...place, profileId: z.string().max(100).optional(),
  audience: z.discriminatedUnion("kind", [z.object({ kind: z.literal("guild"), id: z.string().min(1).max(100) }).strict(), z.object({ kind: z.literal("circle"), id: z.string().min(1).max(100) }).strict(), z.object({ kind: z.literal("link") }).strict()]),
}).strict();
export const meetPatch = z.object({
  title: common.title.optional(), note: common.note.optional(), startsAt: common.startsAt, durationMin: common.durationMin.optional(),
  capacity: common.capacity, data: common.data, mapId: place.mapId.optional(), x: place.x.optional(), y: place.y.optional(), cancel: z.boolean().optional(),
}).strict();
export const rsvpInput = z.object({ status: z.enum(["going", "maybe", "none"]), name: z.string().trim().max(40).optional() }).strict();

export interface MeetView {
  id: string; kind: MeetKind; title: string; note: string; host: string; mapId: number; x: number; y: number;
  startsAt: number | null; endsAt: number; capacity: number | null; data: MeetData;
  audience: { kind: "guild" | "circle" | "link"; id: string | null; name: string | null };
  /** Only the creator of a link meet gets the code back. */
  linkCode: string | null; mine: boolean; going: number; maybe: number; myRsvp: "going" | "maybe" | null;
  rsvps: { name: string; status: "going" | "maybe"; mine: boolean }[];
}

type Row = Record<string, unknown>;
const text = (value: unknown, fallback = "") => typeof value === "string" ? value : fallback;
const num = (value: unknown) => typeof value === "number" ? value : null;

async function audiences(db: Db, userId: string) {
  const [guilds, circles] = await Promise.all([myGuildIds(db, userId), myCircleIds(db, userId)]);
  return { guilds, circles };
}

async function fetchVisible(db: Db, userId: string, ids?: string[]): Promise<Row[]> {
  const { guilds, circles } = await audiences(db, userId);
  const rows = await db.prepare(`SELECT m.* FROM et_meets m WHERE m.status='open' AND m.ends_at>=? ${ids ? "AND m.id IN (SELECT value FROM json_each(?))" : ""} AND (
      m.user_id=?
      OR (m.audience_kind='guild' AND m.audience_id IN (SELECT value FROM json_each(?)))
      OR (m.audience_kind='circle' AND m.audience_id IN (SELECT value FROM json_each(?)))
      OR m.id IN (SELECT meet_id FROM et_meet_access WHERE user_id=?))
    ORDER BY COALESCE(m.starts_at,m.created_at),m.id LIMIT 200`)
    .bind(...[now() - GRACE_SECONDS, ...(ids ? [JSON.stringify(ids)] : []), userId, JSON.stringify(guilds), JSON.stringify(circles), userId]).all();
  return rows.results;
}

async function present(db: Db, userId: string, rows: Row[]): Promise<MeetView[]> {
  if (!rows.length) return [];
  const ids = JSON.stringify(rows.map(row => String(row.id)));
  const [rsvps, guildNames, circleNames] = await Promise.all([
    db.prepare("SELECT meet_id,user_id,name,status FROM et_meet_rsvps WHERE meet_id IN (SELECT value FROM json_each(?)) ORDER BY created_at,user_id").bind(ids).all(),
    db.prepare("SELECT id,name FROM et_guilds WHERE id IN (SELECT audience_id FROM et_meets WHERE id IN (SELECT value FROM json_each(?)) AND audience_kind='guild')").bind(ids).all(),
    db.prepare("SELECT id,name FROM et_circles WHERE id IN (SELECT audience_id FROM et_meets WHERE id IN (SELECT value FROM json_each(?)) AND audience_kind='circle')").bind(ids).all(),
  ]);
  const names = new Map([...guildNames.results, ...circleNames.results].map(row => [String(row.id), String(row.name)]));
  return rows.map(row => {
    const id = String(row.id), kind = text(row.audience_kind) as MeetView["audience"]["kind"];
    const mine = row.user_id === userId;
    const list = rsvps.results.filter(r => r.meet_id === id).map(r => ({ name: text(r.name, "Player"), status: text(r.status) as "going" | "maybe", mine: r.user_id === userId }));
    const own = list.find(r => r.mine);
    return {
      id, kind: text(row.kind) as MeetKind, title: text(row.title), note: text(row.note), host: text(row.host, "Player"), mapId: Number(row.map_id), x: Number(row.x), y: Number(row.y),
      startsAt: num(row.starts_at), endsAt: Number(row.ends_at), capacity: num(row.capacity), data: decode<MeetData>(row.data, {}),
      audience: { kind, id: typeof row.audience_id === "string" ? row.audience_id : null, name: typeof row.audience_id === "string" ? names.get(row.audience_id) ?? null : null },
      linkCode: mine && kind === "link" ? text(row.link_code) || null : null, mine,
      going: list.filter(r => r.status === "going").length, maybe: list.filter(r => r.status === "maybe").length, myRsvp: own?.status ?? null, rsvps: list,
    };
  });
}

/** Meets this account may see; with a link code the meet it belongs to is added to the account's list first. */
export async function listMeets(db: Db, userId: string, options: { code?: string } = {}): Promise<{ meets: MeetView[]; opened?: string }> {
  let opened: string | undefined;
  if (options.code) {
    const code = normalizeCode(options.code);
    const meet = code.length === 10 ? await db.prepare("SELECT id FROM et_meets WHERE link_code=? AND status='open' AND ends_at>=?").bind(code, now() - GRACE_SECONDS).first<{ id: string }>() : null;
    if (!meet) throw new ApiError("invalid_code", "This meet link is not valid any more.", 404);
    await db.prepare("INSERT OR IGNORE INTO et_meet_access(meet_id,user_id) VALUES(?,?)").bind(meet.id, userId).run();
    opened = meet.id;
  }
  return { meets: await present(db, userId, await fetchVisible(db, userId)), ...(opened ? { opened } : {}) };
}

async function profileName(db: Db, userId: string, profileId?: string) {
  if (!profileId) return null;
  const row = await db.prepare("SELECT name FROM atlas_profiles WHERE id=? AND user_id=?").bind(profileId, userId).first<{ name: string | null }>();
  return row?.name ?? null;
}

export async function createMeet(db: Db, userId: string, input: z.infer<typeof meetInput>): Promise<MeetView> {
  const t = now();
  const active = await db.prepare("SELECT COUNT(*) AS n FROM et_meets WHERE user_id=? AND status='open' AND ends_at>=?").bind(userId, t).first<{ n: number }>();
  if (Number(active?.n ?? 0) >= MEET_MAX_ACTIVE) throw new ApiError("too_many_meets", `You can have ${MEET_MAX_ACTIVE} open meets at a time. Cancel one first.`, 409);
  if (input.startsAt != null && (input.startsAt < t - GRACE_SECONDS || input.startsAt > t + 30 * 86400)) throw new ApiError("invalid_time", "A meet starts within the next 30 days.");
  const { guilds, circles } = await audiences(db, userId);
  if (input.audience.kind === "guild" && !guilds.includes(input.audience.id)) throw new ApiError("forbidden", "Confirm this guild on the map first.", 403);
  if (input.audience.kind === "circle" && !circles.includes(input.audience.id)) throw new ApiError("forbidden", "You are not in this group.", 403);
  const host = input.host || await profileName(db, userId, input.profileId) || await firstProfileName(db, userId) || "Player";
  const id = crypto.randomUUID();
  const link = input.audience.kind === "link" ? newInviteCode() : null;
  const startsAt = input.startsAt ?? null;
  const endsAt = (startsAt ?? t) + input.durationMin * 60;
  await db.batch([
    db.prepare(`INSERT INTO et_meets(id,user_id,host,kind,title,note,map_id,x,y,starts_at,ends_at,audience_kind,audience_id,link_code,capacity,data,status,created_at,updated_at)
      VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,'open',?,?)`).bind(id, userId, host, input.kind, input.title, input.note, input.mapId, input.x, input.y, startsAt, endsAt,
      input.audience.kind, input.audience.kind === "link" ? null : input.audience.id, link, input.capacity ?? null, JSON.stringify(input.data ?? {}), t, t),
    db.prepare("INSERT INTO et_meet_rsvps(meet_id,user_id,name,status,created_at) VALUES(?,?,?,'going',?)").bind(id, userId, host, t),
    // meets that ended more than a week ago are dropped whenever a new one is made
    db.prepare("DELETE FROM et_meet_rsvps WHERE meet_id IN (SELECT id FROM et_meets WHERE ends_at<?)").bind(t - 7 * 86400),
    db.prepare("DELETE FROM et_meet_access WHERE meet_id IN (SELECT id FROM et_meets WHERE ends_at<?)").bind(t - 7 * 86400),
    db.prepare("DELETE FROM et_meets WHERE ends_at<?").bind(t - 7 * 86400),
  ]);
  const [view] = await present(db, userId, await fetchVisible(db, userId, [id]));
  return view;
}

export async function updateMeet(db: Db, userId: string, id: string, patch: z.infer<typeof meetPatch>): Promise<MeetView | null> {
  const row = await db.prepare("SELECT * FROM et_meets WHERE id=? AND user_id=? AND status='open'").bind(id, userId).first();
  if (!row) throw new ApiError("not_found", "This meet does not exist, or it is not yours.", 404);
  if (patch.cancel) {
    await db.prepare("UPDATE et_meets SET status='cancelled',updated_at=? WHERE id=?").bind(now(), id).run();
    return null;
  }
  const startsAt = patch.startsAt === undefined ? num(row.starts_at) : patch.startsAt;
  const minutes = patch.durationMin ?? Math.max(15, Math.round((Number(row.ends_at) - (num(row.starts_at) ?? Number(row.created_at))) / 60));
  const endsAt = (startsAt ?? Number(row.created_at)) + minutes * 60;
  const capacity = patch.capacity === undefined ? num(row.capacity) : patch.capacity;
  if (capacity !== null) {
    const going = await db.prepare("SELECT COUNT(*) AS n FROM et_meet_rsvps WHERE meet_id=? AND status='going'").bind(id).first<{ n: number }>();
    if (Number(going?.n ?? 0) > capacity) throw new ApiError("meet_full", "More people are already going than that capacity.", 409);
  }
  await db.prepare("UPDATE et_meets SET title=?,note=?,map_id=?,x=?,y=?,starts_at=?,ends_at=?,capacity=?,data=?,updated_at=? WHERE id=?")
    .bind(patch.title ?? text(row.title), patch.note ?? text(row.note), patch.mapId ?? Number(row.map_id), patch.x ?? Number(row.x), patch.y ?? Number(row.y), startsAt, endsAt, capacity,
      JSON.stringify(patch.data ?? decode(row.data, {})), now(), id).run();
  const [view] = await present(db, userId, await fetchVisible(db, userId, [id]));
  return view ?? null;
}

export async function respondToMeet(db: Db, userId: string, id: string, input: z.infer<typeof rsvpInput>): Promise<MeetView> {
  const visible = await fetchVisible(db, userId, [id]);
  if (!visible.length) throw new ApiError("not_found", "This meet does not exist, or you cannot see it.", 404);
  if (input.status === "none") {
    await db.prepare("DELETE FROM et_meet_rsvps WHERE meet_id=? AND user_id=? AND user_id<>(SELECT user_id FROM et_meets WHERE id=?)").bind(id, userId, id).run();
  } else {
    if (input.status === "going") {
      const capacity = num(visible[0].capacity);
      const going = await db.prepare("SELECT COUNT(*) AS n FROM et_meet_rsvps WHERE meet_id=? AND status='going' AND user_id<>?").bind(id, userId).first<{ n: number }>();
      if (capacity !== null && Number(going?.n ?? 0) >= capacity) throw new ApiError("meet_full", "This meet is full. You can still answer “maybe”.", 409);
    }
    const existing = await db.prepare("SELECT name FROM et_meet_rsvps WHERE meet_id=? AND user_id=?").bind(id, userId).first<{ name: string }>();
    const name = input.name || existing?.name || await firstProfileName(db, userId) || "Player";
    await db.prepare(`INSERT INTO et_meet_rsvps(meet_id,user_id,name,status,created_at) VALUES(?,?,?,?,?)
      ON CONFLICT(meet_id,user_id) DO UPDATE SET status=excluded.status,name=excluded.name`).bind(id, userId, name, input.status, now()).run();
  }
  const [view] = await present(db, userId, await fetchVisible(db, userId, [id]));
  return view;
}

async function firstProfileName(db: Db, userId: string) {
  const row = await db.prepare("SELECT name FROM atlas_profiles WHERE user_id=? AND name IS NOT NULL ORDER BY last_seen DESC LIMIT 1").bind(userId).first<{ name: string }>();
  return row?.name ?? null;
}

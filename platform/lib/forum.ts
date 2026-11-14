// Forum shared by the website and the in-game Community page.
//
// Threads belong to one of a fixed list of categories (the addon has the same list). The opening post of a thread is a post with
// the thread's id. Every author is shown as the full character name "Name-Realm". The game cannot prove who typed a name, so
// the name is what the author chose; the account behind it is stored (user_id) and never shown.
//
// Posts travel two ways: the website writes them directly, the in-game page writes them to the addon's outbox, the desktop app
// posts the outbox to /api/device/forum and receives the current forum back, which it writes next to the addon (ForumData.lua).
// Sending the same outbox again is harmless: ids are chosen by the author and a known id is counted as a duplicate.
import { z } from "zod";
import { ApiError } from "./policy";
import { now, type Db } from "./people";

import { BODY_MAX, FORUM_CATEGORIES, TITLE_MAX, TITLE_MIN, type ForumCategory, type ForumPost, type ForumThread } from "./forum-shared";
export { BODY_MAX, FORUM_CATEGORIES, TITLE_MAX, TITLE_MIN };
export type { ForumCategory, ForumPost, ForumThread };
export const AUTHOR_MAX = 80;
export const OUTBOX_MAX = 40;
/** What one account may write per hour, from the website and the game together. */
export const THREADS_PER_HOUR = 6;
export const POSTS_PER_HOUR = 20;
/** How much of the forum is handed to the addon: it is loaded by the game at login, so it stays small. */
export const SNAPSHOT_THREADS = 60;
export const SNAPSHOT_POSTS_PER_THREAD = 30;
export const SNAPSHOT_BYTES = 600_000;
const PAGE = 40;
const ID = /^[A-Za-z0-9_-]{8,40}$/;

/** Printable text only: control characters go (new lines stay when `lines`), runs of blanks and blank lines are folded. */
export function cleanText(value: unknown, max: number, lines = false): string {
  if (typeof value !== "string") return "";
  let text = value.normalize("NFC").replace(/\r\n?/g, "\n");
  const invisible = "\u200B-\u200F\u202A-\u202E\u2066-\u2069\uFEFF";
  text = text.replace(new RegExp(lines ? `[\u0000-\u0009\u000B-\u001F\u007F-\u009F${invisible}]` : `[\u0000-\u001F\u007F-\u009F${invisible}]`, "g"), " ");
  text = lines ? text.replace(/[ \t]+/g, " ").replace(/ ?\n ?/g, "\n").replace(/\n{3,}/g, "\n\n") : text.replace(/\s+/g, " ");
  return [...text.trim()].slice(0, max).join("");
}

const category = z.enum(FORUM_CATEGORIES);
const textField = (min: number, max: number, lines: boolean) => z.string().transform((v) => cleanText(v, max, lines)).refine((v) => [...v].length >= min, "Too short.");
export const threadInput = z.object({
  category, title: textField(TITLE_MIN, TITLE_MAX, false), body: textField(1, BODY_MAX, true), profileId: z.string().max(100).optional(),
}).strict();
export const postInput = z.object({
  threadId: z.string().regex(ID), body: textField(1, BODY_MAX, true), replyTo: z.string().regex(ID).optional(), profileId: z.string().max(100).optional(),
}).strict();
export const editPostInput = z.object({ body: textField(1, BODY_MAX, true), title: textField(TITLE_MIN, TITLE_MAX, false).optional() }).strict();
export const moderateThreadInput = z.object({ pinned: z.boolean() }).strict();

type Row = Record<string, unknown>;
const text = (value: unknown) => typeof value === "string" ? value : "";
const num = (value: unknown) => typeof value === "number" ? value : null;

const threadView = (row: Row, userId: string | null, admin = false): ForumThread => ({
  id: text(row.id), category: text(row.category) as ForumCategory, title: text(row.title), author: text(row.author), classId: num(row.class_id),
  origin: row.origin === "web" ? "web" : "game", pinned: Boolean(row.pinned), canManage: userId !== null && (admin || row.user_id === userId), canModerate: userId !== null && admin, createdAt: Number(row.created_at), lastPostAt: Number(row.last_post_at),
  replies: Number(row.reply_count ?? 0), mine: userId !== null && row.user_id === userId,
});
const postView = (row: Row, userId: string | null, admin = false): ForumPost => ({
  id: text(row.id), threadId: text(row.thread_id), replyTo: typeof row.reply_to === "string" ? row.reply_to : null, author: text(row.author), classId: num(row.class_id),
  origin: row.origin === "web" ? "web" : "game", body: text(row.body), createdAt: Number(row.created_at), mine: userId !== null && row.user_id === userId, canManage: userId !== null && (admin || row.user_id === userId),
});

/** Resolve admin from the trusted session account's Discord ID, never a display name or request field. */
export async function isForumAdmin(db: Db, userId: string | null, allowlist: string | undefined): Promise<boolean> {
  if (!userId || !allowlist) return false;
  const ids = new Set(allowlist.split(/[\s,]+/).filter((id) => /^\d{5,25}$/.test(id)));
  if (ids.size === 0) return false;
  const row = await db.prepare("SELECT discord_id FROM et_users WHERE id=?").bind(userId).first<Row>();
  return typeof row?.discord_id === "string" && ids.has(row.discord_id);
}

export function newForumId(prefix = "w"): string {
  const bytes = crypto.getRandomValues(new Uint8Array(12));
  return prefix + [...bytes].map((b) => b.toString(36).padStart(2, "0")).join("").slice(0, 14);
}

/** The name an account writes under on the website: one of its own characters ("Name-Realm"), else the account's display name. */
export async function webAuthor(db: Db, userId: string, profileId?: string): Promise<{ author: string; classId: number | null }> {
  if (profileId) {
    const row = await db.prepare("SELECT name,realm,class_id FROM atlas_profiles WHERE id=? AND user_id=?").bind(profileId, userId).first<Row>();
    const name = cleanText(row?.name, 40);
    if (row && name) {
      const realm = cleanText(row.realm, 40);
      return { author: realm ? `${name}-${realm}` : name, classId: num(row.class_id) };
    }
    throw new ApiError("invalid_character", "Choose one of your own characters.", 400);
  }
  const user = await db.prepare("SELECT display_name,username FROM et_users WHERE id=?").bind(userId).first<Row>();
  return { author: cleanText(user?.display_name || user?.username || "Player", AUTHOR_MAX) || "Player", classId: null };
}

export async function myForumCharacters(db: Db, userId: string) {
  const rows = await db.prepare("SELECT id,name,realm,class_id FROM atlas_profiles WHERE user_id=? AND name IS NOT NULL ORDER BY last_seen DESC LIMIT 30").bind(userId).all<Row>();
  return rows.results.map((row) => ({ id: text(row.id), name: `${text(row.name)}${text(row.realm) ? "-" + text(row.realm) : ""}`, classId: num(row.class_id) }));
}

async function checkRate(db: Db, userId: string, kind: "thread" | "post") {
  const since = now() - 3600;
  const row = kind === "thread"
    ? await db.prepare("SELECT COUNT(*) AS n FROM et_forum_threads WHERE user_id=? AND created_at>?").bind(userId, since).first<{ n: number }>()
    : await db.prepare("SELECT COUNT(*) AS n FROM et_forum_posts WHERE user_id=? AND created_at>?").bind(userId, since).first<{ n: number }>();
  if (Number(row?.n ?? 0) >= (kind === "thread" ? THREADS_PER_HOUR : POSTS_PER_HOUR)) throw new ApiError("rate_limited", "You are posting too fast. Try again in a while.", 429);
}

async function refreshThread(db: Db, threadId: string) {
  await db.prepare(`UPDATE et_forum_threads SET
      reply_count=MAX(0,(SELECT COUNT(*) FROM et_forum_posts WHERE thread_id=? AND deleted_at IS NULL AND id<>?)),
      last_post_at=COALESCE((SELECT MAX(created_at) FROM et_forum_posts WHERE thread_id=? AND deleted_at IS NULL),created_at)
    WHERE id=?`).bind(threadId, threadId, threadId, threadId).run();
}

interface NewThread { id: string; category: ForumCategory; title: string; body: string; author: string; classId: number | null; origin: "game" | "web"; createdAt: number }
interface NewPost { id: string; threadId: string; replyTo: string | null; body: string; author: string; classId: number | null; origin: "game" | "web"; createdAt: number }

/** False when the id is already taken (a repeated upload), true when the thread was written. */
async function insertThread(db: Db, userId: string, t: NewThread): Promise<boolean> {
  const results=await db.batch([
    db.prepare(`INSERT INTO et_forum_threads(id,category,title,user_id,author,class_id,origin,pinned,created_at,last_post_at,reply_count)
      SELECT ?,?,?,?,?,?,?,0,?,?,0 WHERE NOT EXISTS (SELECT 1 FROM et_forum_posts WHERE id=?) ON CONFLICT(id) DO NOTHING`).bind(t.id,t.category,t.title,userId,t.author,t.classId,t.origin,t.createdAt,t.createdAt,t.id),
    db.prepare("INSERT INTO et_forum_posts(id,thread_id,reply_to,user_id,author,class_id,origin,body,created_at) SELECT ?,?,NULL,?,?,?,?,?,? WHERE EXISTS (SELECT 1 FROM et_forum_threads WHERE id=? AND user_id=? AND deleted_at IS NULL) ON CONFLICT(id) DO NOTHING")
      .bind(t.id,t.id,userId,t.author,t.classId,t.origin,t.body,t.createdAt,t.id,userId),
  ]) as {meta:{changes?:number}}[];
  return results[0].meta.changes === 1 && results[1].meta.changes === 1;
}
async function insertPost(db: Db, userId: string, p: NewPost): Promise<"written" | "duplicate" | "thread_missing"> {
  const thread = await db.prepare("SELECT id FROM et_forum_threads WHERE id=? AND deleted_at IS NULL").bind(p.threadId).first<Row>();
  if (!thread) return "thread_missing";
  let replyTo = p.replyTo;
  if (replyTo) {
    const target = await db.prepare("SELECT id FROM et_forum_posts WHERE id=? AND thread_id=?").bind(replyTo, p.threadId).first<Row>();
    if (!target) replyTo = null;
  }
  const made = await db.prepare("INSERT INTO et_forum_posts(id,thread_id,reply_to,user_id,author,class_id,origin,body,created_at) SELECT ?,?,?,?,?,?,?,?,? FROM et_forum_threads WHERE id=? AND deleted_at IS NULL ON CONFLICT(id) DO NOTHING")
    .bind(p.id, p.threadId, replyTo, userId, p.author, p.classId, p.origin, p.body, p.createdAt, p.threadId).run();
  if (made.meta.changes !== 1) {
    const current = await db.prepare("SELECT id FROM et_forum_threads WHERE id=? AND deleted_at IS NULL").bind(p.threadId).first<Row>();
    return !current ? "thread_missing" : "duplicate";
  }
  await refreshThread(db, p.threadId);
  return "written";
}

export async function createThread(db: Db, userId: string, raw: z.infer<typeof threadInput>) {
  await checkRate(db, userId, "thread");
  const { author, classId } = await webAuthor(db, userId, raw.profileId);
  const id = newForumId("w");
  await insertThread(db, userId, { id, category: raw.category, title: raw.title, body: raw.body, author, classId, origin: "web", createdAt: now() });
  return getThread(db, id, userId);
}

export async function createPost(db: Db, userId: string, raw: z.infer<typeof postInput>) {
  await checkRate(db, userId, "post");
  const { author, classId } = await webAuthor(db, userId, raw.profileId);
  const result = await insertPost(db, userId, { id: newForumId("w"), threadId: raw.threadId, replyTo: raw.replyTo ?? null, body: raw.body, author, classId, origin: "web", createdAt: now() });
  if (result === "thread_missing") throw new ApiError("not_found", "This thread does not exist any more.", 404);
  return getThread(db, raw.threadId, userId);
}

export async function listForum(db: Db, userId: string | null, query: { category?: string; page?: number; q?: string }, admin = false) {
  const cat = FORUM_CATEGORIES.find((c) => c === query.category);
  const page = Number.isFinite(query.page) ? Math.max(0, Math.min(500, Math.floor(query.page!))) : 0;
  const search = cleanText(query.q, 80);
  const counts = await db.prepare("SELECT category,COUNT(*) AS n FROM et_forum_threads WHERE deleted_at IS NULL GROUP BY category").all<{ category: string; n: number }>();
  const clauses = ["t.deleted_at IS NULL"];
  const args: (string | number)[] = [];
  if (cat) { clauses.push("t.category=?"); args.push(cat); }
  if (search) {
    // SQL placeholders protect input and ESCAPE makes %, _ and backslash literal.
    // Deleted posts cannot cause a thread to appear in search results.
    // SQLite lower() only handles ASCII; fold Czech uppercase explicitly too.
    const fold = (column: string) => `lower(${Array.from("ÁČĎÉĚÍŇÓŘŠŤÚŮÝŽ").reduce((sql, ch) => `replace(${sql},'${ch}','${ch.toLowerCase()}')`, column)})`;
    const like = `%${search.toLocaleLowerCase("cs-CZ").replace(/[\\%_]/g, "\\$&")}%`;
    clauses.push(`(${fold("t.title")} LIKE ? ESCAPE '\\' OR ${fold("t.author")} LIKE ? ESCAPE '\\' OR EXISTS (SELECT 1 FROM et_forum_posts p WHERE p.thread_id=t.id AND p.deleted_at IS NULL AND (${fold("p.body")} LIKE ? ESCAPE '\\' OR ${fold("p.author")} LIKE ? ESCAPE '\\')))`);
    args.push(like, like, like, like);
  }
  args.push(PAGE + 1, page * PAGE);
  const rows = await db.prepare(`SELECT t.* FROM et_forum_threads t WHERE ${clauses.join(" AND ")} ORDER BY t.pinned DESC,t.last_post_at DESC,t.id ASC LIMIT ? OFFSET ?`).bind(...args).all<Row>();
  return {
    categories: FORUM_CATEGORIES.map((id) => ({ id, threads: Number(counts.results.find((c) => c.category === id)?.n ?? 0) })),
    threads: rows.results.slice(0, PAGE).map((row) => threadView(row, userId, admin)),
    hasMore: rows.results.length > PAGE, page,
  };
}

export async function getThread(db: Db, id: string, userId: string | null, admin = false) {
  if (!ID.test(id)) throw new ApiError("not_found", "Thread not found.", 404);
  const row = await db.prepare("SELECT * FROM et_forum_threads WHERE id=? AND deleted_at IS NULL").bind(id).first<Row>();
  if (!row) throw new ApiError("not_found", "Thread not found.", 404);
  const posts = await db.prepare("SELECT * FROM et_forum_posts WHERE thread_id=? AND deleted_at IS NULL ORDER BY created_at ASC,(id<>thread_id) ASC,rowid ASC LIMIT 300").bind(id).all<Row>();
  return { thread: threadView(row, userId, admin), posts: posts.results.map((p) => postView(p, userId, admin)) };
}

/** An author removes their own post; removing the opening post removes the whole thread. */
export async function deleteForumPost(db: Db, userId: string, id: string, admin = false) {
  if (!ID.test(id)) throw new ApiError("not_found", "Post not found.", 404);
  const post = await db.prepare("SELECT id,thread_id FROM et_forum_posts WHERE id=? AND (user_id=? OR ?=1) AND deleted_at IS NULL").bind(id, userId, admin ? 1 : 0).first<Row>();
  if (!post) throw new ApiError("not_found", "Post not found.", 404);
  const at = now();
  const statements = [];
  if (post.id === post.thread_id) {
    statements.push(db.prepare("UPDATE et_forum_threads SET deleted_at=? WHERE id=? AND deleted_at IS NULL AND EXISTS (SELECT 1 FROM et_forum_posts WHERE id=? AND deleted_at IS NULL AND (user_id=? OR ?=1))").bind(at, id, id, userId, admin ? 1 : 0));
  }
  statements.push(db.prepare("UPDATE et_forum_posts SET deleted_at=? WHERE id=? AND deleted_at IS NULL AND (user_id=? OR ?=1)").bind(at, id, userId, admin ? 1 : 0));
  const result = await db.batch(statements) as { meta: { changes?: number } }[];
  if (result[result.length - 1].meta.changes !== 1) throw new ApiError("not_found", "Post not found.", 404);
  await refreshThread(db, text(post.thread_id));
  return { deleted: true };
}

/** Edit own content, or any content for a server-authenticated moderator. */
export async function editForumPost(db: Db, userId: string, id: string, raw: z.infer<typeof editPostInput>, admin = false) {
  if (!ID.test(id)) throw new ApiError("not_found", "Post not found.", 404);
  const post = await db.prepare("SELECT p.id,p.thread_id FROM et_forum_posts p JOIN et_forum_threads t ON t.id=p.thread_id WHERE p.id=? AND p.deleted_at IS NULL AND t.deleted_at IS NULL AND (p.user_id=? OR ?=1)").bind(id, userId, admin ? 1 : 0).first<Row>();
  if (!post) throw new ApiError("not_found", "Post not found.", 404);
  if (raw.title !== undefined && post.id !== post.thread_id) throw new ApiError("invalid_post", "Only the opening post can change a title.", 400);
  const statements = [];
  if (raw.title !== undefined) statements.push(db.prepare("UPDATE et_forum_threads SET title=? WHERE id=? AND deleted_at IS NULL AND EXISTS (SELECT 1 FROM et_forum_posts WHERE id=? AND deleted_at IS NULL AND (user_id=? OR ?=1))").bind(raw.title, post.thread_id, id, userId, admin ? 1 : 0));
  statements.push(db.prepare("UPDATE et_forum_posts SET body=? WHERE id=? AND deleted_at IS NULL AND (user_id=? OR ?=1) AND EXISTS (SELECT 1 FROM et_forum_threads WHERE id=? AND deleted_at IS NULL)").bind(raw.body, id, userId, admin ? 1 : 0, post.thread_id));
  const result = await db.batch(statements) as { meta: { changes?: number } }[];
  if (result[result.length - 1].meta.changes !== 1) throw new ApiError("not_found", "Post not found.", 404);
  return getThread(db, text(post.thread_id), userId, admin);
}

/** Moderator controls never derive authority from the client-supplied body. */
export async function moderateForumThread(db: Db, userId: string, id: string, raw: z.infer<typeof moderateThreadInput>, admin = false) {
  if (!admin) throw new ApiError("forbidden", "Moderator access required.", 403);
  if (!ID.test(id)) throw new ApiError("not_found", "Thread not found.", 404);
  const result = await db.prepare("UPDATE et_forum_threads SET pinned=? WHERE id=? AND deleted_at IS NULL")
    .bind(Number(raw.pinned), id).run();
  if (result.meta.changes !== 1) throw new ApiError("not_found", "Thread not found.", 404);
  return getThread(db, id, userId, true);
}

// ---------------------------------------------------------------- the desktop app

const outboxPost = z.object({
  kind: z.literal("post"), id: z.string().regex(ID), threadId: z.string().regex(ID), replyTo: z.string().regex(ID).optional(),
  body: z.string().max(4000), author: z.string().max(200), classId: z.number().int().min(1).max(100).optional(), createdAt: z.number().finite(),
}).strict();
const outboxThread = z.object({
  kind: z.literal("thread"), id: z.string().regex(ID), category, title: z.string().max(400), body: z.string().max(4000),
  author: z.string().max(200), classId: z.number().int().min(1).max(100).optional(), createdAt: z.number().finite(),
}).strict();
export const deviceForumInput = z.object({ outbox: z.array(z.unknown()).max(OUTBOX_MAX * 4).default([]) }).strict();

/** What the game writes can be wrong in any way: nothing is trusted, a bad entry is skipped, never the whole upload. */
function authorName(value: string): string {
  const name = cleanText(value, AUTHOR_MAX);
  return name || "Unknown";
}
function stamp(value: number, at: number): number {
  const seconds = Math.floor(value);
  return seconds > at + 300 || seconds < at - 30 * 86400 ? at : seconds;
}

export interface SyncReport { accepted: number; duplicates: number; rejected: number; acknowledgedIds: string[] }

export async function applyOutbox(db: Db, userId: string, rawEntries: unknown[]): Promise<SyncReport> {
  const report: SyncReport = { accepted: 0, duplicates: 0, rejected: 0, acknowledgedIds: [] };
  const ack = (id: string) => { if (!report.acknowledgedIds.includes(id)) report.acknowledgedIds.push(id); };
  const at = now();
  const threads: z.infer<typeof outboxThread>[] = [];
  const posts: z.infer<typeof outboxPost>[] = [];
  for (const entry of rawEntries.slice(0, OUTBOX_MAX * 4)) {
    const t = outboxThread.safeParse(entry);
    if (t.success) { threads.push(t.data); continue; }
    const p = outboxPost.safeParse(entry);
    if (p.success) { posts.push(p.data); continue; }
    report.rejected++;
  }
  let threadBudget = 0;
  let postBudget = 0;
  const since = at - 3600;
  threadBudget = THREADS_PER_HOUR - Number((await db.prepare("SELECT COUNT(*) AS n FROM et_forum_threads WHERE user_id=? AND created_at>?").bind(userId, since).first<{ n: number }>())?.n ?? 0);
  postBudget = POSTS_PER_HOUR - Number((await db.prepare("SELECT COUNT(*) AS n FROM et_forum_posts WHERE user_id=? AND created_at>?").bind(userId, since).first<{ n: number }>())?.n ?? 0);
  threads.sort((a, b) => a.createdAt - b.createdAt);
  posts.sort((a, b) => a.createdAt - b.createdAt);
  for (const t of threads) {
    const title = cleanText(t.title, TITLE_MAX);
    const body = cleanText(t.body, BODY_MAX, true);
    if ([...title].length < TITLE_MIN || !body) { report.rejected++; continue; }
    const known = await db.prepare("SELECT id,user_id FROM et_forum_threads WHERE id=?").bind(t.id).first<Row>();
    if (known) { if (known.user_id === userId) { report.duplicates++; ack(t.id); } else report.rejected++; continue; }
    if (threadBudget <= 0) { report.rejected++; continue; }
    const made = await insertThread(db, userId, { id: t.id, category: t.category, title, body, author: authorName(t.author), classId: t.classId ?? null, origin: "game", createdAt: stamp(t.createdAt, at) });
    if (made) { report.accepted++; threadBudget--; ack(t.id); }
    else {
      const existing = await db.prepare("SELECT user_id FROM et_forum_threads WHERE id=?").bind(t.id).first<Row>();
      if (existing?.user_id === userId) { report.duplicates++; ack(t.id); } else report.rejected++;
    }
  }
  for (const p of posts) {
    const body = cleanText(p.body, BODY_MAX, true);
    if (!body) { report.rejected++; continue; }
    const known = await db.prepare("SELECT id,user_id FROM et_forum_posts WHERE id=?").bind(p.id).first<Row>();
    if (known) { if (known.user_id === userId) { report.duplicates++; ack(p.id); } else report.rejected++; continue; }
    if (postBudget <= 0) { report.rejected++; continue; }
    const result = await insertPost(db, userId, { id: p.id, threadId: p.threadId, replyTo: p.replyTo ?? null, body, author: authorName(p.author), classId: p.classId ?? null, origin: "game", createdAt: stamp(p.createdAt, at) });
    if (result === "written") { report.accepted++; postBudget--; ack(p.id); }
    else if (result === "duplicate") {
      const existing = await db.prepare("SELECT user_id FROM et_forum_posts WHERE id=?").bind(p.id).first<Row>();
      if (existing?.user_id === userId) { report.duplicates++; ack(p.id); } else report.rejected++;
    } else report.rejected++;
  }
  return report;
}

export interface AddonPost { id: string; author: string; classId: number | null; origin: "game" | "web"; body: string; createdAt: number; replyTo: string | null }
export interface AddonThread { id: string; category: ForumCategory; title: string; author: string; classId: number | null; origin: "game" | "web"; pinned: boolean; createdAt: number; lastPostAt: number; replies: number; posts: AddonPost[] }

/** The forum as the addon keeps it: the newest threads, each with its opening post and the latest replies, within a size budget. */
export async function addonSnapshot(db: Db): Promise<{ generatedAt: number; threads: AddonThread[] }> {
  const threadRows = await db.prepare("SELECT * FROM et_forum_threads WHERE deleted_at IS NULL ORDER BY pinned DESC,last_post_at DESC LIMIT ?").bind(SNAPSHOT_THREADS).all<Row>();
  const out: AddonThread[] = [];
  let bytes = 0;
  for (const row of threadRows.results) {
    const id = text(row.id);
    const rows = await db.prepare("SELECT * FROM et_forum_posts WHERE thread_id=? AND deleted_at IS NULL ORDER BY created_at ASC,(id<>thread_id) ASC,rowid ASC").bind(id).all<Row>();
    const all = rows.results.map((p) => postView(p, null));
    const opening = all.find((p) => p.id === id);
    const rest = all.filter((p) => p.id !== id).slice(-(SNAPSHOT_POSTS_PER_THREAD - 1));
    const posts = [...(opening ? [opening] : []), ...rest].map((p): AddonPost => ({ id: p.id, author: p.author, classId: p.classId, origin: p.origin, body: p.body, createdAt: p.createdAt, replyTo: p.replyTo }));
    const view = threadView(row, null);
    const size = posts.reduce((sum, p) => sum + p.body.length * 2 + p.author.length + 120, view.title.length + 200);
    if (bytes + size > SNAPSHOT_BYTES) break;
    bytes += size;
    out.push({ id, category: view.category, title: view.title, author: view.author, classId: view.classId, origin: view.origin, pinned: view.pinned, createdAt: view.createdAt, lastPostAt: view.lastPostAt, replies: view.replies, posts });
  }
  return { generatedAt: now(), threads: out };
}

/** One call of the desktop app: take what the game wrote, give back what the forum looks like now. */
export async function deviceForum(db: Db, userId: string, raw: unknown) {
  const input = deviceForumInput.safeParse(raw);
  if (!input.success) throw new ApiError("invalid_request", "Invalid forum request.", 400);
  const report = await applyOutbox(db, userId, input.data.outbox);
  // the website asked "where are you?": the app answers with one position instead of sending them all the time
  const locate = (await db.prepare("SELECT 1 AS yes FROM et_locate_requests WHERE user_id=?").bind(userId).first()) !== null;
  return { ...report, ...await addonSnapshot(db), locate };
}

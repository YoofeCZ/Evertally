// What the forum page in the browser needs from lib/forum.ts, without pulling the server code (zod, the database) into the page.
export const FORUM_CATEGORIES = ["general", "dungeons", "professions", "trading", "guilds", "feedback"] as const;
export type ForumCategory = typeof FORUM_CATEGORIES[number];
export const TITLE_MAX = 80;
export const TITLE_MIN = 3;
export const BODY_MAX = 800;

export interface ForumPost { id: string; threadId: string; replyTo: string | null; author: string; classId: number | null; origin: "game" | "web"; body: string; createdAt: number; mine: boolean; canManage: boolean }
export interface ForumThread {
  id: string; category: ForumCategory; title: string; author: string; classId: number | null; origin: "game" | "web";
  pinned: boolean; canManage: boolean; canModerate: boolean; createdAt: number; lastPostAt: number; replies: number; mine: boolean;
}

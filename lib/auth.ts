// Discord sign-in and opaque server-side sessions.
import { env } from "cloudflare:workers";
import { getBinding } from "@/db";
import {
  SESSION_COOKIE, SESSION_TTL_SECONDS, STATE_COOKIE, STATE_TTL_SECONDS,
  base64url, fromBase64url, isLoopbackHost, randomToken, readCookie, safeEqual, safeReturnPath, serializeCookie, sha256Hex,
} from "./auth-core";

export type SessionUser = { id: string; username: string; displayName: string; avatarUrl: string | null };
type Row = Record<string, unknown>;

const now = () => Math.floor(Date.now() / 1000);
const isSecure = (request: Request) => new URL(request.url).protocol === "https:";

function serializeUser(row: Row): SessionUser {
  const discordId = typeof row.discord_id === "string" ? row.discord_id : null;
  const avatar = typeof row.avatar === "string" ? row.avatar : null;
  return {
    id: String(row.id),
    username: String(row.username),
    displayName: String(row.display_name ?? row.username),
    avatarUrl: discordId && avatar && /^[a-z0-9_]+$/i.test(avatar) ? `https://cdn.discordapp.com/avatars/${discordId}/${avatar}.png?size=64` : null,
  };
}

export async function getSessionUser(request: Request): Promise<SessionUser | null> {
  const token = readCookie(request.headers.get("cookie"), SESSION_COOKIE);
  if (!token || token.length > 100) return null;
  const row = await getBinding()
    .prepare("SELECT u.* FROM et_sessions s JOIN et_users u ON u.id = s.user_id WHERE s.token_hash = ? AND s.expires_at > ?")
    .bind(await sha256Hex(token), now())
    .first<Row>();
  return row ? serializeUser(row) : null;
}

async function sessionCookie(request: Request, userId: string): Promise<string> {
  const token = randomToken();
  const created = now();
  const db = getBinding();
  await db.batch([
    // Opportunistic cleanup keeps the table small without a cron job.
    db.prepare("DELETE FROM et_sessions WHERE expires_at <= ?").bind(created),
    db.prepare("INSERT INTO et_sessions(token_hash, user_id, created_at, expires_at) VALUES(?, ?, ?, ?)")
      .bind(await sha256Hex(token), userId, created, created + SESSION_TTL_SECONDS),
  ]);
  return serializeCookie(SESSION_COOKIE, token, { maxAge: SESSION_TTL_SECONDS, secure: isSecure(request) });
}

function redirect(location: string, cookies: string[] = []): Response {
  const headers = new Headers({ Location: location, "Cache-Control": "no-store" });
  for (const cookie of cookies) headers.append("Set-Cookie", cookie);
  return new Response(null, { status: 302, headers });
}

function discordConfig(request: Request) {
  const vars = env as unknown as Record<string, string | undefined>;
  const clientId = vars.DISCORD_CLIENT_ID;
  const clientSecret = vars.DISCORD_CLIENT_SECRET;
  if (!clientId || !clientSecret) return null;
  const redirectUri = vars.DISCORD_REDIRECT_URI || new URL("/auth/discord/callback", request.url).toString();
  return { clientId, clientSecret, redirectUri };
}

export function discordConfigured(request: Request): boolean {
  return discordConfig(request) !== null;
}

export function startDiscordLogin(request: Request): Response {
  const config = discordConfig(request);
  if (!config) return redirect("/?auth_error=discord_not_configured");
  const state = randomToken(24);
  const returnTo = safeReturnPath(new URL(request.url).searchParams.get("return_to"));
  const authorize = new URL("https://discord.com/oauth2/authorize");
  authorize.search = new URLSearchParams({
    client_id: config.clientId, response_type: "code", redirect_uri: config.redirectUri,
    scope: "identify", state, prompt: "consent",
  }).toString();
  const value = `${state}.${base64url(new TextEncoder().encode(returnTo))}`;
  return redirect(authorize.toString(), [serializeCookie(STATE_COOKIE, value, { maxAge: STATE_TTL_SECONDS, path: "/auth", secure: isSecure(request) })]);
}

export async function finishDiscordLogin(request: Request): Promise<Response> {
  const clearState = serializeCookie(STATE_COOKIE, "", { maxAge: 0, path: "/auth", secure: isSecure(request) });
  const fail = (code: string) => redirect(`/?auth_error=${code}`, [clearState]);
  const config = discordConfig(request);
  if (!config) return fail("discord_not_configured");

  const params = new URL(request.url).searchParams;
  if (params.get("error")) return fail("discord_denied");
  const code = params.get("code");
  const state = params.get("state") ?? "";
  const [expectedState, encodedReturn] = (readCookie(request.headers.get("cookie"), STATE_COOKIE) ?? "").split(".");
  if (!code || !expectedState || !safeEqual(state, expectedState)) return fail("invalid_state");
  let returnTo = "/";
  try { returnTo = safeReturnPath(fromBase64url(encodedReturn ?? "")); } catch { /* keep "/" */ }

  const tokenResponse = await fetch("https://discord.com/api/oauth2/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "authorization_code", code, redirect_uri: config.redirectUri,
      client_id: config.clientId, client_secret: config.clientSecret,
    }),
  });
  if (!tokenResponse.ok) return fail("discord_token");
  const token = await tokenResponse.json() as { access_token?: unknown };
  if (typeof token.access_token !== "string") return fail("discord_token");

  const meResponse = await fetch("https://discord.com/api/users/@me", { headers: { Authorization: `Bearer ${token.access_token}` } });
  if (!meResponse.ok) return fail("discord_profile");
  const me = await meResponse.json() as { id?: unknown; username?: unknown; global_name?: unknown; avatar?: unknown };
  if (typeof me.id !== "string" || !/^\d{5,25}$/.test(me.id) || typeof me.username !== "string") return fail("discord_profile");

  const db = getBinding();
  const loginAt = now();
  const displayName = typeof me.global_name === "string" && me.global_name ? me.global_name.slice(0, 80) : me.username.slice(0, 80);
  const avatar = typeof me.avatar === "string" ? me.avatar.slice(0, 80) : null;
  await db.prepare(`INSERT INTO et_users(id, discord_id, username, display_name, avatar, created_at, last_login_at) VALUES(?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(discord_id) DO UPDATE SET username = excluded.username, display_name = excluded.display_name, avatar = excluded.avatar, last_login_at = excluded.last_login_at`)
    .bind(crypto.randomUUID(), me.id, me.username.slice(0, 80), displayName, avatar, loginAt, loginAt).run();
  const user = await db.prepare("SELECT id FROM et_users WHERE discord_id = ?").bind(me.id).first<Row>();
  if (!user) return fail("discord_profile");
  return redirect(returnTo, [clearState, await sessionCookie(request, String(user.id))]);
}

export async function logout(request: Request): Promise<Response> {
  const origin = request.headers.get("origin");
  if (origin && origin !== new URL(request.url).origin) return new Response(null, { status: 403 });
  const token = readCookie(request.headers.get("cookie"), SESSION_COOKIE);
  if (token && token.length <= 100) await getBinding().prepare("DELETE FROM et_sessions WHERE token_hash = ?").bind(await sha256Hex(token)).run();
  const headers = new Headers({ Location: "/", "Cache-Control": "no-store" });
  headers.append("Set-Cookie", serializeCookie(SESSION_COOKIE, "", { maxAge: 0, secure: isSecure(request) }));
  return new Response(null, { status: 303, headers });
}

/** Local development only: compiled out of production builds and limited to loopback hosts. */
export async function devLogin(request: Request): Promise<Response> {
  const url = new URL(request.url);
  if (!import.meta.env.DEV || !isLoopbackHost(url.hostname)) return new Response("Not found", { status: 404 });
  const at = now();
  await getBinding().prepare(`INSERT INTO et_users(id, discord_id, username, display_name, avatar, created_at, last_login_at) VALUES('dev-local', NULL, 'local-tester', 'Local tester', NULL, ?, ?)
      ON CONFLICT(id) DO UPDATE SET last_login_at = excluded.last_login_at`).bind(at, at).run();
  return redirect(safeReturnPath(url.searchParams.get("return_to")), [await sessionCookie(request, "dev-local")]);
}

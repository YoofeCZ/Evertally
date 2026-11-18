// Pure auth helpers (no database, no Workers runtime) so they can be unit tested.
import { SCOPES, type Scope } from "./contracts";

export const SESSION_COOKIE = "et_session";
export const STATE_COOKIE = "et_oauth";
export const SESSION_TTL_SECONDS = 30 * 24 * 3600;
export const STATE_TTL_SECONDS = 600;
export const DEVICE_CODE_TTL_SECONDS = 600;
export const DEVICE_POLL_INTERVAL_SECONDS = 5;
export const DEVICE_TOKEN_PREFIX = "etd_";
// No 0/O/1/I/L: the code is read from a tray app and typed or compared by a human.
const USER_CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

export function base64url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function fromBase64url(value: string): string {
  const padded = value.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(value.length / 4) * 4, "=");
  return new TextDecoder().decode(Uint8Array.from(atob(padded), (c) => c.charCodeAt(0)));
}

export function randomToken(bytes = 32): string {
  return base64url(crypto.getRandomValues(new Uint8Array(bytes)));
}

export async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}

/** Constant-time comparison for secrets of equal expected length. */
export function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

export function newUserCode(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(8));
  const chars = Array.from(bytes, (b) => USER_CODE_ALPHABET[b % USER_CODE_ALPHABET.length]);
  return `${chars.slice(0, 4).join("")}-${chars.slice(4).join("")}`;
}

export function normalizeUserCode(value: string): string | null {
  const cleaned = value.toUpperCase().replace(/[^A-Z0-9]/g, "");
  if (cleaned.length !== 8 || [...cleaned].some((c) => !USER_CODE_ALPHABET.includes(c))) return null;
  return `${cleaned.slice(0, 4)}-${cleaned.slice(4)}`;
}

export function readCookie(header: string | null, name: string): string | null {
  for (const part of (header ?? "").split(";")) {
    const index = part.indexOf("=");
    if (index > 0 && part.slice(0, index).trim() === name) return part.slice(index + 1).trim();
  }
  return null;
}

export function serializeCookie(name: string, value: string, options: { maxAge: number; path?: string; secure: boolean }): string {
  return `${name}=${value}; Path=${options.path ?? "/"}; Max-Age=${options.maxAge}; HttpOnly; SameSite=Lax${options.secure ? "; Secure" : ""}`;
}

/** Only same-site relative paths survive a login round trip. */
export function safeReturnPath(value: string | null | undefined): string {
  if (!value || !value.startsWith("/") || value.startsWith("//") || value.startsWith("/\\")) return "/";
  try {
    const url = new URL(value, "https://evertally.local");
    if (url.origin !== "https://evertally.local" || url.pathname.startsWith("/auth/")) return "/";
    return `${url.pathname}${url.search}${url.hash}`;
  } catch {
    return "/";
  }
}

export function isLoopbackHost(hostname: string): boolean {
  return ["localhost", "127.0.0.1", "[::1]", "::1"].includes(hostname.toLowerCase());
}

/** A device sends what the addon prepared: since 2026-11-18 everything a player records is public (lib/publish.ts
 * ALL_PUBLIC), so the scopes chosen when pairing (older devices) no longer narrow it. */
export function deviceGrantScopes(deviceScopes: Scope[], exportScopes: Scope[]): Scope[] {
  void deviceScopes;
  return SCOPES.filter((scope) => exportScopes.includes(scope));
}

export function sanitizeDeviceName(value: unknown): string {
  const text = typeof value === "string" ? value : "";
  const cleaned = text.replace(/[\u0000-\u001f\u007f]/g, "").trim().slice(0, 60);
  return cleaned || "Evertally Sync";
}

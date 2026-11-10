// Device authorization for the Evertally Sync desktop app (RFC 8628-style).
// The app starts a pairing, the signed-in user approves it on the web with chosen
// scopes, and only then the app receives a token. Secrets are stored as hashes only.
import { getBinding } from "@/db";
import {
  DEVICE_CODE_TTL_SECONDS, DEVICE_POLL_INTERVAL_SECONDS, DEVICE_TOKEN_PREFIX,
  deviceGrantScopes, newUserCode, normalizeUserCode, randomToken, sanitizeDeviceName, sha256Hex,
} from "./auth-core";
import { exportSchema, SCOPES, type Scope } from "./contracts";
import { projectExport } from "./import";
import { ApiError } from "./policy";
import { createGrant, serializeGrant, uploadEvents } from "./store";

type Row = Record<string, unknown>;
const now = () => Math.floor(Date.now() / 1000);
const parseScopes = (value: unknown): Scope[] => {
  try {
    const list = JSON.parse(String(value));
    return Array.isArray(list) ? SCOPES.filter((scope) => list.includes(scope)) : [];
  } catch {
    return [];
  }
};

export function serializeDevice(row: Row) {
  return {
    id: String(row.id), name: String(row.name), scopes: parseScopes(row.scopes),
    createdAt: Number(row.created_at), lastSeenAt: typeof row.last_seen_at === "number" ? row.last_seen_at : null,
    revokedAt: typeof row.revoked_at === "number" ? row.revoked_at : null,
  };
}

export async function startDevicePairing(name: unknown, origin: string) {
  const db = getBinding();
  const deviceCode = randomToken(32);
  const created = now();
  // Retry on the (unlikely) user-code collision instead of failing the pairing.
  for (let attempt = 0; attempt < 5; attempt++) {
    const userCode = newUserCode();
    const result = await db.prepare(`INSERT INTO et_device_codes(code_hash, user_code, name, created_at, expires_at)
        SELECT ?, ?, ?, ?, ? WHERE NOT EXISTS(SELECT 1 FROM et_device_codes WHERE user_code = ? AND expires_at > ?)`)
      .bind(await sha256Hex(deviceCode), userCode, sanitizeDeviceName(name), created, created + DEVICE_CODE_TTL_SECONDS, userCode, created)
      .run();
    if (result.meta.changes === 1) {
      await db.prepare("DELETE FROM et_device_codes WHERE expires_at <= ? AND device_id IS NULL").bind(created - 3600).run();
      return {
        deviceCode, userCode, expiresIn: DEVICE_CODE_TTL_SECONDS, interval: DEVICE_POLL_INTERVAL_SECONDS,
        verificationUri: `${origin}/link`, verificationUriComplete: `${origin}/link?code=${encodeURIComponent(userCode)}`,
      };
    }
  }
  throw new ApiError("pairing_unavailable", "Could not start pairing, try again.", 503);
}

async function pendingCode(userCode: string): Promise<Row> {
  const code = normalizeUserCode(userCode);
  if (!code) throw new ApiError("invalid_code", "The pairing code is not valid.", 400);
  const row = await getBinding().prepare("SELECT * FROM et_device_codes WHERE user_code = ? AND expires_at > ? ORDER BY created_at DESC LIMIT 1").bind(code, now()).first<Row>();
  if (!row) throw new ApiError("code_expired", "This pairing code expired. Start pairing again in the app.", 404);
  if (row.approved_by !== null || row.denied_at !== null) throw new ApiError("code_used", "This pairing code was already used.", 409);
  return row;
}

export async function describePairing(userCode: string) {
  const row = await pendingCode(userCode);
  return { userCode: String(row.user_code), name: String(row.name), expiresAt: Number(row.expires_at) };
}

export async function approvePairing(userId: string, userCode: string, scopes: Scope[], approve: boolean) {
  const row = await pendingCode(userCode);
  const db = getBinding();
  if (!approve) {
    await db.prepare("UPDATE et_device_codes SET denied_at = ? WHERE code_hash = ? AND approved_by IS NULL").bind(now(), row.code_hash).run();
    return { approved: false };
  }
  const allowed = SCOPES.filter((scope) => scopes.includes(scope));
  if (!allowed.length) throw new ApiError("invalid_scopes", "Choose at least one kind of data to share.", 400);
  const result = await db.prepare("UPDATE et_device_codes SET approved_by = ?, scopes = ? WHERE code_hash = ? AND approved_by IS NULL AND denied_at IS NULL AND expires_at > ?")
    .bind(userId, JSON.stringify(allowed), row.code_hash, now()).run();
  if (result.meta.changes !== 1) throw new ApiError("code_used", "This pairing code was already used.", 409);
  return { approved: true, name: String(row.name), scopes: allowed };
}

/** Polled by the app. Issues the device token exactly once, after approval. */
export async function pollPairing(deviceCode: unknown) {
  if (typeof deviceCode !== "string" || deviceCode.length > 100) throw new ApiError("invalid_request", "Missing device code.", 400);
  const db = getBinding();
  const row = await db.prepare("SELECT * FROM et_device_codes WHERE code_hash = ?").bind(await sha256Hex(deviceCode)).first<Row>();
  if (!row || row.device_id !== null) throw new ApiError("expired_token", "Pairing expired. Start again.", 400);
  if (row.denied_at !== null) throw new ApiError("access_denied", "Pairing was declined on the website.", 403);
  if (Number(row.expires_at) <= now()) throw new ApiError("expired_token", "Pairing expired. Start again.", 400);
  if (row.approved_by === null) return { status: "pending" as const, interval: DEVICE_POLL_INTERVAL_SECONDS };

  const deviceId = crypto.randomUUID();
  const token = DEVICE_TOKEN_PREFIX + randomToken(32);
  const created = now();
  // The conditional update makes the token issue single-use even under concurrent polls.
  const claimed = await db.prepare("UPDATE et_device_codes SET device_id = ? WHERE code_hash = ? AND device_id IS NULL").bind(deviceId, row.code_hash).run();
  if (claimed.meta.changes !== 1) throw new ApiError("expired_token", "Pairing expired. Start again.", 400);
  await db.prepare("INSERT INTO et_devices(id, user_id, name, token_hash, scopes, created_at, last_seen_at) VALUES(?, ?, ?, ?, ?, ?, ?)")
    .bind(deviceId, String(row.approved_by), String(row.name), await sha256Hex(token), String(row.scopes), created, created).run();
  const user = await db.prepare("SELECT display_name, username FROM et_users WHERE id = ?").bind(String(row.approved_by)).first<Row>();
  return { status: "approved" as const, token, deviceId, scopes: parseScopes(row.scopes), user: { displayName: String(user?.display_name ?? user?.username ?? "") } };
}

export async function deviceFromRequest(request: Request): Promise<Row> {
  const header = request.headers.get("authorization") ?? "";
  const token = header.startsWith("Bearer ") ? header.slice(7).trim() : "";
  if (!token.startsWith(DEVICE_TOKEN_PREFIX) || token.length > 100) throw new ApiError("invalid_token", "This app is not paired. Pair it again.", 401);
  const row = await getBinding().prepare("SELECT * FROM et_devices WHERE token_hash = ? AND revoked_at IS NULL").bind(await sha256Hex(token)).first<Row>();
  if (!row) throw new ApiError("invalid_token", "This app was disconnected. Pair it again.", 401);
  return row;
}

/**
 * Upload from a paired app. The app sends the addon's export as parsed JSON; the server
 * finds or creates the consent grant for that export version, limited to what both the
 * addon prepared and the user allowed for this device, and projects before storing.
 */
export async function deviceUpload(device: Row, raw: unknown) {
  const parsed = exportSchema.safeParse(raw);
  if (!parsed.success) throw new ApiError("invalid_export", `Invalid export: ${parsed.error.issues.slice(0, 2).map((i) => `${i.path.join(".")}: ${i.message}`).join("; ")}`, 400);
  const envelope = parsed.data;
  if (!envelope.enabled) throw new ApiError("export_disabled", "Web sharing is turned off in the addon.", 403);
  const userId = String(device.user_id);
  const scopes = deviceGrantScopes(parseScopes(device.scopes), envelope.scopes);
  if (!scopes.length) throw new ApiError("scope_denied", "Nothing in this export is allowed for this app.", 403);

  const db = getBinding();
  const existing = await db.prepare("SELECT * FROM atlas_grants WHERE user_id = ? AND producer_id = ? AND consent_epoch = ?")
    .bind(userId, envelope.producerId, envelope.consentEpoch).first<Row>();
  const grant = existing
    ? serializeGrant(existing)
    : await createGrant(userId, { producerId: envelope.producerId, consentEpoch: envelope.consentEpoch, since: envelope.since, scopes });
  if (grant.revokedAt !== null) throw new ApiError("consent_revoked", "Sharing for this addon export was revoked on the website. Re-enable web export in the addon.", 403);

  const projected = projectExport(envelope, scopes.filter((scope) => grant.scopes.includes(scope)));
  await db.prepare("UPDATE et_devices SET last_seen_at = ? WHERE id = ?").bind(now(), String(device.id)).run();
  return uploadEvents(userId, grant.id, projected);
}

export async function listDevices(userId: string) {
  const rows = await getBinding().prepare("SELECT * FROM et_devices WHERE user_id = ? AND revoked_at IS NULL ORDER BY created_at DESC").bind(userId).all<Row>();
  return rows.results.map(serializeDevice);
}

export async function revokeDevice(userId: string, id: string) {
  const result = await getBinding().prepare("UPDATE et_devices SET revoked_at = COALESCE(revoked_at, ?) WHERE id = ? AND user_id = ?").bind(now(), id, userId).run();
  if (result.meta.changes !== 1) throw new ApiError("not_found", "Device not found.", 404);
}

import { z } from "zod";
import { isLoopbackHost } from "./auth-core";
import { discordConfigured, getSessionUser } from "./auth";
import { SCOPES } from "./contracts";
import { approvePairing, describePairing, deviceFromRequest, deviceUpload, listDevices, pollPairing, revokeDevice, startDevicePairing } from "./devices";
import { ApiError } from "./policy";
import { getBinding } from "@/db";
import { circleAction, circlesOverview, createCircle, joinCircle } from "./circles";
import { createMeet, listMeets, meetInput, meetPatch, respondToMeet, rsvpInput, updateMeet } from "./meets";
import { eraseMyTrail, guildOverview, setMembership, SHARE_MODES, type Db as PeopleDb } from "./people";
import { createGrant, deleteMyData, getAtlas, getLeaderboards, getRuns, meData, revokeGrant, setProfileVisibility, statusData, uploadEvents, profileHistory } from "./store";

export const VERSION = "0.4.0";
export const json = (value: unknown, status = 200) =>
  Response.json(value, { status, headers: { "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff" } });

function requireSameOrigin(request: Request) {
  const origin = request.headers.get("origin");
  if (!origin || origin !== new URL(request.url).origin) throw new ApiError("origin_denied", "This action must be confirmed on the Evertally website.", 403);
}

async function readBody(request: Request, limit = 1024 * 1024): Promise<unknown> {
  if (!request.headers.get("content-type")?.toLowerCase().includes("application/json")) throw new ApiError("content_type", "Expected application/json.", 415);
  const reader = request.body?.getReader();
  if (!reader) throw new ApiError("invalid_body", "Missing request body.");
  const chunks: Uint8Array[] = [];
  let size = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > limit) {
      await reader.cancel();
      throw new ApiError("payload_too_large", "One batch must not exceed 1 MiB.", 413);
    }
    chunks.push(value);
  }
  const data = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    data.set(chunk, offset);
    offset += chunk.byteLength;
  }
  try {
    return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(data));
  } catch {
    throw new ApiError("invalid_json", "Invalid JSON.");
  }
}

const scopeList = z.array(z.enum(SCOPES)).min(1).max(SCOPES.length).refine((v) => new Set(v).size === v.length, "Duplicate scopes.");
const grantInput = z.object({ producerId: z.string().min(1).max(180), consentEpoch: z.number().int().nonnegative(), since: z.number().finite().nonnegative(), scopes: scopeList })
  .strict().refine((v) => v.since <= Math.floor(Date.now() / 1000) + 300, "The period cannot start in the future.");
const uploadInput = z.object({ grantId: z.string().uuid(), export: z.unknown() }).strict();
const visibilityInput = z.object({ public: z.boolean() }).strict();
const deviceStartInput = z.object({ name: z.string().max(200).optional() }).strict();
const devicePollInput = z.object({ deviceCode: z.string().min(10).max(100) }).strict();
const deviceApproveInput = z.object({ userCode: z.string().min(8).max(12), scopes: z.array(z.enum(SCOPES)).max(SCOPES.length), approve: z.boolean() }).strict();
const membershipInput = z.object({ profileId: z.string().min(1).max(100), action: z.enum(["join", "share", "leave"]), share: z.enum(SHARE_MODES).optional() }).strict();
const circleCreateInput = z.object({ name: z.string().trim().min(1).max(40), profileId: z.string().min(1).max(100), share: z.enum(SHARE_MODES).optional() }).strict();
const circleJoinInput = z.object({ code: z.string().min(4).max(20), profileId: z.string().min(1).max(100), share: z.enum(SHARE_MODES).optional() }).strict();
const circleActionInput = z.object({ action: z.enum(["share", "character", "leave", "rotate", "close", "kick"]), share: z.enum(SHARE_MODES).optional(), profileId: z.string().max(100).optional(), target: z.string().max(100).optional() }).strict();
const deviceUploadInput = z.object({ export: z.unknown() }).strict();

function parse<T>(schema: z.ZodType<T, z.ZodTypeDef, unknown>, value: unknown, code: string, message: string): T {
  const result = schema.safeParse(value);
  if (!result.success) throw new ApiError(code, message);
  return result.data;
}

/** Endpoints used by the desktop app: authenticated by device code or bearer token, never by cookies. */
async function handleDeviceApi(request: Request, operation: string): Promise<Response> {
  if (operation === "device-start") {
    const input = parse(deviceStartInput, await readBody(request, 4096), "invalid_request", "Invalid pairing request.");
    return json(await startDevicePairing(input.name, new URL(request.url).origin), 201);
  }
  if (operation === "device-poll") {
    const input = parse(devicePollInput, await readBody(request, 4096), "invalid_request", "Invalid pairing request.");
    return json(await pollPairing(input.deviceCode));
  }
  if (operation === "device-upload") {
    const device = await deviceFromRequest(request);
    const input = parse(deviceUploadInput, await readBody(request), "invalid_upload", "Invalid upload batch.");
    return json(await deviceUpload(device, input.export));
  }
  if (operation === "device-whoami") {
    const device = await deviceFromRequest(request);
    return json({ deviceId: String(device.id), name: String(device.name) });
  }
  throw new ApiError("not_found", "Not found.", 404);
}

export async function handleApi(request: Request, operation: string, id?: string): Promise<Response> {
  try {
    if (operation.startsWith("device-")) return await handleDeviceApi(request, operation);

    const user = await getSessionUser(request);
    const params = new URL(request.url).searchParams;
    if (request.method !== "GET") requireSameOrigin(request);

    if (operation === "status") {
      return json({
        version: VERSION, user, ...await statusData(), countingUnit: "participation",
        auth: { discord: discordConfigured(request), devLogin: Boolean(import.meta.env.DEV) && isLoopbackHost(new URL(request.url).hostname) },
        capabilities: { browserImport: true, desktopSync: true, gameVerified: false, rankedRulesets: 0 },
      });
    }
    if (operation === "atlas") return json({ entities: await getAtlas(params.get("kind") ?? "", (params.get("search") ?? "").slice(0, 200)) });
    if (operation === "profile-read" && id) return json(await profileHistory(id,user?.id));
    if (operation === "leaderboards") return json(await getLeaderboards(params));
    if (operation === "runs" && !params.has("mine")) return json({ runs: await getRuns(), countingUnit: "participation" });
    if (operation === "export") {
      const runs = (await getRuns()).filter((run) => !params.get("instanceId") || String(run.instanceId) === params.get("instanceId")).slice(0, 100);
      return json({ schemaVersion: 1, generatedAt: Math.floor(Date.now() / 1000), runs, entities: (await getAtlas()).slice(0, 200) });
    }

    if (!user) throw new ApiError("unauthorized", "Sign in to see your own data.", 401);
    if (operation === "me") return json({ user, ...await meData(user.id), devices: await listDevices(user.id) });
    if (operation === "runs") return json({ runs: await getRuns(user.id), countingUnit: "participation" });
    if (operation === "consents") {
      const input = parse(grantInput, await readBody(request), "invalid_consent", "Invalid consent scope.");
      return json({ grant: await createGrant(user.id, input) }, 201);
    }
    if (operation === "revoke" && id) {
      await revokeGrant(user.id, id);
      return json({ revoked: true });
    }
    if (operation === "uploads") {
      const input = parse(uploadInput, await readBody(request), "invalid_upload", "Invalid upload batch.");
      return json(await uploadEvents(user.id, input.grantId, input.export));
    }
    if (operation === "profile" && id) {
      const input = parse(visibilityInput, await readBody(request), "invalid_profile", "Invalid profile visibility.");
      return json({ profile: await setProfileVisibility(user.id, id, input.public) });
    }
    if (operation === "delete") {
      await deleteMyData(user.id);
      return json({ deleted: true });
    }
    if (operation === "pairing" && request.method === "GET") return json(await describePairing(params.get("code") ?? ""));
    if (operation === "pairing") {
      const input = parse(deviceApproveInput, await readBody(request, 4096), "invalid_request", "Invalid pairing approval.");
      return json(await approvePairing(user.id, input.userCode, input.scopes, input.approve));
    }
    const people = () => getBinding() as unknown as PeopleDb;
    if (operation === "track" && request.method === "GET") throw new ApiError("player_location_disabled", "Player locations are not displayed.", 403);
    if (operation === "track") return json(await eraseMyTrail(people(), user.id, params.get("profile") || undefined));
    if (operation === "guild") {
      const { guilds } = await guildOverview(people(), user.id);
      const { circles } = await circlesOverview(people(), user.id);
      return json({
        guilds: guilds.map(guild => ({ ...guild, members: guild.members?.map(member => ({ ...member, position: null })) ?? null })),
        circles: circles.map(circle => ({ ...circle, members: circle.members.map(member => ({ ...member, position: null })) })),
      });
    }
    if (operation === "circle-create") {
      const input = parse(circleCreateInput, await readBody(request, 4096), "invalid_request", "Invalid group.");
      return json(await createCircle(people(), user.id, input), 201);
    }
    if (operation === "circle-join") {
      const input = parse(circleJoinInput, await readBody(request, 4096), "invalid_request", "Invalid invite.");
      return json(await joinCircle(people(), user.id, input.code, input.profileId, input.share));
    }
    if (operation === "circle-action" && id) {
      const input = parse(circleActionInput, await readBody(request, 4096), "invalid_request", "Invalid group choice.");
      return json(await circleAction(people(), user.id, id, input.action, input));
    }
    if (operation === "circle-trail" && id) throw new ApiError("player_location_disabled", "Player locations are not displayed.", 403);
    if (operation === "meets" && request.method === "GET") return json(await listMeets(people(), user.id, { code: params.get("code") ?? undefined }));
    if (operation === "meets") {
      const input = parse(meetInput, await readBody(request, 16384), "invalid_meet", "Invalid meet.");
      return json({ meet: await createMeet(people(), user.id, input) }, 201);
    }
    if (operation === "meet" && id) {
      const input = parse(meetPatch, await readBody(request, 16384), "invalid_meet", "Invalid meet.");
      return json({ meet: await updateMeet(people(), user.id, id, input) });
    }
    if (operation === "meet-rsvp" && id) {
      const input = parse(rsvpInput, await readBody(request, 2048), "invalid_request", "Invalid answer.");
      return json({ meet: await respondToMeet(people(), user.id, id, input) });
    }
    if (operation === "guild-member" && id) {
      const input = parse(membershipInput, await readBody(request, 4096), "invalid_request", "Invalid guild choice.");
      return json(await setMembership(people(), user.id, id, input.profileId, input.action, input.share));
    }
    if (operation === "guild-trail" && id) throw new ApiError("player_location_disabled", "Player locations are not displayed.", 403);
    if (operation === "devices") return json({ devices: await listDevices(user.id) });
    if (operation === "devices-revoke" && id) {
      await revokeDevice(user.id, id);
      return json({ revoked: true });
    }
    throw new ApiError("not_found", "Not found.", 404);
  } catch (error) {
    if (error instanceof ApiError) return json({ error: { code: error.code, message: error.message } }, error.status);
    console.error("evertally_api_error", error instanceof Error ? error.name : "unknown");
    return json({ error: { code: "service_unavailable", message: "The database is not available right now. Try again." } }, 503);
  }
}

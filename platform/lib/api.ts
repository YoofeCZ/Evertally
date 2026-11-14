import { z } from "zod";
import { env } from "cloudflare:workers";
import { isLoopbackHost } from "./auth-core";
import { discordConfigured, getSessionUser } from "./auth";
import { SCOPES } from "./contracts";
import { approvePairing, describePairing, deviceFromRequest, deviceUpload, listDevices, pollPairing, revokeDevice, startDevicePairing } from "./devices";
import { ApiError } from "./policy";
import {deviceLive} from "./live";
import {ownLive} from "./people";
import { getBinding } from "@/db";
import { circleAction, circlesOverview, circleTrail, createCircle, joinCircle } from "./circles";
import { answerFriend, getSharing, listFriends, requestFriend, setSharing, visiblePlayers } from "./sharing";
import { createMeet, listMeets, meetInput, meetPatch, respondToMeet, rsvpInput, updateMeet } from "./meets";
import { eraseMyTrail, guildOverview, guildTrail, myTrail, setMembership, SHARE_MODES, type Db as PeopleDb } from "./people";
import { armoryOverview } from "./armory";
import { createThread, createPost, deleteForumPost, editForumPost, editPostInput, moderateForumThread, moderateThreadInput, isForumAdmin, deviceForum, getThread, listForum, myForumCharacters, postInput, threadInput } from "./forum";
import { createGrant, deleteMyData, getAtlas, getGuilds, getLeaderboards, getRankingPackage, getRuns, meData, revokeGrant, setProfileVisibility, statusData, uploadEvents, profileHistory } from "./store";

export const VERSION = "0.9.0";
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
// Any of the three may change at once; item level and guild only show while the character is public.
const visibilityInput = z.object({ public: z.boolean().optional(), showItemLevel: z.boolean().optional(), showGuild: z.boolean().optional(), showGear: z.boolean().optional() }).strict()
  .refine(v => v.public !== undefined || v.showItemLevel !== undefined || v.showGuild !== undefined || v.showGear !== undefined, "Nothing to change.");
const deviceStartInput = z.object({ name: z.string().max(200).optional() }).strict();
const devicePollInput = z.object({ deviceCode: z.string().min(10).max(100) }).strict();
const deviceApproveInput = z.object({ userCode: z.string().min(8).max(12), scopes: z.array(z.enum(SCOPES)).max(SCOPES.length), approve: z.boolean() }).strict();
const membershipInput = z.object({ profileId: z.string().min(1).max(100), action: z.enum(["join", "share", "leave"]), share: z.enum(SHARE_MODES).optional() }).strict();
const circleCreateInput = z.object({ name: z.string().trim().min(1).max(40), profileId: z.string().min(1).max(100), share: z.enum(SHARE_MODES).optional() }).strict();
const circleJoinInput = z.object({ code: z.string().min(4).max(20), profileId: z.string().min(1).max(100), share: z.enum(SHARE_MODES).optional() }).strict();
const circleActionInput = z.object({ action: z.enum(["share", "character", "leave", "rotate", "close", "kick"]), share: z.enum(SHARE_MODES).optional(), profileId: z.string().max(100).optional(), target: z.string().max(100).optional() }).strict();
const sharingInput = z.object({ friends: z.boolean().optional(), signedIn: z.boolean().optional(), public: z.boolean().optional() }).strict();
const friendRequestInput = z.object({ name: z.string().min(1).max(80) }).strict();
const friendActionInput = z.object({ action: z.enum(["accept", "decline", "remove"]) }).strict();
const deviceUploadInput = z.object({ export: z.unknown() }).strict();

function parse<T>(schema: z.ZodType<T, z.ZodTypeDef, unknown>, value: unknown, code: string, message: string): T {
  const result = schema.safeParse(value);
  if (!result.success) throw new ApiError(code, message);
  return result.data;
}

/** Endpoints used by the desktop app: authenticated by device code or bearer token, never by cookies. */
async function handleDeviceApi(request: Request, operation: string): Promise<Response> {
  if(operation==="device-live")return json(await deviceLive(await deviceFromRequest(request),await readBody(request,32768)));
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
  if (operation === "device-forum") {
    const device = await deviceFromRequest(request);
    const result = await deviceForum(getBinding() as unknown as PeopleDb, String(device.user_id), await readBody(request, 262144));
    return json(result);
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
    if (operation === "public-live") {
      // only what its owners chose to show to everyone, without any account identifier
      const players = await visiblePlayers(getBinding() as unknown as PeopleDb, null);
      return json({ players: players.map(p => ({ profileId: p.profileId, name: p.name, classId: p.classId, level: p.level, mapId: p.mapId, x: p.x, y: p.y, at: p.at })) });
    }
    // the forum is public to read; writing needs an account
    const forumAdmin = () => isForumAdmin(getBinding() as unknown as PeopleDb, user?.id ?? null, (env as unknown as Record<string, string | undefined>).FORUM_ADMIN_DISCORD_IDS);
    if (operation === "forum") return json(await listForum(getBinding() as unknown as PeopleDb, user?.id ?? null, { category: params.get("category") ?? undefined, page: Number(params.get("page")) || 0, q: params.get("q") ?? undefined }, await forumAdmin()));
    if (operation === "forum-thread" && id) return json(await getThread(getBinding() as unknown as PeopleDb, id, user?.id ?? null, await forumAdmin()));
    if (operation === "leaderboards") return json(await getLeaderboards(params));
    // public guilds: only what members of public characters chose to show
    if (operation === "guilds") return json(await getGuilds(params));
    // the public leaderboard for the in-game tooltip, fetched by Evertally Sync without credentials
    if (operation === "ranking-package") return json(await getRankingPackage());
    if (operation === "runs" && !params.has("mine")) return json({ runs: await getRuns(), countingUnit: "participation" });
    if (operation === "export") {
      const runs = (await getRuns()).filter((run) => !params.get("instanceId") || String(run.instanceId) === params.get("instanceId")).slice(0, 100);
      return json({ schemaVersion: 1, generatedAt: Math.floor(Date.now() / 1000), runs, entities: (await getAtlas()).slice(0, 200) });
    }

    if (!user) throw new ApiError("unauthorized", "Sign in to see your own data.", 401);
    if (operation === "me") return json({ user, ...await meData(user.id), devices: await listDevices(user.id) });
    if (operation === "runs") return json({ runs: await getRuns(user.id), countingUnit: "participation" });
    // Own characters, plus what other players allowed this account to keep. Nothing else is ever returned here.
    if (operation === "armory") return json(await armoryOverview(getBinding() as unknown as PeopleDb, user.id));
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
      return json({ profile: await setProfileVisibility(user.id, id, input) });
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
    if(operation==="live") {
      const db=people();const [own,guilds,circles]=await Promise.all([ownLive(db,user.id),guildOverview(db,user.id),circlesOverview(db,user.id)]);
      const peers=new Map<string,{mapId:number;x:number;y:number;at:number;live?:boolean}>();
      const add=(id:string|null,p:{mapId:number;x:number;y:number;at:number;live?:boolean}|null)=>{if(id&&p?.live)peers.set(id,p);};
      for(const guild of guilds.guilds)for(const member of guild.members??[])add(member.profileId,member.position);
      for(const circle of circles.circles)for(const member of circle.members)add(member.profileId,member.position);
      // what other accounts chose to show to friends, to signed-in visitors or to everyone
      const others=await visiblePlayers(db,user.id);
      return json({own,peers:[...peers].map(([profileId,position])=>({profileId,...position})),others});
    }
    const hours = (fallback: number, max: number) => Math.min(Math.max(1, Number(params.get("hours")) || fallback), max);
    if (operation === "track" && request.method === "GET") return json(await myTrail(people(), user.id, { profileId: params.get("profile") || undefined, since: Math.floor(Date.now() / 1000) - hours(24, 720) * 3600 }));
    if (operation === "track") return json(await eraseMyTrail(people(), user.id, params.get("profile") || undefined));
    if (operation === "guild") return json({ ...await guildOverview(people(), user.id), ...await circlesOverview(people(), user.id) });
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
    if (operation === "circle-trail" && id) return json(await circleTrail(people(), user.id, id, params.get("profile") ?? "", hours(24, 72)));
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
    if (operation === "guild-trail" && id) return json(await guildTrail(people(), user.id, id, params.get("profile") ?? "", hours(24, 72)));
    if (operation === "sharing" && request.method === "GET") return json({ sharing: await getSharing(people(), user.id) });
    if (operation === "sharing") {
      const input = parse(sharingInput, await readBody(request, 1024), "invalid_request", "Invalid choice.");
      return json({ sharing: await setSharing(people(), user.id, input) });
    }
    if (operation === "friends" && request.method === "GET") return json(await listFriends(people(), user.id));
    if (operation === "friends") {
      const input = parse(friendRequestInput, await readBody(request, 2048), "invalid_request", "Invalid request.");
      return json(await requestFriend(people(), user.id, input.name));
    }
    if (operation === "friend" && id) {
      const input = parse(friendActionInput, await readBody(request, 1024), "invalid_request", "Invalid choice.");
      return json(await answerFriend(people(), user.id, id, input.action));
    }
    if (operation === "forum-characters") return json({ characters: await myForumCharacters(people(), user.id) });
    if (operation === "forum-thread-create") {
      const input = parse(threadInput, await readBody(request, 8192), "invalid_post", "Check the title and the text of the thread.");
      return json(await createThread(people(), user.id, input), 201);
    }
    if (operation === "forum-post-create") {
      const input = parse(postInput, await readBody(request, 8192), "invalid_post", "Check the text of the reply.");
      return json(await createPost(people(), user.id, input), 201);
    }
    if (operation === "forum-post-delete" && id) return json(await deleteForumPost(people(), user.id, id, await forumAdmin()));
    if (operation === "forum-post-edit" && id) {
      const input = parse(editPostInput, await readBody(request, 8192), "invalid_post", "Check the post text and title.");
      return json(await editForumPost(people(), user.id, id, input, await forumAdmin()));
    }
    if (operation === "forum-thread-moderate" && id) {
      const input = parse(moderateThreadInput, await readBody(request, 1024), "invalid_post", "Choose a moderation action.");
      return json(await moderateForumThread(people(), user.id, id, input, await forumAdmin()));
    }
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

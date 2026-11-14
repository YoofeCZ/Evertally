// Guilds and raid progression in the shape of Raider.IO, from what players chose to show:
// a guild exists here only through public characters whose players turned on "show guild",
// and a boss counts only from successful boss fights of public characters (scope own_runs).
// The guild master's private roster (guild sharing) never reaches these pages.
import type { Character, Entry, Run } from "../components/evertally/types";
import type { Db } from "./people";
import { completed, factionOf, type Faction } from "../components/evertally/data";
import { levelBoard } from "./run-rankings";

export type BossKill = { encounterId: number; name: string | null; instanceId: number | null; instanceName: string | null; firstAt: number; kills: number };
export type RaidProgress = { instanceId: number | null; instanceName: string; bosses: BossKill[] };
export type GuildMember = { character: Character; itemLevel: number | null; completions: number; bosses: number; lastAt: number | null };
export type GuildSummary = {
  rank: number; name: string; realm: string | null; faction: Faction | null;
  members: number; maxLevel: number | null; avgLevel: number | null; itemLevel: number | null;
  completions: number; bosses: number; raids: { instanceName: string; killed: number }[]; lastAt: number | null;
};
export type GuildDetail = GuildSummary & { roster: GuildMember[]; progress: RaidProgress[]; recent: Run[]; realmRank: number; realmTotal: number };

const PAGE_SIZE = 40;
const decode = (value: unknown): Record<string, unknown> | null => { try { const v = JSON.parse(String(value)); return v && typeof v === "object" ? v as Record<string, unknown> : null; } catch { return null; } };
const text = (value: unknown, max = 80) => typeof value === "string" && value.trim() ? value.trim().slice(0, max) : null;
const fold = (value: string | null | undefined) => (value ?? "").trim().toLocaleLowerCase("en");
/** One guild per realm and name, whatever the capitals. */
export const guildKey = (realm: string | null | undefined, name: string) => `${fold(realm).replace(/[\s'-]/g, "")}|${fold(name)}`;

/**
 * Successful boss fights of public characters, per character and boss: the first kill and how many.
 * Only while the grant that carried them is live and still includes own_runs. `ids` limits it to these characters.
 */
export async function publicBossKills(db: Db, ids?: readonly string[]): Promise<Map<string, BossKill[]>> {
  const out = new Map<string, Map<number, BossKill>>();
  const size = 1000;
  const only = ids ? [...new Set(ids)] : null;
  if (only && !only.length) return new Map();
  const chunks = only ? Array.from({ length: Math.ceil(only.length / 90) }, (_, i) => only.slice(i * 90, i * 90 + 90)) : [null];
  for (const chunk of chunks) {
    for (let offset = 0; ; offset += size) {
      const batch = await db.prepare(`SELECT o.profile_id,o.observed_at,o.payload FROM atlas_observations o
        JOIN atlas_profiles p ON p.id=o.profile_id AND p.user_id=o.user_id AND p.producer_id=o.producer_id
        JOIN atlas_grants g ON g.id=o.grant_id AND g.user_id=o.user_id AND g.producer_id=o.producer_id
        WHERE o.kind='raid.encounter_finished' AND o.scope='own_runs' AND p.public=1 AND g.revoked_at IS NULL
        AND EXISTS(SELECT 1 FROM json_each(g.scopes) WHERE value='own_runs')
        ${chunk ? `AND o.profile_id IN (${chunk.map(() => "?").join(",")})` : ""}
        ORDER BY o.observed_at ASC,o.id ASC LIMIT ? OFFSET ?`).bind(...(chunk ?? []), size, offset).all<Record<string, unknown>>();
      for (const row of batch.results) {
        const payload = decode(row.payload);
        const encounterId = Number(payload?.encounterId);
        if (!payload || payload.success !== true || !Number.isInteger(encounterId) || encounterId <= 0) continue;
        const profile = String(row.profile_id);
        const bosses = out.get(profile) ?? new Map<number, BossKill>();
        out.set(profile, bosses);
        const at = Number(row.observed_at) || 0;
        const seen = bosses.get(encounterId);
        if (seen) { seen.kills++; seen.firstAt = Math.min(seen.firstAt, at); continue; }
        const instanceId = Number(payload.instanceId);
        bosses.set(encounterId, { encounterId, name: text(payload.name, 150), instanceId: Number.isInteger(instanceId) && instanceId > 0 ? instanceId : null,
          instanceName: text(payload.instanceName, 150), firstAt: at, kills: 1 });
      }
      if (batch.results.length < size) break;
    }
  }
  return new Map([...out].map(([profile, bosses]) => [profile, [...bosses.values()]]));
}

/** Boss kills grouped by instance, the furthest progress first. Several characters' kills merge; the earliest first kill wins. */
export function raidProgress(kills: Iterable<BossKill>): RaidProgress[] {
  const raids = new Map<string, RaidProgress & { byBoss: Map<number, BossKill> }>();
  for (const kill of kills) {
    const name = kill.instanceName ?? "?";
    const key = kill.instanceId != null ? `id:${kill.instanceId}` : `name:${fold(name)}`;
    const raid = raids.get(key) ?? { instanceId: kill.instanceId, instanceName: name, bosses: [], byBoss: new Map() };
    raids.set(key, raid);
    const seen = raid.byBoss.get(kill.encounterId);
    if (seen) { seen.kills += kill.kills; seen.firstAt = Math.min(seen.firstAt, kill.firstAt); }
    else raid.byBoss.set(kill.encounterId, { ...kill });
  }
  return [...raids.values()].map(({ byBoss, ...raid }) => ({ ...raid, bosses: [...byBoss.values()].sort((a, b) => a.firstAt - b.firstAt || a.encounterId - b.encounterId) }))
    .sort((a, b) => b.bosses.length - a.bosses.length || a.instanceName.localeCompare(b.instanceName));
}

type Built = { summary: Omit<GuildSummary, "rank">; members: Entry[]; kills: BossKill[]; bossesBy: Map<string, number> };

/** Every guild that public characters show, with what its shown members did. */
async function buildGuilds(db: Db, runs: readonly Run[]): Promise<Map<string, Built>> {
  const board = await levelBoard(db, new URLSearchParams());
  const shown = board.filter(e => e.guild && e.character.name);
  const kills = await publicBossKills(db, shown.map(e => e.character.id));
  const done = new Map<string, number>(), last = new Map<string, number>();
  for (const run of runs) {
    const id = run.character?.id;
    if (!id) continue;
    if (completed(run)) done.set(id, (done.get(id) ?? 0) + 1);
    if (typeof run.startedAt === "number") last.set(id, Math.max(last.get(id) ?? 0, run.startedAt));
  }
  const groups = new Map<string, { name: string; realm: string | null; members: Entry[] }>();
  for (const entry of shown) {
    const key = guildKey(entry.character.realm, entry.guild!);
    const group = groups.get(key) ?? { name: entry.guild!, realm: entry.character.realm ?? null, members: [] };
    group.members.push(entry);
    groups.set(key, group);
  }
  const out = new Map<string, Built>();
  for (const [key, group] of groups) {
    const levels = group.members.map(m => m.character.level).filter((l): l is number => typeof l === "number");
    const items = group.members.map(m => m.itemLevel).filter((l): l is number => typeof l === "number");
    const factions = new Map<Faction, number>();
    for (const m of group.members) { const f = factionOf(m.character.raceId ?? null); if (f) factions.set(f, (factions.get(f) ?? 0) + 1); }
    const faction = [...factions].sort((a, b) => b[1] - a[1])[0]?.[0] ?? null;
    const guildKills = group.members.flatMap(m => kills.get(m.character.id) ?? []);
    const progress = raidProgress(guildKills);
    const lastAt = Math.max(0, ...group.members.map(m => last.get(m.character.id) ?? 0)) || null;
    out.set(key, {
      members: group.members, kills: guildKills, bossesBy: new Map(group.members.map(m => [m.character.id, kills.get(m.character.id)?.length ?? 0])),
      summary: {
        name: group.name, realm: group.realm, faction, members: group.members.length,
        maxLevel: levels.length ? Math.max(...levels) : null,
        avgLevel: levels.length ? Math.round(levels.reduce((a, b) => a + b, 0) / levels.length) : null,
        itemLevel: items.length ? Math.round(items.reduce((a, b) => a + b, 0) / items.length) : null,
        completions: group.members.reduce((sum, m) => sum + (done.get(m.character.id) ?? 0), 0),
        bosses: progress.reduce((sum, raid) => sum + raid.bosses.length, 0),
        raids: progress.map(raid => ({ instanceName: raid.instanceName, killed: raid.bosses.length })),
        lastAt,
      },
    });
  }
  return out;
}

// Like Raider.IO: raid progress first, then completed runs, then size and level; a stable order last.
const order = (a: Omit<GuildSummary, "rank">, b: Omit<GuildSummary, "rank">) =>
  b.bosses - a.bosses || b.completions - a.completions || b.members - a.members || (b.maxLevel ?? 0) - (a.maxLevel ?? 0) || a.name.localeCompare(b.name);

/** The guild board: filters faction, realm and a search over name and realm; ranks after filtering; 40 per page. */
export async function guildBoard(db: Db, runs: readonly Run[], params: URLSearchParams) {
  const all = [...(await buildGuilds(db, runs)).values()].map(g => g.summary);
  const faction = params.get("faction"), realm = fold(params.get("realm")).replace(/[\s'-]/g, ""), q = fold(params.get("q")).slice(0, 80);
  const filtered = all.filter(g => (!faction || g.faction === faction) && (!realm || fold(g.realm).replace(/[\s'-]/g, "") === realm)
    && (!q || `${fold(g.name)} ${fold(g.realm)}`.includes(q))).sort(order);
  const raw = Number(params.get("page"));
  const page = Number.isFinite(raw) ? Math.max(0, Math.min(10000, Math.floor(raw))) : 0;
  const ranked: GuildSummary[] = filtered.map((g, i) => ({ ...g, rank: i + 1 }));
  return { guilds: ranked.slice(page * PAGE_SIZE, (page + 1) * PAGE_SIZE), total: ranked.length, page, pageSize: PAGE_SIZE,
    hasMore: (page + 1) * PAGE_SIZE < ranked.length, sampleSize: all.reduce((sum, g) => sum + g.members, 0) };
}

/** One guild: its place among all guilds, the shown members, raid progress and the latest runs of its members. Null when nobody shows it. */
export async function guildDetail(db: Db, runs: readonly Run[], realm: string, name: string): Promise<GuildDetail | null> {
  const guilds = await buildGuilds(db, runs);
  const found = guilds.get(guildKey(realm, name));
  if (!found) return null;
  const ordered = [...guilds.values()].map(g => g.summary).sort(order);
  const rank = ordered.indexOf(found.summary) + 1;
  const sameRealm = ordered.filter(g => fold(g.realm).replace(/[\s'-]/g, "") === fold(found.summary.realm).replace(/[\s'-]/g, ""));
  const realmRank = sameRealm.indexOf(found.summary) + 1;
  const ids = new Set(found.members.map(m => m.character.id));
  const done = new Map<string, number>(), last = new Map<string, number>();
  const recent: Run[] = [];
  for (const run of runs) {
    const id = run.character?.id;
    if (!id || !ids.has(id)) continue;
    if (completed(run)) done.set(id, (done.get(id) ?? 0) + 1);
    if (typeof run.startedAt === "number") last.set(id, Math.max(last.get(id) ?? 0, run.startedAt));
    recent.push(run);
  }
  recent.sort((a, b) => (b.startedAt ?? 0) - (a.startedAt ?? 0));
  const roster: GuildMember[] = found.members.map(m => ({ character: m.character, itemLevel: m.itemLevel ?? null,
    completions: done.get(m.character.id) ?? 0, bosses: found.bossesBy.get(m.character.id) ?? 0, lastAt: last.get(m.character.id) ?? null }))
    .sort((a, b) => (b.character.level ?? 0) - (a.character.level ?? 0) || (b.itemLevel ?? -1) - (a.itemLevel ?? -1) || String(a.character.name).localeCompare(String(b.character.name)));
  return { ...found.summary, rank, realmRank, realmTotal: sameRealm.length, roster, progress: raidProgress(found.kills), recent: recent.slice(0, 15) };
}

export type FameEntry = { guild: string; realm: string | null; faction: Faction | null; at: number };
export type FameRaid = { instanceId: number | null; instanceName: string; bosses: { encounterId: number; name: string | null; firsts: FameEntry[] }[] };
/**
 * The hall of fame: for every raid boss, the guilds that defeated it first (their earliest member's kill), three per boss.
 * Only guilds that public characters show; the faction and realm filters apply to the guild.
 */
export async function hallOfFame(db: Db, runs: readonly Run[], params: URLSearchParams): Promise<{ raids: FameRaid[]; guilds: number }> {
  const faction = params.get("faction"), realm = fold(params.get("realm")).replace(/[\s'-]/g, "");
  const guilds = [...(await buildGuilds(db, runs)).values()].filter(g => (!faction || g.summary.faction === faction)
    && (!realm || fold(g.summary.realm).replace(/[\s'-]/g, "") === realm));
  const raids = new Map<string, { instanceId: number | null; instanceName: string; bosses: Map<number, { name: string | null; firsts: FameEntry[] }> }>();
  for (const g of guilds) for (const raid of raidProgress(g.kills)) {
    const key = raid.instanceId != null ? `id:${raid.instanceId}` : `name:${fold(raid.instanceName)}`;
    const into = raids.get(key) ?? { instanceId: raid.instanceId, instanceName: raid.instanceName, bosses: new Map() };
    raids.set(key, into);
    for (const boss of raid.bosses) {
      const row = into.bosses.get(boss.encounterId) ?? { name: boss.name, firsts: [] };
      row.firsts.push({ guild: g.summary.name, realm: g.summary.realm, faction: g.summary.faction, at: boss.firstAt });
      into.bosses.set(boss.encounterId, row);
    }
  }
  const out: FameRaid[] = [...raids.values()].map(raid => ({ instanceId: raid.instanceId, instanceName: raid.instanceName,
    bosses: [...raid.bosses].map(([encounterId, b]) => ({ encounterId, name: b.name, firsts: b.firsts.sort((x, y) => x.at - y.at || x.guild.localeCompare(y.guild)).slice(0, 3) }))
      .sort((a, b) => (a.firsts[0]?.at ?? 0) - (b.firsts[0]?.at ?? 0)) }))
    .sort((a, b) => b.bosses.length - a.bosses.length || a.instanceName.localeCompare(b.instanceName));
  return { raids: out, guilds: guilds.length };
}

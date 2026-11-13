import type { Scope } from "@/lib/contracts";

export type View = "overview" | "runs" | "rankings" | "atlas" | "database" | "professions" | "sync" | "account" | "link";
export type Character = { id: string; name?: string | null; realm?: string | null; classId?: number | null; raceId?: number | null; level?: number | null };
export type CombatMetrics = { damage?: number; healing?: number; overhealing?: number; absorbs?: number; damageTaken?: number; interrupts?: number; dispels?: number; deaths?: number };
export type RunMember = { guid: string; name?: string; classId?: number; raceId?: number; level?: number; role?: string };
export type RunCombat = CombatMetrics & {
  source: "damage_meter" | "combat_log" | "unavailable";
  coverage: "observed" | "partial" | "unavailable";
  coveredMs: number; activeMs: number;
  players: (RunMember & CombatMetrics & { activeMs?: number })[];
};
export type Run = {
  id: string; name: string; instanceId?: number | null; startedAt?: number; durationMs?: number | null; status?: string; completion?: string;
  endedAt?: number | null; difficultyId?: number | null; instanceType?: string | null;
  rankEligible?: boolean; character?: Character | null; bossCount?: number | null; evidence?: string;
  bosses?: { encounterId?: number; name?: string; killedAt?: number; durationMs?: number; splitMs?: number }[]; groupSize?: number | null; minLevel?: number | null; maxLevel?: number | null;
  roster?: RunMember[]; combat?: RunCombat | null;
  deaths?: number | null; rulesetId?: string | null; game?: { product?: string; build?: string; interface?: number; region?: string; realm?: string } | null;
};
export type Entity = { id: string; kind: string; name: string; count: number; lastSeen?: number; payload?: Record<string, unknown>; origin?: "catalog" | "observation"; sourceLabel?: string; isVendor?: boolean; locations?: {mapId:number;mapSystem?:string;x?:number;y?:number;positionMethod?:string;count?:number;lastSeen?:number}[] };
export type Grant = { id: string; producerId: string; scopes: Scope[]; revokedAt: number | null; createdAt: number };
export type Device = { id: string; name: string; scopes: Scope[]; createdAt: number; lastSeenAt: number | null };
export type Profile = Character & { public: boolean };
export type User = { id: string; username: string; displayName: string; avatarUrl: string | null };
export type Status = {
  version: string; user: User | null; totalEvents: number; totalRuns: number; totalCharacters: number; latestAt: number | null;
  auth: { discord: boolean; devLogin: boolean };
};
export type Me = { user: User; grants: Grant[]; profiles: Profile[]; devices: Device[]; eventCount: number; runCount: number };
export type Entry = { rank: number; character: Character; count: number; bestMs?: number | null; value?:number;runId?:string;instanceName?:string };

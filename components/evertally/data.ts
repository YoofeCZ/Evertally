import type { Run } from "./types";

export const CLASSES: Record<number, string> = { 1: "Warrior", 2: "Paladin", 3: "Hunter", 4: "Rogue", 5: "Priest", 6: "Death Knight", 7: "Shaman", 8: "Mage", 9: "Warlock", 10: "Monk", 11: "Druid", 12: "Demon Hunter", 13: "Evoker" };
export const RACES: Record<number, string> = { 1: "Human", 2: "Orc", 3: "Dwarf", 4: "Night Elf", 5: "Undead", 6: "Tauren", 7: "Gnome", 8: "Troll", 9: "Goblin", 10: "Blood Elf", 11: "Draenei", 22: "Worgen", 24: "Pandaren", 25: "Pandaren", 26: "Pandaren" };

export function duration(ms?: number | null): string {
  if (ms == null || !Number.isFinite(ms) || ms < 0) return "—";
  const seconds = Math.floor(ms / 1000);
  const hours = Math.floor(seconds / 3600);
  return `${hours ? `${hours}:` : ""}${String(Math.floor(seconds / 60) % 60).padStart(2, "0")}:${String(seconds % 60).padStart(2, "0")}`;
}

export type RunFilters = Record<string, string>;
const positive = (value: string | undefined) => value && Number.isFinite(Number(value)) && Number(value) > 0 ? Number(value) : null;

export function filterRuns(runs: readonly Run[], filters: RunFilters, query = "", now = Date.now() / 1000): Run[] {
  const needle = query.trim().toLowerCase();
  const min = positive(filters.minLevel), max = positive(filters.maxLevel), days = positive(filters.periodDays);
  return runs.filter((run) => {
    const level = run.character?.level;
    return (!needle || `${run.name} ${run.character?.name ?? ""} ${run.instanceId ?? ""}`.toLowerCase().includes(needle)) &&
      (!filters.instanceId || String(run.instanceId) === filters.instanceId) &&
      (!filters.classId || String(run.character?.classId) === filters.classId) &&
      (!filters.raceId || String(run.character?.raceId) === filters.raceId) &&
      (!filters.difficultyId || String(run.difficultyId) === filters.difficultyId) &&
      (!filters.completion || run.completion === filters.completion) &&
      (!days || typeof run.startedAt === "number" && Number.isFinite(run.startedAt) && run.startedAt >= now - days * 86400 && run.startedAt <= now) &&
      (!min || typeof level === "number" && level >= min) && (!max || typeof level === "number" && level <= max);
  });
}

export function completed(run: Run): boolean {
  return run.status === "completed" && run.evidence !== "manual" && (run.completion === "last_boss" || run.completion === "full_clear");
}

/** Times are comparable only inside one instance, difficulty and finish definition.
 * Each record remains a player's participation, not a deduplicated group run. */
export function summarizeRuns(runs: readonly Run[]) {
  const finishes = runs.filter(completed);
  const candidates = finishes.filter((run) => typeof run.durationMs === "number" && Number.isFinite(run.durationMs) && run.durationMs > 0);
  const definitions = new Set(candidates.map((run) => JSON.stringify([run.instanceId,run.difficultyId,run.completion,run.game?.product,run.game?.build,run.game?.realm??run.character?.realm])));
  const comparable = candidates.length > 0 && definitions.size === 1 && candidates.every((run) => typeof run.instanceId === "number" && run.instanceId > 0 && typeof run.difficultyId === "number" && Number.isFinite(run.difficultyId));
  const times = comparable ? candidates.map((run) => run.durationMs!).sort((a, b) => a - b) : [];
  const midpoint = Math.floor(times.length / 2);
  return {
    visits: runs.length,
    completed: finishes.length,
    unfinished: runs.filter((run) => ["interrupted", "abandoned", "manual"].includes(run.status ?? "")).length,
    timed: times.length,
    comparable,
    bestMs: times[0] ?? null,
    medianMs: times.length ? times.length % 2 ? times[midpoint] : (times[midpoint - 1] + times[midpoint]) / 2 : null,
  };
}

export function elapsedBossTime(run: Run, killedAt?: number): number | null {
  if (typeof run.startedAt !== "number" || !Number.isFinite(run.startedAt) || typeof killedAt !== "number" || !Number.isFinite(killedAt) || killedAt < run.startedAt) return null;
  return (killedAt - run.startedAt) * 1000;
}

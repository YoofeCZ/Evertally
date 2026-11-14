// The leaderboard keeps its whole state in the address, like `#rankings/level?class=3&faction=horde&page=2`,
// so a view can be shared, reloaded and walked with the back button.

// "instances" is the overview of every instance with its record; a click opens the times of that one instance.
export type Metric = "level" | "count" | "time" | "instances" | "dps" | "hps";
export const METRICS: readonly Metric[] = ["level", "count", "time", "instances", "dps", "hps"];
/** Times and combat rates are only comparable inside one instance. */
export const needsInstance = (metric: Metric) => metric === "time" || metric === "dps" || metric === "hps";

export type RankingFilters = { classId?: string; raceId?: string; faction?: string; instanceType?: string; instanceId?: string };
export type RankingState = { metric: Metric; filters: RankingFilters; q: string; page: number };

// address name -> filter key, in the order they are written
const FILTERS: readonly (readonly [string, keyof RankingFilters])[] = [["class", "classId"], ["race", "raceId"], ["faction", "faction"], ["type", "instanceType"], ["instance", "instanceId"]];
const RUN_ONLY: readonly (keyof RankingFilters)[] = ["instanceType", "instanceId"];
const VALID: Record<keyof RankingFilters, RegExp> = {
  classId: /^[1-9]\d{0,2}$/, raceId: /^[1-9]\d{0,2}$/, instanceId: /^[1-9]\d{0,6}$/,
  faction: /^(alliance|horde)$/, instanceType: /^(party|raid)$/,
};
const MAX_PAGE = 10000;
/** Which filters a board understands: the level board knows no runs, the instance overview no single instance. */
const applies = (metric: Metric, key: keyof RankingFilters) => metric === "level" ? !RUN_ONLY.includes(key) : !(metric === "instances" && key === "instanceId");

export function parseRankingRoute(route: string): RankingState {
  const at = route.indexOf("?");
  const path = at < 0 ? route : route.slice(0, at);
  const params = new URLSearchParams(at < 0 ? "" : route.slice(at + 1));
  const head = path.split("/")[0];
  const metric = (METRICS as readonly string[]).includes(head) ? head as Metric : "level";
  const filters: RankingFilters = {};
  for (const [name, key] of FILTERS) {
    const value = params.get(name)?.trim();
    if (value && VALID[key].test(value) && applies(metric, key)) filters[key] = value;
  }
  const page = Number(params.get("page"));
  return {
    metric,
    filters,
    q: (params.get("q") ?? "").trim().slice(0, 80),
    // the address counts pages from 1 for people; the API counts from 0
    page: Number.isInteger(page) && page > 1 ? Math.min(page, MAX_PAGE) - 1 : 0,
  };
}

export function rankingHash(state: RankingState): string {
  const params = new URLSearchParams();
  for (const [name, key] of FILTERS) {
    const value = state.filters[key];
    if (value && applies(state.metric, key)) params.set(name, value);
  }
  if (state.q) params.set("q", state.q);
  if (state.page > 0) params.set("page", String(state.page + 1));
  const query = params.toString();
  return `rankings/${state.metric}${query ? `?${query}` : ""}`;
}

/** The query `/api/leaderboards` understands. */
export function rankingQuery(state: RankingState): string {
  const params = new URLSearchParams({ metric: state.metric, page: String(state.page) });
  if (state.q) params.set("q", state.q);
  for (const [, key] of FILTERS) {
    const value = state.filters[key];
    if (value && applies(state.metric, key)) params.set(key, value);
  }
  return params.toString();
}

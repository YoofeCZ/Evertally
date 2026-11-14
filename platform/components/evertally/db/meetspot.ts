// A fair place to meet: of all flight masters the side may use, the ones where the person with the longest way arrives soonest.
// Travel times are the planner's (walking, flights, boats, zeppelins, portals), so a place across the sea is judged by the boat.
import { reachTimes, type Options, type Place, type Travel } from "./travel";
import type { Flights } from "./store";

export type Suggestion = { id: string; label: string; u: number; v: number; worst: number; total: number; times: { name: string; seconds: number }[] };

export function suggestSpots(travel: Travel, flights: Flights, people: (Place & { name: string })[], options: Options, count = 3): Suggestion[] {
  if (people.length < 2) return [];
  const reach = people.map(person => reachTimes(travel, flights, person, options));
  const out: Suggestion[] = [];
  for (const [id, node] of Object.entries(flights.nodes)) {
    if (node.f && node.f !== options.side) continue;
    const times = reach.map(map => map.get(`taxi${id}`));
    if (times.some(time => time === undefined)) continue;
    const seconds = times as number[];
    out.push({ id, label: node.n, u: node.u, v: node.v, worst: Math.max(...seconds), total: seconds.reduce((a, b) => a + b, 0), times: people.map((person, i) => ({ name: person.name, seconds: seconds[i] })) });
  }
  return out.sort((a, b) => a.worst - b.worst || a.total - b.total).slice(0, count);
}

// Puts real ground under the walking steps of a journey. planJourney (travel.ts) walks between fixed places with baked costs and
// joins free points to the nearest places by straight lines; here every walking leg is searched on the walk mask (terrain.ts) so
// the line goes around mountains and water. Times: a baked walk between two fixed places keeps its baked time (only its line
// changes); a leg from or to a free point, which used to be a straight line times 1.3, now takes the length of the path on the
// mask times GROUND_FACTOR, the factor that makes those lengths agree on average with the baked walks.
import { findPath, type Walk } from "./terrain";
import { fromYards, planJourney, toYards, type Journey, type Leg, type Options, type Place, type Step, type Travel } from "./travel";
import type { Flights } from "./store";

/**
 * Median of (baked yards / yards along the mask) over all 2 781 baked walks between fixed places (tools/check_walkmask.mjs).
 * The baked costs come from a hierarchical search that is not always the shortest way, so this is a calibration, not a
 * claim that the real path is that much longer. platform/tests/ground.test.ts re-measures it.
 */
export const GROUND_FACTOR = 1.18;

type Located = { c: number; x: number; y: number };

function refineLeg(travel: Travel, walk: Walk, leg: Leg, speed: number): Leg & { ground: boolean } {
  if (leg.points.length < 2) return { ...leg, ground: false };
  const a = leg.points[0], b = leg.points[leg.points.length - 1];
  const from: Located = toYards(travel, a[0], a[1]), to: Located = toYards(travel, b[0], b[1]);
  const map = from.c === to.c ? walk.get(from.c) : undefined;
  const found = map ? findPath(map, [from.x, from.y], [to.x, to.y]) : null;
  if (!found) return { ...leg, ground: false };
  const points = found.points.map(([x, y]) => fromYards(travel, from.c, x, y));
  if (!leg.estimated) return { ...leg, points, ground: true }; // a baked walk keeps its baked time and length
  const yards = Math.max(Math.hypot(from.x - to.x, from.y - to.y), found.grid * GROUND_FACTOR);
  return { points, yards, seconds: yards / speed, estimated: true, ground: true };
}

/**
 * The same journey with real ground under every walking step it can find one for. Steps it cannot (no mask for that map, a
 * tram station, an end on blocked ground) keep their straight line and their estimate. Waits and rides are untouched.
 */
export function groundJourney(journey: Journey, travel: Travel, walk: Walk, options: Options): Journey {
  let seconds = journey.seconds;
  const steps = journey.steps.map<Step>(step => {
    if (step.mode !== "walk" || !step.legs?.length) return step;
    const legs = step.legs.map(leg => refineLeg(travel, walk, leg, options.speed));
    const points: [number, number][] = [];
    for (const leg of legs) points.push(...(points.length ? leg.points.slice(1) : leg.points));
    const newSeconds = legs.reduce((sum, leg) => sum + leg.seconds, 0);
    seconds += newSeconds - step.seconds;
    return {
      ...step, points, seconds: newSeconds, yards: legs.reduce((sum, leg) => sum + leg.yards, 0),
      estimated: legs.some(leg => leg.estimated), ground: legs.every(leg => leg.points.length < 2 || leg.ground), legs,
    };
  });
  return { steps, seconds };
}

/** Select the route using terrain costs before drawing the winning walking legs. */
export function planGroundJourney(travel: Travel, flights: Flights, from: Place, to: Place, options: Options, walk: Walk): Journey | null {
  const planned = planJourney(travel, flights, from, to, options, (a, b) => {
    const start = toYards(travel, a[0], a[1]), end = toYards(travel, b[0], b[1]);
    if (start.c !== end.c) return undefined;
    const map = walk.get(start.c);
    if (!map) return undefined;
    const found = findPath(map, [start.x, start.y], [end.x, end.y]);
    return found ? found.grid * GROUND_FACTOR : null;
  });
  return planned ? groundJourney(planned, travel, walk, options) : null;
}

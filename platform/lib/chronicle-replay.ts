import { LOG_KINDS, type Chronicle, type ChronicleEvent, type Fight, type LogLine } from "./chronicle";

export type FightTurn =
  | { t: number; kind: "start" }
  | { t: number; kind: "end" }
  | { t: number; kind: "event"; event: ChronicleEvent }
  | { t: number; kind: "log"; line: LogLine };

/** Actual observations, in order. Boundaries annotate the recorded interval; no attacks or amounts are inferred. */
export function fightTurns(c: Chronicle, index: number): FightTurn[] {
  const f = c.fights?.[index];
  if (!f) return [];
  const turns: FightTurn[] = [{ t: f.t, kind: "start" }];
  const log = f.log ?? [];
  const recorded = new Map<string, number[]>();
  for (const line of log) {
    turns.push({ t: f.t + line[0], kind: "log", line });
    if (f.actors?.[line[1]]?.side !== "me") continue;
    const kind = LOG_KINDS[line[3]], key = `${kind}:${kind === "death" ? "" : f.spells?.[line[4]]?.name ?? ""}`;
    const times = recorded.get(key) ?? [];
    times.push(f.t + line[0]); recorded.set(key, times);
  }
  for (const event of c.events) {
    if (event.k === "state" || event.k === "combat" || event.t < f.t || event.t > f.t + f.d || event.f !== undefined && event.f !== index) continue;
    // A complete log may contain the same own cast/aura/death as the ordinary journey events.
    const matchingKind = event.actorSide === "enemy" || event.actorSide === "party" ? null : event.k === "action" && event.a === "cast" ? "cast" : event.k === "aura" ? "aura" : event.k === "death" ? "death" : null;
    const times = matchingKind ? recorded.get(`${matchingKind}:${matchingKind === "death" ? "" : event.text}`) : undefined;
    if (times) {
      let left = 0, right = times.length;
      while (left < right) { const mid = (left + right) >>> 1; if (times[mid] < event.t - 0.05) left = mid + 1; else right = mid; }
      if (left < times.length && Math.abs(times[left] - event.t) < 0.05) continue;
    }
    turns.push({ t: event.t, kind: "event", event });
  }
  turns.sort((a, b) => a.t - b.t);
  turns.push({ t: f.t + f.d, kind: "end" });
  return turns;
}

/** Stop on a crossed start even at very high journey speeds, including playback begun inside a fight. */
export function crossedFight(fights: readonly Fight[], from: number, to: number, handled: ReadonlySet<number>): number {
  return fights.findIndex((f, i) => !handled.has(i) && f.d > 0 && f.t <= to && f.t + f.d > from);
}

/** Keep each action readable, while compressing long waits between observations. */
export function turnDelay(from: number, to: number): number {
  return Math.max(1100, Math.min(2400, (to - from) * 1000));
}

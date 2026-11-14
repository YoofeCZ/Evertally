import test from "node:test";
import assert from "node:assert/strict";
import { duration, elapsedBossTime, filterRuns, summarizeRuns } from "../components/evertally/data";
import type { Run } from "../components/evertally/types";

const run = (id: string, durationMs?: number | null, extra: Partial<Run> = {}): Run => ({ id, name: "Deadmines", instanceId: 36, difficultyId: 1, status: "completed", completion: "last_boss", startedAt: 1000, durationMs, character: { id: "own", classId: 8, raceId: 7, level: 20 }, ...extra });

test("Observed timing summary never mixes instances, difficulties or finish definitions", () => {
  for (const extra of [{ instanceId: 33 }, { difficultyId: 2 }, { completion: "full_clear" },{game:{realm:"Another realm"}},{game:{build:"Different build"}}]) {
    const summary = summarizeRuns([run("a", 1000), run("b", 2000, extra)]);
    assert.equal(summary.bestMs, null); assert.equal(summary.medianMs, null); assert.equal(summary.timed, 0);
  }
  assert.equal(summarizeRuns([run("unknown-difficulty",1000,{difficultyId:null})]).comparable,false);
  assert.equal(summarizeRuns([run("manual",1000,{evidence:"manual"})]).completed,0);
});
test("Median uses individual completed observations; interrupted and absent times do not become zero", () => {
  const summary = summarizeRuns([run("a", 1000), run("b", 9000), run("c", 3000), run("d", 5000), run("e", null), run("f", 0), run("g", 1, { status: "interrupted" }), run("h", 1, { status: "manual" })]);
  assert.equal(summary.visits, 8); assert.equal(summary.completed, 6); assert.equal(summary.unfinished, 2);
  assert.equal(summary.bestMs, 1000); assert.equal(summary.medianMs, 4000); assert.equal(summary.timed, 4);
  assert.equal(summarizeRuns([run("unknown", null)]).bestMs, null);
  assert.equal(summarizeRuns([run("unknown", 50, { instanceId: null })]).bestMs, null);
});
test("Race, class, historical level and period filters exclude unknown fields instead of treating them as zero", () => {
  const rows = [run("match", 1000, { startedAt: 100000 }), run("old", 1000, { startedAt: 1 }), run("missing", 1000, { character: null }), run("other", 1000, { character: { id: "other", classId: 7, raceId: 6, level: 60 } })];
  assert.deepEqual(filterRuns(rows, { classId: "8", raceId: "7", minLevel: "15", maxLevel: "25", periodDays: "7" }, "deadmines", 700000).map((r) => r.id), ["match"]);
  assert.deepEqual(filterRuns(rows, { minLevel: "60", maxLevel: "20" }), []);
});
test("Missing time differs from zero; invalid boss ordering does not invent a split", () => {
  assert.equal(duration(null), "—"); assert.equal(duration(0), "00:00"); assert.equal(duration(-1), "—"); assert.equal(duration(3661000), "1:01:01");
  assert.equal(elapsedBossTime(run("a", 300000), 1100), 100000);
  assert.equal(elapsedBossTime(run("a", 300000), 900), null);
});

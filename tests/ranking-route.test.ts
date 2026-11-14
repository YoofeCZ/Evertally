import test from "node:test";
import assert from "node:assert/strict";
import { parseRankingRoute, rankingHash, rankingQuery } from "../components/evertally/rankingRoute";
import { factionOf } from "../components/evertally/data";

test("an empty leaderboard address is the level board, first page, no filters", () => {
  assert.deepEqual(parseRankingRoute(""), { metric: "level", filters: {}, q: "", page: 0 });
  assert.equal(rankingHash(parseRankingRoute("")), "rankings/level");
});

test("the address round-trips every filter, the search and a page counted from 1", () => {
  const route = "time?class=3&race=4&faction=alliance&type=party&instance=36&q=%C5%BDofie&page=3";
  const state = parseRankingRoute(route);
  assert.deepEqual(state, { metric: "time", filters: { classId: "3", raceId: "4", faction: "alliance", instanceType: "party", instanceId: "36" }, q: "Žofie", page: 2 });
  assert.equal(rankingHash(state), `rankings/${route}`);
  const api = new URLSearchParams(rankingQuery(state));
  assert.deepEqual(Object.fromEntries(api), { metric: "time", page: "2", q: "Žofie", classId: "3", raceId: "4", faction: "alliance", instanceType: "party", instanceId: "36" });
});

test("broken or foreign values never reach the API", () => {
  const state = parseRankingRoute("bogus?class=abc&race=0&faction=neutral&type=pvp&instance=-1&page=-4&q=" + "x".repeat(200));
  assert.equal(state.metric, "level");
  assert.deepEqual(state.filters, {});
  assert.equal(state.page, 0);
  assert.equal(state.q.length, 80);
  assert.equal(parseRankingRoute("level?page=999999").page, 9999);
});

test("the level board drops instance filters that only apply to runs", () => {
  const state = parseRankingRoute("level?class=1&type=raid&instance=409");
  assert.deepEqual(state.filters, { classId: "1" });
  assert.equal(rankingHash({ ...state, filters: { classId: "1", instanceId: "409" } }), "rankings/level?class=1");
  assert.equal(new URLSearchParams(rankingQuery({ ...state, filters: { instanceId: "409" } })).has("instanceId"), false);
});

test("a leading slash or a bare query is accepted", () => {
  assert.equal(parseRankingRoute("?class=2").filters.classId, "2");
  assert.equal(parseRankingRoute("dps/").metric, "dps");
});

test("faction follows the race, unaligned Pandaren and unknown races have none", () => {
  assert.equal(factionOf(1), "alliance");
  assert.equal(factionOf(11), "alliance");
  assert.equal(factionOf(2), "horde");
  assert.equal(factionOf(10), "horde");
  assert.equal(factionOf(24), null);
  assert.equal(factionOf(null), null);
  assert.equal(factionOf(999), null);
});

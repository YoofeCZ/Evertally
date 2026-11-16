import test from "node:test";
import assert from "node:assert/strict";
import { crossedFight, fightTurns, turnDelay } from "../lib/chronicle-replay";
import type { Chronicle, Fight } from "../lib/chronicle";

const fight: Fight = { t: 2, d: 12, name: "Plainstrider", kind: "combat", result: "kill", me: { dealt: [], healed: [], took: [] } };
const chronicle: Chronicle = { v: 1, character: { name: "Recorder", classId: 1, level: 6 }, startedAt: 1, duration: 20, zones: ["mulgore"], path: [], fights: [fight], events: [
  { t: 1, k: "action", a: "jump", text: "Jumped" },
  { t: 2, k: "combat", a: "start", text: fight.name, f: 0 },
  { t: 3, k: "state", text: "Character state" },
  { t: 4, k: "action", a: "cast", text: "Heroic Strike", f: 0 },
  { t: 4, k: "action", a: "cast_failed", text: "Heroic Strike", f: 0 },
  { t: 5, k: "action", a: "cast", text: "Another fight", f: 1 },
  { t: 13, k: "kill", text: fight.name, xp: 52, f: 0 },
  { t: 14, k: "combat", a: "end", text: fight.name, f: 0 },
] };

test("turns preserve exact action order and unknown measurements without inventing enemy hits", () => {
  const turns = fightTurns(chronicle, 0);
  assert.deepEqual(turns.map(t => [t.t, t.kind]), [[2,"start"],[4,"event"],[4,"event"],[13,"event"],[14,"end"]]);
  assert.equal(turns.filter(t => t.kind === "log").length, 0);
  assert.deepEqual(chronicle.fights![0].me, {dealt:[], healed:[], took:[]});
});
test("the real log keeps both actors and amounts and deduplicates only matching own observations", () => {
  const c: Chronicle = { ...chronicle, fights: [{ ...fight, actors: [{name:"Recorder",side:"me"},{name: fight.name,side:"enemy"}], spells:[{name:"Heroic Strike"}], log:[[2,0,1,2,0,0,0],[2.1,1,0,0,-1,12,0]] }] };
  const turns = fightTurns(c,0);
  assert.equal(turns.filter(t=>t.kind==="event" && t.event.a==="cast").length,0);
  assert.equal(turns.filter(t=>t.kind==="event" && t.event.a==="cast_failed").length,1);
  assert.deepEqual(turns.filter(t=>t.kind==="log").map(t=>t.line),c.fights![0].log);
});
test("fast playback cannot skip a short fight, and a dismissed or finished fight does not reopen", () => {
  assert.equal(crossedFight([fight],0,80,new Set()),0);
  assert.equal(crossedFight([fight],5,6,new Set()),0);
  assert.equal(crossedFight([fight],5,6,new Set([0])),-1);
  assert.equal(crossedFight([fight],14,20,new Set()),-1);
  assert.equal(crossedFight([fight],0,1,new Set()),-1);
});
test("simultaneous actions have readable delays and long gaps do not stall the replay", () => {
  assert.equal(turnDelay(4,4),1100);
  assert.equal(turnDelay(4,5.5),1500);
  assert.equal(turnDelay(4,400),2400);
});

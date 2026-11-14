import test from "node:test";
import assert from "node:assert/strict";
import { averageItemLevel, itemLevels, type ItemLevelInfo } from "../lib/item-level";
import { rankingExtras, rankingPackage, rankPublicLevels, withRankingExtras } from "../lib/run-rankings";
import { fixture } from "./sqlite-db";
import type { Entry } from "../components/evertally/types";

const table = new Map<number, ItemLevelInfo>([[100, { level: 60, twoHand: false }], [200, { level: 70, twoHand: true }], [300, { level: 1, twoHand: false }]]);
const SLOTS = [1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18];

test("item level averages the 17 gear slots, ignores shirt and tabard, counts an empty slot as 0", () => {
  assert.equal(averageItemLevel(SLOTS.map(slot => ({ slot, itemId: 100 })), table), 60);
  // shirt (4) and tabard (19) never count, even with a high item
  assert.equal(averageItemLevel([...SLOTS.map(slot => ({ slot, itemId: 100 })), { slot: 4, itemId: 200 }, { slot: 19, itemId: 200 }], table), 60);
  // one empty slot: 16 × 60 / 17 = 56.47 → 56
  assert.equal(averageItemLevel(SLOTS.filter(s => s !== 18).map(slot => ({ slot, itemId: 100 })), table), 56);
});

test("a two-handed weapon also fills an empty off hand, but not a filled one", () => {
  const rest = SLOTS.filter(s => s !== 16 && s !== 17).map(slot => ({ slot, itemId: 100 }));
  assert.equal(averageItemLevel([...rest, { slot: 16, itemId: 200 }], table), Math.floor((15 * 60 + 140) / 17));
  assert.equal(averageItemLevel([...rest, { slot: 16, itemId: 200 }, { slot: 17, itemId: 300 }], table), Math.floor((15 * 60 + 70 + 1) / 17));
});

test("unknown gear or no gear gives no number rather than a wrong one", () => {
  assert.equal(averageItemLevel([{ slot: 1, itemId: 100 }, { slot: 2, itemId: 999 }], table), null);
  assert.equal(averageItemLevel([], table), null);
  assert.equal(averageItemLevel([{ slot: 4, itemId: 100 }], table), null);
});

test("the generated table parses and knows real items", () => {
  const real = itemLevels();
  assert.ok(real.size > 10000);
  // Destiny (647) is a level 57 two-handed sword in the website's item index
  assert.deepEqual(real.get(647), { level: 57, twoHand: true });
});

function world() {
  const f = fixture([["a", "Ayla"], ["b", "Bram"], ["c", "Cora"]]);
  f.sql.exec(`UPDATE atlas_profiles SET public=1, level=60;`);
  const observe = f.sql.prepare("INSERT INTO atlas_observations(id,user_id,producer_id,event_id,grant_id,kind,scope,observed_at,profile_id,payload,game,evidence) VALUES(?,?,?,?,?,?,?,?,?,?,'{}','api_snapshot')");
  let n = 0;
  const add = (user: string, kind: string, scope: string, at: number, payload: unknown) => observe.run(`o${++n}`, user, "src-" + user, `e${n}`, "grant-" + user, kind, scope, at, "p-" + user, JSON.stringify(payload));
  const gear = (itemId: number) => ({ equipped: [{ slot: 1, itemId }, { slot: 5, itemId }], bags: [], stats: {}, talents: [], professions: [] });
  return { ...f, add, gear };
}

test("item level and guild show only for a public character whose player turned them on", async () => {
  const w = world();
  // 647 = level 57: two of 17 slots → floor(114 / 17) = 6; the newest snapshot wins
  w.add("a", "armory.snapshot", "own_character", 100, w.gear(647));
  w.add("a", "armory.snapshot", "own_character", 50, w.gear(1));
  w.add("a", "guild.snapshot", "guild_share", 100, { guildName: "Dawn Watch", rankIndex: 3 });
  w.add("b", "armory.snapshot", "own_character", 100, w.gear(647));
  w.add("b", "guild.snapshot", "guild_share", 100, { guildName: "Hidden Guild", rankIndex: 1 });
  w.add("c", "armory.snapshot", "own_character", 100, w.gear(647));
  w.sql.exec(`UPDATE atlas_profiles SET show_item_level=1, show_guild=1 WHERE user_id IN ('a','c');
    UPDATE atlas_profiles SET public=0 WHERE user_id='c';`);
  const extras = await rankingExtras(w.db, ["p-a", "p-b", "p-c"]);
  assert.deepEqual(extras.get("p-a"), { itemLevel: 6, guild: "Dawn Watch" });
  assert.equal(extras.has("p-b"), false, "b did not turn the details on");
  assert.equal(extras.has("p-c"), false, "c is private");
});

test("a revoked grant, a missing scope or leaving the guild hides the detail", async () => {
  const w = world();
  w.sql.exec(`UPDATE atlas_profiles SET show_item_level=1, show_guild=1;`);
  w.add("a", "armory.snapshot", "own_character", 100, w.gear(647));
  w.sql.exec(`UPDATE atlas_grants SET revoked_at=5 WHERE user_id='a';`);
  w.add("b", "guild.snapshot", "guild_share", 100, { guildName: "Old Guild", rankIndex: 2 });
  w.sql.prepare("UPDATE atlas_grants SET scopes=? WHERE user_id='b'").run(JSON.stringify(["own_character"]));
  w.add("c", "guild.snapshot", "guild_share", 100, { guildName: "Gone", rankIndex: 2 });
  w.add("c", "guild.snapshot", "guild_share", 200, { left: true });
  assert.equal((await rankingExtras(w.db, ["p-a", "p-b", "p-c"])).size, 0);
});

test("equal levels are ordered by the item level of those who show it, and run boards get the extras per page", async () => {
  const w = world();
  w.add("b", "armory.snapshot", "own_character", 100, w.gear(647));
  w.sql.exec(`UPDATE atlas_profiles SET show_item_level=1 WHERE user_id='b';`);
  for (const user of ["a", "b", "c"]) w.addTrack(user, 1000);
  const board = await rankPublicLevels(w.db, new URLSearchParams());
  assert.deepEqual(board.entries.map(e => [e.character.id, e.itemLevel]), [["p-b", 6], ["p-a", undefined], ["p-c", undefined]]);
  const entries: Entry[] = [{ rank: 1, count: 1, character: { id: "p-b" } }, { rank: 2, count: 1, character: { id: "p-a" } }];
  const page = await withRankingExtras(w.db, { entries });
  assert.equal(page.entries[0].itemLevel, 6);
  assert.equal(page.entries[1].itemLevel, undefined);
});

test("the game package lists the public board with class places and no identifiers", async () => {
  const w = world();
  w.sql.exec(`UPDATE atlas_profiles SET class_id=11 WHERE user_id IN ('a','b'); UPDATE atlas_profiles SET class_id=1, level=59 WHERE user_id='c';
    UPDATE atlas_profiles SET show_item_level=1, show_guild=1 WHERE user_id='a';`);
  w.add("a", "armory.snapshot", "own_character", 100, w.gear(647));
  w.add("a", "guild.snapshot", "guild_share", 100, { guildName: "Dawn Watch", rankIndex: 3 });
  for (const user of ["a", "b", "c"]) w.addTrack(user, 1000);
  const runs = [{ id: "r1", name: "Deadmines", status: "completed", completion: "last_boss", evidence: "api_event", character: { id: "p-b" } }];
  const pkg = await rankingPackage(w.db, runs, 1000);
  assert.equal(pkg.kind, "evertally-ranking");
  assert.equal(pkg.expiresAt - pkg.generatedAt, 3 * 86400);
  assert.deepEqual(pkg.players.map(p => [p.name, p.rank, p.classRank, p.completed, p.itemLevel ?? null, p.guild ?? null]),
    [["Ayla", 1, 1, 0, 6, "Dawn Watch"], ["Bram", 2, 2, 1, null, null], ["Cora", 3, 1, 0, null, null]]);
  assert.ok(!JSON.stringify(pkg).includes("p-a"), "no profile ids");
  w.sql.exec(`UPDATE atlas_profiles SET public=0 WHERE user_id='b'`);
  assert.deepEqual((await rankingPackage(w.db, runs, 1000)).players.map(p => p.name), ["Ayla", "Cora"]);
});

test("the leaderboard search finds a guild only where its player shows it", async () => {
  const w = world();
  w.add("a", "guild.snapshot", "guild_share", 100, { guildName: "Dawn Watch", rankIndex: 3 });
  w.add("b", "guild.snapshot", "guild_share", 100, { guildName: "Dawn Riders", rankIndex: 3 });
  w.sql.exec(`UPDATE atlas_profiles SET show_guild=1 WHERE user_id='a';`);
  for (const user of ["a", "b", "c"]) w.addTrack(user, 1000);
  assert.deepEqual((await rankPublicLevels(w.db, new URLSearchParams({ q: "dawn" }))).entries.map(e => e.character.name), ["Ayla"]);
});

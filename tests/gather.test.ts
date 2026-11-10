import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { gatherColor, placeGather, type GatherFile } from "../components/evertally/db/gatherData";
import type { World } from "../components/evertally/db/store";

const read = <T,>(name: string) => JSON.parse(readFileSync(`public/media/${name}`, "utf8")) as T;
const file = read<GatherFile>("gather/gather.json");
const world = read<World>("world/world.json");

test("Sbírání: známé suroviny existují, mají minimální dovednost a body", () => {
  const byName = new Map(file.nodes.map(node => [node.name, node]));
  for (const name of ["Peacebloom", "Silverleaf", "Dreamfoil", "Copper Vein", "Mithril Deposit"]) assert.ok(byName.has(name), `${name} missing`);
  assert.ok((byName.get("Peacebloom")?.skill ?? 999) < (byName.get("Dreamfoil")?.skill ?? 0));
  assert.ok(file.nodes.length >= 60);
  assert.equal(new Set(file.nodes.map(node => node.key)).size, file.nodes.length);
  for (const node of file.nodes) {
    assert.ok(node.n > 0, `${node.key} has no points`);
    const total = Object.values(file.points[node.key]).reduce((sum, flat) => sum + flat.length / 2, 0);
    assert.equal(total, node.n, `${node.key}: count differs`);
  }
});
test("Sbírání: souřadnice jsou celá tisíciny mapy a leží uvnitř ní", () => {
  for (const [key, maps] of Object.entries(file.points)) for (const [map, flat] of Object.entries(maps)) {
    assert.equal(flat.length % 2, 0, `${key}/${map} has an odd coordinate count`);
    for (const value of flat) assert.ok(Number.isInteger(value) && value >= 0 && value <= 1000, `${key}/${map}: ${value}`);
  }
});
test("Sbírání: body se umístí na světovou mapu; nezařazené jsou jen na ostrově, který svět nezná", () => {
  const { points, unplaced } = placeGather(file, world);
  const total = file.nodes.reduce((sum, node) => sum + node.n, 0);
  let placed = 0;
  for (const flat of points.values()) {
    placed += flat.length / 2;
    for (const value of flat) assert.ok(value >= 0 && value <= 1, `outside the world: ${value}`);
  }
  assert.equal(placed + unplaced, total);
  // exactly the points on maps the world does not carry (Zephras Isle, UiMap 2521) stay unplaced
  const known = new Set(Object.values(world.maps).map(entry => String(entry.ui)));
  const offWorld = Object.values(file.points).flatMap(maps => Object.entries(maps)).filter(([map]) => !known.has(map));
  assert.deepEqual([...new Set(offWorld.map(([map]) => map))], ["2521"]);
  assert.equal(unplaced, offWorld.reduce((sum, [, flat]) => sum + flat.length / 2, 0));
  assert.ok(placed / total > 0.95, `only ${placed}/${total} placed`);
});
test("Barvy: rudy mají barvu svého kovu a bylinky se opakují jen po vyčerpání palety", () => {
  const ore = (name: string) => gatherColor({ key: name, name, type: "ore", skill: 1, n: 1 }, 0);
  assert.notEqual(ore("Copper Vein"), ore("Gold Vein"));
  assert.equal(ore("Copper Vein"), "#d9824a");
  const herbs = new Set(Array.from({ length: 12 }, (_, i) => gatherColor({ key: `h${i}`, name: `h${i}`, type: "herb", skill: 1, n: 1 }, i)));
  assert.equal(herbs.size, 12);
});

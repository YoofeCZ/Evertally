import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { PROFESSIONS, spawnsOf, trainersFor, vendorsFor, type Services } from "../components/evertally/db/serviceData";
import type { World } from "../components/evertally/db/store";

const read = <T,>(name: string) => JSON.parse(readFileSync(`public/media/${name}`, "utf8")) as T;
const services = read<Services>("db/services.json");
const world = read<World>("world/world.json");

test("Každá profese má trenéry na mapě; neumístěný trenér je jen na zóně, kterou svět nezná (Zephras Isle)", () => {
  for (const profession of PROFESSIONS) {
    const trainers = [...trainersFor(services, [profession]).keys()];
    const placed = trainers.filter(id => spawnsOf(services, id, world).length > 0);
    assert.ok(placed.length >= 8, `${profession}: only ${placed.length} placed`);
    for (const id of trainers.filter(id => !placed.includes(id))) {
      for (const [zone] of services.pos[String(id)]) assert.equal(zone, "zephras-isle", `NPC ${id} sits in unknown zone ${zone}`);
    }
  }
});
test("Trenér jedné profese se v seznamu druhé neobjeví jen kvůli názvu obchodu", () => {
  const alchemy = new Set(trainersFor(services, ["alchemy"]).keys());
  const mining = new Set(trainersFor(services, ["mining"]).keys());
  assert.equal([...alchemy].filter(id => mining.has(id)).length, 0);
});
test("Vendoři podle regeantu: libovolný vs. všechny vybrané", () => {
  const [a, b] = Object.entries(services.sells).filter(([, vendors]) => vendors.length >= 2).slice(0, 2).map(([item]) => Number(item));
  const any = vendorsFor(services, [a, b], "any");
  const all = vendorsFor(services, [a, b], "all");
  assert.ok(any.size >= all.size);
  for (const [, sold] of all) assert.deepEqual([...sold].sort(), [a, b].sort());
  for (const npc of services.sells[String(a)]) assert.ok(any.has(npc));
  assert.equal(vendorsFor(services, [], "any").size, 0);
  assert.equal(vendorsFor(services, [-1], "any").size, 0);
});
test("Rychlý výběr obsahuje jen věci, které někdo prodává, a každý prodavač má pozici", () => {
  assert.ok(services.quick.length >= 8);
  for (const item of services.quick) assert.ok((services.sells[String(item)] ?? []).length > 0);
  for (const vendors of Object.values(services.sells)) for (const npc of vendors) assert.ok(services.pos[String(npc)]?.length, `NPC ${npc} has no spawn`);
});
test("Souřadnice trenérů leží uvnitř svých map", () => {
  for (const id of trainersFor(services, [...PROFESSIONS]).keys()) for (const [zone, x, y] of services.pos[String(id)]) {
    assert.ok(x >= 0 && x <= 100 && y >= 0 && y <= 100, `${id} in ${zone}: ${x},${y}`);
  }
});

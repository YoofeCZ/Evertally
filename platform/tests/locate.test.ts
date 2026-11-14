import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { locate } from "../components/evertally/db/locate";
import { zoneToWorld, type World } from "../components/evertally/db/store";

const world = JSON.parse(readFileSync("public/media/world/world.json", "utf8")) as World;

test("Bod v zóně se převede na UiMap a pozici 0..1 a zpět na stejný bod", () => {
  const [key, entry] = Object.entries(world.maps).find(([, e]) => e.kind === "zone" && e.ui === 1429)!;
  const [u, v] = zoneToWorld(entry.rect, 40, 65);
  const found = locate(world, u, v)!;
  assert.equal(found.mapId, 1429);
  assert.equal(found.key, key);
  assert.ok(Math.abs(found.x - 0.4) < 1e-3 && Math.abs(found.y - 0.65) < 1e-3);
  const [u2, v2] = zoneToWorld(entry.rect, found.x * 100, found.y * 100);
  assert.ok(Math.abs(u2 - u) < 1e-4 && Math.abs(v2 - v) < 1e-4);
});
test("Na moři mimo všechny zóny se nic nenajde; uvnitř menší mapy vyhrává ta menší", () => {
  assert.equal(locate(world, -1, -1), null);
  for (const [, entry] of Object.entries(world.maps).filter(([, e]) => e.kind === "city").slice(0, 5)) {
    const centre = locate(world, (entry.rect[0] + entry.rect[1]) / 2, (entry.rect[2] + entry.rect[3]) / 2)!;
    const found = world.maps[centre.key];
    assert.ok(found.kind === "city" || found.kind === "zone");
    assert.ok((found.rect[1] - found.rect[0]) * (found.rect[3] - found.rect[2]) <= (entry.rect[1] - entry.rect[0]) * (entry.rect[3] - entry.rect[2]) + 1e-12);
  }
});

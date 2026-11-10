import test from "node:test";
import assert from "node:assert/strict";
import type { Entity } from "../components/evertally/types";
import { clampMapView, clusterPins, entityLocations, entityMapKeys, parseActivity, parseMapCatalog, resolveMap, safeMapEntity, worldPins } from "../components/evertally/world-map";

const catalog = () => parseMapCatalog({ schemaVersion: 1, maps: [
  { key: "dun-morogh", nameEn: "Dun Morogh", nameCs: "Dun Morogh", image: "/media/maps/dun-morogh.webp", width: 1002, height: 668, uiMapIds: [1426], legacyAreaIds: [1] },
  { key: "durotar", nameEn: "Durotar", image: "/media/maps/durotar.webp", width: 1002, height: 668, uiMapIds: [1411], legacyAreaIds: [14] },
] });
const npc = (payload: Record<string, unknown>, extra: Record<string, unknown> = {}): Entity => ({ id: "706", kind: "npc", name: "Frostmane Troll Whelp", count: 2, lastSeen: 1000, payload, ...extra });

test("Map namespaces cannot mistake a legacy area ID for a C_Map ID or pick an ambiguous asset", () => {
  const maps = catalog();
  assert.equal(resolveMap(maps, 1426)?.key, "dun-morogh");
  assert.equal(resolveMap(maps, 1), null);
  assert.equal(resolveMap(maps, 1, "legacy_area")?.key, "dun-morogh");
  assert.equal(resolveMap([...maps, { ...maps[1], uiMapIds: [1426] }], 1426), null);
  assert.deepEqual(entityMapKeys(npc({ mapId: 1426 }), maps), ["dun-morogh"]);
  assert.deepEqual(entityMapKeys(npc({ mapId: 1 }), maps), []);
  assert.deepEqual(entityMapKeys(npc({ mapId: 1, mapSystem: "legacy_area" }), maps), ["dun-morogh"]);
});

test("Map catalogue only permits local explicit cartography assets and unique map keys", () => {
  assert.throws(() => parseMapCatalog({ schemaVersion: 1, maps: [{ ...catalog()[0], image: "https://tracker.example/map.png" }] }));
  assert.throws(() => parseMapCatalog({ schemaVersion: 1, maps: [{ ...catalog()[0], image: "/media/maps/../../secrets.png" }] }));
  assert.throws(() => parseMapCatalog({ schemaVersion: 1, maps: [catalog()[0], catalog()[0]] }));
  assert.throws(() => parseMapCatalog({ schemaVersion: 1, maps: [{ ...catalog()[0], width: 0 }] }));
});

test("Player interaction coordinates never reach map pins or detail projection, including historical quests and vendor records", () => {
  for (const kind of ["npc", "quest", "item"]) {
    const entity = { ...npc({ mapId: 1426, x: 0.3, y: 0.7, positionMethod: "player_interaction" }), kind };
    assert.deepEqual(worldPins([entity], catalog()), []);
    assert.equal(entityLocations(entity)[0].x, undefined);
    assert.equal(entityLocations(entity)[0].y, undefined);
    const detail = safeMapEntity(entity);
    assert.equal(detail.payload?.x, undefined); assert.equal(detail.payload?.y, undefined);
    assert.equal(entity.payload?.x, 0.3, "projection does not mutate the source observation");
  }
  const historical = npc({ mapId: 1426, x: 0.3, y: 0.7, items: [] });
  assert.deepEqual(worldPins([historical], catalog()), []);
  assert.deepEqual(entityMapKeys(historical, catalog()), ["dun-morogh"], "zone-level facts remain useful without player coordinates");
});

test("Only explicit NPC unit positions can become observed pins and invalid coordinates stay unknown", () => {
  const exact = npc({ mapId: 1426, x: 0, y: 0.25, positionMethod: "unit_position" });
  const pins = worldPins([exact], catalog());
  assert.equal(pins.length, 1); assert.equal(pins[0].x, 0); assert.equal(pins[0].y, 0.25); assert.equal(pins[0].reference, false);
  for (const payload of [{ x: 2, y: 0.2 }, { x: 0.5 }, { x: NaN, y: 0.2 }, { x: 0.5, y: Infinity }, { x: 0.5, y: -1 }]) {
    assert.deepEqual(worldPins([npc({ mapId: 1426, positionMethod: "unit_position", ...payload })], catalog()), []);
  }
  assert.deepEqual(worldPins([{ ...exact, kind: "quest" }], catalog()), []);
});

test("Reference NPC spawns require explicit catalog provenance and never count as player observations", () => {
  const payload = { mapId: 1426, mapSystem: "ui_map", x: 0.3, y: 0.7, positionMethod: "npc_database" };
  assert.deepEqual(worldPins([npc(payload)], catalog()), []);
  const reference = npc(payload, { origin: "catalog", sourceLabel: "Reference database", locations: [payload, payload] });
  const pins = worldPins([reference], catalog());
  assert.equal(pins.length, 1); assert.equal(pins[0].count, 0); assert.equal(pins[0].lastSeen, undefined); assert.equal(pins[0].reference, true);
  assert.equal(pins[0].sourceLabel, "Reference database");
});

test("Zone activity enforces at least three contributors and discards all identities and positions", () => {
  const result = parseActivity({ minContributors: 1, windowHours: 24, generatedAt: 1000, zones: [
    { mapId: 1426, mapSystem: "ui_map", contributors: 2, observations: 50 },
    { mapId: 1411, mapSystem: "ui_map", contributors: 3, observations: 12, playerName: "Secret player", userIds: ["secret-id"], x: 0.3, y: 0.7 },
    { mapId: 14, mapSystem: "legacy_area", contributors: 10, observations: 100 },
  ] });
  assert.equal(result.minContributors, 3);
  assert.deepEqual(result.zones, [{ mapId: 1411, contributors: 3, observations: 12 }]);
  assert.equal(JSON.stringify(result).includes("Secret"), false); assert.equal(JSON.stringify(result).includes("secret-id"), false);
  assert.equal(Object.hasOwn(result.zones[0], "x"), false);
  assert.deepEqual(parseActivity({ minContributors: 5, zones: [{ mapId: 1426, mapSystem: "ui_map", contributors: 4 }] }).zones, []);
});

test("Map pan and zoom remain inside the map at every scale, and NPC clusters keep their original positions", () => {
  assert.deepEqual(clampMapView({ zoom: 1, x: 900, y: -900 }, 1000, 600), { zoom: 1, x: 0, y: -0 });
  assert.deepEqual(clampMapView({ zoom: 20, x: 99999, y: -99999 }, 1000, 600), { zoom: 8, x: 3500, y: -2100 });
  assert.deepEqual(clampMapView({ zoom: NaN, x: Infinity, y: NaN }, 1000, 600), { zoom: 1, x: 0, y: 0 });
  const pins = worldPins([npc({ mapId: 1426, x: 0.5, y: 0.5, positionMethod: "unit_position" }), npc({ mapId: 1426, x: 0.51, y: 0.51, positionMethod: "unit_position" }, { id: "707" })], catalog());
  const clusters = clusterPins(pins, 10, 1.5);
  assert.equal(clusters.length, 1); assert.equal(clusters[0].pins.length, 2); assert.equal(clusters[0].x, 0.505);
  assert.equal(clusters[0].pins[0].x, 0.5);
});

import type { Entity } from "./types";

export type MapSystem = "ui_map" | "existing_C_Map" | "legacy_area" | "legacy_map";
export type MapDefinition = {
  key: string; nameEn: string; nameCs: string; image: string; width: number; height: number;
  uiMapIds: number[]; legacyAreaIds: number[]; legacyMapIds: number[]; mapFiles: string[]; continent?: string;
  bounds?: { parentKey: string; x: number; y: number; width: number; height: number };
};
export type MapLocation = {
  mapId: number; mapSystem: MapSystem; x?: number; y?: number; positionMethod: string;
  lastSeen?: number; count: number;
};
export type WorldPin = {
  key: string; entity: Entity; mapKey: string; x: number; y: number; lastSeen?: number; count: number;
  reference: boolean; sourceLabel?: string;
};
export type PinCluster = { key: string; x: number; y: number; pins: WorldPin[] };
export type ZoneActivity = { mapId: number; contributors: number; observations: number; lastSeen?: number };
export type ActivitySnapshot = { generatedAt?: number; windowHours: number; minContributors: number; zones: ZoneActivity[] };
export type MapLayer = "" | "npc" | "quest" | "item" | "vendor";

const object = (value: unknown): Record<string, unknown> | null => value !== null && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : null;
const integer = (value: unknown): value is number => typeof value === "number" && Number.isSafeInteger(value) && value > 0;
const finite = (value: unknown): value is number => typeof value === "number" && Number.isFinite(value);
const coordinate = (value: unknown): value is number => finite(value) && value >= 0 && value <= 1;
const ids = (value: unknown): number[] => Array.isArray(value) ? [...new Set(value.filter(integer))] : [];

/** Static assets are explicitly mapped to game map namespaces, never to arbitrary IDs. */
export function parseMapCatalog(value: unknown): MapDefinition[] {
  const root = object(value);
  if (root?.schemaVersion !== 1 || !Array.isArray(root.maps) || root.maps.length > 1000) throw new Error("Invalid map catalogue");
  const keys = new Set<string>();
  return root.maps.map((value): MapDefinition => {
    const map = object(value);
    if (!map || typeof map.key !== "string" || !/^[a-z0-9][a-z0-9-]{0,79}$/.test(map.key) || keys.has(map.key)
      || typeof map.nameEn !== "string" || !map.nameEn.trim()
      || typeof map.image !== "string" || !/^\/media\/maps\/[a-zA-Z0-9/_-]+\.(?:png|jpe?g|webp)$/.test(map.image)
      || !integer(map.width) || !integer(map.height) || map.width > 32768 || map.height > 32768) throw new Error("Invalid map asset");
    keys.add(map.key);
    const bounds = object(map.bounds);
    const area = bounds && typeof bounds.parentKey === "string" && coordinate(bounds.x) && coordinate(bounds.y)
      && finite(bounds.width) && finite(bounds.height) && bounds.width > 0 && bounds.height > 0
      && bounds.x + bounds.width <= 1.001 && bounds.y + bounds.height <= 1.001
      ? { parentKey: bounds.parentKey, x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height } : undefined;
    return {
      key: map.key, nameEn: map.nameEn.trim(), nameCs: typeof map.nameCs === "string" && map.nameCs.trim() ? map.nameCs.trim() : map.nameEn.trim(),
      image: map.image, width: map.width, height: map.height,
      uiMapIds: ids(map.uiMapIds), legacyAreaIds: ids(map.legacyAreaIds), legacyMapIds: ids(map.legacyMapIds),
      mapFiles: Array.isArray(map.mapFiles) ? map.mapFiles.filter((entry): entry is string => typeof entry === "string" && /^[a-zA-Z0-9_-]+$/.test(entry)) : [],
      ...(typeof map.continent === "string" ? { continent: map.continent } : {}), ...(area ? { bounds: area } : {}),
    };
  });
}

export function resolveMap(maps: readonly MapDefinition[], mapId: number, system: MapSystem = "existing_C_Map"): MapDefinition | null {
  const namespace = system === "legacy_area" ? "legacyAreaIds" : system === "legacy_map" ? "legacyMapIds" : "uiMapIds";
  const matches = maps.filter(map => map[namespace].includes(mapId));
  return matches.length === 1 ? matches[0] : null;
}

/** Older Evertally records used C_Map exclusively, but did not include its namespace. */
export function entityLocations(entity: Entity): MapLocation[] {
  const extended = entity as Entity & { locations?: unknown };
  const source = Array.isArray(extended.locations) && extended.locations.length ? extended.locations : [entity.payload ?? {}];
  const result: MapLocation[] = [];
  for (const raw of source.slice(0, 1000)) {
    const location = object(raw);
    if (!location || !integer(location.mapId)) continue;
    const system = location.mapSystem ?? "existing_C_Map";
    if (!["ui_map", "existing_C_Map", "legacy_area", "legacy_map"].includes(String(system))) continue;
    result.push({
      mapId: location.mapId, mapSystem: system as MapSystem,
      // Player-interaction coordinates are deliberately never projected to the map.
      ...(entity.kind === "npc" && (location.positionMethod === "unit_position" || location.positionMethod === "npc_database" && isReferenceEntity(entity)) && coordinate(location.x) && coordinate(location.y)
        ? { x: location.x, y: location.y } : {}),
      positionMethod: typeof location.positionMethod === "string" ? location.positionMethod : "unknown",
      count: integer(location.count) ? location.count : 1,
      ...(finite(location.lastSeen ?? location.observedAt ?? entity.lastSeen) ? { lastSeen: (location.lastSeen ?? location.observedAt ?? entity.lastSeen) as number } : {}),
    });
  }
  return result;
}

export function matchesMapLayer(entity: Entity, layer: string): boolean {
  const vendor = Array.isArray(entity.payload?.items) || (entity as Entity & { isVendor?: boolean }).isVendor === true;
  if (!layer) return true;
  return layer === "vendor" ? entity.kind === "npc" && vendor : entity.kind === layer;
}

export function isReferenceEntity(entity: Entity): boolean { return (entity as Entity & { origin?: string }).origin === "catalog"; }

export function entityMapKeys(entity: Entity, maps: readonly MapDefinition[]): string[] {
  return [...new Set(entityLocations(entity).map(location => resolveMap(maps, location.mapId, location.mapSystem)?.key).filter((key): key is string => Boolean(key)))];
}

export function worldPins(entities: readonly Entity[], maps: readonly MapDefinition[]): WorldPin[] {
  const result = new Map<string, WorldPin>();
  for (const entity of entities) for (const location of entityLocations(entity)) {
    const reference = isReferenceEntity(entity);
    if (entity.kind !== "npc" || !(location.positionMethod === "unit_position" || reference && location.positionMethod === "npc_database") || location.x === undefined || location.y === undefined) continue;
    const map = resolveMap(maps, location.mapId, location.mapSystem);
    if (!map) continue;
    const key = `${reference ? "catalog" : "observation"}:${entity.kind}:${entity.id}:${map.key}:${location.x}:${location.y}`;
    const previous = result.get(key);
    if (previous && !reference) { previous.count += location.count; previous.lastSeen = Math.max(previous.lastSeen ?? 0, location.lastSeen ?? 0) || undefined; }
    else if (previous) continue;
    else result.set(key, { key, entity, mapKey: map.key, x: location.x, y: location.y, count: reference ? 0 : location.count, lastSeen: reference ? undefined : location.lastSeen, reference, sourceLabel: typeof (entity as Entity & { sourceLabel?: string }).sourceLabel === "string" ? (entity as Entity & { sourceLabel: string }).sourceLabel : undefined });
  }
  return [...result.values()];
}

/** Clusters represent groups of NPC observations, never player locations. */
export function clusterPins(pins: readonly WorldPin[], columns: number, ratio: number): PinCluster[] {
  const cells = new Map<string, WorldPin[]>();
  const cols = Math.max(1, Math.floor(columns)), rows = Math.max(1, Math.floor(cols / Math.max(0.1, ratio)));
  for (const pin of pins) {
    const key = `${Math.min(cols - 1, Math.floor(pin.x * cols))}:${Math.min(rows - 1, Math.floor(pin.y * rows))}`;
    const cell = cells.get(key); if (cell) cell.push(pin); else cells.set(key, [pin]);
  }
  return [...cells].map(([key, group]) => ({ key, x: group.reduce((total, pin) => total + pin.x, 0) / group.length, y: group.reduce((total, pin) => total + pin.y, 0) / group.length, pins: group }));
}

/** Whitelist zone totals only. No identity, coordinate or tracking field survives. */
export function parseActivity(value: unknown): ActivitySnapshot {
  const input = object(value);
  if (!input || !Array.isArray(input.zones)) throw new Error("Invalid zone activity");
  const threshold = Math.max(3, integer(input.minContributors) ? input.minContributors : 3);
  const zones: ZoneActivity[] = [];
  for (const raw of input.zones.slice(0, 1000)) {
    const zone = object(raw);
    if (!zone || !integer(zone.mapId) || zone.mapSystem !== "ui_map" || !integer(zone.contributors) || zone.contributors < threshold) continue;
    const observations = zone.observations ?? zone.observationCount;
    zones.push({ mapId: zone.mapId, contributors: zone.contributors, observations: integer(observations) ? observations : 0, ...(finite(zone.lastSeen) ? { lastSeen: zone.lastSeen } : {}) });
  }
  return { zones, minContributors: threshold, windowHours: integer(input.windowHours) ? input.windowHours : 24, ...(finite(input.generatedAt) ? { generatedAt: input.generatedAt } : {}) };
}

export type MapView = { zoom: number; x: number; y: number };
export function clampMapView(view: MapView, width: number, height: number): MapView {
  const zoom = Math.min(8, Math.max(1, Number.isFinite(view.zoom) ? view.zoom : 1));
  const limitX = Math.max(0, width) * (zoom - 1) / 2, limitY = Math.max(0, height) * (zoom - 1) / 2;
  return { zoom, x: Math.max(-limitX, Math.min(limitX, Number.isFinite(view.x) ? view.x : 0)), y: Math.max(-limitY, Math.min(limitY, Number.isFinite(view.y) ? view.y : 0)) };
}

export function safeMapEntity(entity: Entity): Entity {
  const payload = { ...(entity.payload ?? {}) };
  if (entity.kind !== "npc" || payload.positionMethod !== "unit_position") { delete payload.x; delete payload.y; }
  return { ...entity, payload };
}

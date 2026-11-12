"use client";
// Data layer for the reference database: small JSON shards under /media/db, cached for the session.
import { useEffect, useMemo, useState } from "react";
import { parseMapCatalog, type MapDefinition } from "../world-map";
import { parseWalk, type Walk } from "./terrain";
import type { Travel } from "./travel";

// ---- compact search rows (see tools/build_db.py) -------------------------------------------
export type ItemRow = [id: number, name: string, quality: number | null, ilvl: number | null, req: number | null, cat: number, slot: number, shard: number, lite: 0 | 1, iconFileId?: number | null];
export type NpcRow = [id: number, name: string, lvlMin: number, lvlMax: number, rank: number, services: string[], spawns: 0 | 1, shard: number, zone: string | null];
export type QuestRow = [id: number, name: string, lvl: number | null, req: number | null, zoneOrSort: string | null, faction: string, shard: number];
export type Search = { items: ItemRow[]; npcs: NpcRow[]; quests: QuestRow[]; cats: string[]; slots: string[] };

// ---- detail records -------------------------------------------------------------------------
export type Span = [text: string, cls?: string | null, item?: number];
export type TipRow = ["L", Span[]] | ["C", Span[], Span[]] | ["M", number, number, number] | ["S"];
export type ItemDetail = {
  id: number; name: string; q?: number; ilvl?: number; req?: number; cat?: string; slot?: string; sub?: string; tip?: TipRow[]; icon?: string;
  bosses?: string[]; chance?: number; change?: string[]; status?: string; wh?: string; lite?: 1;
  src: { k: string; n: string; key: string }[]; drops?: [number, number?][]; objDrops?: number[]; vendors?: number[]; rewards?: number[]; starts?: number[];
};
export type NpcDetail = {
  id: number; name: string; lvl: [number, number]; sub?: string; zone?: string; friendly?: string; rank?: number; services?: string[];
  starts?: number[]; ends?: number[]; sells?: number[]; drops?: [number, number?][]; kills?: number[]; sp: Record<string, [number, number][]>;
};
export type QuestDetail = {
  id: number; name: string; lvl?: number; req?: number; zone?: string; sort?: string; text?: string[]; fac?: string; races?: string[]; classes?: string[];
  startNpc?: number[]; startObj?: number[]; startItem?: number[]; endNpc?: number[]; endObj?: number[]; kill?: number[]; objObj?: number[]; need?: number[];
  pre?: number[]; next?: number[]; excl?: number[]; child?: number[]; rewards?: number[]; src?: number;
  tips?: string[]; steps?: [type: string, text: string][];
};
export type DungeonBoss = { name: string; npc: number | null; lvl: string | null; rare: boolean; loot: (number | string)[]; note: string | null };
export type DungeonQuest = { id: number; name: string; lvl?: number; req?: number; fac?: string; pickup?: string; turnin?: string; rewards: number[]; choice: boolean };
export type Dungeon = {
  key: string; name: string; type: "dungeon" | "raid"; group: string | null; lvl: [number, number] | null; location: string | null; players: number;
  bosses: DungeonBoss[]; quests: DungeonQuest[]; other: number[]; extras: Record<string, [string, string | null, number | null, string[] | null]>;
  status: string; entrance: { zone: string; x: number; y: number; label?: string; hint?: string } | null; source: string;
};
export type PoiPoint = [id: number, x: number, y: number];
export type ZoneData = { key: string; poi: Record<string, PoiPoint[]>; mobs: PoiPoint[]; names: Record<string, string> };
export type Meta = { counts: Record<string, number>; layers: Record<string, string>; zones: Record<string, { name: string; poi: Record<string, number>; mobs: number }>; sources: { name: string; license: string; use: string }[]; generatedAt: number; shardSize: { items: number; npcs: number; quests: number } };

const cache = new Map<string, Promise<unknown>>();
export function fetchJson<T>(url: string): Promise<T> {
  let entry = cache.get(url) as Promise<T> | undefined;
  if (!entry) {
    entry = fetch(url).then(response => {
      if (!response.ok) throw new Error(`${url}: ${response.status}`);
      return response.json() as Promise<T>;
    });
    entry.catch(() => cache.delete(url)); // retry on the next request
    cache.set(url, entry);
  }
  return entry;
}

export type Async<T> = { data: T | null; loading: boolean; error: boolean };
export function useLoad<T>(key: string | null, load: () => Promise<T>): Async<T> {
  const [state, setState] = useState<{ key: string | null; data: T | null; error: boolean }>({ key: null, data: null, error: false });
  useEffect(() => {
    if (!key) return;
    let live = true;
    load().then(data => live && setState({ key, data, error: false })).catch(() => live && setState({ key, data: null, error: true }));
    return () => { live = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps -- `key` identifies the request
  }, [key]);
  const current = state.key === key;
  return { data: current ? state.data : null, error: current && state.error, loading: Boolean(key) && !(current && (state.data || state.error)) };
}

// ---- seamless world (tools/build_map_data.py): everything in (u, v) on Azeroth's map ----------------------------
export type WorldMapEntry = { ui: number; kind: "world" | "continent" | "zone" | "city"; rect: [l: number, r: number, t: number, b: number]; parent: string | null; level?: [number, number] };
export type World = { schema: 1; size: [number, number]; maps: Record<string, WorldMapEntry> };
export type FlightNode = { n: string; z: string | null; f: "A" | "H" | ""; u: number; v: number };
export type FlightPath = { a: number; b: number; s: number; p: [number, number][] };
export type Flights = { nodes: Record<string, FlightNode>; paths: FlightPath[]; source: string };
export type PlaceEntry = { map: number; name: string; raid: boolean; min: number | null; max: number | null };
export type Place = { u: number; v: number; list: PlaceEntry[] };
export type Transport = { kind: "boat" | "zeppelin" | "airship"; route: string; a: [number, number]; b: [number, number]; faction?: string };
export type Sailing = { kind: string; route: string; pieces: [number, number][][] };
export type Places = { instances: Place[]; unplaced: PlaceEntry[]; transports: Transport[]; sailings: Sailing[]; bosses: Record<string, string[]>; zones: Record<string, string> };
export type Floor = { img: string; name: string | null; wing: string | null };
export type Floors = { maps: Record<string, Floor[]>; keys: Record<string, number> };
export const useWorld = () => useLoad<World>("world", () => fetchJson<World>("/media/world/world.json"));
export const useFlights = () => useLoad<Flights>("flights", () => fetchJson<Flights>("/media/world/flights.json"));
export const usePlaces = () => useLoad<Places>("places", () => fetchJson<Places>("/media/world/places.json"));
let walkLoad: Promise<Walk> | null = null;
/** The walk mask (about 100 KB): fetched the first time a journey needs real ground, then kept. */
export const loadWalk = () => (walkLoad ??= fetch("/media/world/walk.bin").then(response => { if (!response.ok) throw new Error(`walk.bin: ${response.status}`); return response.arrayBuffer(); }).then(parseWalk).catch(error => { walkLoad = null; throw error; }));
export const useWalk = (wanted: boolean) => useLoad<Walk>(wanted ? "walk" : null, loadWalk);
export const useTravel = () => useLoad<Travel>("travel", () => fetchJson<Travel>("/media/world/travel.json"));
export const useFloors = () => useLoad<Floors>("floors", () => fetchJson<Floors>("/media/world/floors.json"));
/** A zone-relative point (percent of its map) on Azeroth's map. */
export const zoneToWorld = (rect: [number, number, number, number], x: number, y: number): [number, number] => [rect[0] + x / 100 * (rect[1] - rect[0]), rect[2] + y / 100 * (rect[3] - rect[2])];

export type Recipe = { id: number; name: string; line: number; skill: [orange: number, yellow: number, green: number, grey: number]; reagents: [item: number, qty: number][]; out?: number; qty?: number; fee?: number; req?: number; scroll?: [item: number, skill: number] };
export type RecipeBook = { professions: Record<string, string>; recipes: Recipe[] };
export const useRecipes = () => useLoad<RecipeBook>("recipes", () => fetchJson<RecipeBook>("/media/db/recipes.json"));
export const useMaps = () => useLoad<MapDefinition[]>("maps", async () => parseMapCatalog(await fetchJson("/media/maps/manifest.json")));
export const useMeta =() => useLoad<Meta>("meta", () => fetchJson<Meta>("/media/db/meta.json"));
export const useDungeonArt = () => useLoad<Record<string, { image: string; source: "client" | "journal" | "floor" | "map" }>>("dungeon-art", () => fetchJson("/media/dungeons/manifest.json"));
export const useDungeons = () => useLoad<{ entries: Dungeon[] }>("dungeons", () => fetchJson("/media/db/dungeons.json"));
export const useObjects = () => useLoad<Record<string, [string, string?, number?, number?]>>("objects", () => fetchJson("/media/db/objects.json"));
export const useZoneData = (key: string | null) => useLoad<ZoneData>(key ? `zone:${key}` : null, () => fetchJson<ZoneData>(`/media/db/zones/${key}.json`));

export type Index = {
  search: Search;
  items: Map<number, ItemRow>; npcs: Map<number, NpcRow>; quests: Map<number, QuestRow>;
};
export function useIndex(): Async<Index> {
  const raw = useLoad<Search>("search", () => fetchJson<Search>("/media/db/search.json"));
  const data = useMemo<Index | null>(() => raw.data && ({
    search: raw.data,
    items: new Map(raw.data.items.map(row => [row[0], row])),
    npcs: new Map(raw.data.npcs.map(row => [row[0], row])),
    quests: new Map(raw.data.quests.map(row => [row[0], row])),
  }), [raw.data]);
  return { data, loading: raw.loading, error: raw.error };
}

async function fromShard<T>(kind: "items" | "npcs" | "quests", shard: number, id: number): Promise<T | null> {
  const records = await fetchJson<Record<string, T>>(`/media/db/${kind}/${shard}.json`);
  return records[String(id)] ?? null;
}
export function useItem(index: Index | null, id: number | null) {
  const row = id && index ? index.items.get(id) : undefined;
  return useLoad<ItemDetail | null>(row ? `item:${id}` : null, () => fromShard<ItemDetail>("items", row![7], id!));
}
export function useNpc(index: Index | null, id: number | null) {
  const row = id && index ? index.npcs.get(id) : undefined;
  return useLoad<NpcDetail | null>(row ? `npc:${id}` : null, () => fromShard<NpcDetail>("npcs", row![7], id!));
}
export function useQuest(index: Index | null, id: number | null) {
  const row = id && index ? index.quests.get(id) : undefined;
  return useLoad<QuestDetail | null>(row ? `quest:${id}` : null, () => fromShard<QuestDetail>("quests", row![6], id!));
}
export const loadNpc = (index: Index, id: number) => { const row = index.npcs.get(id); return row ? fromShard<NpcDetail>("npcs", row[7], id) : Promise.resolve(null); };
export const loadQuest = (index: Index, id: number) => { const row = index.quests.get(id); return row ? fromShard<QuestDetail>("quests", row[6], id) : Promise.resolve(null); };
/** Imperative lookup used by hover cards. */
export const loadItem = (index: Index, id: number) => { const row = index.items.get(id); return row ? fromShard<ItemDetail>("items", row[7], id) : Promise.resolve(null); };

// ---- small helpers --------------------------------------------------------------------------
export const QUALITY_NAMES = ["Poor", "Common", "Uncommon", "Rare", "Epic", "Legendary", "Artifact"];
export const RANK = ["", "Elite", "Rare Elite", "Boss", "Rare"];
export const qualityClass = (q: number | null | undefined) => `q${q ?? 1}`;
export const itemIconUrl = (id: number, fileId?:number|null) => fileId ? `/media/identity/client-items/${fileId}.jpg` : `/media/identity/items/${id}.jpg`;
export const hrefItem = (id: number) => `#database/items/${id}`;
export const hrefNpc = (id: number) => `#database/npcs/${id}`;
export const hrefQuest = (id: number) => `#database/quests/${id}`;
export const hrefDungeon = (key: string) => `#database/dungeons/${key}`;
export const hrefMap = (zone: string, focus?: string) => `#atlas/${zone}${focus ? `?focus=${focus}` : ""}`;
export function money(gold: number, silver: number, copper: number) { return { gold, silver, copper }; }

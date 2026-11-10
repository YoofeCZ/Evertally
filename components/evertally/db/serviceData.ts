"use client";
// Who trains a profession and who sells an item: the data behind the map's "Trainers & vendors" layer (tools/build_services.py).
import { fetchJson, useLoad, zoneToWorld, type World } from "./store";

export type Services = {
  professions: Record<string, number[]>;
  pos: Record<string, [zone: string, x: number, y: number][]>;
  sells: Record<string, number[]>;
  quick: number[];
};
export const PROFESSIONS = ["alchemy", "blacksmithing", "cooking", "enchanting", "engineering", "first-aid", "fishing", "herbalism", "leatherworking", "mining", "skinning", "tailoring"] as const;
export type Profession = typeof PROFESSIONS[number];
export const useServices = (wanted: boolean) => useLoad<Services>(wanted ? "services" : null, () => fetchJson<Services>("/media/db/services.json"));

/** Trainers of any of the chosen professions, each with the professions it teaches. */
export function trainersFor(services: Services, chosen: readonly string[]): Map<number, string[]> {
  const out = new Map<number, string[]>();
  for (const profession of chosen) for (const id of services.professions[profession] ?? []) out.set(id, [...(out.get(id) ?? []), profession]);
  return out;
}

/** Vendors that sell the chosen items: any of them, or (mode "all") every one. Each vendor maps to the items it sells. */
export function vendorsFor(services: Services, items: readonly number[], mode: "any" | "all"): Map<number, number[]> {
  const out = new Map<number, number[]>();
  for (const item of items) for (const npc of services.sells[String(item)] ?? []) out.set(npc, [...(out.get(npc) ?? []), item]);
  if (mode === "all") for (const [npc, sold] of out) if (sold.length < new Set(items).size) out.delete(npc);
  return out;
}

/** Spawns of an NPC on Azeroth's map; spawns in a zone the world map does not know are left out. */
export function spawnsOf(services: Services, npc: number, world: World): [number, number][] {
  const out: [number, number][] = [];
  for (const [zone, x, y] of services.pos[String(npc)] ?? []) {
    const entry = world.maps[zone];
    if (entry) out.push(zoneToWorld(entry.rect, x, y));
  }
  return out;
}

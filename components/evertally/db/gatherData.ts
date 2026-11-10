// Resource nodes for the Gathering layer (tools/build_gather.py): which resources exist, and where they were listed.
import { fetchJson, useLoad, zoneToWorld, type World } from "./store";

export type GatherKind = "herb" | "ore" | "container" | "fishing";
export type GatherNode = { key: string; name: string; type: GatherKind; skill: number | null; n: number };
export type GatherFile = { source: string; nodes: GatherNode[]; points: Record<string, Record<string, number[]>> };
export const GATHER_KINDS: GatherKind[] = ["herb", "ore", "container", "fishing"];
export const useGatherFile = (wanted: boolean) => useLoad<GatherFile>(wanted ? "gather" : null, () => fetchJson<GatherFile>("/media/gather/gather.json"));

/** Every resource's points on Azeroth's map as flat [u, v, u, v, ...]; maps the world does not carry are counted as unplaced. */
export function placeGather(file: GatherFile, world: World): { points: Map<string, Float32Array>; unplaced: number } {
  const byUi = new Map(Object.values(world.maps).map(entry => [String(entry.ui), entry.rect]));
  const points = new Map<string, Float32Array>();
  let unplaced = 0;
  for (const node of file.nodes) {
    const out: number[] = [];
    for (const [map, flat] of Object.entries(file.points[node.key] ?? {})) {
      const rect = byUi.get(map);
      if (!rect) { unplaced += flat.length / 2; continue; }
      for (let i = 0; i + 1 < flat.length; i += 2) out.push(...zoneToWorld(rect, flat[i] / 10, flat[i + 1] / 10));
    }
    points.set(node.key, Float32Array.from(out));
  }
  return { points, unplaced };
}

const ORE: [RegExp, string][] = [[/copper|amber/i, "#d9824a"], [/tin/i, "#c4ccd4"], [/silver|moonstone/i, "#e6edf7"], [/iron/i, "#8f95a3"], [/gold|fool/i, "#f5c518"], [/mithril/i, "#6fb1e8"], [/truesilver|starsilver/i, "#9fe7ff"], [/thorium/i, "#6fcf7a"], [/obsidian/i, "#7b5a8a"], [/bloodstone|incendicite|indurium/i, "#d6455a"]];
const HERB = ["#8bd96a", "#f1d95b", "#c79bff", "#ff8fb2", "#6fd6c6", "#f4a261", "#b5e48c", "#9ad0ff", "#e6a8ff", "#ffd166", "#7bdff2", "#ff9e7a"];
/** A stable colour per resource: metals look like their metal, herbs take a colour from a palette by their position. */
export function gatherColor(node: GatherNode, index: number): string {
  if (node.type === "ore") return ORE.find(([pattern]) => pattern.test(node.name))?.[1] ?? "#b9a28a";
  if (node.type === "herb") return HERB[index % HERB.length];
  return node.type === "fishing" ? "#4aa3ff" : "#c9a227";
}

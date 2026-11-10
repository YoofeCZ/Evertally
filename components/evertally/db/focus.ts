// Turns "show me X on the map" (an NPC, quest, item, object or dungeon) into pins per zone.
// Positions come only from the reference database (spawn points, object points, dungeon entrances); never from players.
import type { MapHighlight } from "./MapCanvas";
import { loadItem, loadNpc, loadQuest, type Dungeon, type Index } from "./store";

export type FocusKind = "npc" | "quest" | "item" | "obj" | "dungeon";
export type Focus = { kind: FocusKind; id: string };
/** A pin in zone-relative percent (0..100 of that zone's map); MapView places it on the world. */
export type Hl = { key: string; zone: string; x: number; y: number; label: string; role: MapHighlight["role"] };
export type Resolved = { title: string; hint?: string; href?: string; hl: Hl[]; lines: string[] };
export type ObjectTable = Record<string, [string, string?, number?, number?]>;

const KINDS: FocusKind[] = ["npc", "quest", "item", "obj", "dungeon"];
export function parseFocus(text: string | null | undefined): Focus | null {
  const [kind, ...rest] = (text ?? "").split(":");
  const id = rest.join(":");
  return KINDS.includes(kind as FocusKind) && /^[a-z0-9-]{1,80}$/.test(id) ? { kind: kind as FocusKind, id } : null;
}
export const focusText = (focus: Focus | null) => focus ? `${focus.kind}:${focus.id}` : "";

const MAX_PER_NPC = 12;
async function npcPins(index: Index, id: number, role: Hl["role"], label: (name: string) => string, out: Hl[], cap = MAX_PER_NPC) {
  const detail = await loadNpc(index, id);
  if (!detail) return null;
  for (const [zone, points] of Object.entries(detail.sp)) {
    points.slice(0, cap).forEach(([x, y], i) => {
      out.push({ key: `${role}:${id}:${zone}:${i}`, zone, x, y, role, label: label(detail.name) });
    });
  }
  return detail;
}
function objectPin(objects: ObjectTable, id: number, role: Hl["role"], out: Hl[], prefix = "") {
  const entry = objects[String(id)];
  if (entry?.[1] && entry[2] != null && entry[3] != null) out.push({ key: `${role}:o${id}`, zone: entry[1], x: entry[2], y: entry[3], role, label: `${prefix}${entry[0]}` });
  return entry?.[0] ?? null;
}

export async function resolveFocus(index: Index, focus: Focus, objects: ObjectTable, dungeons: Dungeon[]): Promise<Resolved> {
  const id = Number(focus.id);
  const hl: Hl[] = [];
  const lines: string[] = [];
  if (focus.kind === "npc") {
    const detail = await npcPins(index, id, "npc", name => name, hl, 40);
    return { title: detail?.name ?? index.npcs.get(id)?.[1] ?? `NPC #${id}`, href: `#database/npcs/${id}`, hl, lines };
  }
  if (focus.kind === "obj") {
    const name = objectPin(objects, id, "object", hl);
    return { title: name ?? `Object #${id}`, hl, lines };
  }
  if (focus.kind === "dungeon") {
    const dungeon = dungeons.find(d => d.key === focus.id);
    if (dungeon?.entrance) hl.push({ key: `entrance:${dungeon.key}`, zone: dungeon.entrance.zone, x: dungeon.entrance.x, y: dungeon.entrance.y, role: "entrance", label: dungeon.entrance.label ?? dungeon.name });
    return { title: dungeon?.name ?? focus.id, hint: dungeon?.entrance?.hint, href: `#database/dungeons/${focus.id}`, hl, lines };
  }
  if (focus.kind === "quest") {
    const quest = await loadQuest(index, id);
    if (!quest) return { title: index.quests.get(id)?.[1] ?? `Quest #${id}`, hl, lines };
    const starts = quest.startNpc ?? [], ends = quest.endNpc ?? [];
    await Promise.all([
      ...starts.slice(0, 4).map(npc => npcPins(index, npc, "start", name => name, hl, 4)),
      ...ends.filter(npc => !starts.includes(npc)).slice(0, 4).map(npc => npcPins(index, npc, "end", name => name, hl, 4)),
      ...(quest.kill ?? []).slice(0, 6).map(npc => npcPins(index, npc, "kill", name => name, hl, 25)),
    ]);
    quest.startObj?.slice(0, 4).forEach(obj => objectPin(objects, obj, "start", hl));
    quest.endObj?.slice(0, 4).forEach(obj => objectPin(objects, obj, "end", hl));
    quest.objObj?.slice(0, 6).forEach(obj => objectPin(objects, obj, "object", hl));
    if (starts.some(npc => ends.includes(npc))) lines.push("start=end");
    return { title: quest.name, hint: quest.lvl ? `Level ${quest.lvl}` : undefined, href: `#database/quests/${id}`, hl, lines };
  }
  // item: who drops it, who sells it, which objects contain it
  const detail = await loadItem(index, id);
  if (!detail) return { title: index.items.get(id)?.[1] ?? `Item #${id}`, hl, lines };
  const drops = [...(detail.drops ?? [])].sort((a, b) => (b[1] ?? 0) - (a[1] ?? 0)).slice(0, 24);
  await Promise.all([
    ...drops.map(([npc, pct]) => npcPins(index, npc, "drop", name => pct ? `${name} · ${pct.toFixed(pct < 1 ? 2 : 1)}%` : name, hl, 8)),
    ...(detail.vendors ?? []).slice(0, 10).map(npc => npcPins(index, npc, "vendor", name => name, hl, 3)),
  ]);
  detail.objDrops?.slice(0, 10).forEach(obj => objectPin(objects, obj, "object", hl));
  return { title: detail.name, href: `#database/items/${id}`, hl, lines };
}

/** The zone with the most pins, so a link without a zone lands where the answer is. */
export function bestZone(hl: Hl[]): string | null {
  const counts = new Map<string, number>();
  for (const pin of hl) counts.set(pin.zone, (counts.get(pin.zone) ?? 0) + 1);
  return [...counts].sort((a, b) => b[1] - a[1])[0]?.[0] ?? null;
}

import { CHRONICLE_NPCS, CHRONICLE_NPC_MODELS } from "./chronicle-npcs.data";

export type ChronicleArt = { name?: string; image?: string };
export type ArtRequest = { kind: "spell" | "npc"; id?: number; name?: string; displayId?: number };
const positiveId = (id: number | undefined) => Number.isInteger(id) && id! > 0 && id! <= 1e9;
export const sameArtName = (a: string | undefined, b: string | undefined) => !a || !b || a.trim().toLocaleLowerCase() === b.trim().toLocaleLowerCase();

/** Only fixed public game-data hosts are queried. No names from a recording are sent upstream. */
export async function loadChronicleArt(input: ArtRequest, fetcher: typeof fetch = fetch): Promise<ChronicleArt> {
  const resolved = positiveId(input.id) ? input.id : input.kind === "npc" && input.name ? CHRONICLE_NPCS[input.name.toLocaleLowerCase()] : undefined;
  const id = positiveId(resolved) ? resolved : undefined;
  if (input.kind === "npc" && positiveId(input.displayId)) {
    const display = input.displayId!;
    return { image: `https://wow.zamimg.com/modelviewer/classic/webthumbs/npc/${display % 256}/${display}.webp` };
  }
  if (!id) return {};
  if (input.kind === "npc") {
    const model = CHRONICLE_NPC_MODELS[id];
    if (!model) return {};
    return {name:model[0],image:`https://wow.zamimg.com/modelviewer/classic/webthumbs/npc/${model[1] % 256}/${model[1]}.webp`};
  }
  const url = `https://nether.wowhead.com/classic/tooltip/spell/${id}`;
  const response = await fetcher(url, { signal: AbortSignal.timeout(5000) });
  if (!response.ok) return {};
  const body = await response.text();
  if (body.length > 1_000_000) return {};
  const raw = JSON.parse(body) as { name?: unknown; icon?: unknown };
  if (typeof raw.name !== "string" || typeof raw.icon !== "string" || !/^[a-z0-9_]+$/i.test(raw.icon)) return {};
  return { name: raw.name.slice(0,120), image: `https://wow.zamimg.com/images/wow/icons/large/${raw.icon.toLowerCase()}.jpg` };
}

const cache = new Map<string, { until: number; value: Promise<ChronicleArt> }>();
export function chronicleArt(input: ArtRequest): Promise<ChronicleArt> {
  const id = input.id ?? (input.kind === "npc" && input.name ? CHRONICLE_NPCS[input.name.toLocaleLowerCase()] : undefined);
  const key = `${input.kind}:${id ?? ""}:${input.displayId ?? ""}`;
  if (!id && !input.displayId) return Promise.resolve({});
  const hit = cache.get(key), now = Date.now();
  if (hit && hit.until > now) return hit.value;
  if (cache.size >= 512) cache.delete(cache.keys().next().value!);
  const entry = {until:now+86400_000, value:loadChronicleArt({...input,id}).catch<ChronicleArt>(()=>({}))};
  cache.set(key,entry);
  void entry.value.then(value=>{if(!value.image)entry.until=Date.now()+300_000;});
  return entry.value;
}

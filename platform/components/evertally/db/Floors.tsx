"use client";
/* eslint-disable @next/next/no-img-element -- bundled floor maps with an intrinsic size */
// Blizzard's own map of every floor of a dungeon or raid (read from the game client, see tools/build_dungeon_floors.py).
import { useState, type ReactNode } from "react";
import { useFloors, type Floor, type Floors } from "./store";
import { useS } from "./strings";

/** Wings share one instance map: which floors belong to which of our dungeon keys. */
const WING: Record<string, string> = {
  "dire-maul-north": "Dire Maul - North", "dire-maul-east": "Dire Maul - East", "dire-maul-west": "Dire Maul - West",
  "lower-blackrock-spire": "Lower Blackrock Spire", "upper-blackrock-spire": "Upper Blackrock Spire",
  "stratholme-living": "Stratholme - Main Gate", "stratholme-undead": "Stratholme - Service Entrance",
};
const FLOOR_NAME: Record<string, string> = {
  "scarlet-monastery-graveyard": "Graveyard", "scarlet-monastery-library": "Library",
  "scarlet-monastery-armory": "Armory", "scarlet-monastery-cathedral": "Cathedral",
};

export function floorsFor(floors: Floors | null, mapId: number | null, key?: string): Floor[] {
  const all = mapId == null ? [] : floors?.maps[String(mapId)] ?? [];
  if (!key) return all;
  if (WING[key]) return all.filter(floor => floor.wing === WING[key]);
  if (FLOOR_NAME[key]) return all.filter(floor => floor.name === FLOOR_NAME[key]);
  return all;
}

export function useFloorsFor(key: string | null, mapId?: number | null) {
  const floors = useFloors();
  const id = mapId ?? (key ? floors.data?.keys[key] ?? null : null);
  return { loading: floors.loading, mapId: id, floors: floorsFor(floors.data, id, key ?? undefined) };
}

export function FloorMaps({ dungeonKey, mapId, aside }: { dungeonKey?: string; mapId?: number | null; aside?: ReactNode }) {
  const s = useS();
  const { floors, loading } = useFloorsFor(dungeonKey ?? null, mapId);
  const [index, setIndex] = useState(0);
  if (!floors.length) return <p className="muted small">{loading ? s.loading : s.noFloors}</p>;
  const current = floors[Math.min(index, floors.length - 1)];
  return (
    <div className="floor-maps">
      {floors.length > 1 && <div className="floor-tabs" role="tablist">{floors.map((floor, i) => <button key={floor.img} type="button" role="tab" aria-selected={i === index} className={i === index ? "on" : ""} onClick={() => setIndex(i)}>{floor.name ?? `${s.floor} ${i + 1}`}</button>)}</div>}
      <div className="floor-body">
        <a className="floor-art" href={current.img} target="_blank" rel="noreferrer" title={s.openImage}><img src={current.img} alt={current.name ?? s.floor} width={1002} height={668} loading="lazy" decoding="async" /></a>
        {aside && <div className="floor-aside">{aside}</div>}
      </div>
      <p className="fine-print">{s.floorSource}</p>
    </div>
  );
}

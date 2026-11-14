"use client";
/* eslint-disable @next/next/no-img-element -- small bundled item icons with explicit size and a fallback glyph */
// Original line icons (24x24, currentColor) for map points of interest, NPC services and item categories.
import { useState } from "react";
import { itemIconUrl, qualityClass } from "./store";

type Glyph = { label: string; color: string; svg: string };
const dot = (cx: number, cy: number) => `<circle cx="${cx}" cy="${cy}" r="1.2" fill="currentColor" stroke="none"/>`;

/** Map layers / NPC roles. `color` fills the round marker; the glyph is drawn in white. */
export const POI: Record<string, Glyph> = {
  qs: { label: "Quest available", color: "#c9a227", svg: `<path d="M12 5v8.500"/>${dot(12, 18.500)}` },
  qe: { label: "Quest turn-in", color: "#d9b84a", svg: `<path d="M9.200 9.200a3 3 0 1 1 4.600 2.500c-1 .6-1.800 1.200-1.800 2.500"/>${dot(12, 18.500)}` },
  vendor: { label: "Vendor", color: "#3f9b6b", svg: `<path d="M9.500 4h5l-1.100 2.600c2.800 1.100 4.600 3.500 4.600 6.400a5.500 5.500 0 0 1-5.500 5.500h-2A5.500 5.500 0 0 1 6 13c0-2.900 1.800-5.300 4.600-6.400L9.500 4z"/><path d="M12 10.500v5M10.500 12h2.500a1 1 0 0 1 0 2h-2"/>` },
  trainer: { label: "Trainer", color: "#4a7fd0", svg: `<path d="M12 6.500C10 5 7 4.700 4.500 5.200v12.500c2.500-.5 5.500-.2 7.500 1.300 2-1.500 5-1.800 7.500-1.300V5.200C17 4.700 14 5 12 6.500zM12 6.500V19"/>` },
  flight: { label: "Flight master", color: "#2e9aa6", svg: `<path d="M3.500 13.500c3-.4 5.500-2 7.500-5 1 2.200 2.500 3.300 4.500 3.700 1.500.3 3 0 5-1.200-.9 3.600-3.800 6.200-8 6.700-3 .4-6-.4-9-2.200z"/>` },
  inn: { label: "Innkeeper", color: "#c9742e", svg: `<path d="M5.500 7.500h9.500v7.500a3 3 0 0 1-3 3H8.500a3 3 0 0 1-3-3V7.500zM15 9.500h1.800a2 2 0 0 1 0 4H15M8 4.500v1.500M12 4.500v1.500"/>` },
  bank: { label: "Banker", color: "#8a6bd1", svg: `<rect x="4" y="7.500" width="16" height="11" rx="2"/><path d="M4 12.500h16M12 11v3.500"/>` },
  auction: { label: "Auctioneer", color: "#b8528e", svg: `<path d="M5 19h8M9 15l6.500-6.500M12 5.500l4.500 4.500-2.200 2.200-4.500-4.500L12 5.500zM14.500 16.500l4 4"/>` },
  stable: { label: "Stable master", color: "#9c7a4a", svg: `<path d="M7 20v-9a5 5 0 0 1 10 0v9M7 15.500h3M14 15.500h3"/>` },
  battle: { label: "Battlemaster", color: "#c0453a", svg: `<path d="M5 5l9 9M5 5v3.500M5 5h3.500M19 5l-9 9M19 5v3.500M19 5h-3.500M7.500 16.500l-2.500 2.500M16.500 16.500l2.500 2.500"/>` },
  repair: { label: "Repair", color: "#6b7a8a", svg: `<path d="M13.500 4.500l6 6-2.500 2.500-6-6 2.500-2.500zM11.500 8L4.500 15l4 4 7-7"/>` },
  spirit: { label: "Spirit healer", color: "#7ab8d8", svg: `<path d="M7 19V11a5 5 0 0 1 10 0v8l-2-1.500L13.500 19 12 17.500 10.500 19 9 17.500 7 19z"/>${dot(10, 11)}${dot(14, 11)}` },
  mail: { label: "Mailbox", color: "#5a72b8", svg: `<rect x="4" y="6.500" width="16" height="11" rx="2"/><path d="M4.500 8.200l7.500 5.300 7.500-5.300"/>` },
  dungeon: { label: "Dungeon entrance", color: "#7e4fd0", svg: `<path d="M5 20V10a7 7 0 0 1 14 0v10M9 20v-6.500a3 3 0 0 1 6 0V20"/>` },
  raid: { label: "Raid entrance", color: "#b3392e", svg: `<path d="M12 4a7 7 0 0 0-4 12.700V19h8v-2.300A7 7 0 0 0 12 4zM10.500 19v-2.500M13.500 19v-2.500"/>${dot(9.500, 11)}${dot(14.500, 11)}` },
  city: { label: "City", color: "#b78a3a", svg: `<path d="M5 20V9.500l2-1.500V6h2v2l3-1.500L15 8V6h2v2l2 1.500V20M10 20v-4.500h4V20"/>` },
  boat: { label: "Boat", color: "#3a86c8", svg: `<path d="M3.500 15.500h17l-2.500 4h-12l-2.500-4zM12 4v9.500M12 5.500l5.500 6.500H12"/>` },
  zeppelin: { label: "Zeppelin", color: "#c8873a", svg: `<ellipse cx="12" cy="10.500" rx="8.500" ry="4.500"/><path d="M9.500 15l-1 3.500h7L14.500 15"/>` },
  airship: { label: "Airship", color: "#8a6bd1", svg: `<ellipse cx="12" cy="10.500" rx="8.500" ry="4.500"/><path d="M9.500 15l-1 3.500h7L14.500 15M4 10.500h16"/>` },
  origin: { label: "Start", color: "#2f9e6e", svg: `<circle cx="12" cy="12" r="3.500" fill="currentColor" stroke="none"/><circle cx="12" cy="12" r="7"/>` },
  goal: { label: "Destination", color: "#d9534f", svg: `<path d="M7 20V5M7 5.500h10l-2.500 3.500L17 12.500H7"/>` },
  walk: { label: "Walk", color: "#7a8699", svg: `<circle cx="13" cy="5" r="1.600"/><path d="M13 8l-2.500 4 3 2.500L12 20M10.500 12L8 15M13.500 14.500l3.500 1"/>` },
  tram: { label: "Tram", color: "#c8a03a", svg: `<rect x="6" y="5.500" width="12" height="11" rx="2"/><path d="M6 11.500h12M9 16.500l-1.500 3M15 16.500l1.500 3M9.500 3.500h5"/>` },
  lift: { label: "Lift", color: "#8a6bd1", svg: `<rect x="6" y="4.500" width="12" height="15" rx="2"/><path d="M12 8l-2.500 2.500h5L12 8zM12 16l-2.500-2.500h5L12 16z"/>` },
  portal: { label: "Portal", color: "#7e4fd0", svg: `<ellipse cx="12" cy="12" rx="5" ry="8"/><ellipse cx="12" cy="12" rx="2" ry="4.500"/>` },
  passage: { label: "Passage", color: "#9c7a4a", svg: `<path d="M5 20V10a7 7 0 0 1 14 0v10M10 20v-5h4v5"/>` },
  pin: { label: "Pin", color: "#e0457b", svg: `<path d="M12 20.500s6-5.500 6-10a6 6 0 1 0-12 0c0 4.500 6 10 6 10z"/><circle cx="12" cy="10.500" r="2"/>` },
  mob: { label: "Creature", color: "#8a4a4a", svg: `<circle cx="12" cy="12" r="3.500"/>` },
  meet: { label: "Meet", color: "#e5a13a", svg: `<path d="M6 20V4.500M6 5h11l-2.500 3.500L17 12H6"/>` },
  "meet-group": { label: "Group run", color: "#7e4fd0", svg: `<circle cx="9" cy="9" r="2.800"/><circle cx="16.500" cy="10" r="2.300"/><path d="M3.500 19a5.500 5.500 0 0 1 11 0M14.500 14.300A4.500 4.500 0 0 1 20.500 19"/>` },
  "meet-farm": { label: "Farming", color: "#4f9a58", svg: `<path d="M5 19c0-8 5-13 14-14 0 9-5 14-13 14M5 19c3-4 6-7 10-9"/>` },
  "meet-trade": { label: "Trade", color: "#2e9aa6", svg: `<path d="M5 8h13M14.500 4.500 18 8l-3.500 3.500M19 16H6M9.500 12.500 6 16l3.500 3.500"/>` },
  "meet-event": { label: "Event", color: "#d9534f", svg: `<path d="M12 4.500l2.200 4.600 5 .7-3.600 3.500.9 5L12 15.900 7.500 18.300l.9-5L4.800 9.800l5-.7L12 4.500z"/>` },
  "meet-note": { label: "Note", color: "#8a8fa0", svg: `<path d="M6 4.500h12v11l-4 4H6v-15zM14 19.500v-4h4M9 9h6M9 12.500h4"/>` },
  gather: { label: "Gathering", color: "#4f9a58", svg: `<path d="M5 19c0-8 5-13 14-14 0 9-5 14-13 14M5 19c3-4 6-7 10-9"/>` },
  route: { label: "My route", color: "#d9a21f", svg: `<circle cx="6.500" cy="17.500" r="2"/><circle cx="17.500" cy="6.500" r="2"/><path d="M8.500 17.500h5a3.500 3.500 0 0 0 0-7h-3a3.500 3.500 0 0 1 0-7H15.500"/>` },
  guild: { label: "Guild", color: "#3f9b6b", svg: `<circle cx="9" cy="9" r="3"/><path d="M3.500 19a5.500 5.500 0 0 1 11 0M15.500 6.200a3 3 0 0 1 0 5.600M17 13.600A5.500 5.500 0 0 1 20.500 19"/>` },
  sighting: { label: "Community sighting", color: "#4a9bd1", svg: `<circle cx="12" cy="12" r="3.500"/><path d="M12 4v3M12 17v3M4 12h3M17 12h3"/>` },
};

const CATEGORY_SVG: Record<string, string> = {
  Weapon: `<path d="M14.500 4h5.500v5.500L9.500 20 4 14.500 14.500 4zM10 9l5 5M4 20l3.500-3.500"/>`,
  Armor: `<path d="M12 3.500l7 3v5.500c0 4.200-3 7.200-7 8.500-4-1.300-7-4.300-7-8.500V6.500l7-3z"/>`,
  Consumable: `<path d="M10 4h4M10.500 4v4L6.500 17a2.500 2.500 0 0 0 2.300 3.500h6.400a2.500 2.500 0 0 0 2.300-3.500L13.500 8V4M8.500 14h7"/>`,
  Container: `<path d="M8.500 7.500h7l2 3.500v7a2 2 0 0 1-2 2h-7a2 2 0 0 1-2-2v-7l2-3.500zM9.500 7.500a2.500 2.500 0 0 1 5 0M9 13.500h6"/>`,
  Recipe: `<path d="M7 4.500h8.500l2.500 2.500V19.500H7zM9.500 10h6M9.500 13h6M9.500 16h4"/>`,
  "Trade Goods": `<path d="M12 3.500l7.500 4v9L12 20.500l-7.500-4v-9L12 3.500zM4.500 7.500L12 11.500l7.500-4M12 11.500v9"/>`,
  Reagent: `<path d="M9 4.500h6M10 4.500v5L6 18a2 2 0 0 0 1.800 3h8.400A2 2 0 0 0 18 18l-4-8.500v-5"/>`,
  Quest: `<path d="M12 5v8M12 17.500h.01"/>`,
  Key: `<circle cx="8.500" cy="12" r="3.500"/><path d="M12 12h8M17 12v3M20 12v2"/>`,
  Projectile: `<path d="M5 19L19 5M19 5h-5M19 5v5M5 19l-1-3 3 1"/>`,
  Miscellaneous: `<path d="M12 4l7 5-3 10H8L5 9l7-5z"/>`,
  Gem: `<path d="M7 5h10l3.500 5L12 20 3.500 10 7 5zM3.500 10h17M9.500 5l2.500 5 2.500-5M12 10v10"/>`,
  Quiver: `<path d="M8 20L16 4M6.500 17.500l3 2M13 8l3-2"/>`,
};

export function PoiGlyph({ kind, size = 18 }: { kind: string; size?: number }) {
  const glyph = POI[kind] ?? POI.mob;
  return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" dangerouslySetInnerHTML={{ __html: glyph.svg }} />;
}

/** Round marker badge, the same look on the map (HTML string for Leaflet) and in legends (React). */
export function PoiBadge({ kind, size = 22 }: { kind: string; size?: number }) {
  const glyph = POI[kind] ?? POI.mob;
  return <span className={`poi-badge poi-${kind}`} style={{ width: size, height: size, background: glyph.color }}><PoiGlyph kind={kind} size={Math.round(size * 0.68)} /></span>;
}
export function poiMarkerHtml(kind: string, size = 26, extra = ""): string {
  const glyph = POI[kind] ?? POI.mob;
  return `<span class="poi-badge poi-${kind} ${extra}" style="width:${size}px;height:${size}px;background:${glyph.color}"><svg width="${Math.round(size * 0.68)}" height="${Math.round(size * 0.68)}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${glyph.svg}</svg></span>`;
}

export function CategoryGlyph({ category, size = 20 }: { category?: string | null; size?: number }) {
  return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" dangerouslySetInnerHTML={{ __html: CATEGORY_SVG[category ?? ""] ?? CATEGORY_SVG.Miscellaneous }} />;
}

/** Game item icon framed in its quality colour; falls back to a category glyph when no art exists. */
export function ItemIcon({ id, fileId, quality, category, size = 34, cached = true, title }: { id: number; fileId?:number|null; quality?: number | null; category?: string | null; size?: number; cached?: boolean; title?: string }) {
  const [failed, setFailed] = useState<string|null>(null);
  const source=itemIconUrl(id,fileId);
  const show = (cached || Boolean(fileId)) && failed!==source;
  return (
    <span className={`item-icon ${qualityClass(quality)}`} style={{ width: size, height: size }} title={title}>
      {show ? <img src={source} alt="" width={size} height={size} loading="lazy" decoding="async" onError={() => setFailed(source)} /> : <CategoryGlyph category={category} size={Math.round(size * 0.58)} />}
    </span>
  );
}

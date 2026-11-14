"use client";
/* eslint-disable @next/next/no-img-element -- small bundled game icons with explicit sizes and a fallback */
// The pictures of the journey replay: one set of vector icons that is drawn both in the page and on the map canvas, the item
// icons of the game, and the portrait of the character.
import { useState } from "react";
import { useLoad, fetchJson } from "../db/store";

/** 24 x 24 outlines, filled with the even-odd rule. One per type of moment (see `typeKey`). */
export const ICON: Record<string, string> = {
  "quest.accept": "M10.4 3.5h3.2l-.7 10.2h-1.8L10.4 3.5zM12 15.9a1.9 1.9 0 1 1 0 3.8 1.9 1.9 0 0 1 0-3.8z",
  "quest.turnin": "M8.2 8.6A3.8 3.8 0 0 1 12 4.5a3.7 3.7 0 0 1 3.8 3.7c0 1.5-.9 2.4-1.9 3.1-.8.6-1.2 1-1.2 1.9v.4h-2v-.6c0-1.6.8-2.4 1.8-3.1.7-.5 1.2-.9 1.2-1.7 0-.9-.7-1.7-1.7-1.7s-1.8.8-1.8 1.8H8.2zM11.7 16.2a1.5 1.5 0 1 1 0 3 1.5 1.5 0 0 1 0-3z",
  "quest.abandon": "M7 5.6l5 5 5-5L18.4 7l-5 5 5 5-1.4 1.4-5-5-5 5L5.6 17l5-5-5-5L7 5.6z",
  "combat.kill": "M12 5.5a6.5 6.5 0 1 0 0 13 6.5 6.5 0 0 0 0-13zm0 2.6a3.9 3.9 0 1 1 0 7.8 3.9 3.9 0 0 1 0-7.8zM11 2h2v3h-2V2zm0 17h2v3h-2v-3zM2 11h3v2H2v-2zm17 0h3v2h-3v-2z",
  "combat.death": "M12 3C7.6 3 5 6 5 9.7c0 2.3 1 3.8 2.4 4.8V18h2v-1.6h1.2V18h2.8v-1.6h1.2V18h2v-3.5c1.4-1 2.4-2.5 2.4-4.8C19 6 16.4 3 12 3zM9.2 9a1.8 1.8 0 1 1 0 3.6 1.8 1.8 0 0 1 0-3.6zm5.6 0a1.8 1.8 0 1 1 0 3.6 1.8 1.8 0 0 1 0-3.6z",
  "combat.boss": "M3.5 18.5L2.5 7l5 4 4.5-7 4.5 7 5-4-1 11.5h-17zM5 20.5h14V22H5v-1.5z",
  "loot.item": "M12 2.5l7.5 6.5L12 21.5 4.5 9 12 2.5zM12 6.2L8.2 9.2 12 16.2l3.8-7L12 6.2z",
  "loot.money": "M12 3.5a8.5 8.5 0 1 0 0 17 8.5 8.5 0 0 0 0-17zm0 2.6a5.9 5.9 0 1 1 0 11.8 5.9 5.9 0 0 1 0-11.8zm-.9 2.4v.9H10v1.7h2.1c.4 0 .6.2.6.4s-.2.4-.6.4h-.6c-1.2 0-2 .8-2 1.8 0 1 .8 1.7 1.8 1.8v.9h1.4v-.9H14v-1.7h-2.2c-.3 0-.5-.2-.5-.4s.2-.4.5-.4h.5c1.3 0 2.2-.8 2.2-1.9 0-1-.7-1.6-1.7-1.8v-.8h-1.7z",
  "prof.skill": "M12 3.5l7.5 8.5h-4.7V20.5H9.2V12H4.5L12 3.5z",
  "travel.flight": "M3 11.4L21 3.5l-4.3 17-5-4.8-3.3 3.2v-5.4L3 11.4zm6.5 1.1l5.6-4-7.6 5.1 2-1.1z",
  "travel.instance": "M5 21V10a7 7 0 0 1 14 0v11h-4.2v-8.4a2.8 2.8 0 0 0-5.6 0V21H5z",
  "travel.zone": "M5.5 3h2v18h-2V3zM8.5 4h10.5l-3 4.5 3 4.5H8.5V4z",
  "char.level": "M12 2.8l2.8 5.9 6.4.8-4.7 4.4 1.2 6.4L12 17.2l-5.7 3.1 1.2-6.4L2.8 9.5l6.4-.8L12 2.8z",
  "char.group": "M9 11a3 3 0 1 0 0-6 3 3 0 0 0 0 6zm6.6-.4a2.6 2.6 0 1 0 0-5.2 2.6 2.6 0 0 0 0 5.2zM9 13c-3 0-6 1.5-6 4v2.5h12V17c0-2.5-3-4-6-4zm6.6.7c-.5 0-1 .1-1.5.2 1.2.9 1.9 2.1 1.9 3.5v2.1h5.5v-2c0-2.1-2.6-3.8-5.9-3.8z",
  "char.emote": "M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18zM9 9.4a1.3 1.3 0 1 1 0 2.6 1.3 1.3 0 0 1 0-2.6zm6 0a1.3 1.3 0 1 1 0 2.6 1.3 1.3 0 0 1 0-2.6zM7.8 14h8.4a4.2 4.2 0 0 1-8.4 0z",
};
export const MARK_COLOR: Record<string, string> = {
  "quest.accept": "#f2c04b", "quest.turnin": "#f2c04b", "quest.abandon": "#8f8ca0", "combat.kill": "#e2786a", "combat.death": "#d9534f", "combat.boss": "#d9534f",
  "loot.item": "#e8a15a", "loot.money": "#f2c04b", "prof.skill": "#5fb98d", "travel.flight": "#5b8def", "travel.instance": "#5b8def", "travel.zone": "#7fb2ff",
  "char.level": "#a78bfa", "char.group": "#5b8def", "char.emote": "#e8a15a",
};
/** The colour of the icon on its coloured disc: dark on the light yellows, white elsewhere. */
export const INK: Record<string, string> = { "quest.accept": "#1a1726", "quest.turnin": "#1a1726", "loot.money": "#1a1726" };
export const hasIcon = (key: string) => key in ICON;

const cache = new Map<string, Path2D>();
/** Draws an icon centred at (cx, cy), `size` pixels across, on a canvas. */
export function drawIcon(ctx: CanvasRenderingContext2D, key: string, cx: number, cy: number, size: number, color: string) {
  const d = ICON[key];
  if (!d) return;
  let path = cache.get(key);
  if (!path) { path = new Path2D(d); cache.set(key, path); }
  ctx.save();
  ctx.translate(cx - size / 2, cy - size / 2); ctx.scale(size / 24, size / 24);
  ctx.fillStyle = color; ctx.fill(path, "evenodd");
  ctx.restore();
}

export function TypeIcon({ k, size = 16 }: { k: string; size?: number }) {
  return <svg viewBox="0 0 24 24" width={size} height={size} aria-hidden="true" focusable="false"><path d={ICON[k] ?? ""} fill="currentColor" fillRule="evenodd" /></svg>;
}
/** The icon on a coloured disc: how a moment looks in a list and on the timeline. */
export function IconChip({ k, size = 24 }: { k: string; size?: number }) {
  return <span className="chr-chip" style={{ width: size, height: size, background: MARK_COLOR[k] ?? "#7fb2ff", color: INK[k] ?? "#fff" }}><TypeIcon k={k} size={Math.round(size * 0.62)} /></span>;
}

const QUALITY = ["#9d9d9d", "#ffffff", "#1eff00", "#0070dd", "#a335ee", "#ff8000"];
/** The game's item id to the file of its icon (a few thousand items have one under another name). */
export const useItemIcons = () => useLoad<{ items: Record<string, number> }>("client-item-icons", () => fetchJson("/media/identity/client-items.json"));

function ItemIconInner({ id, q, size, label }: { id: number; q: number; size: number; label?: string }) {
  const icons = useItemIcons();
  const [failed, setFailed] = useState(0);
  const file = icons.data?.items[String(id)];
  const sources = [file ? `/media/identity/client-items/${file}.jpg` : "", `/media/identity/items/${id}.jpg`].filter(Boolean);
  const src = sources[failed];
  return (
    <span className="chr-item" style={{ width: size, height: size, ["--q" as string]: QUALITY[q] ?? QUALITY[1] }} title={label}>
      {src ? <img src={src} alt="" width={size} height={size} loading="lazy" decoding="async" onError={() => setFailed(n => n + 1)} /> : <TypeIcon k="loot.item" size={Math.round(size * 0.6)} />}
    </span>
  );
}
/** The icon of an item with a frame in the colour of its quality. Without an id, or when no picture exists, a plain symbol. */
export function ItemIcon({ id, q = 1, size = 28, label }: { id?: number; q?: number; size?: number; label?: string }) {
  if (!id) return <span className="chr-item" style={{ width: size, height: size, ["--q" as string]: QUALITY[q] ?? QUALITY[1] }}><TypeIcon k="loot.item" size={Math.round(size * 0.6)} /></span>;
  return <ItemIconInner key={id} id={id} q={q} size={size} label={label} />;
}

export const classIconUrl = (classId: number) => `/media/identity/classes/${classId}.png`;
const raceIconUrl = (raceId: number) => `/media/identity/races/${raceId}.png`;
/** The character as the game shows it: the class icon in a ring of the class colour, the race beside it and the level on it. */
export function Portrait({ classId, raceId, level, color, size = 58 }: { classId: number; raceId?: number; level: number; color: string; size?: number }) {
  const [noClass, setNoClass] = useState(false);
  const [noRace, setNoRace] = useState(false);
  return (
    <span className="chr-portrait" style={{ width: size, height: size, ["--class" as string]: color }}>
      {noClass ? <b>?</b> : <img src={classIconUrl(classId)} alt="" width={size} height={size} onError={() => setNoClass(true)} />}
      {raceId !== undefined && !noRace && <img className="chr-race" src={raceIconUrl(raceId)} alt="" width={Math.round(size * 0.38)} height={Math.round(size * 0.38)} onError={() => setNoRace(true)} />}
      <em>{level}</em>
    </span>
  );
}

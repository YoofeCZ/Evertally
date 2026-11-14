"use client";
// The replay of a recorded journey: a map you can move and zoom freely (or let it follow the character), a timeline with the
// zones, dungeons and notable moments, the numbers so far, filters, a calendar of the days played, and the list of everything
// that happened. It runs entirely in the browser from one recording.
import { useCallback, useEffect, useMemo, useRef, useState, type PointerEvent as ReactPointerEvent, type ReactNode } from "react";
import { useI18n } from "@/lib/i18n";
import {
  ALL_TYPES, CATEGORIES, TYPE_KEYS, buildIndex, categoryOf, clock, countByCategory, countByType, daysOf, demoChronicle, eventAt, eventsBetween,
  instanceAt, instanceSummary, instances, moneyText, parseChronicle, passes, pathWindow, positionAt, sessionAt, statsAt, totalsAt, typeKey, visits, whenOf,
  type Category, type Chronicle, type ChronicleEvent, type Day, type Instance,
} from "@/lib/chronicle";
import { CLASS_COLORS, CLASSES } from "../data";
import { Icon } from "../ui";
import { useMaps } from "../db/store";
import type { MapDefinition } from "../world-map";

const SPEEDS = [1, 5, 20, 60, 200] as const;
const COLORS: Record<Category, string> = { quests: "#f2c04b", combat: "#e2786a", loot: "#c9c4d6", professions: "#5fb98d", travel: "#7fb2ff", character: "#a78bfa" };
const QUALITY = ["#9d9d9d", "#ffffff", "#1eff00", "#0070dd", "#a335ee", "#ff8000"];
/** How each kind of moment looks on the timeline. */
const MARK: Record<string, { g: string; c: string }> = {
  "quest.accept": { g: "!", c: "#f2c04b" }, "quest.turnin": { g: "?", c: "#f2c04b" }, "quest.abandon": { g: "×", c: "#9a97a8" },
  "combat.kill": { g: "•", c: "#e2786a" }, "combat.death": { g: "✕", c: "#e2786a" }, "combat.boss": { g: "☠", c: "#d9534f" },
  "loot.item": { g: "◆", c: "#e8a15a" }, "loot.money": { g: "¢", c: "#f2c04b" }, "prof.skill": { g: "▲", c: "#5fb98d" },
  "travel.flight": { g: "➤", c: "#5b8def" }, "travel.instance": { g: "∩", c: "#5b8def" }, "travel.zone": { g: "◇", c: "#7fb2ff" },
  "char.level": { g: "★", c: "#a78bfa" }, "char.group": { g: "+", c: "#5b8def" }, "char.emote": { g: "☺", c: "#e8a15a" },
};
const SHOWN_ON_TIMELINE = ["quest.accept", "quest.turnin", "quest.abandon", "combat.boss", "combat.death", "travel.instance", "travel.flight", "char.level", "char.group"];
const SHOWN_ON_MAP = ["quest.accept", "quest.turnin", "quest.abandon", "combat.kill", "combat.death", "combat.boss", "char.level", "travel.instance", "travel.flight"];

const TEXT = {
  en: {
    of: "The journey of", toPlay: "to play", forHelp: "for shortcuts", helpTitle: "Keyboard",
    keys: [["Space", "Play / pause"], ["← →", "Back / forward 10 s (Shift: 60 s)"], ["F", "Follow the character"], ["M", "Show or hide the moments"], ["+  −", "Faster / slower"], ["Drag, wheel", "Move and zoom the map"], ["?", "This help"]] as [string, string][],
    title: "Journey replay", lead: "Watch a whole journey again: where the character walked, what it fought, found and finished, on a timeline you can scrub.",
    demo: "Play the demo", open: "Open a recording", drop: "or drop a recording file here",
    note: "The addon does not write recordings yet. The demo is a generated journey, not a real player's. A real recording uses the same format.",
    bad: "This file is not a valid recording.", unreadable: "The file could not be read.", loading: "Loading maps…",
    play: "Play", pause: "Pause", replay: "Play again", speed: "Speed", follow: "Follow the character", idle: "Skip quiet stretches", moments: "Moments", full: "Full screen",
    sofar: "So far", quests: "quests done", kills: "kills", xp: "XP", money: "money", items: "items", places: "places", deaths: "deaths", skills: "Skills", professions: "Professions",
    sheet: "Sheet", itemLevel: "Item level", attributes: "Attributes", enhancements: "Enhancements", notedAt: "Stats as noted at", recorded: "recorded", played: "of play",
    earlier: "earlier moments not shown", later: "later moments not shown", what: "What happened", where: "Where", type: "Type", amount: "Amount", reward: "Experience", fight: "Fight", attempt: "Attempt",
    into: "into the journey", session: "session", back: "Back to the start", none: "Nothing to show here yet.", level: "Level",
    killsList: "Kills", itemsList: "Items", centre: "Centre on the character", zoomIn: "Zoom in", zoomOut: "Zoom out",
    show: "Show", reset: "Reset", tabs: { timeline: "Timeline", map: "Map", icon: "Character icon" } as Record<string, string>,
    tabNote: { timeline: "Badges and hairlines along the line of time.", map: "Markers placed on the map.", icon: "Messages that rise above the character." } as Record<string, string>,
    quality: ["Poor", "Common", "Uncommon", "Rare", "Epic"], andBetter: "and better",
    days: "Days", lastDay: "Last day played", whole: "Whole journey", pickDays: "Pick a day, then another to watch everything between them.", menu: "Settings",
    inInstance: "In", wiped: "wiped after", killedIn: "killed in", pull: "attempt",
    cat: { quests: "Quests", combat: "Combat", loot: "Loot and money", professions: "Professions", travel: "Travel", character: "Character" } as Record<Category, string>,
    types: { "quest.accept": "Quests accepted", "quest.turnin": "Quests turned in", "quest.abandon": "Quests abandoned", "combat.kill": "Kills", "combat.death": "Deaths", "combat.boss": "Boss encounters", "loot.item": "Loot", "loot.money": "Money", "prof.skill": "Skill-ups", "travel.flight": "Flight paths", "travel.instance": "Instances", "travel.zone": "Zones", "char.level": "Levels", "char.group": "Group changes", "char.emote": "Emotes" } as Record<string, string>,
    kind: { quest: "Quest", kill: "Kill", loot: "Loot", money: "Money", level: "Level", skill: "Skill", zone: "Zone", death: "Death", dungeon: "Dungeon", travel: "Travel", boss: "Boss", group: "Group", emote: "Emote" } as Record<string, string>,
    accepted: "Accepted", done: "Completed", handed: "Handed in", abandoned: "Abandoned", defeated: "Defeated", wipedOn: "Wiped on",
  },
  cs: {
    of: "Cesta postavy", toPlay: "přehrát", forHelp: "zkratky", helpTitle: "Klávesy",
    keys: [["Mezerník", "Přehrát / pozastavit"], ["← →", "Zpět / vpřed o 10 s (Shift: 60 s)"], ["F", "Sledovat postavu"], ["M", "Zobrazit nebo skrýt momenty"], ["+  −", "Rychleji / pomaleji"], ["Tažení, kolečko", "Posun a přiblížení mapy"], ["?", "Tato nápověda"]] as [string, string][],
    title: "Přehrání cesty", lead: "Podívej se znovu na celou cestu: kudy postava šla, s čím bojovala, co našla a dokončila, na časové ose, po které můžeš posouvat.",
    demo: "Přehrát ukázku", open: "Otevřít záznam", drop: "nebo sem přetáhni soubor se záznamem",
    note: "Addon záznamy zatím nezapisuje. Ukázka je vygenerovaná cesta, ne skutečného hráče. Skutečný záznam bude mít stejný formát.",
    bad: "Tento soubor není platný záznam.", unreadable: "Soubor se nepodařilo přečíst.", loading: "Načítám mapy…",
    play: "Přehrát", pause: "Pozastavit", replay: "Přehrát znovu", speed: "Rychlost", follow: "Sledovat postavu", idle: "Přeskakovat klidné úseky", moments: "Momenty", full: "Celá obrazovka",
    sofar: "Zatím", quests: "questů hotovo", kills: "zabití", xp: "XP", money: "peníze", items: "předmětů", places: "míst", deaths: "smrtí", skills: "Dovednosti", professions: "Profese",
    sheet: "Postava", itemLevel: "Úroveň výbavy", attributes: "Atributy", enhancements: "Vylepšení", notedAt: "Staty zaznamenané v", recorded: "zaznamenáno", played: "hraní",
    earlier: "dřívějších momentů se nezobrazuje", later: "pozdějších momentů se nezobrazuje", what: "Co se stalo", where: "Kde", type: "Druh", amount: "Množství", reward: "Zkušenosti", fight: "Souboj", attempt: "Pokus",
    into: "od začátku cesty", session: "hraní", back: "Zpět na začátek", none: "Zatím tu není co ukázat.", level: "Úroveň",
    killsList: "Zabití", itemsList: "Předměty", centre: "Vycentrovat na postavu", zoomIn: "Přiblížit", zoomOut: "Oddálit",
    show: "Zobrazit", reset: "Obnovit", tabs: { timeline: "Časová osa", map: "Mapa", icon: "Ikona postavy" } as Record<string, string>,
    tabNote: { timeline: "Značky a čáry podél časové osy.", map: "Značky umístěné na mapě.", icon: "Zprávy, které stoupají nad postavou." } as Record<string, string>,
    quality: ["Špatná", "Obyčejná", "Neobvyklá", "Vzácná", "Epická"], andBetter: "a lepší",
    days: "Dny", lastDay: "Poslední hraný den", whole: "Celá cesta", pickDays: "Vyber den a pak další a uvidíš vše mezi nimi.", menu: "Nastavení",
    inInstance: "V", wiped: "neúspěch po", killedIn: "poražen za", pull: "pokus",
    cat: { quests: "Questy", combat: "Boj", loot: "Loot a peníze", professions: "Profese", travel: "Cestování", character: "Postava" } as Record<Category, string>,
    types: { "quest.accept": "Přijaté questy", "quest.turnin": "Odevzdané questy", "quest.abandon": "Opuštěné questy", "combat.kill": "Zabití", "combat.death": "Smrti", "combat.boss": "Souboje s bossy", "loot.item": "Loot", "loot.money": "Peníze", "prof.skill": "Zlepšení dovedností", "travel.flight": "Letecké cesty", "travel.instance": "Instance", "travel.zone": "Zóny", "char.level": "Úrovně", "char.group": "Změny skupiny", "char.emote": "Emoty" } as Record<string, string>,
    kind: { quest: "Quest", kill: "Zabití", loot: "Loot", money: "Peníze", level: "Úroveň", skill: "Dovednost", zone: "Zóna", death: "Smrt", dungeon: "Dungeon", travel: "Cestování", boss: "Boss", group: "Skupina", emote: "Emote" } as Record<string, string>,
    accepted: "Přijato", done: "Splněno", handed: "Odevzdáno", abandoned: "Opuštěno", defeated: "Poražen", wipedOn: "Neúspěch na",
  },
};
type Words = typeof TEXT.en;

/** The text of a moment, as it is listed and as it floats above the character. */
function popup(e: ChronicleEvent, w: Words): { text: string; color: string } {
  switch (e.k) {
    case "quest": return { text: `${e.a === "accept" ? w.accepted : e.a === "abandon" ? w.abandoned : e.a === "turnin" ? w.handed : w.done}: ${e.text}${e.xp ? ` +${e.xp} XP` : ""}`, color: COLORS.quests };
    case "kill": return { text: `${e.text}${e.xp ? ` +${e.xp} XP` : ""}`, color: COLORS.combat };
    case "boss": return { text: `${e.a === "wipe" ? w.wipedOn : w.defeated} ${e.text}`, color: e.a === "wipe" ? COLORS.combat : "#7be0a0" };
    case "loot": return { text: `${e.text}${e.n && e.n > 1 ? ` ×${e.n}` : ""}`, color: QUALITY[e.q ?? 1] };
    case "money": return { text: moneyText(e.n ?? 0), color: "#f2c04b" };
    case "skill": return { text: `${e.text} ${e.n}/${e.max ?? e.n}`, color: COLORS.professions };
    case "level": return { text: `${w.level} ${e.n}!`, color: COLORS.character };
    case "death": return { text: e.text, color: COLORS.combat };
    default: return { text: e.text, color: COLORS.travel };
  }
}
const nameOf = (maps: readonly MapDefinition[], key: string, lang: string) => {
  const m = maps.find(x => x.key === key);
  return m ? (lang === "cs" ? m.nameCs : m.nameEn) : key.replace(/-/g, " ").replace(/^./, s => s.toUpperCase());
};
const hue = (key: string) => { let h = 0; for (const ch of key) h = (h * 31 + ch.charCodeAt(0)) % 360; return h; };
const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v));

type Cam = { x: number; y: number; z: number };
type ZoneArt = { key: string; img: HTMLImageElement | null; w: number; h: number };
type StageProps = { follow: boolean; overview: boolean; reduced: boolean; words: Words; mapTypes: ReadonlySet<string>; iconTypes: ReadonlySet<string>; minQ: number; onFree: () => void };
export type StageApi = { zoom: (factor: number) => void };

/**
 * The map: the zone picture under a camera that follows the character or is moved by hand (drag, wheel, pinch, double click),
 * with the trail, the markers of what happened and the messages that rise above the character.
 */
function Stage({ c, maps, timeRef, props, onApi }: { c: Chronicle; maps: readonly MapDefinition[]; timeRef: { current: number }; props: StageProps; onApi: (api: StageApi) => void }) {
  const canvas = useRef<HTMLCanvasElement>(null);
  const live = useRef(props);
  useEffect(() => { live.current = props; });
  const classColor = CLASS_COLORS[c.character.classId] ?? "#69ccf0";
  useEffect(() => {
    const el = canvas.current;
    const ctx = el?.getContext("2d");
    if (!el || !ctx) return;
    const images = new Map<string, HTMLImageElement>();
    const art = (key: string): ZoneArt => {
      const def = maps.find(m => m.key === key);
      if (!def) return { key, img: null, w: 1000, h: 667 };
      let img = images.get(def.image);
      if (!img) { img = new Image(); img.decoding = "async"; img.src = def.image; images.set(def.image, img); }
      return { key, img: img.complete && img.naturalWidth ? img : null, w: def.width, h: def.height };
    };
    let cw = 0, ch = 0, raf = 0, lastNow = performance.now();
    const resize = () => {
      const dpr = Math.min(2, window.devicePixelRatio || 1);
      cw = el.clientWidth; ch = el.clientHeight;
      el.width = Math.max(1, Math.floor(cw * dpr)); el.height = Math.max(1, Math.floor(ch * dpr));
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    };
    resize();
    const observer = new ResizeObserver(resize);
    observer.observe(el);

    const cam: Cam = { x: 0.5, y: 0.5, z: 1 };
    const free: Cam = { x: 0.5, y: 0.5, z: 1 };
    let zone = -1, fadeStart = -1e9, wasFollow = live.current.follow;
    let previous: { art: ZoneArt; cam: Cam } | null = null;
    const longest = visits(c).reduce((best, v) => (v.to - v.from > best.span ? { zone: v.zone, span: v.to - v.from } : best), { zone: 0, span: -1 }).zone;
    const overviewStep = Math.max(1, Math.ceil(c.path.length / 900));

    const base = (a: ZoneArt) => Math.min(cw / a.w, ch / a.h);
    const place = (a: ZoneArt, k: Cam, u: number, v: number): [number, number] => {
      const s = base(a) * k.z;
      return [cw / 2 + (u - k.x) * a.w * s, ch / 2 + (v - k.y) * a.h * s];
    };
    const drawZone = (a: ZoneArt, k: Cam, alpha: number) => {
      const s = base(a) * k.z;
      const [x0, y0] = place(a, k, 0, 0);
      ctx.globalAlpha = alpha;
      if (a.img) { ctx.drawImage(a.img, x0, y0, a.w * s, a.h * s); ctx.fillStyle = "rgba(9,8,16,0.28)"; ctx.fillRect(x0, y0, a.w * s, a.h * s); }
      else { ctx.fillStyle = "#1c1a28"; ctx.fillRect(x0, y0, a.w * s, a.h * s); }
      ctx.globalAlpha = 1;
    };

    // ---- moving the map by hand
    const here = () => art(c.zones[Math.max(0, zone)]);
    /** Take the map out of "follow": the view stays where it is and the page is told. */
    const release = () => { if (live.current.follow) { Object.assign(free, cam); live.current.onFree(); } };
    const zoomAt = (px: number, py: number, factor: number) => {
      release();
      const a = here();
      const s = base(a) * cam.z;
      const u = (px - cw / 2) / (a.w * s) + cam.x, v = (py - ch / 2) / (a.h * s) + cam.y;
      const z = clamp(cam.z * factor, 0.5, 9);
      const s2 = base(a) * z;
      cam.x = clamp(u - (px - cw / 2) / (a.w * s2), 0, 1); cam.y = clamp(v - (py - ch / 2) / (a.h * s2), 0, 1); cam.z = z;
      Object.assign(free, cam);
    };
    const pointers = new Map<number, { x: number; y: number }>();
    let pinch = 0;
    const spot = (e: { clientX: number; clientY: number }) => { const r = el.getBoundingClientRect(); return { x: e.clientX - r.left, y: e.clientY - r.top }; };
    const down = (e: PointerEvent) => { if (live.current.overview) return; el.setPointerCapture(e.pointerId); pointers.set(e.pointerId, spot(e)); el.classList.add("is-drag"); pinch = 0; };
    const move = (e: PointerEvent) => {
      const old = pointers.get(e.pointerId);
      if (!old) return;
      const now = spot(e);
      pointers.set(e.pointerId, now);
      if (pointers.size === 2) {
        const [p, q] = [...pointers.values()];
        const dist = Math.hypot(p.x - q.x, p.y - q.y);
        if (pinch) zoomAt((p.x + q.x) / 2, (p.y + q.y) / 2, dist / pinch);
        pinch = dist;
      } else if (pointers.size === 1 && (now.x !== old.x || now.y !== old.y)) {
        release();
        const a = here(), s = base(a) * cam.z;
        cam.x = clamp(cam.x - (now.x - old.x) / (a.w * s), 0, 1); cam.y = clamp(cam.y - (now.y - old.y) / (a.h * s), 0, 1);
        Object.assign(free, cam);
      }
    };
    const up = (e: PointerEvent) => { pointers.delete(e.pointerId); pinch = 0; if (!pointers.size) el.classList.remove("is-drag"); };
    const wheel = (e: WheelEvent) => { if (live.current.overview) return; e.preventDefault(); const p = spot(e); zoomAt(p.x, p.y, Math.exp(-e.deltaY * 0.0016)); };
    const dbl = (e: MouseEvent) => { if (live.current.overview) return; const r = el.getBoundingClientRect(); zoomAt(e.clientX - r.left, e.clientY - r.top, 1.8); };
    el.addEventListener("pointerdown", down); el.addEventListener("pointermove", move); el.addEventListener("pointerup", up); el.addEventListener("pointercancel", up);
    el.addEventListener("wheel", wheel, { passive: false }); el.addEventListener("dblclick", dbl);
    onApi({ zoom: factor => zoomAt(cw / 2, ch / 2, factor) });

    const draw = (now: number) => {
      const p = live.current;
      const dt = Math.min(0.1, (now - lastNow) / 1000); lastNow = now;
      const t = timeRef.current;
      const pos = positionAt(c, t);
      ctx.clearRect(0, 0, cw, ch);
      const bg = ctx.createRadialGradient(cw / 2, ch / 2, 0, cw / 2, ch / 2, Math.max(cw, ch) * 0.7);
      bg.addColorStop(0, "#1b1930"); bg.addColorStop(1, "#0b0b12");
      ctx.fillStyle = bg; ctx.fillRect(0, 0, cw, ch);
      if (!pos) return;
      if (p.overview) {
        // before the start: the zone where most of the journey happened, with the whole way through it
        const a = art(c.zones[longest]);
        const whole: Cam = { x: 0.5, y: 0.5, z: 0.92 };
        drawZone(a, whole, 1);
        ctx.lineCap = "round"; ctx.lineJoin = "round"; ctx.shadowColor = "rgba(90,170,255,0.9)"; ctx.shadowBlur = 8;
        ctx.strokeStyle = "rgba(105,185,255,0.85)"; ctx.lineWidth = 2.4; ctx.beginPath();
        let pen = false;
        for (let i = 0; i < c.path.length; i += overviewStep) {
          const q = c.path[i];
          if (q[1] !== longest) { pen = false; continue; }
          const [sx, sy] = place(a, whole, q[2], q[3]);
          if (pen) ctx.lineTo(sx, sy); else ctx.moveTo(sx, sy);
          pen = true;
        }
        ctx.stroke(); ctx.shadowBlur = 0;
        raf = requestAnimationFrame(draw);
        return;
      }
      const map = art(c.zones[pos.zone]);
      if (wasFollow && !p.follow) Object.assign(free, cam);
      wasFollow = p.follow;
      // following keeps the zoom the visitor chose, but never closer in than a comfortable minimum
      const target: Cam = p.follow ? { x: pos.x, y: pos.y, z: Math.max(cam.z, 2.6) } : free;
      if (zone !== pos.zone) {
        if (zone >= 0 && !p.reduced) { previous = { art: art(c.zones[zone]), cam: { ...cam } }; fadeStart = now; }
        zone = pos.zone;
        Object.assign(free, { x: 0.5, y: 0.5, z: 1 });
        Object.assign(cam, p.follow ? target : free);
      } else {
        const k = 1 - Math.exp(-dt * (p.follow ? 5 : 8));
        cam.x += (target.x - cam.x) * k; cam.y += (target.y - cam.y) * k; cam.z += (target.z - cam.z) * k;
      }
      const fade = Math.min(1, (now - fadeStart) / 900);
      if (previous && fade < 1) drawZone(previous.art, previous.cam, 1); else previous = null;
      drawZone(map, cam, previous ? fade : 1);

      // the whole way through this zone as a dotted line, and the last stretch as a bright glowing one
      const all = pathWindow(c, t, 1e9);
      const stepAll = Math.max(1, Math.ceil(all.length / 500));
      ctx.lineCap = "round"; ctx.lineJoin = "round";
      ctx.setLineDash([1, 7]); ctx.lineWidth = 2; ctx.strokeStyle = "rgba(150,195,255,0.45)"; ctx.beginPath();
      all.forEach((q, i) => { if (i % stepAll && i !== all.length - 1) return; const [sx, sy] = place(map, cam, q[2], q[3]); if (i) ctx.lineTo(sx, sy); else ctx.moveTo(sx, sy); });
      ctx.stroke(); ctx.setLineDash([]);
      const near = pathWindow(c, t, 150);
      const [px, py] = place(map, cam, pos.x, pos.y);
      ctx.shadowColor = "rgba(90,170,255,0.9)"; ctx.shadowBlur = 9;
      for (let i = 1; i < near.length; i++) {
        const a = near[i - 1], b = near[i];
        if (b[0] - a[0] > 15) continue;
        const [ax, ay] = place(map, cam, a[2], a[3]), [bx, by] = place(map, cam, b[2], b[3]);
        ctx.strokeStyle = `rgba(105,185,255,${0.12 + 0.83 * (i / near.length)})`; ctx.lineWidth = 3.2;
        ctx.beginPath(); ctx.moveTo(ax, ay); ctx.lineTo(bx, by); ctx.stroke();
      }
      ctx.shadowBlur = 0;

      // what happened along the way in this zone (only the kinds the filter allows)
      const from = all.length ? all[0][0] : 0;
      let fights = 0;
      ctx.textAlign = "center"; ctx.textBaseline = "middle";
      const badge = (x: number, y: number, r: number, fill: string, glyph: string, ink = "#14121c") => {
        ctx.fillStyle = fill; ctx.strokeStyle = "#14121c"; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(x, y, r, 0, 7); ctx.fill(); ctx.stroke();
        ctx.fillStyle = ink; ctx.font = `700 ${Math.round(r * 1.25)}px Inter, sans-serif`; ctx.fillText(glyph, x, y + 0.5);
      };
      for (const e of eventsBetween(c, from, t)) {
        if (e.k === "kill" && t - e.t < 7 && e.zone === pos.zone) fights++;
        if (e.zone !== pos.zone || e.x === undefined || e.y === undefined || !p.mapTypes.has(typeKey(e))) continue;
        const [ex, ey] = place(map, cam, e.x, e.y);
        if (ex < -20 || ey < -20 || ex > cw + 20 || ey > ch + 20) continue;
        const key = typeKey(e);
        if (e.k === "kill") { ctx.fillStyle = `rgba(226,120,106,${Math.max(0.15, 0.85 - (t - e.t) / 400)})`; ctx.beginPath(); ctx.arc(ex, ey, 3.2, 0, 7); ctx.fill(); }
        else if (key === "quest.accept") badge(ex, ey, 9, "#f2c04b", "!");
        else if (key === "quest.turnin") badge(ex, ey, 9, "#f2c04b", "?");
        else if (key === "quest.abandon") badge(ex, ey, 8, "#9a97a8", "×");
        else if (e.k === "level") badge(ex, ey, 8, "#a78bfa", "★", "#fff");
        else if (e.k === "boss") badge(ex, ey, 11, e.a === "wipe" ? "#9b3b34" : "#d9534f", "☠", "#fff");
        else if (e.k === "dungeon") badge(ex, ey, 10, "#5b8def", e.a === "enter" ? "∩" : "↩", "#fff");
        else if (e.k === "travel") badge(ex, ey, 9, "#5b8def", "➤", "#fff");
        else if (e.k === "death") { ctx.strokeStyle = "#e2786a"; ctx.lineWidth = 3; ctx.beginPath(); ctx.moveTo(ex - 5, ey - 5); ctx.lineTo(ex + 5, ey + 5); ctx.moveTo(ex + 5, ey - 5); ctx.lineTo(ex - 5, ey + 5); ctx.stroke(); }
      }

      // the character, with a ring that pulses and turns red in a fight
      const pulse = p.reduced ? 0.5 : (Math.sin(now / 320) + 1) / 2;
      const ring = fights ? "226,120,106" : "105,204,240";
      ctx.strokeStyle = `rgba(${ring},${0.85 - pulse * 0.6})`; ctx.lineWidth = 2.5;
      ctx.beginPath(); ctx.arc(px, py, 11 + pulse * 9, 0, 7); ctx.stroke();
      ctx.fillStyle = classColor; ctx.strokeStyle = "#fff"; ctx.lineWidth = 2.5; ctx.shadowColor = "rgba(0,0,0,0.6)"; ctx.shadowBlur = 6;
      ctx.beginPath(); ctx.arc(px, py, 8, 0, 7); ctx.fill(); ctx.stroke(); ctx.shadowBlur = 0;

      // messages rise from the character and fade: the newest nearest to it
      const recent = eventsBetween(c, t - 5, t).filter(e => e.k !== "zone" && passes(e, p.iconTypes, p.minQ)).slice(-5);
      ctx.font = "600 13px Inter, sans-serif"; ctx.lineJoin = "round";
      recent.forEach((e, i) => {
        const age = t - e.t, m = popup(e, p.words);
        const fadeOut = Math.min(1, Math.max(0, (5 - age) / 1.5));
        const rise = p.reduced ? 0 : Math.min(age, 3) * 5;
        const y = py - 28 - (recent.length - 1 - i) * 20 - rise;
        ctx.globalAlpha = fadeOut; ctx.lineWidth = 4; ctx.strokeStyle = "rgba(10,9,18,0.92)"; ctx.strokeText(m.text, px, y);
        ctx.fillStyle = m.color; ctx.fillText(m.text, px, y); ctx.globalAlpha = 1;
      });
      raf = requestAnimationFrame(draw);
    };
    raf = requestAnimationFrame(draw);
    return () => {
      cancelAnimationFrame(raf); observer.disconnect();
      el.removeEventListener("pointerdown", down); el.removeEventListener("pointermove", move); el.removeEventListener("pointerup", up); el.removeEventListener("pointercancel", up);
      el.removeEventListener("wheel", wheel); el.removeEventListener("dblclick", dbl);
    };
  }, [c, maps, timeRef, classColor, onApi]);
  return <canvas ref={canvas} className="chr-canvas" role="img" aria-label={c.character.name} />;
}

/** The bar at the bottom: zones and dungeons as stretches, the chosen moments as badges, how busy it was, and a playhead to drag. */
function Timeline({ c, maps, time, dom, types, minQ, instanceList, onSeek, lang }: {
  c: Chronicle; maps: readonly MapDefinition[]; time: number; dom: { from: number; to: number }; types: ReadonlySet<string>; minQ: number; instanceList: readonly Instance[]; onSeek: (t: number) => void; lang: string;
}) {
  const span = Math.max(1, dom.to - dom.from);
  const runs = useMemo(() => visits(c).filter(r => r.to > dom.from && r.from < dom.to), [c, dom.from, dom.to]);
  const bars = useRef<HTMLCanvasElement>(null);
  const track = useRef<HTMLDivElement>(null);
  const dragging = useRef(false);
  const [hover, setHover] = useState<number | null>(null);
  const pct = (t: number) => `${clamp(((t - dom.from) / span) * 100, 0, 100)}%`;
  const marks = useMemo(() => {
    const out: { t: number; key: string; label: string }[] = [];
    const gap = span / 240;
    const last: Record<string, number> = {};
    for (const e of eventsBetween(c, dom.from, dom.to)) {
      const key = typeKey(e);
      if (!MARK[key] || !passes(e, types, minQ) || e.t - (last[key] ?? -1e9) < gap) continue;
      last[key] = e.t; out.push({ t: e.t, key, label: e.text });
    }
    return out;
  }, [c, dom.from, dom.to, span, types, minQ]);
  const levels = useMemo(() => eventsBetween(c, dom.from, dom.to).filter(e => e.k === "level").map(e => ({ t: e.t, n: e.n ?? 0 })), [c, dom.from, dom.to]);
  useEffect(() => {
    const el = bars.current;
    const ctx = el?.getContext("2d");
    if (!el || !ctx) return;
    const W = el.width = 600, H = el.height = 20, n = 200;
    const bins = new Array<number>(n).fill(0);
    for (const e of eventsBetween(c, dom.from, dom.to)) bins[Math.min(n - 1, Math.floor(((e.t - dom.from) / span) * n))]++;
    const peak = Math.max(1, ...bins);
    ctx.clearRect(0, 0, W, H);
    bins.forEach((v, i) => { if (!v) return; const h = Math.max(2, (v / peak) * H); ctx.fillStyle = "rgba(226,120,106,0.75)"; ctx.fillRect((i / n) * W, H - h, W / n - 0.6, h); });
  }, [c, dom.from, span, dom.to]);
  const at = (event: { clientX: number }) => {
    const box = track.current?.getBoundingClientRect();
    return box ? clamp(dom.from + ((event.clientX - box.left) / box.width) * span, dom.from, dom.to) : dom.from;
  };
  const down = (event: ReactPointerEvent) => { dragging.current = true; (event.currentTarget as HTMLElement).setPointerCapture(event.pointerId); onSeek(at(event)); };
  const move = (event: ReactPointerEvent) => { setHover(at(event)); if (dragging.current) onSeek(at(event)); };
  const band = (from: number, to: number) => ({ left: pct(from), width: `calc(${(clamp(to, dom.from, dom.to) - clamp(from, dom.from, dom.to)) / span * 100}% - 2px)` });
  return (
    <div className="chr-timeline">
      <div className="chr-levels" aria-hidden="true">{levels.map(l => <span key={l.t} style={{ left: pct(l.t) }}>{l.n}</span>)}</div>
      <div className="chr-zones" aria-hidden="true">
        {runs.map((r, i) => <span key={i} style={{ ...band(r.from, r.to), background: `hsl(${hue(c.zones[r.zone])} 38% 30% / .92)` }}>{nameOf(maps, c.zones[r.zone], lang)}</span>)}
        {instanceList.filter(x => (x.to ?? c.duration) > dom.from && x.from < dom.to).map((x, i) => <span key={`i${i}`} className="chr-instance" style={band(x.from, x.to ?? c.duration)}>∩ {x.name}</span>)}
      </div>
      <div ref={track} className="chr-track" role="slider" tabIndex={-1} aria-label="Timeline" aria-valuemin={Math.round(dom.from)} aria-valuemax={Math.round(dom.to)} aria-valuenow={Math.round(time)} aria-valuetext={clock(time)}
        onPointerDown={down} onPointerMove={move} onPointerUp={() => { dragging.current = false; }} onPointerLeave={() => setHover(null)}>
        <i className="chr-fill" style={{ width: pct(time) }} />
        {marks.map((m, i) => <b key={i} className="chr-mark" style={{ left: pct(m.t), ["--mark" as string]: MARK[m.key].c }} title={m.label}>{MARK[m.key].g}</b>)}
        <u className="chr-head" style={{ left: pct(time) }} />
        {hover !== null && <em className="chr-hover" style={{ left: pct(hover) }}>{clock(hover)}</em>}
      </div>
      <canvas ref={bars} className="chr-bars" aria-hidden="true" />
    </div>
  );
}

/** One collapsible block of the left panel. */
const Block = ({ title, children, open = true }: { title: string; children: ReactNode; open?: boolean }) => (
  <details className="chr-block" open={open}><summary>{title}</summary>{children}</details>
);
const ICONS: Record<string, string> = {
  moments: "M5 4h11a2 2 0 0 1 2 2v13H7a2 2 0 0 1-2-2V4zm2 3v10h9V6H7zm1.5 2h6v1.5h-6V9zm0 3h6v1.5h-6V12z",
  days: "M7 2v2H5a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2h-2V2h-2v2H9V2H7zm-2 8h14v9H5v-9z",
  filter: "M3 5h18l-7 8v6l-4-2v-4L3 5z",
  menu: "M4 6h16v2H4V6zm0 5h16v2H4v-2zm0 5h16v2H4v-2z",
};
const Glyph = ({ name }: { name: string }) => <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true"><path d={ICONS[name]} fill="currentColor" /></svg>;

function Calendar({ days, range, onPick, w, lang }: { days: readonly Day[]; range: { from: number; to: number } | null; onPick: (r: { from: number; to: number } | null) => void; w: Words; lang: string }) {
  const [first, setFirst] = useState<Day | null>(null);
  const byKey = useMemo(() => new Map(days.map(d => [d.key, d])), [days]);
  const peak = Math.max(1, ...days.map(d => d.events));
  const months = useMemo(() => {
    if (!days.length) return [];
    const parse = (k: string) => { const [y, m] = k.split("-").map(Number); return y * 12 + (m - 1); };
    const lo = parse(days[0].key), hi = parse(days[days.length - 1].key);
    const out: { y: number; m: number }[] = [];
    for (let i = hi; i >= Math.max(lo, hi - 5); i--) out.push({ y: Math.floor(i / 12), m: i % 12 });
    return out;
  }, [days]);
  const pick = (d: Day) => {
    if (!first) { setFirst(d); onPick({ from: d.from, to: d.to }); return; }
    onPick({ from: Math.min(first.from, d.from), to: Math.max(first.to, d.to) }); setFirst(null);
  };
  const monthName = (y: number, m: number) => new Date(y, m, 1).toLocaleDateString(lang === "cs" ? "cs-CZ" : "en-GB", { month: "long", year: "numeric" });
  const weekday = (i: number) => new Date(2024, 0, 1 + i).toLocaleDateString(lang === "cs" ? "cs-CZ" : "en-GB", { weekday: "narrow" });
  return (
    <div>
      <div className="chr-pop-actions">
        <button type="button" onClick={() => { const d = days[days.length - 1]; if (d) { setFirst(null); onPick({ from: d.from, to: d.to }); } }}>{w.lastDay}</button>
        <button type="button" onClick={() => { setFirst(null); onPick(null); }}>{w.whole}</button>
      </div>
      {months.map(({ y, m }) => {
        const lead = (new Date(y, m, 1).getDay() + 6) % 7, count = new Date(y, m + 1, 0).getDate();
        return (
          <section key={`${y}-${m}`} className="chr-month">
            <h4>{monthName(y, m)}</h4>
            <div className="chr-grid">
              {Array.from({ length: 7 }, (_, i) => <b key={`h${i}`}>{weekday(i)}</b>)}
              {Array.from({ length: lead }, (_, i) => <i key={`l${i}`} />)}
              {Array.from({ length: count }, (_, i) => {
                const key = `${y}-${String(m + 1).padStart(2, "0")}-${String(i + 1).padStart(2, "0")}`;
                const d = byKey.get(key);
                const inRange = d && range && d.from >= range.from - 1e-6 && d.to <= range.to + 1e-6;
                return d
                  ? <button key={key} type="button" className={inRange ? "is-range" : ""} style={{ ["--heat" as string]: 0.25 + 0.6 * (d.events / peak) }} onClick={() => pick(d)}>{i + 1}</button>
                  : <span key={key}>{i + 1}</span>;
              })}
            </div>
          </section>
        );
      })}
      <p className="chr-muted">{w.pickDays}</p>
    </div>
  );
}

function Filters({ w, counts, sets, minQ, setMinQ, setSets, defaults }: {
  w: Words; counts: Record<string, number>; sets: Record<string, ReadonlySet<string>>; minQ: number; setMinQ: (q: number) => void;
  setSets: (tab: string, next: ReadonlySet<string>) => void; defaults: Record<string, ReadonlySet<string>>;
}) {
  const [tab, setTab] = useState<"timeline" | "map" | "icon">("timeline");
  const set = sets[tab];
  const flip = (keys: string[], on: boolean) => { const next = new Set(set); for (const k of keys) { if (on) next.add(k); else next.delete(k); } setSets(tab, next); };
  return (
    <div>
      <div className="chr-pop-head"><h3>{w.show}</h3><button type="button" onClick={() => { for (const t of ["timeline", "map", "icon"]) setSets(t, defaults[t]); setMinQ(2); }}>{w.reset}</button></div>
      <div className="chr-seg" role="tablist">{(["timeline", "map", "icon"] as const).map(id => <button key={id} type="button" role="tab" aria-selected={tab === id} className={tab === id ? "is-on" : ""} onClick={() => setTab(id)}>{w.tabs[id]}</button>)}</div>
      <p className="chr-muted">{w.tabNote[tab]}</p>
      <div className="chr-quality"><span>{w.itemsList}</span><b>{w.quality[Math.min(4, minQ)]} {minQ > 0 ? w.andBetter : ""}</b></div>
      <div className="chr-seg is-quality">{w.quality.map((name, q) => <button key={name} type="button" className={q === minQ ? "is-on" : ""} style={{ ["--q" as string]: QUALITY[q] }} onClick={() => setMinQ(q)}>{name}</button>)}</div>
      {CATEGORIES.map(cat => {
        const keys = TYPE_KEYS[cat];
        const on = keys.filter(k => set.has(k)).length;
        return (
          <fieldset key={cat} className="chr-group">
            <label className="chr-check is-master"><input type="checkbox" checked={on === keys.length} ref={el => { if (el) el.indeterminate = on > 0 && on < keys.length; }} onChange={event => flip(keys, event.target.checked)} /> {w.cat[cat]}</label>
            <div>{keys.map(k => (
              <label key={k} className="chr-check" style={{ ["--mark" as string]: MARK[k].c }}>
                <input type="checkbox" checked={set.has(k)} onChange={event => flip([k], event.target.checked)} /> {w.types[k]} <small>{counts[k] ?? 0}</small>
              </label>
            ))}</div>
          </fieldset>
        );
      })}
    </div>
  );
}

/** The ring of the start screen: the whole journey as coloured stretches, each in the colour of what filled it most. */
function journeyRing(c: Chronicle): { d: string; color: string; opacity: number }[] {
  const n = 96, gap = 0.018, r0 = 70, r1 = 90;
  const bins = Array.from({ length: n }, () => ({ total: 0, by: {} as Record<string, number> }));
  for (const e of c.events) { const b = bins[Math.min(n - 1, Math.floor((e.t / c.duration) * n))]; const cat = categoryOf(e.k); b.total++; b.by[cat] = (b.by[cat] ?? 0) + 1; }
  const peak = Math.max(1, ...bins.map(b => b.total));
  const point = (a: number, r: number) => `${(100 + r * Math.sin(a)).toFixed(2)} ${(100 - r * Math.cos(a)).toFixed(2)}`;
  return bins.map((b, i) => {
    const a0 = (i / n) * Math.PI * 2 + gap, a1 = ((i + 1) / n) * Math.PI * 2 - gap;
    const top = Object.entries(b.by).sort((x, y) => y[1] - x[1])[0];
    return {
      d: `M ${point(a0, r1)} A ${r1} ${r1} 0 0 1 ${point(a1, r1)} L ${point(a1, r0)} A ${r0} ${r0} 0 0 0 ${point(a0, r0)} Z`,
      color: top ? COLORS[top[0] as Category] : "#ffffff", opacity: top ? 0.45 + 0.55 * (b.total / peak) : 0.1,
    };
  });
}
const DEFAULT_SETS = { timeline: new Set(SHOWN_ON_TIMELINE), map: new Set(SHOWN_ON_MAP), icon: new Set(ALL_TYPES) } as Record<string, ReadonlySet<string>>;

function Player({ c, maps, onBack }: { c: Chronicle; maps: readonly MapDefinition[]; onBack: () => void }) {
  const { lang } = useI18n();
  const w = TEXT[lang === "cs" ? "cs" : "en"];
  const index = useMemo(() => buildIndex(c), [c]);
  const counts = useMemo(() => countByCategory(c), [c]);
  const typeCounts = useMemo(() => countByType(c), [c]);
  const days = useMemo(() => daysOf(c), [c]);
  const instanceList = useMemo(() => instances(c), [c]);
  const root = useRef<HTMLDivElement>(null);
  const stage = useRef<StageApi | null>(null);
  const timeRef = useRef(0);
  const [time, setTime] = useState(0);
  const [playing, setPlaying] = useState(false);
  const [started, setStarted] = useState(false);
  const [help, setHelp] = useState(false);
  const [speed, setSpeed] = useState<number>(20);
  const [follow, setFollow] = useState(true);
  const [skipIdle, setSkipIdle] = useState(true);
  const [panel, setPanel] = useState(() => typeof window === "undefined" || window.innerWidth > 900);
  const [pop, setPop] = useState<null | "days" | "filters" | "menu">(null);
  const [range, setRange] = useState<{ from: number; to: number } | null>(null);
  const [filters, setFilters] = useState<ReadonlySet<Category>>(new Set(CATEGORIES));
  const [sets, setSetsState] = useState<Record<string, ReadonlySet<string>>>(DEFAULT_SETS);
  const [minQ, setMinQ] = useState(2);
  const reduced = useMemo(() => typeof window !== "undefined" && window.matchMedia("(prefers-reduced-motion: reduce)").matches, []);
  const dom = useMemo(() => range ?? { from: 0, to: c.duration }, [range, c.duration]);

  useEffect(() => {
    if (!playing) return;
    let raf = 0, last = performance.now(), ui = 0;
    const tick = (now: number) => {
      // wall-clock time: only a long pause (a hidden tab) is cut short, so a slow frame rate does not slow the playback
      const dt = Math.min(0.5, (now - last) / 1000); last = now;
      const next = c.events[eventAt(c, timeRef.current) + 1];
      const rate = speed * (skipIdle && next && next.t - timeRef.current > 20 ? 4 : 1);
      timeRef.current = Math.min(dom.to, timeRef.current + dt * rate);
      if (now - ui > 100) { ui = now; setTime(timeRef.current); }
      if (timeRef.current >= dom.to) { setTime(dom.to); setPlaying(false); return; }
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [playing, speed, skipIdle, c, dom.to]);

  const seek = useCallback((t: number) => { timeRef.current = clamp(t, dom.from, dom.to); setTime(timeRef.current); }, [dom.from, dom.to]);
  const toggle = useCallback(() => { setStarted(true); if (!playing && timeRef.current >= dom.to) seek(dom.from); setPlaying(p => !p); }, [playing, dom.to, dom.from, seek]);
  const pickRange = useCallback((r: { from: number; to: number } | null) => { setRange(r); const t = r ? r.from : 0; timeRef.current = t; setTime(t); }, []);
  const onFree = useCallback(() => setFollow(false), []);
  const onApi = useCallback((api: StageApi) => { stage.current = api; }, []);
  const ring = useMemo(() => journeyRing(c), [c]);
  const total = useMemo(() => totalsAt(index, c.duration), [index, c]);

  const totals = totalsAt(index, time);
  const pos = positionAt(c, time);
  const zoneName = pos ? nameOf(maps, c.zones[pos.zone], lang) : "";
  const shown = useMemo(() => c.events.filter(e => filters.has(categoryOf(e.k)) && (e.k !== "loot" || (e.q ?? 1) >= minQ)), [c, filters, minQ]);
  const split = useMemo(() => { let n = 0; for (const e of shown) { if (e.t > time) break; n++; } return n; }, [shown, time]);
  const list = shown.slice(Math.max(0, split - 12), split + 6);
  const currentEvent = split > 0 ? shown[split - 1] : null;
  const stats = statsAt(c, time);
  const inside = instanceAt(instanceList, time);
  const insideSummary = inside ? instanceSummary(c, inside, time) : null;
  const recentWindow = useMemo(() => {
    const kills = new Map<string, number>(), items = new Map<string, { n: number; q: number }>();
    for (const e of eventsBetween(c, time - 90, time)) {
      if (e.k === "kill") kills.set(e.text, (kills.get(e.text) ?? 0) + 1);
      else if (e.k === "loot" && (e.q ?? 1) >= minQ) { const x = items.get(e.text); items.set(e.text, { n: (x?.n ?? 0) + (e.n ?? 1), q: e.q ?? 1 }); }
    }
    return { kills: [...kills].sort((a, b) => b[1] - a[1]).slice(0, 8), items: [...items].slice(-8) };
  }, [c, time, minQ]);
  const when = (t: number) => new Date(whenOf(c, t) * 1000).toLocaleString(lang === "cs" ? "cs-CZ" : "en-GB", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit", second: "2-digit" });
  const cls = CLASSES[c.character.classId] as unknown;
  const className = typeof cls === "string" ? cls : (cls as { name?: string } | undefined)?.name ?? "";
  const color = CLASS_COLORS[c.character.classId] ?? "#69ccf0";
  const setSets = (tab: string, next: ReadonlySet<string>) => setSetsState(prev => ({ ...prev, [tab]: next }));

  const key = (event: React.KeyboardEvent) => {
    const big = event.shiftKey ? 60 : 10;
    if (event.key === "?") setHelp(v => !v);
    else if (event.key === "Escape") { setHelp(false); setPop(null); }
    else if (event.key === " ") { event.preventDefault(); toggle(); }
    else if (event.key === "ArrowRight") { event.preventDefault(); seek(timeRef.current + big); }
    else if (event.key === "ArrowLeft") { event.preventDefault(); seek(timeRef.current - big); }
    else if (event.key === "f") setFollow(v => !v);
    else if (event.key === "m") setPanel(v => !v);
    else if (event.key === "+" || event.key === "=") setSpeed(s => SPEEDS[Math.min(SPEEDS.length - 1, SPEEDS.indexOf(s as (typeof SPEEDS)[number]) + 1)]);
    else if (event.key === "-") setSpeed(s => SPEEDS[Math.max(0, SPEEDS.indexOf(s as (typeof SPEEDS)[number]) - 1)]);
  };
  const fullscreen = () => { if (document.fullscreenElement) void document.exitFullscreen(); else void root.current?.requestFullscreen?.(); };
  const stat = (v: string, l: string) => <div key={l}><dt>{v}</dt><dd>{l}</dd></div>;

  return (
    <div ref={root} className={`chr${started ? "" : " is-intro"}`} tabIndex={0} onKeyDown={key} aria-label={w.title}>
      <Stage c={c} maps={maps} timeRef={timeRef} onApi={onApi} props={{ follow, overview: !started, reduced, words: w, mapTypes: sets.map, iconTypes: sets.icon, minQ, onFree }} />
      <div className="chr-vignette" aria-hidden="true" />
      <div className="chr-top">
        <button type="button" className="chr-btn" onClick={onBack}><Icon name="map" size={15} /> {w.back}</button>
        <span className="chr-spacer" />
        <div className="chr-pill">
          <button type="button" className={panel ? "is-on" : ""} onClick={() => setPanel(v => !v)} aria-pressed={panel} aria-label={w.moments} title={w.moments}><Glyph name="moments" /></button>
          <button type="button" className={pop === "days" ? "is-on" : ""} onClick={() => setPop(p => (p === "days" ? null : "days"))} aria-pressed={pop === "days"} aria-label={w.days} title={w.days}><Glyph name="days" /></button>
          <button type="button" className={pop === "filters" ? "is-on" : ""} onClick={() => setPop(p => (p === "filters" ? null : "filters"))} aria-pressed={pop === "filters"} aria-label={w.show} title={w.show}><Glyph name="filter" /></button>
          <button type="button" className={pop === "menu" ? "is-on" : ""} onClick={() => setPop(p => (p === "menu" ? null : "menu"))} aria-pressed={pop === "menu"} aria-label={w.menu} title={w.menu}><Glyph name="menu" /></button>
        </div>
      </div>

      {!started && (
        <div className="chr-intro">
          <p className="chr-eyebrow">{w.of}</p>
          <h1 style={{ color: "#d4a574" }}>{c.character.name}</h1>
          <p className="chr-sub">{[className, c.character.guild ? `<${c.character.guild}>` : null, `${w.level} ${total.level}`].filter(Boolean).join(" · ")}</p>
          <button type="button" className="chr-ring" onClick={toggle} aria-label={w.play}>
            <svg viewBox="0 0 200 200" aria-hidden="true">{ring.map((seg, i) => <path key={i} d={seg.d} fill={seg.color} opacity={seg.opacity} />)}</svg>
            <span><svg viewBox="0 0 24 24" width="34" height="34" aria-hidden="true"><path d="M8 5v14l11-7z" fill="currentColor" /></svg></span>
          </button>
          <p className="chr-big"><b>{clock(c.duration)}</b> {w.played} <b>{total.kills.toLocaleString()}</b> {w.kills} <b>{total.quests}</b> {w.quests} <b>{total.items.toLocaleString()}</b> {w.items} <b>{total.places}</b> {w.places}</p>
          <p className="chr-hint"><kbd>{lang === "cs" ? "Mezerník" : "Space"}</kbd> {w.toPlay} <i /> <kbd>?</kbd> {w.forHelp}</p>
        </div>
      )}
      {help && (
        <div className="chr-help" role="dialog" aria-label={w.helpTitle} onClick={() => setHelp(false)}>
          <div><h3>{w.helpTitle}</h3><dl>{w.keys.map(([k, v]) => <div key={k}><dt><kbd>{k}</kbd></dt><dd>{v}</dd></div>)}</dl></div>
        </div>
      )}

      {pop && (
        <div className="chr-card chr-pop" role="dialog" aria-label={pop === "days" ? w.days : pop === "filters" ? w.show : w.menu}>
          <button type="button" className="chr-x" onClick={() => setPop(null)} aria-label="×">×</button>
          {pop === "days" && <><h3 className="chr-pop-title">{w.days}</h3><Calendar days={days} range={range} onPick={pickRange} w={w} lang={lang} /></>}
          {pop === "filters" && <Filters w={w} counts={typeCounts} sets={sets} minQ={minQ} setMinQ={setMinQ} setSets={setSets} defaults={DEFAULT_SETS} />}
          {pop === "menu" && (
            <div className="chr-menu">
              <h3 className="chr-pop-title">{w.menu}</h3>
              <label className="chr-check"><input type="checkbox" checked={follow} onChange={event => setFollow(event.target.checked)} /> {w.follow}</label>
              <label className="chr-check"><input type="checkbox" checked={skipIdle} onChange={event => setSkipIdle(event.target.checked)} /> {w.idle}</label>
              <div className="chr-quality"><span>{w.speed}</span></div>
              <div className="chr-seg">{SPEEDS.map(s => <button key={s} type="button" className={speed === s ? "is-on" : ""} onClick={() => setSpeed(s)}>{s}×</button>)}</div>
              <button type="button" className="chr-btn" onClick={fullscreen}>⛶ {w.full}</button>
            </div>
          )}
        </div>
      )}

      <aside className="chr-card chr-left">
        <header>
          <span className="chr-level" style={{ borderColor: color }}>{totals.level}</span>
          <div><h2 style={{ color }}>{c.character.name}</h2>
            <p>{[c.character.race, className, c.character.faction].filter(Boolean).join(" · ")}</p>
            {c.character.guild && <p className="chr-guild">&lt;{c.character.guild}&gt;</p>}</div>
        </header>
        <p className="chr-where"><strong>{zoneName}</strong>{pos && <span>{(pos.x * 100).toFixed(1)}, {(pos.y * 100).toFixed(1)}</span>}</p>
        <p className="chr-played">{clock(time)} {w.recorded} · <b>{moneyText(totals.copper)}</b></p>
        <Block title={w.sofar}>
          <dl className="chr-stats">{stat(String(totals.quests), w.quests)}{stat(String(totals.kills), w.kills)}{stat(totals.xp.toLocaleString(), w.xp)}{stat(moneyText(totals.copper), w.money)}{stat(String(totals.items), w.items)}{stat(String(totals.places), w.places)}</dl>
          {totals.deaths > 0 && <p className="chr-deaths">{totals.deaths} {w.deaths}</p>}
        </Block>
        {stats && (
          <Block title={w.sheet}>
            {stats.ilvl !== undefined && <p className="chr-ilvl"><span>{w.itemLevel}</span><b>{stats.ilvl}</b></p>}
            {stats.attrs && stats.attrs.length > 0 && <><h4>{w.attributes}</h4><dl className="chr-rows">{stats.attrs.map(([n, v]) => <div key={n}><dt>{n}</dt><dd>{v.toLocaleString()}</dd></div>)}</dl></>}
            {stats.enh && stats.enh.length > 0 && <><h4>{w.enhancements}</h4><dl className="chr-rows">{stats.enh.map(([n, v]) => <div key={n}><dt>{n}</dt><dd>{v}</dd></div>)}</dl></>}
            <p className="chr-muted">{w.notedAt} {clock(stats.t)}</p>
          </Block>
        )}
        {Object.keys(totals.skills).length > 0 && (
          <Block title={w.skills}>
            <h4>{w.professions}</h4>
            {Object.entries(totals.skills).map(([name, [v, max]]) => <div key={name} className="chr-skill"><span>{name}</span><b>{v}/{max}</b><i><u style={{ width: `${(v / max) * 100}%` }} /></i></div>)}
          </Block>
        )}
      </aside>

      {inside && insideSummary && (
        <aside className="chr-card chr-instance-card">
          <h3>{w.inInstance} {inside.name}</h3>
          {inside.detail && <p className="chr-muted">{inside.detail}</p>}
          <dl className="chr-stats is-row">{stat(String(insideSummary.kills), w.kills)}{stat(String(insideSummary.deaths), w.deaths)}{stat(String(insideSummary.items), w.items)}{stat(moneyText(insideSummary.copper), w.money)}</dl>
          <ul className="chr-bosses">
            {insideSummary.bosses.map((b, i) => (
              <li key={i} className={b.a === "wipe" ? "is-wipe" : "is-kill"}>
                <strong>{b.text}{b.n && b.n > 1 ? ` · ${w.pull} ${b.n}` : ""}</strong>
                <span>{b.a === "wipe" ? w.wiped : w.killedIn} {clock(b.d ?? 0)}</span>
                {b.detail && <small>{b.detail}</small>}
              </li>
            ))}
          </ul>
        </aside>
      )}

      {panel && (
        <aside className="chr-card chr-right">
          <div className="chr-chips" role="group" aria-label={w.moments}>
            {CATEGORIES.map(cat => (
              <button key={cat} type="button" className={filters.has(cat) ? "is-on" : ""} aria-pressed={filters.has(cat)} style={{ ["--chip" as string]: COLORS[cat] }}
                onClick={() => setFilters(prev => { const next = new Set(prev); if (next.has(cat)) next.delete(cat); else next.add(cat); return next; })}>{w.cat[cat]} <b>{counts[cat]}</b></button>
            ))}
          </div>
          {split > 12 && <p className="chr-muted">{split - 12} {w.earlier}</p>}
          <ol className="chr-moments">
            {list.length === 0 && <li className="chr-muted">{w.none}</li>}
            {list.map(e => (
              <li key={`${e.t}${e.k}${e.text}`} className={e === currentEvent ? "is-current" : ""} style={{ ["--chip" as string]: COLORS[categoryOf(e.k)] }}>
                <button type="button" onClick={() => seek(e.t)}><time>{clock(e.t)}</time><span>{popup(e, w).text}{e.detail && <small>{e.detail}</small>}</span></button>
              </li>
            ))}
          </ol>
          {shown.length - split - 6 > 0 && <p className="chr-muted">{shown.length - split - 6} {w.later}</p>}
          {currentEvent && (
            <section className="chr-detail">
              <h3>{popup(currentEvent, w).text}</h3>
              <p className="chr-muted">{clock(currentEvent.t)} {w.into} · {when(currentEvent.t)}{c.sessions?.length ? ` · ${w.session} ${sessionAt(c, currentEvent.t) + 1}` : ""}</p>
              <h4>{w.what}</h4>
              <dl>
                <div><dt>{w.type}</dt><dd>{w.kind[currentEvent.k]}{currentEvent.a ? ` · ${currentEvent.a}` : ""}</dd></div>
                {currentEvent.zone !== undefined && <div><dt>{w.where}</dt><dd>{nameOf(maps, c.zones[currentEvent.zone], lang)}{currentEvent.x !== undefined && currentEvent.y !== undefined ? ` ${(currentEvent.x * 100).toFixed(1)}, ${(currentEvent.y * 100).toFixed(1)}` : ""}</dd></div>}
                {currentEvent.xp ? <div><dt>{w.reward}</dt><dd>+{currentEvent.xp} XP</dd></div> : null}
                {currentEvent.k === "loot" && currentEvent.n ? <div><dt>{w.amount}</dt><dd>×{currentEvent.n}</dd></div> : null}
                {currentEvent.k === "boss" && currentEvent.d !== undefined ? <div><dt>{w.fight}</dt><dd>{clock(currentEvent.d)}{currentEvent.n ? ` · ${w.attempt} ${currentEvent.n}` : ""}</dd></div> : null}
                {currentEvent.detail ? <div><dt>{w.what}</dt><dd>{currentEvent.detail}</dd></div> : null}
              </dl>
            </section>
          )}
          {(recentWindow.kills.length > 0 || recentWindow.items.length > 0) && (
            <section className="chr-recent">
              <div><h4>{w.killsList}</h4>{recentWindow.kills.map(([n, k]) => <p key={n}><span>{n}</span>{k > 1 && <b>×{k}</b>}</p>)}</div>
              <div><h4>{w.itemsList}</h4>{recentWindow.items.map(([n, x]) => <p key={n} style={{ color: QUALITY[x.q] }}><span>{n}</span>{x.n > 1 && <b>×{x.n}</b>}</p>)}</div>
            </section>
          )}
        </aside>
      )}

      <div className={`chr-zoom${panel ? " is-shifted" : ""}`}>
        <button type="button" onClick={() => stage.current?.zoom(1.5)} aria-label={w.zoomIn}>+</button>
        <button type="button" onClick={() => stage.current?.zoom(1 / 1.5)} aria-label={w.zoomOut}>−</button>
        <button type="button" className={follow ? "is-on" : ""} onClick={() => setFollow(true)} aria-label={w.centre} title={w.centre}>
          <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true"><circle cx="12" cy="12" r="3.2" fill="none" stroke="currentColor" strokeWidth="2" /><path d="M12 2v5M12 17v5M2 12h5M17 12h5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" /></svg>
        </button>
      </div>

      <footer className="chr-bar">
        <button type="button" className="chr-play" onClick={toggle} aria-label={playing ? w.pause : time >= dom.to ? w.replay : w.play}>
          {playing ? <svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true"><rect x="6" y="5" width="4" height="14" rx="1" fill="currentColor" /><rect x="14" y="5" width="4" height="14" rx="1" fill="currentColor" /></svg>
            : <svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true"><path d="M8 5v14l11-7z" fill="currentColor" /></svg>}
        </button>
        <Timeline c={c} maps={maps} time={time} dom={dom} types={sets.timeline} minQ={minQ} instanceList={instanceList} onSeek={seek} lang={lang} />
        <div className="chr-clock"><b>{clock(time)} / {clock(c.duration)}</b><span>{when(time)}</span></div>
        <button type="button" className="chr-speed" onClick={() => setSpeed(s => SPEEDS[(SPEEDS.indexOf(s as (typeof SPEEDS)[number]) + 1) % SPEEDS.length])} aria-label={w.speed}>{speed}×</button>
      </footer>
    </div>
  );
}

/** The page: a start screen, or the player once a recording is chosen (`#chronicle/demo` starts the demo at once). */
export function ChronicleView({ route }: { route: string }) {
  const { lang } = useI18n();
  const w = TEXT[lang === "cs" ? "cs" : "en"];
  const maps = useMaps();
  const demoRequested = route.split("?")[0] === "demo";
  const [opened, setOpened] = useState<Chronicle | null>(null);
  const [problem, setProblem] = useState("");
  const [over, setOver] = useState(false);
  const demo = useMemo(() => (demoRequested ? demoChronicle() : null), [demoRequested]);
  const chronicle = opened ?? demo;

  const read = async (file: File | undefined) => {
    if (!file) return;
    if (file.size > 40_000_000) { setProblem(w.bad); return; }
    try {
      const parsed = parseChronicle(JSON.parse(await file.text()));
      if (parsed) { setOpened(parsed); setProblem(""); } else setProblem(w.bad);
    } catch { setProblem(w.unreadable); }
  };

  if (chronicle) {
    if (!maps.data) return <div className="chr-start"><p className="muted">{w.loading}</p></div>;
    return <Player key={chronicle.startedAt + chronicle.duration} c={chronicle} maps={maps.data} onBack={() => { setOpened(null); window.location.hash = "chronicle"; }} />;
  }
  return (
    <div className="chr-start page-column">
      <h1>{w.title}</h1>
      <p className="chr-lead">{w.lead}</p>
      <div className={`chr-drop${over ? " is-over" : ""}`}
        onDragOver={event => { event.preventDefault(); setOver(true); }} onDragLeave={() => setOver(false)}
        onDrop={event => { event.preventDefault(); setOver(false); void read(event.dataTransfer.files[0]); }}>
        <a className="btn btn-primary" href="#chronicle/demo">{w.demo}</a>
        <label className="btn btn-ghost">{w.open}<input type="file" accept="application/json,.json" hidden onChange={event => void read(event.target.files?.[0])} /></label>
        <span className="muted small">{w.drop}</span>
      </div>
      {problem && <p className="pp-notice" role="alert">{problem}</p>}
      <p className="muted small">{w.note}</p>
    </div>
  );
}

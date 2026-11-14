"use client";
// The replay of a recorded journey: a map that follows the character, a timeline with the zones and the notable moments,
// the numbers so far and the list of everything that happened. It runs entirely in the browser from one recording.
import { useCallback, useEffect, useMemo, useRef, useState, type PointerEvent as ReactPointerEvent } from "react";
import { useI18n } from "@/lib/i18n";
import {
  CATEGORIES, buildIndex, categoryOf, clock, countByCategory, demoChronicle, eventAt, eventsBetween, moneyText, parseChronicle,
  pathWindow, positionAt, totalsAt, visits, type Category, type Chronicle, type ChronicleEvent,
} from "@/lib/chronicle";
import { CLASS_COLORS, CLASSES } from "../data";
import { Icon } from "../ui";
import { useMaps } from "../db/store";
import type { MapDefinition } from "../world-map";

const SPEEDS = [1, 5, 20, 60, 200] as const;
const COLORS: Record<Category, string> = { quests: "#f2c04b", combat: "#e2786a", loot: "#c9c4d6", professions: "#5fb98d", travel: "#7fb2ff", character: "#a78bfa" };
const QUALITY = ["#9d9d9d", "#ffffff", "#1eff00", "#0070dd", "#a335ee", "#ff8000"];
const TEXT = {
  en: {
    of: "The journey of", toPlay: "to play", forHelp: "for shortcuts", helpTitle: "Keyboard", keys: [["Space", "Play / pause"], ["← →", "Back / forward 10 s (Shift: 60 s)"], ["F", "Follow the character / whole zone"], ["M", "Show or hide the moments"], ["+  −", "Faster / slower"], ["?", "This help"]] as [string, string][],
    title: "Journey replay", lead: "Watch a whole journey again: where the character walked, what it fought, found and finished, on a timeline you can scrub.",
    demo: "Play the demo", open: "Open a recording", drop: "or drop a recording file here",
    note: "The addon does not write recordings yet. The demo is a generated journey, not a real player's. A real recording uses the same format.",
    bad: "This file is not a valid recording.", unreadable: "The file could not be read.", loading: "Loading maps…",
    play: "Play", pause: "Pause", replay: "Play again", speed: "Speed", follow: "Follow", whole: "Whole zone", idle: "Skip quiet stretches", moments: "Moments", close: "Close", full: "Full screen",
    sofar: "So far", quests: "quests done", kills: "kills", xp: "XP", money: "money", items: "items", places: "places", deaths: "deaths", skills: "Skills",
    recorded: "recorded", earlier: "earlier moments not shown", later: "later moments not shown", what: "What happened", where: "Where", type: "Type", amount: "Amount", reward: "Experience",
    into: "into the journey", back: "Back to the start", none: "Nothing to show here yet.",
    cat: { quests: "Quests", combat: "Combat", loot: "Loot and money", professions: "Professions", travel: "Travel", character: "Character" } as Record<Category, string>,
    kind: { quest: "Quest", kill: "Kill", loot: "Loot", money: "Money", level: "Level", skill: "Skill", zone: "Zone", death: "Death", dungeon: "Dungeon", travel: "Travel" } as Record<string, string>,
    accepted: "Accepted", done: "Completed", completed: "Handed in", level: "Level",
  },
  cs: {
    of: "Cesta postavy", toPlay: "přehrát", forHelp: "zkratky", helpTitle: "Klávesy", keys: [["Mezerník", "Přehrát / pozastavit"], ["← →", "Zpět / vpřed o 10 s (Shift: 60 s)"], ["F", "Sledovat postavu / celá zóna"], ["M", "Zobrazit nebo skrýt momenty"], ["+  −", "Rychleji / pomaleji"], ["?", "Tato nápověda"]] as [string, string][],
    title: "Přehrání cesty", lead: "Podívej se znovu na celou cestu: kudy postava šla, s čím bojovala, co našla a dokončila, na časové ose, po které můžeš posouvat.",
    demo: "Přehrát ukázku", open: "Otevřít záznam", drop: "nebo sem přetáhni soubor se záznamem",
    note: "Addon záznamy zatím nezapisuje. Ukázka je vygenerovaná cesta, ne skutečného hráče. Skutečný záznam bude mít stejný formát.",
    bad: "Tento soubor není platný záznam.", unreadable: "Soubor se nepodařilo přečíst.", loading: "Načítám mapy…",
    play: "Přehrát", pause: "Pozastavit", replay: "Přehrát znovu", speed: "Rychlost", follow: "Sledovat", whole: "Celá zóna", idle: "Přeskakovat klidné úseky", moments: "Momenty", close: "Zavřít", full: "Celá obrazovka",
    sofar: "Zatím", quests: "questů hotovo", kills: "zabití", xp: "XP", money: "peníze", items: "předmětů", places: "míst", deaths: "smrtí", skills: "Dovednosti",
    recorded: "zaznamenáno", earlier: "dřívějších momentů se nezobrazuje", later: "pozdějších momentů se nezobrazuje", what: "Co se stalo", where: "Kde", type: "Druh", amount: "Množství", reward: "Zkušenosti",
    into: "od začátku cesty", back: "Zpět na začátek", none: "Zatím tu není co ukázat.",
    cat: { quests: "Questy", combat: "Boj", loot: "Loot a peníze", professions: "Profese", travel: "Cestování", character: "Postava" } as Record<Category, string>,
    kind: { quest: "Quest", kill: "Zabití", loot: "Loot", money: "Peníze", level: "Úroveň", skill: "Dovednost", zone: "Zóna", death: "Smrt", dungeon: "Dungeon", travel: "Cestování" } as Record<string, string>,
    accepted: "Přijato", done: "Splněno", completed: "Odevzdáno", level: "Úroveň",
  },
};
type Words = typeof TEXT.en;

/** The floating text that appears above the character when something happens. */
function popup(e: ChronicleEvent, w: Words): { text: string; color: string } {
  switch (e.k) {
    case "quest": return { text: `${e.a === "accept" ? w.accepted : e.a === "turnin" ? w.completed : w.done}: ${e.text}${e.xp ? ` +${e.xp} XP` : ""}`, color: COLORS.quests };
    case "kill": return { text: `${e.text}${e.xp ? ` +${e.xp} XP` : ""}`, color: COLORS.combat };
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

type Cam = { x: number; y: number; z: number };
type ZoneArt = { key: string; img: HTMLImageElement | null; w: number; h: number };

/** The map: the zone picture under a camera that follows the character, with the trail, the places and the floating messages. */
function Stage({ c, maps, timeRef, follow, reduced, words, overview }: { c: Chronicle; maps: readonly MapDefinition[]; timeRef: { current: number }; follow: boolean; reduced: boolean; words: Words; overview: boolean }) {
  const canvas = useRef<HTMLCanvasElement>(null);
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
    let zone = -1, fadeStart = -1e9;
    const longest = visits(c).reduce((best, v) => (v.to - v.from > best.span ? { zone: v.zone, span: v.to - v.from } : best), { zone: 0, span: -1 }).zone;
    const overviewStep = Math.max(1, Math.ceil(c.path.length / 900));
    let previous: { art: ZoneArt; cam: Cam } | null = null;

    const place = (a: ZoneArt, k: Cam, u: number, v: number): [number, number] => {
      const s = Math.min(cw / a.w, ch / a.h) * k.z;
      return [cw / 2 + (u - k.x) * a.w * s, ch / 2 + (v - k.y) * a.h * s];
    };
    const drawZone = (a: ZoneArt, k: Cam, alpha: number) => {
      const s = Math.min(cw / a.w, ch / a.h) * k.z;
      const [x0, y0] = place(a, k, 0, 0);
      ctx.globalAlpha = alpha;
      if (a.img) { ctx.drawImage(a.img, x0, y0, a.w * s, a.h * s); ctx.fillStyle = "rgba(9,8,16,0.28)"; ctx.fillRect(x0, y0, a.w * s, a.h * s); }
      else { ctx.fillStyle = "#1c1a28"; ctx.fillRect(x0, y0, a.w * s, a.h * s); }
      ctx.globalAlpha = 1;
    };

    const draw = (now: number) => {
      const dt = Math.min(0.1, (now - lastNow) / 1000); lastNow = now;
      const t = timeRef.current;
      const pos = positionAt(c, t);
      ctx.clearRect(0, 0, cw, ch);
      const bg = ctx.createRadialGradient(cw / 2, ch / 2, 0, cw / 2, ch / 2, Math.max(cw, ch) * 0.7);
      bg.addColorStop(0, "#1b1930"); bg.addColorStop(1, "#0b0b12");
      ctx.fillStyle = bg; ctx.fillRect(0, 0, cw, ch);
      if (!pos) return;
      if (overview) {
        // before the start: the zone where most of the journey happened, with the whole way through it
        const a = art(c.zones[longest]);
        const whole: Cam = { x: 0.5, y: 0.5, z: 0.92 };
        drawZone(a, whole, 1);
        ctx.lineCap = "round"; ctx.lineJoin = "round"; ctx.shadowColor = "rgba(90,170,255,0.9)"; ctx.shadowBlur = 8;
        ctx.strokeStyle = "rgba(105,185,255,0.85)"; ctx.lineWidth = 2.4; ctx.beginPath();
        let pen = false;
        for (let i = 0; i < c.path.length; i += overviewStep) {
          const p = c.path[i];
          if (p[1] !== longest) { pen = false; continue; }
          const [sx, sy] = place(a, whole, p[2], p[3]);
          if (pen) ctx.lineTo(sx, sy); else ctx.moveTo(sx, sy);
          pen = true;
        }
        ctx.stroke(); ctx.shadowBlur = 0;
        raf = requestAnimationFrame(draw);
        return;
      }
      const here = art(c.zones[pos.zone]);
      const target: Cam = follow ? { x: pos.x, y: pos.y, z: 2.6 } : { x: 0.5, y: 0.5, z: 1 };
      if (zone !== pos.zone) {
        if (zone >= 0 && !reduced) { previous = { art: art(c.zones[zone]), cam: { ...cam } }; fadeStart = now; }
        zone = pos.zone; Object.assign(cam, target);
      } else {
        const k = 1 - Math.exp(-dt * (follow ? 5 : 3));
        cam.x += (target.x - cam.x) * k; cam.y += (target.y - cam.y) * k; cam.z += (target.z - cam.z) * k;
      }
      const fade = Math.min(1, (now - fadeStart) / 900);
      if (previous && fade < 1) drawZone(previous.art, previous.cam, 1);
      else previous = null;
      drawZone(here, cam, previous ? fade : 1);

      // the whole way through this zone as a dotted line, and the last stretch as a bright glowing one
      const all = pathWindow(c, t, 1e9);
      const stepAll = Math.max(1, Math.ceil(all.length / 500));
      ctx.lineCap = "round"; ctx.lineJoin = "round";
      ctx.setLineDash([1, 7]); ctx.lineWidth = 2; ctx.strokeStyle = "rgba(150,195,255,0.45)"; ctx.beginPath();
      all.forEach((p, i) => { if (i % stepAll && i !== all.length - 1) return; const [sx, sy] = place(here, cam, p[2], p[3]); if (i) ctx.lineTo(sx, sy); else ctx.moveTo(sx, sy); });
      ctx.stroke(); ctx.setLineDash([]);
      const near = pathWindow(c, t, 150);
      const [px, py] = place(here, cam, pos.x, pos.y);
      ctx.shadowColor = "rgba(90,170,255,0.9)"; ctx.shadowBlur = 9;
      for (let i = 1; i < near.length; i++) {
        const a = near[i - 1], b = near[i];
        if (b[0] - a[0] > 15) continue;
        const [ax, ay] = place(here, cam, a[2], a[3]), [bx, by] = place(here, cam, b[2], b[3]);
        ctx.strokeStyle = `rgba(105,185,255,${0.12 + 0.83 * (i / near.length)})`; ctx.lineWidth = 3.2;
        ctx.beginPath(); ctx.moveTo(ax, ay); ctx.lineTo(bx, by); ctx.stroke();
      }
      ctx.shadowBlur = 0;

      // what happened along the way in this zone
      const from = all.length ? all[0][0] : 0;
      const seen = eventsBetween(c, from, t);
      let fights = 0;
      for (const e of seen) {
        if (e.zone !== pos.zone || e.x === undefined || e.y === undefined) continue;
        const [ex, ey] = place(here, cam, e.x, e.y);
        if (ex < -20 || ey < -20 || ex > cw + 20 || ey > ch + 20) continue;
        if (e.k === "kill") { const age = t - e.t; ctx.fillStyle = `rgba(226,120,106,${Math.max(0.15, 0.85 - age / 400)})`; ctx.beginPath(); ctx.arc(ex, ey, 3.2, 0, 7); ctx.fill(); }
        else if (e.k === "quest" && (e.a === "accept" || e.a === "turnin")) {
          ctx.fillStyle = "#f2c04b"; ctx.strokeStyle = "#14121c"; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(ex, ey, 9, 0, 7); ctx.fill(); ctx.stroke();
          ctx.fillStyle = "#14121c"; ctx.font = "700 12px Inter, sans-serif"; ctx.textAlign = "center"; ctx.textBaseline = "middle"; ctx.fillText(e.a === "accept" ? "!" : "?", ex, ey + 0.5);
        } else if (e.k === "level") { ctx.fillStyle = "#a78bfa"; ctx.strokeStyle = "#fff"; ctx.lineWidth = 1.5; ctx.beginPath(); ctx.arc(ex, ey, 6, 0, 7); ctx.fill(); ctx.stroke(); }
        else if (e.k === "death") { ctx.strokeStyle = "#e2786a"; ctx.lineWidth = 3; ctx.beginPath(); ctx.moveTo(ex - 5, ey - 5); ctx.lineTo(ex + 5, ey + 5); ctx.moveTo(ex + 5, ey - 5); ctx.lineTo(ex - 5, ey + 5); ctx.stroke(); }
        if (e.k === "kill" && t - e.t < 7) fights++;
      }

      // the character, with a ring that pulses and turns red in a fight
      const pulse = reduced ? 0.5 : (Math.sin(now / 320) + 1) / 2;
      const ring = fights ? "226,120,106" : "105,204,240";
      ctx.strokeStyle = `rgba(${ring},${0.85 - pulse * 0.6})`; ctx.lineWidth = 2.5;
      ctx.beginPath(); ctx.arc(px, py, 11 + pulse * 9, 0, 7); ctx.stroke();
      ctx.fillStyle = classColor; ctx.strokeStyle = "#fff"; ctx.lineWidth = 2.5; ctx.shadowColor = "rgba(0,0,0,0.6)"; ctx.shadowBlur = 6;
      ctx.beginPath(); ctx.arc(px, py, 8, 0, 7); ctx.fill(); ctx.stroke(); ctx.shadowBlur = 0;

      // messages rise from the character and fade: the newest nearest to it
      const recent = eventsBetween(c, t - 5, t).filter(e => e.k !== "zone").slice(-5);
      ctx.font = "600 13px Inter, sans-serif"; ctx.textAlign = "center"; ctx.textBaseline = "middle"; ctx.lineJoin = "round";
      recent.forEach((e, i) => {
        const age = t - e.t, m = popup(e, words);
        const fadeOut = Math.min(1, Math.max(0, (5 - age) / 1.5));
        const rise = reduced ? 0 : Math.min(age, 3) * 5;
        const y = py - 28 - (recent.length - 1 - i) * 20 - rise;
        ctx.globalAlpha = fadeOut; ctx.lineWidth = 4; ctx.strokeStyle = "rgba(10,9,18,0.92)"; ctx.strokeText(m.text, px, y);
        ctx.fillStyle = m.color; ctx.fillText(m.text, px, y); ctx.globalAlpha = 1;
      });
      raf = requestAnimationFrame(draw);
    };
    raf = requestAnimationFrame(draw);
    return () => { cancelAnimationFrame(raf); observer.disconnect(); };
  }, [c, maps, timeRef, follow, reduced, classColor, words, overview]);
  return <canvas ref={canvas} className="chr-canvas" role="img" aria-label={c.character.name} />;
}

/** The bar at the bottom: zones as coloured stretches, notable moments, how busy it was, and a playhead to drag. */
function Timeline({ c, maps, time, onSeek, lang }: { c: Chronicle; maps: readonly MapDefinition[]; time: number; onSeek: (t: number) => void; lang: string }) {
  const runs = useMemo(() => visits(c), [c]);
  const bars = useRef<HTMLCanvasElement>(null);
  const track = useRef<HTMLDivElement>(null);
  const dragging = useRef(false);
  const [hover, setHover] = useState<number | null>(null);
  const marks = useMemo(() => {
    const out: { t: number; kind: "quest" | "level" | "death" | "turn"; label: string }[] = [];
    const gap = c.duration / 260;
    const last: Record<string, number> = {};
    for (const e of c.events) {
      const kind = e.k === "quest" && e.a === "accept" ? "quest" : e.k === "quest" && e.a === "turnin" ? "turn" : e.k === "level" ? "level" : e.k === "death" ? "death" : null;
      if (!kind || e.t - (last[kind] ?? -1e9) < gap) continue;
      last[kind] = e.t; out.push({ t: e.t, kind, label: e.text });
    }
    return out;
  }, [c]);
  const levels = useMemo(() => c.events.filter(e => e.k === "level").map(e => ({ t: e.t, n: e.n ?? 0 })), [c]);
  useEffect(() => {
    const el = bars.current;
    const ctx = el?.getContext("2d");
    if (!el || !ctx) return;
    const W = el.width = 600, H = el.height = 20, n = 200;
    const bins = new Array<number>(n).fill(0);
    for (const e of c.events) bins[Math.min(n - 1, Math.floor((e.t / c.duration) * n))]++;
    const peak = Math.max(1, ...bins);
    ctx.clearRect(0, 0, W, H);
    bins.forEach((v, i) => { if (!v) return; const h = Math.max(2, (v / peak) * H); ctx.fillStyle = "rgba(226,120,106,0.75)"; ctx.fillRect((i / n) * W, H - h, W / n - 0.6, h); });
  }, [c]);
  const at = (event: { clientX: number }) => {
    const box = track.current?.getBoundingClientRect();
    return box ? Math.min(c.duration, Math.max(0, ((event.clientX - box.left) / box.width) * c.duration)) : 0;
  };
  const down = (event: ReactPointerEvent) => { dragging.current = true; (event.currentTarget as HTMLElement).setPointerCapture(event.pointerId); onSeek(at(event)); };
  const move = (event: ReactPointerEvent) => { setHover(at(event)); if (dragging.current) onSeek(at(event)); };
  const pct = (t: number) => `${(t / c.duration) * 100}%`;
  return (
    <div className="chr-timeline">
      <div className="chr-levels" aria-hidden="true">{levels.map(l => <span key={l.t} style={{ left: pct(l.t) }}>{l.n}</span>)}</div>
      <canvas ref={bars} className="chr-bars" aria-hidden="true" />
      <div className="chr-zones" aria-hidden="true">
        {runs.map((r, i) => (
          <span key={i} style={{ left: pct(r.from), width: `calc(${((r.to - r.from) / c.duration) * 100}% - 2px)`, background: `hsl(${hue(c.zones[r.zone])} 38% 30% / .92)` }}>{nameOf(maps, c.zones[r.zone], lang)}</span>
        ))}
      </div>
      <div ref={track} className="chr-track" role="slider" tabIndex={-1} aria-label="Timeline" aria-valuemin={0} aria-valuemax={Math.round(c.duration)} aria-valuenow={Math.round(time)} aria-valuetext={clock(time)}
        onPointerDown={down} onPointerMove={move} onPointerUp={() => { dragging.current = false; }} onPointerLeave={() => setHover(null)}>
        <i className="chr-fill" style={{ width: pct(time) }} />
        {marks.map((m, i) => <b key={i} className={`chr-mark is-${m.kind}`} style={{ left: pct(m.t) }} title={m.label}>{m.kind === "quest" ? "!" : m.kind === "turn" ? "?" : m.kind === "level" ? "★" : "✕"}</b>)}
        <u className="chr-head" style={{ left: pct(time) }} />
        {hover !== null && <em className="chr-hover" style={{ left: pct(hover) }}>{clock(hover)}</em>}
      </div>
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

function Player({ c, maps, onBack }: { c: Chronicle; maps: readonly MapDefinition[]; onBack: () => void }) {
  const { lang } = useI18n();
  const w = TEXT[lang === "cs" ? "cs" : "en"];
  const index = useMemo(() => buildIndex(c), [c]);
  const counts = useMemo(() => countByCategory(c), [c]);
  const root = useRef<HTMLDivElement>(null);
  const timeRef = useRef(0);
  const [time, setTime] = useState(0);
  const [playing, setPlaying] = useState(false);
  const [started, setStarted] = useState(false);
  const [help, setHelp] = useState(false);
  const [speed, setSpeed] = useState<number>(20);
  const [follow, setFollow] = useState(true);
  const [skipIdle, setSkipIdle] = useState(true);
  const [panel, setPanel] = useState(true);
  const [filters, setFilters] = useState<ReadonlySet<Category>>(new Set(CATEGORIES));
  const reduced = useMemo(() => typeof window !== "undefined" && window.matchMedia("(prefers-reduced-motion: reduce)").matches, []);

  useEffect(() => {
    if (!playing) return;
    let raf = 0, last = performance.now(), ui = 0;
    const tick = (now: number) => {
      const dt = Math.min(0.1, (now - last) / 1000); last = now;
      const next = c.events[eventAt(c, timeRef.current) + 1];
      const rate = speed * (skipIdle && next && next.t - timeRef.current > 20 ? 4 : 1);
      timeRef.current = Math.min(c.duration, timeRef.current + dt * rate);
      if (now - ui > 100) { ui = now; setTime(timeRef.current); }
      if (timeRef.current >= c.duration) { setTime(c.duration); setPlaying(false); return; }
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [playing, speed, skipIdle, c]);

  const seek = useCallback((t: number) => { timeRef.current = Math.min(c.duration, Math.max(0, t)); setTime(timeRef.current); }, [c]);
  const toggle = useCallback(() => { setStarted(true); if (!playing && timeRef.current >= c.duration) seek(0); setPlaying(p => !p); }, [playing, c, seek]);
  const ring = useMemo(() => journeyRing(c), [c]);
  const total = useMemo(() => totalsAt(index, c.duration), [index, c]);
  const shown = useMemo(() => c.events.filter(e => filters.has(categoryOf(e.k))), [c, filters]);
  const totals = totalsAt(index, time);
  const pos = positionAt(c, time);
  const zoneName = pos ? nameOf(maps, c.zones[pos.zone], lang) : "";
  const current = eventAt(c, time, filters);
  const currentEvent = current >= 0 ? c.events[current] : null;
  // the window of the list: some before, some after the playhead
  const split = useMemo(() => { let n = 0; for (const e of shown) { if (e.t > time) break; n++; } return n; }, [shown, time]);
  const list = shown.slice(Math.max(0, split - 12), split + 6);
  const when = (t: number) => new Date((c.startedAt + t) * 1000).toLocaleString(lang === "cs" ? "cs-CZ" : "en-GB", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit", second: "2-digit" });
  const cls = CLASSES[c.character.classId] as unknown;
  const className = typeof cls === "string" ? cls : (cls as { name?: string } | undefined)?.name ?? "";
  const color = CLASS_COLORS[c.character.classId] ?? "#69ccf0";

  const key = (event: React.KeyboardEvent) => {
    const big = event.shiftKey ? 60 : 10;
    if (event.key === "?") setHelp(v => !v);
    else if (event.key === "Escape") setHelp(false);
    else if (event.key === " ") { event.preventDefault(); toggle(); }
    else if (event.key === "ArrowRight") { event.preventDefault(); seek(timeRef.current + big); }
    else if (event.key === "ArrowLeft") { event.preventDefault(); seek(timeRef.current - big); }
    else if (event.key === "f") setFollow(v => !v);
    else if (event.key === "m") setPanel(v => !v);
    else if (event.key === "+" || event.key === "=") setSpeed(s => SPEEDS[Math.min(SPEEDS.length - 1, SPEEDS.indexOf(s as (typeof SPEEDS)[number]) + 1)]);
    else if (event.key === "-") setSpeed(s => SPEEDS[Math.max(0, SPEEDS.indexOf(s as (typeof SPEEDS)[number]) - 1)]);
  };
  const fullscreen = () => { if (document.fullscreenElement) void document.exitFullscreen(); else void root.current?.requestFullscreen?.(); };
  const stats: [string, string][] = [
    [String(totals.quests), w.quests], [String(totals.kills), w.kills], [totals.xp.toLocaleString(), w.xp], [moneyText(totals.copper), w.money], [String(totals.items), w.items], [String(totals.places), w.places],
  ];

  return (
    <div ref={root} className={`chr${started ? "" : " is-intro"}`} tabIndex={0} onKeyDown={key} aria-label={w.title}>
      <Stage c={c} maps={maps} timeRef={timeRef} follow={follow} reduced={reduced} words={w} overview={!started} />
      <div className="chr-vignette" aria-hidden="true" />
      <div className="chr-top">
        <button type="button" className="chr-btn" onClick={onBack}><Icon name="map" size={15} /> {w.back}</button>
        <span className="chr-spacer" />
        <button type="button" className={`chr-btn${follow ? " is-on" : ""}`} onClick={() => setFollow(v => !v)} aria-pressed={follow}>{follow ? w.follow : w.whole}</button>
        <button type="button" className={`chr-btn${skipIdle ? " is-on" : ""}`} onClick={() => setSkipIdle(v => !v)} aria-pressed={skipIdle} title={w.idle}>{w.idle}</button>
        <button type="button" className={`chr-btn${panel ? " is-on" : ""}`} onClick={() => setPanel(v => !v)} aria-pressed={panel}>{w.moments}</button>
        <button type="button" className="chr-btn" onClick={fullscreen} aria-label={w.full}>⛶</button>
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
          <p className="chr-big"><b>{clock(c.duration)}</b> {w.recorded} <b>{total.kills.toLocaleString()}</b> {w.kills} <b>{total.quests}</b> {w.quests} <b>{total.items.toLocaleString()}</b> {w.items} <b>{total.places}</b> {w.places}</p>
          <p className="chr-hint"><kbd>{lang === "cs" ? "Mezerník" : "Space"}</kbd> {w.toPlay} <i /> <kbd>?</kbd> {w.forHelp}</p>
        </div>
      )}
      {help && (
        <div className="chr-help" role="dialog" aria-label={w.helpTitle} onClick={() => setHelp(false)}>
          <div><h3>{w.helpTitle}</h3><dl>{w.keys.map(([k, v]) => <div key={k}><dt><kbd>{k}</kbd></dt><dd>{v}</dd></div>)}</dl></div>
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
        <p className="chr-played">{clock(time)} {w.recorded}</p>
        <h3>{w.sofar}</h3>
        <dl className="chr-stats">{stats.map(([v, l]) => <div key={l}><dt>{v}</dt><dd>{l}</dd></div>)}</dl>
        {Object.keys(totals.skills).length > 0 && <>
          <h3>{w.skills}</h3>
          {Object.entries(totals.skills).map(([name, [v, max]]) => <div key={name} className="chr-skill"><span>{name}</span><b>{v}/{max}</b><i><u style={{ width: `${(v / max) * 100}%` }} /></i></div>)}
        </>}
        {totals.deaths > 0 && <p className="chr-deaths">{totals.deaths} {w.deaths}</p>}
      </aside>

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
                <button type="button" onClick={() => seek(e.t)}><time>{clock(e.t)}</time><span>{popup(e, w).text}</span></button>
              </li>
            ))}
          </ol>
          {shown.length - split - 6 > 0 && <p className="chr-muted">{shown.length - split - 6} {w.later}</p>}
          {currentEvent && (
            <section className="chr-detail">
              <h3>{popup(currentEvent, w).text}</h3>
              <p className="chr-muted">{clock(currentEvent.t)} {w.into} · {when(currentEvent.t)}</p>
              <h4>{w.what}</h4>
              <dl>
                <div><dt>{w.type}</dt><dd>{w.kind[currentEvent.k]}{currentEvent.a ? ` · ${currentEvent.a}` : ""}</dd></div>
                {currentEvent.zone !== undefined && <div><dt>{w.where}</dt><dd>{nameOf(maps, c.zones[currentEvent.zone], lang)}{currentEvent.x !== undefined && currentEvent.y !== undefined ? ` ${(currentEvent.x * 100).toFixed(1)}, ${(currentEvent.y * 100).toFixed(1)}` : ""}</dd></div>}
                {currentEvent.xp ? <div><dt>{w.reward}</dt><dd>+{currentEvent.xp} XP</dd></div> : null}
                {currentEvent.k === "loot" && currentEvent.n ? <div><dt>{w.amount}</dt><dd>×{currentEvent.n}</dd></div> : null}
              </dl>
            </section>
          )}
        </aside>
      )}

      <footer className="chr-bar">
        <button type="button" className="chr-play" onClick={toggle} aria-label={playing ? w.pause : time >= c.duration ? w.replay : w.play}>
          {playing ? <svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true"><rect x="6" y="5" width="4" height="14" rx="1" fill="currentColor" /><rect x="14" y="5" width="4" height="14" rx="1" fill="currentColor" /></svg>
            : <svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true"><path d="M8 5v14l11-7z" fill="currentColor" /></svg>}
        </button>
        <Timeline c={c} maps={maps} time={time} onSeek={seek} lang={lang} />
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

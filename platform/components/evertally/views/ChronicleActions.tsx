"use client";
/* eslint-disable @next/next/no-img-element -- small bundled class icons */
// The moves of a fight: one lane per fighter (the character, the group, the enemies) with every spell they used along the time,
// and under it the combat log as a list. Everything is clickable: a move shows its detail, a fighter or a spell narrows the view.
import { useEffect, useMemo, useRef, useState } from "react";
import { LOG_KINDS, clock, type Actor, type Fight, type LogLine } from "@/lib/chronicle";
import { CLASS_COLORS } from "../data";
import { TypeIcon, classIconUrl, drawIcon } from "./ChronicleArt";

const T = {
  en: {
    all: "Everyone", reset: "Reset", search: "Find a spell or a fighter", zoom: "Wheel to zoom, drag to move", whole: "Whole fight", axis: "Click the scale to jump there",
    time: "Time", source: "Who", target: "At whom", spell: "Spell", amount: "Amount", kind: "What", none: "No moves match the filter.", more: "Show more",
    kinds: ["Damage", "Healing", "Casts", "Effects", "Interrupts", "Dispels", "Deaths"], sides: { me: "You", party: "Group", enemy: "Enemy" } as Record<string, string>,
    detail: "The move", jump: "Jump there in the replay", onlyActor: "Only this fighter", onlySpell: "Only this spell", so: "Up to this moment", dealtSoFar: "damage done", healedSoFar: "healing done", crit: "Critical hit",
    hint: "Click a fighter to hide or show it, double-click to show only that one.", moves: "moves", shown: "shown", died: "died", of: "of",
  },
  cs: {
    all: "Všichni", reset: "Obnovit", search: "Hledat kouzlo nebo bojovníka", zoom: "Kolečkem přibližuješ, tažením posouváš", whole: "Celý souboj", axis: "Kliknutím na stupnici se tam přesuneš",
    time: "Čas", source: "Kdo", target: "Na koho", spell: "Kouzlo", amount: "Množství", kind: "Co", none: "Filtru neodpovídá žádný tah.", more: "Zobrazit další",
    kinds: ["Poškození", "Léčení", "Seslání", "Efekty", "Přerušení", "Rozptýlení", "Smrti"], sides: { me: "Ty", party: "Skupina", enemy: "Protivník" } as Record<string, string>,
    detail: "Tah", jump: "Skočit tam v přehrávání", onlyActor: "Jen tento bojovník", onlySpell: "Jen toto kouzlo", so: "Do tohoto okamžiku", dealtSoFar: "způsobeno", healedSoFar: "vyléčeno", crit: "Kritický zásah",
    hint: "Kliknutím na bojovníka ho skryješ nebo ukážeš, dvojklikem ukážeš jen jeho.", moves: "tahů", shown: "zobrazeno", died: "zemřel", of: "z",
  },
};
const SCHOOL: Record<string, string> = { physical: "#c9c4d6", nature: "#7fd26a", fire: "#ff8a3c", frost: "#6cc4ff", shadow: "#a77bd6", arcane: "#e08cf0", holy: "#ffd86b" };
const SIDE: Record<string, string> = { me: "#f2c04b", party: "#7fb2ff", enemy: "#ff7a59" };
const KIND_COLOR = ["#ff9a3c", "#5fd08f", "#9aa4b8", "#c49bff", "#5b8def", "#7fd8ff", "#e2786a"];
const DMG = LOG_KINDS.indexOf("dmg"), HEAL = LOG_KINDS.indexOf("heal"), DEATH = LOG_KINDS.indexOf("death");
const LANE = 26, AXIS = 22;
const NO_ACTORS: Actor[] = [], NO_SPELLS: { name: string; school?: string }[] = [], NO_LOG: LogLine[] = [];
const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v));
const num = (n: number) => Math.round(n).toLocaleString("en-US").replace(/,/g, " ");
const exact = (t: number) => `${Math.floor(t / 60)}:${(t % 60).toFixed(1).padStart(4, "0")}`;
const tone = (a: Actor) => (a.classId ? CLASS_COLORS[a.classId] ?? SIDE[a.side] : SIDE[a.side]);

function Fighter({ actor, size = 22 }: { actor: Actor; size?: number }) {
  return actor.classId && actor.side !== "enemy"
    ? <img src={classIconUrl(actor.classId)} alt="" width={size} height={size} className="chr-fighter" />
    : <span className="chr-fighter is-foe" style={{ width: size, height: size }}><TypeIcon k="combat.death" size={Math.round(size * 0.65)} /></span>;
}

export function Actions({ f, local, lang, onSeek }: { f: Fight; local: number; lang: string; onSeek: (local: number) => void }) {
  const w = T[lang === "cs" ? "cs" : "en"];
  const actors = f.actors ?? NO_ACTORS, spells = f.spells ?? NO_SPELLS, log = f.log ?? NO_LOG;
  const [hidden, setHidden] = useState<ReadonlySet<number>>(new Set());
  const [kinds, setKinds] = useState<ReadonlySet<number>>(new Set(LOG_KINDS.map((_, i) => i)));
  const [spellOnly, setSpellOnly] = useState<number | null>(null);
  const [query, setQuery] = useState("");
  const [sel, setSel] = useState<number | null>(null);
  const [view, setView] = useState({ from: 0, to: Math.max(1, f.d) });
  const [limit, setLimit] = useState(150);
  const [tip, setTip] = useState<{ x: number; y: number; i: number } | null>(null);
  const [width, setWidth] = useState(600);
  const canvas = useRef<HTMLCanvasElement>(null);
  const live = useRef({ view, hidden, kinds, spellOnly, query });
  useEffect(() => { live.current = { view, hidden, kinds, spellOnly, query }; });

  const q = query.trim().toLowerCase();
  const passes = (l: LogLine, state = { hidden, kinds, spellOnly, q }) =>
    !state.hidden.has(l[1]) && state.kinds.has(l[3]) && (state.spellOnly === null || l[4] === state.spellOnly)
    && (!state.q || (l[4] >= 0 && spells[l[4]].name.toLowerCase().includes(state.q)) || actors[l[1]]?.name.toLowerCase().includes(state.q) || (l[2] >= 0 && actors[l[2]].name.toLowerCase().includes(state.q)));
  /** log indices per fighter, in time order, for the lanes */
  const lanes = useMemo(() => actors.map((_, a) => log.flatMap((l, i) => (l[1] === a ? [i] : []))), [actors, log]);
  const rows = useMemo(() => {
    const out: number[] = [];
    log.forEach((l, i) => { if (l[0] >= view.from - 1e-6 && l[0] <= view.to + 1e-6 && passes(l)) out.push(i); });
    return out;
  // eslint-disable-next-line react-hooks/exhaustive-deps -- `passes` only reads the values listed here
  }, [log, view, hidden, kinds, spellOnly, q]);
  const shown = Math.max(limit, sel !== null ? rows.indexOf(sel) + 25 : 0);
  const laneOrder = actors.map((a, i) => ({ a, i })).filter(x => !hidden.has(x.i));
  const height = AXIS + laneOrder.length * LANE + 4;

  useEffect(() => {
    const el = canvas.current;
    if (!el) return;
    const observer = new ResizeObserver(() => setWidth(Math.max(200, el.clientWidth)));
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  // ---- drawing
  useEffect(() => {
    const el = canvas.current;
    const ctx = el?.getContext("2d");
    if (!el || !ctx) return;
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    el.width = Math.floor(width * dpr); el.height = Math.floor(height * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, width, height);
    const span = Math.max(0.5, view.to - view.from), px = (t: number) => ((t - view.from) / span) * width;
    // scale
    ctx.font = "10px ui-monospace, Consolas, monospace"; ctx.textBaseline = "middle"; ctx.textAlign = "center";
    const steps = [0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300];
    const step = steps.find(s => (s / span) * width >= 64) ?? 300;
    ctx.strokeStyle = "rgba(255,255,255,.07)"; ctx.fillStyle = "#9a97a8"; ctx.lineWidth = 1;
    for (let t = Math.ceil(view.from / step) * step; t <= view.to; t += step) { const x = px(t); ctx.beginPath(); ctx.moveTo(x, AXIS - 4); ctx.lineTo(x, height); ctx.stroke(); ctx.fillText(clock(t), x, 9); }
    laneOrder.forEach(({ i }, row) => {
      const y = AXIS + row * LANE;
      ctx.fillStyle = row % 2 ? "rgba(255,255,255,.025)" : "rgba(255,255,255,.05)"; ctx.fillRect(0, y, width, LANE);
      const list = lanes[i];
      let lo = 0, hi = list.length;
      while (lo < hi) { const mid = (lo + hi) >> 1; if (log[list[mid]][0] < view.from - 1) lo = mid + 1; else hi = mid; }
      for (let k = lo; k < list.length; k++) {
        const l = log[list[k]];
        if (l[0] > view.to + 1) break;
        if (!passes(l)) continue;
        const x = px(l[0]), cy = y + LANE / 2, school = l[4] >= 0 ? SCHOOL[spells[l[4]].school ?? "physical"] ?? "#c9c4d6" : "#e2786a";
        if (l[3] === DMG) { ctx.fillStyle = school; ctx.fillRect(x - 1.5, cy - 7, 3, 14); if (l[6]) { ctx.fillStyle = "#fff"; ctx.fillRect(x - 1.5, cy - 8, 3, 2); } }
        else if (l[3] === HEAL) { ctx.fillStyle = "#5fd08f"; ctx.beginPath(); ctx.moveTo(x, cy - 7); ctx.lineTo(x + 4, cy); ctx.lineTo(x, cy + 7); ctx.lineTo(x - 4, cy); ctx.closePath(); ctx.fill(); }
        else if (l[3] === DEATH) drawIcon(ctx, "combat.death", x, cy, 16, "#ff6a5a");
        else { ctx.fillStyle = KIND_COLOR[l[3]]; ctx.beginPath(); ctx.arc(x, cy, l[3] === 4 ? 5.5 : 4, 0, 7); ctx.fill(); if (l[3] === 4) { ctx.strokeStyle = "#fff"; ctx.lineWidth = 1.5; ctx.stroke(); } }
      }
    });
    if (sel !== null) { const x = px(log[sel][0]); ctx.strokeStyle = "rgba(255,255,255,.85)"; ctx.lineWidth = 1.5; ctx.beginPath(); ctx.moveTo(x, AXIS - 4); ctx.lineTo(x, height); ctx.stroke(); }
    if (local >= view.from && local <= view.to) { const x = px(local); ctx.strokeStyle = "#6cc4ff"; ctx.lineWidth = 2; ctx.shadowColor = "#6cc4ff"; ctx.shadowBlur = 6; ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, height); ctx.stroke(); ctx.shadowBlur = 0; }
  // eslint-disable-next-line react-hooks/exhaustive-deps -- `passes` and `laneOrder` follow the listed values
  }, [width, height, view, hidden, kinds, spellOnly, q, sel, local, lanes, log, spells, actors]);

  // ---- pointer: hover, click, drag to move, wheel to zoom
  useEffect(() => {
    const el = canvas.current;
    if (!el) return;
    let drag: { x: number; from: number; to: number; moved: boolean } | null = null;
    const spot = (e: { clientX: number; clientY: number }) => { const r = el.getBoundingClientRect(); return { x: e.clientX - r.left, y: e.clientY - r.top, w: r.width }; };
    const timeAt = (x: number, wd: number, v = live.current.view) => v.from + (x / wd) * (v.to - v.from);
    const nearest = (x: number, y: number, wd: number): number | null => {
      const s = live.current;
      const order = actors.map((_, i) => i).filter(i => !s.hidden.has(i));
      const row = Math.floor((y - AXIS) / LANE);
      if (row < 0 || row >= order.length) return null;
      const list = lanes[order[row]];
      const t = timeAt(x, wd), reach = (6 / wd) * (s.view.to - s.view.from);
      let best: number | null = null, gap = reach;
      let lo = 0, hi = list.length;
      while (lo < hi) { const mid = (lo + hi) >> 1; if (log[list[mid]][0] < t - reach) lo = mid + 1; else hi = mid; }
      const state = { hidden: s.hidden, kinds: s.kinds, spellOnly: s.spellOnly, q: s.query.trim().toLowerCase() };
      for (let k = lo; k < list.length && log[list[k]][0] <= t + reach; k++) {
        const l = log[list[k]];
        if (!passes(l, state)) continue;
        const d = Math.abs(l[0] - t);
        if (d <= gap) { gap = d; best = list[k]; }
      }
      return best;
    };
    const down = (e: PointerEvent) => { el.setPointerCapture(e.pointerId); const p = spot(e); drag = { x: p.x, from: live.current.view.from, to: live.current.view.to, moved: false }; };
    const move = (e: PointerEvent) => {
      const p = spot(e);
      if (drag) {
        const dx = p.x - drag.x;
        if (Math.abs(dx) > 3) drag.moved = true;
        if (drag.moved) {
          const span = drag.to - drag.from, shift = (-dx / p.w) * span, from = clamp(drag.from + shift, 0, Math.max(0, f.d - span));
          setView({ from, to: from + span });
          setTip(null);
          return;
        }
      }
      const i = nearest(p.x, p.y, p.w);
      setTip(i === null ? null : { x: p.x, y: p.y, i });
      el.style.cursor = i === null ? "grab" : "pointer";
    };
    const up = (e: PointerEvent) => {
      const p = spot(e);
      if (drag && !drag.moved) {
        if (p.y < AXIS) onSeek(clamp(timeAt(p.x, p.w), 0, f.d));
        else { const i = nearest(p.x, p.y, p.w); if (i !== null) setSel(i); }
      }
      drag = null;
    };
    const wheel = (e: WheelEvent) => {
      e.preventDefault();
      const p = spot(e), v = live.current.view, span = v.to - v.from;
      const next = clamp(span * Math.exp(e.deltaY * 0.0015), 4, Math.max(4, f.d));
      const at = timeAt(p.x, p.w, v), ratio = p.x / p.w;
      const from = clamp(at - ratio * next, 0, Math.max(0, f.d - next));
      setView({ from, to: from + next });
    };
    const leave = () => setTip(null);
    el.addEventListener("pointerdown", down); el.addEventListener("pointermove", move); el.addEventListener("pointerup", up); el.addEventListener("pointercancel", up);
    el.addEventListener("pointerleave", leave); el.addEventListener("wheel", wheel, { passive: false });
    return () => {
      el.removeEventListener("pointerdown", down); el.removeEventListener("pointermove", move); el.removeEventListener("pointerup", up); el.removeEventListener("pointercancel", up);
      el.removeEventListener("pointerleave", leave); el.removeEventListener("wheel", wheel);
    };
  // eslint-disable-next-line react-hooks/exhaustive-deps -- the handlers read the filters through `live`
  }, [actors, lanes, log, f.d, onSeek]);

  useEffect(() => { if (sel !== null) document.getElementById(`chr-log-${sel}`)?.scrollIntoView({ block: "nearest" }); }, [sel]);

  const toggleActor = (i: number) => setHidden(prev => { const next = new Set(prev); if (next.has(i)) next.delete(i); else next.add(i); return next; });
  const only = (i: number) => setHidden(new Set(actors.map((_, x) => x).filter(x => x !== i)));
  const reset = () => { setHidden(new Set()); setKinds(new Set(LOG_KINDS.map((_, i) => i))); setSpellOnly(null); setQuery(""); setView({ from: 0, to: Math.max(1, f.d) }); };
  const spellName = (i: number) => (i >= 0 ? spells[i].name : "");
  const spellColor = (i: number) => (i >= 0 ? SCHOOL[spells[i].school ?? "physical"] ?? "#c9c4d6" : "#e2786a");
  const lineText = (l: LogLine) => (l[3] === DEATH ? w.died : spellName(l[4]));
  const selLine = sel !== null ? log[sel] : null;
  const so = useMemo(() => {
    if (selLine === null || sel === null) return null;
    let dealt = 0, healed = 0;
    for (let i = 0; i <= sel; i++) { const l = log[i]; if (l[1] !== selLine[1]) continue; if (l[3] === DMG) dealt += l[5]; else if (l[3] === HEAL) healed += l[5]; }
    return { dealt, healed };
  }, [log, sel, selLine]);
  const tipLine = tip ? log[tip.i] : null;
  const zoomed = view.from > 0.01 || view.to < f.d - 0.01;

  if (!log.length) return <p className="chr-muted">{w.none}</p>;
  return (
    <div className="chr-actions">
      <div className="chr-filters">
        <div className="chr-fighters" role="group" aria-label={w.all} title={w.hint}>
          {actors.map((a, i) => (
            <button key={i} type="button" className={hidden.has(i) ? "is-off" : ""} style={{ ["--c" as string]: tone(a) }} onClick={() => toggleActor(i)} onDoubleClick={() => only(i)} aria-pressed={!hidden.has(i)}>
              <Fighter actor={a} size={18} />{a.name}
            </button>
          ))}
        </div>
        <div className="chr-kinds" role="group">
          {w.kinds.map((name, i) => (
            <button key={name} type="button" className={kinds.has(i) ? "is-on" : ""} style={{ ["--c" as string]: KIND_COLOR[i] }} aria-pressed={kinds.has(i)}
              onClick={() => setKinds(prev => { const next = new Set(prev); if (next.has(i)) next.delete(i); else next.add(i); return next; })}>{name}</button>
          ))}
        </div>
        <div className="chr-find">
          <input value={query} onChange={event => setQuery(event.target.value)} placeholder={w.search} aria-label={w.search} maxLength={60} />
          {spellOnly !== null && <button type="button" className="chr-tag" style={{ ["--c" as string]: spellColor(spellOnly) }} onClick={() => setSpellOnly(null)}>{spellName(spellOnly)} ×</button>}
          {(zoomed || hidden.size > 0 || spellOnly !== null || query || kinds.size < LOG_KINDS.length) && <button type="button" className="chr-link" onClick={reset}>{w.reset}</button>}
        </div>
      </div>

      <div className="chr-lanes">
        <div className="chr-lane-names" style={{ paddingTop: AXIS }}>
          {laneOrder.map(({ a, i }) => <button key={i} type="button" style={{ height: LANE, ["--c" as string]: tone(a) }} onClick={() => only(i)} title={w.onlyActor}><Fighter actor={a} size={16} /><span>{a.name}</span></button>)}
        </div>
        <div className="chr-lane-chart">
          <canvas ref={canvas} style={{ height }} aria-label={w.moves} />
          {tip && tipLine && (
            <div className="chr-tip chr-move-tip" style={{ left: clamp(tip.x, 70, width - 70), top: tip.y + 14 }}>
              <b style={{ color: tone(actors[tipLine[1]]) }}>{actors[tipLine[1]].name}</b>
              <span style={{ color: spellColor(tipLine[4]) }}>{lineText(tipLine)}{tipLine[2] >= 0 && tipLine[3] !== DEATH ? ` → ${actors[tipLine[2]].name}` : ""}</span>
              {tipLine[5] > 0 && <span>{tipLine[3] === HEAL ? "+" : ""}{num(tipLine[5])}{tipLine[6] ? " ★" : ""}</span>}
              <small>{exact(tipLine[0])}</small>
            </div>
          )}
        </div>
      </div>
      <p className="chr-muted chr-lane-note">{w.zoom} · {w.axis}{zoomed ? ` · ${exact(view.from)}–${exact(view.to)}` : ""}</p>

      {selLine && so && (
        <section className="chr-move">
          <header>
            <h4>{w.detail} · {exact(selLine[0])}</h4>
            <button type="button" className="chr-link" onClick={() => onSeek(selLine[0])}>{w.jump}</button>
            <button type="button" className="chr-link" onClick={() => setSel(null)} aria-label="×">×</button>
          </header>
          <p>
            <b style={{ color: tone(actors[selLine[1]]) }}>{actors[selLine[1]].name}</b>
            {selLine[3] === DEATH ? "" : <> · <button type="button" className="chr-spell-link" style={{ color: spellColor(selLine[4]) }} onClick={() => selLine[4] >= 0 && setSpellOnly(selLine[4])} title={w.onlySpell}>{spellName(selLine[4])}</button></>}
            {selLine[2] >= 0 && selLine[2] !== selLine[1] ? <> → <b style={{ color: tone(actors[selLine[2]]) }}>{actors[selLine[2]].name}</b></> : null}
            {selLine[3] === DEATH ? <> {w.died}</> : null}
          </p>
          <dl>
            <div><dt>{w.kind}</dt><dd>{w.kinds[selLine[3]]}</dd></div>
            {selLine[5] > 0 && <div><dt>{w.amount}</dt><dd>{selLine[3] === HEAL ? "+" : ""}{num(selLine[5])}{selLine[6] ? ` · ${w.crit}` : ""}</dd></div>}
            <div><dt>{w.so}</dt><dd>{num(so.dealt)} {w.dealtSoFar}{so.healed ? ` · ${num(so.healed)} ${w.healedSoFar}` : ""}</dd></div>
          </dl>
          <div className="chr-move-actions">
            <button type="button" className="chr-link" onClick={() => only(selLine[1])}>{w.onlyActor}</button>
            {selLine[4] >= 0 && <button type="button" className="chr-link" onClick={() => setSpellOnly(selLine[4])}>{w.onlySpell}</button>}
          </div>
        </section>
      )}

      <p className="chr-muted">{rows.length} {w.moves}{rows.length > shown ? ` · ${shown} ${w.shown}` : ""}</p>
      <table className="chr-log">
        <thead><tr><th>{w.time}</th><th>{w.source}</th><th>{w.spell}</th><th>{w.target}</th><th>{w.amount}</th></tr></thead>
        <tbody>
          {rows.length === 0 && <tr><td colSpan={5} className="chr-muted">{w.none}</td></tr>}
          {rows.slice(0, shown).map(i => {
            const l = log[i], src = actors[l[1]], dst = l[2] >= 0 ? actors[l[2]] : null;
            return (
              <tr key={i} id={`chr-log-${i}`} className={`${sel === i ? "is-sel" : ""}${l[3] === DEATH ? " is-death" : ""}`} onClick={() => setSel(i)}>
                <td className="chr-t">{exact(l[0])}</td>
                <td><span className="chr-who" style={{ ["--c" as string]: tone(src) }}><Fighter actor={src} size={16} />{src.name}</span></td>
                <td>{l[3] === DEATH ? <span className="chr-died">{w.died}</span> : <span className="chr-spell" style={{ ["--c" as string]: spellColor(l[4]) }}><i style={{ background: KIND_COLOR[l[3]] }} title={w.kinds[l[3]]} />{spellName(l[4])}</span>}</td>
                <td>{dst && dst !== src ? <span className="chr-who" style={{ ["--c" as string]: tone(dst) }}><Fighter actor={dst} size={16} />{dst.name}</span> : <span className="chr-muted">–</span>}</td>
                <td className={`chr-amt${l[3] === HEAL ? " is-heal" : ""}${l[6] ? " is-crit" : ""}`}>{l[5] > 0 ? `${l[3] === HEAL ? "+" : ""}${num(l[5])}${l[6] ? " ★" : ""}` : ""}</td>
              </tr>
            );
          })}
        </tbody>
      </table>
      {rows.length > shown && <button type="button" className="chr-btn" onClick={() => setLimit(shown + 200)}>{w.more}</button>}
    </div>
  );
}

"use client";
/* eslint-disable @next/next/no-img-element -- small bundled class icons */
// The window of one event: a boss fight, a dungeon or raid encounter, a battleground. What the character did and took, spell by
// spell, how the group did, and how the fight went second by second.
import { useEffect, useMemo, useRef, useState, type PointerEvent as ReactPointerEvent } from "react";
import { LOG_KINDS, clock, typeKey, whenOf, type Chronicle, type ChronicleEvent, type Fight, type Member, type SpellRow } from "@/lib/chronicle";
import { fightTurns, turnDelay, type FightTurn } from "@/lib/chronicle-replay";
import { CLASS_COLORS, CLASSES } from "../data";
import { IconChip, ItemIcon, NpcIcon, SpellIcon, TypeIcon, classIconUrl } from "./ChronicleArt";
import { Actions } from "./ChronicleActions";

const T = {
  en: {
    close: "Close", prev: "Previous fight", next: "Next fight", tabs: { replay: "Action replay", overview: "Overview", spells: "Spells", group: "Group", graph: "Timeline", events: "Recorded events", actions: "Combat log" } as Record<string, string>,
    kill: "Defeated", wipe: "Wiped", win: "Victory", loss: "Defeat", ended: "Ended", interrupted: "Interrupted", boss: "Boss fight", pvp: "PvP fight", combat: "Fight", attempt: "attempt", players: "players",
    damage: "Damage done", healing: "Healing done", taken: "Damage taken", deaths: "Deaths", interrupts: "Interrupts", dispels: "Dispels", duration: "Duration",
    perSecond: "per second", ofGroup: "of the group's damage", score: "Score", kills: "Honorable kills", assists: "Assists", objectives: "Objectives", honor: "Honor",
    spell: "Spell", casts: "Casts", total: "Total", share: "Share", average: "Average", best: "Highest", crit: "Crit", none: "Nothing recorded here.",
    top: "Top spells", role: { tank: "Tank", healer: "Healer", dps: "Damage" } as Record<string, string>, you: "you", marks: "Moments of the fight", hoverNote: "Click the graph to jump there.",
    series: { dmg: "Damage", heal: "Healing", taken: "Taken" } as Record<string, string>,
    unrecorded: "Not recorded", partial: "Some fight measurements were not available.", eventsNote: "The recorded events during this fight. Click an event to jump to it.",
    eventAction: { jump: "Jumped", cast: "Used", cast_start: "Started casting", cast_failed: "Cast failed", mount: "Mounted", dismount: "Dismounted", item: "Used item", item_attempt: "Use requested" } as Record<string, string>,
    gained: "Gained", lost: "Lost", refreshed: "Refreshed", started: "Entered combat", finished: "Left combat", stacks: "stacks",
    noMeasurements: "Measurements for this fight were not recorded.", findEvents: "Find an event or spell", showMore: "Show more", of: "of",
    play: "Play actions", pause: "Pause actions", previousAction: "Previous action", nextAction: "Next action", continue: "Continue the journey", action: "Action", fighting: "In combat", replayDone: "Fight replay finished", replayNote: "Actual recorded actions, shown one at a time. Hits without a recording are not reconstructed.", eventSource: "Recorded event", unknownActor: "Unknown participant", opponent: "Opponent", replaySpeed: "Action replay speed",
    logAction: { dmg: "Damage", heal: "Healing", cast: "Used", aura: "Aura", interrupt: "Interrupted", dispel: "Dispelled", death: "Died" } as Record<string, string>,
  },
  cs: {
    close: "Zavřít", prev: "Předchozí souboj", next: "Další souboj", tabs: { replay: "Přehrání akcí", overview: "Přehled", spells: "Kouzla", group: "Skupina", graph: "Průběh", events: "Zaznamenané události", actions: "Bojový log" } as Record<string, string>,
    kill: "Poražen", wipe: "Neúspěch", win: "Vítězství", loss: "Porážka", ended: "Ukončen", interrupted: "Přerušen", boss: "Souboj s bossem", pvp: "PvP souboj", combat: "Souboj", attempt: "pokus", players: "hráčů",
    damage: "Způsobené poškození", healing: "Léčení", taken: "Utržené poškození", deaths: "Smrti", interrupts: "Přerušení", dispels: "Rozptýlení", duration: "Trvání",
    perSecond: "za sekundu", ofGroup: "poškození skupiny", score: "Skóre", kills: "Čestná zabití", assists: "Asistence", objectives: "Cíle", honor: "Čest",
    spell: "Kouzlo", casts: "Použití", total: "Celkem", share: "Podíl", average: "Průměr", best: "Nejvyšší", crit: "Krit", none: "Tady nic není zaznamenáno.",
    top: "Nejsilnější kouzla", role: { tank: "Tank", healer: "Léčitel", dps: "Poškození" } as Record<string, string>, you: "ty", marks: "Okamžiky souboje", hoverNote: "Kliknutím do grafu se tam přesuneš.",
    series: { dmg: "Poškození", heal: "Léčení", taken: "Utrženo" } as Record<string, string>,
    unrecorded: "Nezaznamenáno", partial: "Část měření tohoto souboje nebyla dostupná.", eventsNote: "Zaznamenané události v průběhu souboje. Kliknutím se přesuneš na daný okamžik.",
    eventAction: { jump: "Skok", cast: "Použito", cast_start: "Začátek sesílání", cast_failed: "Seslání selhalo", mount: "Nasednutí", dismount: "Sesednutí", item: "Použitý předmět", item_attempt: "Pokus o použití" } as Record<string, string>,
    gained: "Získáno", lost: "Ztraceno", refreshed: "Obnoveno", started: "Začátek boje", finished: "Konec boje", stacks: "vrstev",
    noMeasurements: "Metriky tohoto souboje nejsou zaznamenané.", findEvents: "Hledat událost nebo kouzlo", showMore: "Zobrazit další", of: "z",
    play: "Přehrát akce", pause: "Pozastavit akce", previousAction: "Předchozí akce", nextAction: "Další akce", continue: "Pokračovat v cestě", action: "Událost", fighting: "Probíhá boj", replayDone: "Přehrání souboje dokončeno", replayNote: "Skutečně zaznamenané akce, postupně jedna po druhé. Zásahy bez záznamu se nedopočítávají.", eventSource: "Zaznamenaná událost", unknownActor: "Neznámý účastník", opponent: "Protivník", replaySpeed: "Rychlost přehrávání akcí",
    logAction: { dmg: "Poškození", heal: "Léčení", cast: "Použito", aura: "Aura", interrupt: "Přerušení", dispel: "Rozptýlení", death: "Smrt" } as Record<string, string>,
  },
};
const SCHOOL: Record<string, string> = { physical: "#c9c4d6", nature: "#7fd26a", fire: "#ff8a3c", frost: "#6cc4ff", shadow: "#a77bd6", arcane: "#e08cf0", holy: "#ffd86b" };
const SERIES_COLOR = { dmg: "#ff9a3c", heal: "#5fd08f", taken: "#e2786a" } as const;
export const num = (n: number | null | undefined) => n !== undefined && n !== null && Number.isFinite(n) ? Math.round(n).toLocaleString("en-US").replace(/,/g, " ") : "–";

const Tile = ({ value, label, sub, tone }: { value: string; label: string; sub?: string; tone?: string }) => (
  <div className="chr-tile" style={tone ? { ["--tone" as string]: tone } : undefined}><b>{value}</b><span>{label}</span>{sub && <small>{sub}</small>}</div>
);

function SpellTable({ rows, w, color }: { rows: readonly SpellRow[]; w: typeof T.en; color: string }) {
  const total = rows.reduce((a, r) => a + r.total, 0) || 1;
  if (!rows.length) return <p className="chr-muted">{w.none}</p>;
  return (
    <table className="chr-spells">
      <thead><tr><th>{w.spell}</th><th>{w.casts}</th><th>{w.total}</th><th>{w.share}</th><th>{w.average}</th><th>{w.best}</th><th>{w.crit}</th></tr></thead>
      <tbody>{rows.map(r => {
        const hits = r.hits ?? r.casts;
        return (
          <tr key={r.name}>
            <td><SpellIcon id={r.id} size={24} label={r.name} /> {r.name}</td>
            <td title={r.casts === undefined ? w.unrecorded : undefined}>{num(r.casts)}</td><td>{num(r.total)}</td>
            <td className="chr-share"><i style={{ width: `${(r.total / total) * 100}%`, background: SCHOOL[r.school ?? "physical"] ?? color }} /><span>{Math.round((r.total / total) * 100)}%</span></td>
            <td>{hits ? num(r.total / hits) : "–"}</td><td>{r.max !== undefined ? num(r.max) : "–"}</td><td>{r.crits !== undefined && hits ? `${Math.round((r.crits / hits) * 100)}%` : "–"}</td>
          </tr>
        );
      })}</tbody>
    </table>
  );
}

function Meters({ members, by, w }: { members: readonly Member[]; by: "dmg" | "heal" | "taken"; w: typeof T.en }) {
  const sorted = [...members].sort((a, b) => (b[by] ?? -1) - (a[by] ?? -1));
  const top = sorted[0]?.[by] || 1;
  return (
    <ol className="chr-meters">{sorted.map(m => (
      <li key={m.name} className={m.me ? "is-me" : ""}>
        <img src={classIconUrl(m.classId)} alt="" width={28} height={28} />
        <span className="chr-bar-row" style={{ ["--c" as string]: CLASS_COLORS[m.classId] ?? "#69ccf0" }}>
          {m[by] !== undefined && <i style={{ width: `${(m[by]! / top) * 100}%` }} />}
          <b>{m.name}{m.me ? ` · ${w.you}` : ""}</b>
          <small>{m.role ? w.role[m.role] : CLASSES[m.classId]}{m.deaths ? ` · ☠ ${m.deaths}` : ""}</small>
        </span>
        <strong title={m[by] === undefined ? w.unrecorded : undefined}>{num(m[by])}</strong>
      </li>
    ))}</ol>
  );
}

/** The fight second by second: damage, healing and damage taken as lines, the moments as pins, and the playhead. */
function Graph({ f, local, show, onSeek, w }: { f: Fight; local: number; show: Record<"dmg" | "heal" | "taken", boolean>; onSeek: (local: number) => void; w: typeof T.en }) {
  const [hover, setHover] = useState<number | null>(null);
  const sr = f.series;
  const W = 680, H = 210, L = 46, R = 10, TOP = 26, B = 24, iw = W - L - R, ih = H - TOP - B;
  const keys = (["dmg", "heal", "taken"] as const).filter(k => show[k] && sr?.[k]?.length);
  const peak = useMemo(() => Math.max(1, ...keys.flatMap(k => (sr?.[k] ?? []).map(v => v / (sr?.step ?? 1)))), [keys, sr]);
  if (!sr) return <p className="chr-muted">{w.none}</p>;
  const x = (t: number) => L + (Math.min(f.d, Math.max(0, t)) / Math.max(1, f.d)) * iw;
  const y = (v: number) => TOP + ih - (v / peak) * ih;
  const line = (a: number[]) => a.map((v, i) => `${i ? "L" : "M"}${x((i + 0.5) * sr.step).toFixed(1)} ${y(v / sr.step).toFixed(1)}`).join(" ");
  const area = (a: number[]) => `${line(a)} L${x((a.length - 0.5) * sr.step).toFixed(1)} ${y(0)} L${x(0.5 * sr.step).toFixed(1)} ${y(0)} Z`;
  const step = f.d > 240 ? 60 : f.d > 100 ? 30 : 10;
  const ticks = Array.from({ length: Math.floor(f.d / step) + 1 }, (_, i) => i * step);
  const at = (event: ReactPointerEvent) => { const r = event.currentTarget.getBoundingClientRect(); return Math.min(f.d, Math.max(0, ((event.clientX - r.left) / r.width * W - L) / iw * f.d)); };
  const idx = hover === null ? -1 : Math.min(sr.dmg.length - 1, Math.floor(hover / sr.step));
  return (
    <div className="chr-graph" onPointerMove={event => setHover(at(event))} onPointerLeave={() => setHover(null)} onClick={event => onSeek(at(event as unknown as ReactPointerEvent))}>
      <svg viewBox={`0 0 ${W} ${H}`} role="img" aria-label={w.tabs.graph}>
        {[0, 0.25, 0.5, 0.75, 1].map(g => <g key={g}><line x1={L} x2={W - R} y1={y(peak * g)} y2={y(peak * g)} className="chr-grid-line" /><text x={L - 6} y={y(peak * g) + 3} textAnchor="end">{num(peak * g)}</text></g>)}
        {ticks.map(t => <text key={t} x={x(t)} y={H - 6} textAnchor="middle">{clock(t)}</text>)}
        {keys.map(k => <g key={k}><path d={area(sr[k]!)} fill={SERIES_COLOR[k]} opacity={0.14} /><path d={line(sr[k]!)} fill="none" stroke={SERIES_COLOR[k]} strokeWidth={2} strokeLinejoin="round" /></g>)}
        {(f.marks ?? []).map((m, i) => <g key={i}><line x1={x(m.t)} x2={x(m.t)} y1={TOP} y2={y(0)} className="chr-mark-line" /><title>{`${clock(m.t)} ${m.text}`}</title>
          <circle cx={x(m.t)} cy={TOP - 10} r={9} fill={m.kind === "death" ? "#d9534f" : m.kind === "phase" ? "#a78bfa" : m.kind === "interrupt" ? "#5b8def" : "#f2c04b"} />
          <text x={x(m.t)} y={TOP - 6} textAnchor="middle" className="chr-mark-glyph">{m.kind === "death" ? "☠" : m.kind === "phase" ? "▸" : m.kind === "interrupt" ? "✋" : "★"}</text></g>)}
        {local >= 0 && local <= f.d && <line x1={x(local)} x2={x(local)} y1={TOP - 4} y2={y(0)} className="chr-playhead" />}
        {hover !== null && <line x1={x(hover)} x2={x(hover)} y1={TOP} y2={y(0)} className="chr-hover-line" />}
      </svg>
      {hover !== null && idx >= 0 && (
        <div className="chr-tip" style={{ left: `${(x(hover) / W) * 100}%` }}>
          <b>{clock(hover)}</b>
          {(["dmg", "heal", "taken"] as const).filter(k => sr[k]?.length).map(k => <span key={k} style={{ color: SERIES_COLOR[k] }}>{w.series[k]} {num((sr[k]![idx] ?? 0) / sr.step)}/s</span>)}
        </div>
      )}
    </div>
  );
}

function eventText(e: ChronicleEvent, w: typeof T.en): string {
  if (e.k === "speech") return `${e.speaker ?? e.text}: ${e.message ?? ""}`;
  if (e.k === "action") {
    const prefix = e.a ? w.eventAction[e.a] : undefined;
    return e.a === "jump" ? w.eventAction.jump : prefix ? `${prefix}: ${e.text}` : e.text;
  }
  if (e.k === "aura") return `${e.a === "loss" ? w.lost : e.a === "refresh" ? w.refreshed : w.gained}: ${e.text}`;
  if (e.k === "combat") return `${e.a === "start" ? w.started : w.finished}: ${e.text}`;
  return `${e.text}${e.xp ? ` +${e.xp} XP` : ""}`;
}

/** These are the recorder's observed moments; they do not stand in for an unavailable combat log. */
function ObservedEvents({ events, fight, time, onSeek, w }: { events: readonly ChronicleEvent[]; fight: Fight; time: number; onSeek: (t: number) => void; w: typeof T.en }) {
  const [query, setQuery] = useState("");
  const [limit, setLimit] = useState(200);
  const filtered = useMemo(() => {
    const q = query.trim().toLocaleLowerCase();
    return q ? events.filter(e => `${eventText(e, w)} ${e.detail ?? ""}`.toLocaleLowerCase().includes(q)) : events;
  }, [events, query, w]);
  return (
    <>
      <p className="chr-muted">{w.eventsNote}</p>
      <label className="chr-event-search"><span>{w.findEvents}</span><input type="search" value={query} onChange={event => { setQuery(event.target.value); setLimit(200); }} placeholder={w.findEvents} /></label>
      <p className="chr-muted">{Math.min(limit, filtered.length)} {w.of} {filtered.length}</p>
      <ol className="chr-moments chr-recorded-events">
        {filtered.slice(0, limit).map((e, i) => (
          <li key={`${e.t}:${e.k}:${i}`} className={e.t <= time && time - e.t < 1 ? "is-current" : ""}>
            <button type="button" onClick={() => onSeek(e.t)}>
              <time>{clock(Math.max(0, e.t - fight.t))}</time>
              {e.k === "loot" || e.k === "action" && e.a === "item" ? <ItemIcon id={e.id} q={e.q} size={26} /> : e.k === "aura" || e.k === "action" && e.a?.startsWith("cast") ? <SpellIcon id={e.id} icon={e.icon} helpful={e.helpful} label={e.text} size={26} /> : <IconChip k={typeKey(e)} size={26} />}
              <span>{eventText(e, w)}{(e.detail || e.stacks !== undefined) && <small>{[e.detail, e.stacks !== undefined ? `${e.stacks} ${w.stacks}` : null].filter(Boolean).join(" · ")}</small>}</span>
            </button>
          </li>
        ))}
        {!filtered.length && <li className="chr-muted">{w.none}</li>}
      </ol>
      {limit < filtered.length && <button type="button" className="chr-btn" onClick={() => setLimit(n => n + 200)}>{w.showMore}</button>}
    </>
  );
}

function describeTurn(turn: FightTurn, c: Chronicle, f: Fight, w: typeof T.en) {
  if (turn.kind === "start" || turn.kind === "end") return { source: f.name, text: turn.kind === "start" ? w.started : w[f.result], target: undefined, amount: undefined };
  if (turn.kind === "event") {
    const e = turn.event;
    return { source: e.actor ?? (e.k === "speech" ? e.speaker ?? e.text : e.k === "kill" || e.k === "boss" ? w.eventSource : c.character.name), text: eventText(e, w), target: e.target, amount: undefined };
  }
  const line = turn.line, spell = f.spells?.[line[4]]?.name, kind = LOG_KINDS[line[3]];
  return { source: f.actors?.[line[1]]?.name ?? w.unknownActor, target: f.actors?.[line[2]]?.name, text: `${w.logAction[kind]}${spell ? `: ${spell}` : ""}`, amount: kind === "dmg" || kind === "heal" ? `${num(line[5])}${line[6] ? " !" : ""}` : undefined };
}

function TurnIcon({ turn, fight }: { turn: FightTurn; fight: Fight }) {
  if (turn.kind === "event") {
    const e = turn.event;
    if (e.k === "aura" || e.k === "action" && e.a?.startsWith("cast")) return <SpellIcon id={e.id} icon={e.icon} helpful={e.helpful} label={e.text} size={32} />;
    if (e.k === "loot" || e.k === "action" && (e.a === "item" || e.a === "item_attempt")) return <ItemIcon id={e.id} q={e.q} size={32} />;
    return <IconChip k={typeKey(e)} size={32} />;
  }
  if (turn.kind === "log") return <SpellIcon label={fight.spells?.[turn.line[4]]?.name} size={32} />;
  return <IconChip k={fight.kind === "pvp" ? "combat.pvp" : fight.kind === "boss" ? "combat.boss" : "combat.fight"} size={32} />;
}

/** A replay of observations, not a simulation: equal-time actions each get their own readable step. */
function FightReplay({ c, fight, index, time, autoPlay, active, onSeek, w }: { c: Chronicle; fight: Fight; index: number; time: number; autoPlay: boolean; active: boolean; onSeek: (t: number) => void; w: typeof T.en }) {
  const turns = useMemo(() => fightTurns(c, index), [c, index]);
  const [cursor, setCursor] = useState(() => autoPlay ? 0 : Math.max(0, turns.findLastIndex(turn => turn.t <= time)));
  const [playing, setPlaying] = useState(autoPlay);
  const [rate, setRate] = useState(1);
  const history = useRef<HTMLOListElement>(null);
  const turn = turns[cursor];
  useEffect(() => {
    if (!active || !playing || cursor >= turns.length - 1) return;
    const timer = window.setTimeout(() => {
      const next = cursor + 1;
      setCursor(next); onSeek(turns[next].t);
      if (next === turns.length - 1) setPlaying(false);
    }, turnDelay(turns[cursor].t, turns[cursor + 1].t) / rate);
    return () => window.clearTimeout(timer);
  }, [active, playing, cursor, turns, rate, onSeek]);
  useEffect(() => { if (history.current) history.current.scrollTop = history.current.scrollHeight; }, [cursor]);
  if (!turn) return <p className="chr-muted">{w.none}</p>;
  const now = describeTurn(turn, c, fight, w);
  const step = (next: number) => { setPlaying(false); const at = Math.max(0, Math.min(turns.length - 1, next)); setCursor(at); onSeek(turns[at].t); };
  const toggle = () => {
    if (!playing && cursor === turns.length - 1) { setCursor(0); onSeek(turns[0].t); }
    setPlaying(value => !value);
  };
  return (
    <div className="chr-replay">
      <div className="chr-replay-actors">
        <div className={now.source === c.character.name ? "is-active" : ""}><img src={classIconUrl(c.character.classId)} alt="" width={40} height={40} /><span><b>{c.character.name}</b><small>{w.you}</small></span></div>
        <TypeIcon k="combat.fight" size={22} />
        <div className={now.source === fight.name ? "is-active" : ""}>{fight.kind === "pvp" ? <IconChip k="combat.pvp" size={40} /> : <NpcIcon id={fight.npcId} displayId={fight.displayId} name={fight.name} size={48} />}<span><b>{fight.name}</b><small>{w.opponent}</small></span></div>
      </div>
      <div className="chr-replay-current" key={cursor} aria-live="polite" aria-atomic="true">
        <TurnIcon turn={turn} fight={fight} />
        <div><small>{now.source}{now.target ? ` → ${now.target}` : ""}</small><strong>{now.text}</strong></div>
        {now.amount !== undefined && <b className="chr-replay-amount">{now.amount}</b>}
      </div>
      <div className="chr-fight-playback">
        <button type="button" className="chr-btn" onClick={() => step(cursor - 1)} disabled={cursor === 0} aria-label={w.previousAction}>‹</button>
        <button type="button" className="chr-btn is-on" onClick={toggle}>{playing ? w.pause : w.play}</button>
        <button type="button" className="chr-btn" onClick={() => step(cursor + 1)} disabled={cursor >= turns.length - 1} aria-label={w.nextAction}>›</button>
        <span>{w.action} {cursor + 1} / {turns.length} · {clock(turn.t - fight.t)} / {clock(fight.d)}</span>
        <button type="button" className="chr-btn" aria-label={w.replaySpeed} onClick={() => setRate(value => value === 1 ? 2 : 1)}>{rate}×</button>
      </div>
      {cursor === turns.length - 1 && <p className="chr-replay-finished" role="status">{w.replayDone} · {w[fight.result]}</p>}
      <ol className="chr-replay-history" ref={history} aria-label={w.tabs.events}>
        {turns.slice(0, cursor + 1).map((item, i) => {
          const row = describeTurn(item, c, fight, w);
          return <li key={i} className={i === cursor ? "is-current" : ""}><button type="button" onClick={() => step(i)}><time>{clock(item.t - fight.t)}</time><TurnIcon turn={item} fight={fight} /><span className="chr-replay-copy"><b>{row.source}{row.target ? ` → ${row.target}` : ""}</b>{row.text}</span>{row.amount !== undefined && <strong>{row.amount}</strong>}</button></li>;
        })}
      </ol>
      <p className="chr-muted">{w.replayNote}</p>
    </div>
  );
}

export function FightWindow({ fight, index, count, c, lang, time, autoPlay = false, onClose, onContinue, onStep, onSeek }: {
  fight: Fight; index: number; count: number; c: Chronicle; lang: string; time: number; autoPlay?: boolean; onClose: () => void; onContinue: () => void; onStep: (delta: number) => void; onSeek: (t: number) => void;
}) {
  const w = T[lang === "cs" ? "cs" : "en"];
  type Tab = "replay" | "overview" | "spells" | "group" | "graph" | "events" | "actions";
  const [chosen, setTab] = useState<Tab>("replay");
  const dialog = useRef<HTMLElement>(null);
  useEffect(() => { dialog.current?.focus({ preventScroll: true }); }, []);
  const hasLog = (fight.log?.length ?? 0) > 0;
  const observed = useMemo(() => c.events.filter(e => e.k !== "state" && (e.f === index || e.f === undefined && e.t >= fight.t && e.t <= fight.t + fight.d)), [c, fight, index]);
  // only the tabs that have something to show: a recorder may not be able to read spells, the course of the fight or the log
  const tabs: Tab[] = [
    "replay",
    "overview",
    ...(fight.me.dealt.length + fight.me.healed.length + fight.me.took.length > 0 ? (["spells"] as Tab[]) : []),
    ...((fight.group?.length ?? 0) > 0 ? (["group"] as Tab[]) : []),
    ...((fight.series?.dmg?.length ?? 0) > 0 ? (["graph"] as Tab[]) : []),
    ...(observed.length > 0 ? (["events"] as Tab[]) : []),
    ...(hasLog ? (["actions"] as Tab[]) : []),
  ];
  const tab: Tab = tabs.includes(chosen) ? chosen : "overview";
  const [spellKind, setSpellKind] = useState<"dealt" | "healed" | "took">("dealt");
  const [meter, setMeter] = useState<"dmg" | "heal" | "taken">("dmg");
  const [show, setShow] = useState({ dmg: true, heal: true, taken: true });
  const win = fight.result === "kill" || fight.result === "win";
  const loss = fight.result === "wipe" || fight.result === "loss";
  const rate = (value: number | undefined) => value === undefined ? w.unrecorded : fight.d > 0 ? `${num(value / fight.d)} ${w.perSecond}` : undefined;
  const groupDmg = fight.coverage !== "partial" && fight.coverage !== "unavailable" && fight.group?.length && fight.group.every(m => m.dmg !== undefined) ? fight.group.reduce((a, m) => a + m.dmg!, 0) : undefined;
  const local = time - fight.t;
  const when = new Date(whenOf(c, fight.t) * 1000).toLocaleString(lang === "cs" ? "cs-CZ" : "en-GB", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });
  const result = local >= fight.d ? w[fight.result] : w.fighting;
  const sub = [fight.kind === "pvp" ? w.pvp : fight.kind === "combat" ? w.combat : w.boss, fight.difficulty, fight.size ? `${fight.size} ${w.players}` : null, fight.attempt && fight.attempt > 1 ? `${w.attempt} ${fight.attempt}` : null].filter(Boolean).join(" · ");
  return (
    <div className="chr-scrim" onClick={onClose}>
      <section ref={dialog} className={`chr-card chr-fight${tab === "actions" ? " is-wide" : ""}`} role="dialog" aria-modal="true" tabIndex={-1} aria-label={fight.name} onClick={event => event.stopPropagation()} onKeyDown={event => {
        if (event.key !== "Tab") { if (event.key !== "Escape") event.stopPropagation(); return; }
        const controls = Array.from(dialog.current?.querySelectorAll<HTMLElement>("button:not(:disabled), input, a[href]") ?? []).filter(el => el.getClientRects().length);
        const first = controls[0], last = controls[controls.length - 1];
        if (event.shiftKey && (event.target === first || event.target === dialog.current)) { event.preventDefault(); last?.focus(); }
        else if (!event.shiftKey && event.target === last) { event.preventDefault(); first?.focus(); }
        event.stopPropagation();
      }}>
        <header>
          {fight.kind === "pvp" ? <IconChip k="combat.pvp" size={44} /> : <NpcIcon id={fight.npcId} displayId={fight.displayId} name={fight.name} size={52} />}
          <div className="chr-fight-title">
            <h2>{fight.name}</h2>
            <p>{sub} · {clock(fight.d)} · {when}</p>
          </div>
          <span className={`chr-result ${local >= fight.d && win ? "is-win" : local >= fight.d && loss ? "is-loss" : "is-neutral"}`}>{result}</span>
          <div className="chr-fight-nav">
            <button type="button" onClick={() => onStep(-1)} disabled={index <= 0} aria-label={w.prev}>‹</button>
            <button type="button" onClick={() => onStep(1)} disabled={index >= count - 1} aria-label={w.next}>›</button>
            <button type="button" onClick={onClose} aria-label={w.close}>×</button>
          </div>
        </header>
        <nav className="chr-tabs" role="tablist">{tabs.map(id => <button key={id} type="button" role="tab" aria-selected={tab === id} className={tab === id ? "is-on" : ""} onClick={() => setTab(id)}>{w.tabs[id]}</button>)}</nav>

        <div className="chr-fight-body">
          <div hidden={tab !== "replay"}><FightReplay c={c} fight={fight} index={index} time={time} autoPlay={autoPlay} active={tab === "replay"} onSeek={onSeek} w={w} /></div>
          {tab === "overview" && (
            <>
              {fight.pvp && (
                <div className="chr-score">
                  {fight.pvp.score && <p><span>{w.score}</span><b>{fight.pvp.score[0]} : {fight.pvp.score[1]}</b></p>}
                  <div className="chr-tiles">
                    <Tile value={String(fight.pvp.kills)} label={w.kills} /><Tile value={String(fight.pvp.deaths)} label={w.deaths} />
                    {fight.pvp.assists !== undefined && <Tile value={String(fight.pvp.assists)} label={w.assists} />}
                    {fight.pvp.objectives !== undefined && <Tile value={String(fight.pvp.objectives)} label={w.objectives} />}
                    {fight.pvp.honor !== undefined && <Tile value={num(fight.pvp.honor)} label={w.honor} tone="#f2c04b" />}
                  </div>
                </div>
              )}
              <div className="chr-tiles">
                <Tile value={num(fight.me.dmg)} label={w.damage} sub={rate(fight.me.dmg)} tone={SERIES_COLOR.dmg} />
                <Tile value={num(fight.me.heal)} label={w.healing} sub={rate(fight.me.heal)} tone={SERIES_COLOR.heal} />
                <Tile value={num(fight.me.taken)} label={w.taken} sub={rate(fight.me.taken)} tone={SERIES_COLOR.taken} />
                <Tile value={num(fight.me.deaths)} label={w.deaths} sub={fight.me.deaths === undefined ? w.unrecorded : undefined} />
                {fight.me.interrupts !== undefined && <Tile value={String(fight.me.interrupts)} label={w.interrupts} />}
                {fight.me.dispels !== undefined && <Tile value={String(fight.me.dispels)} label={w.dispels} />}
              </div>
              {fight.coverage === "unavailable" || [fight.me.dmg, fight.me.heal, fight.me.taken].every(v => v === undefined) ? <p className="chr-muted">{w.noMeasurements}</p> : fight.coverage === "partial" ? <p className="chr-muted">{w.partial}</p> : null}
              {groupDmg !== undefined && groupDmg > 0 && fight.me.dmg !== undefined && <p className="chr-share-line"><b>{Math.round((fight.me.dmg / groupDmg) * 100)}%</b> {w.ofGroup}</p>}
              {fight.me.dealt.length > 0 && <><h3>{w.top}</h3><SpellTable rows={fight.me.dealt.slice(0, 4)} w={w} color={SERIES_COLOR.dmg} /></>}
              {fight.marks && fight.marks.length > 0 && (
                <>
                  <h3>{w.marks}</h3>
                  <ul className="chr-fight-marks">{fight.marks.map((m, i) => <li key={i}><button type="button" onClick={() => onSeek(fight.t + m.t)}><time>{clock(m.t)}</time>{m.text}</button></li>)}</ul>
                </>
              )}
            </>
          )}
          {tab === "spells" && (
            <>
              <div className="chr-seg">{(["dealt", "healed", "took"] as const).map(k => <button key={k} type="button" className={spellKind === k ? "is-on" : ""} onClick={() => setSpellKind(k)}>{k === "dealt" ? w.damage : k === "healed" ? w.healing : w.taken}</button>)}</div>
              <SpellTable rows={fight.me[spellKind]} w={w} color={spellKind === "healed" ? SERIES_COLOR.heal : spellKind === "took" ? SERIES_COLOR.taken : SERIES_COLOR.dmg} />
            </>
          )}
          {tab === "group" && (
            fight.group?.length ? (
              <>
                <div className="chr-seg">{(["dmg", "heal", "taken"] as const).map(k => <button key={k} type="button" className={meter === k ? "is-on" : ""} onClick={() => setMeter(k)}>{k === "dmg" ? w.damage : k === "heal" ? w.healing : w.taken}</button>)}</div>
                <Meters members={fight.group} by={meter} w={w} />
              </>
            ) : <p className="chr-muted">{w.none}</p>
          )}
          {tab === "actions" && <Actions key={fight.t} f={fight} local={local} lang={lang} onSeek={l => onSeek(fight.t + l)} />}
          {tab === "events" && <ObservedEvents key={`${fight.t}:${index}`} events={observed} fight={fight} time={time} onSeek={onSeek} w={w} />}
          {tab === "graph" && (
            <>
              <div className="chr-seg is-series">{(["dmg", "heal", "taken"] as const).map(k => <button key={k} type="button" className={show[k] ? "is-on" : ""} style={{ ["--s" as string]: SERIES_COLOR[k] }} onClick={() => setShow(p => ({ ...p, [k]: !p[k] }))}>{w.series[k]}</button>)}</div>
              <Graph f={fight} local={local} show={show} onSeek={l => onSeek(fight.t + l)} w={w} />
              <p className="chr-muted"><TypeIcon k="combat.boss" size={12} /> {w.hoverNote}</p>
            </>
          )}
        </div>
        <footer className="chr-fight-footer"><button type="button" className="chr-btn is-on" onClick={onContinue}>{w.continue} →</button></footer>
      </section>
    </div>
  );
}

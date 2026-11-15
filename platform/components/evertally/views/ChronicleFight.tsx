"use client";
/* eslint-disable @next/next/no-img-element -- small bundled class icons */
// The window of one event: a boss fight, a dungeon or raid encounter, a battleground. What the character did and took, spell by
// spell, how the group did, and how the fight went second by second.
import { useMemo, useState, type PointerEvent as ReactPointerEvent } from "react";
import { clock, whenOf, type Chronicle, type Fight, type Member, type SpellRow } from "@/lib/chronicle";
import { CLASS_COLORS, CLASSES } from "../data";
import { IconChip, TypeIcon, classIconUrl } from "./ChronicleArt";
import { Actions } from "./ChronicleActions";

const T = {
  en: {
    close: "Close", prev: "Previous fight", next: "Next fight", tabs: { overview: "Overview", spells: "Spells", group: "Group", graph: "Timeline", actions: "Moves" } as Record<string, string>,
    kill: "Defeated", wipe: "Wiped", win: "Victory", loss: "Defeat", boss: "Boss fight", pvp: "Battleground", attempt: "attempt", players: "players",
    damage: "Damage done", healing: "Healing done", taken: "Damage taken", deaths: "Deaths", interrupts: "Interrupts", dispels: "Dispels", duration: "Duration",
    perSecond: "per second", ofGroup: "of the group's damage", score: "Score", kills: "Honorable kills", assists: "Assists", objectives: "Objectives", honor: "Honor",
    spell: "Spell", casts: "Casts", total: "Total", share: "Share", average: "Average", best: "Highest", crit: "Crit", none: "Nothing recorded here.",
    top: "Top spells", role: { tank: "Tank", healer: "Healer", dps: "Damage" } as Record<string, string>, you: "you", marks: "Moments of the fight", hoverNote: "Click the graph to jump there.",
    series: { dmg: "Damage", heal: "Healing", taken: "Taken" } as Record<string, string>,
  },
  cs: {
    close: "Zavřít", prev: "Předchozí souboj", next: "Další souboj", tabs: { overview: "Přehled", spells: "Kouzla", group: "Skupina", graph: "Průběh", actions: "Tahy" } as Record<string, string>,
    kill: "Poražen", wipe: "Neúspěch", win: "Vítězství", loss: "Porážka", boss: "Souboj s bossem", pvp: "Bojiště", attempt: "pokus", players: "hráčů",
    damage: "Způsobené poškození", healing: "Léčení", taken: "Utržené poškození", deaths: "Smrti", interrupts: "Přerušení", dispels: "Rozptýlení", duration: "Trvání",
    perSecond: "za sekundu", ofGroup: "poškození skupiny", score: "Skóre", kills: "Čestná zabití", assists: "Asistence", objectives: "Cíle", honor: "Čest",
    spell: "Kouzlo", casts: "Použití", total: "Celkem", share: "Podíl", average: "Průměr", best: "Nejvyšší", crit: "Krit", none: "Tady nic není zaznamenáno.",
    top: "Nejsilnější kouzla", role: { tank: "Tank", healer: "Léčitel", dps: "Poškození" } as Record<string, string>, you: "ty", marks: "Okamžiky souboje", hoverNote: "Kliknutím do grafu se tam přesuneš.",
    series: { dmg: "Poškození", heal: "Léčení", taken: "Utrženo" } as Record<string, string>,
  },
};
const SCHOOL: Record<string, string> = { physical: "#c9c4d6", nature: "#7fd26a", fire: "#ff8a3c", frost: "#6cc4ff", shadow: "#a77bd6", arcane: "#e08cf0", holy: "#ffd86b" };
const SERIES_COLOR = { dmg: "#ff9a3c", heal: "#5fd08f", taken: "#e2786a" } as const;
export const num = (n: number) => Math.round(n).toLocaleString("en-US").replace(/,/g, " ");

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
            <td><span className="chr-school" style={{ background: SCHOOL[r.school ?? "physical"] ?? color }}>{r.name.slice(0, 1)}</span>{r.name}</td>
            <td>{num(r.casts)}</td><td>{num(r.total)}</td>
            <td className="chr-share"><i style={{ width: `${(r.total / total) * 100}%`, background: SCHOOL[r.school ?? "physical"] ?? color }} /><span>{Math.round((r.total / total) * 100)}%</span></td>
            <td>{hits ? num(r.total / hits) : "–"}</td><td>{r.max !== undefined ? num(r.max) : "–"}</td><td>{r.crits !== undefined && hits ? `${Math.round((r.crits / hits) * 100)}%` : "–"}</td>
          </tr>
        );
      })}</tbody>
    </table>
  );
}

function Meters({ members, by, w }: { members: readonly Member[]; by: "dmg" | "heal" | "taken"; w: typeof T.en }) {
  const sorted = [...members].sort((a, b) => b[by] - a[by]);
  const top = sorted[0]?.[by] || 1;
  return (
    <ol className="chr-meters">{sorted.map(m => (
      <li key={m.name} className={m.me ? "is-me" : ""}>
        <img src={classIconUrl(m.classId)} alt="" width={28} height={28} />
        <span className="chr-bar-row" style={{ ["--c" as string]: CLASS_COLORS[m.classId] ?? "#69ccf0" }}>
          <i style={{ width: `${(m[by] / top) * 100}%` }} />
          <b>{m.name}{m.me ? ` · ${w.you}` : ""}</b>
          <small>{m.role ? w.role[m.role] : CLASSES[m.classId]}{m.deaths ? ` · ☠ ${m.deaths}` : ""}</small>
        </span>
        <strong>{num(m[by])}</strong>
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

export function FightWindow({ fight, index, count, c, lang, time, onClose, onStep, onSeek }: {
  fight: Fight; index: number; count: number; c: Chronicle; lang: string; time: number; onClose: () => void; onStep: (delta: number) => void; onSeek: (t: number) => void;
}) {
  const w = T[lang === "cs" ? "cs" : "en"];
  type Tab = "overview" | "spells" | "group" | "graph" | "actions";
  const [chosen, setTab] = useState<Tab>("overview");
  const hasLog = (fight.log?.length ?? 0) > 0;
  // only the tabs that have something to show: a recorder may not be able to read spells, the course of the fight or the log
  const tabs: Tab[] = [
    "overview",
    ...(fight.me.dealt.length + fight.me.healed.length + fight.me.took.length > 0 ? (["spells"] as Tab[]) : []),
    ...((fight.group?.length ?? 0) > 0 ? (["group"] as Tab[]) : []),
    ...((fight.series?.dmg?.length ?? 0) > 0 ? (["graph"] as Tab[]) : []),
    ...(hasLog ? (["actions"] as Tab[]) : []),
  ];
  const tab: Tab = tabs.includes(chosen) ? chosen : "overview";
  const [spellKind, setSpellKind] = useState<"dealt" | "healed" | "took">("dealt");
  const [meter, setMeter] = useState<"dmg" | "heal" | "taken">("dmg");
  const [show, setShow] = useState({ dmg: true, heal: true, taken: true });
  const win = fight.result === "kill" || fight.result === "win";
  const dur = Math.max(1, fight.d);
  const groupDmg = (fight.group ?? []).reduce((a, m) => a + m.dmg, 0) || fight.me.dmg;
  const local = time - fight.t;
  const when = new Date(whenOf(c, fight.t) * 1000).toLocaleString(lang === "cs" ? "cs-CZ" : "en-GB", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });
  const result = w[fight.result];
  const sub = [fight.kind === "pvp" ? w.pvp : w.boss, fight.difficulty, fight.size ? `${fight.size} ${w.players}` : null, fight.attempt && fight.attempt > 1 ? `${w.attempt} ${fight.attempt}` : null].filter(Boolean).join(" · ");
  return (
    <div className="chr-scrim" onClick={onClose}>
      <section className={`chr-card chr-fight${tab === "actions" ? " is-wide" : ""}`} role="dialog" aria-label={fight.name} onClick={event => event.stopPropagation()}>
        <header>
          <IconChip k={fight.kind === "pvp" ? "combat.pvp" : "combat.boss"} size={44} />
          <div className="chr-fight-title">
            <h2>{fight.name}</h2>
            <p>{sub} · {clock(fight.d)} · {when}</p>
          </div>
          <span className={`chr-result ${win ? "is-win" : "is-loss"}`}>{result}</span>
          <div className="chr-fight-nav">
            <button type="button" onClick={() => onStep(-1)} disabled={index <= 0} aria-label={w.prev}>‹</button>
            <button type="button" onClick={() => onStep(1)} disabled={index >= count - 1} aria-label={w.next}>›</button>
            <button type="button" onClick={onClose} aria-label={w.close}>×</button>
          </div>
        </header>
        <nav className="chr-tabs" role="tablist">{tabs.map(id => <button key={id} type="button" role="tab" aria-selected={tab === id} className={tab === id ? "is-on" : ""} onClick={() => setTab(id)}>{w.tabs[id]}</button>)}</nav>

        <div className="chr-fight-body">
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
                <Tile value={num(fight.me.dmg)} label={w.damage} sub={`${num(fight.me.dmg / dur)} ${w.perSecond}`} tone={SERIES_COLOR.dmg} />
                <Tile value={num(fight.me.heal)} label={w.healing} sub={`${num(fight.me.heal / dur)} ${w.perSecond}`} tone={SERIES_COLOR.heal} />
                <Tile value={num(fight.me.taken)} label={w.taken} sub={`${num(fight.me.taken / dur)} ${w.perSecond}`} tone={SERIES_COLOR.taken} />
                <Tile value={String(fight.me.deaths)} label={w.deaths} />
                {fight.me.interrupts !== undefined && <Tile value={String(fight.me.interrupts)} label={w.interrupts} />}
                {fight.me.dispels !== undefined && <Tile value={String(fight.me.dispels)} label={w.dispels} />}
              </div>
              {fight.group && <p className="chr-share-line"><b>{Math.round((fight.me.dmg / groupDmg) * 100)}%</b> {w.ofGroup}</p>}
              <h3>{w.top}</h3>
              <SpellTable rows={fight.me.dealt.slice(0, 4)} w={w} color={SERIES_COLOR.dmg} />
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
          {tab === "graph" && (
            <>
              <div className="chr-seg is-series">{(["dmg", "heal", "taken"] as const).map(k => <button key={k} type="button" className={show[k] ? "is-on" : ""} style={{ ["--s" as string]: SERIES_COLOR[k] }} onClick={() => setShow(p => ({ ...p, [k]: !p[k] }))}>{w.series[k]}</button>)}</div>
              <Graph f={fight} local={local} show={show} onSeek={l => onSeek(fight.t + l)} w={w} />
              <p className="chr-muted"><TypeIcon k="combat.boss" size={12} /> {w.hoverNote}</p>
            </>
          )}
        </div>
      </section>
    </div>
  );
}

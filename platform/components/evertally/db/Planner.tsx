"use client";
import { useDeferredValue, useMemo, useState } from "react";
import { Icon } from "../ui";
import type { DungeonPin } from "./MapCanvas";
import { PoiBadge } from "./icons";
import { useDb } from "./parts";
import { loadNpc, zoneToWorld, type Flights, type World } from "./store";
import { clockText, SPEEDS, type Journey, type Place, type Step } from "./travel";
import { useS } from "./strings";

type Hit = { key: string; label: string; sub: string; poi: string; resolve: () => Promise<Place | null> };

function StopField({ label, placeholder, value, onChange, picking, onPickMode, zoneName, world, pins, flights }: {
  label: string; placeholder: string; value: Place | null; onChange: (place: Place | null) => void; picking: boolean; onPickMode: () => void;
  zoneName: (key: string) => string; world: World | null; pins: DungeonPin[]; flights: Flights | null;
}) {
  const s = useS();
  const { index } = useDb();
  const [text, setText] = useState("");
  const needle = useDeferredValue(text.trim().toLowerCase());
  const hits = useMemo<Hit[]>(() => {
    if (needle.length < 2 || !world) return [];
    const out: Hit[] = [];
    const match = (name: string) => name.toLowerCase().includes(needle);
    for (const [key, m] of Object.entries(world.maps)) {
      if (m.kind === "world" || m.kind === "continent" || !match(zoneName(key))) continue;
      out.push({ key: `z:${key}`, label: zoneName(key), sub: m.kind === "city" ? s.modeCity : s.zone, poi: "city", resolve: async () => ({ label: zoneName(key), u: (m.rect[0] + m.rect[1]) / 2, v: (m.rect[2] + m.rect[3]) / 2 }) });
      if (out.length >= 3) break;
    }
    for (const pin of pins.filter(p => match(p.label)).slice(0, 2)) out.push({ key: `d:${pin.key}`, label: pin.label, sub: pin.raid ? s.raid : s.dungeon, poi: pin.raid ? "raid" : "dungeon", resolve: async () => ({ label: pin.label, u: pin.u, v: pin.v }) });
    for (const [id, node] of Object.entries(flights?.nodes ?? {}).filter(([, n]) => match(n.n)).slice(0, 3)) out.push({ key: `f:${id}`, label: node.n, sub: s.flights, poi: "flight", resolve: async () => ({ label: node.n, u: node.u, v: node.v }) });
    if (index) {
      for (const row of index.search.npcs.filter(r => r[6] === 1 && match(r[1])).slice(0, 4)) {
        out.push({
          key: `n:${row[0]}`, label: row[1], sub: s.npc, poi: row[5][0] ?? "mob",
          resolve: async () => {
            const detail = await loadNpc(index, row[0]);
            const first = detail && Object.entries(detail.sp)[0];
            const rect = first && world.maps[first[0]]?.rect;
            if (!first || !rect || !first[1][0]) return null;
            const [u, v] = zoneToWorld(rect, first[1][0][0], first[1][0][1]);
            return { label: row[1], u, v };
          },
        });
      }
    }
    return out.slice(0, 9);
  }, [needle, world, pins, flights, index, zoneName, s]);
  const choose = async (hit: Hit) => {
    const place = await hit.resolve();
    if (place) { onChange(place); setText(""); }
  };
  return (
    <div className="stop-field">
      <span className="stop-label">{label}</span>
      <div className="stop-input">
        <label className="search"><input value={value ? value.label : text} onChange={event => { if (value) onChange(null); setText(event.target.value); }} placeholder={placeholder} aria-label={label} /></label>
        {value && <button type="button" className="icon-btn" onClick={() => { onChange(null); setText(""); }} aria-label={s.clear}><Icon name="close" size={14} /></button>}
        <button type="button" className={`btn btn-sm ${picking ? "btn-on" : "btn-ghost"}`} onClick={onPickMode} title={s.pickOnMap}><Icon name="map" size={14} /></button>
      </div>
      {!value && hits.length > 0 && (
        <div className="search-pop" role="listbox">
          {hits.map(hit => <button key={hit.key} type="button" onClick={() => void choose(hit)}><PoiBadge kind={hit.poi} size={20} /><span>{hit.label}</span><small>{hit.sub}</small></button>)}
        </div>
      )}
    </div>
  );
}

const MODE_POI: Record<Step["mode"], string> = { walk: "walk", flight: "flight", boat: "boat", zeppelin: "zeppelin", lift: "lift", tram: "tram", portal: "portal", passage: "passage" };

function JourneyList({ journey }: { journey: Journey }) {
  const s = useS();
  const name: Record<Step["mode"], string> = { walk: s.modeWalk, flight: s.modeFlight, boat: s.modeBoat, zeppelin: s.modeZeppelin, lift: s.modeLift, tram: s.modeTram, portal: s.modePortal, passage: s.modePassage };
  return (
    <div className="journey">
      <div className="chips"><span className="chip mono">{s.totalTime} {clockText(journey.seconds)}</span><span className="chip">{journey.steps.length}×</span></div>
      <ol className="journey-steps">
        {journey.steps.map((step, i) => (
          <li key={i}>
            <PoiBadge kind={MODE_POI[step.mode]} size={22} />
            <span className="js-text"><strong>{name[step.mode]}</strong> {step.from === step.to ? step.from : <>{step.from} <span className="muted">→</span> {step.to}</>}
              <small className="muted">{step.yards ? `${Math.round(step.yards).toLocaleString()} ${s.yards}${step.ground ? ` · ${s.onGround}` : ""}${step.estimated ? ` · ${s.approx}` : ""}` : ""}{step.wait ? `${step.yards ? " · " : ""}${s.waitAvg} ${clockText(step.wait)}` : ""}</small>
            </span>
            <span className="mono js-time">{clockText(step.seconds)}</span>
          </li>
        ))}
      </ol>
    </div>
  );
}

export function Planner({ from, to, setFrom, setTo, pickTarget, setPickTarget, side, setSide, speed, setSpeed, journey, ready, zoneName, world, pins, flights, onClear }: {
  from: Place | null; to: Place | null; setFrom: (place: Place | null) => void; setTo: (place: Place | null) => void;
  pickTarget: "from" | "to" | null; setPickTarget: (target: "from" | "to" | null) => void; side: "A" | "H"; setSide: (side: "A" | "H") => void;
  speed: number; setSpeed: (speed: number) => void; journey: Journey | null | undefined; ready: boolean;
  zoneName: (key: string) => string; world: World | null; pins: DungeonPin[]; flights: Flights | null; onClear: () => void;
}) {
  const s = useS();
  const labels: Record<number, string> = { 7: s.onFoot, 11.2: s.mount60, 14: s.mount100 };
  return (
    <section className="ms-block planner">
      <header><h3>{s.planner}</h3>{(from || to) && <button type="button" className="link-btn" onClick={onClear}>{s.clear}</button>}</header>
      <p className="fine-print tight">{s.plannerLead}</p>
      <StopField label={s.from} placeholder={s.fromPlaceholder} value={from} onChange={setFrom} picking={pickTarget === "from"} onPickMode={() => setPickTarget(pickTarget === "from" ? null : "from")} zoneName={zoneName} world={world} pins={pins} flights={flights} />
      <button type="button" className="swap" onClick={() => { const a = from; setFrom(to); setTo(a); }} aria-label={s.swap} title={s.swap}>⇅</button>
      <StopField label={s.to} placeholder={s.toPlaceholder} value={to} onChange={setTo} picking={pickTarget === "to"} onPickMode={() => setPickTarget(pickTarget === "to" ? null : "to")} zoneName={zoneName} world={world} pins={pins} flights={flights} />
      {pickTarget && <p className="muted small">{s.pickingHint}</p>}
      <div className="head-row">
        <label className="field grow"><span>{s.speed}</span><select value={speed} onChange={event => setSpeed(Number(event.target.value))}>{SPEEDS.map(value => <option key={value} value={value}>{labels[value]}</option>)}</select></label>
        <div className="field"><span>{s.side}</span><div className="segmented small"><button type="button" className={side === "A" ? "on" : ""} onClick={() => setSide("A")}>{s.alliance}</button><button type="button" className={side === "H" ? "on" : ""} onClick={() => setSide("H")}>{s.horde}</button></div></div>
      </div>
      {from && to && !ready && <p className="muted small">{s.loading}</p>}
      {from && to && ready && journey === null && <p className="muted small">{s.noJourney}</p>}
      {journey && <JourneyList journey={journey} />}
      {journey && <p className="fine-print tight">{s.plannerNote}</p>}
    </section>
  );
}

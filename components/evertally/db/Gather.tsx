"use client";
// "Gathering" on the map: where herbs, ore, chests and fishing pools were listed, with every resource switchable on its
// own, and an optional "my skill" that hides what you cannot gather yet.
import { useCallback, useEffect, useMemo, useState } from "react";
import { Icon } from "../ui";
import type { GatherSet, Trail } from "./MapCanvas";
import { farmRoute, type Pt } from "./farmRoute";
import { clockText, toYards, type Travel } from "./travel";
import { GATHER_KINDS, gatherColor, placeGather, useGatherFile, type GatherKind, type GatherNode } from "./gatherData";
import type { World } from "./store";
import { useS } from "./strings";

type Stored = { hidden: string[]; skill: number | null };
const STORAGE = "evertally.map.gather";
const fill = (text: string, values: Record<string, string | number>) => text.replace(/\{(\w+)\}/g, (_, key: string) => String(values[key] ?? ""));

export type GatherHook = ReturnType<typeof useGatherLayer>;
export type FarmContext = { zone: string; start: [number, number] | null; travel: Travel | null; speed: number };

export function useGatherLayer({ layers, world }: { layers: Record<string, boolean>; world: World | null }) {
  const s = useS();
  const file = useGatherFile(Boolean(layers.gather));
  const [stored, setStored] = useState<Stored>({ hidden: [], skill: null });

  useEffect(() => {
    // one-time client-side restore: localStorage does not exist while rendering on the server
    try {
      const raw = JSON.parse(window.localStorage.getItem(STORAGE) ?? "null") as Partial<Stored> | null;
      // eslint-disable-next-line react-hooks/set-state-in-effect
      if (raw) setStored({ hidden: Array.isArray(raw.hidden) ? raw.hidden.filter(key => typeof key === "string") : [], skill: typeof raw.skill === "number" && raw.skill > 0 ? raw.skill : null });
    } catch { /* storage unavailable or damaged */ }
  }, []);
  const update = useCallback((next: Stored) => {
    setStored(next);
    try { window.localStorage.setItem(STORAGE, JSON.stringify(next)); } catch { /* storage unavailable */ }
  }, []);

  const placed = useMemo(() => (file.data && world ? placeGather(file.data, world) : null), [file.data, world]);
  const nodes = useMemo(() => file.data?.nodes ?? [], [file.data]);
  const colors = useMemo(() => {
    const counters: Record<string, number> = {};
    return new Map(nodes.map(node => [node.key, gatherColor(node, counters[node.type] = (counters[node.type] ?? -1) + 1)]));
  }, [nodes]);
  const hiddenSet = useMemo(() => new Set(stored.hidden), [stored.hidden]);
  const visible = useCallback((node: GatherNode) => !hiddenSet.has(node.key) && (stored.skill === null || node.skill === null || node.skill <= stored.skill), [hiddenSet, stored.skill]);

  const sets = useMemo<GatherSet[]>(() => {
    if (!layers.gather || !placed) return [];
    return nodes.filter(visible).map(node => ({
      key: node.key, color: colors.get(node.key) ?? "#fff", pts: placed.points.get(node.key) ?? new Float32Array(),
      label: `${node.name}${node.skill ? ` · ${fill(s.gatherSkillShort, { skill: node.skill })}` : ""}`,
    }));
  }, [layers.gather, placed, nodes, visible, colors, s.gatherSkillShort]);

  // "show only this resource": applied once the resource list is there, because the layer may just have been switched on
  const [focusKey, setFocusKey] = useState<string | null>(null);
  useEffect(() => {
    if (!focusKey || !nodes.some(node => node.key === focusKey)) return;
    // eslint-disable-next-line react-hooks/set-state-in-effect -- applies a request that had to wait for the data
    update({ ...stored, hidden: nodes.filter(node => node.key !== focusKey).map(node => node.key) });
    setFocusKey(null);
  }, [focusKey, nodes, stored, update]);

  // a farming route through the chosen resources of one zone, from where you were last seen
  const [farm, setFarm] = useState<{ order: Pt[]; start: Pt | null; yards: number; seconds: number } | null>(null);
  const [farmNote, setFarmNote] = useState("");
  const planFarm = useCallback((context: FarmContext) => {
    const entry = world?.maps[context.zone];
    if (!world || !entry || (entry.kind !== "zone" && entry.kind !== "city")) { setFarm(null); setFarmNote(s.farmNeedZone); return; }
    const [l, r, t, b] = entry.rect;
    const inside: Pt[] = [];
    for (const set of sets) for (let i = 0; i + 1 < set.pts.length; i += 2) if (set.pts[i] >= l && set.pts[i] <= r && set.pts[i + 1] >= t && set.pts[i + 1] <= b) inside.push([set.pts[i], set.pts[i + 1]]);
    if (!inside.length) { setFarm(null); setFarmNote(s.farmNone); return; }
    const travel = context.travel;
    const yards = (a: Pt, c: Pt) => { if (!travel) return Math.hypot(a[0] - c[0], a[1] - c[1]) * 3000; const p = toYards(travel, a[0], a[1]), q = toYards(travel, c[0], c[1]); return p.c === q.c ? Math.hypot(p.x - q.x, p.y - q.y) : 1e9; };
    const start = context.start && context.start[0] >= l && context.start[0] <= r && context.start[1] >= t && context.start[1] <= b ? context.start : null;
    const result = farmRoute(inside, start, yards);
    setFarmNote(""); setFarm({ order: result.order, start, yards: result.yards, seconds: result.yards / context.speed });
  }, [world, sets, s.farmNeedZone, s.farmNone]);
  const trails = useMemo<Trail[]>(() => (farm && layers.gather ? [{ id: "farm", points: [...(farm.start ? [farm.start] : []), ...farm.order], color: "#ffffff", opacity: 1 }] : []), [farm, layers.gather]);

  return { focus: setFocusKey, sets, trails, panel: { layers, loading: file.loading, failed: file.error, nodes, colors, stored, update, visible, unplaced: placed?.unplaced ?? 0, farm, farmNote, planFarm, clearFarm: () => { setFarm(null); setFarmNote(""); } } };
}

export function GatherPanel({ panel, farmContext }: { panel: GatherHook["panel"]; farmContext: FarmContext }) {
  const s = useS();
  const [open, setOpen] = useState(true);
  const { stored, update, nodes } = panel;
  if (!panel.layers.gather) return null;

  const labels: Record<GatherKind, string> = { herb: s.gatherHerbs, ore: s.gatherOre, container: s.gatherChests, fishing: s.gatherFishing };
  const toggle = (key: string) => update({ ...stored, hidden: stored.hidden.includes(key) ? stored.hidden.filter(entry => entry !== key) : [...stored.hidden, key] });
  const setGroup = (kind: GatherKind, on: boolean) => {
    const keys = nodes.filter(node => node.type === kind).map(node => node.key);
    update({ ...stored, hidden: on ? stored.hidden.filter(key => !keys.includes(key)) : [...new Set([...stored.hidden, ...keys])] });
  };
  const shownPoints = nodes.filter(panel.visible).reduce((sum, node) => sum + node.n, 0);

  return (
    <section className={`people-panel gather-panel ${open ? "open" : ""}`} aria-label={s.gatherLayer}>
      <header>
        <h3><Icon name="search" size={15} /> {s.gatherLayer}</h3>
        <button type="button" className="icon-btn" onClick={() => setOpen(value => !value)} aria-expanded={open} aria-label={open ? "−" : "+"}>{open ? "−" : "+"}</button>
      </header>
      {open && (
        <div className="pp-body">
          {panel.failed && <p className="pp-notice" role="alert">{s.error}</p>}
          <div className="pp-block">
            <label className="pp-controls skill">
              <span>{s.gatherSkill}</span>
              <input type="number" min={1} max={300} inputMode="numeric" value={stored.skill ?? ""} placeholder="—" aria-label={s.gatherSkill}
                onChange={event => update({ ...stored, skill: Math.min(300, Number(event.target.value) || 0) || null })} />
            </label>
            <p className="muted small">{s.gatherSkillHint}</p>
          </div>
          {GATHER_KINDS.map(kind => {
            const group = nodes.filter(node => node.type === kind);
            if (!group.length) return null;
            return (
              <div className="pp-block" key={kind}>
                <div className="gather-head"><h4>{labels[kind]}</h4>
                  <span><button type="button" className="link-btn" onClick={() => setGroup(kind, true)}>{s.gatherAll}</button> · <button type="button" className="link-btn" onClick={() => setGroup(kind, false)}>{s.gatherNone}</button></span>
                </div>
                <div className="chip-grid" role="group" aria-label={labels[kind]}>
                  {group.map(node => {
                    const on = !stored.hidden.includes(node.key);
                    const reachable = panel.visible(node) || !on;
                    return (
                      <button key={node.key} type="button" className={`chip-toggle ${on ? "on" : ""} ${on && !reachable ? "locked" : ""}`} aria-pressed={on} onClick={() => toggle(node.key)} title={`${node.n} · ${node.skill ? fill(s.gatherSkillShort, { skill: node.skill }) : ""}`}>
                        <i className="swatch" style={{ background: panel.colors.get(node.key) }} aria-hidden="true" />{node.name}{node.skill ? <em>{node.skill}</em> : null}
                      </button>
                    );
                  })}
                </div>
              </div>
            );
          })}
          <div className="pp-block">
            <h4>{s.farmTitle}</h4>
            <div className="btn-row">
              <button type="button" className="btn btn-ghost btn-sm" onClick={() => panel.planFarm(farmContext)}>{s.farmPlan}</button>
              {panel.farm && <button type="button" className="btn btn-ghost btn-sm" onClick={panel.clearFarm}>{s.farmClear}</button>}
            </div>
            {panel.farm && <p className="small">{fill(s.farmSummary, { count: panel.farm.order.length, time: clockText(panel.farm.seconds) })}</p>}
            {panel.farmNote && <p className="muted small">{panel.farmNote}</p>}
          </div>
          <div className="pp-block">
            <p className="small">{fill(s.gatherShown, { count: shownPoints })}</p>
            {panel.unplaced > 0 && <p className="muted small">{fill(s.gatherUnplaced, { count: panel.unplaced })}</p>}
            <p className="fine-print">{s.gatherZoom} {s.gatherNote}</p>
          </div>
        </div>
      )}
    </section>
  );
}

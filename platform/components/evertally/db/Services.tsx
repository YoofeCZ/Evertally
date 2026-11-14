"use client";
// "Trainers & vendors" on the map: pick professions to see their trainers, pick reagents (or any item) to see who sells
// them. The map shows only what is chosen, so a town stays readable; the panel says how many places that is.
import { useCallback, useEffect, useMemo, useState } from "react";
import { useI18n } from "@/lib/i18n";
import { Icon } from "../ui";
import type { MapMarker } from "./MapCanvas";
import { PROFESSIONS, spawnsOf, trainersFor, useServices, vendorsFor, type Profession } from "./serviceData";
import { qualityClass, type Index, type World } from "./store";
import { split, useS } from "./strings";

type Mode = "any" | "all";
type Choice = { professions: Profession[]; items: number[]; mode: Mode };
const STORAGE = "evertally.map.services";
const MAX_MARKERS = 700;
const fill = (text: string, values: Record<string, string | number>) => text.replace(/\{(\w+)\}/g, (_, key: string) => String(values[key] ?? ""));
const limited = (names: string[], keep = 3) => (names.length > keep ? `${names.slice(0, keep).join(", ")} +${names.length - keep}` : names.join(", "));

export type ServicesHook = ReturnType<typeof useServiceMarkers>;

export function useServiceMarkers({ layers, world, index }: { layers: Record<string, boolean>; world: World | null; index: Index | null }) {
  const s = useS();
  const { lang } = useI18n();
  const services = useServices(Boolean(layers.services));
  const [choice, setChoice] = useState<Choice>({ professions: [], items: [], mode: "any" });
  const [query, setQuery] = useState("");

  useEffect(() => {
    // one-time client-side restore: localStorage does not exist while rendering on the server
    try {
      const stored = JSON.parse(window.localStorage.getItem(STORAGE) ?? "null") as Partial<Choice> | null;
      if (stored) {
        // eslint-disable-next-line react-hooks/set-state-in-effect
        setChoice({
          professions: (stored.professions ?? []).filter((p): p is Profession => (PROFESSIONS as readonly string[]).includes(p)),
          items: (stored.items ?? []).filter(item => Number.isInteger(item)).slice(0, 12),
          mode: stored.mode === "all" ? "all" : "any",
        });
      }
    } catch { /* storage unavailable or damaged */ }
  }, []);
  const update = useCallback((next: Choice) => {
    setChoice(next);
    try { window.localStorage.setItem(STORAGE, JSON.stringify(next)); } catch { /* storage unavailable */ }
  }, []);

  const names = useMemo(() => split(s.profNames), [s.profNames]);
  const professionName = useCallback((key: string) => names[PROFESSIONS.indexOf(key as Profession)] ?? key, [names]);
  const itemName = useCallback((id: number) => index?.items.get(id)?.[1] ?? `#${id}`, [index]);
  const npcName = useCallback((id: number) => index?.npcs.get(id)?.[1] ?? `NPC #${id}`, [index]);

  const result = useMemo(() => {
    const markers: MapMarker[] = [];
    let hidden = 0;
    let places = 0;
    if (!layers.services || !services.data || !world) return { markers, hidden, places };
    const add = (npc: number, poi: "trainer" | "vendor", label: string) => {
      const spots = spawnsOf(services.data!, npc, world);
      if (!spots.length) { hidden++; return; }
      places++;
      spots.forEach(([u, v], i) => {
        if (markers.length < MAX_MARKERS) markers.push({ key: `svc-${poi}-${npc}-${i}`, poi, u, v, label, sel: { kind: "npc", id: npc, label: npcName(npc), poi } });
      });
    };
    for (const [npc, taught] of trainersFor(services.data, choice.professions)) add(npc, "trainer", `${npcName(npc)} · ${fill(s.trainerOf, { profession: taught.map(professionName).join(", ") })}`);
    for (const [npc, sold] of vendorsFor(services.data, choice.items, choice.mode)) add(npc, "vendor", `${npcName(npc)} · ${fill(s.vendorSells, { items: limited(sold.map(itemName)) })}`);
    return { markers, hidden, places };
  }, [layers.services, services.data, world, choice, npcName, itemName, professionName, s.trainerOf, s.vendorSells]);

  const suggestions = useMemo(() => {
    const needle = query.trim().toLowerCase();
    if (needle.length < 2 || !services.data || !index) return [];
    const found: { id: number; name: string; rank: number }[] = [];
    for (const key of Object.keys(services.data.sells)) {
      const id = Number(key);
      if (choice.items.includes(id)) continue;
      const name = index.items.get(id)?.[1];
      if (!name) continue;
      const at = name.toLowerCase().indexOf(needle);
      if (at >= 0) found.push({ id, name, rank: at === 0 ? 0 : 1 });
    }
    return found.sort((a, b) => a.rank - b.rank || a.name.localeCompare(b.name, lang)).slice(0, 8);
  }, [query, services.data, index, choice.items, lang]);

  /** Adds an item to the vendor filter (the layer is switched on by the caller). */
  const showItem = useCallback((id: number) => update({ ...choice, items: choice.items.includes(id) ? choice.items : [...choice.items, id].slice(-12) }), [choice, update]);
  return {
    showItem,
    markers: result.markers,
    panel: { layers, loading: services.loading, failed: services.error, choice, update, query, setQuery, suggestions, quick: services.data?.quick ?? [], itemName, index, professionName, names, ...result },
  };
}

export function ServicesPanel({ panel }: { panel: ServicesHook["panel"] }) {
  const s = useS();
  const [open, setOpen] = useState(true);
  const { choice, update, index } = panel;
  if (!panel.layers.services) return null;
  const toggleProfession = (key: Profession) => update({ ...choice, professions: choice.professions.includes(key) ? choice.professions.filter(p => p !== key) : [...choice.professions, key] });
  const addItem = (id: number) => { if (!choice.items.includes(id) && choice.items.length < 12) update({ ...choice, items: [...choice.items, id] }); panel.setQuery(""); };
  const removeItem = (id: number) => update({ ...choice, items: choice.items.filter(item => item !== id) });
  const quality = (id: number) => qualityClass(index?.items.get(id)?.[2]);
  const empty = !choice.professions.length && !choice.items.length;

  return (
    <section className={`people-panel services-panel ${open ? "open" : ""}`} aria-label={s.servicesLayer}>
      <header>
        <h3><Icon name="search" size={15} /> {s.servicesLayer}</h3>
        <button type="button" className="icon-btn" onClick={() => setOpen(value => !value)} aria-expanded={open} aria-label={open ? "−" : "+"}>{open ? "−" : "+"}</button>
      </header>
      {open && (
        <div className="pp-body">
          {panel.failed && <p className="pp-notice" role="alert">{s.error}</p>}
          <div className="pp-block">
            <h4>{s.servicesTrainers}</h4>
            <div className="chip-grid" role="group" aria-label={s.servicesTrainers}>
              {PROFESSIONS.map(key => (
                <button key={key} type="button" className={`chip-toggle ${choice.professions.includes(key) ? "on" : ""}`} aria-pressed={choice.professions.includes(key)} onClick={() => toggleProfession(key)}>{panel.professionName(key)}</button>
              ))}
            </div>
          </div>
          <div className="pp-block">
            <h4>{s.servicesVendors}</h4>
            <label className="search"><Icon name="search" size={14} />
              <input value={panel.query} onChange={event => panel.setQuery(event.target.value)} placeholder={s.servicesSearch} aria-label={s.servicesSearch} disabled={panel.loading} />
            </label>
            {panel.suggestions.length > 0 && (
              <ul className="svc-suggest" role="listbox" aria-label={s.servicesSearch}>
                {panel.suggestions.map(entry => (
                  <li key={entry.id}><button type="button" role="option" aria-selected={false} onClick={() => addItem(entry.id)}><span className={quality(entry.id)}>{entry.name}</span></button></li>
                ))}
              </ul>
            )}
            {choice.items.length > 0 && (
              <>
                <div className="chip-grid" role="group" aria-label={s.servicesVendors}>
                  {choice.items.map(id => (
                    <button key={id} type="button" className="chip-toggle on item" onClick={() => removeItem(id)} title={s.servicesClear}><span className={quality(id)}>{panel.itemName(id)}</span> <i aria-hidden="true">×</i></button>
                  ))}
                </div>
                {choice.items.length > 1 && (
                  <div className="seg" role="group" aria-label={s.servicesMode}>
                    <button type="button" className={choice.mode === "any" ? "on" : ""} aria-pressed={choice.mode === "any"} onClick={() => update({ ...choice, mode: "any" })}>{s.modeAny}</button>
                    <button type="button" className={choice.mode === "all" ? "on" : ""} aria-pressed={choice.mode === "all"} onClick={() => update({ ...choice, mode: "all" })}>{s.modeAll}</button>
                  </div>
                )}
              </>
            )}
            {panel.quick.length > 0 && (
              <>
                <h5>{s.servicesQuick}</h5>
                <div className="chip-grid">
                  {panel.quick.filter(id => !choice.items.includes(id)).slice(0, 10).map(id => (
                    <button key={id} type="button" className="chip-toggle item" onClick={() => addItem(id)}><span className={quality(id)}>{panel.itemName(id)}</span></button>
                  ))}
                </div>
              </>
            )}
          </div>
          <div className="pp-block">
            {empty ? <p className="muted small">{s.servicesPick}</p> : (
              <>
                <p className="small">{fill(s.servicesShown, { count: panel.places })}</p>
                {panel.hidden > 0 && <p className="muted small">{fill(s.servicesHidden, { count: panel.hidden })}</p>}
                <div className="btn-row"><button type="button" className="btn btn-ghost btn-sm" onClick={() => update({ professions: [], items: [], mode: choice.mode })}>{s.servicesClearAll}</button></div>
              </>
            )}
            <p className="fine-print">{s.servicesNote}</p>
          </div>
        </div>
      )}
    </section>
  );
}

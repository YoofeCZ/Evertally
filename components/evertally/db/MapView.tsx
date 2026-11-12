"use client";
/* eslint-disable @next/next/no-img-element -- bundled dungeon art with a fixed size */
import { lazy, Suspense, useCallback, useDeferredValue, useEffect, useMemo, useState } from "react";
import { useI18n } from "@/lib/i18n";
import "@/app/db.css";
import { useApi } from "../api";
import { CommunityPackage } from "../CommunityPackage";
import type { Entity, User } from "../types";
import { Icon } from "../ui";
import { parseActivity, resolveMap, safeMapEntity, worldPins } from "../world-map";
import type { Camera, DrawTool, Drawing, DungeonPin, MapHighlight, MapMarker, RouteLeg, Selection, UserPin, ViewState } from "./MapCanvas";
import { FloorMaps } from "./Floors";
import { sanitizeDrawings } from "./draw";
import { clock, planRoute, type Leg } from "./flights";
import { bestZone, focusText, parseFocus, resolveFocus, type Focus, type Resolved } from "./focus";
import { POI, PoiBadge } from "./icons";
import { levelClass } from "./levels";
import { DbProvider, Fold, ItemChips, useDb, npcLevel, rankName } from "./parts";
import { MeetsPanel, useMeets } from "./Meets";
import { Movable } from "./Movable";
import { PeoplePanel, usePeople } from "./People";
import { GatherPanel, useGatherLayer } from "./Gather";
import { ServicesPanel, useServiceMarkers } from "./Services";
import { Planner } from "./Planner";
import { suggestSpots } from "./meetspot";
import { planGroundJourney } from "./ground";
import { planJourney, type Place } from "./travel";
import { qualityClass, useWalk, useDungeonArt, useDungeons, useFlights, useFloors, useMaps, useNpc, useObjects, usePlaces, useTravel, useWorld, zoneToWorld, type Flights } from "./store";
import { useS } from "./strings";

const MapCanvas = lazy(() => import("./MapCanvas"));

const WORLD = "azeroth";
const DEFAULT_LAYERS: Record<string, boolean> = { players: true, meets: false, gather: false, services: false, route: false, guild: false, qs: true, qe: true, inn: true, dungeon: true, flight: true, transport: true, activity: true };
const SERVICE_LAYERS = ["qs", "qe", "inn", "vendor", "trainer", "repair", "bank", "auction", "stable", "battle", "spirit", "mail"];
const CS: Record<string, string> = { qs: "Zadavatelé questů", qe: "Odevzdání questů", vendor: "Obchodníci", trainer: "Trenéři", inn: "Hostinští", bank: "Bankéři", auction: "Aukcionáři", stable: "Správci stájí", battle: "Bojoví mistři", repair: "Opravy", spirit: "Léčitelé duší", mail: "Schránky", dungeon: "Vstupy do dungeonů a raidů", flight: "Letištní mistři", transport: "Lodě, zeppeliny a vzducholodě" };
const EN: Record<string, string> = { qs: "Quest givers", qe: "Quest turn-ins", vendor: "Vendors", trainer: "Trainers", inn: "Innkeepers", bank: "Banks", auction: "Auction houses", stable: "Stable masters", battle: "Battlemasters", repair: "Repair", spirit: "Spirit healers", mail: "Mailboxes", dungeon: "Dungeon & raid entrances", flight: "Flight masters", transport: "Boats, zeppelins & airships" };
const norm = (text: string) => text.toLowerCase().replace(/^the /, "").replace(/[^a-z0-9]+/g, "");

type FloorTarget = { title: string; key?: string; mapId: number | null };
type PlanState = { from: number; to: number; legs: Leg[]; seconds: number } | "none";
type PickAction = { zone?: string; focus?: string; fly?: [number, number][]; select?: Selection };

function parseRoute(route: string) {
  const [path, qs = ""] = route.split("?");
  const meet = new URLSearchParams(qs).get("meet") ?? "";
  return { zone: path.split("/").filter(Boolean)[0] ?? WORLD, focus: parseFocus(new URLSearchParams(qs).get("focus")), meet: /^[A-Za-z0-9-]{4,20}$/.test(meet) ? meet : "" };
}
const go = (zone: string, focus?: string, replace = false) => {
  const hash = `#atlas/${zone}${focus ? `?focus=${focus}` : ""}`;
  if (replace) window.location.replace(hash); else window.location.hash = hash;
};

// ---- sidebar pieces ------------------------------------------------------------------------------
function QuestPin({ id, zone }: { id: number; zone: string }) {
  const { index } = useDb();
  const row = index?.quests.get(id);
  return <a className="elink quest" href={`#atlas/${zone}?focus=quest:${id}`}><PoiBadge kind="qs" size={16} /><span>{row?.[1] ?? `Quest #${id}`}</span>{row?.[2] && row[2] > 0 ? <small className="muted"> ({row[2]})</small> : null}</a>;
}

function NpcCard({ id, zone }: { id: number; zone: string }) {
  const s = useS();
  const { index } = useDb();
  const detail = useNpc(index, id);
  const row = index?.npcs.get(id);
  const d = detail.data;
  const home = row?.[8] ?? zone;
  const services = d?.services ?? row?.[5] ?? [];
  return (
    <div className="sel-card">
      <h4>{d?.name ?? row?.[1] ?? `NPC #${id}`}</h4>
      {d?.sub && <p className="subtitle">&lt;{d.sub}&gt;</p>}
      <div className="chips">
        {row && <span className="chip">{s.level} {npcLevel(row)}</span>}
        {row && row[4] > 0 && <span className="chip warn">{rankName(row[4])}</span>}
        {services.map(service => <span key={service} className="chip"><PoiBadge kind={service} size={14} />{POI[service]?.label ?? service}</span>)}
      </div>
      {detail.loading && <p className="muted small">{s.loading}</p>}
      {d?.starts && d.starts.length > 0 && <div><h5>{s.questsStart} ({d.starts.length})</h5><Fold className="quest-col" limit={6} items={d.starts.map(q => <QuestPin key={q} id={q} zone={home} />)} /></div>}
      {d?.ends && d.ends.length > 0 && <div><h5>{s.questsEnd} ({d.ends.length})</h5><Fold className="quest-col" limit={6} items={d.ends.map(q => <QuestPin key={q} id={q} zone={home} />)} /></div>}
      {d?.sells && d.sells.length > 0 && <div><h5>{s.sells} ({d.sells.length})</h5><ItemChips ids={d.sells} limit={8} /></div>}
      <div className="btn-row">
        <a className="btn btn-ghost btn-sm" href={`#atlas/${home}?focus=npc:${id}`}>{s.showOnMap}</a>
        <a className="btn btn-ghost btn-sm" href={`#database/npcs/${id}`}>{s.openPage}</a>
      </div>
    </div>
  );
}

function DungeonCard({ id, onFloors }: { id: string; onFloors: (target: FloorTarget) => void }) {
  const s = useS();
  const dungeons = useDungeons();
  const art = useDungeonArt();
  const floors = useFloors();
  const places = usePlaces();
  if (id.startsWith("map:")) {
    const mapId = Number(id.slice(4));
    const entry = places.data?.instances.flatMap(place => place.list).find(e => e.map === mapId);
    if (!entry) return <p className="muted small">{s.loading}</p>;
    const count = floors.data?.maps[String(mapId)]?.length ?? 0;
    return (
      <div className="sel-card">
        <h4>{entry.name}</h4>
        <div className="chips"><span className="chip">{entry.raid ? s.raid : s.dungeon}</span>{entry.min && <span className="chip mono">{s.level} {entry.min === entry.max || !entry.max ? entry.min : `${entry.min}–${entry.max}`}</span>}</div>
        {count > 0 && <button type="button" className="btn btn-primary btn-sm" onClick={() => onFloors({ title: entry.name, mapId })}>{s.openFloors} ({count})</button>}
      </div>
    );
  }
  const d = dungeons.data?.entries.find(entry => entry.key === id);
  if (!d) return <p className="muted small">{s.loading}</p>;
  const mapId = floors.data?.keys[d.key] ?? null;
  return (
    <div className="sel-card">
      {art.data?.[d.key] && <img className="sel-art" src={art.data[d.key].image} alt="" loading="lazy" />}
      <h4>{d.name}</h4>
      <div className="chips"><span className="chip">{d.type === "raid" ? s.raid : s.dungeon}</span><span className="chip mono">{s.level} {d.lvl ? `${d.lvl[0]}–${d.lvl[1]}` : "—"}</span><span className="chip">{d.players}p</span>{d.bosses.length > 0 && <span className="chip">{d.bosses.length} {s.bossCount}</span>}</div>
      {d.entrance?.hint && <p className="muted small">{d.entrance.hint}</p>}
      <div className="btn-row">
        {mapId != null && <button type="button" className="btn btn-primary btn-sm" onClick={() => onFloors({ title: d.name, key: d.key, mapId })}>{s.openFloors}</button>}
        <a className="btn btn-ghost btn-sm" href={`#database/dungeons/${d.key}`}>{s.openPage}</a>
      </div>
    </div>
  );
}

function FlightCard({ id, flights, planning, onPlan, onRoute }: { id: number; flights: Flights; planning: boolean; onPlan: () => void; onRoute: (from: number, to: number) => void }) {
  const s = useS();
  const node = flights.nodes[String(id)];
  const out = useMemo(() => flights.paths.filter(path => path.a === id).sort((a, b) => a.s - b.s), [flights, id]);
  if (!node) return null;
  return (
    <div className="sel-card">
      <h4>{node.n}</h4>
      <div className="chips">{node.f && <span className="chip">{node.f === "A" ? s.alliance : s.horde}</span>}<span className="chip">{s.flights}</span></div>
      {out.length > 0 && <div><h5>{s.direct}</h5><ul className="flight-list">{out.map(path => <li key={path.b}><button type="button" onClick={() => onRoute(id, path.b)}><span>{flights.nodes[String(path.b)]?.n}</span><span className="mono">{clock(path.s)}</span></button></li>)}</ul></div>}
      <button type="button" className={`btn btn-sm ${planning ? "btn-on" : "btn-ghost"}`} onClick={onPlan}>{planning ? s.cancel : s.planRoute}</button>
      {planning && <p className="muted small">{s.pickDestination}</p>}
    </div>
  );
}

type CardProps = {
  zone: string; flights: Flights | null; planning: boolean;
  onFloors: (target: FloorTarget) => void; onPlan: (id: number) => void; onRoute: (from: number, to: number) => void; onTravel: (role: "from" | "to", place: Place) => void;
  pins: UserPin[]; onPin: (id: string, change: { label: string } | null) => void;
};

function SelectionBody({ sel, ...card }: { sel: Selection } & CardProps) {
  const s = useS();
  return (
    <>
      {sel.kind === "pin" && (
        <div className="sel-card">
          <label className="field"><span>{s.pinName}</span><input value={card.pins.find(pin => pin.id === sel.id)?.label ?? ""} placeholder={s.myPin} onChange={event => card.onPin(String(sel.id), { label: event.target.value })} /></label>
          <button type="button" className="btn btn-danger btn-sm" onClick={() => card.onPin(String(sel.id), null)}>{s.deletePin}</button>
        </div>
      )}
      {sel.kind === "npc" && <NpcCard id={Number(sel.id)} zone={card.zone} />}
      {sel.kind === "dungeon" && <DungeonCard id={String(sel.id)} onFloors={card.onFloors} />}
      {sel.kind === "flight" && card.flights && <FlightCard id={Number(sel.id)} flights={card.flights} planning={card.planning} onPlan={() => card.onPlan(Number(sel.id))} onRoute={card.onRoute} />}
      {sel.kind === "transport" && <div className="sel-card"><h4>{sel.label}</h4><div className="chips"><span className="chip"><PoiBadge kind={sel.poi} size={14} />{POI[sel.poi]?.label ?? sel.poi}</span></div></div>}
      {sel.kind === "obj" && <div className="sel-card"><h4>{sel.label}</h4><div className="chips"><span className="chip"><PoiBadge kind={sel.poi} size={14} />{POI[sel.poi]?.label ?? sel.poi}</span></div></div>}
      {sel.kind === "sighting" && <div className="sel-card"><h4>{sel.label}</h4><p className="muted small">{sel.meta}</p><p className="fine-print">{s.sightingsNote}</p></div>}
      {sel.pos && sel.kind !== "sighting" && (
        <div className="btn-row travel-row">
          <button type="button" className="btn btn-ghost btn-sm" onClick={() => card.onTravel("from", { label: sel.label, u: sel.pos![0], v: sel.pos![1] })}><PoiBadge kind="origin" size={16} /> {s.fromHere}</button>
          <button type="button" className="btn btn-ghost btn-sm" onClick={() => card.onTravel("to", { label: sel.label, u: sel.pos![0], v: sel.pos![1] })}><PoiBadge kind="goal" size={16} /> {s.toHere}</button>
        </div>
      )}
    </>
  );
}

/** The panel inside the map: one thing shows its card; a stack of things is a list that opens entry by entry. */
function SelectionCard({ group, onClose, ...card }: { group: Selection[]; onClose: () => void } & CardProps) {
  const s = useS();
  const [open, setOpen] = useState(0);
  const [filter, setFilter] = useState("");
  const shown = group.filter(entry => !filter || entry.label.toLowerCase().includes(filter.toLowerCase()));
  return (
    <section className="map-panel" aria-label={s.highlighted}>
      <header><h3>{group.length > 1 ? `${group.length} ${s.pointsInZone}` : s.highlighted}</h3><button type="button" className="icon-btn" onClick={onClose} aria-label={s.clearHighlight}><Icon name="close" size={14} /></button></header>
      {group.length > 1 ? (
        <>
          {group.length > 6 && <label className="search"><Icon name="search" size={14} /><input value={filter} onChange={event => setFilter(event.target.value)} placeholder={s.searchPlaceholder} aria-label={s.search} /></label>}
          <div className="stack-accordion">
            {shown.map(entry => {
              const index = group.indexOf(entry);
              return (
                <div key={`${entry.kind}-${entry.id}`} className={`acc ${open === index ? "open" : ""}`}>
                  <button type="button" className="acc-head" aria-expanded={open === index} onClick={() => setOpen(open === index ? -1 : index)}><PoiBadge kind={entry.poi} size={20} /><span>{entry.label}</span><i aria-hidden="true">{open === index ? "−" : "+"}</i></button>
                  {open === index && <div className="acc-body"><SelectionBody sel={entry} {...card} /></div>}
                </div>
              );
            })}
          </div>
        </>
      ) : <SelectionBody sel={group[0]} {...card} />}
    </section>
  );
}

const ROLE_LABEL = (s: ReturnType<typeof useS>): Record<MapHighlight["role"], string> => ({ start: s.startsHere, end: s.endsHere, kill: s.kill, drop: s.dropsFrom, npc: s.npc, object: s.interact, vendor: s.sells, entrance: s.entranceTitle, sighting: s.sightings, from: s.from, to: s.to });
const ROLE_POI: Record<MapHighlight["role"], string> = { start: "qs", end: "qe", kill: "mob", drop: "mob", npc: "mob", object: "qe", vendor: "vendor", entrance: "dungeon", sighting: "sighting", from: "origin", to: "goal" };

function FocusCard({ resolved, loading, focus, zone, zoneName }: { resolved: Resolved | null; loading: boolean; focus: Focus; zone: string; zoneName: (key: string) => string }) {
  const s = useS();
  const labels = ROLE_LABEL(s);
  const zones = useMemo(() => {
    const counts = new Map<string, number>();
    for (const pin of resolved?.hl ?? []) counts.set(pin.zone, (counts.get(pin.zone) ?? 0) + 1);
    return [...counts].sort((a, b) => b[1] - a[1]);
  }, [resolved]);
  const roles = useMemo(() => {
    const counts = new Map<MapHighlight["role"], number>();
    for (const pin of (resolved?.hl ?? []).filter(entry => entry.zone === zone)) counts.set(pin.role, (counts.get(pin.role) ?? 0) + 1);
    return [...counts];
  }, [resolved, zone]);
  return (
    <section className="ms-block focus">
      <header><h3>{s.highlighted}</h3><a className="icon-btn" href={`#atlas/${zone}`} aria-label={s.clearHighlight}><Icon name="close" size={14} /></a></header>
      <p className="focus-title"><span className="chip small">{({ npc: s.npc, quest: s.quest, item: s.item, obj: s.interact, dungeon: s.dungeon })[focus.kind]}</span> <strong>{resolved?.title ?? (loading ? s.loading : focus.id)}</strong></p>
      {resolved?.hint && <p className="muted small">{resolved.hint}</p>}
      {roles.length > 0 && <ul className="role-legend">{roles.map(([role, count]) => <li key={role}><PoiBadge kind={ROLE_POI[role]} size={16} />{labels[role]} <span className="mono muted">{count}</span></li>)}</ul>}
      {resolved && zones.length === 0 && <p className="muted small">{s.noSpawns}</p>}
      {zones.length > 1 && <div className="chips">{zones.map(([key, count]) => <a key={key} className={`chip link ${key === zone ? "on" : ""}`} href={`#atlas/${key}?focus=${focusText(focus)}`}>{zoneName(key)} <span className="mono muted">{count}</span></a>)}</div>}
      {resolved?.href && <a className="btn btn-ghost btn-sm" href={resolved.href}>{s.openPage}</a>}
    </section>
  );
}

function RouteCard({ plan, flights, onClear }: { plan: PlanState; flights: Flights; onClear: () => void }) {
  const s = useS();
  return (
    <section className="ms-block focus">
      <header><h3>{s.fastestRoute}</h3><button type="button" className="icon-btn" onClick={onClear} aria-label={s.clearRoute}><Icon name="close" size={14} /></button></header>
      {plan === "none" ? <p className="muted small">{s.routeNone}</p> : (
        <>
          <p className="focus-title"><strong>{flights.nodes[String(plan.from)]?.n}</strong> → <strong>{flights.nodes[String(plan.to)]?.n}</strong></p>
          <div className="chips"><span className="chip mono">{clock(plan.seconds)}</span><span className="chip">{plan.legs.length} {s.hops}</span></div>
          <ol className="route-steps">{plan.legs.map((leg, i) => <li key={i}><span>{flights.nodes[String(leg.a)]?.n} → {flights.nodes[String(leg.b)]?.n}</span><span className="mono muted">{clock(leg.seconds)}</span></li>)}</ol>
        </>
      )}
    </section>
  );
}

function MapSearch({ onPick, zoneName, pins, flights }: { onPick: (action: PickAction) => void; zoneName: (key: string) => string; pins: DungeonPin[]; flights: Flights | null }) {
  const s = useS();
  const { index } = useDb();
  const world = useWorld();
  const [text, setText] = useState("");
  const needle = useDeferredValue(text.trim().toLowerCase());
  const results = useMemo(() => {
    if (!index || needle.length < 2) return null;
    const take = <T,>(rows: T[], name: (row: T) => string, limit: number) => rows.filter(row => name(row).toLowerCase().includes(needle)).sort((a, b) => Number(name(b).toLowerCase().startsWith(needle)) - Number(name(a).toLowerCase().startsWith(needle)) || name(a).length - name(b).length).slice(0, limit);
    return {
      zones: take(Object.entries(world.data?.maps ?? {}).filter(([, m]) => m.kind !== "world"), ([key]) => zoneName(key), 4),
      dungeons: take(pins, pin => pin.label, 4),
      flights: take(Object.entries(flights?.nodes ?? {}), ([, node]) => node.n, 4),
      npcs: take(index.search.npcs.filter(row => row[6] === 1), row => row[1], 5),
      quests: take(index.search.quests, row => row[1], 5),
      items: take(index.search.items, row => row[1], 5),
    };
  }, [index, world.data, needle, zoneName, pins, flights]);
  const act = (action: PickAction) => () => { onPick(action); setText(""); };
  return (
    <div className="map-search">
      <label className="search"><Icon name="search" size={16} /><input value={text} onChange={event => setText(event.target.value)} placeholder={s.searchPlaceholder} aria-label={s.search} /></label>
      {results && (
        <div className="search-pop" role="listbox">
          {results.zones.map(([key, m]) => <button key={key} type="button" onClick={act({ zone: key })}><Icon name="map" size={16} /><span>{zoneName(key)}</span><small>{m.level ? `${m.level[0]}–${m.level[1]}` : s.zone}</small></button>)}
          {results.dungeons.map(pin => <button key={pin.key} type="button" onClick={act({ fly: [[pin.u, pin.v]], select: pin.sel })}><PoiBadge kind={pin.raid ? "raid" : "dungeon"} size={20} /><span>{pin.label}</span><small>{pin.min ? `${pin.min}–${pin.max}` : ""}</small></button>)}
          {results.flights.map(([id, node]) => <button key={id} type="button" onClick={act({ fly: [[node.u, node.v]], select: { kind: "flight", id: Number(id), label: node.n, poi: "flight", meta: node.f } })}><PoiBadge kind="flight" size={20} /><span>{node.n}</span><small>{s.flights}</small></button>)}
          {results.npcs.map(row => <button key={row[0]} type="button" onClick={act({ zone: row[8] ?? WORLD, focus: `npc:${row[0]}` })}><PoiBadge kind={row[5][0] ?? "mob"} size={20} /><span>{row[1]}</span><small>{s.npc}</small></button>)}
          {results.quests.map(row => <button key={row[0]} type="button" onClick={act({ zone: row[4] ?? WORLD, focus: `quest:${row[0]}` })}><PoiBadge kind="qs" size={20} /><span>{row[1]}</span><small>{s.quest}</small></button>)}
          {results.items.map(row => <button key={row[0]} type="button" onClick={act({ zone: WORLD, focus: `item:${row[0]}` })}><span className={`dot-q ${qualityClass(row[2])}`} /><span className={qualityClass(row[2])}>{row[1]}</span><small>{s.item}</small></button>)}
          {!Object.values(results).some(list => list.length) && <p className="muted small pad">{s.noResults}</p>}
        </div>
      )}
    </div>
  );
}

function LayerDock({ layers, toggle, poiLabel, mobsLabel, activityLabel }: { layers: Record<string, boolean>; toggle: (id: string) => void; poiLabel: (id: string) => string; mobsLabel: string; activityLabel: string }) {
  const s = useS();
  const [wide, setWide] = useState(false);
  const rows: [string, string, string][] = [
    // what is about people comes first: your route, your guild and groups, your meets
    ["route", "route", s.myRoute],
    ["guild", "guild", s.guildLayer],
    ["meets", "meet", s.meetsLayer],
    ["players", "guild", s.playersLayer],
    ...["dungeon", "flight", "transport"].map(id => [id, id === "transport" ? "boat" : id, poiLabel(id)] as [string, string, string]),
    ...SERVICE_LAYERS.map(id => [id, id, poiLabel(id)] as [string, string, string]),
    ["mobs", "mob", mobsLabel],
    ["activity", "sighting", activityLabel],
    ["gather", "gather", s.gatherLayer],
    ["services", "trainer", s.servicesLayer],
  ];
  return (
    <div className={`layer-dock ${wide ? "wide" : ""}`} role="group" aria-label={s.layers}>
      <button type="button" className="dock-toggle" onClick={() => setWide(value => !value)} aria-expanded={wide} title={s.layers}><Icon name="map" size={14} />{wide && <span>{s.layers}</span>}</button>
      {rows.map(([id, poi, label]) => (
        <button key={id} type="button" className={layers[id] ? "on" : ""} aria-pressed={Boolean(layers[id])} onClick={() => toggle(id)} title={label}>
          <PoiBadge kind={poi} size={20} />{wide && <span>{label}</span>}
        </button>
      ))}
    </div>
  );
}

// ---- the page ----------------------------------------------------------------------------------------
function Inner({ route, user, signIn }: { route: string; user: User | null; signIn: string | null }) {
  const s = useS();
  const { lang } = useI18n();
  const { index } = useDb();
  const maps = useMaps();
  const world = useWorld();
  const flights = useFlights();
  const places = usePlaces();
  const floors = useFloors();
  const dungeons = useDungeons();
  const objects = useObjects();
  const { zone: requested, focus, meet: meetCode } = parseRoute(route);
  const focusKey = focusText(focus);

  const [mounted, setMounted] = useState(false);
  const [layers, setLayers] = useState(DEFAULT_LAYERS);
  const [level, setLevel] = useState<number | null>(null);
  const [selection, setSelection] = useState<Selection[] | null>(null);
  const [fullscreen, setFullscreen] = useState(false);
  const [camera, setCamera] = useState<Camera>({ n: 0, key: requested });
  const [view, setView] = useState<ViewState>({ zone: WORLD, zoom: 0 });
  const [planFrom, setPlanFrom] = useState<number | null>(null);
  const [plan, setPlan] = useState<PlanState | null>(null);
  const [floorView, setFloorView] = useState<FloorTarget | null>(null);
  const [userPins, setUserPins] = useState<UserPin[]>([]);
  const [drawings, setDrawings] = useState<Drawing[]>([]);
  const [draw, setDraw] = useState<DrawTool | null>(null);
  const [ink, setInk] = useState("#ffd24a");
  const [inkWidth, setInkWidth] = useState(4);
  const [menu, setMenu] = useState<{ u: number; v: number; x: number; y: number } | null>(null);
  const [from, setFrom] = useState<Place | null>(null);
  const [to, setTo] = useState<Place | null>(null);
  const [pickTarget, setPickTarget] = useState<"from" | "to" | null>(null);
  const [side, setSide] = useState<"A" | "H">("A");
  const [speed, setSpeed] = useState(7);
  const travel = useTravel();

  useEffect(() => {
    // one-time client-side restore: localStorage does not exist while rendering on the server
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setMounted(true);
    try {
      const stored = window.localStorage.getItem("evertally.map.layers");
      if (stored) setLayers({ ...DEFAULT_LAYERS, ...JSON.parse(stored) });
      const storedLevel = Number(window.localStorage.getItem("evertally.map.level"));
      if (storedLevel > 0) setLevel(storedLevel);
      setUserPins(JSON.parse(window.localStorage.getItem("evertally.map.pins") ?? "[]") as UserPin[]);
      setDrawings(sanitizeDrawings(JSON.parse(window.localStorage.getItem("evertally.map.drawings") ?? "[]")));
      const storedTravel = JSON.parse(window.localStorage.getItem("evertally.map.travel") ?? "{}") as { side?: string; speed?: number };
      if (storedTravel.side === "A" || storedTravel.side === "H") setSide(storedTravel.side);
      if (storedTravel.speed === 7 || storedTravel.speed === 11.2 || storedTravel.speed === 14) setSpeed(storedTravel.speed);
    } catch { /* storage unavailable */ }
  }, []);
  const toggle = (id: string) => setLayers(previous => {
    const next = { ...previous, [id]: !previous[id] };
    try { window.localStorage.setItem("evertally.map.layers", JSON.stringify(next)); } catch { /* storage unavailable */ }
    return next;
  });
  const savePins = useCallback((next: UserPin[]) => { setUserPins(next); try { window.localStorage.setItem("evertally.map.pins", JSON.stringify(next)); } catch { /* storage unavailable */ } }, []);
  const saveDrawings = useCallback((next: Drawing[]) => { setDrawings(next); try { window.localStorage.setItem("evertally.map.drawings", JSON.stringify(next)); } catch { /* storage unavailable */ } }, []);
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => { if (event.key === "Escape") { setDraw(null); setMenu(null); setPickTarget(null); } };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);
  const changeLevel = (value: string) => {
    const next = Math.min(60, Number(value.replace(/\D/g, "")) || 0) || null;
    setLevel(next);
    try { window.localStorage.setItem("evertally.map.level", String(next ?? "")); } catch { /* storage unavailable */ }
  };

  const all = useMemo(() => maps.data ?? [], [maps.data]);
  const art = useMemo(() => Object.fromEntries(all.map(entry => [entry.key, entry.image])), [all]);
  const zoneName = useCallback((key: string) => { const m = all.find(entry => entry.key === key); return m ? (lang === "cs" ? m.nameCs : m.nameEn) : key.replace(/-/g, " "); }, [all, lang]);
  const poiLabel = (id: string) => (lang === "cs" ? CS : EN)[id] ?? POI[id]?.label ?? id;
  const flyTo = useCallback((next: Omit<Camera, "n">) => setCamera(previous => ({ ...next, n: previous.n + 1 })), []);
  const mapOf = (key: string) => world.data?.maps[key];
  const people = usePeople({ user, layers, world: world.data, zoneName, flyTo });
  const services = useServiceMarkers({ layers, world: world.data, index });
  const gather = useGatherLayer({ layers, world: world.data });
  const meets = useMeets({ user, layers, world: world.data, zoneName, flyTo, guilds: people.panel.guilds, circles: people.panel.circles, profiles: people.panel.profiles });
  const allPeople = useMemo(() => [...people.people, ...meets.people], [people.people, meets.people]);
  const allTrails = useMemo(() => [...people.trails, ...gather.trails], [people.trails, gather.trails]);
  const onPerson = useCallback((id: string) => { if (id.startsWith("meet:")) meets.onPick(id); else people.onPerson(id); }, [meets, people]);
  const dungeonList = useMemo(() => (dungeons.data?.entries ?? []).map(entry => ({ key: entry.key, name: entry.name })).sort((a, b) => a.name.localeCompare(b.name)), [dungeons.data]);
  const enableLayer = useCallback((id: string) => setLayers(previous => {
    if (previous[id]) return previous;
    const next = { ...previous, [id]: true };
    try { window.localStorage.setItem("evertally.map.layers", JSON.stringify(next)); } catch { /* storage unavailable */ }
    return next;
  }), []);
  // a link `#atlas?meet=CODE` opens that meet once; without an account it just shows the sign-in prompt in the meets panel
  const [openedMeet, setOpenedMeet] = useState("");
  useEffect(() => {
    if (!meetCode || openedMeet === meetCode) return;
    // eslint-disable-next-line react-hooks/set-state-in-effect -- one-time reaction to the address
    enableLayer("meets");
    if (!user) return;
    setOpenedMeet(meetCode);
    void meets.openCode(meetCode);
  }, [meetCode, openedMeet, user, enableLayer, meets]);

  // ---- "show X on the map" ----
  const [resolvedState, setResolvedState] = useState<{ key: string; value: Resolved } | null>(null);
  useEffect(() => {
    if (!focus || !index || !objects.data || !dungeons.data) return;
    let live = true;
    const key = focusText(focus);
    resolveFocus(index, focus, objects.data, dungeons.data.entries)
      .then(value => live && setResolvedState({ key, value }))
      .catch(() => live && setResolvedState({ key, value: { title: focus.id, hl: [], lines: [] } }));
    return () => { live = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps -- `focusKey` identifies the request
  }, [focusKey, index, objects.data, dungeons.data]);
  const resolved = resolvedState?.key === focusKey ? resolvedState.value : null;
  const activeZone = useMemo(() => !resolved ? null : resolved.hl.some(pin => pin.zone === requested) ? requested : bestZone(resolved.hl), [resolved, requested]);

  // a link without the right zone lands where the answer actually is
  useEffect(() => {
    if (resolved && activeZone && activeZone !== requested) go(activeZone, focusKey, true);
  }, [resolved, activeZone, requested, focusKey]);

  const focusHighlights = useMemo<MapHighlight[]>(() => {
    if (!resolved || !world.data) return [];
    return resolved.hl.filter(pin => pin.zone === activeZone).flatMap(pin => {
      const rect = world.data!.maps[pin.zone]?.rect;
      if (!rect) return [];
      const [u, v] = zoneToWorld(rect, pin.x, pin.y);
      return [{ key: pin.key, u, v, label: pin.label, role: pin.role }];
    });
  }, [resolved, activeZone, world.data]);

  // the camera follows the link: a region, or the pins of what was asked for
  // eslint-disable-next-line react-hooks/set-state-in-effect -- camera commands follow the address; the map itself is an external system
  useEffect(() => { if (world.data && !focus) flyTo({ key: requested }); }, [requested, focusKey, world.data]); // eslint-disable-line react-hooks/exhaustive-deps -- `focus` is derived from `focusKey`
  useEffect(() => {
    if (!focus || !resolved) return;
    // eslint-disable-next-line react-hooks/set-state-in-effect -- frame the pins once their positions are known
    if (focusHighlights.length) flyTo({ points: focusHighlights.map(pin => [pin.u, pin.v] as [number, number]) });
    else flyTo({ key: requested });
  }, [resolved]); // eslint-disable-line react-hooks/exhaustive-deps -- once per resolved answer

  // ---- selection: one creature shows all its spawns ----
  const selectedNpc = !focus && selection?.length === 1 && selection[0].kind === "npc" ? Number(selection[0].id) : null;
  const npcDetail = useNpc(index, selectedNpc);
  const selectionHighlights = useMemo<MapHighlight[]>(() => {
    if (!npcDetail.data || !world.data) return [];
    const out: MapHighlight[] = [];
    for (const [zone, points] of Object.entries(npcDetail.data.sp)) {
      const rect = world.data.maps[zone]?.rect;
      if (!rect) continue;
      points.slice(0, 40).forEach(([x, y], i) => { const [u, v] = zoneToWorld(rect, x, y); out.push({ key: `sel:${zone}:${i}`, u, v, role: "npc", label: i === 0 ? npcDetail.data!.name : "" }); });
    }
    return out;
  }, [npcDetail.data, world.data]);
  const stops = useMemo<MapHighlight[]>(() => [
    ...(from ? [{ key: "journey-from", u: from.u, v: from.v, label: from.label, role: "from" as const }] : []),
    ...(to ? [{ key: "journey-to", u: to.u, v: to.v, label: to.label, role: "to" as const }] : []),
  ], [from, to]);
  const highlights = useMemo(() => [...(focus ? focusHighlights : selectionHighlights), ...stops], [focus, focusHighlights, selectionHighlights, stops]);

  // ---- journey planner: walking, flights, boats, zeppelins, lifts, the tram and portals ----
  const journey = useMemo(() => from && to && travel.data && flights.data ? planJourney(travel.data, flights.data, from, to, { side, speed }) : undefined, [from, to, travel.data, flights.data, side, speed]);
  // the walking steps follow real ground once the walk mask has arrived; until then (or when it cannot be loaded) they are straight lines
  const walk = useWalk(Boolean(journey?.steps.some(step => step.legs?.length)));
  const journeyShown = useMemo(() => (from && to && walk.data && travel.data && flights.data ? planGroundJourney(travel.data, flights.data, from, to, { side, speed }, walk.data) : journey), [journey, from, to, walk.data, travel.data, flights.data, side, speed]);
  const journeyLegs = useMemo<RouteLeg[] | null>(() => journeyShown ? journeyShown.steps.filter(step => step.points.length >= 2).map(step => ({ points: step.points, mode: step.mode, label: step.mode === "walk" ? "" : clock(step.seconds) })) : null, [journeyShown]);
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- frame the journey when it changes
    if (journey?.steps.length) flyTo({ points: journey.steps.flatMap(step => step.points) });
    else if (from && !to) flyTo({ points: [[from.u, from.v]] });
    else if (to && !from) flyTo({ points: [[to.u, to.v]] });
  }, [journey, from, to]); // eslint-disable-line react-hooks/exhaustive-deps -- fly when the endpoints or the route change
  const setTravelPlace = useCallback((role: "from" | "to", place: Place | null) => { (role === "from" ? setFrom : setTo)(place); setPickTarget(null); }, []);
  const meetTools = useMemo(() => ({
    routeTo: (place: { label: string; u: number; v: number }) => { setTravelPlace("to", place); if (people.latestPlace) setTravelPlace("from", people.latestPlace); },
    suggest: (audience: string) => {
      const everyone = people.positionsFor(audience);
      return { count: everyone.length, spots: travel.data && flights.data && everyone.length >= 2 ? suggestSpots(travel.data, flights.data, everyone, { side, speed }) : [] };
    },
    showVendors: (item: number) => { enableLayer("services"); services.showItem(item); },
    showGather: (key: string) => { enableLayer("gather"); gather.focus(key); },
  }), [people, travel.data, flights.data, side, speed, enableLayer, services, gather, setTravelPlace]);
  const changeSide = (value: "A" | "H") => { setSide(value); try { window.localStorage.setItem("evertally.map.travel", JSON.stringify({ side: value, speed })); } catch { /* storage unavailable */ } };
  const changeSpeed = (value: number) => { setSpeed(value); try { window.localStorage.setItem("evertally.map.travel", JSON.stringify({ side, speed: value })); } catch { /* storage unavailable */ } };

  // ---- community layers (zone totals and NPC sightings; never players) ----
  const activity = useApi<unknown>(layers.activity ? "/api/activity" : null);
  const atlas = useApi<{ entities: Entity[] }>(layers.sightings ? "/api/atlas" : null);
  const community = useMemo<Record<string, number>>(() => {
    const result: Record<string, number> = {};
    try { for (const entry of parseActivity(activity.data).zones) { const key = resolveMap(all, entry.mapId, "ui_map")?.key; if (key) result[key] = entry.contributors; } } catch { /* no snapshot */ }
    return result;
  }, [activity.data, all]);
  const sightings = useMemo<MapMarker[]>(() => {
    if (!atlas.data?.entities.length || !all.length || !world.data) return [];
    return worldPins(atlas.data.entities.map(safeMapEntity), all).filter(pin => !pin.reference).flatMap(pin => {
      const rect = world.data!.maps[pin.mapKey]?.rect;
      if (!rect) return [];
      const [u, v] = zoneToWorld(rect, pin.x * 100, pin.y * 100);
      return [{ key: pin.key, poi: "sighting", u, v, label: pin.entity.name, sel: { kind: "sighting", id: pin.entity.id, label: pin.entity.name, poi: "sighting", meta: `${pin.count} ${s.sightings.toLowerCase()}` } as Selection }];
    });
  }, [atlas.data, all, world.data, s.sightings]);

  // ---- dungeon & raid entrances: ours, plus OpenMap's raids and any we lack ----
  const pins = useMemo<DungeonPin[]>(() => {
    if (!world.data) return [];
    const out: DungeonPin[] = [];
    const seenMaps = new Set<number>(), names = new Set<string>();
    for (const d of dungeons.data?.entries ?? []) {
      const entrance = d.entrance;
      const rect = entrance ? world.data.maps[entrance.zone]?.rect : null;
      if (!entrance || !rect) continue;
      const [u, v] = zoneToWorld(rect, entrance.x, entrance.y);
      out.push({ key: d.key, u, v, label: d.name, raid: d.type === "raid", min: d.lvl?.[0] ?? null, max: d.lvl?.[1] ?? null, sel: { kind: "dungeon", id: d.key, label: d.name, poi: d.type === "raid" ? "raid" : "dungeon" } });
      const mapId = floors.data?.keys[d.key];
      if (mapId) seenMaps.add(mapId);
      names.add(norm(d.name));
    }
    for (const place of places.data?.instances ?? []) for (const entry of place.list) {
      if (seenMaps.has(entry.map) || names.has(norm(entry.name))) continue;
      out.push({ key: `map:${entry.map}`, u: place.u, v: place.v, label: entry.name, raid: entry.raid, min: entry.min, max: entry.max, sel: { kind: "dungeon", id: `map:${entry.map}`, label: entry.name, poi: entry.raid ? "raid" : "dungeon" } });
      seenMaps.add(entry.map);
    }
    return out;
  }, [world.data, dungeons.data, places.data, floors.data]);

  // ---- flights ----
  const routeTo = useCallback((from: number, to: number) => {
    if (!flights.data) return;
    const faction = (flights.data.nodes[String(from)]?.f || flights.data.nodes[String(to)]?.f || "") as "A" | "H" | "";
    const found = planRoute(flights.data, from, to, faction);
    setPlanFrom(null);
    if (!found) { setPlan("none"); return; }
    setPlan({ from, to, legs: found.legs, seconds: found.seconds });
    flyTo({ points: found.legs.flatMap(leg => leg.points) });
  }, [flights.data, flyTo]);
  const routeLegs = useMemo<RouteLeg[] | null>(() => plan && plan !== "none" ? plan.legs.map(leg => ({ points: leg.points, label: clock(leg.seconds) })) : null, [plan]);
  const flightFocus = selection?.[0]?.kind === "flight" ? Number(selection[0].id) : null;

  const onSelect = useCallback((group: Selection[]) => {
    const first = group[0];
    if (pickTarget && first?.pos) { setTravelPlace(pickTarget, { label: first.label, u: first.pos[0], v: first.pos[1] }); return; }
    if (planFrom != null && first?.kind === "flight") { if (Number(first.id) !== planFrom) routeTo(planFrom, Number(first.id)); return; }
    setSelection(group);
  }, [planFrom, routeTo, pickTarget, setTravelPlace]);
  const onBackground = useCallback(() => setSelection(null), []);

  const pick = (action: PickAction) => {
    if (action.select?.kind === "flight" && planFrom != null && Number(action.select.id) !== planFrom) { routeTo(planFrom, Number(action.select.id)); return; }
    if (action.fly) { flyTo({ points: action.fly }); if (action.select) setSelection([action.select]); return; }
    if (action.zone) go(action.zone, action.focus);
  };
  const reset = () => { setSelection(null); setPlan(null); setPlanFrom(null); go(WORLD); flyTo({ key: WORLD }); };

  // ---- sidebar data ----
  const viewEntry = mapOf(view.zone);
  const pointPlace = useCallback((u: number, v: number): Place => {
    const entry = world.data?.maps[view.zone];
    const local = entry && (entry.kind === "zone" || entry.kind === "city") ? [(u - entry.rect[0]) / (entry.rect[1] - entry.rect[0]) * 100, (v - entry.rect[2]) / (entry.rect[3] - entry.rect[2]) * 100] : null;
    return { label: local ? `${zoneName(view.zone)} ${local[0].toFixed(0)}, ${local[1].toFixed(0)}` : `${(u * 100).toFixed(0)}, ${(v * 100).toFixed(0)}`, u, v };
  }, [world.data, view.zone, zoneName]);
  const onPick = useCallback((u: number, v: number) => { if (pickTarget) setTravelPlace(pickTarget, pointPlace(u, v)); }, [pickTarget, pointPlace, setTravelPlace]);
  const onContext = useCallback((u: number, v: number, x: number, y: number) => { setDraw(null); setMenu({ u, v, x, y }); }, []);
  const onDraw = useCallback((drawing: Drawing) => saveDrawings([...drawings, drawing]), [drawings, saveDrawings]);
  const onPin = useCallback((id: string, change: { label: string } | null) => {
    savePins(change ? userPins.map(pin => pin.id === id ? { ...pin, ...change } : pin) : userPins.filter(pin => pin.id !== id));
    if (!change) setSelection(null);
  }, [userPins, savePins]);
  const crumbs = useMemo(() => {
    const out: string[] = [];
    for (let key: string | null = view.zone; key && world.data?.maps[key]; key = world.data.maps[key].parent) out.unshift(key);
    if (out[0] !== WORLD) out.unshift(WORLD);
    return out;
  }, [view.zone, world.data]);
  const groups = useMemo(() => {
    const entries = Object.entries(world.data?.maps ?? {}).filter(([, m]) => m.kind === "zone" || m.kind === "city");
    const sorted = (keys: string[]) => keys.sort((a, b) => zoneName(a).localeCompare(zoneName(b)));
    const by = (parent: string) => sorted(entries.filter(([, m]) => m.parent === parent).map(([key]) => key));
    const other = sorted(entries.filter(([, m]) => !m.parent || !["kalimdor", "eastern-kingdoms"].includes(m.parent)).map(([key]) => key));
    return [["kalimdor", by("kalimdor")], ["eastern-kingdoms", by("eastern-kingdoms")], ["other", other]] as const;
  }, [world.data, zoneName]);
  const inZone = viewEntry && (viewEntry.kind === "zone" || viewEntry.kind === "city");
  const zoneQuests = useMemo(() => index && inZone ? index.search.quests.filter(row => row[4] === view.zone).sort((a, b) => (a[2] != null && a[2] > 0 ? a[2] : 999) - (b[2] != null && b[2] > 0 ? b[2] : 999) || a[1].localeCompare(b[1])) : [], [index, view.zone, inZone]);
  const ready = Boolean(world.data && maps.data);

  return (
    <>
      <div className={`map-page ${fullscreen ? "is-full" : ""}`}>
        <aside className="map-side">
          <div className="ms-block head">
            <h1>{s.mapTitle}</h1>
            <MapSearch onPick={pick} zoneName={zoneName} pins={pins} flights={flights.data} />
            <div className="head-row">
              <label className="field grow"><span>{s.zone}</span>
                <select value={mapOf(requested) ? requested : WORLD} onChange={event => go(event.target.value)}>
                  <option value={WORLD}>{zoneName(WORLD)}</option>
                  {groups.map(([key, list]) => list.length > 0 && <optgroup key={key} label={key === "other" ? (lang === "cs" ? "Ostatní" : "Other") : zoneName(key)}>{key !== "other" && <option value={key}>{zoneName(key)}</option>}{list.map(entry => <option key={entry} value={entry}>{zoneName(entry)}</option>)}</optgroup>)}
                </select>
              </label>
              <label className="field level"><span>{s.myLevel}</span><input inputMode="numeric" maxLength={2} value={level ?? ""} onChange={event => changeLevel(event.target.value)} title={s.levelHint} placeholder="—" /></label>
            </div>
          </div>

          <Planner from={from} to={to} setFrom={place => setTravelPlace("from", place)} setTo={place => setTravelPlace("to", place)} pickTarget={pickTarget} setPickTarget={setPickTarget}
            side={side} setSide={changeSide} speed={speed} setSpeed={changeSpeed} journey={journeyShown} ready={Boolean(travel.data && flights.data)} zoneName={zoneName} world={world.data} pins={pins} flights={flights.data}
            onClear={() => { setFrom(null); setTo(null); setPickTarget(null); }} />
          {focus && <FocusCard resolved={resolved} loading={!resolved} focus={focus} zone={activeZone ?? requested} zoneName={zoneName} />}
          {plan && flights.data && <RouteCard plan={plan} flights={flights.data} onClear={() => setPlan(null)} />}
          {zoneQuests.length > 0 && (
            <details className="ms-block quests-block">
              <summary><h3>{s.questsInZone} <span className="count">{zoneQuests.length}</span></h3></summary>
              <ul className="mini-list">{zoneQuests.slice(0, 120).map(row => <li key={row[0]}><a href={`#atlas/${view.zone}?focus=quest:${row[0]}`} className={focus?.kind === "quest" && Number(focus.id) === row[0] ? "on" : ""}><span className="mono lvl">{row[2] != null && row[2] > 0 ? row[2] : "?"}</span><span>{row[1]}</span></a></li>)}</ul>
              {zoneQuests.length > 120 && <p className="fine-print">{s.tooMany}</p>}
            </details>
          )}
          <p className="fine-print side-note">{s.mapNote}</p>
        </aside>

        <div className={`map-stage ${fullscreen ? "is-full" : ""}`}>
          {ready && mounted ? (
            <Suspense fallback={<div className="map-loading">{s.loading}</div>}>
              <MapCanvas world={world.data!} art={art} layers={layers} level={level} places={places.data} flights={flights.data} dungeons={pins} extra={sightings}
                highlights={highlights} community={community} dim={Boolean(focus)} camera={camera} route={journeyLegs ?? routeLegs} flightFocus={flightFocus} zoneName={zoneName}
                picking={pickTarget != null} onPick={onPick} trails={allTrails} people={allPeople} onPerson={onPerson} services={services.markers} gather={gather.sets} pins={userPins} drawings={drawings} draw={draw} drawColor={ink} drawWidth={inkWidth} onContext={onContext} onDraw={onDraw} onErase={id => saveDrawings(drawings.filter(d => d.id !== id))} onSelect={onSelect} onView={setView} onBackground={() => { onBackground(); setMenu(null); }} />
            </Suspense>
          ) : <div className="map-loading">{maps.error || world.error ? s.error : s.loading}</div>}
          {selection && selection.length > 0 && (
            <SelectionCard key={selection.map(entry => `${entry.kind}${entry.id}`).join(",")} group={selection} zone={view.zone} flights={flights.data} planning={planFrom != null}
              onClose={() => { setSelection(null); setPlanFrom(null); }} onFloors={setFloorView} onTravel={setTravelPlace} pins={userPins} onPin={onPin}
              onPlan={id => setPlanFrom(previous => previous === id ? null : id)} onRoute={routeTo} />
          )}
          {menu && (
            <div className="ctx-menu" style={{ left: `max(8px, min(${menu.x}px, calc(100% - 240px)))`, top: `max(8px, min(${menu.y}px, calc(100% - 300px)))` }} role="menu" onContextMenu={event => event.preventDefault()}>
              <button type="button" role="menuitem" onClick={() => { setTravelPlace("from", pointPlace(menu.u, menu.v)); setMenu(null); }}><PoiBadge kind="origin" size={16} />{s.fromHere}</button>
              <button type="button" role="menuitem" onClick={() => { setTravelPlace("to", pointPlace(menu.u, menu.v)); setMenu(null); }}><PoiBadge kind="goal" size={16} />{s.toHere}</button>
              <button type="button" role="menuitem" onClick={() => { const place = pointPlace(menu.u, menu.v); const pin = { id: `${Date.now()}`, u: menu.u, v: menu.v, label: place.label }; savePins([...userPins, pin]); setSelection([{ kind: "pin", id: pin.id, label: pin.label, poi: "pin", pos: [pin.u, pin.v] }]); setMenu(null); }}><PoiBadge kind="pin" size={16} />{s.ctxPin}</button>
              <button type="button" role="menuitem" onClick={() => { enableLayer("meets"); meets.startDraft(menu.u, menu.v); setMenu(null); }}><PoiBadge kind="meet" size={16} />{s.meetNew}</button>
              <div className="ctx-sep" />
              <button type="button" role="menuitem" onClick={() => { setDraw("free"); setMenu(null); }}><Icon name="arrow" size={14} />{s.ctxDraw}…</button>
              <div className="ctx-sep" />
              <button type="button" role="menuitem" onClick={() => { void navigator.clipboard?.writeText(pointPlace(menu.u, menu.v).label); setMenu(null); }}><Icon name="check" size={14} />{s.ctxCopy}</button>
              {drawings.length > 0 && <button type="button" role="menuitem" onClick={() => { saveDrawings([]); setMenu(null); }}><Icon name="trash" size={14} />{s.ctxClearDrawings}</button>}
              {userPins.length > 0 && <button type="button" role="menuitem" onClick={() => { savePins([]); setSelection(null); setMenu(null); }}><Icon name="trash" size={14} />{s.ctxClearPins}</button>}
            </div>
          )}
          {draw && (
            <div className="draw-bar" role="toolbar" aria-label={s.drawing}>
              <div className="draw-group"><span>{s.drawTool}</span>
                {([["free", s.toolFree], ["line", s.toolLine], ["arrow", s.toolArrow], ["circle", s.toolCircle], ["mark", s.toolMark], ["erase", s.toolErase]] as [DrawTool, string][]).map(([tool, label]) => <button key={tool} type="button" className={draw === tool ? "on" : ""} onClick={() => setDraw(tool)}>{label}</button>)}
              </div>
              <div className="draw-group"><span>{s.ink}</span>
                {["#111111", "#e5483d", "#3b82f6", "#3fbf5f", "#ffd24a", "#ffffff"].map(color => <button key={color} type="button" className={`swatch ${ink === color ? "on" : ""}`} style={{ background: color }} aria-label={color} onClick={() => setInk(color)} />)}
              </div>
              <div className="draw-group"><span>{s.inkWidth}</span>
                {[2, 4, 8].map(width => <button key={width} type="button" className={inkWidth === width ? "on" : ""} onClick={() => setInkWidth(width)}><i style={{ display: "inline-block", width: 14, height: width, background: "currentColor", borderRadius: 4 }} /></button>)}
              </div>
              <div className="draw-group">
                <button type="button" onClick={() => saveDrawings(drawings.slice(0, -1))} disabled={!drawings.length}>{s.undo}</button>
                <button type="button" onClick={() => saveDrawings([])} disabled={!drawings.length}>{s.clear}</button>
                <button type="button" className="done" onClick={() => setDraw(null)}>{s.done}</button>
              </div>
              <span className="muted small">{s.drawingsCount}: {drawings.length} · {s.drawHint}</span>
            </div>
          )}
          <div className="map-float"><Movable id="people"><PeoplePanel panel={people.panel} signIn={signIn} onLayer={enableLayer} onRoute={(name, at) => { setTravelPlace("to", { label: name, u: at[0], v: at[1] }); if (people.latestPlace) setTravelPlace("from", people.latestPlace); flyTo({ points: [at] }); }} /></Movable><Movable id="meets"><MeetsPanel panel={meets.panel} signIn={signIn} index={index} dungeons={dungeonList} tools={meetTools} /></Movable><Movable id="gather"><GatherPanel panel={gather.panel} farmContext={{ zone: view.zone, start: people.latestPlace ? [people.latestPlace.u, people.latestPlace.v] : null, travel: travel.data, speed }} /></Movable><Movable id="services"><ServicesPanel panel={services.panel} /></Movable></div>
          <LayerDock layers={layers} toggle={toggle} poiLabel={poiLabel} mobsLabel={s.mobsLayer} activityLabel={s.activity} />
          <div className="stage-top">
            <nav className="crumbs" aria-label={s.region}>{crumbs.map((key, i) => <button key={key} type="button" className={i === crumbs.length - 1 ? "on" : ""} onClick={() => { go(key); flyTo({ key }); }}>{zoneName(key)}{i === crumbs.length - 1 && viewEntry?.level ? <i className={levelClass(viewEntry.level, level)}>{viewEntry.level[0]}–{viewEntry.level[1]}</i> : null}</button>)}</nav>
            <span className="spacer" />
            <button type="button" className="btn btn-glass btn-sm" onClick={reset}>{s.resetView}</button>
            <button type="button" className="btn btn-glass btn-sm" onClick={() => setFullscreen(value => !value)}>{fullscreen ? s.exitFullscreen : s.fullscreen}</button>
          </div>
          <p className="stage-hint">{pickTarget ? s.pickingHint : planFrom != null ? s.pickDestination : s.worldHint}</p>
          {floorView && (
            <div className="floor-overlay" role="dialog" aria-label={floorView.title}>
              <header><h3>{floorView.title}</h3><button type="button" className="icon-btn" onClick={() => setFloorView(null)} aria-label={s.cancel}><Icon name="close" size={16} /></button></header>
              <FloorMaps dungeonKey={floorView.key} mapId={floorView.mapId} />
            </div>
          )}
        </div>
      </div>
      {!fullscreen && <div className="page-column map-extra"><CommunityPackage /></div>}
    </>
  );
}

export function MapView({ route, user, signIn }: { route: string; user: User | null; signIn: string | null }) {
  return <DbProvider><Inner route={route} user={user} signIn={signIn} /></DbProvider>;
}

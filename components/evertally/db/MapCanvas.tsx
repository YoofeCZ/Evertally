"use client";
// One seamless map of Azeroth (Leaflet, CRS.Simple): the world art, the continents and every zone are placed on it by
// their real position (tools/build_map_data.py), and fade in as you zoom. Browser-only: loaded lazily from MapView.
import "leaflet/dist/leaflet.css";
import { useEffect, useRef, useState } from "react";
import type * as Leaflet from "leaflet";
import { poiMarkerHtml } from "./icons";
import { levelClass } from "./levels";
import { fetchJson, zoneToWorld, type Flights, type Places, type World, type WorldMapEntry, type ZoneData } from "./store";

type Lib = typeof Leaflet;
type Rect = [number, number, number, number];

export type Selection = { kind: "npc" | "obj" | "dungeon" | "sighting" | "flight" | "transport" | "pin"; id: number | string; label: string; poi: string; meta?: string; pos?: [number, number] };
export type MapMarker = { key: string; poi: string; u: number; v: number; label: string; sel: Selection; cls?: string };
export type MapHighlight = { key: string; u: number; v: number; label: string; role: "start" | "end" | "kill" | "drop" | "npc" | "object" | "vendor" | "entrance" | "sighting" | "from" | "to" };
export type Camera = { n: number; key?: string; points?: [number, number][] };
export type ViewState = { zone: string; zoom: number };
export type DungeonPin = { key: string; u: number; v: number; label: string; raid: boolean; min: number | null; max: number | null; sel: Selection };
export type DrawTool = "free" | "line" | "arrow" | "circle" | "mark" | "erase";
/** `zoom` is the zoom it was drawn at: strokes belong to the map and scale with it, as in OpenMap. */
export type Drawing = { id: string; kind: Exclude<DrawTool, "erase">; points: [number, number][]; color: string; width: number; zoom: number };
export type UserPin = { id: string; u: number; v: number; label: string };
export type RouteLeg = { points: [number, number][]; label: string; mode?: string };
/** A walked route (own or a guild member's) and the people on the map; both in (u, v) world units. */
export type Trail = { id: string; points: [number, number][]; color: string; opacity: number };
export type GatherSet = { key: string; label: string; color: string; pts: Float32Array };
/** `poi` swaps the initial for one of the map badges (a meet), keeping the label and tooltip. */
export type Person = { id: string; u: number; v: number; label: string; sub: string; color: string; self?: boolean; poi?: string };
export type CanvasProps = {
  world: World; art: Record<string, string>; layers: Record<string, boolean>; level: number | null;
  places: Places | null; flights: Flights | null; dungeons: DungeonPin[]; extra: MapMarker[];
  highlights: MapHighlight[]; community: Record<string, number>; dim: boolean; camera: Camera;
  route: RouteLeg[] | null; flightFocus: number | null; zoneName: (key: string) => string;
  picking: boolean; onPick: (u: number, v: number) => void;
  trails: Trail[]; people: Person[]; onPerson: (id: string) => void; services: MapMarker[]; gather: GatherSet[];
  pins: UserPin[]; drawings: Drawing[]; draw: DrawTool | null; drawColor: string; drawWidth: number; onErase: (id: string) => void; onContext: (u: number, v: number, x: number, y: number) => void; onDraw: (drawing: Drawing) => void;
  onSelect: (group: Selection[]) => void; onView: (view: ViewState) => void; onBackground: () => void;
};

const ROLE_POI: Record<MapHighlight["role"], string> = { start: "qs", end: "qe", kill: "mob", drop: "mob", npc: "mob", object: "qe", vendor: "vendor", entrance: "dungeon", sighting: "sighting", from: "origin", to: "goal" };
const DOT_ROLES = ["kill", "drop", "npc", "object", "vendor", "sighting"];
const PRIORITY: Record<string, number> = { dungeon: 60, raid: 60, flight: 50, boat: 45, zeppelin: 45, airship: 45, inn: 40, spirit: 30, bank: 30, auction: 30, qe: 20, qs: 21, vendor: 10 };
const POI_KINDS = ["qs", "qe", "vendor", "trainer", "inn", "bank", "auction", "stable", "battle", "repair", "spirit", "mail"];
const MARKER = 26;
const clamp = (value: number, lo = 0, hi = 1) => Math.min(hi, Math.max(lo, value));
const escapeHtml = (text: string) => text.replace(/[&<>"']/g, ch => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[ch]!);

type Item = { marker: Leaflet.Marker; data: MapMarker };
type Group = { layer: Leaflet.LayerGroup; markers: MapMarker[]; items: Item[]; on: boolean };
type ArtLayer = { key: string; entry: WorldMapEntry; layer: Leaflet.ImageOverlay; bounds: Leaflet.LatLngBounds; on: boolean };
type Label = { key: string; marker: Leaflet.Marker; center: Leaflet.LatLng; width: number; area: number; entry: WorldMapEntry };

class Engine {
  readonly map: Leaflet.Map;
  private W = 1002;
  private H = 668;
  private props!: CanvasProps;
  private last: Partial<CanvasProps> = {};
  private art = new Map<string, ArtLayer>();
  private labels: Label[] = [];
  private groups = new Map<string, Group>();
  private zones = new Map<string, "loading" | "ready" | "error">();
  private zoneData = new Map<string, ZoneData>();
  private sailing: Leaflet.LayerGroup | null = null;
  private highlights: Leaflet.LayerGroup;
  private hlItems: { marker: Leaflet.Marker; role: MapHighlight["role"]; label: string; u: number; v: number }[] = [];
  private mergeRadius = 16;
  private routes: Leaflet.LayerGroup;
  private drawLayer: Leaflet.LayerGroup;
  private peopleLayer: Leaflet.LayerGroup;
  private drawingsPending = false;
  private gatherLayer: Leaflet.LayerGroup;
  private gatherRenderer: Leaflet.Canvas | null = null;
  private gatherKey = "";
  private gatherVersion = 0;
  // OpenMap behaviour: while a drawing tool is active the left button draws, the right button drags the map.
  private rightPan: { x: number; y: number; moved: boolean } | null = null;
  private panMoved = false;
  private readonly rightDown = (e: MouseEvent) => { this.panMoved = false; if (e.button === 2 && this.props?.draw) this.rightPan = { x: e.clientX, y: e.clientY, moved: false }; };
  private readonly rightMove = (e: MouseEvent) => {
    const pan = this.rightPan;
    if (!pan) return;
    const dx = e.clientX - pan.x, dy = e.clientY - pan.y;
    if (!pan.moved && Math.hypot(dx, dy) < 4) return;
    pan.moved = true; this.panMoved = true;
    this.map.panBy([-dx, -dy], { animate: false });
    pan.x = e.clientX; pan.y = e.clientY;
  };
  private readonly rightUp = () => { this.rightPan = null; };
  private trailRenderer: Leaflet.Canvas | null = null;
  private drawing: { kind: Exclude<DrawTool, "erase">; points: Leaflet.LatLng[]; temp: Leaflet.LayerGroup | null } | null = null;
  private lastView = "";
  private zoneKey = "azeroth";
  private frame = 0;
  private cameraN = -1;
  private placed = false;
  private dead = false;
  private userMoved = false;
  private minimap: { size: number; yards: Record<string, number[]>; tiles: Record<string, [number, number][]> } | null = null;
  private minimapLoading = false;
  private tiles = new Map<string, { layer: Leaflet.ImageOverlay; on: boolean; bounds: Leaflet.LatLngBounds }>();
  private camera: Camera | null = null;
  private observer: ResizeObserver;

  constructor(private L: Lib, private host: HTMLElement, private coord: HTMLElement | null) {
    this.map = L.map(host, { crs: L.CRS.Simple, zoomSnap: 0.25, zoomDelta: 0.5, wheelPxPerZoomLevel: 100, minZoom: -1, maxZoom: 5.75, attributionControl: false, zoomControl: false, zoomAnimation: true, inertia: true, maxBoundsViscosity: 0.85 });
    L.control.zoom({ position: "topleft" }).addTo(this.map);
    (host as HTMLElement & { __map?: Leaflet.Map }).__map = this.map; // handy for checking the view from the console
    const terrain = this.map.createPane("terrain"); // one pane, so fading it never double-blends the seams between tiles
    terrain.style.zIndex = "450"; terrain.style.pointerEvents = "none";
    // Everything drawn as a vector (routes, your drawings, creature dots) needs a pane above the zone art: in the default
    // overlay pane the opaque art of a zone (z-index up to 106) paints over it, and the strokes vanish when you zoom in.
    const vectors = this.map.createPane("vectors");
    vectors.style.zIndex = "470";
    this.map.options.renderer = L.svg({ pane: "vectors", padding: 0.5 });
    this.routes = L.layerGroup().addTo(this.map);
    this.highlights = L.layerGroup().addTo(this.map);
    this.gatherLayer = L.layerGroup().addTo(this.map);
    this.peopleLayer = L.layerGroup().addTo(this.map);
    host.addEventListener("mousedown", this.rightDown, true);
    window.addEventListener("mousemove", this.rightMove);
    window.addEventListener("mouseup", this.rightUp);
    this.drawLayer = L.layerGroup().addTo(this.map);
    this.map.on("zoom move", () => this.schedule());
    this.map.on("zoomend moveend", () => this.refresh());
    this.map.on("zoomend", () => { if (this.props?.drawings.length) this.buildDrawings(); });
    this.map.on("mousemove", event => this.pointer(event as Leaflet.LeafletMouseEvent));
    this.map.on("mouseout", () => { if (this.coord) this.coord.textContent = ""; });
    this.map.on("contextmenu", event => { const e = event as Leaflet.LeafletMouseEvent; if (this.panMoved) return; if (this.props) this.props.onContext(e.latlng.lng / this.W, 1 - e.latlng.lat / this.H, e.containerPoint.x, e.containerPoint.y); });
    this.map.on("mousedown", event => {
      const e = event as Leaflet.LeafletMouseEvent;
      if (!this.props?.draw || e.originalEvent.button !== 0) return;
      if (this.props.draw === "erase") { this.erase(e.containerPoint); return; }
      this.drawing = { kind: this.props.draw, points: [e.latlng], temp: null };
      if (this.props.draw === "mark") this.drawEnd();
    });
    this.map.on("mouseup", () => this.drawEnd());
    this.map.on("click", event => this.click(event as Leaflet.LeafletMouseEvent));
    // the stage is laid out after the map is created: re-measure, and keep the requested framing until the user moves the map
    this.map.on("dragstart", () => { this.userMoved = true; });
    host.addEventListener("wheel", () => { this.userMoved = true; }, { passive: true });
    this.observer = new ResizeObserver(() => {
      if (this.dead || !this.placed) return;
      this.map.invalidateSize();
      if (!this.userMoved && this.camera) this.fly(this.camera, true);
    });
    this.observer.observe(host);
  }

  private ll(u: number, v: number) { return this.L.latLng((1 - v) * this.H, u * this.W); }
  private rectBounds(r: Rect) { return this.L.latLngBounds(this.ll(r[0], r[3]), this.ll(r[1], r[2])); }
  private schedule() { if (!this.frame) this.frame = requestAnimationFrame(() => { this.frame = 0; if (!this.dead) this.refresh(); }); }

  destroy() { this.host.removeEventListener("mousedown", this.rightDown, true); window.removeEventListener("mousemove", this.rightMove); window.removeEventListener("mouseup", this.rightUp); this.dead = true; this.observer.disconnect(); cancelAnimationFrame(this.frame); this.map.remove(); }

  // ---- props ------------------------------------------------------------------------------------------
  update(p: CanvasProps) {
    const prev = this.last;
    this.props = p;
    this.last = p;
    if (prev.world !== p.world || prev.art !== p.art) this.buildArt();
    if (prev.world !== p.world || prev.community !== p.community || prev.level !== p.level || prev.zoneName !== p.zoneName) this.buildLabels();
    if (prev.places !== p.places || prev.flights !== p.flights || prev.level !== p.level || prev.dungeons !== p.dungeons || prev.extra !== p.extra || prev.services !== p.services) this.buildFixed();
    if (prev.highlights !== p.highlights) this.buildHighlights();
    if (prev.pins !== p.pins) this.buildPins();
    if (prev.trails !== p.trails || prev.people !== p.people) this.buildPeople();
    if (prev.gather !== p.gather) { this.gatherVersion++; this.gatherKey = ""; }
    if (prev.drawings !== p.drawings) this.buildDrawings();
    if (p.draw) this.map.dragging.disable(); else this.map.dragging.enable();
    this.host.classList.toggle("drawing", Boolean(p.draw));
    if (prev.route !== p.route || prev.flightFocus !== p.flightFocus || prev.flights !== p.flights) this.buildRoutes();
    this.host.classList.toggle("dim", p.dim);
    this.host.classList.toggle("picking", p.picking);
    if (p.camera.n !== this.cameraN) { this.cameraN = p.camera.n; this.camera = p.camera; this.userMoved = false; this.fly(p.camera); }
    this.refresh();
  }

  // ---- art: world, continents, zones --------------------------------------------------------------------
  private buildArt() {
    const { L, map } = this;
    const { world, art } = this.props;
    for (const a of this.art.values()) a.layer.remove();
    this.art.clear();
    [this.W, this.H] = world.size;
    const union: Rect = [0, 1, 0, 1];
    for (const [key, entry] of Object.entries(world.maps)) {
      const image = art[key];
      if (!image) continue;
      const bounds = this.rectBounds(entry.rect);
      const zIndex = entry.kind === "world" ? 1 : entry.kind === "continent" ? 2 : 10 + Math.round((1 - (entry.rect[1] - entry.rect[0])) * 100);
      const layer = L.imageOverlay(image, bounds, { className: `map-art art-${entry.kind}`, zIndex, interactive: false, opacity: 0 });
      this.art.set(key, { key, entry, layer, bounds, on: false });
      if (entry.kind === "continent") { union[0] = Math.min(union[0], entry.rect[0]); union[1] = Math.max(union[1], entry.rect[1]); union[2] = Math.min(union[2], entry.rect[2]); union[3] = Math.max(union[3], entry.rect[3]); }
    }
    map.setMaxBounds(this.rectBounds(union).pad(0.08));
    map.setMinZoom(map.getBoundsZoom(this.rectBounds([0, 1, 0, 1])) - 0.35);
    if (!this.placed) { map.fitBounds(this.rectBounds([0, 1, 0, 1]), { animate: false }); this.placed = true; }
  }

  // ---- zone names (screen-space tags, biggest zones win the room) ------------------------------------------
  private buildLabels() {
    const { L } = this;
    for (const label of this.labels) label.marker.remove();
    this.labels = [];
    const { world, level, community, zoneName } = this.props;
    for (const [key, entry] of Object.entries(world.maps)) {
      if (entry.kind !== "zone" && entry.kind !== "city") continue;
      const center = this.rectBounds(entry.rect).getCenter();
      const name = zoneName(key);
      const badge = community[key];
      const html = `<span class="zone-tag ${entry.kind}"><b>${escapeHtml(name)}</b>${entry.level ? `<i class="${levelClass(entry.level, level)}">${entry.level[0]}–${entry.level[1]}</i>` : ""}${badge ? `<em>● ${badge}</em>` : ""}</span>`;
      const marker = L.marker(center, { icon: L.divIcon({ className: "zone-tag-wrap", html, iconSize: [0, 0] }), interactive: false, keyboard: false, zIndexOffset: -100 }).addTo(this.map);
      this.labels.push({ key, marker, center, width: name.length * 7 + (entry.level ? 52 : 18), area: (entry.rect[1] - entry.rect[0]) * (entry.rect[3] - entry.rect[2]), entry });
    }
  }

  private layoutLabels(z: number) {
    const placed: [number, number, number, number][] = [];
    const view = this.map.getBounds();
    const scale = 2 ** z;
    for (const label of [...this.labels].sort((a, b) => b.area - a.area)) {
      const el = label.marker.getElement();
      if (!el) continue;
      const px = (label.entry.rect[1] - label.entry.rect[0]) * this.W * scale;
      let visible = z >= 0.35 && px >= 55 && px <= 1500 && view.contains(label.center);
      if (visible) {
        const p = this.map.latLngToContainerPoint(label.center);
        const box: [number, number, number, number] = [p.x - label.width / 2, p.y - 12, p.x + label.width / 2, p.y + 12];
        visible = !placed.some(o => box[0] < o[2] && box[2] > o[0] && box[1] < o[3] && box[3] > o[1]);
        if (visible) placed.push(box);
      }
      el.style.visibility = visible ? "visible" : "hidden";
    }
  }

  // ---- markers: dungeons, flights, boats ---------------------------------------------------------------------
  private group(id: string, input: MapMarker[]) {
    const { L } = this;
    const markers = input.map(marker => marker.sel.pos ? marker : { ...marker, sel: { ...marker.sel, pos: [marker.u, marker.v] as [number, number] } });
    const layer = L.layerGroup();
    const items: Item[] = [];
    for (const marker of markers) {
      const icon = L.divIcon({ className: "poi-icon", html: poiMarkerHtml(marker.poi, MARKER, marker.cls ?? ""), iconSize: [MARKER, MARKER], iconAnchor: [MARKER / 2, MARKER / 2] });
      const item = L.marker(this.ll(marker.u, marker.v), { icon, title: marker.label, riseOnHover: true, zIndexOffset: PRIORITY[marker.poi] ?? 0 });
      item.bindTooltip(escapeHtml(marker.label), { direction: "top", offset: [0, -MARKER / 2] });
      item.on("click", event => { L.DomEvent.stopPropagation(event); this.props.onSelect(this.stack(marker)); });
      layer.addLayer(item);
      items.push({ marker: item, data: marker });
    }
    const previous = this.groups.get(id);
    if (previous?.on) this.map.removeLayer(previous.layer);
    this.groups.set(id, { layer, markers, items, on: false });
  }

  /** Everything whose badge overlaps the clicked one (clicked first, one entry per thing): crowded towns stay usable without numbered clusters. */
  private stack(marker: MapMarker): Selection[] {
    const origin = this.map.latLngToContainerPoint(this.ll(marker.u, marker.v));
    const seen = new Set([`${marker.sel.kind}:${marker.sel.id}`]);
    const out = [marker.sel];
    for (const group of this.groups.values()) {
      if (!group.on) continue;
      for (const other of group.markers) {
        const id = `${other.sel.kind}:${other.sel.id}`;
        if (seen.has(id) || this.map.latLngToContainerPoint(this.ll(other.u, other.v)).distanceTo(origin) > this.mergeRadius) continue;
        seen.add(id);
        out.push(other.sel);
      }
    }
    return out;
  }

  private buildFixed() {
    const { places, flights, dungeons, extra, services, level } = this.props;
    this.group("dungeons", dungeons.map(d => ({
      key: d.key, poi: d.raid ? "raid" : "dungeon", u: d.u, v: d.v, sel: d.sel,
      label: `${d.label}${d.min ? ` (${d.min}${d.max && d.max !== d.min ? `–${d.max}` : ""})` : ""}`,
      cls: levelClass(d.min && d.max ? [d.min, d.max] : null, level),
    })));
    this.group("flights", flights ? Object.entries(flights.nodes).map(([id, node]) => ({ key: `f${id}`, poi: "flight", u: node.u, v: node.v, label: node.n, cls: node.f === "A" ? "f-a" : node.f === "H" ? "f-h" : "", sel: { kind: "flight", id: Number(id), label: node.n, poi: "flight", meta: node.f } as Selection })) : []);
    const transports: MapMarker[] = [];
    for (const t of places?.transports ?? []) {
      const [from, to] = t.route.split(" - ");
      for (const [point, name] of [[t.a, from], [t.b, to]] as const) {
        const key = `${t.kind}:${t.route}:${point[0]}:${point[1]}`;
        if (!transports.some(m => m.key === key)) transports.push({ key, poi: t.kind, u: point[0], v: point[1], label: `${name ?? t.route} (${t.route})`, sel: { kind: "transport", id: `${t.kind}:${t.route}`, label: t.route, poi: t.kind, meta: t.kind } });
      }
    }
    this.group("transports", transports);
    this.group("extra", extra);
    this.group("services", services);

    if (this.sailing) this.map.removeLayer(this.sailing);
    this.sailing = this.L.layerGroup();
    for (const sailing of places?.sailings ?? []) {
      const color = sailing.kind === "boat" ? "#7cc4ff" : "#ffd27c";
      sailing.pieces.forEach((piece, index) => {
        this.L.polyline(piece.map(([u, v]) => this.ll(u, v)), { weight: 2, color, opacity: 0.8, dashArray: "6 6", interactive: false }).addTo(this.sailing!);
        const next = sailing.pieces[index + 1];
        if (next?.length && piece.length) {
          const a = piece[piece.length - 1], b = next[0];
          this.L.polyline([this.ll(a[0], a[1]), this.ll(b[0], b[1])], { weight: 1.5, color, opacity: 0.4, dashArray: "2 8", interactive: false }).addTo(this.sailing!);
        }
      });
    }
  }

  // ---- highlights, routes ------------------------------------------------------------------------------------
  private buildHighlights() {
    const { L } = this;
    this.highlights.clearLayers();
    this.hlItems = [];
    for (const hl of this.props.highlights) {
      if (!Number.isFinite(hl.u) || !Number.isFinite(hl.v)) continue;
      const dot = DOT_ROLES.includes(hl.role); // spawns of creatures are small dots, not badges, so they never bury the map
      const size = dot ? 14 : 30;
      const html = dot
        ? `<span class="hl-dot hl-${hl.role}"></span>`
        : `<span class="hl hl-${hl.role}" style="--hl:${size}px"><span class="hl-ring"></span>${poiMarkerHtml(ROLE_POI[hl.role], size)}<b class="hl-label">${escapeHtml(hl.label)}</b></span>`;
      const marker = L.marker(this.ll(hl.u, hl.v), { icon: L.divIcon({ className: `poi-icon hl-icon${dot ? " is-dot" : ""}`, html, iconSize: [size, size], iconAnchor: [size / 2, size / 2] }), zIndexOffset: 1000, interactive: dot, keyboard: false }).addTo(this.highlights);
      if (dot && hl.label) marker.bindTooltip(escapeHtml(hl.label), { direction: "top", offset: [0, -6] });
      this.hlItems.push({ marker, role: hl.role, label: hl.label, u: hl.u, v: hl.v });
    }
  }

  private buildRoutes() {
    const { L } = this;
    const { route, flightFocus, flights } = this.props;
    this.routes.clearLayers();
    if (flights && flightFocus != null) {
      for (const path of flights.paths) {
        if (path.a !== flightFocus && path.b !== flightFocus) continue;
        // a two-way connection is drawn once, from the selected node outward
        if (path.a === flightFocus || !flights.paths.some(o => o.a === path.b && o.b === path.a)) {
          L.polyline(path.p.map(([u, v]) => this.ll(u, v)), { weight: 3, color: "#8bd5ff", opacity: 0.85, interactive: false }).addTo(this.routes);
        }
      }
    }
    const STYLE: Record<string, { color: string; dash?: string; weight: number }> = {
      walk: { color: "#e8e6f2", dash: "3 9", weight: 4 }, flight: { color: "#6cc6ff", weight: 5 }, boat: { color: "#4aa3ff", dash: "10 8", weight: 5 },
      zeppelin: { color: "#ffb347", dash: "10 8", weight: 5 }, airship: { color: "#b69cff", dash: "10 8", weight: 5 }, lift: { color: "#b69cff", dash: "2 6", weight: 5 },
      tram: { color: "#ffd24a", dash: "2 6", weight: 5 }, portal: { color: "#c26bff", dash: "2 6", weight: 5 }, passage: { color: "#c9a56a", dash: "2 6", weight: 5 },
    };
    for (const leg of route ?? []) {
      if (leg.points.length < 2) continue;
      const points = leg.points.map(([u, v]) => this.ll(u, v));
      const style = STYLE[leg.mode ?? ""] ?? { color: "#ffd24a", dash: "10 8", weight: 5 };
      L.polyline(points, { weight: style.weight + 4, color: "#0b0b0f", opacity: 0.6, interactive: false }).addTo(this.routes);
      L.polyline(points, { weight: style.weight, color: style.color, opacity: 0.95, dashArray: style.dash, className: style.dash && style.dash.startsWith("10") ? "route-line" : undefined, interactive: false }).addTo(this.routes);
      const mid = points[Math.floor(points.length / 2)];
      if (mid && leg.label) L.marker(mid, { icon: L.divIcon({ className: "route-tag-wrap", html: `<span class="route-tag">${escapeHtml(leg.label)}</span>`, iconSize: [0, 0] }), interactive: false }).addTo(this.routes);
    }
  }

  // ---- zone points of interest (loaded when a zone is big enough on screen) ----------------------------------------
  private ensureZone(key: string) {
    if (this.zones.has(key)) return;
    this.zones.set(key, "loading");
    fetchJson<ZoneData>(`/media/db/zones/${key}.json`)
      .then(data => { if (this.dead) return; this.zoneData.set(key, data); this.zones.set(key, "ready"); this.buildZoneGroups(key); this.refresh(); })
      .catch(() => this.zones.set(key, "error"));
  }

  private zoneMarkers(key: string, poi: string): MapMarker[] {
    const data = this.zoneData.get(key);
    const entry = this.props.world.maps[key];
    if (!data || !entry) return [];
    return (data.poi[poi] ?? []).map(([id, x, y]) => {
      const [u, v] = zoneToWorld(entry.rect, x, y);
      const label = data.names[String(id)] ?? `#${id}`;
      return { key: `${key}:${poi}:${id}:${x}:${y}`, poi, u, v, label, sel: { kind: id < 0 ? "obj" : "npc", id: Math.abs(id), label, poi } as Selection };
    });
  }

  private buildZoneGroups(key: string) {
    const { L } = this;
    for (const poi of POI_KINDS) this.group(`z:${key}:${poi}`, this.zoneMarkers(key, poi));
    const data = this.zoneData.get(key);
    const entry = this.props.world.maps[key];
    if (!data || !entry) return;
    const renderer = L.canvas({ padding: 0.1, pane: "vectors" });
    const layer = L.layerGroup();
    for (const [id, x, y] of data.mobs) {
      const [u, v] = zoneToWorld(entry.rect, x, y);
      const label = data.names[String(id)] ?? `NPC #${id}`;
      const dot = L.circleMarker(this.ll(u, v), { renderer, radius: 2.6, weight: 0, fillColor: "#e2786a", fillOpacity: 0.6 });
      dot.bindTooltip(escapeHtml(label), { direction: "top", offset: [0, -4] });
      dot.on("click", event => { L.DomEvent.stopPropagation(event); this.props.onSelect([{ kind: "npc", id, label, poi: "mob" }]); });
      layer.addLayer(dot);
    }
    const previous = this.groups.get(`z:${key}:mobs`);
    if (previous?.on) this.map.removeLayer(previous.layer);
    this.groups.set(`z:${key}:mobs`, { layer, markers: [], items: [], on: false });
  }

  // ---- level of detail ----------------------------------------------------------------------------------------
  private setOn(group: Group | undefined, on: boolean) {
    if (!group || group.on === on) return;
    if (on) this.map.addLayer(group.layer); else this.map.removeLayer(group.layer);
    group.on = on;
  }

  refresh() {
    if (this.dead || !this.props || !this.placed) return;
    const { map } = this;
    const { layers, world } = this.props;
    const z = map.getZoom();
    if (!Number.isFinite(z)) return;
    if (this.drawingsPending) this.buildDrawings();
    const scale = 2 ** z;
    const view = map.getBounds();

    for (const a of this.art.values()) {
      const px = (a.entry.rect[1] - a.entry.rect[0]) * this.W * scale;
      const deep = z > 3.7 && (a.entry.kind === "world" || a.entry.kind === "continent"); // the zones and the terrain cover them by now
      const opacity = deep ? 0 : a.entry.kind === "world" ? clamp(1 - (z - 1.2) / 0.5) : a.entry.kind === "continent" ? Math.min(clamp((z - 0.05) / 0.3), clamp(1 - (z - 2.4) / 0.9)) : clamp((px - 220) / 260);
      const show = opacity > 0.01 && view.intersects(a.bounds);
      if (show && !a.on) {
        a.layer.addTo(map);
        a.on = true;
        // a continent's map is mostly sea and runs past the world art: feather only the edges that lie over other art
        const el = a.layer.getElement();
        if (el && a.entry.kind === "continent") {
          const [l, r, t, b] = a.entry.rect;
          el.style.setProperty("--fl", l > 0 ? "12%" : "0%"); el.style.setProperty("--fr", r < 1 ? "12%" : "0%");
          el.style.setProperty("--ft", t > 0 ? "12%" : "0%"); el.style.setProperty("--fb", b < 1 ? "12%" : "0%");
        }
      }
      else if (!show && a.on) { a.layer.remove(); a.on = false; }
      if (show) a.layer.setOpacity(opacity);
    }

    for (const [key, entry] of Object.entries(world.maps)) {
      if (entry.kind !== "zone" && entry.kind !== "city") continue;
      const px = (entry.rect[1] - entry.rect[0]) * this.W * scale;
      const near = view.intersects(this.rectBounds(entry.rect));
      if (near && px >= 380) this.ensureZone(key);
      if (this.zones.get(key) !== "ready") continue;
      const detail = near && px >= 460;
      for (const poi of POI_KINDS) this.setOn(this.groups.get(`z:${key}:${poi}`), detail && Boolean(layers[poi]));
      this.setOn(this.groups.get(`z:${key}:mobs`), near && px >= 700 && Boolean(layers.mobs));
    }
    this.setOn(this.groups.get("dungeons"), z >= 0.35 && Boolean(layers.dungeon));
    this.setOn(this.groups.get("flights"), z >= 0.9 && Boolean(layers.flight));
    this.setOn(this.groups.get("transports"), z >= 0.5 && Boolean(layers.transport));
    this.setOn(this.groups.get("extra"), z >= 1.5 && Boolean(layers.sightings));
    this.setOn(this.groups.get("services"), z >= 0.6 && Boolean(layers.services));
    this.updateGather(z, view);
    this.setOn(this.groups.get("pins"), true);
    if (this.sailing) {
      const want = Boolean(layers.transport);
      if (want && !map.hasLayer(this.sailing)) this.sailing.addTo(map);
      if (!want && map.hasLayer(this.sailing)) map.removeLayer(this.sailing);
    }

    this.updateMinimap(z, view);
    this.host.style.setProperty("--ms", String(clamp(0.66 + (z - 2.2) * 0.2, 0.6, 1.1)));
    this.declutter();
    this.layoutLabels(z);
    this.reportView(z);
  }

  /** The region the view is centred on: of the maps under the centre that fill enough of the screen, the one whose own centre is nearest. */
  /**
   * Badges that would sit on top of each other collapse into the most important one, which shows how many it hides (+n) and
   * names them in its tooltip. Zooming in pulls them apart again. Nothing is removed from the data, only hidden on screen.
   */
  private declutter() {
    const size = 26 * clamp(Number.parseFloat(this.host.style.getPropertyValue("--ms")) || 1, 0.6, 1.1);
    const radius = size * 0.78;
    this.mergeRadius = radius;
    const view = this.map.getBounds().pad(0.05);
    type Entry = { el: HTMLElement; x: number; y: number; rank: number; label: string; tip?: Leaflet.Marker; own: string };
    const live: Entry[] = [];
    const reset = (el: HTMLElement | undefined) => { if (el) { el.style.display = ""; el.removeAttribute("data-merged"); } };
    const HL_RANK: Record<string, number> = { from: 100, to: 100, start: 90, end: 90, drop: 60, vendor: 60, object: 55, kill: 50, entrance: 50, sighting: 45, npc: 40 };
    for (const [id, group] of this.groups) {
      if (!group.on || !id.startsWith("z:")) continue;
      for (const item of group.items) {
        const el = item.marker.getElement();
        reset(el);
        const at = this.ll(item.data.u, item.data.v);
        if (!el || !view.contains(at)) continue;
        const point = this.map.latLngToContainerPoint(at);
        item.marker.setTooltipContent(escapeHtml(item.data.label));
        live.push({ el, x: point.x, y: point.y, rank: PRIORITY[item.data.poi] ?? 0, label: item.data.label, tip: item.marker, own: item.data.label });
      }
    }
    for (const item of this.hlItems) {
      const el = item.marker.getElement();
      reset(el);
      const at = this.ll(item.u, item.v);
      if (!el || !view.contains(at)) continue;
      const point = this.map.latLngToContainerPoint(at);
      live.push({ el, x: point.x, y: point.y, rank: 1000 + (HL_RANK[item.role] ?? 0), label: item.label, own: item.label });
    }
    live.sort((a, b) => b.rank - a.rank);
    const cells = new Map<string, { entry: Entry; hidden: string[] }[]>();
    for (const entry of live) {
      const r = entry.el.classList.contains("is-dot") ? 9 : radius;
      const cx = Math.floor(entry.x / r), cy = Math.floor(entry.y / r);
      let keeper: { entry: Entry; hidden: string[] } | undefined;
      for (let dx = -1; dx <= 1 && !keeper; dx++) for (let dy = -1; dy <= 1 && !keeper; dy++) {
        keeper = cells.get(`${cx + dx},${cy + dy}`)?.find(k => Math.hypot(k.entry.x - entry.x, k.entry.y - entry.y) < r && k.entry.el.classList.contains("is-dot") === entry.el.classList.contains("is-dot") && (k.entry.rank >= 1000) === (entry.rank >= 1000));
      }
      if (keeper) {
        entry.el.style.display = "none";
        keeper.hidden.push(entry.label);
      } else {
        const list = cells.get(`${cx},${cy}`) ?? [];
        list.push({ entry, hidden: [] });
        cells.set(`${cx},${cy}`, list);
      }
    }
    for (const list of cells.values()) for (const { entry, hidden } of list) {
      // the same creature as quest giver and turn-in, or one creature's many spawns, count once
      const names = [...new Set(hidden)].filter(name => name !== entry.own);
      const total = names.length || (hidden.length && entry.rank >= 1000 ? hidden.length : 0);
      if (!total) continue;
      entry.el.setAttribute("data-merged", `+${total}`);
      entry.tip?.setTooltipContent(`${escapeHtml(entry.own)}<br><small>${names.slice(0, 6).map(escapeHtml).join(", ")}${names.length > 6 ? ", …" : ""}</small>`);
    }
  }

  // ---- the game's own terrain, tile by tile, for the closest zoom ------------------------------------------------
  private updateMinimap(z: number, view: Leaflet.LatLngBounds) {
    if (z < 2.9) { for (const t of this.tiles.values()) if (t.on) { t.layer.remove(); t.on = false; } return; }
    if (!this.minimap) {
      if (!this.minimapLoading) {
        this.minimapLoading = true;
        fetchJson<NonNullable<typeof this.minimap>>("/media/world/minimap.json").then(data => { this.minimap = data; if (!this.dead) this.refresh(); }).catch(() => { this.minimapLoading = false; });
      }
      return;
    }
    const pane = this.map.getPane("terrain");
    if (pane) pane.style.opacity = String(clamp((z - 3.0) / 0.7));
    const tile = 1600 / 3;
    for (const [continent, list] of Object.entries(this.minimap.tiles)) {
      const [au, bu, av, bv] = this.minimap.yards[continent];
      for (const [col, row] of list) {
        const key = `${continent}_${col}_${row}`;
        let entry = this.tiles.get(key);
        if (!entry) {
          const y1 = (32 - col) * tile, y0 = y1 - tile, x1 = (32 - row) * tile, x0 = x1 - tile;
          const pad = 0.00003; // half a pixel of overlap hides seams between neighbouring tiles
          const bounds = this.rectBounds([au + bu * y1 - pad, au + bu * y0 + pad, av + bv * x1 - pad, av + bv * x0 + pad]);
          const layer = this.L.imageOverlay(`/media/world/minimap/${continent}/${col}_${row}.webp`, bounds, { className: "map-art art-terrain", pane: "terrain", interactive: false });
          entry = { layer, on: false, bounds };
          this.tiles.set(key, entry);
        }
        const show = view.intersects(entry.bounds);
        if (show && !entry.on) { entry.layer.addTo(this.map); entry.on = true; }
        else if (!show && entry.on) { entry.layer.remove(); entry.on = false; }
      }
    }
  }

  private currentZone(z: number): string {
    if (z < 0.4) return "azeroth";
    const center = this.map.getCenter();
    const u = center.lng / this.W, v = 1 - center.lat / this.H;
    const width = this.map.getSize().x;
    let best = "azeroth", bestDistance = Infinity;
    for (const [key, entry] of Object.entries(this.props.world.maps)) {
      if (entry.kind === "world") continue;
      const [l, r, t, b] = entry.rect;
      if (u < l || u > r || v < t || v > b) continue;
      if ((r - l) * this.W * 2 ** z < width * (entry.kind === "continent" ? 0.45 : 0.6)) continue;
      const distance = ((u - (l + r) / 2) / (r - l)) ** 2 + ((v - (t + b) / 2) / (b - t)) ** 2 + (entry.kind === "continent" ? 1 : 0);
      if (distance < bestDistance) { best = key; bestDistance = distance; }
    }
    return best;
  }

  private reportView(z: number) {
    const zone = this.currentZone(z);
    this.zoneKey = zone;
    const text = `${zone}|${Math.round(z * 4) / 4}`;
    if (text === this.lastView) return;
    this.lastView = text;
    this.props.onView({ zone, zoom: z });
  }

  // ---- pointer ------------------------------------------------------------------------------------------------
  private pointer(event: Leaflet.LeafletMouseEvent) {
    if (!this.props) return;
    const u = event.latlng.lng / this.W, v = 1 - event.latlng.lat / this.H;
    if (this.coord) {
      // inside a zone the numbers are the zone map's own coordinates, as in the game and in guides
      const entry = this.props.world.maps[this.zoneKey];
      const local = entry && (entry.kind === "zone" || entry.kind === "city") ? [(u - entry.rect[0]) / (entry.rect[1] - entry.rect[0]) * 100, (v - entry.rect[2]) / (entry.rect[3] - entry.rect[2]) * 100] : [u * 100, v * 100];
      this.coord.textContent = local[0] >= 0 && local[0] <= 100 && local[1] >= 0 && local[1] <= 100 ? `${local[0].toFixed(1)}, ${local[1].toFixed(1)}` : "";
    }
    if (this.drawing) this.drawMove(event.latlng);
  }

  private click(event: Leaflet.LeafletMouseEvent) {
    if (this.props.picking) { this.props.onPick(event.latlng.lng / this.W, 1 - event.latlng.lat / this.H); return; }
    this.props.onBackground();
  }

  // ---- drawing ------------------------------------------------------------------------------------------------
  private shape(kind: Drawing["kind"], points: Leaflet.LatLng[], color: string, width: number, zoom: number): Leaflet.LayerGroup {
    const { L } = this;
    const group = L.layerGroup();
    // strokes that predate width and zoom still draw (see draw.ts); NaN would make Leaflet throw
    const weight = clamp((Number.isFinite(width) ? width : 4) * 2 ** (this.map.getZoom() - (Number.isFinite(zoom) ? zoom : this.map.getZoom())), 1.5, 60);
    const style = { color, weight, opacity: 0.95, interactive: false, lineCap: "round" as const, lineJoin: "round" as const };
    if (kind === "mark") {
      const size = clamp(26 * 2 ** ((this.map.getZoom() - zoom) / 2), 14, 56);
      L.marker(points[0], { icon: L.divIcon({ className: "draw-mark-wrap", html: `<span class="draw-mark" style="font-size:${size}px;color:${color}">&#9760;</span>`, iconSize: [size, size], iconAnchor: [size / 2, size / 2] }), interactive: false, keyboard: false }).addTo(group);
    } else if (kind === "circle" && points.length > 1) {
      L.circle(points[0], { ...style, radius: points[0].distanceTo(points[1]), fillColor: color, fillOpacity: 0.1 }).addTo(group);
    } else if (points.length > 1) {
      L.polyline(points, style).addTo(group);
      if (kind === "arrow") {
        const a = points[points.length - 2], b = points[points.length - 1];
        const angle = Math.atan2(b.lat - a.lat, b.lng - a.lng);
        const head = Math.max(weight * 3.2, 12) / 2 ** this.map.getZoom();
        for (const turn of [0.45, -0.45]) {
          const tip = L.latLng(b.lat - Math.sin(angle + turn) * head, b.lng - Math.cos(angle + turn) * head);
          L.polyline([b, tip], style).addTo(group);
        }
      }
    }
    return group;
  }

  private drawMove(at: Leaflet.LatLng) {
    const d = this.drawing;
    if (!d || d.kind === "mark") return;
    if (d.kind === "free") d.points.push(at); else d.points = [d.points[0], at];
    d.temp?.remove();
    d.temp = this.shape(d.kind, d.points, this.props.drawColor, this.props.drawWidth, this.map.getZoom()).addTo(this.map);
  }

  private drawEnd() {
    const d = this.drawing;
    this.drawing = null;
    if (!d) return;
    d.temp?.remove();
    if (d.points.length < 2 && d.kind !== "mark") return;
    const pts = d.kind === "free" ? d.points.filter((_, i) => i % 2 === 0 || i === d.points.length - 1) : d.points;
    this.props.onDraw({ id: `${Date.now()}-${Math.round(Math.random() * 1e6)}`, kind: d.kind, color: this.props.drawColor, width: this.props.drawWidth, zoom: this.map.getZoom(), points: pts.map(p => [p.lng / this.W, 1 - p.lat / this.H] as [number, number]) });
  }

  /** Erasing: the drawing whose line, ring or mark lies within a few pixels of the click. */
  private erase(at: Leaflet.Point) {
    let best: { id: string; d: number } | null = null;
    const px = (u: number, v: number) => this.map.latLngToContainerPoint(this.ll(u, v));
    for (const drawing of this.props.drawings) {
      const pts = drawing.points.map(([u, v]) => px(u, v));
      let d = Infinity;
      if (drawing.kind === "mark") d = pts[0].distanceTo(at);
      else if (drawing.kind === "circle" && pts.length > 1) d = Math.abs(pts[0].distanceTo(at) - pts[0].distanceTo(pts[1]));
      else for (let i = 1; i < pts.length; i++) d = Math.min(d, this.L.LineUtil.pointToSegmentDistance(at, pts[i - 1], pts[i]));
      if (d < 14 && (!best || d < best.d)) best = { id: drawing.id, d };
    }
    if (best) this.props.onErase(best.id);
  }

  private buildDrawings() {
    // Before the first view is set the zoom is NaN and an arrow head cannot be sized: try again from refresh().
    this.drawingsPending = !Number.isFinite(this.map.getZoom());
    if (this.drawingsPending) return;
    this.drawLayer.clearLayers();
    for (const drawing of this.props.drawings) this.shape(drawing.kind, drawing.points.map(([u, v]) => this.ll(u, v)), drawing.color, drawing.width, drawing.zoom).addTo(this.drawLayer);
  }

  // Resource nodes: only the ones in (and a little around) the view become canvas dots, so 30 000 listed points stay cheap.
  private updateGather(z: number, view: Leaflet.LatLngBounds) {
    const sets = this.props.gather;
    if (z < 1.6 || !sets.length) {
      if (this.gatherKey !== "off") { this.gatherLayer.clearLayers(); this.gatherKey = "off"; }
      return;
    }
    const pad = view.pad(0.25);
    const step = Math.max(1e-6, (pad.getEast() - pad.getWest()) * 0.2);
    const key = [this.gatherVersion, Math.floor(pad.getWest() / step), Math.floor(pad.getEast() / step), Math.floor(pad.getSouth() / step), Math.floor(pad.getNorth() / step), Math.round(z * 4)].join("|");
    if (key === this.gatherKey) return;
    this.gatherKey = key;
    const { L } = this;
    this.gatherRenderer ??= L.canvas({ padding: 0.3, pane: "vectors" });
    this.gatherLayer.clearLayers();
    const u0 = pad.getWest() / this.W, u1 = pad.getEast() / this.W, v0 = 1 - pad.getNorth() / this.H, v1 = 1 - pad.getSouth() / this.H;
    let inside = 0;
    for (const set of sets) for (let i = 0; i + 1 < set.pts.length; i += 2) if (set.pts[i] >= u0 && set.pts[i] <= u1 && set.pts[i + 1] >= v0 && set.pts[i + 1] <= v1) inside++;
    const stride = Math.max(1, Math.ceil(inside / 6000));
    const radius = clamp(2.5 + (z - 1.6) * 1.3, 3, 9);
    let seen = 0;
    for (const set of sets) {
      for (let i = 0; i + 1 < set.pts.length; i += 2) {
        const u = set.pts[i], v = set.pts[i + 1];
        if (u < u0 || u > u1 || v < v0 || v > v1 || seen++ % stride) continue;
        const dot = L.circleMarker(this.ll(u, v), { renderer: this.gatherRenderer, radius, weight: 1.5, color: "#0b0b0f", opacity: 0.85, fillColor: set.color, fillOpacity: 0.95 });
        dot.once("mouseover", () => { dot.bindTooltip(escapeHtml(set.label), { direction: "top", offset: [0, -4] }).openTooltip(); });
        this.gatherLayer.addLayer(dot);
      }
    }
  }

  // Routes are canvas-drawn (thousands of vertices stay cheap) and keep their screen width at every zoom.
  private buildPeople() {
    const { L } = this;
    this.peopleLayer.clearLayers();
    this.trailRenderer ??= L.canvas({ padding: 0.4, pane: "vectors" });
    for (const trail of this.props.trails) {
      if (trail.points.length < 2) continue;
      const line = trail.points.map(([u, v]) => this.ll(u, v));
      L.polyline(line, { renderer: this.trailRenderer, weight: 6, color: "#0b0b0f", opacity: Math.min(1, trail.opacity * 0.8), interactive: false, lineJoin: "round" }).addTo(this.peopleLayer);
      L.polyline(line, { renderer: this.trailRenderer, weight: 2.5, color: trail.color, opacity: trail.opacity, interactive: false, lineJoin: "round" }).addTo(this.peopleLayer);
    }
    for (const person of this.props.people) {
      if (!Number.isFinite(person.u) || !Number.isFinite(person.v)) continue;
      const initial = escapeHtml([...person.label.trim()][0]?.toUpperCase() ?? "?");
      const marker = L.marker(this.ll(person.u, person.v), {
        icon: L.divIcon({ className: "person-icon", html: person.poi ? `<span class="person badge${person.self ? " self" : ""}" style="--pc:${person.color}">${poiMarkerHtml(person.poi, 26)}</span>` : `<span class="person${person.self ? " self" : ""}" style="--pc:${person.color}"><b>${initial}</b></span>`, iconSize: [26, 26], iconAnchor: [13, 13] }),
        zIndexOffset: person.self ? 1400 : 1200, keyboard: false,
      }).addTo(this.peopleLayer);
      marker.bindTooltip(`<b>${escapeHtml(person.label)}</b>${person.sub ? `<br>${escapeHtml(person.sub)}` : ""}`, { direction: "top", offset: [0, -12] });
      marker.on("click", event => { L.DomEvent.stopPropagation(event); this.props.onPerson(person.id); });
    }
  }

  private buildPins() {
    this.group("pins", this.props.pins.map(pin => ({ key: pin.id, poi: "pin", u: pin.u, v: pin.v, label: pin.label || "Pin", sel: { kind: "pin", id: pin.id, label: pin.label || "Pin", poi: "pin" } as Selection })));
    this.refresh();
  }

  // ---- camera -------------------------------------------------------------------------------------------------
  fly(camera: Camera, instant = false) {
    const { map, L } = this;
    const entry = camera.key ? this.props.world.maps[camera.key] : null;
    let bounds: Leaflet.LatLngBounds | null = null;
    let maxZoom = 4.2;
    if (camera.points?.length) {
      bounds = L.latLngBounds(camera.points.map(([u, v]) => this.ll(u, v))).pad(0.35);
      maxZoom = camera.points.length === 1 ? 3.6 : 4.2;
    } else if (entry) {
      const [l, r, t, b] = entry.kind === "world" ? [0, 1, 0, 1] : entry.rect;
      // a continent's map is mostly sea: frame its land
      bounds = entry.kind === "continent" ? this.rectBounds([l + (r - l) * 0.1, r - (r - l) * 0.1, t + (b - t) * 0.06, b - (b - t) * 0.1]) : this.rectBounds([l, r, t, b]);
    }
    if (!bounds) return;
    if (instant || !this.lastView) map.fitBounds(bounds, { animate: false, maxZoom }); else map.flyToBounds(bounds, { maxZoom, duration: 0.9, padding: [12, 12] });
  }
}

export default function MapCanvas(props: CanvasProps) {
  const host = useRef<HTMLDivElement>(null);
  const coord = useRef<HTMLSpanElement>(null);
  const engine = useRef<Engine | null>(null);
  const latest = useRef(props);
  const [ready, setReady] = useState(0);

  useEffect(() => {
    let disposed = false;
    let created: Engine | null = null;
    void (async () => {
      const mod = await import("leaflet");
      const L = ((mod as unknown as { default?: Lib }).default ?? mod) as Lib;
      if (disposed || !host.current) return;
      created = new Engine(L, host.current, coord.current);
      engine.current = created;
      setReady(n => n + 1);
    })();
    return () => { disposed = true; engine.current = null; created?.destroy(); };
  }, []);

  useEffect(() => { latest.current = props; });

  useEffect(() => {
    const e = engine.current;
    if (!e) return;
    e.update({
      ...latest.current,
      onSelect: group => latest.current.onSelect(group),
      onView: view => latest.current.onView(view),
      onBackground: () => latest.current.onBackground(),
      onPick: (u, v) => latest.current.onPick(u, v),
      onContext: (u, v, x, y) => latest.current.onContext(u, v, x, y),
      onDraw: drawing => latest.current.onDraw(drawing),
      onErase: id => latest.current.onErase(id),
      onPerson: id => latest.current.onPerson(id),
    });
  }, [ready, props.world, props.art, props.layers, props.level, props.places, props.flights, props.dungeons, props.extra, props.highlights, props.community, props.dim, props.camera, props.route, props.flightFocus, props.zoneName, props.picking, props.pins, props.drawings, props.draw, props.drawColor, props.drawWidth, props.trails, props.people, props.services, props.gather]);

  return (
    <div className="map-canvas">
      <div ref={host} className="map-host" />
      <span ref={coord} className="map-coord mono" aria-hidden="true" />
    </div>
  );
}

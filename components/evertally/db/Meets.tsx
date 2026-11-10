"use client";
// Meets on the map: somebody picks a place and a time, chooses who may see it (a guild, a group, or anyone with the link)
// and the others answer going / maybe. The kind says what it is for: a plain meet, a dungeon or raid group, a farming
// session, a trade (what I look for, what I offer), an event, or just a note on the map.
import { useCallback, useEffect, useMemo, useState } from "react";
import { useI18n } from "@/lib/i18n";
import { api, ApiFailure } from "../api";
import type { User } from "../types";
import { Icon } from "../ui";
import { locate } from "./locate";
import type { Person } from "./MapCanvas";
import { useGatherFile, type GatherNode } from "./gatherData";
import { clockText } from "./travel";
import type { Suggestion } from "./meetspot";
import { useServices } from "./serviceData";
import { POI, PoiBadge } from "./icons";
import { qualityClass, type Index, type World } from "./store";
import { useS } from "./strings";

export const MEET_KINDS = ["meet", "group", "farm", "trade", "event", "note"] as const;
export type MeetKind = typeof MEET_KINDS[number];
type Rsvp = "going" | "maybe";
type ItemQty = { item: number; qty: number };
type MeetData = { ref?: string; roles?: { tank?: number; healer?: number; dps?: number }; wanted?: ItemQty[]; offered?: ItemQty[] };
export type Meet = {
  id: string; kind: MeetKind; title: string; note: string; host: string; mapId: number; x: number; y: number; startsAt: number | null; endsAt: number; capacity: number | null; data: MeetData;
  audience: { kind: "guild" | "circle" | "link"; id: string | null; name: string | null }; linkCode: string | null; mine: boolean; going: number; maybe: number; myRsvp: Rsvp | null;
  rsvps: { name: string; status: Rsvp; mine: boolean }[];
};
type Audience = { value: string; label: string };
export type MeetsHook = ReturnType<typeof useMeets>;

const KIND_POI: Record<MeetKind, string> = { meet: "meet", group: "meet-group", farm: "meet-farm", trade: "meet-trade", event: "meet-event", note: "meet-note" };
const fill = (text: string, values: Record<string, string | number>) => text.replace(/\{(\w+)\}/g, (_, key: string) => String(values[key] ?? ""));

function relative(seconds: number, lang: string) {
  const format = new Intl.RelativeTimeFormat(lang === "cs" ? "cs" : "en", { numeric: "auto" });
  const abs = Math.abs(seconds);
  if (abs < 3600) return format.format(Math.round(seconds / 60), "minute");
  if (abs < 86400) return format.format(Math.round(seconds / 3600), "hour");
  return format.format(Math.round(seconds / 86400), "day");
}

export function useMeets({ user, layers, world, zoneName, flyTo, guilds, circles, profiles }: {
  user: User | null; layers: Record<string, boolean>; world: World | null; zoneName: (key: string) => string; flyTo: (camera: { points: [number, number][] }) => void;
  guilds: { id: string; name: string; mine: { status: string }[] }[] | null; circles: { id: string; name: string }[] | null; profiles: { id: string; name: string | null }[];
}) {
  const s = useS();
  const { lang } = useI18n();
  const [meets, setMeets] = useState<Meet[] | null>(null);
  const [draftAt, setDraftAt] = useState<[number, number] | null>(null);
  const [picked, setPicked] = useState<string | null>(null);
  const [notice, setNotice] = useState("");
  const [failed, setFailed] = useState(false);
  const [bump, setBump] = useState(0);
  const [now, setNow] = useState(() => Math.floor(Date.now() / 1000));
  const want = Boolean(layers.meets && user);

  useEffect(() => { const timer = setInterval(() => setNow(Math.floor(Date.now() / 1000)), 30000); return () => clearInterval(timer); }, []);
  useEffect(() => {
    if (!want) return;
    let live = true;
    api<{ meets: Meet[] }>("/api/meets").then(data => { if (live) { setMeets(data.meets); setFailed(false); } }).catch(() => { if (live) setFailed(true); });
    return () => { live = false; };
  }, [want, bump]);

  const byUi = useMemo(() => new Map(Object.entries(world?.maps ?? {}).map(([key, entry]) => [entry.ui, { key, rect: entry.rect }])), [world]);
  const place = useCallback((meet: { mapId: number; x: number; y: number }): [number, number] | null => {
    const map = byUi.get(meet.mapId);
    return map ? [map.rect[0] + meet.x * (map.rect[1] - map.rect[0]), map.rect[2] + meet.y * (map.rect[3] - map.rect[2])] : null;
  }, [byUi]);
  const where = useCallback((mapId: number) => { const map = byUi.get(mapId); return map ? zoneName(map.key) : "?"; }, [byUi, zoneName]);

  const kindLabel = useCallback((kind: MeetKind) => ({ meet: s.meetKindMeet, group: s.meetKindGroup, farm: s.meetKindFarm, trade: s.meetKindTrade, event: s.meetKindEvent, note: s.meetKindNote })[kind], [s]);
  const when = useCallback((meet: Meet) => {
    if (meet.startsAt === null || meet.startsAt <= now) return now <= meet.endsAt ? s.meetNowOn : fill(s.meetEndsIn, { when: relative(meet.endsAt - now, lang) });
    return fill(s.meetStartsIn, { when: `${new Intl.DateTimeFormat(lang === "cs" ? "cs" : "en", { weekday: "short", hour: "2-digit", minute: "2-digit" }).format(new Date(meet.startsAt * 1000))} (${relative(meet.startsAt - now, lang)})` });
  }, [now, lang, s.meetNowOn, s.meetEndsIn, s.meetStartsIn]);

  const audiences = useMemo<Audience[]>(() => [
    ...(circles ?? []).map(circle => ({ value: `circle:${circle.id}`, label: fill(s.audCircle, { name: circle.name }) })),
    ...(guilds ?? []).filter(guild => guild.mine.some(row => row.status === "active")).map(guild => ({ value: `guild:${guild.id}`, label: fill(s.audGuild, { name: guild.name }) })),
    { value: "link", label: s.audLink },
  ], [circles, guilds, s.audCircle, s.audGuild, s.audLink]);

  const people = useMemo<Person[]>(() => {
    if (!layers.meets) return [];
    const out: Person[] = [];
    for (const meet of meets ?? []) {
      const at = place(meet);
      if (at) out.push({ id: `meet:${meet.id}`, u: at[0], v: at[1], label: `${kindLabel(meet.kind)}: ${meet.title}`, sub: `${fill(s.meetHostBy, { host: meet.host })} · ${when(meet)}`, color: POI[KIND_POI[meet.kind]]?.color ?? "#fff", poi: KIND_POI[meet.kind], self: meet.id === picked });
    }
    if (draftAt) out.push({ id: "meet:draft", u: draftAt[0], v: draftAt[1], label: s.meetNew, sub: s.meetPlaceHint, color: "#ffffff", poi: "meet", self: true });
    return out;
  }, [layers.meets, meets, draftAt, picked, place, kindLabel, when, s.meetHostBy, s.meetNew, s.meetPlaceHint]);

  const fail = (error: unknown) => setNotice(error instanceof ApiFailure ? error.message : s.meetLoadFailed);
  const refresh = () => setBump(value => value + 1);
  const pick = useCallback((id: string) => { setPicked(id.replace(/^meet:/, "")); }, []);

  const create = async (body: Record<string, unknown>) => {
    try {
      const data = await api<{ meet: Meet }>("/api/meets", { method: "POST", body: JSON.stringify(body) });
      setDraftAt(null); setNotice(s.meetCreated); setPicked(data.meet.id); refresh();
      return data.meet;
    } catch (error) { fail(error); return null; }
  };
  const respond = async (meet: Meet, status: Rsvp | "none") => {
    try { await api(`/api/meets/${meet.id}/rsvp`, { method: "POST", body: JSON.stringify({ status }) }); setNotice(""); refresh(); } catch (error) { fail(error); }
  };
  const cancel = async (meet: Meet) => {
    if (!window.confirm(s.meetCancelAsk)) return;
    try { await api(`/api/meets/${meet.id}`, { method: "PATCH", body: JSON.stringify({ cancel: true }) }); setNotice(""); refresh(); } catch (error) { fail(error); }
  };
  /** Opens a meet link: the meet is added to the account's list and shown. */
  const openCode = useCallback(async (code: string) => {
    try {
      const data = await api<{ meets: Meet[]; opened?: string }>(`/api/meets?code=${encodeURIComponent(code)}`);
      setMeets(data.meets);
      if (data.opened) {
        setPicked(data.opened);
        const meet = data.meets.find(entry => entry.id === data.opened);
        const at = meet && place(meet);
        if (at) flyTo({ points: [at] });
      }
      return true;
    } catch (error) { fail(error); return false; }
    // eslint-disable-next-line react-hooks/exhaustive-deps -- `fail` only sets state
  }, [place, flyTo]);

  return {
    people, onPick: pick,
    startDraft: (u: number, v: number) => setDraftAt([u, v]),
    openCode,
    panel: { user, layers, meets, draftAt, setDraftAt, picked, setPicked, notice, failed, now, audiences, profiles, world, place, where, when, kindLabel, create, respond, cancel, flyTo, refresh },
  };
}

/** "Copper Ore" and a "Copper Vein" node are the same resource: compare names without the word for the thing that holds it. */
const resourceName = (name: string) => name.toLowerCase().replace(/\b(ore|vein|deposit|mineral)\b/g, "").replace(/\s+/g, " ").trim();
const nodeFor = (itemName: string | undefined, nodes: GatherNode[] | undefined) => itemName ? nodes?.find(node => (node.type === "herb" || node.type === "ore") && resourceName(node.name) === resourceName(itemName)) : undefined;

function ItemChips({ list, index, vendors, nodes, onVendors, onGather }: {
  list: ItemQty[]; index: Index | null; vendors?: Record<string, number[]>; nodes?: GatherNode[]; onVendors?: (item: number) => void; onGather?: (key: string) => void;
}) {
  const s = useS();
  return <>{list.map(entry => {
    const name = index?.items.get(entry.item)?.[1];
    const node = nodeFor(name, nodes);
    const sold = vendors?.[String(entry.item)]?.length ?? 0;
    return (
      <span key={entry.item} className="chip-toggle item on">
        <span className={qualityClass(index?.items.get(entry.item)?.[2])}>{name ?? `#${entry.item}`}</span><em>×{entry.qty}</em>
        {sold > 0 && onVendors && <button type="button" className="mini-link" title={s.meetWhereToGet} onClick={() => onVendors(entry.item)}>{s.meetVendors} ({sold})</button>}
        {node && onGather && <button type="button" className="mini-link" title={s.meetWhereToGet} onClick={() => onGather(node.key)}>{s.meetGather}</button>}
      </span>
    );
  })}</>;
}

export type MeetTools = {
  routeTo: (place: { label: string; u: number; v: number }) => void;
  suggest: (audience: string) => { count: number; spots: Suggestion[] };
  showVendors: (item: number) => void; showGather: (key: string) => void;
};

export function MeetsPanel({ panel, signIn, index, dungeons, tools }: {
  panel: MeetsHook["panel"]; signIn: string | null; index: Index | null; dungeons: { key: string; name: string }[]; tools: MeetTools;
}) {
  const s = useS();
  const [open, setOpen] = useState(true);
  const [copied, setCopied] = useState("");
  const { picked, meets } = panel;
  const gather = useGatherFile(Boolean(panel.layers.meets));
  const services = useServices(Boolean(panel.layers.meets));
  useEffect(() => { if (picked) document.getElementById(`meet-${picked}`)?.scrollIntoView({ block: "nearest" }); }, [picked, meets]);
  if (!panel.layers.meets) return null;

  const copyLink = async (meet: Meet) => {
    if (!meet.linkCode) return;
    try { await navigator.clipboard?.writeText(`${window.location.origin}${window.location.pathname}#atlas?meet=${meet.linkCode}`); setCopied(meet.id); setTimeout(() => setCopied(""), 1500); } catch { /* clipboard unavailable */ }
  };
  // `/etally waypoint <map> <x> <y> <name>` sets a map waypoint in the game (see UI.lua)
  const copyGame = async (meet: Meet) => {
    try { await navigator.clipboard?.writeText(`/etally waypoint ${meet.mapId} ${meet.x.toFixed(4)} ${meet.y.toFixed(4)} ${meet.title.replace(/[|\n]/g, " ")}`); setCopied(`game-${meet.id}`); setTimeout(() => setCopied(""), 1500); } catch { /* clipboard unavailable */ }
  };
  const refName = (meet: Meet) => meet.kind === "group" ? dungeons.find(entry => entry.key === meet.data.ref)?.name ?? meet.data.ref : meet.kind === "farm" ? gather.data?.nodes.find(node => node.key === meet.data.ref)?.name ?? meet.data.ref : null;

  return (
    <section className={`people-panel meets-panel ${open ? "open" : ""}`} aria-label={s.meetsHeading}>
      <header>
        <h3><Icon name="map" size={15} /> {s.meetsHeading}</h3>
        <button type="button" className="icon-btn" onClick={() => setOpen(value => !value)} aria-expanded={open} aria-label={open ? "−" : "+"}>{open ? "−" : "+"}</button>
      </header>
      {open && (
        <div className="pp-body">
          {!panel.user ? (
            <div className="pp-block"><p className="muted small">{s.meetSignIn}</p>{signIn && <a className="btn btn-primary btn-sm" href={signIn}>{s.peopleSignInButton}</a>}</div>
          ) : (
            <>
              {panel.notice && <p className="pp-notice" role="status">{panel.notice}</p>}
              {panel.failed && <p className="pp-notice" role="alert">{s.meetLoadFailed}</p>}
              {panel.draftAt && <MeetForm panel={panel} index={index} dungeons={dungeons} suggest={tools.suggest} />}
              <div className="pp-block">
                {meets && meets.length === 0 && !panel.draftAt && <p className="muted small">{s.meetNone}</p>}
                {meets?.map(meet => {
                  const here = panel.place(meet);
                  const full = meet.capacity !== null && meet.going >= meet.capacity && meet.myRsvp !== "going";
                  const roles = meet.data.roles ? [["tank", s.roleTank], ["healer", s.roleHealer], ["dps", s.roleDps]].filter(([key]) => (meet.data.roles as Record<string, number | undefined>)[key]).map(([key, label]) => `${(meet.data.roles as Record<string, number>)[key]}× ${label}`).join(", ") : "";
                  return (
                    <article key={meet.id} id={`meet-${meet.id}`} className={`meet-card ${picked === meet.id ? "picked" : ""}`}>
                      <header>
                        <PoiBadge kind={`meet${meet.kind === "meet" ? "" : `-${meet.kind}`}`} size={22} />
                        <div><b>{meet.title}</b><span className="muted small">{panel.kindLabel(meet.kind)} · {fill(s.meetHostBy, { host: meet.host })}</span></div>
                      </header>
                      <p className="small">{panel.when(meet)} · {panel.where(meet.mapId)}{meet.audience.name ? ` · ${meet.audience.name}` : meet.audience.kind === "link" ? ` · ${s.audLink}` : ""}</p>
                      {refName(meet) && <p className="small"><b>{meet.kind === "group" ? s.meetDungeon : s.meetResource}:</b> {refName(meet)}</p>}
                      {roles && <p className="small">{fill(s.meetRolesNeeded, { roles })}</p>}
                      {meet.note && <p className="meet-note small">{meet.note}</p>}
                      {(meet.data.wanted?.length ?? 0) > 0 && <div className="chip-grid"><span className="muted small">{s.meetWanted}:</span><ItemChips list={meet.data.wanted!} index={index} vendors={services.data?.sells} nodes={gather.data?.nodes} onVendors={tools.showVendors} onGather={tools.showGather} /></div>}
                      {(meet.data.offered?.length ?? 0) > 0 && <div className="chip-grid"><span className="muted small">{s.meetOffered}:</span><ItemChips list={meet.data.offered!} index={index} /></div>}
                      <p className="small">{fill(s.meetPeople, { going: meet.going, maybe: meet.maybe })}{meet.capacity ? ` · ${meet.going}/${meet.capacity}` : ""}{full ? ` · ${s.meetFull}` : ""}</p>
                      {meet.rsvps.length > 0 && <p className="muted small">{meet.rsvps.slice(0, 10).map(entry => `${entry.name}${entry.status === "maybe" ? " ?" : ""}`).join(", ")}{meet.rsvps.length > 10 ? ` +${meet.rsvps.length - 10}` : ""}</p>}
                      <div className="btn-row">
                        <button type="button" className={`btn btn-sm ${meet.myRsvp === "going" ? "btn-primary" : "btn-ghost"}`} aria-pressed={meet.myRsvp === "going"} disabled={full} onClick={() => void panel.respond(meet, meet.myRsvp === "going" ? "none" : "going")}>{s.meetGoing}</button>
                        <button type="button" className={`btn btn-sm ${meet.myRsvp === "maybe" ? "btn-primary" : "btn-ghost"}`} aria-pressed={meet.myRsvp === "maybe"} onClick={() => void panel.respond(meet, meet.myRsvp === "maybe" ? "none" : "maybe")}>{s.meetMaybe}</button>
                        {!meet.mine && meet.myRsvp && <button type="button" className="btn btn-ghost btn-sm" onClick={() => void panel.respond(meet, "none")}>{s.meetNotGoing}</button>}
                      </div>
                      <div className="btn-row">
                        {here && <button type="button" className="btn btn-ghost btn-sm" onClick={() => { panel.setPicked(meet.id); panel.flyTo({ points: [here] }); }}>{s.meetShow}</button>}
                        {here && <button type="button" className="btn btn-ghost btn-sm" onClick={() => tools.routeTo({ label: meet.title, u: here[0], v: here[1] })}>{s.meetRoute}</button>}
                        <button type="button" className="btn btn-ghost btn-sm" title={s.meetCopyGameNote} onClick={() => void copyGame(meet)}>{copied === `game-${meet.id}` ? s.groupCopied : s.meetCopyGame}</button>
                        {meet.linkCode && <button type="button" className="btn btn-ghost btn-sm" onClick={() => void copyLink(meet)}>{copied === meet.id ? s.groupCopied : s.meetCopyLink}</button>}
                        {meet.mine && <button type="button" className="btn btn-ghost btn-sm danger" onClick={() => void panel.cancel(meet)}>{s.meetCancel}</button>}
                      </div>
                      {meet.linkCode && <p className="fine-print">{s.meetLinkNote}</p>}
                    </article>
                  );
                })}
              </div>
            </>
          )}
        </div>
      )}
    </section>
  );
}

const WHEN_MINUTES: Record<string, number> = { "15": 15, "30": 30, "60": 60, "120": 120 };

function MeetForm({ panel, index, dungeons, suggest }: { panel: MeetsHook["panel"]; index: Index | null; dungeons: { key: string; name: string }[]; suggest: MeetTools["suggest"] }) {
  const s = useS();
  const [kind, setKind] = useState<MeetKind>("meet");
  const [title, setTitle] = useState("");
  const [note, setNote] = useState("");
  const [whenMode, setWhenMode] = useState("now");
  const [custom, setCustom] = useState("");
  const [lasts, setLasts] = useState(120);
  const [audience, setAudience] = useState(panel.audiences[0]?.value ?? "link");
  const [capacity, setCapacity] = useState("");
  const [host, setHost] = useState("");
  const [ref, setRef] = useState("");
  const [roles, setRoles] = useState({ tank: "", healer: "", dps: "" });
  const [wanted, setWanted] = useState<ItemQty[]>([]);
  const [offered, setOffered] = useState<ItemQty[]>([]);
  const [query, setQuery] = useState("");
  const [target, setTarget] = useState<"wanted" | "offered">("wanted");
  const [spots, setSpots] = useState<Suggestion[] | null>(null);
  const gather = useGatherFile(kind === "farm");
  const located = panel.draftAt && panel.world ? locate(panel.world, panel.draftAt[0], panel.draftAt[1]) : null;
  const audienceValue = panel.audiences.some(entry => entry.value === audience) ? audience : panel.audiences[0]?.value ?? "link";

  const suggestions = useMemo(() => {
    const needle = query.trim().toLowerCase();
    if (needle.length < 2 || !index) return [];
    const found: { id: number; name: string; rank: number }[] = [];
    for (const row of index.search.items) {
      const at = row[1].toLowerCase().indexOf(needle);
      if (at >= 0) found.push({ id: row[0], name: row[1], rank: at === 0 ? 0 : 1 });
      if (found.length > 200) break;
    }
    return found.sort((a, b) => a.rank - b.rank || a.name.localeCompare(b.name)).slice(0, 8);
  }, [query, index]);

  const addItem = (id: number) => {
    const set = target === "wanted" ? setWanted : setOffered;
    const list = target === "wanted" ? wanted : offered;
    if (!list.some(entry => entry.item === id) && list.length < 12) set([...list, { item: id, qty: 1 }]);
    setQuery("");
  };
  const itemList = (list: ItemQty[], set: (next: ItemQty[]) => void) => list.map(entry => (
    <span key={entry.item} className="chip-toggle item on">
      <span className={qualityClass(index?.items.get(entry.item)?.[2])}>{index?.items.get(entry.item)?.[1] ?? `#${entry.item}`}</span>
      <input type="number" min={1} max={1000} value={entry.qty} aria-label="×" onChange={event => set(list.map(other => other.item === entry.item ? { ...other, qty: Math.min(1000, Math.max(1, Number(event.target.value) || 1)) } : other))} />
      <button type="button" aria-label={s.servicesClear} onClick={() => set(list.filter(other => other.item !== entry.item))}>×</button>
    </span>
  ));

  const submit = async () => {
    if (!located || !title.trim()) return;
    const now = panel.now; // the panel's own clock, refreshed every 30 s: plenty for “in 15 minutes”
    const startsAt = whenMode === "now" ? null : whenMode === "custom" ? Math.floor(new Date(custom).getTime() / 1000) : now + WHEN_MINUTES[whenMode] * 60;
    if (startsAt !== null && !Number.isFinite(startsAt)) return;
    const [audienceKind, audienceId] = audienceValue.split(":");
    const num = (value: string) => Math.min(40, Math.max(0, Number(value) || 0));
    const data: MeetData = {
      ...(kind === "group" || kind === "farm" ? (ref ? { ref } : {}) : {}),
      ...(kind === "group" && (roles.tank || roles.healer || roles.dps) ? { roles: { tank: num(roles.tank), healer: num(roles.healer), dps: num(roles.dps) } } : {}),
      ...(kind === "trade" && wanted.length ? { wanted } : {}), ...(kind === "trade" && offered.length ? { offered } : {}),
    };
    await panel.create({
      kind, title: title.trim(), note: note.trim(), mapId: located.mapId, x: located.x, y: located.y, startsAt, durationMin: lasts,
      audience: audienceKind === "link" ? { kind: "link" } : { kind: audienceKind, id: audienceId }, capacity: Number(capacity) >= 2 ? Math.min(40, Number(capacity)) : null,
      ...(host.trim() ? { host: host.trim() } : panel.profiles[0] ? { profileId: panel.profiles[0].id } : {}), data,
    });
  };

  return (
    <div className="pp-block meet-form">
      <h4>{s.meetNew}</h4>
      <p className="muted small">{s.meetPlace}: {located ? `${panel.where(located.mapId)} (${Math.round(located.x * 100)}, ${Math.round(located.y * 100)})` : "?"} · {s.meetPlaceHint}</p>
      <div className="chip-grid" role="group" aria-label={s.meetKindMeet}>
        {MEET_KINDS.map(entry => (
          <button key={entry} type="button" className={`chip-toggle ${kind === entry ? "on" : ""}`} aria-pressed={kind === entry} onClick={() => setKind(entry)}>
            <PoiBadge kind={KIND_POI[entry]} size={16} />{panel.kindLabel(entry)}
          </button>
        ))}
      </div>
      <p className="fine-print">{s.meetKindHelp}</p>
      <input value={title} onChange={event => setTitle(event.target.value)} placeholder={s.meetTitle} maxLength={80} aria-label={s.meetTitle} />
      {kind === "group" && (
        <>
          <label className="pp-controls col">{s.meetDungeon}
            <select value={ref} onChange={event => setRef(event.target.value)}><option value="">—</option>{dungeons.map(entry => <option key={entry.key} value={entry.key}>{entry.name}</option>)}</select>
          </label>
          <div className="pp-controls">{s.meetRoles}
            {([["tank", s.roleTank], ["healer", s.roleHealer], ["dps", s.roleDps]] as const).map(([key, label]) => (
              <label key={key} className="mini">{label}<input type="number" min={0} max={40} value={roles[key]} onChange={event => setRoles({ ...roles, [key]: event.target.value })} /></label>
            ))}
          </div>
        </>
      )}
      {kind === "farm" && (
        <label className="pp-controls col">{s.meetResource}
          <select value={ref} onChange={event => setRef(event.target.value)}><option value="">—</option>{gather.data?.nodes.map(node => <option key={node.key} value={node.key}>{node.name}</option>)}</select>
        </label>
      )}
      {kind === "trade" && (
        <div className="meet-items">
          <div className="seg" role="group">
            <button type="button" className={target === "wanted" ? "on" : ""} aria-pressed={target === "wanted"} onClick={() => setTarget("wanted")}>{s.meetWanted}</button>
            <button type="button" className={target === "offered" ? "on" : ""} aria-pressed={target === "offered"} onClick={() => setTarget("offered")}>{s.meetOffered}</button>
          </div>
          <label className="search"><Icon name="search" size={14} /><input value={query} onChange={event => setQuery(event.target.value)} placeholder={s.meetItemSearch} aria-label={s.meetItemSearch} /></label>
          {suggestions.length > 0 && <ul className="svc-suggest">{suggestions.map(entry => <li key={entry.id}><button type="button" onClick={() => addItem(entry.id)}><span className={qualityClass(index?.items.get(entry.id)?.[2])}>{entry.name}</span></button></li>)}</ul>}
          {wanted.length > 0 && <div className="chip-grid"><span className="muted small">{s.meetWanted}:</span>{itemList(wanted, setWanted)}</div>}
          {offered.length > 0 && <div className="chip-grid"><span className="muted small">{s.meetOffered}:</span>{itemList(offered, setOffered)}</div>}
        </div>
      )}
      <div className="pp-block flat">
        <button type="button" className="btn btn-ghost btn-sm" disabled={audienceValue === "link"} onClick={() => setSpots(suggest(audienceValue).spots)}>{s.meetSuggest}</button>
        {audienceValue === "link" && <p className="fine-print">{s.meetSuggestNeed}</p>}
        {spots && spots.length === 0 && <p className="muted small">{s.meetSuggestNeed}</p>}
        {spots && spots.length > 0 && (
          <>
            <p className="muted small">{s.meetSuggestTitle}</p>
            {spots.map(spot => (
              <button key={spot.id} type="button" className="spot" onClick={() => { panel.setDraftAt([spot.u, spot.v]); setSpots(null); }} title={s.meetSuggestUse}>
                <b>{spot.label}</b><span>{fill(s.meetSuggestWorst, { time: clockText(spot.worst) })} · {spot.times.map(entry => `${entry.name} ${clockText(entry.seconds)}`).join(", ")}</span>
              </button>
            ))}
            <p className="fine-print">{s.meetSuggestNote}</p>
          </>
        )}
      </div>
      <textarea value={note} onChange={event => setNote(event.target.value)} placeholder={s.meetNote} maxLength={400} rows={2} aria-label={s.meetNote} />
      <div className="pp-controls">
        <label>{s.meetWhen}
          <select value={whenMode} onChange={event => setWhenMode(event.target.value)}>
            <option value="now">{s.whenNow}</option><option value="15">{s.when15}</option><option value="30">{s.when30}</option><option value="60">{s.when60}</option><option value="120">{s.when120}</option><option value="custom">{s.whenCustom}</option>
          </select>
        </label>
        {whenMode === "custom" && <input type="datetime-local" value={custom} onChange={event => setCustom(event.target.value)} aria-label={s.meetWhen} />}
        <label>{s.meetLasts}
          <select value={lasts} onChange={event => setLasts(Number(event.target.value))}>
            <option value={30}>{s.lasts30}</option><option value={60}>{s.lasts60}</option><option value={120}>{s.lasts120}</option><option value={240}>{s.lasts240}</option><option value={480}>{s.lasts480}</option>
          </select>
        </label>
      </div>
      <div className="pp-controls">
        <label>{s.meetAudience}
          <select value={audienceValue} onChange={event => setAudience(event.target.value)}>{panel.audiences.map(entry => <option key={entry.value} value={entry.value}>{entry.label}</option>)}</select>
        </label>
        <label className="mini">{s.meetCapacity}<input type="number" min={2} max={40} value={capacity} onChange={event => setCapacity(event.target.value)} placeholder="—" /></label>
      </div>
      <label className="pp-controls col">{s.meetHost}
        <input value={host} onChange={event => setHost(event.target.value)} placeholder={panel.profiles[0]?.name ?? ""} maxLength={40} />
      </label>
      <div className="btn-row">
        <button type="button" className="btn btn-primary btn-sm" disabled={!located || !title.trim()} onClick={() => void submit()}>{s.meetCreate}</button>
        <button type="button" className="btn btn-ghost btn-sm" onClick={() => panel.setDraftAt(null)}>{s.meetCancelForm}</button>
      </div>
    </div>
  );
}

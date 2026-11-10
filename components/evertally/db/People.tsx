"use client";
// "My route" and "Guild" on the map: the route the signed-in account walked, and the guild members who confirmed the
// guild on this page. Everything comes from /api/track and /api/guild; the server decides who may see what
// (lib/people.ts), this file only draws it and lets people change their choice.
import { useCallback, useEffect, useMemo, useState } from "react";
import { useI18n } from "@/lib/i18n";
import { api, ApiFailure } from "../api";
import { CLASSES } from "../data";
import type { User } from "../types";
import { Icon } from "../ui";
import type { Person, Trail } from "./MapCanvas";
import { zoneToWorld, type World } from "./store";
import { useS } from "./strings";

type Point = [seconds: number, x: number, y: number];
type Path = { id: string; profileId: string | null; mapId: number; startedAt: number; endedAt: number; points: Point[] };
type Character = { id: string; name: string | null; realm: string | null; classId: number | null; level: number | null };
type MyTrail = { paths: Path[]; truncated: boolean; characters: Character[] };
type Share = "off" | "last" | "trail";
type Member = { name: string; rankIndex: number; level: number | null; classId: number | null; onMap: boolean; share: Share | null; profileId: string | null; position: { mapId: number; x: number; y: number; at: number } | null };
type Guild = { id: string; name: string; realm: string; ownerName: string | null; rosterAt: number | null; rosterSize: number; mine: { profileId: string; name: string; status: string; share: Share; eligible: boolean }[]; members: Member[] | null };
type Hours = 24 | 168 | 720;
type CircleMember = { profileId: string; name: string; classId: number | null; level: number | null; share: Share; isMe: boolean; isOwner: boolean; position: { mapId: number; x: number; y: number; at: number } | null };
type Circle = { id: string; name: string; isOwner: boolean; inviteCode: string | null; mine: { profileId: string; name: string; share: Share }; members: CircleMember[] };
type Profile = { id: string; name: string | null; classId: number | null; level: number | null };
export type GroupAction = "share" | "character" | "leave" | "rotate" | "close" | "kick";

const CLASS_COLOR: Record<number, string> = { 1: "#c79c6e", 2: "#f58cba", 3: "#abd473", 4: "#fff569", 5: "#ffffff", 6: "#c41f3b", 7: "#0070de", 8: "#69ccf0", 9: "#9482c9", 10: "#00ff96", 11: "#ff7d0a", 12: "#a330c9", 13: "#33937f" };
const ROUTE_COLORS = ["#ffd24a", "#7ee081", "#6cb8ff", "#ff8f6b", "#c79bff", "#ff6bb5"];
const MEMBER_COLOR = "#cfd3dc";
const MAX_VERTICES = 40000;
const classColor = (classId: number | null) => (classId ? CLASS_COLOR[classId] : undefined) ?? MEMBER_COLOR;

function ago(then: number, now: number, lang: string, justNow: string) {
  const delta = Math.max(0, now - then);
  if (delta < 90) return justNow;
  const format = new Intl.RelativeTimeFormat(lang === "cs" ? "cs" : "en", { numeric: "auto" });
  if (delta < 3600) return format.format(-Math.round(delta / 60), "minute");
  if (delta < 86400) return format.format(-Math.round(delta / 3600), "hour");
  return format.format(-Math.round(delta / 86400), "day");
}
const fill = (text: string, values: Record<string, string | number>) => text.replace(/\{(\w+)\}/g, (_, key: string) => String(values[key] ?? ""));

export type PeopleHook = ReturnType<typeof usePeople>;

export function usePeople({ user, layers, world, zoneName, flyTo }: {
  user: User | null; layers: Record<string, boolean>; world: World | null; zoneName: (key: string) => string;
  flyTo: (camera: { points: [number, number][] }) => void;
}) {
  const s = useS();
  const { lang } = useI18n();
  const [hours, setHours] = useState<Hours>(24);
  const [character, setCharacter] = useState("");
  const [route, setRoute] = useState<MyTrail | null>(null);
  const [guilds, setGuilds] = useState<Guild[] | null>(null);
  const [circles, setCircles] = useState<Circle[] | null>(null);
  const [profiles, setProfiles] = useState<Profile[]>([]);
  const [failed, setFailed] = useState(false);
  const [notice, setNotice] = useState("");
  const [memberTrails, setMemberTrails] = useState<Record<string, Path[]>>({});
  const [picked, setPicked] = useState<string | null>(null);
  const [bump, setBump] = useState(0);
  const [now, setNow] = useState(() => Math.floor(Date.now() / 1000));
  const signedIn = Boolean(user);
  // meets need your last position too (route me there, a fair meeting place), even when the route itself is not drawn
  const wantRoute = Boolean(layers.route || layers.meets) && signedIn;
  // the meets form also needs to know which guilds and groups you are in
  const wantGuild = Boolean(layers.guild || layers.meets) && signedIn;

  useEffect(() => { const timer = setInterval(() => setNow(Math.floor(Date.now() / 1000)), 30000); return () => clearInterval(timer); }, []);
  useEffect(() => {
    if (!wantRoute) return;
    let live = true;
    api<MyTrail>(`/api/track?hours=${hours}`).then(data => { if (live) { setRoute(data); setFailed(false); } }).catch(() => { if (live) setFailed(true); });
    return () => { live = false; };
  }, [wantRoute, hours, bump]);
  useEffect(() => {
    if (!wantGuild) return;
    let live = true;
    api<{ guilds: Guild[]; circles?: Circle[] }>("/api/guild").then(data => { if (live) { setGuilds(data.guilds); setCircles(data.circles ?? []); setFailed(false); } }).catch(() => { if (live) setFailed(true); });
    return () => { live = false; };
  }, [wantGuild, bump]);
  useEffect(() => {
    if (!wantGuild) return;
    let live = true;
    api<{ profiles: Profile[] }>("/api/me").then(data => { if (live) setProfiles(data.profiles ?? []); }).catch(() => { /* the lists above report the failure */ });
    return () => { live = false; };
  }, [wantGuild]);

  const byUi = useMemo(() => new Map(Object.entries(world?.maps ?? {}).map(([key, entry]) => [entry.ui, { key, rect: entry.rect }])), [world]);
  const place = useCallback((mapId: number, x: number, y: number): [number, number] | null => {
    const map = byUi.get(mapId);
    return map ? zoneToWorld(map.rect, x * 100, y * 100) : null;
  }, [byUi]);
  const where = useCallback((mapId: number) => { const map = byUi.get(mapId); return map ? zoneName(map.key) : "?"; }, [byUi, zoneName]);

  const shownPaths = useMemo(() => (layers.route && route ? route.paths.filter(path => !character || path.profileId === character) : []), [layers.route, route, character]);
  const lines = useCallback((paths: Path[], colorOf: (path: Path) => string, newest: number, span: number): Trail[] => {
    const total = paths.reduce((sum, path) => sum + path.points.length, 0);
    const step = Math.max(1, Math.ceil(total / MAX_VERTICES));
    return paths.map(path => {
      const points: [number, number][] = [];
      path.points.forEach((point, index) => {
        if (index % step && index !== path.points.length - 1) return;
        const at = place(path.mapId, point[1], point[2]);
        if (at) points.push(at);
      });
      // older stretches fade, so a long period still reads as "most recent first"
      return { id: path.id, points, color: colorOf(path), opacity: Math.max(0.35, 1 - ((newest - path.endedAt) / span) * 0.65) };
    });
  }, [place]);

  const trails = useMemo<Trail[]>(() => {
    const out: Trail[] = [];
    if (shownPaths.length && route) {
      const ids = route.characters.map(entry => entry.id);
      const newest = Math.max(...shownPaths.map(path => path.endedAt));
      out.push(...lines(shownPaths, path => ROUTE_COLORS[Math.max(0, ids.indexOf(path.profileId ?? "")) % ROUTE_COLORS.length], newest, hours * 3600));
    }
    if (layers.guild) for (const [profileId, paths] of Object.entries(memberTrails)) {
      const member = [...(guilds?.flatMap(guild => guild.members ?? []) ?? []), ...(circles?.flatMap(circle => circle.members) ?? [])].find(entry => entry.profileId === profileId);
      if (paths.length) out.push(...lines(paths, () => classColor(member?.classId ?? null), Math.max(...paths.map(path => path.endedAt)), 72 * 3600));
    }
    return out;
  }, [shownPaths, route, layers.guild, memberTrails, guilds, circles, lines, hours]);

  const people = useMemo<Person[]>(() => {
    const out: Person[] = [];
    if (shownPaths.length && route) {
      const seen = new Set<string>();
      for (const path of shownPaths) {
        const key = path.profileId ?? "";
        if (seen.has(key)) continue;
        seen.add(key);
        const last = path.points[path.points.length - 1];
        const at = place(path.mapId, last[1], last[2]);
        const who = route.characters.find(entry => entry.id === path.profileId);
        if (at) out.push({ id: `me:${key}`, u: at[0], v: at[1], label: who?.name ?? s.guildYou, sub: `${where(path.mapId)} · ${ago(path.endedAt, now, lang, s.agoNow)}`, color: classColor(who?.classId ?? null), self: true });
      }
    }
    const seen = new Set<string>();
    const add = (profileId: string, position: { mapId: number; x: number; y: number; at: number }, name: string, classId: number | null, prefix: string) => {
      if (seen.has(profileId)) return;
      const at = place(position.mapId, position.x, position.y);
      if (!at) return;
      seen.add(profileId);
      out.push({ id: `${prefix}:${profileId}`, u: at[0], v: at[1], label: name, sub: `${where(position.mapId)} · ${ago(position.at, now, lang, s.agoNow)}`, color: classColor(classId) });
    };
    if (layers.guild) {
      for (const guild of guilds ?? []) for (const member of guild.members ?? []) if (member.position && member.profileId) add(member.profileId, member.position, member.name, member.classId, "g");
      for (const circle of circles ?? []) for (const member of circle.members) if (member.position && !member.isMe) add(member.profileId, member.position, member.name, member.classId, "c");
    }
    return out;
  }, [shownPaths, route, layers.guild, guilds, circles, place, where, now, lang, s.agoNow, s.guildYou]);

  const fail = (error: unknown) => setNotice(error instanceof ApiFailure ? error.message : s.routeLoadFailed);
  const refresh = () => setBump(value => value + 1);
  const eraseRoute = async () => {
    if (!window.confirm(s.routeEraseAsk)) return;
    try { await api("/api/track", { method: "DELETE" }); setRoute(previous => previous && { ...previous, paths: [] }); setNotice(s.routeErased); } catch (error) { fail(error); }
  };
  const membership = async (guild: Guild, profileId: string, action: "join" | "share" | "leave", share?: Share) => {
    try { await api(`/api/guild/${guild.id}`, { method: "POST", body: JSON.stringify({ profileId, action, share }) }); setNotice(""); refresh(); } catch (error) { fail(error); }
  };
  const toggleMemberRoute = async (guild: Guild, profileId: string) => {
    if (memberTrails[profileId]) { setMemberTrails(previous => Object.fromEntries(Object.entries(previous).filter(([key]) => key !== profileId))); return; }
    try {
      const data = await api<{ paths: Path[] }>(`/api/guild/${guild.id}/trail?profile=${encodeURIComponent(profileId)}&hours=72`);
      setMemberTrails(previous => ({ ...previous, [profileId]: data.paths }));
      setNotice("");
    } catch (error) { fail(error); }
  };
  const createGroup = async (name: string, profileId: string, share: Share) => {
    try { await api("/api/circles", { method: "POST", body: JSON.stringify({ name, profileId, share }) }); setNotice(""); refresh(); return true; } catch (error) { fail(error); return false; }
  };
  const joinGroup = async (code: string, profileId: string, share: Share) => {
    try { await api("/api/circles/join", { method: "POST", body: JSON.stringify({ code, profileId, share }) }); setNotice(""); refresh(); return true; } catch (error) { fail(error); return false; }
  };
  const groupAction = async (circle: Circle, action: GroupAction, extra: { share?: Share; profileId?: string; target?: string } = {}) => {
    try { await api(`/api/circles/${circle.id}`, { method: "POST", body: JSON.stringify({ action, ...extra }) }); setNotice(""); refresh(); } catch (error) { fail(error); }
  };
  const toggleCircleRoute = async (circle: Circle, profileId: string) => {
    if (memberTrails[profileId]) { setMemberTrails(previous => Object.fromEntries(Object.entries(previous).filter(([key]) => key !== profileId))); return; }
    try {
      const data = await api<{ paths: Path[] }>(`/api/circles/${circle.id}/trail?profile=${encodeURIComponent(profileId)}&hours=72`);
      setMemberTrails(previous => ({ ...previous, [profileId]: data.paths }));
      setNotice("");
    } catch (error) { fail(error); }
  };
  const flyToPosition = (position: { mapId: number; x: number; y: number }) => { const at = place(position.mapId, position.x, position.y); if (at) flyTo({ points: [at] }); };
  const newest = route?.paths[0];
  const latestPlace = useMemo(() => {
    if (!newest) return null;
    const last = newest.points[newest.points.length - 1];
    const at = place(newest.mapId, last[1], last[2]);
    return at ? { label: route?.characters.find(entry => entry.id === newest.profileId)?.name ?? s.guildYou, u: at[0], v: at[1] } : null;
  }, [newest, place, route, s.guildYou]);
  /** Everyone of a guild or group (value "guild:ID" / "circle:ID") whose position is known, with the account's own last position. */
  const positionsFor = useCallback((audience: string) => {
    const [kind, id] = audience.split(":");
    const out: { name: string; label: string; u: number; v: number }[] = [];
    const push = (name: string, position: { mapId: number; x: number; y: number } | null) => {
      const at = position && place(position.mapId, position.x, position.y);
      if (at) out.push({ name, label: name, u: at[0], v: at[1] });
    };
    if (kind === "circle") for (const member of circles?.find(circle => circle.id === id)?.members ?? []) { if (!member.isMe) push(member.name, member.position); }
    if (kind === "guild") { const guild = guilds?.find(entry => entry.id === id); for (const member of guild?.members ?? []) if (!guild!.mine.some(row => row.profileId === member.profileId)) push(member.name, member.position); }
    if (latestPlace && out.length) out.push({ name: latestPlace.label, label: latestPlace.label, u: latestPlace.u, v: latestPlace.v });
    return out;
  }, [circles, guilds, place, latestPlace]);
  const latest = shownPaths[0];
  const flyToLatest = () => { if (!latest) return; const last = latest.points[latest.points.length - 1]; const at = place(latest.mapId, last[1], last[2]); if (at) flyTo({ points: [at] }); };

  return {
    trails, people, onPerson: setPicked, latestPlace, positionsFor,
    panel: {
      user, layers, route, shownPaths, guilds, failed, notice, hours, setHours, character, setCharacter, picked, memberTrails, now,
      refresh, eraseRoute, membership, toggleMemberRoute, flyToLatest, where, circles, profiles, createGroup, joinGroup, groupAction, toggleCircleRoute, flyToPosition,
      placeOf: (position: { mapId: number; x: number; y: number }) => place(position.mapId, position.x, position.y), hasOrigin: Boolean(latestPlace),
      flyToMember: (member: Member) => { if (!member.position) return; const at = place(member.position.mapId, member.position.x, member.position.y); if (at) flyTo({ points: [at] }); },
    },
  };
}

export function PeoplePanel({ panel, signIn, onRoute, onLayer }: { panel: PeopleHook["panel"]; signIn: string | null; onRoute: (name: string, at: [number, number]) => void; onLayer: (id: "route" | "guild") => void }) {
  const s = useS();
  const { lang } = useI18n();
  const [open, setOpen] = useState(true);
  const [showAll, setShowAll] = useState(false);
  const [joinAs, setJoinAs] = useState<Record<string, Share>>({});
  const [groupName, setGroupName] = useState("");
  const [groupCode, setGroupCode] = useState("");
  const [groupChar, setGroupChar] = useState("");
  const [groupShare, setGroupShare] = useState<Share>("last");
  const [copied, setCopied] = useState("");
  const [tab, setTab] = useState<"route" | "groups" | "guild" | null>(null);
  const { user, layers, route, shownPaths, guilds, hours, now } = panel;
  if (!layers.route && !layers.guild) return null;

  const points = shownPaths.reduce((sum, path) => sum + path.points.length, 0);
  const latest = shownPaths[0];
  const shareLabel: Record<Share, string> = { off: s.shareOff, last: s.shareLast, trail: s.shareTrail };
  const active = tab === "route" && !layers.route ? "groups" : tab && tab !== "route" && !layers.guild ? "route" : tab ?? (layers.route ? "route" : "groups");
  const chooseTab = (next: "route" | "groups" | "guild") => {
    setTab(next);
    onLayer(next === "route" ? "route" : "guild");
  };
  const tabs = [
    { id: "route" as const, label: s.myRoute },
    { id: "groups" as const, label: s.groupsHeading },
    { id: "guild" as const, label: lang === "cs" ? "Cech" : "Guild" },
  ];
  const plural = (n: number, forms: [string, string, string]) => `${n} ${forms[n === 1 ? 0 : n >= 2 && n <= 4 ? 1 : 2]}`;
  const summary = lang === "cs" ? `${plural(shownPaths.length, ["úsek", "úseky", "úseků"])} · ${plural(points, ["bod", "body", "bodů"])}` : fill(s.routeSummary, { paths: shownPaths.length, points });

  return (
    <section className={`people-panel ${open ? "open" : ""}`} aria-label={lang === "cs" ? "Trasy a skupiny" : "Routes and groups"}>
      <header>
        <h3><Icon name="route" size={15} /> {lang === "cs" ? "Trasy a skupiny" : "Routes and groups"}</h3>
        <button type="button" className="icon-btn" onClick={() => setOpen(value => !value)} aria-expanded={open} aria-label={open ? (lang === "cs" ? "Sbalit panel" : "Collapse panel") : (lang === "cs" ? "Rozbalit panel" : "Expand panel")}>{open ? "−" : "+"}</button>
      </header>
      {open && (
        <>
        {user && <div className="pp-tabs" role="tablist" aria-label={lang === "cs" ? "Vybrat část" : "Choose section"}>
          {tabs.map(item => <button key={item.id} type="button" role="tab" aria-selected={active === item.id} className={active === item.id ? "active" : ""} onClick={() => chooseTab(item.id)}>{item.label}</button>)}
        </div>}
        <div className="pp-body" role="tabpanel">
          {!user ? (
            <div className="pp-block">
              <p className="muted small">{s.peopleSignIn}</p>
              {signIn && <a className="btn btn-primary btn-sm" href={signIn}>{s.peopleSignInButton}</a>}
            </div>
          ) : (
            <>
              {panel.notice && <p className="pp-notice" role="status">{panel.notice}</p>}
              {panel.failed && <p className="pp-notice" role="alert">{s.routeLoadFailed}</p>}
              {active === "route" && layers.route && (
                <div className="pp-block">
                  <h4>{lang === "cs" ? "Tvoje zaznamenaná cesta" : "Your recorded journey"}</h4>
                  <p className="pp-intro">{lang === "cs" ? "Podívej se, kudy tvoje postava prošla." : "See where your character has travelled."}</p>
                  <div className="pp-controls">
                    <label>{s.routeRange}
                      <select value={hours} onChange={event => panel.setHours(Number(event.target.value) as Hours)}>
                        <option value={24}>{s.range24}</option><option value={168}>{s.range7}</option><option value={720}>{s.range30}</option>
                      </select>
                    </label>
                    {(route?.characters.length ?? 0) > 1 && (
                      <label>{s.allCharacters}
                        <select value={panel.character} onChange={event => panel.setCharacter(event.target.value)}>
                          <option value="">{s.allCharacters}</option>
                          {route?.characters.map(entry => <option key={entry.id} value={entry.id}>{entry.name ?? "?"}</option>)}
                        </select>
                      </label>
                    )}
                  </div>
                  {latest ? (
                    <>
                      <p className="pp-summary"><strong>{summary}</strong><span>{fill(s.routeLast, { when: ago(latest.endedAt, now, lang, s.agoNow) })}</span></p>
                      {route?.truncated && <p className="muted small">{s.routeTruncated}</p>}
                      <div className="btn-row">
                        <button type="button" className="btn btn-ghost btn-sm" onClick={panel.flyToLatest}>{s.routeLatest}</button>
                        <button type="button" className="btn btn-ghost btn-sm" onClick={panel.refresh}>{s.refresh}</button>
                        <button type="button" className="btn btn-ghost btn-sm danger" onClick={() => void panel.eraseRoute()}><Icon name="trash" size={13} /> {s.routeErase}</button>
                      </div>
                    </>
                  ) : <p className="muted small">{route ? s.routeEmpty : "…"}</p>}
                  <p className="fine-print">{lang === "cs" ? "Trasu vidíš jen ty, dokud se nerozhodneš ji sdílet. Uchovává se 30 dní." : "Only you see this route until you choose to share it. It is kept for 30 days."}</p>
                </div>
              )}
              {active === "guild" && layers.guild && (
                <div className="pp-block">
                  <h4>{lang === "cs" ? "Tvůj cech" : "Your guild"}</h4>
                  {guilds && guilds.length === 0 && <div className="pp-empty"><strong>{lang === "cs" ? "Zatím tu žádný cech není" : "No guild yet"}</strong><p>{lang === "cs" ? "Ve hře v Evertally zapni Webový export → Moje postava a Můj cech. Potom napiš /reload a počkej na synchronizaci aplikace." : "In Evertally, turn on Website export → My character and My guild. Then type /reload and wait for the app to sync."}</p></div>}
                  {guilds?.map(guild => {
                    const members = guild.members;
                    const visible = members ? (showAll ? members : members.filter(member => member.onMap)) : [];
                    return (
                      <div className="pp-guild" key={guild.id}>
                        <div className="pp-guild-head"><b>{guild.name}</b><span className="muted small">{guild.realm}</span></div>
                        <p className="muted small">
                          {guild.ownerName ? fill(s.guildBy, { name: guild.ownerName }) : s.guildNoRoster}
                          {guild.ownerName && <> · {fill(s.guildMembersCount, { count: guild.rosterSize })}{guild.rosterAt ? ` · ${fill(s.guildImported, { when: ago(guild.rosterAt, now, lang, s.agoNow) })}` : ""}</>}
                        </p>
                        {guild.mine.map(row => (
                          <div className="pp-char" key={row.profileId}>
                            <div className="pp-char-head"><b>{row.name}</b><span className={`pp-state ${row.status}`}>{row.status === "active" ? s.active : row.status === "declined" ? s.declined : s.pending}</span></div>
                            {row.status === "active" ? (
                              <div className="pp-controls">
                                <label>{s.guildShareWith}
                                  <select value={row.share} onChange={event => void panel.membership(guild, row.profileId, "share", event.target.value as Share)}>
                                    {(["last", "trail", "off"] as Share[]).map(mode => <option key={mode} value={mode}>{shareLabel[mode]}</option>)}
                                  </select>
                                </label>
                                <button type="button" className="btn btn-ghost btn-sm" onClick={() => void panel.membership(guild, row.profileId, "leave")}>{s.guildLeave}</button>
                              </div>
                            ) : row.eligible ? (
                              <div className="pp-join">
                                <p className="muted small">{fill(s.guildTrust, { name: guild.ownerName ?? "?" })}</p>
                                <div className="pp-controls">
                                  <select value={joinAs[row.profileId] ?? "last"} onChange={event => setJoinAs(previous => ({ ...previous, [row.profileId]: event.target.value as Share }))} aria-label={s.guildShareWith}>
                                    <option value="last">{s.shareLast}</option><option value="trail">{s.shareTrail}</option>
                                  </select>
                                  <button type="button" className="btn btn-primary btn-sm" onClick={() => void panel.membership(guild, row.profileId, "join", joinAs[row.profileId] ?? "last")}>{s.guildJoin}</button>
                                </div>
                              </div>
                            ) : <p className="muted small">{guild.ownerName ? fill(s.guildNotListed, { name: row.name }) : s.guildNoRoster}</p>}
                          </div>
                        ))}
                        {members && (
                          <>
                            <h5>{s.guildMembers}</h5>
                            <ul className="pp-members">
                              {visible.map(member => {
                                const mine = guild.mine.some(row => row.profileId === member.profileId);
                                const shown = member.profileId ? Boolean(panel.memberTrails[member.profileId]) : false;
                                return (
                                  <li key={`${member.name}-${member.profileId ?? ""}`} className={`${member.onMap ? "on" : "off"} ${member.profileId && panel.picked === `g:${member.profileId}` ? "picked" : ""}`}>
                                    <i style={{ background: classColor(member.classId) }} title={member.classId ? CLASSES[member.classId] : undefined} />
                                    <span className="who"><b>{member.name}</b>{member.level ? <em> {member.level}</em> : null}{mine ? <em> · {s.guildYou}</em> : null}</span>
                                    <span className="where muted small">
                                      {member.position ? `${panel.where(member.position.mapId)} · ${ago(member.position.at, now, lang, s.agoNow)}` : member.onMap ? (member.share === "off" ? s.guildNotSharing : s.guildNoPosition) : s.guildOffMap}
                                    </span>
                                    <span className="acts">
                                      {member.position && <button type="button" className="icon-btn" title={s.guildFly} aria-label={s.guildFly} onClick={() => panel.flyToMember(member)}><Icon name="compass" size={14} /></button>}
                                      {member.position && !mine && <button type="button" className="icon-btn" title={panel.hasOrigin ? s.routeToPlayer : `${s.routeToPlayer}. ${s.routeToPlayerNeed}`} aria-label={s.routeToPlayer} onClick={() => { const at = panel.placeOf(member.position!); if (at) onRoute(member.name, at); }}><Icon name="route" size={14} /></button>}
                                      {member.share === "trail" && member.profileId && !mine && (
                                        <button type="button" className={`pp-route ${shown ? "on" : ""}`} aria-pressed={shown} onClick={() => void panel.toggleMemberRoute(guild, member.profileId!)}>{shown ? s.guildHideRoute : s.guildShowRoute}</button>
                                      )}
                                    </span>
                                  </li>
                                );
                              })}
                            </ul>
                            {members.some(member => !member.onMap) && (
                              <button type="button" className="btn btn-ghost btn-sm" onClick={() => setShowAll(value => !value)}>
                                {showAll ? s.guildOnMap : `${s.guildOffMap}: ${members.filter(member => !member.onMap).length}`}
                              </button>
                            )}
                            <p className="fine-print">{s.guildFresh} {fill(s.routeInGame, { name: members.find(member => member.position)?.name ?? "Name" })}</p>
                          </>
                        )}
                      </div>
                    );
                  })}
                </div>
              )}
              {active === "groups" && layers.guild && <div className="pp-block"><GroupsBlock panel={panel} state={{ groupName, setGroupName, groupCode, setGroupCode, groupChar, setGroupChar, groupShare, setGroupShare, copied, setCopied }} shareLabel={shareLabel} onRoute={onRoute} /></div>}
            </>
          )}
        </div>
        </>
      )}
    </section>
  );
}

type GroupState = { groupName: string; setGroupName: (value: string) => void; groupCode: string; setGroupCode: (value: string) => void; groupChar: string; setGroupChar: (value: string) => void; groupShare: Share; setGroupShare: (value: Share) => void; copied: string; setCopied: (value: string) => void };

function GroupsBlock({ panel, state, shareLabel, onRoute }: { panel: PeopleHook["panel"]; state: GroupState; shareLabel: Record<Share, string>; onRoute: (name: string, at: [number, number]) => void }) {
  const s = useS();
  const { lang } = useI18n();
  const [form, setForm] = useState<"create" | "join" | null>(null);
  const { circles, profiles, now } = panel;
  const character = state.groupChar || profiles[0]?.id || "";
  const copy = async (text: string, key: string) => { try { await navigator.clipboard?.writeText(text); state.setCopied(key); setTimeout(() => state.setCopied(""), 1500); } catch { /* clipboard unavailable */ } };
  const characterSelect = (value: string, onChange: (id: string) => void) => (
    <select value={value} onChange={event => onChange(event.target.value)} aria-label={s.groupCharacter}>
      {profiles.map(entry => <option key={entry.id} value={entry.id}>{entry.name ?? "?"}{entry.level ? ` (${entry.level})` : ""}</option>)}
    </select>
  );
  return (
    <div className="pp-groups">
      <h4>{lang === "cs" ? "Hrajte společně" : "Play together"}</h4>
      <p className="pp-intro">{lang === "cs" ? "Založ skupinu pro kamarády nebo se připoj pomocí jejich kódu. Každý si sám vybere, co sdílí." : "Create a group for friends or join with their code. Each player chooses what to share."}</p>
      {profiles.length === 0 && <div className="pp-empty"><strong>{lang === "cs" ? "Nejdřív přidej postavu" : "Add a character first"}</strong><p>{s.groupNoCharacters}</p></div>}
      {circles?.map(circle => (
        <div className="pp-guild" key={circle.id}>
          <div className="pp-guild-head"><b>{circle.name}</b><span className="muted small">{fill(s.groupMembers, { count: circle.members.length })}</span></div>
          {circle.inviteCode && (
            <div className="pp-controls">
              <label>{s.groupInvite}<input className="code" readOnly value={circle.inviteCode} onFocus={event => event.currentTarget.select()} /></label>
              <button type="button" className="btn btn-ghost btn-sm" onClick={() => void copy(circle.inviteCode!, `code-${circle.id}`)}>{state.copied === `code-${circle.id}` ? s.groupCopied : s.groupCopy}</button>
              <button type="button" className="btn btn-ghost btn-sm" onClick={() => void panel.groupAction(circle, "rotate")}>{s.groupRotate}</button>
            </div>
          )}
          <div className="pp-controls">
            <label>{s.groupCharacter}{characterSelect(circle.mine.profileId, id => void panel.groupAction(circle, "character", { profileId: id }))}</label>
            <label>{s.groupShareHint}
              <select value={circle.mine.share} onChange={event => void panel.groupAction(circle, "share", { share: event.target.value as Share })}>
                {(["last", "trail", "off"] as Share[]).map(mode => <option key={mode} value={mode}>{shareLabel[mode]}</option>)}
              </select>
            </label>
          </div>
          <ul className="pp-members">
            {circle.members.map(member => {
              const shown = Boolean(panel.memberTrails[member.profileId]);
              return (
                <li key={member.profileId} className={`on ${panel.picked === `c:${member.profileId}` ? "picked" : ""}`}>
                  <i style={{ background: classColor(member.classId) }} title={member.classId ? CLASSES[member.classId] : undefined} />
                  <span className="who"><b>{member.name}</b>{member.level ? <em> {member.level}</em> : null}{member.isMe ? <em> · {s.guildYou}</em> : null}{member.isOwner ? <em> · {s.groupOwnerTag}</em> : null}</span>
                  <span className="where muted small">{member.isMe ? "" : member.position ? `${panel.where(member.position.mapId)} · ${ago(member.position.at, now, lang, s.agoNow)}` : member.share === "off" ? s.guildNotSharing : s.guildNoPosition}</span>
                  <span className="acts">
                  {member.position && !member.isMe && <button type="button" className="icon-btn" title={s.guildFly} aria-label={s.guildFly} onClick={() => panel.flyToPosition(member.position!)}><Icon name="compass" size={14} /></button>}
                  {member.position && !member.isMe && <button type="button" className="icon-btn" title={panel.hasOrigin ? s.routeToPlayer : `${s.routeToPlayer}. ${s.routeToPlayerNeed}`} aria-label={s.routeToPlayer} onClick={() => { const at = panel.placeOf(member.position!); if (at) onRoute(member.name, at); }}><Icon name="route" size={14} /></button>}
                  {member.share === "trail" && !member.isMe && <button type="button" className={`pp-route ${shown ? "on" : ""}`} aria-pressed={shown} onClick={() => void panel.toggleCircleRoute(circle, member.profileId)}>{shown ? s.guildHideRoute : s.guildShowRoute}</button>}
                  {circle.isOwner && !member.isMe && <button type="button" className="pp-route" onClick={() => void panel.groupAction(circle, "kick", { target: member.profileId })}>{s.groupKick}</button>}
                  </span>
                </li>
              );
            })}
          </ul>
          <div className="btn-row">
            <button type="button" className="btn btn-ghost btn-sm" onClick={() => void panel.groupAction(circle, "leave")}>{s.groupLeave}</button>
            {circle.isOwner && <button type="button" className="btn btn-ghost btn-sm danger" onClick={() => { if (window.confirm(s.groupCloseAsk)) void panel.groupAction(circle, "close"); }}>{s.groupClose}</button>}
          </div>
        </div>
      ))}
      {profiles.length > 0 && !form && <div className="pp-group-actions">
        <button type="button" className="btn btn-primary btn-sm" onClick={() => setForm("create")}>{lang === "cs" ? "Vytvořit skupinu" : "Create a group"}</button>
        <button type="button" className="btn btn-ghost btn-sm" onClick={() => setForm("join")}>{s.groupJoinTitle}</button>
      </div>}
      {profiles.length > 0 && form && (
        <div className="pp-char pp-group-form">
          <div className="pp-form-heading"><strong>{form === "create" ? (lang === "cs" ? "Nová skupina" : "New group") : s.groupJoinTitle}</strong><button type="button" className="pp-back" onClick={() => setForm(null)}>{lang === "cs" ? "Zpět" : "Back"}</button></div>
          <div className="pp-controls">
            <label>{s.groupCharacter}{characterSelect(character, state.setGroupChar)}</label>
            <label>{s.groupShareHint}
              <select value={state.groupShare} onChange={event => state.setGroupShare(event.target.value as Share)}>
                {(["last", "trail", "off"] as Share[]).map(mode => <option key={mode} value={mode}>{shareLabel[mode]}</option>)}
              </select>
            </label>
          </div>
          {form === "create" ? <div className="pp-controls">
            <label className="pp-grow">{s.groupName}<input value={state.groupName} onChange={event => state.setGroupName(event.target.value)} placeholder={lang === "cs" ? "Např. Naše parta" : "e.g. Our party"} maxLength={40} /></label>
            <button type="button" className="btn btn-primary btn-sm" disabled={!state.groupName.trim()} onClick={() => void panel.createGroup(state.groupName, character, state.groupShare).then(ok => { if (ok) { state.setGroupName(""); setForm(null); } })}>{s.groupCreate}</button>
          </div> : <div className="pp-controls">
            <label className="pp-grow">{s.groupCode}<input value={state.groupCode} onChange={event => state.setGroupCode(event.target.value)} placeholder={s.groupCode} maxLength={20} /></label>
            <button type="button" className="btn btn-primary btn-sm" disabled={state.groupCode.trim().length < 6} onClick={() => void panel.joinGroup(state.groupCode, character, state.groupShare).then(ok => { if (ok) { state.setGroupCode(""); setForm(null); } })}>{s.groupJoin}</button>
          </div>}
        </div>
      )}
    </div>
  );
}

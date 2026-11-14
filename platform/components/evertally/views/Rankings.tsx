"use client";
import { useState, type CSSProperties, type FormEvent, type ReactNode } from "react";
import { useI18n, type Key } from "@/lib/i18n";
import { useApi } from "../api";
import { CLASS_COLORS, CLASSES, FOREVER_CLASS_IDS, FOREVER_RACE_IDS, RACES, duration, factionOf, type Faction } from "../data";
import { useDungeonArt } from "../db/store";
import { CharacterIcons, fullName } from "../Identity";
import { guildHref, METRICS, needsInstance, parseRankingRoute, rankingHash, rankingQuery, type Metric, type RankingFilters, type RankingState } from "../rankingRoute";
import type { Entry, Me, Run, User } from "../types";
import type { InstanceSummary, RealmSummary, Statistics } from "@/lib/run-rankings";
import type { FameRaid, GuildSummary } from "@/lib/guilds";
import { Icon } from "../ui";

type Board = { entries: Entry[]; sampleSize: number; rulesLabel: string; total: number; page: number; pageSize: number; hasMore: boolean };

const METRIC_KEY: Record<Metric, Key> = { level: "rankings.level", count: "rankings.count", time: "rankings.time", instances: "rankings.instances", dps: "rankings.dps", hps: "rankings.hps", guilds: "rankings.guilds", fame: "rankings.fame", stats: "rankings.stats" };
const KINDS: readonly (readonly [string, Key])[] = [["", "rankings.kindAll"], ["party", "rankings.dungeons"], ["raid", "rankings.raids"]];
const DEFAULT_ART = "/media/dungeons/blackrock-depths.jpg";
const slug = (name: string) => name.toLowerCase().replace(/['’]/g, "").replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");

function go(next: RankingState) { window.location.hash = rankingHash(next); }

/** Raider.IO-style leaderboard: one button per board, art banner with filter pills, pagination on top, one dense row each. */
export function RankingsView({ route, user = null }: { route: string; user?: User | null }) {
  const state = parseRankingRoute(route);
  // two components, so switching between characters and guilds never changes the hooks of one of them
  return state.metric === "guilds" ? <GuildBoard state={state} /> : state.metric === "stats" ? <StatsBoard state={state} /> : state.metric === "fame" ? <FameBoard state={state} /> : <CharacterBoard state={state} user={user} />;
}

function Tabs({ state }: { state: RankingState }) {
  const { t } = useI18n();
  return <nav className="lb-tabs" aria-label={t("rankings.metric")}>
    {METRICS.map(m => <a key={m} href={`#${rankingHash({ ...state, metric: m, page: 0 })}`} className={m === state.metric ? "on" : undefined} aria-current={m === state.metric ? "page" : undefined}>{t(METRIC_KEY[m])}</a>)}
  </nav>;
}

function CharacterBoard({ state, user }: { state: RankingState; user: User | null }) {
  const { t, num } = useI18n();
  const { metric, filters } = state;
  const setFilter = (key: keyof RankingFilters, value: string) => go({ ...state, filters: { ...filters, [key]: value || undefined }, page: 0 });
  const setPage = (page: number) => go({ ...state, page });

  const waiting = needsInstance(metric) && !filters.instanceId;
  // the Instances board, and times or combat rates without an instance, show one card per instance instead of a table
  const overviewMode = metric === "instances";
  const showGrid = waiting || overviewMode;
  const board = useApi<Board>(showGrid ? null : `/api/leaderboards?${rankingQuery(state)}`);
  const overviewQuery = new URLSearchParams(rankingQuery({ ...state, metric: "count", q: "", page: 0 }));
  overviewQuery.set("metric", "instances"); overviewQuery.delete("page"); overviewQuery.delete("instanceId");
  const overview = useApi<{ instances: InstanceSummary[]; sampleSize: number }>(showGrid ? `/api/leaderboards?${overviewQuery}` : null);
  const runs = useApi<{ runs: Run[] }>(metric === "level" || overviewMode ? null : "/api/runs");
  const pickInstance = (id: number) => overviewMode
    ? go({ ...state, metric: "time", filters: { ...filters, instanceId: String(id) }, page: 0 })
    : setFilter("instanceId", String(id));
  const art = useDungeonArt();
  // a signed-in player sees which of their own characters are not on the board yet
  const me = useApi<Me>(user ? "/api/me" : null);
  const hidden = (me.data?.profiles ?? []).filter(p => !p.public && p.name);

  // keep the last table on screen while the next filter loads, instead of flashing an empty page
  const [shown, setShown] = useState<Board | null>(null);
  if (board.data && board.data !== shown) setShown(board.data);
  const data = showGrid ? null : board.data ?? shown;

  // the search box follows the address when it changes from outside (back button, a shared link)
  const [draft, setDraft] = useState(state.q);
  const [seenQ, setSeenQ] = useState(state.q);
  if (seenQ !== state.q) { setSeenQ(state.q); setDraft(state.q); }
  const search = (event: FormEvent) => { event.preventDefault(); go({ ...state, q: draft.trim().slice(0, 80), page: 0 }); };

  const instances = Array.from(new Map((runs.data?.runs ?? []).filter(r => r.instanceId && (!filters.instanceType || r.instanceType === filters.instanceType)).map(r => [String(r.instanceId), r.name])).entries()).sort((a, b) => a[1].localeCompare(b[1]));
  // a shared link may name an instance that is not among the latest runs; the results still know its name
  const instanceName = filters.instanceId ? instances.find(([id]) => id === filters.instanceId)?.[1] ?? data?.entries.find(e => e.instanceName)?.instanceName : undefined;
  if (filters.instanceId && !instances.some(([id]) => id === filters.instanceId)) instances.push([filters.instanceId, instanceName ?? `#${filters.instanceId}`]);
  const picked = instanceName ? art.data?.[slug(instanceName)] : undefined;
  const banner = picked && picked.source !== "floor" && picked.source !== "map" ? picked.image : DEFAULT_ART;

  const metricTitle = t(METRIC_KEY[metric]);
  const crumbs = [
    metricTitle,
    filters.classId ? CLASSES[Number(filters.classId)] ?? `#${filters.classId}` : t("runs.allClasses"),
    filters.raceId ? RACES[Number(filters.raceId)] ?? `#${filters.raceId}` : t("runs.allRaces"),
    filters.faction ? t(filters.faction === "horde" ? "rankings.horde" : "rankings.alliance") : t("rankings.allFactions"),
    ...(filters.realm ? [filters.realm] : []),
    ...(filters.role ? [t(`role.${filters.role as "tank" | "healer" | "dps"}`)] : []),
    ...(metric === "level" ? [] : [instanceName ?? (filters.instanceType ? t(filters.instanceType === "raid" ? "rankings.raids" : "rankings.dungeons") : t("rankings.allCategories"))]),
  ];

  const entries = data?.entries ?? [];
  // an empty filtered board is only "nobody matches" when the unfiltered board has somebody on it
  const filtered = Boolean(state.q || Object.keys(filters).length);
  const probe = useApi<Board>(data && !data.total && filtered ? `/api/leaderboards?metric=${metric === "level" ? "level" : "count"}` : null);
  const nothingPublic = !filtered || probe.data?.total === 0;
  const pager = data && (state.page > 0 || data.hasMore) ? <Pager page={state.page} hasMore={data.hasMore} onPage={setPage} /> : null;

  return (
    <div className="page-column lb">
      <Tabs state={state} />
      <section className="lb-banner" style={{ "--lb-art": `url("${banner}")` } as CSSProperties}>
        <div className="lb-pills">
          <Pill label={t("runs.class")} value={filters.classId ?? ""} onChange={value => setFilter("classId", value)}>
            <option value="">{t("runs.allClasses")}</option>
            {FOREVER_CLASS_IDS.map(id => <option key={id} value={id}>{CLASSES[id]}</option>)}
          </Pill>
          <Pill label={t("runs.race")} value={filters.raceId ?? ""} onChange={value => setFilter("raceId", value)}>
            <option value="">{t("runs.allRaces")}</option>
            {FOREVER_RACE_IDS.map(id => <option key={id} value={id}>{RACES[id]}</option>)}
          </Pill>
          <Pill label={t("rankings.faction")} value={filters.faction ?? ""} onChange={value => setFilter("faction", value)}>
            <option value="">{t("rankings.allFactions")}</option>
            <option value="alliance">{t("rankings.alliance")}</option>
            <option value="horde">{t("rankings.horde")}</option>
          </Pill>
          <RealmPill value={filters.realm} onChange={value => setFilter("realm", value)} />
          {metric === "level" && <Pill label={t("rankings.role")} value={filters.role ?? ""} onChange={value => setFilter("role", value)}>
            <option value="">{t("rankings.allRoles")}</option>
            {(["tank", "healer", "dps"] as const).map(role => <option key={role} value={role}>{t(`role.${role}`)}</option>)}
          </Pill>}
          {metric !== "level" && <>
            <div className="lb-seg" role="group" aria-label={t("rankings.category")}>
              {KINDS.map(([value, key]) => {
                const on = (filters.instanceType ?? "") === value;
                return <button key={value || "all"} type="button" className={on ? "on" : undefined} aria-pressed={on}
                  onClick={() => go({ ...state, filters: { ...filters, instanceType: value || undefined, instanceId: undefined }, page: 0 })}>{t(key)}</button>;
              })}
            </div>
            {!overviewMode && <Pill label={t("rankings.instance")} attention={waiting} value={filters.instanceId ?? ""} onChange={value => setFilter("instanceId", value)}>
              <option value="">{needsInstance(metric) ? t("rankings.pickInstance") : t("runs.allInstances")}</option>
              {instances.map(([id, name]) => <option key={id} value={id}>{name}</option>)}
            </Pill>}
          </>}
        </div>
        <span className="lb-eyebrow">{t("rankings.eyebrow")}</span>
        <h1 className="lb-title">{t("rankings.board")}{crumbs.map(crumb => <span key={crumb}> • {crumb}</span>)}</h1>
      </section>

      {hidden.length > 0 && <div className="lb-mine">
        <Icon name="lock" size={14} />
        <span>{t("rankings.mineHidden", { names: hidden.slice(0, 4).map(p => p.name).join(", ") + (hidden.length > 4 ? ` +${hidden.length - 4}` : "") })}</span>
        <a href="#account">{t("rankings.makePublic")}</a>
      </div>}
      <div className="lb-bar">
        {pager ?? <span />}
        {!overviewMode && <form className="lb-search" role="search" onSubmit={search}>
          <label><span className="visually-hidden">{t("rankings.searchLabel")}</span>
            <Icon name="search" size={15} />
            <input type="search" maxLength={80} value={draft} onChange={event => setDraft(event.target.value)} placeholder={t("rankings.searchPlaceholder")} />
          </label>
          <button className="lb-btn" type="submit">{t("rankings.search")}</button>
          {state.q && <button className="lb-btn ghost" type="button" onClick={() => go({ ...state, q: "", page: 0 })}>{t("rankings.clear")}</button>}
        </form>}
      </div>

      {filters.role && <p className="ch-note"><Icon name="info" size={14} /> {t("rankings.roleNote")}</p>}
      {state.q && <GuildMatches q={state.q} />}
      {showGrid ? <DungeonGrid data={overview.data} failed={Boolean(overview.error)} art={art.data} onPick={pickInstance} lead={overviewMode ? t("rankings.instancesLead") : undefined} emptyTitle={overviewMode ? t("home.noDungeons") : undefined} /> :
      <div className={`lb-table-wrap${board.loading && shown ? " is-loading" : ""}`} aria-busy={board.loading}>
        <table className="lb-table">
          <thead><tr><th className="lb-rank">{t("rankings.rank")}</th><th>{t("runs.character")}</th><th className="num">{metricTitle}</th></tr></thead>
          <tbody>
            {board.error ? <MessageRow icon="info" title={t("error.service_unavailable")} />
              : !data ? <MessageRow icon="trophy" title={t("common.loading")} />
              : entries.length ? entries.map(entry => <Row key={entry.character.id} entry={entry} metric={metric} />)
              : !nothingPublic ? <MessageRow icon="search" title={t("rankings.noMatch")} />
              : <MessageRow icon="trophy" title={metric === "level" ? t("rankings.noPublicTitle") : t("common.noData")}
                  action={metric === "level" ? <a className="lb-btn" href="#account"><Icon name="globe" size={14} /> {t("rankings.makePublic")}</a> : undefined}>
                  {metric === "level" ? t("rankings.noPublicText") : t("rankings.countEmpty")}
                </MessageRow>}
          </tbody>
        </table>
      </div>}

      <div className="lb-foot">
        {pager ?? <span />}
        {data && <span className="lb-count">{t("rankings.results", { count: num(data.total) })}{metric !== "level" && <> · {t("rankings.sample")}: {num(data.sampleSize)}</>}</span>}
        {overviewMode && overview.data && <span className="lb-count">{t("rankings.sample")}: {num(overview.data.sampleSize)}</span>}
      </div>
      <details className="lb-about">
        <summary><Icon name="info" size={14} /> {t("rankings.about")}</summary>
        <p>{metric === "level" ? t("rankings.noteLevel") : t("rankings.noteRuns")}</p>
        <p>{t("rankings.noteExtras")}</p>
      </details>
    </div>
  );
}

export function Pill({ label, value, onChange, accent = false, attention = false, children }: { label: string; value: string; onChange: (value: string) => void; accent?: boolean; attention?: boolean; children: ReactNode }) {
  return <label className={`lb-pill${accent ? " accent" : ""}${attention ? " attention" : ""}${value ? " set" : ""}`}>
    <span className="visually-hidden">{label}</span>
    <select value={value} onChange={event => onChange(event.target.value)}>{children}</select>
  </label>;
}

function Pager({ page, hasMore, onPage }: { page: number; hasMore: boolean; onPage: (page: number) => void }) {
  const { t } = useI18n();
  return <nav className="lb-pager" aria-label={t("rankings.pages")}>
    <button className="lb-btn ghost" disabled={page === 0} onClick={() => onPage(0)}>⏮ {t("rankings.first")}</button>
    <button className="lb-btn ghost" disabled={page === 0} onClick={() => onPage(page - 1)}>← {t("rankings.prev")}</button>
    <span>{t("rankings.page", { page: page + 1 })}</span>
    <button className="lb-btn" disabled={!hasMore} onClick={() => onPage(page + 1)}>{t("rankings.next")} →</button>
  </nav>;
}

export function FactionMark({ faction }: { faction: Faction | null }) {
  const { t } = useI18n();
  if (!faction) return null;
  const label = t(faction === "horde" ? "rankings.horde" : "rankings.alliance");
  return <span className={`lb-faction ${faction}`} role="img" aria-label={label} title={label}>
    <svg viewBox="0 0 16 16" width="16" height="16" aria-hidden="true"><path d="M8 1.5 2.5 3.6v4.1c0 3.2 2.4 5.6 5.5 6.8 3.1-1.2 5.5-3.6 5.5-6.8V3.6L8 1.5Z" /></svg>
  </span>;
}

export function Row({ entry, metric }: { entry: Entry; metric: Metric }) {
  const { t, num, lang } = useI18n();
  const c = entry.character;
  const color = CLASS_COLORS[c.classId ?? 0];
  // the realm is already part of the name (Name-Realm), so the line below names race and class only
  const ilvl = entry.itemLevel != null ? t("rankings.ilvl", { level: entry.itemLevel }) : null;
  const sub = [RACES[c.raceId ?? 0], CLASSES[c.classId ?? 0], entry.spec ? `${entry.spec} ${entry.specPoints ?? ""}`.trim() : null, metric !== "level" && c.level ? `${t("rankings.lv")} ${c.level}` : null, metric !== "level" ? ilvl : null].filter(Boolean).join(" · ");
  const rate = (value?: number) => value == null ? "—" : new Intl.NumberFormat(lang === "cs" ? "cs-CZ" : "en-GB", { maximumFractionDigits: 1 }).format(value);
  let top: ReactNode = null, main: ReactNode;
  if (metric === "level") { main = <><small className="lb-unit">{t("rankings.lv")}</small> {entry.value ?? c.level ?? "—"}</>; top = ilvl; }
  else if (metric === "count") { main = num(entry.count); top = entry.bestMs ? t("rankings.best", { time: duration(entry.bestMs) }) : null; }
  else if (metric === "time") { main = duration(entry.value ?? entry.bestMs); top = entry.instanceName; }
  else { main = <>{rate(entry.value)} <small className="lb-unit">{metric.toUpperCase()}</small></>; top = entry.instanceName; }
  return <tr className={entry.rank <= 3 ? `lb-top lb-top-${entry.rank}` : undefined}>
    <td className="lb-rank">{entry.rank}.</td>
    <td>
      <div className="lb-char" style={color ? { "--class": color } as CSSProperties : undefined}>
        <CharacterIcons character={c} size={24} />
        <FactionMark faction={factionOf(c.raceId)} />
        <span className="lb-who"><a className="profile-name" href={`#character/${encodeURIComponent(c.id)}`}>{fullName(c) || t("common.private")}</a>{(entry.guild || sub) && <small>{entry.guild && <a className="lb-guild" href={guildHref(c.realm, entry.guild)}>&lsaquo;{entry.guild}&rsaquo;</a>}{entry.guild && sub ? " · " : ""}{sub}</small>}</span>
      </div>
    </td>
    <td className="lb-value">{top && <small>{top}</small>}<strong>{main}</strong></td>
  </tr>;
}

function MessageRow({ icon, title, action, children }: { icon: string; title: string; action?: ReactNode; children?: ReactNode }) {
  return <tr className="lb-message"><td colSpan={3}>
    <span className="lb-message-icon"><Icon name={icon} size={20} /></span>
    <strong>{title}</strong>
    {children && <p>{children}</p>}
    {action}
  </td></tr>;
}

/** One card per instance with its record. `lead` and `emptyTitle` let the home page reuse it without the leaderboard's wording. */
export function DungeonGrid({ data, failed, art, onPick, lead, emptyTitle, limit }: { data: { instances: InstanceSummary[] } | null; failed: boolean; art: Record<string, { image: string; source: string }> | null; onPick: (id: number) => void; lead?: string | null; emptyTitle?: string; limit?: number }) {
  const { t, num } = useI18n();
  if (failed) return <div className="lb-grid-note">{t("error.service_unavailable")}</div>;
  if (!data) return <div className="lb-grid-note">{t("common.loading")}</div>;
  if (!data.instances.length) return <div className="lb-grid-note"><strong>{emptyTitle ?? t("rankings.pickInstanceTitle")}</strong><p>{t("rankings.countEmpty")}</p></div>;
  const lines = lead === undefined ? t("rankings.pickInstanceText") : lead;
  return <div className="lb-dungeons">
    {lines && <p className="lb-grid-lead">{lines}</p>}
    <div className="lb-dungeon-grid">{data.instances.slice(0, limit ?? data.instances.length).map(item => {
      const picture = art?.[slug(item.name)];
      const image = picture && picture.source !== "floor" && picture.source !== "map" ? picture.image : null;
      const color = CLASS_COLORS[item.holder?.classId ?? 0];
      return <button key={item.instanceId} className="lb-dungeon" style={image ? { "--art": `url("${image}")` } as CSSProperties : undefined} onClick={() => onPick(item.instanceId)}>
        <span className="lb-dungeon-kind">{t(item.instanceType === "raid" ? "rankings.raids" : "rankings.dungeons")}</span>
        <strong>{item.name}</strong>
        {item.bestMs ? <span className="lb-dungeon-record">{t("rankings.record")} <b>{duration(item.bestMs)}</b> · <i style={color ? { color } : undefined}>{item.holder ? fullName(item.holder) : ""}</i></span>
          : <span className="lb-dungeon-record">{t("rankings.noRecord")}</span>}
        <small>{t("rankings.runsPlayers", { runs: num(item.runs), players: num(item.players) })}</small>
      </button>;
    })}</div>
  </div>;
}

type Guilds = { guilds: GuildSummary[]; total: number; page: number; pageSize: number; hasMore: boolean; sampleSize: number };

/** Guilds ranked by the raid progress of their shown members, then completions; a faction filter and a search over names. */
function GuildBoard({ state }: { state: RankingState }) {
  const { t, num } = useI18n();
  const board = useApi<Guilds>(`/api/guilds?${rankingQuery(state)}`);
  const [shown, setShown] = useState<Guilds | null>(null);
  if (board.data && board.data !== shown) setShown(board.data);
  const data = board.data ?? shown;
  const [draft, setDraft] = useState(state.q);
  const [seenQ, setSeenQ] = useState(state.q);
  if (seenQ !== state.q) { setSeenQ(state.q); setDraft(state.q); }
  const search = (event: FormEvent) => { event.preventDefault(); go({ ...state, q: draft.trim().slice(0, 80), page: 0 }); };
  const faction = state.filters.faction;
  const filtered = Boolean(state.q || faction || state.filters.realm);
  const pager = data && (state.page > 0 || data.hasMore) ? <Pager page={state.page} hasMore={data.hasMore} onPage={page => go({ ...state, page })} /> : null;
  return (
    <div className="page-column lb">
      <Tabs state={state} />
      <section className="lb-banner" style={{ "--lb-art": `url("${DEFAULT_ART}")` } as CSSProperties}>
        <div className="lb-pills">
          <FactionPill state={state} />
          <RealmPill value={state.filters.realm} onChange={value => go({ ...state, filters: { ...state.filters, realm: value || undefined }, page: 0 })} />
        </div>
        <span className="lb-eyebrow">{t("rankings.eyebrow")}</span>
        <h1 className="lb-title">{t("guild.back")}{state.filters.realm && <span> • {state.filters.realm}</span>}<span> • {faction ? t(faction === "horde" ? "rankings.horde" : "rankings.alliance") : t("rankings.allFactions")}</span></h1>
      </section>
      <div className="lb-bar">
        {pager ?? <span />}
        <form className="lb-search" role="search" onSubmit={search}>
          <label><span className="visually-hidden">{t("rankings.searchLabel")}</span>
            <Icon name="search" size={15} />
            <input type="search" maxLength={80} value={draft} onChange={event => setDraft(event.target.value)} placeholder={t("rankings.guild")} />
          </label>
          <button className="lb-btn" type="submit">{t("rankings.search")}</button>
          {state.q && <button className="lb-btn ghost" type="button" onClick={() => go({ ...state, q: "", page: 0 })}>{t("rankings.clear")}</button>}
        </form>
      </div>
      <div className={`lb-table-wrap${board.loading && shown ? " is-loading" : ""}`} aria-busy={board.loading}>
        <table className="lb-table">
          <thead><tr><th className="lb-rank">{t("rankings.rank")}</th><th>{t("rankings.guild")}</th><th className="num">{t("guild.bosses")}</th></tr></thead>
          <tbody>
            {board.error ? <MessageRow icon="info" title={t("error.service_unavailable")} />
              : !data ? <MessageRow icon="trophy" title={t("common.loading")} />
              : data.guilds.length ? data.guilds.map(g => <GuildRow key={`${g.realm}|${g.name}`} guild={g} />)
              : filtered ? <MessageRow icon="search" title={t("rankings.noMatch")} />
              : <MessageRow icon="shield" title={t("rankings.noGuildsTitle")} action={<a className="lb-btn" href="#account"><Icon name="globe" size={14} /> {t("rankings.makePublic")}</a>}>{t("rankings.noGuildsText")}</MessageRow>}
          </tbody>
        </table>
      </div>
      <div className="lb-foot">
        {pager ?? <span />}
        {data && <span className="lb-count">{t("rankings.guildResults", { count: num(data.total) })} · {t("guild.members")}: {num(data.sampleSize)}</span>}
      </div>
      <details className="lb-about">
        <summary><Icon name="info" size={14} /> {t("rankings.about")}</summary>
        <p>{t("rankings.noteGuilds")}</p>
      </details>
    </div>
  );
}

function GuildRow({ guild: g }: { guild: GuildSummary }) {
  const { t, num } = useI18n();
  const color = g.faction === "horde" ? "#e0503f" : g.faction === "alliance" ? "#6fa3f5" : undefined;
  const sub = [g.realm, t("rankings.membersShort", { count: num(g.members) }), g.maxLevel ? `${t("rankings.lv")} ${g.maxLevel}` : null,
    g.itemLevel != null ? t("rankings.ilvl", { level: g.itemLevel }) : null].filter(Boolean).join(" · ");
  const raids = g.raids.slice(0, 2).map(r => `${r.instanceName} ${r.killed}`).join(" · ");
  return <tr className={g.rank <= 3 ? `lb-top lb-top-${g.rank}` : undefined}>
    <td className="lb-rank">{g.rank}.</td>
    <td>
      <div className="lb-char" style={color ? { "--class": color } as CSSProperties : undefined}>
        <span className="gd-crest small" aria-hidden="true"><Icon name="shield" size={18} /></span>
        <FactionMark faction={g.faction} />
        <span className="lb-who"><a className="profile-name" href={guildHref(g.realm, g.name)}>{g.name}</a><small>{sub}</small></span>
      </div>
    </td>
    <td className="lb-value"><small>{raids || `${t("guild.completions")}: ${num(g.completions)}`}</small><strong>{num(g.bosses)}</strong></td>
  </tr>;
}

/** Realm filter: the realms that have public characters, the largest first. */
function RealmPill({ value, onChange }: { value?: string; onChange: (value: string) => void }) {
  const { t, num } = useI18n();
  const realms = useApi<{ realms: RealmSummary[] }>("/api/leaderboards?metric=realms");
  const list = realms.data?.realms ?? [];
  const known = !value || list.some(r => r.realm.toLowerCase() === value.toLowerCase());
  return <Pill label={t("rankings.realm")} value={value ?? ""} onChange={onChange}>
    <option value="">{t("rankings.allRealms")}</option>
    {!known && value && <option value={value}>{value}</option>}
    {list.map(r => <option key={r.realm} value={r.realm}>{r.realm} ({num(r.characters)})</option>)}
  </Pill>;
}

function FactionPill({ state }: { state: RankingState }) {
  const { t } = useI18n();
  return <Pill label={t("rankings.faction")} value={state.filters.faction ?? ""} onChange={value => go({ ...state, filters: { ...state.filters, faction: value || undefined }, page: 0 })}>
    <option value="">{t("rankings.allFactions")}</option>
    <option value="alliance">{t("rankings.alliance")}</option>
    <option value="horde">{t("rankings.horde")}</option>
  </Pill>;
}

/** The guilds a character search also finds, as links above the table. */
function GuildMatches({ q }: { q: string }) {
  const { t } = useI18n();
  const found = useApi<Guilds>(`/api/guilds?${new URLSearchParams({ q })}`);
  const guilds = found.data?.guilds.slice(0, 8) ?? [];
  if (!guilds.length) return null;
  return <div className="lb-matches"><span>{t("rankings.guildMatches")}:</span>
    {guilds.map(g => <a key={`${g.realm}|${g.name}`} className="lb-guild" href={guildHref(g.realm, g.name)}>&lsaquo;{g.name}&rsaquo; <small>{g.realm}</small></a>)}
  </div>;
}

/** Statistics in the shape of Raider.IO's: who plays what, at which level, and which classes finish dungeons and raids. */
function StatsBoard({ state }: { state: RankingState }) {
  const { t, num } = useI18n();
  const params = new URLSearchParams({ metric: "stats" });
  if (state.filters.faction) params.set("faction", state.filters.faction);
  if (state.filters.realm) params.set("realm", state.filters.realm);
  const stats = useApi<Statistics>(`/api/leaderboards?${params}`);
  const s = stats.data;
  const sides = s ? s.factions.alliance + s.factions.horde : 0;
  return (
    <div className="page-column lb">
      <Tabs state={state} />
      <section className="lb-banner" style={{ "--lb-art": `url("${DEFAULT_ART}")` } as CSSProperties}>
        <div className="lb-pills">
          <FactionPill state={state} />
          <RealmPill value={state.filters.realm} onChange={value => go({ ...state, filters: { ...state.filters, realm: value || undefined }, page: 0 })} />
        </div>
        <span className="lb-eyebrow">{t("rankings.eyebrow")}</span>
        <h1 className="lb-title">{t("rankings.stats")}<span> • {state.filters.faction ? t(state.filters.faction === "horde" ? "rankings.horde" : "rankings.alliance") : t("rankings.allFactions")}</span>{state.filters.realm && <span> • {state.filters.realm}</span>}</h1>
      </section>
      {stats.error ? <div className="lb-grid-note">{t("error.service_unavailable")}</div>
        : !s ? <div className="lb-grid-note">{t("common.loading")}</div>
        : <div className="st-grid">
          <StatCard title={t("stats.factions")} more={t("stats.characters", { count: num(s.characters) })}>
            {sides ? <div className="home-factions">
              <div className="home-split"><i className="alliance" style={{ flexGrow: s.factions.alliance }} /><i className="horde" style={{ flexGrow: s.factions.horde }} /></div>
              <p><span className="alliance">{t("rankings.alliance")} {Math.round(s.factions.alliance / sides * 100)} %</span><span className="horde">{t("rankings.horde")} {Math.round(s.factions.horde / sides * 100)} %</span></p>
            </div> : <p className="ch-empty">{t("common.noData")}</p>}
          </StatCard>
          <StatCard title={t("stats.levels")}>
            <Bars rows={s.levels.map(b => ({ key: String(b.from), label: b.from === b.to ? String(b.from) : `${b.from}–${b.to}`, count: b.count }))} />
          </StatCard>
          <StatCard title={t("stats.classes")}>
            <Bars rows={s.classes.map(c => ({ key: String(c.id), label: CLASSES[c.id] ?? `#${c.id}`, count: c.count, color: CLASS_COLORS[c.id] }))} total={s.characters} />
          </StatCard>
          <StatCard title={t("stats.races")}>
            <Bars rows={s.races.map(r => ({ key: String(r.id), label: RACES[r.id] ?? `#${r.id}`, count: r.count, color: factionOf(r.id) === "horde" ? "#e0503f" : factionOf(r.id) === "alliance" ? "#4f8ff0" : undefined }))} total={s.characters} />
          </StatCard>
          <StatCard title={t("stats.roles")} more={s.roles.unknown ? t("stats.rolesUnknown", { count: num(s.roles.unknown) }) : undefined}>
            <Bars rows={(["tank", "healer", "dps"] as const).map(role => ({ key: role, label: t(`role.${role}`), count: s.roles[role], color: role === "tank" ? "#6fa3f5" : role === "healer" ? "#7fd36b" : "#e0503f" }))} empty={t("rankings.roleNote")} />
          </StatCard>
          <StatCard title={t("stats.runsParty")}>
            <Bars rows={s.runs.party.map(c => ({ key: String(c.id), label: CLASSES[c.id] ?? `#${c.id}`, count: c.count, color: CLASS_COLORS[c.id] }))} empty={t("stats.noRuns")} />
          </StatCard>
          <StatCard title={t("stats.runsRaid")}>
            <Bars rows={s.runs.raid.map(c => ({ key: String(c.id), label: CLASSES[c.id] ?? `#${c.id}`, count: c.count, color: CLASS_COLORS[c.id] }))} empty={t("stats.noRuns")} />
          </StatCard>
        </div>}
      <details className="lb-about">
        <summary><Icon name="info" size={14} /> {t("rankings.about")}</summary>
        <p>{t("stats.note")}</p>
      </details>
    </div>
  );
}

function StatCard({ title, more, children }: { title: string; more?: string; children: ReactNode }) {
  return <section className="ch-card home-panel"><h2>{title}{more && <span className="home-more">{more}</span>}</h2>{children}</section>;
}

/** Horizontal bars, the longest full width; with `total` each row also shows its share. */
function Bars({ rows, total, empty }: { rows: { key: string; label: string; count: number; color?: string }[]; total?: number; empty?: string }) {
  const { t, num } = useI18n();
  const most = Math.max(1, ...rows.map(r => r.count));
  if (!rows.some(r => r.count)) return <p className="ch-empty">{empty ?? t("common.noData")}</p>;
  return <ul className="home-bars st-bars">{rows.map(r => <li key={r.key}>
    <span style={r.color ? { color: r.color } : undefined}>{r.label}</span>
    <i><b style={{ width: `${r.count / most * 100}%`, background: r.color ?? "var(--lb-orange)" }} /></i>
    <em>{num(r.count)}{total ? <small> {Math.round(r.count / total * 100)} %</small> : null}</em>
  </li>)}</ul>;
}

/** The hall of fame: for every raid boss, the guilds that defeated it first. */
function FameBoard({ state }: { state: RankingState }) {
  const { t, num, date } = useI18n();
  const params = new URLSearchParams({ metric: "fame" });
  if (state.filters.faction) params.set("faction", state.filters.faction);
  if (state.filters.realm) params.set("realm", state.filters.realm);
  const fame = useApi<{ raids: FameRaid[]; guilds: number }>(`/api/leaderboards?${params}`);
  const f = fame.data;
  const color = (faction: string | null) => faction === "horde" ? "#e0503f" : faction === "alliance" ? "#6fa3f5" : undefined;
  return (
    <div className="page-column lb">
      <Tabs state={state} />
      <section className="lb-banner" style={{ "--lb-art": `url("${DEFAULT_ART}")` } as CSSProperties}>
        <div className="lb-pills">
          <FactionPill state={state} />
          <RealmPill value={state.filters.realm} onChange={value => go({ ...state, filters: { ...state.filters, realm: value || undefined }, page: 0 })} />
        </div>
        <span className="lb-eyebrow">{t("rankings.eyebrow")}</span>
        <h1 className="lb-title">{t("rankings.fame")}<span> • {state.filters.faction ? t(state.filters.faction === "horde" ? "rankings.horde" : "rankings.alliance") : t("rankings.allFactions")}</span>{state.filters.realm && <span> • {state.filters.realm}</span>}</h1>
      </section>
      <p className="lb-grid-lead fame-lead">{t("fame.lead")}{f ? ` ${t("fame.guilds", { count: num(f.guilds) })}.` : ""}</p>
      {fame.error ? <div className="lb-grid-note">{t("error.service_unavailable")}</div>
        : !f ? <div className="lb-grid-note">{t("common.loading")}</div>
        : !f.raids.length ? <div className="lb-grid-note"><strong>{t("fame.empty")}</strong><p>{t("rankings.noGuildsText")}</p></div>
        : f.raids.map(raid => <section key={raid.instanceId ?? raid.instanceName} className="ch-card fame-raid">
          <h2>{raid.instanceName}</h2>
          <table className="lb-table ch-table">
            <thead><tr><th>{t("fame.boss")}</th>{[1, 2, 3].map(place => <th key={place}>{t("fame.place", { place })}</th>)}</tr></thead>
            <tbody>{raid.bosses.map(boss => <tr key={boss.encounterId}>
              <td>{boss.name ?? `#${boss.encounterId}`}</td>
              {[0, 1, 2].map(i => { const first = boss.firsts[i]; return <td key={i}>{first ? <>
                <a className="lb-guild fame-guild" style={color(first.faction) ? { color: color(first.faction) } : undefined} href={guildHref(first.realm, first.guild)}>{first.guild}</a>
                <small className="fame-when">{date(first.at)}</small></> : <span className="fame-none">—</span>}</td>; })}
            </tr>)}</tbody>
          </table>
        </section>)}
    </div>
  );
}

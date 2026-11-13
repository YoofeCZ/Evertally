"use client";
import { Fragment, useMemo, useState } from "react";
import { useI18n } from "@/lib/i18n";
import { useApi } from "../api";
import type { Entry, Run, User } from "../types";
import { CLASSES, ConsoleWindow, Empty, Icon, RACES, RunTable, duration } from "../ui";
import { filterRuns, summarizeRuns } from "../data";
import { CharacterBadge } from "../Identity";

export function PageHead({ title, lead, children }: { title: string; lead: string; children?: React.ReactNode }) {
  return (
    <header className="page-head page-column">
      <h1 className="serif-heading">{title}</h1>
      <p className="lead">{lead}</p>
      {children}
    </header>
  );
}

function Filters({ runs, value, onChange, extended = false, hideInstance = false }: { runs: Run[]; value: Record<string, string>; onChange: (key: string, v: string) => void; extended?: boolean; hideInstance?: boolean }) {
  const { t } = useI18n();
  const instances = Array.from(new Map(runs.filter((r) => r.instanceId).map((r) => [String(r.instanceId), r.name])).entries());
  return (
    <div className="filters">
      {!hideInstance && <label className="field"><span>{t("runs.dungeon")}</span>
        <select value={value.instanceId ?? ""} onChange={(e) => onChange("instanceId", e.target.value)}>
          <option value="">{t("runs.allInstances")}</option>
          {instances.map(([id, name]) => <option key={id} value={id}>{name}</option>)}
        </select>
      </label>}
      <label className="field"><span>{t("runs.class")}</span>
        <select value={value.classId ?? ""} onChange={(e) => onChange("classId", e.target.value)}>
          <option value="">{t("runs.allClasses")}</option>
          {Object.entries(CLASSES).map(([id, name]) => <option key={id} value={id}>{name}</option>)}
        </select>
      </label>
      <label className="field"><span>{t("runs.race")}</span>
        <select value={value.raceId ?? ""} onChange={(e) => onChange("raceId", e.target.value)}>
          <option value="">{t("runs.allRaces")}</option>
          {Object.entries(RACES).map(([id, name]) => <option key={id} value={id}>{name}</option>)}
        </select>
      </label>
      {extended && <>
        <label className="field"><span>{t("runs.period")}</span><select value={value.periodDays ?? ""} onChange={(e) => onChange("periodDays", e.target.value)}><option value="">{t("runs.allTime")}</option><option value="7">{t("runs.week")}</option><option value="30">{t("runs.month")}</option><option value="90">{t("runs.quarter")}</option></select></label>
        <label className="field"><span>{t("runs.difficulty")}</span><select value={value.difficultyId ?? ""} onChange={(e) => onChange("difficultyId", e.target.value)}><option value="">{t("runs.allDifficulties")}</option>{Array.from(new Set(runs.map((run) => run.difficultyId).filter((id): id is number => id != null))).sort((a, b) => a - b).map((id) => <option key={id} value={id}>#{id}</option>)}</select></label>
        <label className="field"><span>{t("runs.finish")}</span><select value={value.completion ?? ""} onChange={(e) => onChange("completion", e.target.value)}><option value="">{t("runs.allFinishes")}</option><option value="last_boss">{t("result.last_boss")}</option><option value="full_clear">{t("result.full_clear")}</option></select></label>
        <label className="field"><span>{t("runs.minLevel")}</span><input type="number" min="1" max="1000" value={value.minLevel ?? ""} onChange={(e) => onChange("minLevel", e.target.value)} /></label>
        <label className="field"><span>{t("runs.maxLevel")}</span><input type="number" min="1" max="1000" value={value.maxLevel ?? ""} onChange={(e) => onChange("maxLevel", e.target.value)} /></label>
      </>}
    </div>
  );
}

export function RunsView({ user }: { user: User | null }) {
  const { t, num } = useI18n();
  const [mine, setMine] = useState(false);
  const [query, setQuery] = useState("");
  const [filters, setFilters] = useState<Record<string, string>>({});
  const [now] = useState(() => Date.now() / 1000);
  const runs = useApi<{ runs: Run[] }>(mine && user ? "/api/runs?mine=1" : "/api/runs");
  const all = useMemo(() => runs.data?.runs ?? [], [runs.data]);
  const shown = filterRuns(all, filters, query, now);
  const summary = summarizeRuns(shown);
  return (
    <>
      <PageHead title={t("runs.title")} lead={t("runs.lead")} />
      <div className="page-column">
        <ConsoleWindow title={<>evertally <span>/</span> {t("nav.runs").toLowerCase()}</>}
          actions={<span className="muted mono">{num(shown.length)}</span>}>
          <div className="toolbar">
            <div className="segmented">
              <button className={!mine ? "on" : ""} onClick={() => setMine(false)}>{t("runs.community")}</button>
              <button className={mine ? "on" : ""} onClick={() => setMine(true)} disabled={!user}>{t("runs.mine")}</button>
            </div>
            <label className="search"><Icon name="search" size={16} /><input value={query} onChange={(e) => setQuery(e.target.value)} placeholder={t("runs.searchPlaceholder")} aria-label={t("common.search")} /></label>
          </div>
          <Filters runs={all} value={filters} extended onChange={(k, v) => setFilters((f) => ({ ...f, [k]: v }))} />
          <div className="run-summary" aria-label={t("runs.statsNote")}>
            {[[t("runs.statVisits"), num(summary.visits)], [t("runs.statCompleted"), num(summary.completed)], [t("runs.statUnfinished"), num(summary.unfinished)], [t("runs.statBest"), duration(summary.bestMs)], [t("runs.statMedian"), duration(summary.medianMs)]].map(([label, value]) => <div key={label}><strong className="mono">{runs.loading || runs.error ? "—" : value}</strong><span>{label}</span></div>)}
          </div>
          <p className="fine-print">{t("runs.statsNote")}</p><p className="fine-print">{summary.comparable ? t("runs.timingSample", { count: summary.timed }) : t("runs.timingGuide")}</p>
          {runs.error ? <p className="notice error" role="alert">{t("error.service_unavailable")}</p> : shown.length ? <RunTable runs={shown} /> : (
            <Empty icon="sword" title={runs.loading ? t("common.loading") : all.length ? t("runs.noMatch") : t("runs.emptyTitle")}>{t("runs.emptyText")}</Empty>
          )}
        </ConsoleWindow>
      </div>
    </>
  );
}

export function RankingsView() {
  const { t, num, lang } = useI18n();
  const [metric, setMetric] = useState<"level" | "count" | "time" | "dps" | "hps">("level");
  const metricTitle=metric==="level"?(lang==="cs"?"Úroveň":"Level"):metric==="count"?t("rankings.count"):metric==="time"?t("rankings.time"):metric.toUpperCase();
  const [filters, setFilters] = useState<Record<string, string>>({});
  const [draft, setDraft] = useState("");
  const [search, setSearch] = useState("");
  const [page, setPage] = useState(0);
  const query = new URLSearchParams({ metric, page:String(page), ...(search ? {q:search} : {}), ...Object.fromEntries(Object.entries(filters).filter(([, v]) => v)) });
  const board = useApi<{ entries: Entry[]; sampleSize: number; rulesLabel: string; total:number; page:number; hasMore:boolean }>(`/api/leaderboards?${query}`);
  const runs = useApi<{ runs: Run[] }>("/api/runs");
  const entries = board.data?.entries ?? [];
  return (
    <>
      <PageHead title={t("rankings.title")} lead={metric === "level"
        ? (lang === "cs" ? "Úrovně veřejně sdílených postav." : "Levels of publicly shared characters.")
        : t("rankings.lead")} />
      <div className="page-column ranking-hall">
        <div className="hall-heading"><div><span className="hall-eyebrow">EVERTALLY / {lang === "cs" ? "SÍŇ VÝSLEDKŮ" : "HALL OF RECORDS"}</span><h2>{metricTitle}</h2></div><div className="hall-sample"><span>{t("rankings.sample")}</span><strong>{board.data ? num(board.data.sampleSize) : "—"}</strong></div></div>
        <ConsoleWindow title={<>{t("nav.rankings").toLowerCase()} <span>/</span> {metricTitle}</>}
          actions={<span className="muted mono">{t("rankings.sample")}: {num(board.data?.sampleSize)}</span>}>
          <div className="toolbar">
            <div className="segmented">
              {(["level","count","time","dps","hps"] as const).map(m=><button key={m} className={metric===m?"on":""} aria-pressed={metric===m} onClick={()=>{setMetric(m);setPage(0);}}>{m==="level"?(lang==="cs"?"Úroveň":"Level"):m==="count"?t("rankings.count"):m==="time"?t("rankings.time"):m.toUpperCase()}</button>)}
            </div>
            {metric!=="level" && <label className="field"><span>{lang==="cs"?"Kategorie":"Category"}</span><select value={filters.instanceType??""} onChange={e=>{setFilters(f=>({...f,instanceType:e.target.value}));setPage(0);}}><option value="">{lang==="cs"?"Vše":"All"}</option><option value="party">{lang==="cs"?"Dungeony":"Dungeons"}</option><option value="raid">{lang==="cs"?"Raidy":"Raids"}</option></select></label>}
          </div>
          <p className="fine-print">{metric==="level"?(lang==="cs"?"Úrovně veřejně sdílených postav. Shodné úrovně řadíme podle identifikátoru postavy; úroveň předmětů není dostupná.":"Levels of publicly shared characters. Ties are ordered by character ID; item level is unavailable."):(lang==="cs"?"Pozorované průchody a bojová měření. Nejde o ověřené soutěžní skóre; chybějící a částečná DPS/HPS se neřadí. Pro časy a DPS/HPS vyber konkrétní instanci.":"Observed participations and combat measurements, not verified competitive scores. Missing/partial DPS/HPS is excluded. Select one instance for times and combat rates.")}</p>
          <Filters runs={runs.data?.runs ?? []} value={filters} hideInstance={metric==="level"} onChange={(k, v) => {setFilters((f) => ({ ...f, [k]: v }));setPage(0);}} />
          <form className="hall-search" role="search" onSubmit={e=>{e.preventDefault();setSearch(draft.trim().slice(0,80));setPage(0);}}><label className="field"><span>{lang==="cs"?"Hledat hráče nebo realm":"Search player or realm"}</span><input type="search" maxLength={80} value={draft} onChange={e=>setDraft(e.target.value)} placeholder={lang==="cs"?"Jméno nebo realm":"Name or realm"} /></label><button className="btn btn-sm" type="submit">{lang==="cs"?"Hledat":"Search"}</button>{search&&<button type="button" className="btn btn-sm btn-ghost" onClick={()=>{setSearch("");setDraft("");setPage(0);}}>{lang==="cs"?"Vymazat":"Clear"}</button>}</form>
          {board.data && <div className="hall-results">{lang==="cs"?"Postav ve výsledcích":"Characters in results"}: <strong>{num(board.data.total)}</strong></div>}
          {board.error ? <p className="notice error" role="alert">{t("error.service_unavailable")}</p> : entries.length ? (
            <div className="table-wrap">
              <table className="data-table hall-table">
                <thead><tr><th>{t("rankings.rank")}</th><th>{t("runs.character")}</th><th className="num">{metricTitle}</th></tr></thead>
                <tbody>{entries.map((e) => (
                  <tr key={e.character.id}>
                    <td className="mono rank">{String(e.rank).padStart(2, "0")}</td>
                    <td><CharacterBadge character={e.character} unnamed={t("common.private")} /></td>
                    <td className="num mono">{metric === "time" ? duration(e.value??e.bestMs) : metric==="count"?num(e.count):e.value==null?"—":new Intl.NumberFormat(lang==="cs"?"cs-CZ":"en-GB",{maximumFractionDigits:1}).format(e.value)}{e.instanceName && <small>{e.instanceName}</small>}</td>
                  </tr>))}
                </tbody>
              </table>
            </div>
          ) : <Empty icon="trophy" title={board.loading ? t("common.loading") : t("common.noData")}>{search?(lang==="cs"?"Hráč nebyl nalezen. Zkus upravit hledání nebo filtry.":"No player found. Try a different search or filters."):metric==="level"?(lang==="cs"?"Žádná veřejně sdílená postava s dostupnou úrovní.":"No public characters with a recorded level."):metric === "time" ? t("rankings.timeEmpty") : t("rankings.countEmpty")}</Empty>}
          {board.data && (page>0||board.data.hasMore) && <nav className="hall-pagination" aria-label={lang==="cs"?"Stránky žebříčku":"Leaderboard pages"}><button className="btn btn-sm btn-ghost" disabled={page===0} onClick={()=>setPage(0)}>{lang==="cs"?"První":"First"}</button><button className="btn btn-sm btn-ghost" disabled={page===0} onClick={()=>setPage(page-1)}>{lang==="cs"?"Předchozí":"Previous"}</button><span>{page+1}</span><button className="btn btn-sm btn-ghost" disabled={!board.data.hasMore} onClick={()=>setPage(page+1)}>{lang==="cs"?"Další":"Next"}</button></nav>}
        </ConsoleWindow>
      </div>
    </>
  );
}

"use client";
import { Fragment, useMemo, useState } from "react";
import { useI18n } from "@/lib/i18n";
import { useApi } from "../api";
import type { Entry, Run, User } from "../types";
import { CLASSES, ConsoleWindow, Empty, Icon, RACES, RunTable, duration } from "../ui";
import { filterRuns, summarizeRuns } from "../data";
import { CharacterBadge, GameIcon } from "../Identity";

export function PageHead({ title, lead, children }: { title: string; lead: string; children?: React.ReactNode }) {
  return (
    <header className="page-head page-column">
      <h1 className="serif-heading">{title}</h1>
      <p className="lead">{lead}</p>
      {children}
    </header>
  );
}

function Filters({ runs, value, onChange, extended = false }: { runs: Run[]; value: Record<string, string>; onChange: (key: string, v: string) => void; extended?: boolean }) {
  const { t } = useI18n();
  const instances = Array.from(new Map(runs.filter((r) => r.instanceId).map((r) => [String(r.instanceId), r.name])).entries());
  return (
    <div className="filters">
      <label className="field"><span>{t("runs.dungeon")}</span>
        <select value={value.instanceId ?? ""} onChange={(e) => onChange("instanceId", e.target.value)}>
          <option value="">{t("runs.allInstances")}</option>
          {instances.map(([id, name]) => <option key={id} value={id}>{name}</option>)}
        </select>
      </label>
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
  const [metric, setMetric] = useState<"count" | "time" | "dps" | "hps">("count");
  const metricTitle=metric==="count"?t("rankings.count"):metric==="time"?t("rankings.time"):metric.toUpperCase();
  const [filters, setFilters] = useState<Record<string, string>>({});
  const query = new URLSearchParams({ metric, ...Object.fromEntries(Object.entries(filters).filter(([, v]) => v)) });
  const board = useApi<{ entries: Entry[]; sampleSize: number; rulesLabel: string }>(`/api/leaderboards?${query}`);
  const runs = useApi<{ runs: Run[] }>("/api/runs");
  const entries = board.data?.entries ?? [];
  return (
    <>
      <PageHead title={t("rankings.title")} lead={t("rankings.lead")} />
      <div className="page-column">
        <ConsoleWindow title={<>{t("nav.rankings").toLowerCase()} <span>/</span> {metricTitle}</>}
          actions={<span className="muted mono">{t("rankings.sample")}: {num(board.data?.sampleSize)}</span>}>
          <div className="toolbar">
            <div className="segmented">
              <button className={metric === "count" ? "on" : ""} onClick={() => setMetric("count")}>{t("rankings.count")}</button>
              <button className={metric === "time" ? "on" : ""} onClick={() => setMetric("time")}>{t("rankings.time")}</button>
              <button className={metric === "dps" ? "on" : ""} onClick={() => setMetric("dps")}>DPS</button>
              <button className={metric === "hps" ? "on" : ""} onClick={() => setMetric("hps")}>HPS</button>
            </div>
            <label className="field"><span>{lang==="cs"?"Kategorie":"Category"}</span><select value={filters.instanceType??""} onChange={e=>setFilters(f=>({...f,instanceType:e.target.value}))}><option value="">{lang==="cs"?"Vše":"All"}</option><option value="party">{lang==="cs"?"Dungeony":"Dungeons"}</option><option value="raid">{lang==="cs"?"Raidy":"Raids"}</option></select></label>
          </div>
          <p className="fine-print">{lang==="cs"?"Pozorované průchody a bojová měření. Nejde o ověřené soutěžní skóre; chybějící a částečná DPS/HPS se neřadí. Pro časy a DPS/HPS vyber konkrétní instanci.":"Observed participations and combat measurements, not verified competitive scores. Missing/partial DPS/HPS is excluded. Select one instance for times and combat rates."}</p>
          <Filters runs={runs.data?.runs ?? []} value={filters} onChange={(k, v) => setFilters((f) => ({ ...f, [k]: v }))} />
          {board.error ? <p className="notice error" role="alert">{t("error.service_unavailable")}</p> : entries.length ? (
            <div className="table-wrap">
              <table className="data-table">
                <thead><tr><th>{t("rankings.rank")}</th><th>{t("runs.character")}</th><th>{t("runs.class")} / {t("runs.race")}</th><th className="num">{metricTitle}</th></tr></thead>
                <tbody>{entries.map((e) => (
                  <tr key={e.character.id}>
                    <td className="mono rank">{String(e.rank).padStart(2, "0")}</td>
                    <td><CharacterBadge character={e.character} unnamed={t("common.private")} /><small>{e.character.realm ?? ""}</small></td>
                    <td><span className="character-badge"><GameIcon group="classes" id={e.character.classId} label={CLASSES[e.character.classId ?? 0] ?? "—"} size={22} />{CLASSES[e.character.classId ?? 0] ?? "—"}</span><small><GameIcon group="races" id={e.character.raceId} label={RACES[e.character.raceId ?? 0] ?? "—"} size={18} /> {RACES[e.character.raceId ?? 0] ?? ""}</small></td>
                    <td className="num mono">{metric === "time" ? duration(e.value??e.bestMs) : metric==="count"?num(e.count):e.value==null?"—":new Intl.NumberFormat(lang==="cs"?"cs-CZ":"en-GB",{maximumFractionDigits:1}).format(e.value)}</td>
                  </tr>))}
                </tbody>
              </table>
            </div>
          ) : <Empty icon="trophy" title={board.loading ? t("common.loading") : t("common.noData")}>{metric === "time" ? t("rankings.timeEmpty") : t("rankings.countEmpty")}</Empty>}
        </ConsoleWindow>
      </div>
    </>
  );
}

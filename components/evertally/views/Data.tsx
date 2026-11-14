"use client";
import { Fragment, useMemo, useState } from "react";
import { useI18n } from "@/lib/i18n";
import { useApi } from "../api";
import type { Run, User } from "../types";
import { CLASSES, ConsoleWindow, Empty, Icon, RACES, RunTable, duration } from "../ui";
import { FOREVER_CLASS_IDS, FOREVER_RACE_IDS, filterRuns, summarizeRuns } from "../data";

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
          {FOREVER_CLASS_IDS.map((id) => <option key={id} value={id}>{CLASSES[id]}</option>)}
        </select>
      </label>
      <label className="field"><span>{t("runs.race")}</span>
        <select value={value.raceId ?? ""} onChange={(e) => onChange("raceId", e.target.value)}>
          <option value="">{t("runs.allRaces")}</option>
          {FOREVER_RACE_IDS.map((id) => <option key={id} value={id}>{RACES[id]}</option>)}
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

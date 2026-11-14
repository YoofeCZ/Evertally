"use client";
import { useMemo, useState, type CSSProperties } from "react";
import { useI18n } from "@/lib/i18n";
import { useApi } from "../api";
import type { Run, User } from "../types";
import { CLASSES, Empty, Icon, RACES, RunTable, duration } from "../ui";
import { FOREVER_CLASS_IDS, FOREVER_RACE_IDS, filterRuns, summarizeRuns } from "../data";
import { Pill } from "./Rankings";

export function PageHead({ title, lead, children }: { title: string; lead: string; children?: React.ReactNode }) {
  return (
    <header className="page-head page-column">
      <h1 className="serif-heading">{title}</h1>
      <p className="lead">{lead}</p>
      {children}
    </header>
  );
}

const ART = "/media/dungeons/blackrock-depths.jpg";

/** Runs in the same shape as the leaderboard: art banner with filter pills, the numbers in a row, one dense table. */
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
  const set = (key: string, value: string) => setFilters((f) => ({ ...f, [key]: value }));
  const instances = Array.from(new Map(all.filter((r) => r.instanceId).map((r) => [String(r.instanceId), r.name])).entries()).sort((a, b) => a[1].localeCompare(b[1]));
  const difficulties = Array.from(new Set(all.map((run) => run.difficultyId).filter((id): id is number => id != null))).sort((a, b) => a - b);
  const instanceName = instances.find(([id]) => id === filters.instanceId)?.[1];
  const crumbs = [mine ? t("runs.mine") : t("runs.community"), instanceName ?? t("runs.allInstances"),
    filters.classId ? CLASSES[Number(filters.classId)] : t("runs.allClasses"), filters.raceId ? RACES[Number(filters.raceId)] : t("runs.allRaces")];
  const stats: [string, string][] = [[t("runs.statVisits"), num(summary.visits)], [t("runs.statCompleted"), num(summary.completed)], [t("runs.statUnfinished"), num(summary.unfinished)], [t("runs.statBest"), duration(summary.bestMs)], [t("runs.statMedian"), duration(summary.medianMs)]];

  return (
    <div className="page-column lb lb-runs">
      <section className="lb-banner" style={{ "--lb-art": `url("${ART}")` } as CSSProperties}>
        <div className="lb-pills">
          <Pill label={t("runs.view")} accent value={mine ? "mine" : ""} onChange={(v) => setMine(v === "mine")}>
            <option value="">{t("runs.community")}</option>
            <option value="mine" disabled={!user}>{t("runs.mine")}</option>
          </Pill>
          <Pill label={t("runs.dungeon")} value={filters.instanceId ?? ""} onChange={(v) => set("instanceId", v)}>
            <option value="">{t("runs.allInstances")}</option>
            {instances.map(([id, name]) => <option key={id} value={id}>{name}</option>)}
          </Pill>
          <Pill label={t("runs.class")} value={filters.classId ?? ""} onChange={(v) => set("classId", v)}>
            <option value="">{t("runs.allClasses")}</option>
            {FOREVER_CLASS_IDS.map((id) => <option key={id} value={id}>{CLASSES[id]}</option>)}
          </Pill>
          <Pill label={t("runs.race")} value={filters.raceId ?? ""} onChange={(v) => set("raceId", v)}>
            <option value="">{t("runs.allRaces")}</option>
            {FOREVER_RACE_IDS.map((id) => <option key={id} value={id}>{RACES[id]}</option>)}
          </Pill>
          <Pill label={t("runs.period")} value={filters.periodDays ?? ""} onChange={(v) => set("periodDays", v)}>
            <option value="">{t("runs.allTime")}</option><option value="7">{t("runs.week")}</option><option value="30">{t("runs.month")}</option><option value="90">{t("runs.quarter")}</option>
          </Pill>
          <Pill label={t("runs.difficulty")} value={filters.difficultyId ?? ""} onChange={(v) => set("difficultyId", v)}>
            <option value="">{t("runs.allDifficulties")}</option>
            {difficulties.map((id) => <option key={id} value={id}>#{id}</option>)}
          </Pill>
          <Pill label={t("runs.finish")} value={filters.completion ?? ""} onChange={(v) => set("completion", v)}>
            <option value="">{t("runs.allFinishes")}</option><option value="last_boss">{t("result.last_boss")}</option><option value="full_clear">{t("result.full_clear")}</option>
          </Pill>
        </div>
        <span className="lb-eyebrow">{t("runs.eyebrow")}</span>
        <h1 className="lb-title">{t("runs.title")}{crumbs.map((crumb) => <span key={crumb}> • {crumb}</span>)}</h1>
      </section>

      <div className="lb-bar">
        <div className="lb-levels">
          <label><span>{t("runs.minLevel")}</span><input type="number" min="1" max="1000" value={filters.minLevel ?? ""} onChange={(e) => set("minLevel", e.target.value)} /></label>
          <label><span>{t("runs.maxLevel")}</span><input type="number" min="1" max="1000" value={filters.maxLevel ?? ""} onChange={(e) => set("maxLevel", e.target.value)} /></label>
        </div>
        <div className="lb-search"><label><span className="visually-hidden">{t("common.search")}</span><Icon name="search" size={15} />
          <input type="search" value={query} onChange={(e) => setQuery(e.target.value)} placeholder={t("runs.searchPlaceholder")} /></label></div>
      </div>

      <div className="lb-stats" aria-label={t("runs.statsNote")}>
        {stats.map(([label, value]) => <div className="ch-stat" key={label}><small>{label}</small><strong>{runs.loading || runs.error ? "—" : value}</strong></div>)}
      </div>

      <div className="lb-table-wrap lb-runtable">
        {runs.error ? <p className="lb-grid-note" role="alert">{t("error.service_unavailable")}</p> : shown.length ? <RunTable runs={shown} /> : (
          <Empty icon="sword" title={runs.loading ? t("common.loading") : all.length ? t("runs.noMatch") : t("runs.emptyTitle")}>{t("runs.emptyText")}</Empty>
        )}
      </div>
      <details className="lb-about">
        <summary><Icon name="info" size={14} /> {t("runs.about")}</summary>
        <p>{t("runs.statsNote")}</p>
        <p>{summary.comparable ? t("runs.timingSample", { count: summary.timed }) : t("runs.timingGuide")}</p>
      </details>
    </div>
  );
}

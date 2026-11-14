"use client";
import type { CSSProperties, ReactNode } from "react";
import { hasKey, useI18n } from "@/lib/i18n";
import { useApi } from "../api";
import { CLASS_COLORS, CLASSES, RACES, completed, duration, factionOf } from "../data";
import { CharacterIcons, fullName } from "../Identity";
import type { Character, Run } from "../types";
import { Icon } from "../ui";
import { FactionMark } from "./Rankings";

type Page = {
  profile: Character & { public: boolean; lastSeen?: number };
  zones: { mapId: number; mapName?: string; visits: number; lastVisited?: number }[];
  runs: Run[];
  itemLevel?: number; guild?: string;
  ranks: { overall: number | null; total: number; class: number | null; classTotal: number } | null;
};
const ART = "/media/dungeons/blackrock-depths.jpg";

/** A character's own page in the shape of a Raider.IO profile: banner, the numbers that rank it, its runs and places. */
export function CharacterView({ id }: { id: string }) {
  const { t, num, date } = useI18n();
  const page = useApi<Page>(id ? `/api/profiles/${encodeURIComponent(id)}` : null);
  if (!id || page.error) return <div className="page-column lb ch">
    <div className="lb-message ch-missing"><span className="lb-message-icon"><Icon name="lock" size={20} /></span>
      <strong>{t("character.notFoundTitle")}</strong><p>{t("character.notFoundText")}</p>
      <a className="lb-btn" href="#rankings">← {t("character.back")}</a></div>
  </div>;
  if (!page.data) return <div className="page-column lb ch"><p className="lb-count">{t("common.loading")}</p></div>;

  const { profile, zones, runs, itemLevel, guild, ranks } = page.data;
  const color = CLASS_COLORS[profile.classId ?? 0];
  const className = CLASSES[profile.classId ?? 0];
  const finished = runs.filter(completed);
  // best time per instance, from finished runs with a measured time
  const best = new Map<string, { name: string; best: number | null; count: number; last: number }>();
  for (const run of finished) {
    const key = String(run.instanceId ?? run.name);
    const time = typeof run.durationMs === "number" && run.durationMs > 0 ? run.durationMs : null;
    const row = best.get(key) ?? { name: run.name, best: null, count: 0, last: 0 };
    row.count++;
    if (time !== null && (row.best === null || time < row.best)) row.best = time;
    row.last = Math.max(row.last, run.startedAt ?? 0);
    best.set(key, row);
  }
  const bestRows = [...best.values()].sort((a, b) => b.count - a.count || a.name.localeCompare(b.name));
  const result = (run: Run) => { const key = `result.${run.completion && completed(run) ? run.completion : run.status ?? "visiting"}`; return hasKey(key) ? t(key) : run.status ?? "—"; };

  return <div className="page-column lb ch">
    <a className="ch-back" href="#rankings">← {t("character.back")}</a>
    <section className="ch-banner" style={{ "--class": color ?? "#ececf0", "--lb-art": `url("${ART}")` } as CSSProperties}>
      <div className="ch-identity">
        <CharacterIcons character={profile} size={56} />
        <div className="ch-name">
          <h1>{fullName(profile) || t("common.private")}</h1>
          {guild && <span className="lb-guild">&lsaquo;{guild}&rsaquo;</span>}
          <p>{[profile.level ? t("character.level", { level: profile.level }) : null, RACES[profile.raceId ?? 0], className].filter(Boolean).join(" · ")}
            <FactionMark faction={factionOf(profile.raceId)} /></p>
        </div>
      </div>
      <div className="ch-stats">
        {itemLevel != null && <Stat label={t("character.ilvl")} value={num(itemLevel)} />}
        {ranks && <Stat label={t("character.rank")} value={ranks.overall ? `#${num(ranks.overall)}` : "—"} sub={t("character.of", { total: num(ranks.total) })} />}
        {ranks && className && <Stat label={t("character.classRank", { class: className })} value={ranks.class ? `#${num(ranks.class)}` : "—"} sub={t("character.of", { total: num(ranks.classTotal) })} />}
        <Stat label={t("character.completions")} value={num(finished.length)} />
      </div>
    </section>
    {!profile.public && <p className="ch-note"><Icon name="lock" size={14} /> {t("character.private")} <a href="#account">{t("nav.account")}</a></p>}

    <div className="ch-grid">
      <div>
        <Card title={t("character.bestTimes")}>
          {bestRows.length ? <table className="lb-table ch-table">
            <thead><tr><th>{t("character.instance")}</th><th className="num">{t("character.best")}</th><th className="num">{t("character.count")}</th><th className="num">{t("character.last")}</th></tr></thead>
            <tbody>{bestRows.map(row => <tr key={row.name}><td>{row.name}</td><td className="num lb-time">{duration(row.best)}</td><td className="num">{num(row.count)}</td><td className="num">{date(row.last)}</td></tr>)}</tbody>
          </table> : <p className="ch-empty">{t("character.noRuns")}</p>}
        </Card>
        <Card title={t("character.recent")}>
          {runs.length ? <table className="lb-table ch-table">
            <thead><tr><th>{t("character.instance")}</th><th>{t("character.result")}</th><th className="num">{t("character.time")}</th><th className="num">{t("character.date")}</th></tr></thead>
            <tbody>{runs.slice(0, 12).map(run => <tr key={run.id}><td>{run.name}</td><td>{result(run)}</td><td className="num">{duration(run.durationMs)}</td><td className="num">{date(run.startedAt)}</td></tr>)}</tbody>
          </table> : <p className="ch-empty">{t("character.noRuns")}</p>}
        </Card>
      </div>
      <div>
        <Card title={`${t("character.zones")} · ${num(zones.length)}`}>
          {zones.length ? <ul className="ch-zones">{zones.slice(0, 14).map(zone => <li key={zone.mapId}><span>{zone.mapName || `#${zone.mapId}`}<small>{date(zone.lastVisited)}</small></span><b>{num(zone.visits)}×</b></li>)}</ul>
            : <p className="ch-empty">{t("character.noZones")}</p>}
        </Card>
        <Card title={t("character.more")}>
          <a className="ch-link" href={`#armory/${encodeURIComponent(profile.id)}`}><Icon name="shield" size={15} /> {t("character.armory")}</a>
          <a className="ch-link" href={`#rankings/level?q=${encodeURIComponent(profile.name ?? "")}`}><Icon name="trophy" size={15} /> {t("character.inLeaderboard")}</a>
        </Card>
      </div>
    </div>
  </div>;
}

function Stat({ label, value, sub }: { label: string; value: ReactNode; sub?: string }) {
  return <div className="ch-stat"><small>{label}</small><strong>{value}</strong>{sub && <span>{sub}</span>}</div>;
}

function Card({ title, children }: { title: string; children: ReactNode }) {
  return <section className="ch-card"><h2>{title}</h2>{children}</section>;
}

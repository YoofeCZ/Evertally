"use client";
import { useState, type CSSProperties, type ReactNode } from "react";
import { hasKey, useI18n } from "@/lib/i18n";
import { ApiFailure, api, useApi } from "../api";
import { CLASS_COLORS, CLASSES, RACES, completed, duration, factionOf } from "../data";
import { CharacterIcons, fullName } from "../Identity";
import type { Character, Run } from "../types";
import { Icon } from "../ui";
import { FactionMark } from "./Rankings";
import { RaidProgressCard } from "./Guild";
import { guildHref } from "../rankingRoute";
import type { RaidProgress } from "@/lib/guilds";
import type { PublicGear } from "@/lib/public-gear";
import { Gear, Stats, Talents } from "./Armory";

type Page = {
  profile: Character & { public: boolean; lastSeen?: number };
  zones: { mapId: number; mapName?: string; visits: number; lastVisited?: number }[];
  runs: Run[];
  itemLevel?: number; guild?: string;
  ranks: { overall: number | null; total: number; class: number | null; classTotal: number; realm?: number | null; realmTotal?: number } | null;
  progress?: RaidProgress[];
  armory?: PublicGear;
  spec?: { name: string; points: string; roles: ("tank" | "healer" | "dps")[] };
  levels?: { level: number; at: number }[];
};
const ART = "/media/dungeons/blackrock-depths.jpg";

/** A character's own page in the shape of a Raider.IO profile: banner, the numbers that rank it, its runs and places. */
export function CharacterView({ id }: { id: string }) {
  const { t, num, date, lang } = useI18n();
  const page = useApi<Page>(id ? `/api/profiles/${encodeURIComponent(id)}` : null);
  if (!id || page.error) return <div className="page-column lb ch">
    <div className="lb-message ch-missing"><span className="lb-message-icon"><Icon name="lock" size={20} /></span>
      <strong>{t("character.notFoundTitle")}</strong><p>{t("character.notFoundText")}</p>
      <a className="lb-btn" href="#rankings">← {t("character.back")}</a></div>
  </div>;
  if (!page.data) return <div className="page-column lb ch"><p className="lb-count">{t("common.loading")}</p></div>;

  const { profile, zones, runs, itemLevel, guild, ranks, progress = [], armory, spec, levels = [] } = page.data;
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
          {guild && <a className="lb-guild" href={guildHref(profile.realm, guild)}>&lsaquo;{guild}&rsaquo;</a>}
          <p>{[profile.level ? t("character.level", { level: profile.level }) : null, RACES[profile.raceId ?? 0], spec ? `${spec.name} ${className ?? ""}`.trim() : className, spec?.points, ...(spec?.roles ?? []).map(role => t(`role.${role}`))].filter(Boolean).join(" · ")}
            <FactionMark faction={factionOf(profile.raceId)} /></p>
        </div>
      </div>
      <div className="ch-stats">
        {itemLevel != null && <Stat label={t("character.ilvl")} value={num(itemLevel)} />}
        {ranks && <Stat label={t("character.rank")} value={ranks.overall ? `#${num(ranks.overall)}` : "—"} sub={t("character.of", { total: num(ranks.total) })} />}
        {ranks && profile.realm && ranks.realmTotal ? <Stat label={t("character.realmRank", { realm: profile.realm })} value={ranks.realm ? `#${num(ranks.realm)}` : "—"} sub={t("character.of", { total: num(ranks.realmTotal) })} /> : null}
        {ranks && className && <Stat label={t("character.classRank", { class: className })} value={ranks.class ? `#${num(ranks.class)}` : "—"} sub={t("character.of", { total: num(ranks.classTotal) })} />}
        <Stat label={t("character.completions")} value={num(finished.length)} />
      </div>
    </section>
    {!profile.public && <p className="ch-note"><Icon name="lock" size={14} /> {t("character.private")} <a href="#account">{t("nav.account")}</a></p>}

    <div className="ch-grid">
      <div>
        {armory && <Card title={`${t("character.gear")} · ${date(armory.observedAt)}`}>
          <div className="ch-gear"><Gear entry={{ armory }} lang={lang} /></div>
        </Card>}
        {armory && armory.talents.length > 0 && <Card title={`${t("character.talents")} · ${armory.talents.map(tree => tree.spent).join("/")}`}>
          <div className="ch-gear"><Talents entry={{ armory }} /></div>
        </Card>}
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
        <RaidProgressCard progress={progress} />
        {levels.length > 1 && <Card title={t("character.levels")}><LevelChart levels={levels} /></Card>}
        {armory && Object.keys(armory.stats).length > 0 && <Card title={t("character.stats")}><div className="ch-gear"><Stats entry={{ armory }} lang={lang} /></div></Card>}
        <Card title={`${t("character.zones")} · ${num(zones.length)}`}>
          {zones.length ? <ul className="ch-zones">{zones.slice(0, 14).map(zone => <li key={zone.mapId}><span>{zone.mapName || `#${zone.mapId}`}<small>{date(zone.lastVisited)}</small></span><b>{num(zone.visits)}×</b></li>)}</ul>
            : <p className="ch-empty">{t("character.noZones")}</p>}
        </Card>
        <Card title={t("character.more")}>
          {guild && <a className="ch-link" href={guildHref(profile.realm, guild)}><Icon name="shield" size={15} /> {t("character.guildLink")}</a>}
          <a className="ch-link" href={`#armory/${encodeURIComponent(profile.id)}`}><Icon name="shield" size={15} /> {t("character.armory")}</a>
          <a className="ch-link" href={`#rankings/level?q=${encodeURIComponent(profile.name ?? "")}`}><Icon name="trophy" size={15} /> {t("character.inLeaderboard")}</a>
          <AskLocation profileId={profile.id} lang={lang} />
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

/** When each level was first reached, as a line: time across, level up. Days only. */
function LevelChart({ levels }: { levels: { level: number; at: number }[] }) {
  const { t, lang } = useI18n();
  // the day only: the hour would tell when the player plays
  const day = (at: number) => new Intl.DateTimeFormat(lang === "cs" ? "cs-CZ" : "en-GB", { day: "numeric", month: "short", timeZone: "UTC" }).format(new Date(at * 1000));
  const points = [...levels].sort((a, b) => a.level - b.level);
  const W = 300, H = 120, P = 8;
  const t0 = Math.min(...points.map(p => p.at)), t1 = Math.max(...points.map(p => p.at));
  const l0 = points[0].level, l1 = points[points.length - 1].level;
  const x = (at: number) => P + (t1 > t0 ? (at - t0) / (t1 - t0) : 1) * (W - 2 * P);
  const y = (level: number) => H - P - (l1 > l0 ? (level - l0) / (l1 - l0) : 1) * (H - 2 * P);
  return <div className="ch-levels">
    <svg viewBox={`0 0 ${W} ${H}`} role="img" aria-label={t("character.levels")}>
      <polyline points={points.map(p => `${x(p.at)},${y(p.level)}`).join(" ")} />
      {points.map(p => <circle key={p.level} cx={x(p.at)} cy={y(p.level)} r={2.6}><title>{t("character.levelReached", { level: p.level, date: day(p.at) })}</title></circle>)}
    </svg>
    <div className="ch-levels-axis"><span>{l0} · {day(t0)}</span><span>{l1} · {day(t1)}</span></div>
  </div>;
}

/** "Where are you?" for any character: the player's own sharing choice decides whether the app answers. */
function AskLocation({ profileId, lang }: { profileId: string; lang: string }) {
  const [note, setNote] = useState("");
  const cs = lang === "cs";
  const ask = async () => {
    try {
      await api("/api/locate", { method: "POST", body: JSON.stringify({ profileId }) });
      setNote(cs ? "Žádost odeslána. Pokud hráč sdílí polohu a jeho aplikace běží, ukáže se na mapě během pár minut." : "Asked. If the player shares their position and their app is running, it shows on the map within a few minutes.");
    } catch (error) {
      const status = error instanceof ApiFailure ? error.status : 0;
      setNote(status === 401 ? (cs ? "Pro žádost se přihlas." : "Sign in to ask.")
        : status === 404 ? (cs ? "Tento hráč s tebou polohu nesdílí." : "This player does not share their position with you.")
        : status === 429 ? (cs ? "Chvíli počkej, ptát se jde jednou za minutu." : "Wait a moment: you can ask once a minute.")
        : (cs ? "Žádost se nepodařila." : "The request failed."));
    }
  };
  return <>
    <button type="button" className="ch-link" onClick={() => void ask()}><Icon name="shield" size={15} /> {cs ? "Kde je tento hráč?" : "Where is this player?"}</button>
    {note && <p className="ch-empty" role="status">{note}</p>}
  </>;
}

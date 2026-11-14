"use client";
import type { CSSProperties, FormEvent, ReactNode } from "react";
import { useI18n } from "@/lib/i18n";
import type { InstanceSummary } from "@/lib/run-rankings";
import { useApi } from "../api";
import { CLASS_COLORS, CLASSES, factionOf } from "../data";
import { useDungeonArt } from "../db/store";
import type { Entity, Entry, Run, Status, View } from "../types";
import { Empty, Icon, RunTable } from "../ui";
import { DungeonGrid, Row } from "./Rankings";

type PackagePlayer = { classId: number | null; raceId: number | null };
const ART = "/media/dungeons/blackrock-depths.jpg";

function searchCharacters(text: string) {
  const q = text.trim().slice(0, 80);
  window.location.hash = `rankings/level${q ? `?q=${encodeURIComponent(q)}` : ""}`;
}
function openInstance(id: number) { window.location.hash = `rankings/time?instance=${id}`; }

/** The home page in the shape of Raider.IO's: a search-first banner, then the board, the instances and the community at a glance. */
export function Overview({ status, go }: { status: Status | null; go: (view: View) => void }) {
  const { t, num, date } = useI18n();
  const board = useApi<{ entries: Entry[]; total: number }>("/api/leaderboards?metric=level");
  const pkg = useApi<{ players: PackagePlayer[]; total: number }>("/api/ranking-package");
  const instances = useApi<{ instances: InstanceSummary[] }>("/api/leaderboards?metric=instances");
  const runs = useApi<{ runs: Run[] }>("/api/runs");
  const atlas = useApi<{ entities: Entity[] }>("/api/atlas");
  const art = useDungeonArt();

  const top = board.data?.entries.slice(0, 8) ?? [];
  const recent = runs.data?.runs.slice(0, 5) ?? [];
  const sightings = [...(atlas.data?.entities ?? [])].sort((a, b) => b.count - a.count).slice(0, 6);
  const players = pkg.data?.players ?? [];
  const classCounts = new Map<number, number>();
  let alliance = 0, horde = 0;
  for (const p of players) {
    if (p.classId) classCounts.set(p.classId, (classCounts.get(p.classId) ?? 0) + 1);
    const faction = factionOf(p.raceId);
    if (faction === "alliance") alliance++; else if (faction === "horde") horde++;
  }
  const classes = [...classCounts.entries()].sort((a, b) => b[1] - a[1]);
  const most = classes[0]?.[1] ?? 1;
  const sides = alliance + horde;
  const search = (event: FormEvent<HTMLFormElement>) => { event.preventDefault(); searchCharacters(String(new FormData(event.currentTarget).get("q") ?? "")); };
  const stats: [string, number | null | undefined][] = [[t("home.statCharacters"), status?.totalCharacters], [t("home.statRuns"), status?.totalRuns], [t("home.statObservations"), status?.totalEvents]];

  return (
    <div className="page-column lb home">
      <section className="home-hero" style={{ "--lb-art": `url("${ART}")` } as CSSProperties}>
        <span className="lb-eyebrow">{t("home.eyebrow")}</span>
        <h1>{t("home.title")}</h1>
        <p>{t("home.lead")}</p>
        <form className="home-search" role="search" onSubmit={search}>
          <Icon name="search" size={18} />
          <input name="q" type="search" maxLength={80} placeholder={t("home.searchPlaceholder")} aria-label={t("nav.search")} />
          <button className="lb-btn" type="submit">{t("common.search")}</button>
        </form>
        <div className="home-actions">
          <a className="lb-btn" href="/downloads/Evertally.zip"><Icon name="download" size={15} /> {t("hero.download")}</a>
          <button className="lb-btn ghost" onClick={() => go("sync")}>{t("hero.sync")} <Icon name="arrow" size={14} /></button>
        </div>
        <div className="home-stats">
          {stats.map(([label, value]) => <div key={label}><strong>{status ? num(value ?? 0) : "—"}</strong><small>{label}</small></div>)}
          <div><strong className="home-date">{date(status?.latestAt)}</strong><small>{t("home.updated")}</small></div>
        </div>
      </section>

      <div className="home-grid">
        <div>
          <Card title={t("home.topTitle")} more={<a href="#rankings">{t("home.allRankings")} →</a>}>
            {top.length ? <table className="lb-table">
              <tbody>{top.map(entry => <Row key={entry.character.id} entry={entry} metric="level" />)}</tbody>
            </table> : <Note icon="trophy" title={board.loading ? t("common.loading") : t("rankings.noPublicTitle")}>
              {!board.loading && <>{t("rankings.noPublicText")} <a href="#account">{t("rankings.makePublic")}</a></>}
            </Note>}
          </Card>
          <Card title={t("home.dungeonsTitle")} more={<a href="#rankings/time">{t("home.allDungeons")} →</a>}>
            <DungeonGrid data={instances.data} failed={Boolean(instances.error)} art={art.data} onPick={openInstance} lead={null} emptyTitle={t("home.noDungeons")} limit={6} />
          </Card>
          <Card title={t("home.recentRuns")} more={<a href="#runs">{t("home.allRuns")} →</a>}>
            {recent.length ? <div className="lb-runtable"><RunTable runs={recent} compact /></div>
              : <Note icon="sword" title={runs.loading ? t("common.loading") : t("runs.emptyTitle")}>{!runs.loading && t("runs.emptyText")}</Note>}
          </Card>
        </div>
        <div>
          <Card title={t("home.factions")}>
            {sides ? <div className="home-factions">
              <div className="home-split"><i className="alliance" style={{ flexGrow: alliance }} /><i className="horde" style={{ flexGrow: horde }} /></div>
              <p><span className="alliance">{t("rankings.alliance")} {Math.round(alliance / sides * 100)} %</span><span className="horde">{t("rankings.horde")} {Math.round(horde / sides * 100)} %</span></p>
            </div> : <p className="ch-empty">{t("common.noData")}</p>}
          </Card>
          <Card title={t("home.classes")} more={pkg.data ? <span>{t("home.sample", { count: num(pkg.data.total) })}</span> : null}>
            {classes.length ? <ul className="home-bars">{classes.map(([id, count]) => <li key={id}>
              <span style={{ color: CLASS_COLORS[id] }}>{CLASSES[id] ?? `#${id}`}</span>
              <i><b style={{ width: `${count / most * 100}%`, background: CLASS_COLORS[id] }} /></i>
              <em>{num(count)}</em>
            </li>)}</ul> : <p className="ch-empty">{t("common.noData")}</p>}
          </Card>
          <Card title={t("home.joinTitle")}>
            <ol className="home-steps">
              <li><strong>{t("home.join1")}</strong><span>{t("home.join1Text")}</span><a href="/downloads/Evertally.zip">{t("hero.download")}</a></li>
              <li><strong>{t("home.join2")}</strong><span>{t("home.join2Text")}</span><button className="link-btn" onClick={() => go("sync")}>{t("hero.sync")}</button></li>
              <li><strong>{t("home.join3")}</strong><span>{t("home.join3Text")}</span><a href="#account">{t("nav.account")}</a></li>
            </ol>
          </Card>
          <Card title={t("home.discoveries")} more={<a href="#atlas">{t("home.allAtlas")} →</a>}>
            {sightings.length ? <ul className="ch-zones">{sightings.map(e => <li key={`${e.kind}:${e.id}`}>
              <span>{e.name}<small>{t(e.kind === "quest" ? "atlas.quest" : e.kind === "npc" ? "atlas.npc" : "atlas.item")}</small></span><b>{num(e.count)}×</b>
            </li>)}</ul> : <p className="ch-empty">{atlas.loading ? t("common.loading") : t("common.noData")}</p>}
          </Card>
        </div>
      </div>
    </div>
  );
}

function Card({ title, more, children }: { title: string; more?: ReactNode; children: ReactNode }) {
  return <section className="ch-card home-panel"><h2>{title}{more && <span className="home-more">{more}</span>}</h2>{children}</section>;
}

function Note({ icon, title, children }: { icon: string; title: string; children?: ReactNode }) {
  return <div className="home-note"><Empty icon={icon} title={title}>{children}</Empty></div>;
}

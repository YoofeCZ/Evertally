"use client";
import { useI18n } from "@/lib/i18n";
import { useApi } from "../api";
import { fullName } from "../Identity";
import type { Entity, Entry, Run, Status, View } from "../types";
import { CLASSES, ConsoleWindow, DuskSky, Empty, Icon, RunTable, SplitFlapBoard, Tag } from "../ui";

export function Overview({ status, go }: { status: Status | null; go: (view: View) => void }) {
  const { t, num, date } = useI18n();
  const runs = useApi<{ runs: Run[] }>("/api/runs");
  const atlas = useApi<{ entities: Entity[] }>("/api/atlas");
  const board = useApi<{ entries: Entry[]; sampleSize: number }>("/api/leaderboards?metric=count");
  const recent = runs.data?.runs.slice(0, 5) ?? [];
  const sightings = [...(atlas.data?.entities ?? [])].sort((a, b) => b.count - a.count).slice(0, 6);

  return (
    <>
      <section className="hero panel-inset">
        <DuskSky />
        <div className="hero-copy">
          <Tag>{t("hero.tag")}</Tag>
          <h1>{t("hero.title")}<br /><span className="accent">{t("hero.titleAccent")}</span></h1>
          <p>{t("hero.subtitle")}</p>
          <div className="button-row center">
            <a className="btn btn-primary btn-lg" href="/downloads/Evertally.zip"><Icon name="download" /> {t("hero.download")}</a>
            <button className="btn btn-glass btn-lg" onClick={() => go("sync")}>{t("hero.sync")} <Icon name="arrow" /></button>
          </div>
        </div>
        <ConsoleWindow className="hero-console" title={<>evertally <span>/</span> {t("nav.runs").toLowerCase()}</>}
          actions={<button className="link-btn" onClick={() => go("runs")}>{t("common.viewAll")} <Icon name="arrow" size={14} /></button>}>
          {recent.length ? <RunTable runs={recent} compact /> : (
            <Empty icon="sword" title={runs.loading ? t("common.loading") : t("runs.emptyTitle")}>{t("runs.emptyText")}</Empty>
          )}
        </ConsoleWindow>
      </section>

      <section className="board-section page-column">
        <div className="board-head">
          <h2 className="serif-heading">{t("board.title")}</h2>
          <span className="status-line"><i className="pulse" /> {t("board.updated")}: {date(status?.latestAt)}</span>
        </div>
        <SplitFlapBoard rows={[
          { label: t("board.runs"), value: status ? status.totalRuns : null },
          { label: t("board.characters"), value: status ? status.totalCharacters : null },
          { label: t("board.observations"), value: status ? status.totalEvents : null },
        ]} />
        <p className="fine-print">{t("board.note")}</p>
      </section>

      <section className="chapter tint-navy panel-inset">
        <div className="chapter-inner page-column">
          <div className="rail" aria-hidden="true"><Icon name="sword" size={16} /><i /></div>
          <div className="chapter-copy">
            <Tag>{t("chapter.runs.tag")}</Tag>
            <h2 className="serif-heading">{t("chapter.runs.title")}</h2>
            <p className="lead">{t("chapter.runs.lead")} <button className="link-btn" onClick={() => go("runs")}>{t("common.learnMore")} <Icon name="arrow" size={14} /></button></p>
          </div>
          <div className="triad">
            {(["boss", "clear", "honest"] as const).map((item, i) => (
              <div key={item}><Icon name={["trophy", "check", "shield"][i]} /><strong>{t(`triad.${item}.title`)}</strong><p>{t(`triad.${item}.text`)}</p></div>
            ))}
          </div>
        </div>
      </section>

      <section className="chapter tint-pine panel-inset">
        <div className="chapter-inner page-column split">
          <div className="rail green" aria-hidden="true"><Icon name="map" size={16} /><i /></div>
          <div className="chapter-copy">
            <Tag tone="green">{t("chapter.atlas.tag")}</Tag>
            <h2 className="serif-heading">{t("chapter.atlas.title")}</h2>
            <p className="lead">{t("chapter.atlas.lead")} <button className="link-btn" onClick={() => go("atlas")}>{t("common.learnMore")} <Icon name="arrow" size={14} /></button></p>
          </div>
          <ConsoleWindow title={<>atlas <span>/</span> {t("atlas.sightings").toLowerCase()}</>}>
            {sightings.length ? (
              <ul className="sighting-list">
                {sightings.map((e) => (
                  <li key={`${e.kind}:${e.id}`}><span className={`node node-${e.kind}`} /><span>{e.name}<small>{t(e.kind === "quest" ? "atlas.quest" : e.kind === "npc" ? "atlas.npc" : "atlas.item")} · ID {e.id}</small></span><b className="mono">{num(e.count)}</b></li>
                ))}
              </ul>
            ) : <Empty icon="map" title={atlas.loading ? t("common.loading") : t("atlas.emptyTitle")}>{t("atlas.emptyText")}</Empty>}
          </ConsoleWindow>
        </div>
      </section>

      <section className="chapter tint-plum panel-inset">
        <div className="chapter-inner page-column split">
          <div className="rail peach" aria-hidden="true"><Icon name="trophy" size={16} /><i /></div>
          <div className="chapter-copy">
            <Tag tone="peach">{t("chapter.community.tag")}</Tag>
            <h2 className="serif-heading">{t("chapter.community.title")}</h2>
            <p className="lead">{t("chapter.community.lead")} <button className="link-btn" onClick={() => go("rankings")}>{t("common.learnMore")} <Icon name="arrow" size={14} /></button></p>
            <div className="quote-card">
              <Icon name="shield" size={20} />
              <strong>{t("chapter.privacy.title")}</strong>
              <p>{t("chapter.privacy.lead")}</p>
            </div>
          </div>
          <ConsoleWindow title={<>{t("nav.rankings").toLowerCase()} <span>/</span> {t("rankings.count").toLowerCase()}</>}>
            {board.data?.entries.length ? (
              <ol className="rank-list">
                {board.data.entries.slice(0, 6).map((entry) => (
                  <li key={entry.character.id}><span className="mono rank">{String(entry.rank).padStart(2, "0")}</span><span>{fullName(entry.character) || t("common.private")}<small>{CLASSES[entry.character.classId ?? 0] ?? ""}</small></span><b className="mono">{num(entry.count)}</b></li>
                ))}
              </ol>
            ) : <Empty icon="trophy" title={board.loading ? t("common.loading") : t("common.noData")}>{t("rankings.countEmpty")}</Empty>}
          </ConsoleWindow>
        </div>
      </section>

      <section className="finale page-column">
        <div className="finale-door" aria-hidden="true"><i /><i /></div>
        <h2>{t("cta.title")}</h2>
        <p>{t("cta.subtitle")}</p>
        <button className="btn btn-boarding" onClick={() => go("sync")}>{t("cta.button")} <Icon name="arrow" /></button>
      </section>
    </>
  );
}

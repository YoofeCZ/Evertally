"use client";
import type { ReactNode } from "react";
import { useI18n } from "@/lib/i18n";
import type { Entity, Run } from "./types";
import { CLASSES, RACES, duration, elapsedBossTime } from "./data";
import { GameIcon } from "./Identity";

const known = (value: unknown) => typeof value === "number" && Number.isFinite(value) ? value : null;
const label = (value: unknown): ReactNode => typeof value === "string" || typeof value === "number" ? value : "—";

function Facts({ entries }: { entries: [string, ReactNode][] }) {
  return <dl className="detail-facts">{entries.map(([name, value]) => <div key={name}><dt>{name}</dt><dd>{value ?? "—"}</dd></div>)}</dl>;
}

function utc(value: number | null | undefined, lang: string) {
  if (value == null || !Number.isFinite(value)) return "—";
  const date = new Date(value * 1000);
  return Number.isFinite(date.getTime()) ? `${new Intl.DateTimeFormat(lang === "cs" ? "cs-CZ" : "en-GB", { dateStyle: "medium", timeStyle: "medium", timeZone: "UTC" }).format(date)} UTC` : "—";
}

export function RunDetails({ run }: { run: Run }) {
  const { t, lang } = useI18n();
  const bosses = run.bosses ?? [];
  const evidence = run.evidence === "api_event" ? t("detail.apiEvent") : run.evidence === "api_snapshot" ? t("detail.apiSnapshot") : run.evidence === "manual" ? t("detail.manual") : t("common.unknown");
  const facts: [string, ReactNode][] = [
    [t("detail.started"), utc(run.startedAt, lang)], [t("detail.ended"), utc(run.endedAt, lang)],
    [t("runs.time"), duration(run.durationMs)], [t("detail.instanceId"), run.instanceId],
    [t("detail.difficulty"), run.difficultyId], [t("detail.groupSize"), run.groupSize],
    [t("detail.groupLevels"), run.minLevel != null && run.maxLevel != null ? `${run.minLevel}–${run.maxLevel}` : null],
    [t("detail.deaths"), run.deaths], [t("detail.ruleset"), run.rulesetId], [t("detail.evidence"), evidence],
    [t("runs.character"), run.character?.name ?? t("common.private")],
    [t("runs.class"), <span key="class" className="character-badge"><GameIcon group="classes" id={run.character?.classId} label={CLASSES[run.character?.classId ?? 0] ?? t("common.unknown")} />{CLASSES[run.character?.classId ?? 0] ?? "—"}</span>], [t("runs.race"), <span key="race" className="character-badge"><GameIcon group="races" id={run.character?.raceId} label={RACES[run.character?.raceId ?? 0] ?? t("common.unknown")} />{RACES[run.character?.raceId ?? 0] ?? "—"}</span>],
    [t("detail.characterLevel"), run.character?.level], [t("detail.realm"), run.character?.realm ?? run.game?.realm],
    [t("detail.build"), run.game?.build],
  ];
  return (
    <section className="record-detail" aria-label={t("detail.runTitle")}>
      <div className="detail-heading"><h3>{t("detail.runTitle")}</h3><span className="mono muted">#{run.instanceId ?? "—"}</span></div>
      <p className="detail-note">{t("detail.runNote")}</p>
      <Facts entries={facts} />
      <h4>{t("detail.bossTimeline")}</h4>
      {bosses.length ? <ol className="boss-timeline">{bosses.map((boss, index) => (
        <li key={`${boss.encounterId ?? boss.name ?? "boss"}:${boss.killedAt ?? index}`}>
          <span className="timeline-node mono">{String(index + 1).padStart(2, "0")}</span>
          <span><strong>{boss.name ?? (boss.encounterId ? `#${boss.encounterId}` : t("detail.unnamedBoss"))}</strong><small>{utc(boss.killedAt, lang)}</small></span>
          <span className="mono split-time">{duration(elapsedBossTime(run, boss.killedAt))}<small>{t("detail.sinceStart")}</small></span>
        </li>))}</ol> : <p className="muted">{t("detail.noBosses")}</p>}
    </section>
  );
}

export function EntityDetails({ entity }: { entity: Entity }) {
  const { t, lang, num } = useI18n();
  const payload = entity.payload ?? {};
  const x = known(payload.x), y = known(payload.y);
  const location = entity.kind === "npc" && payload.positionMethod === "unit_position" && x != null && y != null && x >= 0 && x <= 1 && y >= 0 && y <= 1 ? `${(x * 100).toFixed(1)} · ${(y * 100).toFixed(1)} %` : "—";
  const method = payload.positionMethod === "player_interaction" ? t("detail.playerLocation") : payload.positionMethod === "unit_position" ? t("detail.unitLocation") : t("common.unknown");
  const source = typeof payload.sourceKind === "string" ? ({ corpse: t("detail.corpse"), object: t("detail.object"), gathering: t("detail.gathering"), craft: t("detail.craft"), quest: t("atlas.quest"), unknown: t("common.unknown") } as Record<string, string>)[payload.sourceKind] ?? t("common.unknown") : "—";
  const facts: [string, ReactNode][] = [
    [t("detail.sightings"), num(entity.count)], [t("atlas.lastSeen"), utc(entity.lastSeen, lang)],
    [t("detail.mapId"), label(payload.mapId)], [t("detail.coordinates"), location],
    [t("detail.positionMethod"), method],
  ];
  if (entity.kind === "quest") facts.push([t("detail.questGiver"), label(payload.npcId)], [t("detail.questXp"), label(payload.xp)], [t("detail.questMoney"), copper(known(payload.money))]);
  if (entity.kind === "npc") facts.push([t("detail.npcLevel"), label(payload.level)]);
  if (entity.kind === "item") facts.push([t("detail.quantity"), label(payload.quantity)], [t("detail.lootSource"), source], [t("detail.sourceNpc"), label(payload.sourceNpcId)], [t("detail.sourceCertain"), typeof payload.sourceCertain === "boolean" ? t(payload.sourceCertain ? "detail.yes" : "detail.no") : "—"]);
  const items = Array.isArray(payload.items) ? payload.items.filter((value): value is Record<string, unknown> => typeof value === "object" && value !== null && !Array.isArray(value)) : [];
  return (
    <section className="record-detail" aria-label={t("detail.entityTitle")}>
      <div className="detail-heading"><h3>{entity.kind === "item" && <GameIcon group="items" id={entity.id} label={entity.name} />} {entity.name}</h3><span className="mono muted">#{entity.id}</span></div>
      <p className="detail-note">{t("detail.entityNote")}</p>
      <Facts entries={facts} />
      {items.length > 0 && <><h4>{t("detail.vendorStock")}</h4><div className="table-wrap"><table className="data-table nested-table">
        <thead><tr><th>{t("atlas.item")}</th><th>{t("detail.price")}</th><th className="num">{t("detail.quantity")}</th></tr></thead>
        <tbody>{items.slice(0, 100).map((item, index) => <tr key={`${item.itemId}:${index}`}><td><GameIcon group="items" id={typeof item.itemId === "number" ? item.itemId : null} label={typeof item.name === "string" ? item.name : `#${item.itemId}`} /> {label(item.name ?? (item.itemId ? `#${item.itemId}` : null))}</td><td className="mono">{copper(known(item.price))}</td><td className="num mono">{item.quantity === -1 ? t("detail.unlimited") : label(item.quantity)}</td></tr>)}</tbody>
      </table></div>{items.length > 100 && <p className="fine-print">{t("detail.firstHundred")}</p>}</>}
    </section>
  );
}

function copper(value: number | null): string {
  if (value == null || value < 0) return "—";
  const amount = Math.floor(value);
  return `${Math.floor(amount / 10000)}g ${Math.floor(amount / 100) % 100}s ${amount % 100}c`;
}

"use client";
import type { ReactNode } from "react";
import { useI18n } from "@/lib/i18n";
import type { CombatMetrics, Entity, Run, RunCombat, RunMember } from "./types";
import { CLASSES, RACES, duration, elapsedBossTime } from "./data";
import { GameIcon } from "./Identity";

const known = (value: unknown) => typeof value === "number" && Number.isFinite(value) ? value : null;
const label = (value: unknown): ReactNode => typeof value === "string" || typeof value === "number" ? value : "—";

/** Unknown/partial coverage is never turned into a zero or a comparable rate. */
export function observedCombatRate(combat: RunCombat | null | undefined, amount: number | undefined, activeMs = combat?.activeMs): number | null {
  if (combat?.coverage !== "observed" || combat.source === "unavailable" || amount == null || !Number.isFinite(amount) || amount < 0 || activeMs == null || !Number.isFinite(activeMs) || activeMs <= 0) return null;
  return amount / (activeMs / 1000);
}

export function combatDisplayRows(run: Run): (RunMember & CombatMetrics & { activeMs?: number })[] {
  const rows = new Map<string, RunMember & CombatMetrics & { activeMs?: number }>();
  for (const member of run.roster ?? []) rows.set(member.guid, { ...member });
  for (const member of run.combat?.players ?? []) rows.set(member.guid, { ...rows.get(member.guid), ...member });
  return [...rows.values()];
}

function CombatDetails({ run, lang }: { run: Run; lang: string }) {
  const cs = lang === "cs", combat = run.combat;
  const rows = combatDisplayRows(run);
  const words = cs ? {
    title: "Bojové statistiky", group: "Součty zaznamenané skupiny", player: "Hráč", role: "Role", damage: "Poškození", healing: "Léčení", overhealing: "Přeléčení", absorbs: "Absorpce", damageTaken: "Přijaté poškození", interrupts: "Přerušení", dispels: "Dispel", deaths: "Smrti", active: "Zaznamenaný čas v boji", covered: "Doba sledování", source: "Zdroj", observed: "Zaznamenané bojové intervaly", partial: "Částečný záznam: součty mohou být neúplné; DPS/HPS se nepočítají.", unavailable: "Bojová data nejsou dostupná. Starší běhy se zpětně nedopočítávají.", note: "DPS a HPS používají zaznamenaný čas v boji, nikoli délku celého průchodu. Pomlčka znamená chybějící údaj; nula je skutečně zaznamenaná nula.", meter: "Herní damage meter", log: "Bojový log", unknown: "Neznámá postava", none: "Bez zaznamenané sestavy",
  } : {
    title: "Combat statistics", group: "Observed group totals", player: "Player", role: "Role", damage: "Damage", healing: "Healing", overhealing: "Overhealing", absorbs: "Absorbs", damageTaken: "Damage taken", interrupts: "Interrupts", dispels: "Dispels", deaths: "Deaths", active: "Recorded combat time", covered: "Observation period", source: "Source", observed: "Observed combat intervals", partial: "Partial coverage: totals may be incomplete; DPS/HPS are not calculated.", unavailable: "Combat data is unavailable. Older runs are not reconstructed retrospectively.", note: "DPS and HPS use recorded combat time, not the whole instance visit. A dash means missing data; zero is an observed zero.", meter: "Game damage meter", log: "Combat log", unknown: "Unknown player", none: "No recorded roster",
  };
  const format = new Intl.NumberFormat(cs ? "cs-CZ" : "en-GB", { maximumFractionDigits: 1 });
  const number = (value: number | null | undefined) => value != null && Number.isFinite(value) && value >= 0 ? format.format(value) : "—";
  const coverage = !combat || combat.coverage === "unavailable" || combat.source === "unavailable" ? words.unavailable : combat.coverage === "partial" ? words.partial : words.observed;
  const source = combat?.source === "damage_meter" ? words.meter : combat?.source === "combat_log" ? words.log : "—";
  const metrics: [string, keyof CombatMetrics][] = [[words.damage, "damage"], [words.healing, "healing"], [words.overhealing, "overhealing"], [words.absorbs, "absorbs"], [words.damageTaken, "damageTaken"], [words.interrupts, "interrupts"], [words.dispels, "dispels"], [words.deaths, "deaths"]];
  return <>
    <h4>{words.title}</h4><p className="detail-note">{coverage}</p>
    {combat && <><h5>{words.group}</h5><Facts entries={[
      [words.source, source], [words.active, duration(combat.activeMs)], [words.covered, duration(combat.coveredMs)],
      ...metrics.map(([name, key]): [string, ReactNode] => [name, number(combat[key])]),
      ["DPS", number(observedCombatRate(combat, combat.damage))], ["HPS", number(observedCombatRate(combat, combat.healing))],
    ]} /></>}
    <p className="fine-print">{words.note}</p>
    {rows.length ? <div className="table-wrap"><table className="data-table nested-table">
      <thead><tr><th>{words.player}</th><th>{words.role}</th><th className="num">{words.damage}</th><th className="num">DPS</th><th className="num">{words.healing}</th><th className="num">HPS</th><th className="num">{words.absorbs}</th><th className="num">{words.damageTaken}</th><th className="num">{words.interrupts}</th><th className="num">{words.dispels}</th><th className="num">{words.deaths}</th><th className="num">{words.overhealing}</th></tr></thead>
      <tbody>{rows.map(player => <tr key={player.guid}>
        <td><span className="character-badge"><GameIcon group="classes" id={player.classId} label={CLASSES[player.classId ?? 0] ?? "—"} size={20} /><GameIcon group="races" id={player.raceId} label={RACES[player.raceId ?? 0] ?? "—"} size={20} /><span>{player.name ?? words.unknown}<small>{[CLASSES[player.classId ?? 0], RACES[player.raceId ?? 0], player.level].filter(Boolean).join(" · ")}</small></span></span></td>
        <td>{player.role ?? "—"}</td><td className="num mono">{number(player.damage)}</td><td className="num mono">{number(observedCombatRate(combat, player.damage, player.activeMs ?? combat?.activeMs))}</td>
        <td className="num mono">{number(player.healing)}</td><td className="num mono">{number(observedCombatRate(combat, player.healing, player.activeMs ?? combat?.activeMs))}</td>
        <td className="num mono">{number(player.absorbs)}</td><td className="num mono">{number(player.damageTaken)}</td><td className="num mono">{number(player.interrupts)}</td><td className="num mono">{number(player.dispels)}</td><td className="num mono">{number(player.deaths)}</td><td className="num mono">{number(player.overhealing)}</td>
      </tr>)}</tbody>
    </table></div> : <p className="muted">{words.none}</p>}
  </>;
}

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
          <span className="mono split-time">{duration(boss.splitMs ?? elapsedBossTime(run, boss.killedAt))}<small>{t("detail.sinceStart")}</small>{boss.durationMs != null && <small>{lang === "cs" ? "Boj" : "Fight"}: {duration(boss.durationMs)}</small>}</span>
        </li>))}</ol> : <p className="muted">{t("detail.noBosses")}</p>}
      <CombatDetails run={run} lang={lang} />
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

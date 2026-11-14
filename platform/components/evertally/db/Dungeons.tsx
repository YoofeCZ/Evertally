"use client";
/* eslint-disable @next/next/no-img-element -- bundled dungeon artwork with explicit size */
import { useDeferredValue, useMemo, useState } from "react";
import { Icon } from "../ui";
import { PoiBadge } from "./icons";
import { useZoneName } from "./Items";
import { MiniMap } from "./MiniMap";
import { ExtraItem, ItemChips, ItemLink, NpcLink, Section, useDb } from "./parts";
import { RESOURCES } from "./guides";
import { FloorMaps, useFloorsFor } from "./Floors";
import { hrefMap, hrefQuest, useDungeonArt, useDungeons, type Dungeon, type DungeonBoss } from "./store";
import { useS } from "./strings";
import { useI18n } from "@/lib/i18n";

const levelText = (lvl: [number, number] | null) => lvl ? (lvl[0] === lvl[1] ? `${lvl[0]}` : `${lvl[0]}–${lvl[1]}`) : "—";

function Banner({ dungeon, height }: { dungeon: Dungeon; height: number }) {
  const art = useDungeonArt();
  const entry = art.data?.[dungeon.key];
  return (
    <div className={`dungeon-banner ${dungeon.type}`} style={{ height }}>
      {entry ? <img src={entry.image} alt="" loading="lazy" decoding="async" /> : <span className="banner-glyph"><PoiBadge kind={dungeon.type === "raid" ? "raid" : "dungeon"} size={56} /></span>}
    </div>
  );
}

// ---------------------------------------------------------------------------------------------------
export function DungeonsGrid() {
  const s = useS();
  const dungeons = useDungeons();
  const [text, setText] = useState("");
  const [type, setType] = useState("");
  const needle = useDeferredValue(text.trim().toLowerCase());
  const entries = useMemo(() => (dungeons.data?.entries ?? [])
    .filter(d => (!needle || d.name.toLowerCase().includes(needle) || d.group?.toLowerCase().includes(needle) || d.location?.toLowerCase().includes(needle)) && (!type || d.type === type))
    .sort((a, b) => (a.lvl?.[0] ?? 99) - (b.lvl?.[0] ?? 99) || a.name.localeCompare(b.name)), [dungeons.data, needle, type]);
  if (dungeons.loading) return <p className="muted">{s.loading}</p>;
  if (dungeons.error) return <div className="notice error">{s.error}</div>;
  return (
    <div>
      <div className="db-filters inline">
        <label className="search"><Icon name="search" size={16} /><input value={text} onChange={e => setText(e.target.value)} placeholder={s.tabDungeons} aria-label={s.tabDungeons} /></label>
        <label className="field"><span>{s.kind}</span><select value={type} onChange={e => setType(e.target.value)}><option value="">{s.all}</option><option value="dungeon">{s.dungeon}</option><option value="raid">{s.raid}</option></select></label>
      </div>
      <div className="rio-columns">{(["raid", "dungeon"] as const).filter(kind => !type || type === kind).map(kind => {
        const rows = entries.filter(d => d.type === kind);
        if (!rows.length) return null;
        return (
          <section key={kind} className="rio-section">
            <h3 className="rio-heading">{kind === "raid" ? s.raid : s.dungeon}<small>{rows.length}</small></h3>
            <div className="rio-panel">
              <div className="rio-title">{kind === "raid" ? s.raid : s.dungeon}</div>
              {rows.map((d, i) => (
                <a key={d.key} className="rio-row" href={`#database/dungeons/${d.key}`}>
                  <span className="rio-rank">{i + 1}</span>
                  <span className="rio-thumb"><Banner dungeon={d} height={46} /></span>
                  <span className="rio-name"><strong>{d.name}</strong><small>{[d.group, d.location].filter(Boolean).join(" · ") || (kind === "raid" ? s.raid : s.dungeon)}</small></span>
                  <span className="rio-stat"><b>{levelText(d.lvl)}</b><small>{s.level}</small></span>
                  <span className="rio-stat"><b>{d.players}</b><small>{d.players > 5 ? "raid" : "party"}</small></span>
                  <span className="rio-pill">{d.bosses.length > 0 ? `${d.bosses.length} ${s.bossCount}` : s.statusPending.split(".")[0]}</span>
                </a>))}
            </div>
          </section>);
      })}</div>
    </div>
  );
}

// ---------------------------------------------------------------------------------------------------
function LootList({ loot, extras }: { loot: DungeonBoss["loot"]; extras: Dungeon["extras"] }) {
  return <div className="loot-grid">{loot.map((entry, i) => {
    if (typeof entry === "number") return <ItemLink key={`${entry}-${i}`} id={entry} />;
    const extra = extras[entry];
    return extra ? <ExtraItem key={`${entry}-${i}`} name={extra[0]} slot={extra[1]} quality={extra[2]} lines={extra[3]} /> : <span key={`${entry}-${i}`} className="chip">{entry}</span>;
  })}</div>;
}

function DungeonFloors({ dungeon }: { dungeon: Dungeon }) {
  const s = useS();
  const { floors } = useFloorsFor(dungeon.key);
  if (!floors.length) return null;
  return (
    <Section title={s.floors} count={floors.length}>
      <FloorMaps dungeonKey={dungeon.key} aside={dungeon.bosses.length ? <><h5 className="aside-title">{s.bossesTitle}</h5><ol className="plain-list boss-order">{dungeon.bosses.map(boss => <li key={boss.name}>{boss.name}</li>)}</ol></> : undefined} />
    </Section>
  );
}

export function DungeonDetailView({ keyName }: { keyName: string }) {
  const s = useS();
  const { lang } = useI18n();
  const { index } = useDb();
  const dungeons = useDungeons();
  const art = useDungeonArt();
  const zoneName = useZoneName();
  const [expand, setExpand] = useState(0);
  if (dungeons.loading) return <p className="muted">{s.loading}</p>;
  const dungeon = dungeons.data?.entries.find(d => d.key === keyName);
  if (!dungeon) return <div className="notice error">{s.noResults} {keyName}</div>;
  const siblings = dungeon.group ? dungeons.data!.entries.filter(d => d.group === dungeon.group && d.key !== dungeon.key) : [];
  const status = dungeon.status === "pending" ? s.statusPending : dungeon.status.includes("classic") ? s.statusClassic : dungeon.status.startsWith("atlas") ? s.statusAtlas : dungeon.status.includes("partial") ? s.statusPartial : s.statusFull;
  const artSource = art.data?.[dungeon.key]?.source;
  const guides = RESOURCES.filter(resource => resource.tags.includes("dungeons") || resource.tags.includes("guides"));
  return (
    <article className="db-detail dungeon-detail">
      <div className="dungeon-hero">
        <Banner dungeon={dungeon} height={220} />
        <div className="hero-text">
          <h2>{dungeon.name}</h2>
          <div className="chips">
            <span className="chip">{dungeon.type === "raid" ? s.raid : s.dungeon}</span>
            {dungeon.group && <span className="chip">{dungeon.group}</span>}
            <span className="chip mono">{s.level} {levelText(dungeon.lvl)}</span>
            <span className="chip">{dungeon.players} {lang === "cs" ? "hráčů" : "players"}</span>
            {dungeon.location && <span className="chip">{dungeon.location}</span>}
          </div>
        </div>
      </div>
      {artSource && <p className="fine-print">{s.artSource[artSource]}</p>}
      <div className={`notice ${dungeon.status === "pending" ? "warn" : ""}`}>{status}</div>

      {siblings.length > 0 && <div className="chips">{siblings.map(d => <a key={d.key} className="chip link" href={`#database/dungeons/${d.key}`}>{d.name}</a>)}</div>}

      <div className="db-columns">
        <div className="db-stack">
          {dungeon.entrance && (
            <Section title={s.entranceTitle}>
              <div className="zone-line"><strong>{zoneName(dungeon.entrance.zone)}</strong><a className="btn btn-ghost btn-sm" href={hrefMap(dungeon.entrance.zone, `dungeon:${dungeon.key}`)}><Icon name="globe" size={14} /> {s.viewOnMap}</a></div>
              <MiniMap zone={dungeon.entrance.zone} points={[[dungeon.entrance.x, dungeon.entrance.y]]} focus={`dungeon:${dungeon.key}`} />
              {dungeon.entrance.hint && <p className="muted small"><strong>{s.hint}:</strong> {dungeon.entrance.hint}</p>}
            </Section>
          )}
        </div>
        <div className="db-stack">
          <Section title={s.resources}>
            <ul className="plain-list">{guides.slice(0, 5).map(resource => <li key={resource.id}><a className="elink" href={resource.url} target="_blank" rel="noreferrer">{resource.name} ↗</a> <span className="muted small">{lang === "cs" ? resource.cs : resource.en}</span></li>)}</ul>
            <a className="btn btn-ghost btn-sm" href="#database/guides">{s.tabGuides}</a>
          </Section>
        </div>
      </div>

      <DungeonFloors dungeon={dungeon} />

      {dungeon.bosses.length > 0 && (
        <Section title={s.bossesTitle} count={dungeon.bosses.length} aside={<span className="btn-row"><button type="button" className="link-btn" onClick={() => setExpand(1)}>{lang === "cs" ? "Rozbalit vše" : "Expand all"}</button><button type="button" className="link-btn" onClick={() => setExpand(2)}>{lang === "cs" ? "Sbalit vše" : "Collapse all"}</button></span>}>
          <div className="boss-list rio-panel">{dungeon.bosses.map((boss, i) => (
            <details key={`${expand}-${boss.name}-${i}`} className="boss rio-boss" open={expand === 1 ? true : expand === 2 ? false : i < 2}>
              <summary>
                <span className="rio-rank">{i + 1}</span>
                <span className="boss-name">{boss.npc ? <NpcLink id={boss.npc}>{boss.name}</NpcLink> : boss.name}</span>
                {boss.rare && <span className="chip warn">{s.rareSpawn}</span>}
                {boss.lvl && <span className="chip mono">{s.level} {boss.lvl}</span>}
                <span className="muted small">{boss.loot.length} {s.itemCount}</span>
              </summary>
              {boss.note && <p className="muted small">{boss.note}</p>}
              {boss.loot.length ? <LootList loot={boss.loot} extras={dungeon.extras} /> : <p className="muted small">{s.statusPending}</p>}
            </details>))}</div>
        </Section>
      )}

      {dungeon.other.length > 0 && <Section title={s.other} count={dungeon.other.length}><ItemChips ids={dungeon.other} /></Section>}

      {dungeon.quests.length > 0 && (
        <Section title={s.questsTitle} count={dungeon.quests.length}>
          <div className="table-wrap"><table className="data-table compact">
            <thead><tr><th>{s.quest}</th><th>{s.level}</th><th>{s.pickup}</th><th>{s.turnIn}</th><th>{s.rewardsLabel}</th></tr></thead>
            <tbody>{dungeon.quests.map(quest => (
              <tr key={quest.id}>
                <td><a className="elink quest" href={hrefQuest(quest.id)}><PoiBadge kind="qs" size={16} /><span>{quest.name}</span></a>{quest.fac && quest.fac !== "Both" && <span className="chip small">{quest.fac}</span>}</td>
                <td className="mono">{quest.lvl ?? "—"}{quest.req ? <span className="muted"> / {quest.req}</span> : null}</td>
                <td className="small">{quest.pickup ?? "—"}</td>
                <td className="small">{quest.turnin ?? "—"}</td>
                <td>{quest.rewards.length ? <>{quest.choice && <span className="muted small">{s.choose}:</span>}<div className="item-grid">{quest.rewards.map(item => <ItemLink key={item} id={item} />)}</div></> : <span className="muted">—</span>}</td>
              </tr>))}</tbody>
          </table></div>
        </Section>
      )}
      {!index && <p className="muted">{s.loading}</p>}
      <p className="fine-print">{s.sourceNote}</p>
    </article>
  );
}

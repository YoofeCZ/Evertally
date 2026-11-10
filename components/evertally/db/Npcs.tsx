"use client";
import { useDeferredValue, useMemo, useState } from "react";
import { Icon } from "../ui";
import { PoiBadge, POI } from "./icons";
import { useZoneName } from "./Items";
import { MiniMap } from "./MiniMap";
import { Fold, ItemChips, ItemLink, QuestLink, Section, npcLevel, rankName, useDb } from "./parts";
import { hrefMap, useNpc, type NpcRow } from "./store";
import { useS } from "./strings";

const PAGE = 40;
/** Developer placeholders in the NPC table ("[PH] Combat Tester", "[DNT] Kill Credit") sink to the bottom. */
const JUNK = /^\[(PH|DNT|TEST|UNUSED)/i;
const FACTION: Record<string, "alliance" | "horde" | "both"> = { A: "alliance", H: "horde", AH: "both" };

export function NpcDetailView({ id }: { id: number }) {
  const s = useS();
  const { index } = useDb();
  const detail = useNpc(index, id);
  const zoneName = useZoneName();
  const row = index?.npcs.get(id);
  if (!index) return <p className="muted">{s.loading}</p>;
  if (!row) return <div className="notice error">{s.noResults} #{id}</div>;
  const d = detail.data;
  const zones = d ? Object.entries(d.sp) : [];
  const total = zones.reduce((sum, [, points]) => sum + points.length, 0);
  const services = d?.services ?? row[5];
  const friendly = d?.friendly ? FACTION[d.friendly] : undefined;
  return (
    <article className="db-detail">
      <header className="db-head">
        <span className="npc-portrait"><PoiBadge kind={services.find(service => service in POI) ?? "mob"} size={56} /></span>
        <div>
          <h2>{row[1]}</h2>
          {d?.sub && <p className="subtitle">&lt;{d.sub}&gt;</p>}
          <div className="chips">
            <span className="chip mono">#{id}</span>
            <span className="chip">{s.level} {npcLevel(row)}</span>
            {row[4] > 0 && <span className="chip warn">{rankName(row[4])}</span>}
            {friendly && <span className="chip">{s.friendly} {s[friendly]}</span>}
            {services.map(service => <span key={service} className="chip"><PoiBadge kind={service} size={16} />{POI[service]?.label ?? service}</span>)}
          </div>
        </div>
      </header>

      <div className="db-columns">
        <div className="db-stack">
          <Section title={s.spawnsIn} count={total || undefined}>
            {zones.length ? zones.map(([zone, points]) => (
              <div key={zone} className="zone-block">
                <div className="zone-line"><strong>{zoneName(zone)}</strong><span className="muted">{points.length} {s.locations}</span><a className="btn btn-ghost btn-sm" href={hrefMap(zone, `npc:${id}`)}><Icon name="globe" size={14} /> {s.viewOnMap}</a></div>
                <MiniMap zone={zone} points={points} focus={`npc:${id}`} />
              </div>
            )) : <p className="muted">{detail.loading ? s.loading : s.noSpawns}</p>}
          </Section>
        </div>
        <div className="db-stack">
          {d?.starts && d.starts.length > 0 && <Section title={s.questsStart} count={d.starts.length}><Fold className="quest-col" items={d.starts.map(q => <QuestLink key={q} id={q} />)} /></Section>}
          {d?.ends && d.ends.length > 0 && <Section title={s.questsEnd} count={d.ends.length}><Fold className="quest-col" items={d.ends.map(q => <QuestLink key={q} id={q} />)} /></Section>}
          {d?.kills && d.kills.length > 0 && <Section title={s.questsKill} count={d.kills.length}><Fold className="quest-col" items={d.kills.map(q => <QuestLink key={q} id={q} />)} /></Section>}
        </div>
      </div>

      {d?.sells && d.sells.length > 0 && <Section title={s.sells} count={d.sells.length}><ItemChips ids={d.sells} /></Section>}
      {d?.drops && d.drops.length > 0 && (
        <Section title={s.drops} count={d.drops.length}>
          <div className="table-wrap"><table className="data-table compact">
            <thead><tr><th>Item</th><th className="num">{s.dropChance}</th></tr></thead>
            <tbody>{[...d.drops].sort((a, b) => (b[1] ?? 0) - (a[1] ?? 0)).slice(0, 60).map(([itemId, pct]) => (
              <tr key={itemId}><td><ItemLink id={itemId} /></td><td className="num mono">{pct ? `${pct.toFixed(pct < 1 ? 2 : 1)} %` : "—"}</td></tr>
            ))}</tbody>
          </table></div>
        </Section>
      )}
      {!d && detail.loading && <p className="muted">{s.loading}</p>}
      <p className="fine-print">{s.sourceNote}</p>
    </article>
  );
}

// ---------------------------------------------------------------------------------------------------
export function NpcsList({ query, selected }: { query: string; selected: number | null }) {
  const s = useS();
  const { index } = useDb();
  const zoneName = useZoneName();
  const [text, setText] = useState(query);
  const [service, setService] = useState("");
  const [rank, setRank] = useState("");
  const [zone, setZone] = useState("");
  const [minLevel, setMinLevel] = useState("");
  const [maxLevel, setMaxLevel] = useState("");
  const [page, setPage] = useState(0);
  const needle = useDeferredValue(text.trim().toLowerCase());
  const zones = useMemo(() => index ? [...new Set(index.search.npcs.map(row => row[8]).filter((key): key is string => Boolean(key)))].sort() : [], [index]);
  const matches = useMemo<NpcRow[]>(() => {
    if (!index) return [];
    const numeric = /^#?\d+$/.test(needle) ? Number(needle.replace("#", "")) : null;
    const min = Number(minLevel) || 0, max = Number(maxLevel) || 999;
    return index.search.npcs.filter(row =>
      (!needle || (numeric != null ? row[0] === numeric : row[1].toLowerCase().includes(needle))) &&
      (!service || row[5].includes(service)) && (rank === "" || String(row[4]) === rank) && (!zone || row[8] === zone) &&
      (!min && max === 999 || (row[3] || row[2]) >= min && row[2] <= max))
      .sort((a, b) => (needle ? Number(b[1].toLowerCase().startsWith(needle)) - Number(a[1].toLowerCase().startsWith(needle)) : 0) || Number(JUNK.test(a[1])) - Number(JUNK.test(b[1])) || b[6] - a[6] || a[1].localeCompare(b[1]));
  }, [index, needle, service, rank, zone, minLevel, maxLevel]);
  const pages = Math.max(1, Math.ceil(matches.length / PAGE));
  const current = Math.min(page, pages - 1);
  const reset = <T,>(set: (value: T) => void) => (value: T) => { set(value); setPage(0); };
  if (!index) return <p className="muted">{s.loading}</p>;
  const roles = Object.entries(POI).filter(([key]) => ["vendor", "trainer", "flight", "inn", "bank", "auction", "stable", "battle", "repair", "spirit"].includes(key));
  return (
    <div className="db-list">
      <div className="db-filters">
        <label className="search"><Icon name="search" size={16} /><input value={text} onChange={e => reset(setText)(e.target.value)} placeholder={s.searchAll} aria-label={s.tabNpcs} /></label>
        <div className="filter-row">
          <label className="field"><span>{s.services}</span><select value={service} onChange={e => reset(setService)(e.target.value)}><option value="">{s.all}</option>{roles.map(([key, glyph]) => <option key={key} value={key}>{glyph.label}</option>)}</select></label>
          <label className="field"><span>{s.kind}</span><select value={rank} onChange={e => reset(setRank)(e.target.value)}><option value="">{s.all}</option><option value="0">Normal</option><option value="1">{s.elite}</option><option value="2">{s.rareElite}</option><option value="3">{s.boss}</option><option value="4">{s.rare}</option></select></label>
          <label className="field"><span>{s.zone}</span><select value={zone} onChange={e => reset(setZone)(e.target.value)}><option value="">{s.all}</option>{zones.map(key => <option key={key} value={key}>{zoneName(key)}</option>)}</select></label>
        </div>
        <div className="filter-row">
          <label className="field"><span>{s.minLevel}</span><input inputMode="numeric" value={minLevel} onChange={e => reset(setMinLevel)(e.target.value.replace(/\D/g, ""))} /></label>
          <label className="field"><span>{s.maxLevel}</span><input inputMode="numeric" value={maxLevel} onChange={e => reset(setMaxLevel)(e.target.value.replace(/\D/g, ""))} /></label>
        </div>
      </div>
      <p className="fine-print">{matches.length.toLocaleString()} {s.matches}</p>
      {matches.length ? <ul className="result-list">{matches.slice(current * PAGE, (current + 1) * PAGE).map(row => (
        <li key={row[0]}><a href={`#database/npcs/${row[0]}`} className={selected === row[0] ? "is-selected" : ""}>
          <PoiBadge kind={row[5].find(service => service in POI) ?? "mob"} size={30} />
          <span className="rl-main"><strong>{row[1]}</strong><small>{[row[8] ? zoneName(row[8]) : null, row[5].map(service => POI[service]?.label).filter(Boolean).join(", ") || null].filter(Boolean).join(" · ") || "—"}</small></span>
          <span className="rl-meta mono">{npcLevel(row)}{row[4] > 0 ? ` · ${rankName(row[4])}` : ""}</span>
        </a></li>))}</ul> : <p className="muted">{s.noResults}</p>}
      <div className="pager"><button type="button" className="btn btn-ghost btn-sm" disabled={current === 0} onClick={() => setPage(current - 1)}>{s.previous}</button><span className="mono">{current + 1} / {pages}</span><button type="button" className="btn btn-ghost btn-sm" disabled={current + 1 >= pages} onClick={() => setPage(current + 1)}>{s.next}</button></div>
    </div>
  );
}

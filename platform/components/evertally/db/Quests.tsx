"use client";
import { useDeferredValue, useMemo, useState } from "react";
import { Icon } from "../ui";
import { PoiBadge } from "./icons";
import { useZoneName } from "./Items";
import { Fold, ItemLink, NpcLink, QuestLink, Section, useDb } from "./parts";
import { hrefMap, useObjects, useQuest, type QuestRow } from "./store";
import { useS } from "./strings";

const PAGE = 40;
/** Level -1 / unknown quests (class quests, seasonal) sort after the levelled ones. */
const levelKey = (row: QuestRow) => row[2] != null && row[2] > 0 ? row[2] : 999;
const levelText = (row: QuestRow) => [row[2] != null && row[2] > 0 ? String(row[2]) : "", row[3] ? String(row[3]) : ""].filter(Boolean).join(" · ");
const FACTION: Record<string, "alliance" | "horde" | "both"> = { A: "alliance", H: "horde", AH: "both" };

function ObjectLink({ id }: { id: number }) {
  const objects = useObjects();
  const entry = objects.data?.[String(id)];
  if (!entry) return <span className="chip">#{id}</span>;
  return entry[1] ? <a className="elink" href={hrefMap(entry[1], `obj:${id}`)}>{entry[0]}</a> : <span className="chip">{entry[0]}</span>;
}

function Chain({ ids, label }: { ids: number[] | undefined; label: string }) {
  if (!ids?.length) return null;
  return <Section title={label} count={ids.length}><Fold className="quest-col" items={ids.map(id => <QuestLink key={id} id={id} />)} limit={8} /></Section>;
}

export function QuestDetailView({ id }: { id: number }) {
  const s = useS();
  const { index } = useDb();
  const detail = useQuest(index, id);
  const zoneName = useZoneName();
  const row = index?.quests.get(id);
  if (!index) return <p className="muted">{s.loading}</p>;
  if (!row) return <div className="notice error">{s.noResults} #{id}</div>;
  const d = detail.data;
  const faction = d?.fac ? FACTION[d.fac] : undefined;
  const zone = d?.zone ?? null;
  return (
    <article className="db-detail">
      <header className="db-head">
        <span className="npc-portrait"><PoiBadge kind="qs" size={56} /></span>
        <div>
          <h2>{row[1]}</h2>
          <div className="chips">
            <span className="chip mono">#{id}</span>
            {row[2] ? <span className="chip">{s.level} {row[2]}</span> : <span className="chip">{s.noLevel}</span>}
            {row[3] ? <span className="chip">{s.required} {row[3]}</span> : null}
            {zone && <a className="chip" href={hrefMap(zone)}>{zoneName(zone)}</a>}
            {d?.sort && <span className="chip">{d.sort}</span>}
            {faction && <span className="chip">{s[faction]}</span>}
          </div>
        </div>
      </header>

      <div className="db-columns">
        <div className="db-stack">
          {d?.text?.length ? <Section title={s.objectives}>{d.text.map((paragraph, i) => <p key={i} className="quest-text">{paragraph}</p>)}</Section> : null}
          {d && (d.kill?.length || d.objObj?.length || d.need?.length) ? (
            <Section title={`${s.kill} / ${s.collect}`}>
              <ul className="plain-list">
                {d.kill?.map(npc => <li key={`k${npc}`}><span className="muted">{s.kill}</span> <NpcLink id={npc} /></li>)}
                {d.objObj?.map(obj => <li key={`o${obj}`}><span className="muted">{s.interact}</span> <ObjectLink id={obj} /></li>)}
                {d.need?.map(item => <li key={`i${item}`}><span className="muted">{s.collect}</span> <ItemLink id={item} /></li>)}
              </ul>
            </Section>
          ) : null}
          {d?.tips && d.tips.length > 0 && <Section title={s.tips}><ul className="plain-list tip-list">{d.tips.map((tip, i) => <li key={i}>{tip}</li>)}</ul></Section>}
          {d?.steps && d.steps.length > 0 && (
            <Section title={s.walkthrough}>
              <ol className="plain-list step-list">{d.steps.map(([kind, text], i) => <li key={i}><span className={`chip small step-${kind}`}>{kind}</span> {text}</li>)}</ol>
              <p className="fine-print">{s.tipsSource}</p>
            </Section>
          )}
          {d?.rewards && d.rewards.length > 0 && <Section title={s.rewards} count={d.rewards.length}><div className="item-grid">{d.rewards.map(item => <ItemLink key={item} id={item} />)}</div></Section>}
          {!d && detail.loading && <p className="muted">{s.loading}</p>}
        </div>
        <div className="db-stack">
          <Section title={s.startedBy}>
            {d && (d.startNpc?.length || d.startObj?.length || d.startItem?.length) ? <ul className="plain-list">
              {d.startNpc?.map(npc => <li key={`n${npc}`}><NpcLink id={npc} /></li>)}
              {d.startObj?.map(obj => <li key={`o${obj}`}><span className="muted">{s.fromObject}</span> <ObjectLink id={obj} /></li>)}
              {d.startItem?.map(item => <li key={`i${item}`}><span className="muted">{s.fromItem}</span> <ItemLink id={item} /></li>)}
            </ul> : <p className="muted">—</p>}
          </Section>
          <Section title={s.finishedBy}>
            {d && (d.endNpc?.length || d.endObj?.length) ? <ul className="plain-list">
              {d.endNpc?.map(npc => <li key={`n${npc}`}><NpcLink id={npc} /></li>)}
              {d.endObj?.map(obj => <li key={`o${obj}`}><ObjectLink id={obj} /></li>)}
            </ul> : <p className="muted">—</p>}
          </Section>
          {zone && <a className="btn btn-ghost btn-sm" href={hrefMap(zone, `quest:${id}`)}><Icon name="globe" size={14} /> {s.showOnMap}</a>}
          {(d?.races?.length || d?.classes?.length) ? <p className="muted small">{d?.races?.length ? `${s.racesOnly}: ${d.races.join(", ")}. ` : ""}{d?.classes?.length ? `${s.classesOnly}: ${d.classes.join(", ")}.` : ""}</p> : null}
        </div>
      </div>

      <div className="db-columns">
        <Chain ids={d?.pre} label={s.prerequisites} />
        <Chain ids={d?.next} label={s.leadsTo} />
      </div>
      <Chain ids={d?.child} label={s.relatedQuests} />
      <Chain ids={d?.excl} label={s.exclusive} />
      <p className="fine-print">{s.sourceNote}</p>
    </article>
  );
}

// ---------------------------------------------------------------------------------------------------
export function QuestsList({ query, selected }: { query: string; selected: number | null }) {
  const s = useS();
  const { index } = useDb();
  const zoneName = useZoneName();
  const [text, setText] = useState(query);
  const [zone, setZone] = useState("");
  const [faction, setFaction] = useState("");
  const [minLevel, setMinLevel] = useState("");
  const [maxLevel, setMaxLevel] = useState("");
  const [page, setPage] = useState(0);
  const needle = useDeferredValue(text.trim().toLowerCase());
  const zones = useMemo(() => index ? [...new Set(index.search.quests.map(row => row[4]).filter((key): key is string => Boolean(key)))].sort() : [], [index]);
  const matches = useMemo<QuestRow[]>(() => {
    if (!index) return [];
    const numeric = /^#?\d+$/.test(needle) ? Number(needle.replace("#", "")) : null;
    const min = Number(minLevel) || 0, max = Number(maxLevel) || 999;
    return index.search.quests.filter(row =>
      (!needle || (numeric != null ? row[0] === numeric : row[1].toLowerCase().includes(needle))) &&
      (!zone || row[4] === zone) && (!faction || row[5] === faction || row[5] === "AH" || !row[5]) &&
      (!min && max === 999 || (row[2] ?? 0) >= min && (row[2] ?? 0) <= max))
      .sort((a, b) => (needle ? Number(b[1].toLowerCase().startsWith(needle)) - Number(a[1].toLowerCase().startsWith(needle)) : 0) || levelKey(a) - levelKey(b) || a[1].localeCompare(b[1]));
  }, [index, needle, zone, faction, minLevel, maxLevel]);
  const pages = Math.max(1, Math.ceil(matches.length / PAGE));
  const current = Math.min(page, pages - 1);
  const reset = <T,>(set: (value: T) => void) => (value: T) => { set(value); setPage(0); };
  if (!index) return <p className="muted">{s.loading}</p>;
  return (
    <div className="db-list">
      <div className="db-filters">
        <label className="search"><Icon name="search" size={16} /><input value={text} onChange={e => reset(setText)(e.target.value)} placeholder={s.searchAll} aria-label={s.tabQuests} /></label>
        <div className="filter-row">
          <label className="field"><span>{s.zone}</span><select value={zone} onChange={e => reset(setZone)(e.target.value)}><option value="">{s.all}</option>{zones.map(key => <option key={key} value={key}>{zoneName(key)}</option>)}</select></label>
          <label className="field"><span>{s.alliance} / {s.horde}</span><select value={faction} onChange={e => reset(setFaction)(e.target.value)}><option value="">{s.all}</option><option value="A">{s.alliance}</option><option value="H">{s.horde}</option></select></label>
        </div>
        <div className="filter-row">
          <label className="field"><span>{s.minLevel}</span><input inputMode="numeric" value={minLevel} onChange={e => reset(setMinLevel)(e.target.value.replace(/\D/g, ""))} /></label>
          <label className="field"><span>{s.maxLevel}</span><input inputMode="numeric" value={maxLevel} onChange={e => reset(setMaxLevel)(e.target.value.replace(/\D/g, ""))} /></label>
        </div>
      </div>
      <p className="fine-print">{matches.length.toLocaleString()} {s.matches}</p>
      {matches.length ? <ul className="result-list">{matches.slice(current * PAGE, (current + 1) * PAGE).map(row => (
        <li key={row[0]}><a href={`#database/quests/${row[0]}`} className={selected === row[0] ? "is-selected" : ""}>
          <PoiBadge kind="qs" size={30} />
          <span className="rl-main"><strong>{row[1]}</strong><small>{[row[4] ? zoneName(row[4]) : null, row[5] ? (FACTION[row[5]] ? s[FACTION[row[5]]] : null) : null].filter(Boolean).join(" · ") || "—"}</small></span>
          <span className="rl-meta mono">{levelText(row)}</span>
        </a></li>))}</ul> : <p className="muted">{s.noResults}</p>}
      <div className="pager"><button type="button" className="btn btn-ghost btn-sm" disabled={current === 0} onClick={() => setPage(current - 1)}>{s.previous}</button><span className="mono">{current + 1} / {pages}</span><button type="button" className="btn btn-ghost btn-sm" disabled={current + 1 >= pages} onClick={() => setPage(current + 1)}>{s.next}</button></div>
    </div>
  );
}

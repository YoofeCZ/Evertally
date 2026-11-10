"use client";
import { useDeferredValue, useMemo, useState } from "react";
import { Icon } from "../ui";
import { ItemIcon, PoiBadge } from "./icons";
import { DungeonLink, NpcLink, QuestLink, Section, TipBody, liteRows, npcLevel, rankName, useDb } from "./parts";
import { hrefMap, qualityClass, useDungeons, useItem, useMaps, type Dungeon, type ItemRow } from "./store";
import { RecipeLink, useRecipeIndex } from "./Recipes";
import { split, useS } from "./strings";
import { useI18n } from "@/lib/i18n";

export function useZoneName() {
  const { lang } = useI18n();
  const maps = useMaps();
  return (key?: string | null) => {
    if (!key) return "";
    const map = maps.data?.find(entry => entry.key === key);
    return map ? (lang === "cs" ? map.nameCs : map.nameEn) : key.replace(/-/g, " ");
  };
}
const slugify = (text: string) => text.toLowerCase().replace(/'/g, "").replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
export function dungeonFor(dungeons: Dungeon[] | undefined, name: string): Dungeon | undefined {
  const key = slugify(name);
  return dungeons?.find(d => d.key === key) ?? dungeons?.find(d => d.group && slugify(d.group) === key) ?? dungeons?.find(d => d.key.startsWith(key));
}

// ---------------------------------------------------------------------------------------------------
export function ItemDetailView({ id }: { id: number }) {
  const s = useS();
  const { index } = useDb();
  const detail = useItem(index, id);
  const dungeons = useDungeons();
  const zoneName = useZoneName();
  const recipes = useRecipeIndex();
  const row = index?.items.get(id);
  if (!index) return <p className="muted">{s.loading}</p>;
  if (!row) return <div className="notice error">{s.noResults} #{id}</div>;
  const d = detail.data;
  const category = index.search.cats[row[5]];
  const rows = d?.tip?.length ? d.tip : liteRows(row[1], row[2], row[3], row[4], category);
  const qualityName = row[2] != null ? split(s.qualityNames)[row[2]] : null;
  const drops = d?.drops ?? [];
  const topZone = drops.map(([npc]) => index.npcs.get(npc)?.[8]).find(Boolean) ?? null;
  return (
    <article className="db-detail">
      <header className="db-head">
        <ItemIcon id={id} quality={row[2]} category={category} cached={row[8] === 0} size={64} />
        <div>
          <h2 className={qualityClass(row[2])}>{row[1]}</h2>
          <div className="chips">
            <span className="chip mono">#{id}</span>
            {qualityName && <span className={`chip ${qualityClass(row[2])}`}>{qualityName}</span>}
            {category && <span className="chip">{category}</span>}
            {d?.slot && <span className="chip">{d.slot}{d.sub ? ` · ${d.sub}` : ""}</span>}
            {row[3] ? <span className="chip">{s.itemLevel} {row[3]}</span> : null}
            {row[4] ? <span className="chip">{s.required} {row[4]}</span> : null}
          </div>
        </div>
      </header>

      <div className="db-columns">
        <div>
          <TipBody rows={rows} />
          {row[8] === 1 && <p className="fine-print">{s.noTooltip}</p>}
          {d?.wh && <a className="btn btn-ghost btn-sm" href={d.wh} target="_blank" rel="noreferrer"><Icon name="globe" size={14} /> {s.wowhead} ↗</a>}
        </div>
        <div className="db-stack">
          {d?.change && d.change.length > 0 && <Section title={s.changes}><ul className="plain-list change-list">{d.change.map((line, i) => <li key={i}>{line}</li>)}</ul></Section>}
          {d && d.src.length > 0 && (
            <Section title={s.lootSources}>
              <div className="chips">{d.src.map((source, i) => {
                const dungeon = /^forever::(dungeon|raid)::/.test(source.key) ? dungeonFor(dungeons.data?.entries, source.key.split("::")[2]) : undefined;
                return dungeon ? <DungeonLink key={i} keyName={dungeon.key} name={source.n} /> : <span key={i} className="chip">{source.n}{source.k !== source.n && !["Drop", "Quest"].includes(source.k) ? ` · ${source.k}` : ""}</span>;
              })}</div>
              {d.bosses && d.bosses.length > 0 && <p className="muted small">{s.droppedBy}: {d.bosses.join(", ")}</p>}
            </Section>
          )}
        </div>
      </div>

      {drops.length > 0 && (
        <Section title={s.droppedBy} count={drops.length} aside={topZone ? <a className="btn btn-ghost btn-sm" href={hrefMap(topZone, `item:${id}`)}><PoiBadge kind="mob" size={16} /> {s.showOnMap}</a> : undefined}>
          <div className="table-wrap"><table className="data-table compact">
            <thead><tr><th>NPC</th><th>{s.level}</th><th>{s.zone}</th><th className="num">{s.dropChance}</th></tr></thead>
            <tbody>{drops.slice(0, 40).map(([npcId, pct]) => {
              const npc = index.npcs.get(npcId);
              return <tr key={npcId}>
                <td><NpcLink id={npcId} />{npc && npc[4] > 0 && <span className="chip small">{rankName(npc[4])}</span>}</td>
                <td className="mono">{npcLevel(npc)}</td>
                <td>{npc?.[8] ? <a className="elink" href={hrefMap(npc[8], `npc:${npcId}`)}>{zoneName(npc[8])}</a> : <span className="muted">—</span>}</td>
                <td className="num mono">{pct ? `${pct.toFixed(pct < 1 ? 2 : 1)} %` : d?.chance && drops.length === 1 ? `${d.chance} %` : "—"}</td>
              </tr>;
            })}</tbody>
          </table></div>
          {d?.objDrops && d.objDrops.length > 0 && <p className="muted small">{s.containedIn}: {d.objDrops.length}</p>}
        </Section>
      )}
      {d?.vendors && d.vendors.length > 0 && (
        <Section title={s.soldBy} count={d.vendors.length}>
          <div className="item-grid">{d.vendors.slice(0, 30).map(npc => <NpcLink key={npc} id={npc} />)}</div>
        </Section>
      )}
      {recipes.byOutput.get(id) && <Section title={s.createdBy} count={recipes.byOutput.get(id)!.length}><div className="item-grid">{recipes.byOutput.get(id)!.map(recipe => <RecipeLink key={recipe.id} recipe={recipe} />)}</div></Section>}
      {recipes.byReagent.get(id) && <Section title={s.reagentIn} count={recipes.byReagent.get(id)!.length}><div className="item-grid">{recipes.byReagent.get(id)!.slice(0, 40).map(recipe => <RecipeLink key={recipe.id} recipe={recipe} />)}</div></Section>}
      {d?.rewards && d.rewards.length > 0 && (
        <Section title={s.rewardFrom} count={d.rewards.length}>
          <div className="item-grid">{d.rewards.slice(0, 30).map(q => <QuestLink key={q} id={q} />)}</div>
        </Section>
      )}
      {d?.starts && d.starts.length > 0 && (
        <Section title={s.startsQuest}><div className="item-grid">{d.starts.map(q => <QuestLink key={q} id={q} />)}</div></Section>
      )}
      {!d && detail.loading && <p className="muted">{s.loading}</p>}
    </article>
  );
}

// ---------------------------------------------------------------------------------------------------
const PAGE = 40;
/** Placeholder rows in the item cache ("[TMP] …", "63 Green Frost Belt") sink to the bottom of the default order. */
const JUNK = /^\[|^\d+ |^(zz|test)/i;
type Sort = "relevance" | "name" | "ilvl" | "req";

export function ItemsList({ query, selected }: { query: string; selected: number | null }) {
  const s = useS();
  const { index } = useDb();
  const [text, setText] = useState(query);
  const [quality, setQuality] = useState("");
  const [category, setCategory] = useState("");
  const [slot, setSlot] = useState("");
  const [minReq, setMinReq] = useState("");
  const [maxReq, setMaxReq] = useState("");
  const [lite, setLite] = useState(true);
  const [sort, setSort] = useState<Sort>("relevance");
  const [page, setPage] = useState(0);
  const needle = useDeferredValue(text.trim().toLowerCase());
  const matches = useMemo<ItemRow[]>(() => {
    if (!index) return [];
    const numeric = /^#?\d+$/.test(needle) ? Number(needle.replace("#", "")) : null;
    const cat = category === "" ? -2 : Number(category), slotIndex = slot === "" ? -2 : Number(slot);
    const min = Number(minReq) || 0, max = Number(maxReq) || 999;
    const found = index.search.items.filter(row =>
      (lite || row[8] === 0) && (!needle || (numeric != null ? row[0] === numeric : row[1].toLowerCase().includes(needle))) &&
      (quality === "" || String(row[2]) === quality) && (cat === -2 || row[5] === cat) && (slotIndex === -2 || row[6] === slotIndex) &&
      (!min && max === 999 || (row[4] ?? 0) >= min && (row[4] ?? 0) <= max));
    const key = (row: ItemRow) => sort === "name" ? row[1] : sort === "ilvl" ? -(row[3] ?? 0) : sort === "req" ? (row[4] ?? 0) : (row[8] * 10000 + (JUNK.test(row[1]) ? 5000 : 0) + (needle && row[1].toLowerCase().startsWith(needle) ? 0 : 2000) + (7 - (row[2] ?? 1)) * 100);
    return found.sort((a, b) => { const ka = key(a), kb = key(b); return ka < kb ? -1 : ka > kb ? 1 : a[1].localeCompare(b[1]); });
  }, [index, needle, quality, category, slot, minReq, maxReq, lite, sort]);
  const pages = Math.max(1, Math.ceil(matches.length / PAGE));
  const current = Math.min(page, pages - 1);
  const reset = <T,>(set: (value: T) => void) => (value: T) => { set(value); setPage(0); };
  if (!index) return <p className="muted">{s.loading}</p>;
  const names = split(s.qualityNames);
  return (
    <div className="db-list">
      <div className="db-filters">
        <label className="search"><Icon name="search" size={16} /><input value={text} onChange={e => reset(setText)(e.target.value)} placeholder={s.searchAll} aria-label={s.tabItems} /></label>
        <div className="filter-row">
          <label className="field"><span>{s.quality}</span><select value={quality} onChange={e => reset(setQuality)(e.target.value)}><option value="">{s.all}</option>{names.map((name, i) => <option key={i} value={i}>{name}</option>)}</select></label>
          <label className="field"><span>{s.category}</span><select value={category} onChange={e => reset(setCategory)(e.target.value)}><option value="">{s.all}</option>{index.search.cats.map((c, i) => <option key={c} value={i}>{c}</option>)}</select></label>
          <label className="field"><span>{s.slot}</span><select value={slot} onChange={e => reset(setSlot)(e.target.value)}><option value="">{s.all}</option>{index.search.slots.map((c, i) => <option key={c} value={i}>{c}</option>)}</select></label>
        </div>
        <div className="filter-row">
          <label className="field"><span>{s.minLevel}</span><input inputMode="numeric" value={minReq} onChange={e => reset(setMinReq)(e.target.value.replace(/\D/g, ""))} /></label>
          <label className="field"><span>{s.maxLevel}</span><input inputMode="numeric" value={maxReq} onChange={e => reset(setMaxReq)(e.target.value.replace(/\D/g, ""))} /></label>
          <label className="field"><span>{s.sortBy}</span><select value={sort} onChange={e => reset(setSort)(e.target.value as Sort)}><option value="relevance">{s.relevance}</option><option value="name">{s.name}</option><option value="ilvl">{s.itemLevel}</option><option value="req">{s.required}</option></select></label>
        </div>
        <label className="check"><input type="checkbox" checked={lite} onChange={e => reset(setLite)(e.target.checked)} /> {s.withoutTooltip}</label>
      </div>
      <p className="fine-print">{matches.length.toLocaleString()} {s.matches}</p>
      {matches.length ? <ul className="result-list">{matches.slice(current * PAGE, (current + 1) * PAGE).map(row => (
        <li key={row[0]}><a href={`#database/items/${row[0]}`} className={selected === row[0] ? "is-selected" : ""}>
          <ItemIcon id={row[0]} quality={row[2]} category={index.search.cats[row[5]]} cached={row[8] === 0} size={34} />
          <span className="rl-main"><strong className={qualityClass(row[2])}>{row[1]}</strong><small>{[index.search.slots[row[6]], index.search.cats[row[5]]].filter(Boolean).join(" · ") || "—"}</small></span>
          <span className="rl-meta mono">{row[3] ? `ilvl ${row[3]}` : ""}{row[4] ? ` · ${row[4]}` : ""}</span>
        </a></li>))}</ul> : <p className="muted">{s.noResults}</p>}
      <div className="pager"><button type="button" className="btn btn-ghost btn-sm" disabled={current === 0} onClick={() => setPage(current - 1)}>{s.previous}</button><span className="mono">{current + 1} / {pages}</span><button type="button" className="btn btn-ghost btn-sm" disabled={current + 1 >= pages} onClick={() => setPage(current + 1)}>{s.next}</button></div>
    </div>
  );
}

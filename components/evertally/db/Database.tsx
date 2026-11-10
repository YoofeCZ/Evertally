"use client";
/* eslint-disable @next/next/no-img-element -- bundled dungeon artwork with explicit size */
import { useDeferredValue, useMemo, useState, type ReactNode } from "react";
import { useI18n } from "@/lib/i18n";
import "@/app/db.css";
import { Icon } from "../ui";
import { PageHead } from "../views/Data";
import { DungeonDetailView, DungeonsGrid } from "./Dungeons";
import { HOWTOS, RESOURCES } from "./guides";
import { ItemIcon, PoiBadge } from "./icons";
import { ItemDetailView, ItemsList, useZoneName } from "./Items";
import { NpcDetailView, NpcsList } from "./Npcs";
import { DbProvider, Section, useDb, npcLevel } from "./parts";
import { QuestDetailView, QuestsList } from "./Quests";
import { RecipeDetailView, RecipesList } from "./Recipes";
import { qualityClass, useDungeonArt, useDungeons, useMeta } from "./store";
import { useS } from "./strings";

type Tab = "home" | "dungeons" | "items" | "npcs" | "quests" | "recipes" | "guides";
const TABS: Tab[] = ["home", "dungeons", "items", "npcs", "quests", "recipes", "guides"];

function parse(route: string) {
  const [path, qs = ""] = route.split("?");
  return { segments: path.split("/").filter(Boolean), query: new URLSearchParams(qs).get("q") ?? "" };
}

// ---- home: one search box over everything --------------------------------------------------------
function Home({ initialQuery }: { initialQuery: string }) {
  const s = useS();
  const { index } = useDb();
  const dungeons = useDungeons();
  const art = useDungeonArt();
  const meta = useMeta();
  const zoneName = useZoneName();
  const [text, setText] = useState(initialQuery);
  const needle = useDeferredValue(text.trim().toLowerCase());
  const results = useMemo(() => {
    if (!index || needle.length < 2) return null;
    const numeric = /^#?\d+$/.test(needle) ? Number(needle.replace("#", "")) : null;
    const match = (name: string, id: number) => numeric != null ? id === numeric : name.toLowerCase().includes(needle);
    const rank = <T,>(rows: T[], name: (row: T) => string) => rows.sort((a, b) => Number(name(b).toLowerCase().startsWith(needle)) - Number(name(a).toLowerCase().startsWith(needle)) || name(a).length - name(b).length);
    return {
      dungeons: (dungeons.data?.entries ?? []).filter(d => d.name.toLowerCase().includes(needle) || d.group?.toLowerCase().includes(needle)).slice(0, 6),
      items: rank(index.search.items.filter(row => match(row[1], row[0])), row => row[1]),
      npcs: rank(index.search.npcs.filter(row => match(row[1], row[0])), row => row[1]),
      quests: rank(index.search.quests.filter(row => match(row[1], row[0])), row => row[1]),
    };
  }, [index, dungeons.data, needle]);
  const counts = meta.data?.counts;
  const cards: { tab: Tab; title: string; text: string; count?: number }[] = [
    { tab: "dungeons", title: s.tabDungeons, text: s.cardDungeons, count: dungeons.data?.entries.length },
    { tab: "items", title: s.tabItems, text: s.cardItems, count: counts?.items },
    { tab: "npcs", title: s.tabNpcs, text: s.cardNpcs, count: counts?.npcs },
    { tab: "quests", title: s.tabQuests, text: s.cardQuests, count: counts?.quests },
    { tab: "recipes", title: s.tabRecipes, text: s.cardRecipes, count: counts?.recipes },
    { tab: "guides", title: s.tabGuides, text: s.cardGuides },
  ];
  return (
    <div className="db-home">
      <label className="search big"><Icon name="search" size={18} /><input autoFocus value={text} onChange={e => setText(e.target.value)} placeholder={s.searchAll} aria-label={s.searchAll} /></label>
      <p className="fine-print">{s.searchHint}</p>

      {results ? (
        <div className="result-groups">
          {results.dungeons.length > 0 && <Section title={s.tabDungeons} count={results.dungeons.length}><div className="item-grid">{results.dungeons.map(d => <a key={d.key} className="elink" href={`#database/dungeons/${d.key}`}><PoiBadge kind={d.type === "raid" ? "raid" : "dungeon"} size={18} /> {d.name} <small className="muted">{d.lvl ? `${d.lvl[0]}–${d.lvl[1]}` : ""}</small></a>)}</div></Section>}
          {results.items.length > 0 && <Section title={s.tabItems} count={results.items.length} aside={results.items.length > 8 ? <a className="link-btn" href={`#database/items?q=${encodeURIComponent(text)}`}>{s.showMore}</a> : undefined}><ul className="result-list">{results.items.slice(0, 8).map(row => (
            <li key={row[0]}><a href={`#database/items/${row[0]}`}><ItemIcon id={row[0]} quality={row[2]} category={index?.search.cats[row[5]]} cached={row[8] === 0} size={30} /><span className="rl-main"><strong className={qualityClass(row[2])}>{row[1]}</strong><small>{[index?.search.slots[row[6]], index?.search.cats[row[5]]].filter(Boolean).join(" · ")}</small></span><span className="rl-meta mono">{row[3] ? `ilvl ${row[3]}` : ""}</span></a></li>))}</ul></Section>}
          {results.npcs.length > 0 && <Section title={s.tabNpcs} count={results.npcs.length} aside={results.npcs.length > 8 ? <a className="link-btn" href={`#database/npcs?q=${encodeURIComponent(text)}`}>{s.showMore}</a> : undefined}><ul className="result-list">{results.npcs.slice(0, 8).map(row => (
            <li key={row[0]}><a href={`#database/npcs/${row[0]}`}><PoiBadge kind={row[5][0] ?? "mob"} size={28} /><span className="rl-main"><strong>{row[1]}</strong><small>{row[8] ? zoneName(row[8]) : "—"}</small></span><span className="rl-meta mono">{npcLevel(row)}</span></a></li>))}</ul></Section>}
          {results.quests.length > 0 && <Section title={s.tabQuests} count={results.quests.length} aside={results.quests.length > 8 ? <a className="link-btn" href={`#database/quests?q=${encodeURIComponent(text)}`}>{s.showMore}</a> : undefined}><ul className="result-list">{results.quests.slice(0, 8).map(row => (
            <li key={row[0]}><a href={`#database/quests/${row[0]}`}><PoiBadge kind="qs" size={28} /><span className="rl-main"><strong>{row[1]}</strong><small>{row[4] ? zoneName(row[4]) : "—"}</small></span><span className="rl-meta mono">{row[2] ?? ""}</span></a></li>))}</ul></Section>}
          {!results.dungeons.length && !results.items.length && !results.npcs.length && !results.quests.length && <p className="muted">{s.noResults}</p>}
        </div>
      ) : (
        <>
          <div className="home-cards">{cards.map(card => (
            <a key={card.tab} className="home-card" href={`#database/${card.tab}`}>
              <strong>{card.title}</strong><span className="muted">{card.text}</span>
              {card.count != null && <span className="mono count-line">{card.count.toLocaleString()} {s.records}</span>}
            </a>))}</div>
          <Section title={s.featured}>
            <div className="dungeon-strip">{(dungeons.data?.entries ?? []).filter(d => d.bosses.length > 0).sort((a, b) => (a.lvl?.[0] ?? 99) - (b.lvl?.[0] ?? 99)).slice(0, 12).map(d => (
              <a key={d.key} className="strip-card" href={`#database/dungeons/${d.key}`}>
                {art.data?.[d.key] ? <img src={art.data[d.key].image} alt="" loading="lazy" decoding="async" width={220} height={120} /> : <span className="strip-fallback"><PoiBadge kind="dungeon" size={36} /></span>}
                <span><strong>{d.name}</strong><small className="mono">{s.level} {d.lvl ? `${d.lvl[0]}–${d.lvl[1]}` : "—"}</small></span>
              </a>))}</div>
          </Section>
          <p className="fine-print">{s.sourceNote}</p>
        </>
      )}
    </div>
  );
}

// ---- guides ---------------------------------------------------------------------------------------
function Guides() {
  const s = useS();
  const { lang } = useI18n();
  return (
    <div className="guides">
      <p className="lead small">{s.guidesLead}</p>
      <Section title={s.howto}>
        <div className="howto-grid">{HOWTOS.map(howto => (
          <div key={howto.id} className="howto">
            <h4>{howto.title[lang]}</h4>
            <ol>{howto.steps.map((step, i) => <li key={i}>{step[lang]}</li>)}</ol>
          </div>))}</div>
      </Section>
      <Section title={s.guidesTitle} count={RESOURCES.length}>
        <div className="resource-grid">{RESOURCES.map(resource => (
          <a key={resource.id} className="resource" href={resource.url} target="_blank" rel="noreferrer">
            <strong>{resource.name} <span aria-hidden="true">↗</span></strong>
            <span className="muted">{resource[lang]}</span>
            <span className="chips">{resource.tags.map(tag => <span key={tag} className="chip small">{tag}</span>)}<span className="chip small">{s.external}</span></span>
          </a>))}</div>
      </Section>
    </div>
  );
}

// ---- master/detail wrapper ----------------------------------------------------------------------------
function Split({ list, detail }: { list: ReactNode; detail: ReactNode | null }) {
  return <div className={`db-split ${detail ? "has-detail" : ""}`}><aside className="db-aside">{list}</aside>{detail && <div className="db-main">{detail}</div>}</div>;
}

function Body({ route }: { route: string }) {
  const s = useS();
  const { error, loading } = useDb();
  const { segments, query } = parse(route);
  const tab: Tab = TABS.includes(segments[0] as Tab) ? segments[0] as Tab : "home";
  const id = segments[1] && /^\d+$/.test(segments[1]) ? Number(segments[1]) : null;
  if (error) return <div className="notice error">{s.error}</div>;
  return (
    <>
      <nav className="db-tabs" aria-label={s.dbTitle}>
        {TABS.map(entry => <a key={entry} href={`#database${entry === "home" ? "" : `/${entry}`}`} className={tab === entry ? "on" : ""} aria-current={tab === entry ? "page" : undefined}>{entry === "home" ? s.home : ({ dungeons: s.tabDungeons, items: s.tabItems, npcs: s.tabNpcs, quests: s.tabQuests, recipes: s.tabRecipes, guides: s.tabGuides })[entry]}</a>)}
      </nav>
      {loading && tab !== "dungeons" && tab !== "guides" ? <p className="muted">{s.loading}</p> : null}
      {tab === "home" && <Home initialQuery={query} />}
      {tab === "dungeons" && (segments[1] ? <div className="db-main wide"><a className="link-btn back" href="#database/dungeons">← {s.tabDungeons}</a><DungeonDetailView keyName={segments[1]} /></div> : <DungeonsGrid />)}
      {tab === "items" && <Split list={<ItemsList query={query} selected={id} />} detail={id ? <ItemDetailView id={id} /> : null} />}
      {tab === "npcs" && <Split list={<NpcsList query={query} selected={id} />} detail={id ? <NpcDetailView id={id} /> : null} />}
      {tab === "quests" && <Split list={<QuestsList query={query} selected={id} />} detail={id ? <QuestDetailView id={id} /> : null} />}
      {tab === "recipes" && <Split list={<RecipesList query={query} selected={id} />} detail={id ? <RecipeDetailView id={id} /> : null} />}
      {tab === "guides" && <Guides />}
    </>
  );
}

export function DatabaseView({ route }: { route: string }) {
  const s = useS();
  return (
    <DbProvider>
      <PageHead title={s.dbTitle} lead={s.dbLead} />
      <div className="page-column db-page"><Body route={route} /></div>
    </DbProvider>
  );
}

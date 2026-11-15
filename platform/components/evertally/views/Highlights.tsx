"use client";
// The Highlights page: the newest records and placings of the public chronicles (every line opens the replay), the boards with their podiums,
// and who holds the records. Chronicles appear here only when their players turned on "Share my chronicle".
import { useMemo, useState } from "react";
import type { Board, Section } from "@/lib/chronicle-highlights";
import { BoardCard, Face, Feed, SECTIONS, SectionGlyph, useHighlights, useWords } from "./ChronicleHighlights";

const TEXT = {
  en: {
    title: "Highlights", lead: "The newest highlights from players who share their chronicles, with their records and placings on the boards among them. Every line opens the replay.",
    everyone: "Everyone", show: "Show", empty: "Nothing yet. This fills up as players turn on “Share my chronicle” in the addon (or in Account) and their recordings arrive.",
    loading: "Loading…", holders: "Record holders", holds: (n: number) => `Holds ${n} ${n === 1 ? "record" : "records"}`, how: "How it works",
    howText: "Times are time played between two events of a recording, not a stopwatch of the game. Each board lists one best result per player.",
    boards: "Boards", every: "Every leaderboard", homeFeed: "Recent highlights", allHighlights: "All highlights", homeBoards: "Leaderboards", showAll: (n: number) => `All ${n}`, showLess: "Show less",
  },
  cs: {
    title: "Zajímavosti", lead: "Nejnovější zajímavosti od hráčů, kteří sdílejí své kroniky, s jejich rekordy a umístěním v žebříčcích mezi nimi. Každý řádek otevře přehrání.",
    everyone: "Všichni", show: "Zobrazit", empty: "Zatím nic. Plní se, jak hráči zapínají „Sdílet mou kroniku“ v addonu (nebo v Účtu) a jejich záznamy dorazí.",
    loading: "Načítám…", holders: "Držitelé rekordů", holds: (n: number) => `Drží ${n} ${n === 1 ? "rekord" : n < 5 ? "rekordy" : "rekordů"}`, how: "Jak to funguje",
    howText: "Časy jsou čas hraní mezi dvěma událostmi záznamu, ne stopky hry. Žebříček má od každého hráče jeden nejlepší výsledek.",
    boards: "Žebříčky", every: "Všechny žebříčky", homeFeed: "Nedávné zajímavosti", allHighlights: "Všechny zajímavosti", homeBoards: "Žebříčky kronik", showAll: (n: number) => `Všech ${n}`, showLess: "Méně",
  },
};

function Cards({ boards, limit }: { boards: readonly Board[]; limit: number }) {
  const { lang } = useWords();
  const t = TEXT[lang === "cs" ? "cs" : "en"];
  const [all, setAll] = useState(false);
  return (
    <>
      <div className="hl-cards">{(all ? boards : boards.slice(0, limit)).map(b => <BoardCard key={b.id} b={b} />)}</div>
      {boards.length > limit && <button type="button" className="hl-more" onClick={() => setAll(v => !v)}>{all ? t.showLess : t.showAll(boards.length)}</button>}
    </>
  );
}

/** The sections of the boards: close races first, then levelling, quests, dungeons, professions, deathless. */
export function BoardSections({ boards, closeRaces }: { boards: readonly Board[]; closeRaces: readonly string[] }) {
  const { w } = useWords();
  const close = closeRaces.map(id => boards.find(b => b.id === id)).filter((b): b is Board => Boolean(b));
  return (
    <>
      {close.length > 0 && (
        <section className="hl-section">
          <h2><SectionGlyph id="close" /> <span>{w.closeRaces}<small>{w.closeText}</small></span></h2>
          <Cards boards={close} limit={3} />
        </section>
      )}
      {SECTIONS.map(section => {
        const list = boards.filter(b => b.section === section);
        return list.length ? (
          <section className="hl-section" key={section}>
            <h2><SectionGlyph id={section} /> <span>{w.sectionName[section]}<small>{w.sectionText[section]}</small></span></h2>
            <Cards boards={list} limit={3} />
          </section>
        ) : null;
      })}
    </>
  );
}

/** The two blocks of the home page: the newest highlights and a first look at the boards. Nothing is shown until a player shares a chronicle. */
export function HomeHighlights() {
  const { lang } = useWords();
  const t = TEXT[lang === "cs" ? "cs" : "en"];
  const data = useHighlights();
  const body = data.data;
  if (!body || !body.boards.length) return null;
  const first = [...body.closeRaces.map(id => body.boards.find(b => b.id === id)), ...body.boards].filter((b): b is Board => Boolean(b));
  const seen = new Set<string>(), cards = first.filter(b => !seen.has(b.id) && seen.add(b.id)).slice(0, 3);
  return (
    <>
      <section className="ch-card home-panel hl-home">
        <h2>{t.homeFeed}<span className="home-more"><a href="#highlights">{t.allHighlights} →</a></span></h2>
        <Feed items={body.feed.slice(0, 6)} />
      </section>
      <section className="ch-card home-panel hl-home">
        <h2>{t.homeBoards}<span className="home-more"><a href="#highlights">{t.every} →</a></span></h2>
        <div className="hl-cards">{cards.map(b => <BoardCard key={b.id} b={b} />)}</div>
      </section>
    </>
  );
}

export function HighlightsView() {
  const { lang } = useWords();
  const t = TEXT[lang === "cs" ? "cs" : "en"];
  const { w } = useWords();
  const data = useHighlights();
  const [hidden, setHidden] = useState<ReadonlySet<Section>>(new Set());
  const feed = useMemo(() => (data.data?.feed ?? []).filter(h => !hidden.has(h.section)), [data.data, hidden]);
  const counts = useMemo(() => {
    const out = new Map<Section, number>();
    for (const h of data.data?.feed ?? []) out.set(h.section, (out.get(h.section) ?? 0) + 1);
    return out;
  }, [data.data]);
  const toggle = (s: Section) => setHidden(prev => { const next = new Set(prev); if (next.has(s)) next.delete(s); else next.add(s); return next; });
  const body = data.data;
  return (
    <div className="page-column hl-page">
      <h1>{t.title}</h1>
      <p className="hl-lead">{t.lead}</p>
      {!body ? <p className="muted">{t.loading}</p> : !body.boards.length ? <p className="hl-empty">{t.empty}</p> : (
        <>
          <div className="hl-columns">
            <div>
              <div className="hl-tabs"><button type="button" className="is-on">{t.everyone}</button></div>
              <div className="hl-chips" role="group" aria-label={t.show}>
                <span>{t.show}</span>
                {SECTIONS.filter(s => counts.get(s)).map(s => (
                  <button key={s} type="button" className={hidden.has(s) ? "" : "is-on"} aria-pressed={!hidden.has(s)} onClick={() => toggle(s)}>{w.sectionName[s]} <i>{counts.get(s)}</i></button>
                ))}
              </div>
              <Feed items={feed} />
            </div>
            <aside>
              {body.holders.length > 0 && (
                <section>
                  <h2>{t.holders}</h2>
                  <ul className="hl-holders">
                    {body.holders.map(h => (
                      <li key={h.profileId}><Face classId={h.classId} size={38} /><span><b>{h.name}</b><small>{t.holds(h.records)}</small></span></li>
                    ))}
                  </ul>
                </section>
              )}
              <section>
                <h2>{t.how}</h2>
                <p className="hl-note">{t.howText}</p>
              </section>
            </aside>
          </div>
          <h2 className="hl-boards-head">{t.every}</h2>
          <BoardSections boards={body.boards} closeRaces={body.closeRaces} />
        </>
      )}
    </div>
  );
}

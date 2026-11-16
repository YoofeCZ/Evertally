"use client";
// The Highlights page: the newest records and placings of the public chronicles (every line opens the replay), the boards with their podiums,
// and who holds the records. Chronicles appear here only when their players turned on "Share my chronicle".
import { useCallback, useEffect, useMemo, useState } from "react";
import type { ChronicleListing } from "@/lib/chronicle-build";
import { api, useApi } from "../api";
import { parseChronicle, type Chronicle } from "@/lib/chronicle";
import { useMaps } from "../db/store";
import { MiniPlayer } from "./Chronicle";
import { PagedSearch, Pager, usePaged } from "../Paged";
import type { Board, Section } from "@/lib/chronicle-highlights";
import { BoardCard, Face, Feed, SECTIONS, SectionGlyph, Trail, boardName, detailText, exactText, replayLink, useHighlights, useWords, valueText } from "./ChronicleHighlights";

const TEXT = {
  en: {
    title: "Highlights", lead: "The newest highlights from players who share their chronicles, with their records and placings on the boards among them. Every line opens the replay.",
    everyone: "Everyone", searchFeed: "Search a character, quest or board", noMatch: "Nothing matches the search.", previous: "Previous", next: "Next", pagesLabel: "Pages", show: "Show", empty: "Nothing yet. This fills up as players turn on “Share my chronicle” in the addon (or in Account) and their recordings arrive.",
    loading: "Loading…", spotUnavailable: "The preview could not be loaded.", holders: "Record holders", holds: (n: number) => `Holds ${n} ${n === 1 ? "record" : "records"}`, how: "How it works",
    howText: "Times are time played between two events of a recording, not a stopwatch of the game. Each board lists one best result per player.",
    spotWatch: "Watch it", spotAnother: "Another one", spotOpen: "Open chronicles", spotEmpty: "No chronicle is available yet. An actual recording will play here as soon as one is available to you.", spotNames: { chronicle: "Random chronicle", close: "Close race", dungeon: "Best dungeon", levelling: "Fastest levelling", quest: "Fastest quest", profession: "Fastest profession", deathless: "Furthest without dying" } as Record<string, string>,
    spotTexts: { chronicle: "A whole journey, replayed from the start.", close: "Second place is almost at the record.", dungeon: "The fastest clear, from the door to the last boss.", levelling: "The fastest ten levels.", quest: "The fastest hand-in of a quest.", profession: "The fastest rise of a profession.", deathless: "The furthest a new character got without dying." } as Record<string, string>,
    spotPlayed: "of play", spotVs: "second place", boards: "Boards", every: "Every leaderboard", homeFeed: "Recent highlights", allHighlights: "All highlights", homeBoards: "Leaderboards", showAll: (n: number) => `All ${n}`, showLess: "Show less",
  },
  cs: {
    title: "Zajímavosti", lead: "Nejnovější zajímavosti od hráčů, kteří sdílejí své kroniky, s jejich rekordy a umístěním v žebříčcích mezi nimi. Každý řádek otevře přehrání.",
    everyone: "Všichni", searchFeed: "Hledat postavu, quest nebo žebříček", noMatch: "Hledání nic neodpovídá.", previous: "Předchozí", next: "Další", pagesLabel: "Stránky", show: "Zobrazit", empty: "Zatím nic. Plní se, jak hráči zapínají „Sdílet mou kroniku“ v addonu (nebo v Účtu) a jejich záznamy dorazí.",
    loading: "Načítám…", spotUnavailable: "Náhled se nepodařilo načíst.", holders: "Držitelé rekordů", holds: (n: number) => `Drží ${n} ${n === 1 ? "rekord" : n < 5 ? "rekordy" : "rekordů"}`, how: "Jak to funguje",
    howText: "Časy jsou čas hraní mezi dvěma událostmi záznamu, ne stopky hry. Žebříček má od každého hráče jeden nejlepší výsledek.",
    spotWatch: "Spustit", spotAnother: "Jiná", spotOpen: "Otevřít kroniky", spotEmpty: "Zatím není dostupná žádná kronika. Jakmile pro tebe bude dostupný skutečný záznam, přehraje se tady.", spotNames: { chronicle: "Náhodná kronika", close: "Těsný souboj", dungeon: "Nejlepší dungeon", levelling: "Nejrychlejší levelování", quest: "Nejrychlejší quest", profession: "Nejrychlejší profese", deathless: "Nejdál bez smrti" } as Record<string, string>,
    spotTexts: { chronicle: "Celá cesta, přehraná od začátku.", close: "Druhé místo je skoro u rekordu.", dungeon: "Nejrychlejší průchod od vstupu po posledního bosse.", levelling: "Nejrychlejších deset úrovní.", quest: "Nejrychlejší odevzdání questu.", profession: "Nejrychlejší růst profese.", deathless: "Nejdál, kam se nová postava dostala bez smrti." } as Record<string, string>,
    spotPlayed: "hraní", spotVs: "druhé místo", boards: "Žebříčky", every: "Všechny žebříčky", homeFeed: "Nedávné zajímavosti", allHighlights: "Všechny zajímavosti", homeBoards: "Žebříčky kronik", showAll: (n: number) => `Všech ${n}`, showLess: "Méně",
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

type Pick = { kind: string; profileId: string; slice?: { at: number; to: number }; title: string; who?: { name: string; realm: string | null; classId: number | null; level: number | null }; fact?: string; sub?: string; trail?: number[]; href: string };
const SPOT_KINDS: Record<string, string> = { levelling: "levelling", quests: "quest", professions: "profession", deathless: "deathless" };

/**
 * The first thing on the home page: one chronicle to launch, a different kind of it every time (a whole chronicle, a close race, the best dungeon,
 * the fastest levelling…), chosen at random from public recordings and the viewer's own recordings.
 */
export function Spotlight() {
  const { w, lang } = useWords();
  const t = TEXT[lang === "cs" ? "cs" : "en"];
  const highlights = useHighlights();
  const chronicles = useApi<{ chronicles?: ChronicleListing[] }>("/api/chronicles");
  const [draw] = useState(() => Math.random());
  const [chosen, setChosen] = useState<string | null>(null);
  const [bad, setBad] = useState<ReadonlySet<string>>(new Set());
  const onFail = useCallback((profileId: string) => setBad(prev => new Set(prev).add(profileId)), []);
  // Wait for both sources before choosing; an empty list or a failed request must never turn into a generated recording.
  const loaded = (highlights.data || highlights.error) && (chronicles.data || chronicles.error);
  const picks = useMemo(() => {
    const out: Pick[] = [];
    for (const c of chronicles.data?.chronicles ?? []) if (c.shared || c.own) out.push({ kind: "chronicle", profileId: c.profileId, title: c.name, who: { name: c.name, realm: c.realm, classId: c.classId, level: c.level }, fact: `${exactText(c.summary.seconds)} ${t.spotPlayed}`, href: `#chronicle/${encodeURIComponent(c.profileId)}` });
    const boards = highlights.data?.boards ?? [];
    for (const id of highlights.data?.closeRaces ?? []) {
      const b = boards.find(x => x.id === id);
      if (b && b.entries.length >= 2) out.push({ kind: "close", profileId: b.entries[0].profileId, slice: { at: b.entries[0].at, to: b.entries[0].to }, title: boardName(b, w), who: b.entries[0], fact: valueText(b.entries[0], w, lang), sub: `${exactText(b.entries[1].value)} · ${t.spotVs}`, trail: b.entries[0].trail, href: replayLink(b.entries[0].profileId, b.entries[0].at, b.entries[0].to) });
    }
    for (const b of boards) {
      const kind = b.metric === "door" ? "dungeon" : SPOT_KINDS[b.section];
      if (!kind || !b.entries.length) continue;
      const e = b.entries[0];
      out.push({ kind, profileId: e.profileId, slice: { at: e.at, to: e.to }, title: boardName(b, w), who: e, fact: valueText(e, w, lang), sub: detailText(b.metric, e, w) ?? undefined, trail: e.trail, href: replayLink(e.profileId, e.at, e.to) });
    }
    return out.filter(p => !bad.has(p.profileId));
  }, [highlights.data, chronicles.data, w, lang, t, bad]);
  if (!loaded) return null;
  if (!picks.length) return (
    <section className="hl-spot hl-spot-empty" aria-label={t.spotNames.chronicle}>
      <span className="hl-spot-label"><SectionGlyph id="close" size={18} /> {t.spotNames.chronicle}</span>
      <p role="status">{chronicles.error || highlights.error || bad.size ? t.spotUnavailable : t.spotEmpty}</p>
      <a href="#chronicle">{t.spotOpen} →</a>
    </section>
  );
  // a kind first, so a hundred quest boards do not drown the one chronicle
  const kinds = [...new Set(picks.map(p => p.kind))];
  const kind = kinds[Math.floor(draw * kinds.length)];
  const ofKind = picks.filter(p => p.kind === kind);
  const pick = picks.find(p => p.href === chosen) ?? ofKind[Math.floor((draw * 9973) % ofKind.length)];
  const alternatives = picks.filter(p => p.href !== pick.href);
  const another = () => {
    const kinds = [...new Set(alternatives.map(p => p.kind))];
    const kind = kinds[Math.floor(Math.random() * kinds.length)];
    const choices = alternatives.filter(p => p.kind === kind);
    if (choices.length) setChosen(choices[Math.floor(Math.random() * choices.length)].href);
  };
  return (
    <section className={`hl-spot is-${pick.kind}`} aria-label={t.spotNames[pick.kind]}>
      <div className="hl-spot-head">
        <span className="hl-spot-label"><SectionGlyph id={pick.kind === "dungeon" ? "dungeons" : pick.kind === "quest" ? "quests" : pick.kind === "levelling" ? "levelling" : pick.kind === "profession" ? "professions" : pick.kind === "deathless" ? "deathless" : "close"} size={18} /> {t.spotNames[pick.kind]}</span>
        {alternatives.length > 0 && <span className="hl-spot-actions"><button type="button" onClick={another}>{t.spotAnother}</button></span>}
      </div>
      <SpotPlayer key={pick.href} pick={pick} onFail={onFail} />
      <div className="hl-spot-body">
        <Face classId={pick.who?.classId ?? null} size={44} />
        <span className="hl-spot-text">
          <b>{pick.title}</b>
          <small>{pick.who ? [pick.who.name, pick.who.realm, pick.who.level ? `${w.level} ${pick.who.level}` : null].filter(Boolean).join(" · ") : t.spotTexts[pick.kind]}</small>
          <small>{[pick.fact, pick.sub, pick.who ? t.spotTexts[pick.kind] : null].filter(Boolean).join(" · ")}</small>
        </span>
        {pick.trail && <Trail points={pick.trail} />}
      </div>
    </section>
  );
}

/** The small replay itself: it loads the actual selected recording and plays it, muted, over and over. */
function SpotPlayer({ pick, onFail }: { pick: Pick; onFail: (profileId: string) => void }) {
  const { lang } = useWords();
  const t = TEXT[lang === "cs" ? "cs" : "en"];
  const maps = useMaps();
  const [c, setC] = useState<Chronicle | null>(null);
  useEffect(() => {
    let cancelled = false;
    const profileId = pick.profileId;
    const controller = new AbortController();
    api<{ chronicle: unknown }>(`/api/chronicle?profile=${encodeURIComponent(profileId)}&days=0`, { signal: controller.signal })
      .then(data => { const parsed = data.chronicle ? parseChronicle(data.chronicle) : null; if (cancelled) return; if (parsed) setC(parsed); else onFail(profileId); })
      .catch(() => { if (!cancelled) onFail(profileId); });
    return () => { cancelled = true; controller.abort(); };
  }, [pick.profileId, pick.kind, onFail]);
  if (maps.error) return <div className="chr chr-mini chr-mini-error" role="status">{t.spotUnavailable}<a href={pick.href}>{t.spotWatch}</a></div>;
  if (!c || !maps.data) return <div className="chr chr-mini chr-mini-wait" role="status" aria-label={t.loading} />;
  return <MiniPlayer c={c} maps={maps.data} slice={pick.slice} fullHref={pick.href} profileId={pick.profileId} />;
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
  const paged = usePaged(feed, h => [h.name, h.realm, boardName(h, w), w.sectionName[h.section]].filter(Boolean).join(" "));
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
              <PagedSearch value={paged.query} onChange={paged.setQuery} placeholder={t.searchFeed} />
              {paged.total ? <Feed items={paged.rows} /> : <p className="muted">{t.noMatch}</p>}
              <Pager page={paged.page} pages={paged.pages} onPage={paged.setPage} previous={t.previous} next={t.next} label={t.pagesLabel} />
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

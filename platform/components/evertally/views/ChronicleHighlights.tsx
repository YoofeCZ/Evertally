"use client";
// The pieces of the Highlights page and of the home page: the feed of records and placings (every line opens the replay of that stretch of
// the journey), and the boards with a podium. They read what players chose to share in their public chronicles; the times are time played
// between two events of the recording, not a stopwatch of the game.
import { useState } from "react";
import { useI18n } from "@/lib/i18n";
import type { Board, Entry, Highlight, Highlights, Section } from "@/lib/chronicle-highlights";
import { useApi } from "../api";
import { classIconUrl } from "./ChronicleArt";

export const SECTIONS: Section[] = ["levelling", "quests", "dungeons", "professions", "deathless"];

const TEXT = {
  en: {
    record: "The record on", podium: (n: number) => `Onto the podium, ${n}${n === 2 ? "nd" : "rd"} on`, best: "Personal best on", recorded: "Recorded", open: "Open", whole: "See the whole board", less: "Show less",
    play: "Replay this", level: "Level", to: "to", today: "Today", yesterday: "Yesterday", recordSince: "The record", firstHere: "First recorded here", bosses: (n: number) => `${n} ${n === 1 ? "boss" : "bosses"}`,
    sub: { quest: "Fastest from accepting to handing in", levelling: "Fastest, in time played", door: "Fastest from the door to the last boss", first: "First to clear it", profession: "Fastest to raise it, in time played", deathless: "Highest level before the first death" },
    deathless: "Furthest without dying", sectionName: { levelling: "Levelling", quests: "Quests", dungeons: "Dungeons", professions: "Professions", deathless: "Deathless" } as Record<Section, string>,
    closeRaces: "Close races", closeText: "The boards where second place is nearest the record.",
    sectionText: {
      levelling: "How fast a character gets through ten levels, and from level 1.", quests: "How fast a quest goes from accepting it to handing it in. Every quest has a board.",
      dungeons: "How fast a party clears a dungeon from the door to the last boss, and who cleared it first.", professions: "How fast a profession rises from tier to tier.", deathless: "How far a new character gets before it dies for the first time.",
    } as Record<Section, string>,
    all: (n: number) => `All ${n}`, lowerBy: (n: number) => `${n} ${n === 1 ? "level" : "levels"} lower`,
  },
  cs: {
    record: "Rekord na", podium: (n: number) => `Na stupních vítězů, ${n}. místo na`, best: "Osobní rekord na", recorded: "Zaznamenáno", open: "Volné", whole: "Celý žebříček", less: "Méně",
    play: "Přehrát", level: "Úroveň", to: "až", today: "Dnes", yesterday: "Včera", recordSince: "Rekord", firstHere: "Poprvé zaznamenáno tady", bosses: (n: number) => `${n} ${n === 1 ? "boss" : n < 5 ? "bossové" : "bossů"}`,
    sub: { quest: "Nejrychleji od přijetí po odevzdání", levelling: "Nejrychleji, v čase hraní", door: "Nejrychleji od vstupu po posledního bosse", first: "Kdo ho dokončil první", profession: "Nejrychleji zvýšená, v čase hraní", deathless: "Nejvyšší úroveň před první smrtí" },
    deathless: "Nejdál bez smrti", sectionName: { levelling: "Levelování", quests: "Questy", dungeons: "Dungeony", professions: "Profese", deathless: "Bez smrti" } as Record<Section, string>,
    closeRaces: "Těsné souboje", closeText: "Žebříčky, kde je druhé místo nejblíž rekordu.",
    sectionText: {
      levelling: "Jak rychle postava projde deset úrovní, a od úrovně 1.", quests: "Jak rychle jde quest od přijetí po odevzdání. Každý quest má svůj žebříček.",
      dungeons: "Jak rychle skupina projde dungeon od vstupu po posledního bosse a kdo ho dokončil první.", professions: "Jak rychle profese stoupá z úrovně na úroveň.", deathless: "Jak daleko se nová postava dostane, než poprvé zemře.",
    } as Record<Section, string>,
    all: (n: number) => `Všech ${n}`, lowerBy: (n: number) => `o ${n} ${n === 1 ? "úroveň" : n < 5 ? "úrovně" : "úrovní"} níž`,
  },
};
export type Words = (typeof TEXT)["en"];
export const useWords = () => { const { lang } = useI18n(); return { w: TEXT[lang === "cs" ? "cs" : "en"], lang }; };

/** "32m 28s", "1h 24m": an exact length, the way the leaderboards write it. */
export function exactText(seconds: number): string {
  const s = Math.max(0, Math.round(seconds));
  if (s >= 3600) return `${Math.floor(s / 3600)}h ${String(Math.floor((s % 3600) / 60)).padStart(2, "0")}m`;
  if (s >= 60) return `${Math.floor(s / 60)}m ${String(s % 60).padStart(2, "0")}s`;
  return `${s}s`;
}
const locale = (lang: string) => (lang === "cs" ? "cs-CZ" : "en-GB");
const dayText = (at: number, lang: string) => new Date(at * 1000).toLocaleDateString(locale(lang), { day: "numeric", month: "short" });
const clockText = (at: number, lang: string) => new Date(at * 1000).toLocaleTimeString(locale(lang), { hour: "2-digit", minute: "2-digit" });
const dateTimeText = (at: number, lang: string) => `${dayText(at, lang)}, ${clockText(at, lang)}`;
function agoText(at: number, lang: string): string {
  const seconds = Math.round(at - Date.now() / 1000);
  const rtf = new Intl.RelativeTimeFormat(locale(lang), { numeric: "auto" });
  const abs = Math.abs(seconds);
  if (abs < 3600) return rtf.format(Math.round(seconds / 60), "minute");
  if (abs < 86400) return rtf.format(Math.round(seconds / 3600), "hour");
  return rtf.format(Math.round(seconds / 86400), "day");
}
export const replayLink = (id: string, at: number, to: number) => `#chronicle/${encodeURIComponent(id)}?at=${Math.round(at)}&to=${Math.round(to)}`;

type Named = { metric: Board["metric"]; title: string; from?: number; upTo?: number };
/** The name of a board as the game's players would say it. */
export function boardName(b: Named, w: Words): string {
  switch (b.metric) {
    case "levelling": return `${w.level} ${b.from} ${w.to} ${b.upTo}`;
    case "profession": return `${b.title} ${b.from} ${w.to} ${b.upTo}`;
    case "deathless": return w.deathless;
    default: return b.title;
  }
}
const valueText = (e: { value: number; unit: Entry["unit"] }, w: Words, lang: string) => (e.unit === "seconds" ? exactText(e.value) : e.unit === "level" ? `${w.level} ${e.value}` : dateTimeText(e.value, lang));
const detailText = (metric: Board["metric"], e: Entry, w: Words): string | null => {
  if (e.detail === undefined) return null;
  return metric === "door" ? w.bosses(e.detail) : metric === "first" || metric === "deathless" ? exactText(e.detail) : null;
};

export const useHighlights = () => useApi<Highlights>("/api/highlights");

/* ---------- small drawings ---------- */
const GLYPHS: Record<Section | "close", string> = {
  levelling: "M12 4l7 8h-4.5v8h-5v-8H5z",
  quests: "M9.5 9a2.5 2.5 0 1 1 3.6 2.3c-.8.4-1.1.9-1.1 1.7v.5h-2v-.6c0-1.5.8-2.2 1.7-2.7.5-.3.6-.5.6-.9a1 1 0 0 0-2 0zM11 16h2v2h-2z",
  dungeons: "M6 20V10a6 6 0 0 1 12 0v10h-3v-9a3 3 0 0 0-6 0v9z",
  professions: "M4 18l5-6 4 3 6-8 1.5 1.2L13 18l-4-3-3.4 4z",
  deathless: "M12 20s-7-4.5-7-9.5A4 4 0 0 1 12 8a4 4 0 0 1 7 2.5C19 15.5 12 20 12 20z",
  close: "M12 3l2.6 5.6 6 .7-4.4 4.1 1.2 6L12 16.5 6.6 19.4l1.2-6L3.4 9.3l6-.7z",
};
export const SectionGlyph = ({ id, size = 22 }: { id: Section | "close"; size?: number }) => (
  <span className={`hl-glyph is-${id}`}><svg viewBox="0 0 24 24" width={size} height={size} aria-hidden="true"><path d={GLYPHS[id]} fill="currentColor" /></svg></span>
);
const Crown = () => <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true"><path d="M3 8l4.5 4L12 5l4.5 7L21 8l-2 10H5z" fill="currentColor" /></svg>;
const Star = () => <svg viewBox="0 0 24 24" width="17" height="17" aria-hidden="true"><path d="M12 3l2.6 5.6 6 .7-4.4 4.1 1.2 6L12 16.5 6.6 19.4l1.2-6L3.4 9.3l6-.7z" fill="currentColor" /></svg>;

/** The shape of the route of a stretch, as a small thumbnail. */
export function Trail({ points }: { points: readonly number[] }) {
  if (points.length < 4) return <span className="hl-trail is-empty" aria-hidden="true" />;
  const list: string[] = [];
  for (let i = 0; i + 1 < points.length; i += 2) list.push(`${6 + points[i] * 0.88},${6 + points[i + 1] * 0.88}`);
  const [x0, y0] = list[0].split(","), [x1, y1] = list[list.length - 1].split(",");
  return (
    <span className="hl-trail" aria-hidden="true">
      <svg viewBox="0 0 100 100"><polyline points={list.join(" ")} fill="none" stroke="#e9b44c" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" /><circle cx={x0} cy={y0} r="4" fill="#e9b44c" /><circle cx={x1} cy={y1} r="4" fill="#e9b44c" /></svg>
    </span>
  );
}
export const Face = ({ classId, size = 36 }: { classId: number | null; size?: number }) => (
  <span className="hl-face" style={{ width: size, height: size, ...(classId ? { backgroundImage: `url(${classIconUrl(classId)})` } : {}) }} aria-hidden="true" />
);
const Play = ({ label, href }: { label: string; href: string }) => (
  <a className="hl-play" href={href} aria-label={label} title={label}><svg viewBox="0 0 24 24" width="15" height="15" aria-hidden="true"><path d="M8 5v14l11-7z" fill="currentColor" /></svg></a>
);

/* ---------- the feed ---------- */
export function FeedLine({ h }: { h: Highlight }) {
  const { w, lang } = useWords();
  const lead = h.kind === "record" ? w.record : h.kind === "podium" ? w.podium(h.rank) : w.best;
  const detail = detailText(h.metric, h, w);
  const facts = [valueText(h, w, lang), detail].filter(Boolean).join(" · ");
  const today = new Date(h.to * 1000).toDateString() === new Date().toDateString();
  return (
    <li className={`hl-line is-${h.kind}`}>
      <span className={`hl-badge is-${h.kind}`} aria-hidden="true">{h.kind === "record" ? <Crown /> : h.kind === "best" ? <Star /> : <b>{h.rank}</b>}</span>
      <Face classId={h.classId} />
      <span className="hl-text">
        <span><a className="hl-name" href={`#rankings/level?q=${encodeURIComponent(h.name)}`}>{h.name}</a> <b>{lead}</b> <a className="hl-board" href={replayLink(h.profileId, h.at, h.to)}>{boardName(h, w)}</a></span>
        <small>{facts}</small>
      </span>
      <span className="hl-when">{today ? agoText(h.to, lang) : clockText(h.to, lang)}</span>
      <Play label={w.play} href={replayLink(h.profileId, h.at, h.to)} />
    </li>
  );
}
/** The feed grouped by the day, as a list. */
export function Feed({ items }: { items: readonly Highlight[] }) {
  const { w, lang } = useWords();
  const groups: { key: string; label: string; items: Highlight[] }[] = [];
  const todayKey = new Date().toDateString(), yesterday = new Date(Date.now() - 86400_000).toDateString();
  for (const h of items) {
    const key = new Date(h.to * 1000).toDateString();
    let g = groups[groups.length - 1];
    if (!g || g.key !== key) { g = { key, label: key === todayKey ? w.today : key === yesterday ? w.yesterday : new Date(h.to * 1000).toLocaleDateString(locale(lang), { day: "numeric", month: "long" }), items: [] }; groups.push(g); }
    g.items.push(h);
  }
  return (
    <div className="hl-feed">
      {groups.map(g => <section key={g.key}><h3>{g.label}</h3><ul>{g.items.map(h => <FeedLine key={h.id} h={h} />)}</ul></section>)}
    </div>
  );
}

/* ---------- a board with a podium ---------- */
export function BoardCard({ b }: { b: Board }) {
  const { w, lang } = useWords();
  const [more, setMore] = useState(false);
  const first = b.entries[0];
  const sub = w.sub[b.metric];
  const shown = more ? b.entries.slice(1) : b.entries.slice(1, 3);
  const slots = more ? 0 : Math.max(0, 3 - b.entries.length);
  return (
    <article className="hl-board-card">
      <header>
        <SectionGlyph id={b.section} size={20} />
        <span><b>{boardName(b, w)}</b><small>{sub}</small></span>
      </header>
      <div className="hl-first">
        <span className="hl-first-top">
          <Face classId={first.classId} size={44} />
          <span><b className="hl-name">{first.name}</b><small>{[first.realm, first.level ? `${w.level} ${first.level}` : null].filter(Boolean).join(" · ")}</small></span>
        </span>
        <span className="hl-first-main">
          <strong>{valueText(first, w, lang)}</strong>
          <small>{detailText(b.metric, first, w) ?? ""}</small>
          <Trail points={first.trail} />
          <Play label={w.play} href={replayLink(first.profileId, first.at, first.to)} />
        </span>
        <i className="hl-bar" />
        <small className="hl-since">{w.recordSince} · {dayText(first.to, lang)}{b.total === 1 ? ` · ${w.firstHere}` : ""}</small>
      </div>
      <ol className="hl-rows">
        {shown.map((e, i) => (
          <li key={e.profileId}>
            <span className={`hl-rank r${i + 2}`}>{i + 2}</span>
            <Face classId={e.classId} size={30} />
            <span className="hl-row-name"><b>{e.name}</b>{b.metric === "deathless" && e.value < first.value ? <small>{w.lowerBy(first.value - e.value)}</small> : <small>{[e.realm, detailText(b.metric, e, w)].filter(Boolean).join(" · ")}</small>}</span>
            <span className="hl-row-value">{valueText(e, w, lang)}</span>
            <Play label={w.play} href={replayLink(e.profileId, e.at, e.to)} />
          </li>
        ))}
        {Array.from({ length: slots }, (_, i) => <li key={`open${i}`} className="is-open"><span className={`hl-rank r${shown.length + i + 2}`}>{shown.length + i + 2}</span><span className="hl-ghost" /><span className="hl-row-name"><i /><i /></span><span className="hl-row-value">{w.open}</span></li>)}
      </ol>
      <footer>
        {b.entries.length > 3 ? <button type="button" onClick={() => setMore(v => !v)}>{more ? w.less : w.whole}</button> : <span />}
        <span className="hl-recorded">{w.recorded}</span>
      </footer>
    </article>
  );
}

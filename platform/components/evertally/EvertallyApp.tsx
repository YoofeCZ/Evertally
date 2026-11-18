"use client";
import { useEffect, useRef, useState, useSyncExternalStore } from "react";
import { hasKey, useI18n, type Lang } from "@/lib/i18n";
import { useApi } from "./api";
import type { Status, View } from "./types";
import { DiscordGlyph, Icon, Logo } from "./ui";
import { AccountView, LinkView } from "./views/Account";
import { RunsView } from "./views/Data";
import { RankingsView } from "./views/Rankings";
import { CharacterView } from "./views/Character";
import { GuildView } from "./views/Guild";
import { ChronicleView } from "./views/Chronicle";
import { HighlightsView } from "./views/Highlights";
import { Overview } from "./views/Overview";
import { SyncView } from "./views/Sync";
import { ProfessionsView } from "./views/Professions";
import { ArmoryView } from "./views/Armory";
import { ForumView } from "./views/Forum";
import { DatabaseView } from "./db/Database";
import { MapView } from "./db/MapView";

const NAV: { id: Exclude<View, "link" | "character" | "guild">; key: "nav.overview" | "nav.runs" | "nav.rankings" | "nav.atlas" | "nav.chronicle" | "nav.highlights" | "nav.database" | "nav.professions" | "nav.armory" | "nav.forum" | "nav.sync" | "nav.account" }[] = [
  { id: "overview", key: "nav.overview" }, { id: "runs", key: "nav.runs" }, { id: "rankings", key: "nav.rankings" },
  { id: "highlights", key: "nav.highlights" }, { id: "chronicle", key: "nav.chronicle" }, { id: "database", key: "nav.database" }, { id: "professions", key: "nav.professions" }, { id: "armory", key: "nav.armory" }, { id: "forum", key: "nav.forum" }, { id: "sync", key: "nav.sync" }, { id: "account", key: "nav.account" },
];

/** The search in the top bar finds characters (and guilds shown on the board) in the leaderboard. */
function searchCharacters(text: string) {
  const q = text.trim().slice(0, 80);
  window.location.hash = `rankings/level${q ? `?q=${encodeURIComponent(q)}` : ""}`;
}

const subscribeHash = (onChange: () => void) => {
  window.addEventListener("hashchange", onChange);
  return () => window.removeEventListener("hashchange", onChange);
};
const subscribeNever = () => () => {};

export default function EvertallyApp({ initialView = "overview", code = "" }: { initialView?: View; code?: string }) {
  const { t, lang, setLang } = useI18n();
  const hash = useSyncExternalStore(subscribeHash, () => window.location.hash.slice(1), () => "");
  // `#atlas/durotar?focus=npc:3139`, `#database/items/19019`: the first segment is the view, the rest belongs to it.
  const head = hash.split(/[/?]/)[0];
  const route = hash.slice(head.length).replace(/^\//, "");
  const view: View = initialView === "link" ? "link" : head === "character" ? "character" : head === "guild" ? "guild" : head === "chronicle" ? "chronicle" : head === "atlas" ? "atlas" : NAV.some((n) => n.id === head) ? head as View : "overview";
  const authError = useSyncExternalStore(subscribeNever, () => new URLSearchParams(window.location.search).get("auth_error"), () => null);
  const [dismissed, setDismissed] = useState(false);
  const [version, setVersion] = useState(0);
  const status = useApi<Status>("/api/status", version);
  const user = status.data?.user ?? null;

  useEffect(() => { document.documentElement.lang = lang; }, [lang]);
  // the menu stays on top of everything while the page scrolls; the full-screen map starts below it (db.css reads --topbar-h)
  const bar = useRef<HTMLElement>(null);
  useEffect(() => {
    const element = bar.current;
    if (!element) return;
    const set = () => document.documentElement.style.setProperty("--topbar-h", `${element.getBoundingClientRect().height}px`);
    set();
    const observer = new ResizeObserver(set);
    observer.observe(element);
    return () => observer.disconnect();
  }, []);

  const go = (next: View) => {
    // /link is a separate route; leaving it is a full navigation to the main page.
    // eslint-disable-next-line @next/next/no-location-assign-relative-destination
    if (initialView === "link") { window.location.href = `/#${next}`; return; }
    if (window.location.hash !== `#${next}`) window.location.hash = next;
    window.scrollTo({ top: 0 });
  };
  const returnTo = initialView === "link" ? `/link${code ? `?code=${encodeURIComponent(code)}` : ""}` : `/#${view}`;
  const auth = status.data?.auth;
  const authReady = Boolean(status.data);
  const signIn = auth?.discord ? `/auth/discord?return_to=${encodeURIComponent(returnTo)}` : auth?.devLogin ? `/auth/dev?return_to=${encodeURIComponent(returnTo)}` : null;
  const signOut = async () => {
    await fetch("/auth/logout", { method: "POST" });
    setVersion((v) => v + 1);
  };
  const dismissError = () => {
    setDismissed(true);
    const url = new URL(window.location.href);
    url.searchParams.delete("auth_error");
    window.history.replaceState(null, "", url);
  };
  const authKey = `auth.${authError}`;

  return (
    <div className="site">
      <a className="skip" href="#main">Skip to content</a>
      <header className="topbar" ref={bar}>
        <button className="wordmark" onClick={() => go("overview")} aria-label="Evertally"><Logo /> <span>Evertally</span></button>
        <nav className="nav" aria-label="Main">
          {NAV.map((item) => (
            <button key={item.id} className={view === item.id || (item.id === "rankings" && (view === "guild" || view === "character")) ? "on" : ""} aria-current={view === item.id ? "page" : undefined} onClick={() => go(item.id)}>{t(item.key)}</button>
          ))}
        </nav>
        <form className="top-search" role="search" onSubmit={(event) => { event.preventDefault(); searchCharacters(String(new FormData(event.currentTarget).get("q") ?? "")); }}>
          <button type="submit" aria-label={t("nav.search")} title={t("nav.search")}><Icon name="search" size={14} /></button>
          <input name="q" type="search" maxLength={80} placeholder={t("nav.searchPlaceholder")} aria-label={t("nav.search")} />
        </form>
        <div className="top-actions">
          <div className="lang" role="group" aria-label={t("nav.language")}>
            {(["en", "cs"] as Lang[]).map((l) => <button key={l} className={lang === l ? "on" : ""} onClick={() => setLang(l)}>{l.toUpperCase()}</button>)}
          </div>
          {user ? (
            <div className="user-chip">
              {/* eslint-disable-next-line @next/next/no-img-element -- 26px Discord CDN avatar, no optimization needed */}
              {user.avatarUrl ? <img src={user.avatarUrl} alt="" width={26} height={26} /> : <span className="avatar">{user.displayName.charAt(0)}</span>}
              <span className="user-name">{user.displayName}</span>
              <button className="icon-btn" onClick={() => void signOut()} aria-label={t("nav.signOut")} title={t("nav.signOut")}><Icon name="logout" size={16} /></button>
            </div>
          ) : signIn ? (
            <a className={`btn btn-sm ${auth?.discord ? "btn-discord" : "btn-ghost"}`} href={signIn}>{auth?.discord ? <><DiscordGlyph size={16} /> {t("nav.signIn")}</> : t("nav.devSignIn")}</a>
          ) : null}
        </div>
      </header>

      {authError && !dismissed && (
        <div className="notice error banner page-column" role="alert">
          <span>{hasKey(authKey) ? t(authKey) : t("error.generic")}</span>
          <button className="icon-btn" onClick={dismissError} aria-label={t("common.close")}><Icon name="close" size={14} /></button>
        </div>
      )}

      <main id="main">
        {view === "overview" && <Overview status={status.data} go={go} />}
        {view === "runs" && <RunsView user={user} />}
        {view === "rankings" && <RankingsView route={route} user={user} />}
        {view === "character" && <CharacterView id={decodeURIComponent(route.split("?")[0])} />}
        {view === "guild" && <GuildView route={route} />}
        {view === "highlights" && <HighlightsView />}
        {view === "chronicle" && <ChronicleView route={route} user={user} signIn={signIn} />}
        {view === "atlas" && <MapView route={route} user={user} signIn={signIn} />}
        {view === "database" && <DatabaseView route={route} />}
        {view === "professions" && <ProfessionsView user={user} signIn={signIn} authReady={authReady} />}
        {view === "armory" && <ArmoryView user={user} signIn={signIn} authReady={authReady} route={route} />}
        {view === "forum" && <ForumView route={route} user={user} signIn={signIn} />}
        {view === "sync" && <SyncView user={user} signIn={signIn} />}
        {view === "account" && <AccountView user={user} signIn={signIn} authReady={authReady} onChanged={() => setVersion((v) => v + 1)} />}
        {view === "link" && <LinkView user={user} signIn={signIn} authReady={authReady} initialCode={code} />}
      </main>

      <footer className="footer page-column">
        <div className="footer-brand"><Logo size={26} /> <strong>Evertally</strong><span className="muted">{t("brand.tagline")}</span></div>
        <p className="muted">{t("footer.note")}</p>
        <span className="status-line"><i className="pulse" /> {t("footer.status", { version: status.data?.version ?? "…" })}</span>
      </footer>
    </div>
  );
}

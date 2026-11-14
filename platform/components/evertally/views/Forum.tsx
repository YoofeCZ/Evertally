"use client";
import { useState } from "react";
import { useI18n, hasKey } from "@/lib/i18n";
import { FORUM_CATEGORIES, BODY_MAX, TITLE_MAX, type ForumCategory, type ForumPost, type ForumThread } from "@/lib/forum-shared";
import { ApiFailure, api, useApi } from "../api";
import { CLASSES } from "../data";
import type { User } from "../types";
import { DiscordGlyph, Empty, Icon, Tag } from "../ui";
import { PageHead } from "./Data";

type ManagedThread = ForumThread & { canModerate?: boolean };
type Listing = { categories: { id: ForumCategory; threads: number }[]; threads: ManagedThread[]; hasMore: boolean; page: number };
type Thread = { thread: ManagedThread; posts: ForumPost[] };
type Character = { id: string; name: string; classId: number | null };
function navigateForumHash(hash: string) { window.location.hash = hash; }

export function ForumView({ route, user, signIn }: { route: string; user: User | null; signIn: string | null }) {
  const { t, lang } = useI18n();
  const params = new URLSearchParams(route.split("?")[1] ?? "");
  const category = FORUM_CATEGORIES.find((id) => id === params.get("category")) ?? "";
  const requestedPage = Number(params.get("page"));
  const page = Number.isFinite(requestedPage) ? Math.max(0, Math.min(500, Math.floor(requestedPage))) : 0;
  const search = (params.get("q") ?? "").slice(0, 80);
  const [version, setVersion] = useState(0);
  const [writing, setWriting] = useState(false);
  // "#forum/<threadId>" opens a thread; "#forum" is the list
  const threadId = route.split(/[/?]/)[0];
  const listing = useApi<Listing>(threadId ? null : `/api/forum?${new URLSearchParams({ ...(category ? { category } : {}), ...(search ? { q: search } : {}), page: String(page) })}`, version);
  const refresh = () => setVersion((v) => v + 1);
  const queryString = (cat: string, p: number, q: string) => {
    const query = new URLSearchParams();
    if (cat) query.set("category", cat);
    if (p) query.set("page", String(p));
    if (q.trim()) query.set("q", q.trim().slice(0, 80));
    const result = query.toString();
    return result ? `?${result}` : "";
  };
  const filter = (cat: string, p: number, q: string) => { navigateForumHash(`forum${queryString(cat, p, q)}`); };
  const open = (id: string) => { navigateForumHash(`${id ? `forum/${id}` : "forum"}${queryString(category, page, search)}`); window.scrollTo({ top: 0 }); };
  const categoryName = (id: string) => hasKey(`forum.cat.${id}`) ? t(`forum.cat.${id}` as never) : id;
  const signInLink = signIn && <a className={`btn btn-sm ${signIn.startsWith("/auth/discord") ? "btn-discord" : "btn-ghost"}`} href={signIn}>{signIn.startsWith("/auth/discord") ? <><DiscordGlyph size={16} /> {t("forum.signIn")}</> : t("nav.devSignIn")}</a>;
  return <>
    <PageHead title={t("forum.title")} lead={t("forum.lead")} />
    <div className="page-column forum">
      {threadId ? <ThreadPage id={threadId} user={user} signInLink={signInLink} categoryName={categoryName} back={() => open("")} /> : <>
        <div className="forum-layout"><aside className="forum-rail"><div className="hall-eyebrow">EVERTALLY / {t("forum.title")}</div><h2>{t("forum.category")}</h2>
          <div className="forum-tabs" role="group" aria-label={t("forum.category")}>
            <button className={category === "" ? "on" : ""} aria-pressed={category === ""} onClick={() => filter("", 0, search)}>{t("forum.all")}</button>
            {FORUM_CATEGORIES.map((id) => <button key={id} className={category === id ? "on" : ""} aria-pressed={category === id} onClick={() => filter(id, 0, search)}>
              {categoryName(id)} <span className="forum-count">{listing.data ? listing.data.categories.find((c) => c.id === id)?.threads ?? 0 : "—"}</span></button>)}
          </div>
        </aside><div className="forum-main"><div className="forum-main-head"><div><span className="hall-eyebrow">{t("forum.title")}</span><h2>{category ? categoryName(category) : t("forum.all")}</h2></div>{user ? <button className="btn btn-sm" onClick={() => setWriting((v) => !v)}>{t("forum.newThread")}</button> : signInLink}</div>
        <ForumSearch key={search} current={search} cs={lang === "cs"} onSearch={(q) => filter(category, 0, q)} />
        {writing && user && <Composer thread key="new" initialCategory={category || "general"} onDone={(id) => { setWriting(false); refresh(); if (id) open(id); }} onCancel={() => setWriting(false)} />}
        {listing.error ? <p className="notice error" role="alert">{t("error.service_unavailable")}</p>
          : !listing.data ? <p className="muted">{t("forum.loading")}</p>
          : listing.data.threads.length === 0 ? <Empty icon="chat" title={search ? (lang === "cs" ? "Nic jsme nenašli" : "No results found") : t("forum.empty")}>{search ? (lang === "cs" ? "Zkus jiné hledání nebo kategorii." : "Try a different search or category.") : t("forum.emptyText")}</Empty>
          : <ul className="forum-list">{listing.data.threads.map((th) => <li key={th.id}>
              <button className="forum-row" onClick={() => open(th.id)}><span className="forum-topic-icon"><Icon name="chat" size={18} /></span>
                <span className="forum-row-main"><strong>{th.pinned && <Icon name="pin" size={14} />} {th.title}</strong>
                  <span className="muted"><Author name={th.author} classId={th.classId} /> · {th.origin === "game" ? t("forum.fromGame") : t("forum.fromWeb")}</span></span>
                <span className="forum-row-side"><Tag tone="lilac">{categoryName(th.category)}</Tag><span className="muted">{t("forum.replies", { count: th.replies })}</span><Stamp at={th.lastPostAt} /></span>
              </button></li>)}</ul>}
        {listing.data && (page > 0 || listing.data.hasMore) && <div className="forum-pager">
          <button className="btn btn-sm btn-ghost" disabled={page === 0} onClick={() => filter(category, page - 1, search)}>{t("forum.newer")}</button>
          <button className="btn btn-sm btn-ghost" disabled={!listing.data.hasMore} onClick={() => filter(category, page + 1, search)}>{t("forum.more")}</button></div>}</div></div>
      </>}
      <p className="fine-print">{t("forum.note")}</p>
    </div>
  </>;
}

function ForumSearch({ current, cs, onSearch }: { current: string; cs: boolean; onSearch: (q: string) => void }) {
  const [draft, setDraft] = useState(current);
  return <form className="forum-search" role="search" onSubmit={(event) => { event.preventDefault(); onSearch(draft); }}>
    <label className="field"><span>{cs ? "Hledat ve fóru" : "Search the forum"}</span><input type="search" value={draft} maxLength={80} onChange={(event) => setDraft(event.target.value)} placeholder={cs ? "Název, text nebo autor" : "Title, content or author"} /></label>
    <button className="btn btn-sm" type="submit">{cs ? "Hledat" : "Search"}</button>
    {current && <button className="btn btn-sm btn-ghost" type="button" onClick={() => onSearch("")}>{cs ? "Vymazat hledání" : "Clear search"}</button>}
  </form>;
}

function Stamp({ at }: { at: number }) {
  const { date } = useI18n();
  return <span className="muted">{date(at)}</span>;
}

function Author({ name, classId }: { name: string; classId: number | null }) {
  return <span className="forum-author" title={classId ? CLASSES[classId] : undefined} data-class={classId ?? undefined}>{name}</span>;
}

function ThreadPage({ id, user, signInLink, categoryName, back }: { id: string; user: User | null; signInLink: React.ReactNode; categoryName: (id: string) => string; back: () => void }) {
  const { t, lang } = useI18n();
  const [version, setVersion] = useState(0);
  const [replyTo, setReplyTo] = useState<ForumPost | null>(null);
  const [editing, setEditing] = useState<string | null>(null);
  const [actionError, setActionError] = useState("");
  const [deleting, setDeleting] = useState<string | null>(null);
  const [moderating, setModerating] = useState(false);
  const data = useApi<Thread>(`/api/forum/threads/${encodeURIComponent(id)}`, version);
  const names = new Map(data.data?.posts.map((p) => [p.id, p.author]) ?? []);
  const remove = async (post: ForumPost) => {
    const prompt = post.id === id
      ? (lang === "cs" ? "Smazat celé vlákno včetně odpovědí?" : "Delete the entire thread and its replies?")
      : t("forum.deleteAsk");
    if (!window.confirm(prompt)) return;
    setActionError(""); setDeleting(post.id);
    try {
      await api(`/api/forum/posts/${encodeURIComponent(post.id)}`, { method: "DELETE" });
      if (post.id === id) back(); else { setEditing(null); setVersion((v) => v + 1); }
    } catch (caught) {
      const code = caught instanceof ApiFailure ? caught.code : "generic";
      setActionError(hasKey(`forum.err.${code}`) ? t(`forum.err.${code}` as never) : t("forum.err.generic"));
    } finally { setDeleting(null); }
  };
  const moderate = async (change: { pinned: boolean }) => {
    setActionError(""); setModerating(true);
    try {
      await api(`/api/forum/threads/${encodeURIComponent(id)}`, { method: "PATCH", body: JSON.stringify(change) });
      setReplyTo(null); setVersion((v) => v + 1);
    } catch (caught) {
      const code = caught instanceof ApiFailure ? caught.code : "generic";
      setActionError(hasKey(`forum.err.${code}`) ? t(`forum.err.${code}` as never) : t("forum.err.generic"));
    } finally { setModerating(false); }
  };
  return <>
    <button className="link-btn" onClick={back}>← {t("forum.back")}</button>
    {data.error ? <p className="notice error" role="alert">{data.error.status === 404 ? t("forum.err.not_found") : t("error.service_unavailable")}</p>
      : !data.data ? <p className="muted">{t("forum.loading")}</p> : <>
        <div className="forum-thread-heading"><span className="hall-eyebrow">{t("forum.title")} / {categoryName(data.data.thread.category)}</span><h2>{data.data.thread.title}</h2>
        <p className="muted"><Tag tone="lilac">{categoryName(data.data.thread.category)}</Tag> {t("forum.replies", { count: data.data.thread.replies })} {data.data.thread.pinned && <span className="forum-state">{lang === "cs" ? "Připnuto" : "Pinned"}</span>}</p>
        {user && data.data.thread.canModerate === true && <div className="forum-moderation" aria-label={lang === "cs" ? "Správa vlákna" : "Manage thread"}>
          <button className="btn btn-sm btn-ghost" disabled={moderating} onClick={() => void moderate({ pinned: !data.data!.thread.pinned })}>{data.data.thread.pinned ? (lang === "cs" ? "Odepnout" : "Unpin") : (lang === "cs" ? "Připnout" : "Pin")}</button>
        </div>}</div>
        {actionError && <p className="notice error" role="alert">{actionError}</p>}
        <ol className="forum-posts">{data.data.posts.map((post) => <li key={post.id} className="forum-post" id={`post-${post.id}`}>
          <header><Author name={post.author} classId={post.classId} /> <span className="muted">· {post.origin === "game" ? t("forum.fromGame") : t("forum.fromWeb")} · <Stamp at={post.createdAt} /></span></header>
          {post.replyTo && post.replyTo !== id && names.get(post.replyTo) && <p className="forum-quote">{t("forum.replyTo", { name: names.get(post.replyTo) ?? "" })}</p>}
          {editing === post.id ? <EditPost post={post} title={post.id === id ? data.data!.thread.title : undefined}
            onCancel={() => setEditing(null)} onDone={() => { setEditing(null); setVersion((v) => v + 1); }} />
            : <p className="forum-body">{post.body}</p>}
          <footer>{user && <button className="link-btn" onClick={() => setReplyTo(post)}>{t("forum.reply")}</button>}
            {user && (post as ForumPost & { canManage?: boolean }).canManage === true && editing !== post.id && <>
              <button className="link-btn" onClick={() => { setActionError(""); setEditing(post.id); }}>{lang === "cs" ? "Upravit" : "Edit"}</button>
              <button className="link-btn forum-delete" disabled={deleting !== null} onClick={() => void remove(post)}>{t("forum.delete")}</button>
            </>}
          </footer>
        </li>)}</ol>
        {user ? <Composer key={replyTo?.id ?? "top"} threadId={id} replyTo={replyTo} onDone={() => { setReplyTo(null); setVersion((v) => v + 1); }} onCancel={replyTo ? () => setReplyTo(null) : undefined} /> : signInLink}
      </>}
  </>;
}

function EditPost({ post, title: initialTitle, onCancel, onDone }: { post: ForumPost; title?: string; onCancel: () => void; onDone: () => void }) {
  const { t, lang } = useI18n();
  const [body, setBody] = useState(post.body);
  const [title, setTitle] = useState(initialTitle ?? "");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const ready = body.trim().length > 0 && (initialTitle === undefined || title.trim().length >= 3) && !busy;
  const submit = async () => {
    setBusy(true); setError("");
    try {
      await api(`/api/forum/posts/${encodeURIComponent(post.id)}`, { method: "PATCH", body: JSON.stringify({ body, ...(initialTitle !== undefined ? { title } : {}) }) });
      onDone();
    } catch (caught) {
      const code = caught instanceof ApiFailure ? caught.code : "generic";
      setError(hasKey(`forum.err.${code}`) ? t(`forum.err.${code}` as never) : t("forum.err.generic"));
    } finally { setBusy(false); }
  };
  return <form className="forum-edit" onSubmit={(event) => { event.preventDefault(); if (ready) void submit(); }}>
    {initialTitle !== undefined && <label className="field"><span>{t("forum.threadTitle")}</span><input value={title} maxLength={TITLE_MAX} onChange={(event) => setTitle(event.target.value)} /></label>}
    <label className="field"><span>{t("forum.threadBody")} · {t("forum.chars", { count: body.length, max: BODY_MAX })}</span><textarea value={body} maxLength={BODY_MAX} rows={5} onChange={(event) => setBody(event.target.value)} /></label>
    {error && <p className="notice error" role="alert">{error}</p>}
    <div className="forum-actions"><button className="btn btn-sm" type="submit" disabled={!ready}>{lang === "cs" ? "Uložit změny" : "Save changes"}</button><button className="btn btn-sm btn-ghost" type="button" disabled={busy} onClick={onCancel}>{t("forum.cancel")}</button></div>
  </form>;
}

type ComposerProps = { onDone: (threadId?: string) => void; onCancel?: () => void } & (
  | { thread: true; initialCategory: ForumCategory; threadId?: undefined; replyTo?: undefined }
  | { thread?: false; threadId: string; replyTo: ForumPost | null; initialCategory?: undefined });

function Composer(props: ComposerProps) {
  const { t } = useI18n();
  const characters = useApi<{ characters: Character[] }>("/api/forum/characters");
  const [profileId, setProfileId] = useState("");
  const [category, setCategory] = useState<ForumCategory>(props.thread ? props.initialCategory : "general");
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const submit = async () => {
    setBusy(true); setError("");
    try {
      const payload = props.thread ? { category, title, body, ...(profileId ? { profileId } : {}) } : { threadId: props.threadId, body, ...(props.replyTo ? { replyTo: props.replyTo.id } : {}), ...(profileId ? { profileId } : {}) };
      const made = await api<Thread>(props.thread ? "/api/forum/threads" : "/api/forum/posts", { method: "POST", body: JSON.stringify(payload) });
      setBody(""); setTitle("");
      props.onDone(props.thread ? made.thread.id : undefined);
    } catch (caught) {
      const code = caught instanceof ApiFailure ? caught.code : "generic";
      setError(hasKey(`forum.err.${code}`) ? t(`forum.err.${code}` as never) : t("forum.err.generic"));
    } finally { setBusy(false); }
  };
  const list = characters.data?.characters ?? [];
  const ready = body.trim().length > 0 && (!props.thread || title.trim().length >= 3) && !busy;
  return <form className="forum-composer" onSubmit={(event) => { event.preventDefault(); if (ready) void submit(); }}>
    {props.replyTo && <p className="forum-quote">{t("forum.replyTo", { name: props.replyTo.author })}</p>}
    <div className="toolbar">
      {props.thread && <label className="field"><span>{t("forum.category")}</span><select value={category} onChange={(event) => setCategory(event.target.value as ForumCategory)}>{FORUM_CATEGORIES.map((id) => <option key={id} value={id}>{t(`forum.cat.${id}` as never)}</option>)}</select></label>}
      <label className="field"><span>{t("forum.character")}</span><select value={profileId} onChange={(event) => setProfileId(event.target.value)}>
        <option value="">{t("forum.accountName")}</option>{list.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}</select></label>
    </div>
    {props.thread && <label className="field"><span>{t("forum.threadTitle")}</span><input value={title} maxLength={TITLE_MAX} onChange={(event) => setTitle(event.target.value)} /></label>}
    <label className="field"><span>{t("forum.threadBody")} · {t("forum.chars", { count: body.length, max: BODY_MAX })}</span><textarea value={body} maxLength={BODY_MAX} rows={props.thread ? 6 : 4} onChange={(event) => setBody(event.target.value)} /></label>
    {error && <p className="notice error" role="alert">{error}</p>}
    <div className="forum-actions"><button className="btn btn-sm" type="submit" disabled={!ready}>{t("forum.post")}</button>{props.onCancel && <button className="btn btn-sm btn-ghost" type="button" onClick={props.onCancel}>{t("forum.cancel")}</button>}</div>
  </form>;
}

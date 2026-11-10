"use client";
import { useRef, useState } from "react";
import type { ChangeEvent } from "react";
import { projectExport, type ExportEnvelope, type Scope } from "@/lib/import";
import { scopeFor } from "@/lib/contracts";
import { hasKey, useI18n } from "@/lib/i18n";
// vinext rewrites import.meta.url to a file:/// constant, so Vite must provide the worker URL.
import importWorkerUrl from "../../import-worker.ts?worker&url";
import { api, ApiFailure } from "../api";
import type { Grant, User } from "../types";
import { ConsoleWindow, Icon, Tag } from "../ui";
import { PageHead } from "./Data";

export const SCOPE_ORDER: Scope[] = ["world_facts", "own_runs", "own_character", "own_professions", "own_track", "guild_share"];
export const SCOPE_ICON: Record<Scope, string> = { world_facts: "map", own_runs: "sword", own_character: "user", own_professions: "anvil", own_track: "route", guild_share: "guild" };

function parseFile(file: File): Promise<ExportEnvelope> {
  if (file.size > 25 * 1024 * 1024) return Promise.reject(new Error("The file is larger than 25 MiB."));
  return file.text().then((text) => new Promise((resolve, reject) => {
    const worker = new Worker(importWorkerUrl, { type: "module" });
    const timer = setTimeout(() => { worker.terminate(); reject(new Error("Reading the file took too long.")); }, 15000);
    worker.onmessage = (event) => {
      clearTimeout(timer);
      worker.terminate();
      if (event.data.ok) resolve(event.data.data);
      else reject(new Error(event.data.error));
    };
    worker.onerror = () => { clearTimeout(timer); worker.terminate(); reject(new Error("The parser could not start.")); };
    worker.postMessage({ text });
  }));
}

function ManualImport({ user, signIn }: { user: User | null; signIn: string | null }) {
  const { t, num } = useI18n();
  const input = useRef<HTMLInputElement>(null);
  const [preview, setPreview] = useState<ExportEnvelope | null>(null);
  const [scopes, setScopes] = useState<Scope[]>([]);
  const [consent, setConsent] = useState(false);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<{ tone: "info" | "error" | "success"; text: string } | null>(null);

  const counts = (preview?.events ?? []).reduce<Record<string, number>>((acc, e) => { const s = scopeFor(e.kind); acc[s] = (acc[s] ?? 0) + 1; return acc; }, {});
  const selected = preview ? projectExport(preview, scopes).events.length : 0;

  const choose = async (event: ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    event.target.value = "";
    if (!file) return;
    setBusy(true);
    try {
      const data = await parseFile(file);
      if (!data.enabled) throw new Error(t("sync.manual.disabled"));
      setPreview(data);
      setScopes(SCOPE_ORDER.filter((s) => data.scopes.includes(s) && s !== "own_character"));
      setConsent(false);
      setMessage({ tone: "info", text: t("sync.manual.loaded", { count: num(data.events.length) }) });
    } catch (error) {
      setMessage({ tone: "error", text: error instanceof Error ? error.message : t("error.generic") });
    } finally {
      setBusy(false);
    }
  };

  const send = async () => {
    if (!preview || !consent || !scopes.length) return;
    setBusy(true);
    try {
      const projected = projectExport(preview, scopes);
      const { grant } = await api<{ grant: Grant }>("/api/consents", { method: "POST", body: JSON.stringify({ producerId: preview.producerId, consentEpoch: preview.consentEpoch, since: preview.since, scopes }) });
      let accepted = 0;
      let duplicates = 0;
      for (let i = 0; i < projected.events.length; i += 250) {
        const result = await api<{ accepted: number; duplicates: number }>("/api/uploads", { method: "POST", body: JSON.stringify({ grantId: grant.id, export: { ...projected, events: projected.events.slice(i, i + 250) } }) });
        accepted += result.accepted;
        duplicates += result.duplicates;
      }
      setMessage({ tone: "success", text: t("sync.manual.result", { accepted: num(accepted), duplicates: num(duplicates) }) });
    } catch (error) {
      const key = error instanceof ApiFailure ? `error.${error.code}` : "";
      setMessage({ tone: "error", text: hasKey(key) ? t(key) : error instanceof Error ? error.message : t("error.generic") });
    } finally {
      setBusy(false);
    }
  };

  return (
    <ConsoleWindow title={<>sync <span>/</span> {t("sync.manual.title").toLowerCase()}</>}>
      <div className="manual">
        <p className="muted">{t("sync.manual.text")}</p>
        <input ref={input} type="file" className="visually-hidden" accept=".lua,.json,text/plain,application/json" onChange={(e) => void choose(e)} />
        <div className="button-row">
          <button className="btn btn-ghost" disabled={busy} onClick={() => input.current?.click()}><Icon name="upload" size={16} /> {t("sync.manual.choose")}</button>
          <span className="fine-print">{t("sync.manual.where")}</span>
        </div>
        {message && <div className={`notice ${message.tone}`} role={message.tone === "error" ? "alert" : "status"}>{message.text}</div>}
        {preview && (
          <>
            <div className="scope-grid">
              {SCOPE_ORDER.map((scope) => (
                <label key={scope} className={`scope ${scopes.includes(scope) ? "on" : ""}`}>
                  <input type="checkbox" checked={scopes.includes(scope)} disabled={!preview.scopes.includes(scope) || busy}
                    onChange={(e) => setScopes((cur) => e.target.checked ? [...cur, scope] : cur.filter((s) => s !== scope))} />
                  <Icon name={SCOPE_ICON[scope]} />
                  <span><strong>{t(`scope.${scope}`)}</strong><small>{t(`scope.${scope}.help`)}</small></span>
                  <b className="mono">{num(counts[scope])}</b>
                </label>
              ))}
            </div>
            <label className="consent"><input type="checkbox" checked={consent} disabled={busy} onChange={(e) => setConsent(e.target.checked)} /> {t("sync.manual.consent")}</label>
            <div className="button-row spread">
              {user ? <span className="muted mono">{num(selected)}</span> : <span className="muted">{t("sync.manual.signIn")} {signIn && <a className="link-btn" href={signIn}>{t("nav.signIn")}</a>}</span>}
              <button className="btn btn-primary" disabled={!user || !consent || !scopes.length || !selected || busy} onClick={() => void send()}><Icon name="upload" size={16} /> {t("sync.manual.send")}</button>
            </div>
          </>
        )}
      </div>
    </ConsoleWindow>
  );
}

export function SyncView({ user, signIn }: { user: User | null; signIn: string | null }) {
  const { t } = useI18n();
  return (
    <>
      <PageHead title={t("sync.title")} lead={t("sync.lead")} />
      <div className="page-column sync-grid">
        <section className="chapter-card tint-navy">
          <Tag tone="lilac">{t("sync.app.tag")}</Tag>
          <h2 className="serif-heading small"><Icon name="laptop" size={22} /> {t("sync.app.title")}</h2>
          <p className="lead">{t("sync.app.text")}</p>
          <ol className="steps">
            {(["sync.app.step1", "sync.app.step2", "sync.app.step3", "sync.app.step4"] as const).map((key, i) => (
              <li key={key}><span className="step-node mono">{i + 1}</span><span>{t(key)}</span></li>
            ))}
          </ol>
          <div className="button-row">
            <a className="btn btn-primary" href="/downloads/EvertallySetup.exe"><Icon name="download" size={16} /> {t("sync.app.download")}</a>
            <a className="btn btn-ghost" href="/downloads/Evertally.zip"><Icon name="download" size={16} /> {t("hero.download")}</a>
          </div>
        </section>
        <ManualImport user={user} signIn={signIn} />
      </div>
    </>
  );
}

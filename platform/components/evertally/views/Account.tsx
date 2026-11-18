"use client";
import { useState } from "react";
import type { Scope } from "@/lib/contracts";
import { hasKey, useI18n } from "@/lib/i18n";
import { api, ApiFailure, useApi } from "../api";
import type { Me, User } from "../types";
import { fullName } from "../Identity";
import { CLASSES, ConsoleWindow, DiscordGlyph, Empty, Icon, Tag } from "../ui";
import { PageHead } from "./Data";
import { SCOPE_ICON, SCOPE_ORDER } from "./Sync";

function SignInCard({ signIn, authReady, text }: { signIn: string | null; authReady: boolean; text: string }) {
  const { t } = useI18n();
  return (
    <section className="chapter-card tint-plum center">
      <span className="empty-icon"><Icon name="user" size={22} /></span>
      <h2 className="serif-heading small">{t("account.signInTitle")}</h2>
      <p className="lead">{text}</p>
      {!signIn ? (authReady && <p className="notice error">{t("auth.discord_not_configured")}</p>)
        : signIn.startsWith("/auth/discord") ? <a className="btn btn-discord" href={signIn}><DiscordGlyph /> {t("nav.signIn")}</a>
        : <a className="btn btn-ghost" href={signIn}>{t("nav.devSignIn")}</a>}
    </section>
  );
}

function useErrorText() {
  const { t } = useI18n();
  return (error: unknown) => {
    const key = error instanceof ApiFailure ? `error.${error.code}` : "";
    return hasKey(key) ? t(key) : error instanceof Error ? error.message : t("error.generic");
  };
}

export function AccountView({ user, signIn, authReady, onChanged }: { user: User | null; signIn: string | null; authReady: boolean; onChanged: () => void }) {
  const { t, date } = useI18n();
  const errorText = useErrorText();
  const [version, setVersion] = useState(0);
  const [busy, setBusy] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [message, setMessage] = useState<{ tone: "error" | "success"; text: string } | null>(null);
  const me = useApi<Me>(user ? "/api/me" : null, version);

  const act = async (request: () => Promise<unknown>, success?: string) => {
    setBusy(true);
    try {
      await request();
      setVersion((v) => v + 1);
      if (success) setMessage({ tone: "success", text: success });
      onChanged();
    } catch (error) {
      setMessage({ tone: "error", text: errorText(error) });
    } finally {
      setBusy(false);
    }
  };

  if (!user) return <><PageHead title={t("account.title")} lead={t("account.lead")} /><div className="page-column"><SignInCard signIn={signIn} authReady={authReady} text={t("account.signInText")} /></div></>;
  const data = me.data;
  const grants = data?.grants.filter((g) => g.revokedAt === null) ?? [];
  return (
    <>
      <PageHead title={t("account.title")} lead={t("account.lead")}>
        {/* eslint-disable-next-line @next/next/no-img-element -- small Discord CDN avatar */}
        <div className="account-chip">{user.avatarUrl ? <img src={user.avatarUrl} alt="" width={28} height={28} /> : <span className="avatar">{user.displayName.charAt(0)}</span>}<strong>{user.displayName}</strong><span className="muted">@{user.username}</span></div>
      </PageHead>
      <div className="page-column account-grid">
        {message && <div className={`notice ${message.tone} wide`} role="status">{message.text}</div>}
        <ConsoleWindow title={<>{t("nav.account").toLowerCase()} <span>/</span> {t("account.devices").toLowerCase()}</>}>
          {data?.devices.length ? data.devices.map((d) => (
            <div className="row-item" key={d.id}>
              <Icon name="laptop" />
              <span><strong>{d.name}</strong><small>{t("account.lastSeen")}: {date(d.lastSeenAt)} · {d.scopes.map((s) => t(`scope.${s}`)).join(", ")}</small></span>
              <button className="btn btn-ghost btn-sm" disabled={busy} onClick={() => void act(() => api(`/api/devices/${encodeURIComponent(d.id)}`, { method: "DELETE" }))}>{t("account.unpair")}</button>
            </div>
          )) : <Empty icon="laptop" title={me.loading ? t("common.loading") : t("account.devicesEmpty")}>{t("sync.app.text")}</Empty>}
        </ConsoleWindow>
        <ConsoleWindow title={<>{t("nav.account").toLowerCase()} <span>/</span> {t("account.profiles").toLowerCase()}</>}>
          {data?.profiles.length ? data.profiles.map((p) => (
            <div className="row-item profile-row" key={p.id}>
              <span className="avatar">{p.name?.charAt(0) ?? "?"}</span>
              <span><strong>{fullName(p) || t("common.private")}</strong><small>{[CLASSES[p.classId ?? 0], p.level].filter(Boolean).join(" · ")}</small></span>
              {/* every character is public since 2026-11-18 (lib/publish.ts ALL_PUBLIC): nothing to switch here */}
              <a className="btn btn-sm btn-on" href={`#armory/${encodeURIComponent(p.id)}`}><Icon name="globe" size={14} /> {t("account.public")}</a>
            </div>
          )) : <Empty icon="user" title={t("account.profiles")}>{t("account.profilesEmpty")}</Empty>}
        </ConsoleWindow>
        <ConsoleWindow title={<>{t("nav.account").toLowerCase()} <span>/</span> {t("account.grants").toLowerCase()}</>}>
          {grants.length ? grants.map((g) => (
            <div className="row-item" key={g.id}>
              <Icon name="shield" />
              <span><strong className="mono">{g.producerId.slice(0, 14)}…</strong><small>{g.scopes.map((s) => t(`scope.${s}`)).join(", ")} · {date(g.createdAt)}</small></span>
              <button className="btn btn-ghost btn-sm" disabled={busy} onClick={() => void act(() => api(`/api/consents/${encodeURIComponent(g.id)}`, { method: "DELETE" }))}>{t("account.revoke")}</button>
            </div>
          )) : <Empty icon="shield" title={t("account.grantsEmpty")}>{t("chapter.privacy.lead")}</Empty>}
          <div className="danger-zone">
            {confirmDelete ? (
              <div className="confirm">
                <strong>{t("account.deleteTitle")}</strong>
                <p className="muted">{t("account.deleteText")}</p>
                <div className="button-row">
                  <button className="btn btn-ghost btn-sm" onClick={() => setConfirmDelete(false)}>{t("common.cancel")}</button>
                  <button className="btn btn-danger btn-sm" disabled={busy} onClick={() => void act(() => api("/api/me/data", { method: "DELETE" }), t("account.deleted")).then(() => setConfirmDelete(false))}><Icon name="trash" size={14} /> {t("account.deleteConfirm")}</button>
                </div>
              </div>
            ) : <button className="link-btn danger" onClick={() => setConfirmDelete(true)}><Icon name="trash" size={14} /> {t("account.delete")}</button>}
          </div>
        </ConsoleWindow>
      </div>
    </>
  );
}

export function LinkView({ user, signIn, authReady, initialCode }: { user: User | null; signIn: string | null; authReady: boolean; initialCode: string }) {
  const { t } = useI18n();
  const errorText = useErrorText();
  const [code, setCode] = useState(initialCode);
  const [checked, setChecked] = useState<string | null>(initialCode || null);
  const scopes: Scope[] = [...SCOPE_ORDER];
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<{ tone: "success" | "error" | "info"; text: string } | null>(null);
  const pairing = useApi<{ userCode: string; name: string; expiresAt: number }>(user && checked ? `/api/pairing?code=${encodeURIComponent(checked)}` : null);

  const decide = async (approve: boolean) => {
    if (!pairing.data) return;
    setBusy(true);
    try {
      await api("/api/pairing", { method: "POST", body: JSON.stringify({ userCode: pairing.data.userCode, scopes, approve }) });
      setResult(approve ? { tone: "success", text: t("link.approved") } : { tone: "info", text: t("link.denied") });
    } catch (error) {
      setResult({ tone: "error", text: errorText(error) });
    } finally {
      setBusy(false);
    }
  };

  const signInHere = signIn ? `${signIn.split("?")[0]}?return_to=${encodeURIComponent(`/link${code ? `?code=${encodeURIComponent(code)}` : ""}`)}` : null;
  return (
    <>
      <PageHead title={t("link.title")} lead={t("link.lead")} />
      <div className="page-column link-column">
        {!user ? <SignInCard signIn={signInHere} authReady={authReady} text={t("link.signIn")} /> : result ? (
          <section className={`chapter-card center ${result.tone === "success" ? "tint-pine" : "tint-plum"}`}>
            <span className="empty-icon"><Icon name={result.tone === "success" ? "check" : "info"} size={22} /></span>
            <h2 className="serif-heading small">{result.text}</h2>
          </section>
        ) : (
          <ConsoleWindow title={<>sync <span>/</span> pair</>}>
            <form className="code-form" onSubmit={(e) => { e.preventDefault(); setChecked(code.trim()); }}>
              <label className="field"><span>{t("link.code")}</span>
                <input className="code-input mono" value={code} maxLength={12} autoComplete="off" spellCheck={false} placeholder="ABCD-EFGH" onChange={(e) => setCode(e.target.value.toUpperCase())} />
              </label>
              <button className="btn btn-ghost" type="submit" disabled={code.trim().length < 8}>{t("link.check")}</button>
            </form>
            {pairing.error && <div className="notice error" role="alert">{errorText(pairing.error)}</div>}
            {pairing.data && (
              <div className="pairing">
                <div className="row-item"><Icon name="laptop" /><span><strong>{pairing.data.name}</strong><small>{t("link.device")} · <span className="mono">{pairing.data.userCode}</span></small></span><Tag tone="lilac">{t("link.code")}</Tag></div>
                <p className="notice info">{t("link.mismatch")}</p>
                {/* everything is public since 2026-11-18: the pairing no longer chooses what to share */}
                <p className="fine-print">{t("link.allPublic")}</p>
                <div className="button-row spread">
                  <button className="btn btn-ghost" disabled={busy} onClick={() => void decide(false)}>{t("link.deny")}</button>
                  <button className="btn btn-primary" disabled={busy} onClick={() => void decide(true)}><Icon name="check" size={16} /> {t("link.approve")}</button>
                </div>
              </div>
            )}
          </ConsoleWindow>
        )}
      </div>
    </>
  );
}

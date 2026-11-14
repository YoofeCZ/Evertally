"use client";
import { useState } from "react";
import { useI18n } from "@/lib/i18n";
import { api } from "./api";
import { Icon } from "./ui";

export function CommunityPackage() {
  const { t } = useI18n();
  const [busy, setBusy] = useState(false);
  const [manual, setManual] = useState("");
  const [message, setMessage] = useState<"copied" | "manual" | "error" | null>(null);
  async function getPackage(action: "copy" | "download") {
    setBusy(true); setMessage(null); setManual("");
    try {
      const data = await api<unknown>("/api/community");
      const text = JSON.stringify(data);
      if (action === "copy") {
        try { await navigator.clipboard.writeText(text); setMessage("copied"); }
        catch { setManual(text); setMessage("manual"); }
      } else {
        const url = URL.createObjectURL(new Blob([text], { type: "application/json" }));
        const link = document.createElement("a"); link.href = url; link.download = "evertally-community.json"; link.click();
        setTimeout(() => URL.revokeObjectURL(url), 1000);
      }
    } catch { setMessage("error"); }
    finally { setBusy(false); }
  }
  return <section className="community-package" aria-label={t("community.package")}>
    <div><h2>{t("community.package")}</h2><p>{t("community.help")}</p></div>
    <div className="button-row"><button className="btn btn-primary" disabled={busy} onClick={() => void getPackage("copy")}><Icon name="book" size={16} />{busy ? t("common.loading") : t("community.copy")}</button><button className="btn btn-ghost" disabled={busy} onClick={() => void getPackage("download")}><Icon name="download" size={16} />{t("community.download")}</button></div>
    {message && <p className={`notice ${message === "error" ? "error" : ""}`} role={message === "error" ? "alert" : "status"}>{t(message === "error" ? "error.service_unavailable" : message === "copied" ? "community.copied" : "community.manualCopy")}</p>}
    {manual && <textarea className="package-copy mono" readOnly rows={5} value={manual} aria-label={t("community.package")} onFocus={(event) => event.currentTarget.select()} />}
  </section>;
}

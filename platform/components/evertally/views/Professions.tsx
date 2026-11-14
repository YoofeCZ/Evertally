"use client";
import { useEffect, useState } from "react";
import { useI18n } from "@/lib/i18n";
import { useApi } from "../api";
import type { Character, User } from "../types";
import { ConsoleWindow, DiscordGlyph, Empty, Icon, Tag, duration } from "../ui";
import { PageHead } from "./Data";

type Recipe = { recipeId: number; name?: string; learned?: boolean };
type Profession = { professionId: number; name?: string; skill: number | null; maxSkill: number | null; observedAt: number; recipes: Recipe[] };
type Craft = { recipeId: number; itemId?: number; quantity?: number; professionId?: number; observedAt: number };
type Cooldown = { recipeId: number; readyAt: number; observedAt: number };
type ProfessionSource = { id: string; character: Character | null; professions: Profession[]; crafts: Craft[]; cooldowns: Cooldown[] };
export type ProfessionResponse = { generatedAt: number; totalObservations: number; sampledObservations: number; truncated: boolean; characters: ProfessionSource[] };

export function ProfessionsView({ user, signIn }: { user: User | null; signIn: string | null }) {
  const { t } = useI18n();
  if (user) return <ProfessionData key={user.id} />;
  return <><PageHead title={t("prof.title")} lead={t("prof.lead")} /><div className="page-column"><section className="chapter-card tint-plum center">
    <span className="empty-icon"><Icon name="anvil" size={22} /></span><h2 className="serif-heading small">{t("prof.signInTitle")}</h2><p className="lead">{t("prof.signInText")}</p>
    {!signIn ? <p className="notice error">{t("auth.discord_not_configured")}</p> : signIn.startsWith("/auth/discord") ? <a className="btn btn-discord" href={signIn}><DiscordGlyph />{t("nav.signIn")}</a> : <a className="btn btn-ghost" href={signIn}>{t("nav.devSignIn")}</a>}
  </section></div></>;
}

function ProfessionData() {
  const { t, num, date } = useI18n();
  const [version, setVersion] = useState(0);
  const source = useApi<ProfessionResponse>("/api/professions", version);
  const [selected, setSelected] = useState("");
  const [query, setQuery] = useState("");
  const [learnedOnly, setLearnedOnly] = useState(false);
  const [now, setNow] = useState(() => Date.now() / 1000);
  useEffect(() => { const timer = setInterval(() => setNow(Date.now() / 1000), 1000); return () => clearInterval(timer); }, []);
  const data = source.data;
  const characters = data?.characters ?? [];
  const current = characters.find((entry) => entry.id === selected) ?? characters[0];
  const needle = query.trim().toLowerCase();
  const recipeNames = new Map(current?.professions.flatMap((profession) => profession.recipes.map((recipe) => [recipe.recipeId, recipe.name] as const)) ?? []);
  const matches = (id: number, itemId?: number, name?: string) => !needle || `${id} ${itemId ?? ""} ${name ?? recipeNames.get(id) ?? ""}`.toLowerCase().includes(needle);
  const crafts = current?.crafts.filter((craft) => matches(craft.recipeId, craft.itemId)) ?? [];
  const cooldowns = current?.cooldowns.filter((cooldown) => matches(cooldown.recipeId)) ?? [];
  const knownQuantities = crafts.map((craft) => craft.quantity).filter((quantity): quantity is number => typeof quantity === "number" && Number.isFinite(quantity) && quantity >= 0);
  return <>
    <PageHead title={t("prof.title")} lead={t("prof.lead")} />
    <div className="page-column">
      <ConsoleWindow title={t("prof.title")} actions={<button className="link-btn" disabled={source.loading} onClick={() => setVersion((value) => value + 1)}>{t("prof.refresh")}</button>}>
        {source.error ? <p className="notice error" role="alert">{t("error.service_unavailable")}</p> : !data ? <Empty icon="anvil" title={t("common.loading")}>{t("prof.freshness")}</Empty> : !current ? <Empty icon="anvil" title={t("prof.emptyTitle")}>{t("prof.emptyText")}</Empty> : <>
          <div className="toolbar">
            <label className="field"><span>{t("prof.character")}</span><select value={current.id} onChange={(event) => setSelected(event.target.value)}>{characters.map((entry, index) => <option key={entry.id} value={entry.id}>{entry.character?.name ? `${entry.character.name}${entry.character.realm ? ` · ${entry.character.realm}` : ""}` : t("prof.anonymous", { number: index + 1 })}</option>)}</select></label>
            <label className="search"><Icon name="search" size={16} /><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder={t("prof.search")} aria-label={t("common.search")} /></label>
          </div>
          <p className="fine-print">{t("prof.freshness")}</p><p className="fine-print">{t("prof.sample", { sample: data.sampledObservations, total: data.totalObservations })}</p>
          {data.truncated && <p className="notice" role="status">{t("prof.truncated")}</p>}
          <label className="consent"><input type="checkbox" checked={learnedOnly} onChange={(event) => setLearnedOnly(event.target.checked)} />{t("prof.learnedOnly")}</label>
          {current.professions.map((profession) => {
            const recipes = profession.recipes.filter((recipe) => matches(recipe.recipeId, undefined, recipe.name) && (!learnedOnly || recipe.learned === true));
            return <section className="record-detail" key={profession.professionId}>
              <div className="detail-heading"><h3>{profession.name ?? `#${profession.professionId}`}</h3><Tag tone="lilac">{profession.skill ?? "—"} / {profession.maxSkill ?? "—"}</Tag></div>
              <p className="fine-print">{t("prof.skill")} · {t("prof.recorded")}: {date(profession.observedAt)}</p>
              <details><summary className="record-toggle">{t("prof.recipes")} · {num(recipes.length)}</summary>
                {recipes.length ? <div className="table-wrap"><table className="data-table nested-table"><thead><tr><th>{t("prof.recipe")}</th><th>ID</th><th>{t("prof.learning")}</th></tr></thead><tbody>{recipes.slice(0, 200).map((recipe) => <tr key={recipe.recipeId}><td>{recipe.name ?? `#${recipe.recipeId}`}</td><td className="mono">{recipe.recipeId}</td><td>{recipe.learned === true ? <Tag tone="green">{t("prof.learned")}</Tag> : recipe.learned === false ? t("prof.notLearned") : t("common.unknown")}</td></tr>)}</tbody></table></div> : <p className="muted">{t("prof.noRecipes")}</p>}
                <p className="fine-print">{t("prof.recipeCount", { count: Math.min(recipes.length, 200), total: recipes.length })}</p>
              </details>
            </section>;
          })}
          <div className="run-summary"><div><strong className="mono">{num(crafts.length)}</strong><span>{t("prof.crafts")}</span></div><div><strong className="mono">{knownQuantities.length ? num(knownQuantities.reduce((sum, quantity) => sum + quantity, 0)) : "—"}</strong><span>{t("prof.units")}</span></div></div>
          <p className="fine-print">{t("prof.craftNote")}</p>
          <section className="record-detail"><h3>{t("prof.recentCrafts")}</h3>{crafts.length ? <div className="table-wrap"><table className="data-table nested-table"><thead><tr><th>{t("prof.recipe")}</th><th>{t("prof.output")}</th><th className="num">{t("detail.quantity")}</th><th>{t("prof.recorded")}</th></tr></thead><tbody>{crafts.slice(0, 100).map((craft, index) => <tr key={`${craft.recipeId}:${craft.observedAt}:${index}`}><td>{recipeNames.get(craft.recipeId) ?? `#${craft.recipeId}`}</td><td className="mono">{craft.itemId ?? "—"}</td><td className="num mono">{craft.quantity ?? "—"}</td><td>{date(craft.observedAt)}</td></tr>)}</tbody></table></div> : <p className="muted">{t("prof.noCrafts")}</p>}</section>
          <section className="record-detail"><h3>{t("prof.cooldowns")}</h3><p className="detail-note">{t("prof.cooldownNote")}</p>{cooldowns.length ? <div className="table-wrap"><table className="data-table nested-table"><thead><tr><th>{t("prof.recipe")}</th><th>{t("prof.remaining")}</th><th>{t("prof.readyAt")}</th><th>{t("prof.recorded")}</th></tr></thead><tbody>{cooldowns.map((cooldown) => {
            const valid = Number.isFinite(cooldown.readyAt) && cooldown.readyAt >= 0 && cooldown.readyAt <= 8640000000000;
            const remaining = valid ? Math.max(0, Math.ceil(cooldown.readyAt - now)) : null;
            return <tr key={cooldown.recipeId}><td>{recipeNames.get(cooldown.recipeId) ?? `#${cooldown.recipeId}`}</td><td className="mono">{remaining === null ? "—" : remaining > 0 ? duration(remaining * 1000) : <Tag tone="green">{t("prof.ready")}</Tag>}</td><td>{valid ? date(cooldown.readyAt) : "—"}</td><td>{date(cooldown.observedAt)}</td></tr>;
          })}</tbody></table></div> : <p className="muted">{t("prof.noCooldowns")}</p>}</section>
        </>}
      </ConsoleWindow>
    </div>
  </>;
}

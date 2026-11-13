"use client";
import { useState } from "react";
import { useI18n, type Lang } from "@/lib/i18n";
import type { ArmoryOverview, OwnArmory, ViewedArmory } from "@/lib/armory";
import { useApi } from "../api";
import { CLASSES, RACES } from "../data";
import { itemIconUrl, qualityClass, hrefItem, useIndex } from "../db/store";
import { CharacterIcons, fullName } from "../Identity";
import type { User } from "../types";
import { ConsoleWindow, DiscordGlyph, Empty, Icon, Tag } from "../ui";
import { PageHead } from "./Data";

type Entry = OwnArmory | ViewedArmory;
type Tab = "gear" | "stats" | "talents" | "professions" | "bags";
const TABS: Tab[] = ["gear", "stats", "talents", "professions", "bags"];
const SLOTS: Record<Lang, Record<number, string>> = {
  en: { 1: "Head", 2: "Neck", 3: "Shoulder", 4: "Shirt", 5: "Chest", 6: "Waist", 7: "Legs", 8: "Feet", 9: "Wrist", 10: "Hands", 11: "Finger", 12: "Finger", 13: "Trinket", 14: "Trinket", 15: "Back", 16: "Main hand", 17: "Off hand", 18: "Ranged", 19: "Tabard" },
  cs: { 1: "Hlava", 2: "Krk", 3: "Ramena", 4: "Košile", 5: "Hruď", 6: "Opasek", 7: "Nohy", 8: "Boty", 9: "Zápěstí", 10: "Ruce", 11: "Prsten", 12: "Prsten", 13: "Talisman", 14: "Talisman", 15: "Záda", 16: "Hlavní ruka", 17: "Vedlejší ruka", 18: "Střelná zbraň", 19: "Tabard" },
};
const SLOT_ORDER = [1, 2, 3, 15, 5, 4, 19, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18];
const STATS: Record<Lang, Record<string, string>> = {
  en: { str: "Strength", agi: "Agility", sta: "Stamina", int: "Intellect", spi: "Spirit", armor: "Armor", ap: "Attack power", rap: "Ranged attack power", crit: "Melee crit %", scrit: "Spell crit %", dodge: "Dodge %", parry: "Parry %", block: "Block %", hp: "Health", mana: "Mana", holy: "Holy resistance", fire: "Fire resistance", nature: "Nature resistance", frost: "Frost resistance", shadow: "Shadow resistance", arcane: "Arcane resistance" },
  cs: { str: "Síla", agi: "Obratnost", sta: "Odolnost", int: "Inteligence", spi: "Duch", armor: "Brnění", ap: "Útočná síla", rap: "Útočná síla na dálku", crit: "Kritický zásah %", scrit: "Kritické kouzlo %", dodge: "Úhyb %", parry: "Odražení %", block: "Blok %", hp: "Zdraví", mana: "Mana", holy: "Odolnost Svatá", fire: "Odolnost Oheň", nature: "Odolnost Příroda", frost: "Odolnost Mráz", shadow: "Odolnost Stín", arcane: "Odolnost Tajná" },
};

export function ArmoryView({ user, signIn, route }: { user: User | null; signIn: string | null; route: string }) {
  const { t } = useI18n();
  if (user) return <ArmoryData key={user.id} route={route} />;
  return <><PageHead title={t("armory.title")} lead={t("armory.lead")} /><div className="page-column"><section className="chapter-card tint-plum center">
    <span className="empty-icon"><Icon name="user" size={22} /></span><h2 className="serif-heading small">{t("armory.signInTitle")}</h2><p className="lead">{t("armory.signInText")}</p>
    {!signIn ? <p className="notice error">{t("auth.discord_not_configured")}</p> : signIn.startsWith("/auth/discord") ? <a className="btn btn-discord" href={signIn}><DiscordGlyph />{t("nav.signIn")}</a> : <a className="btn btn-ghost" href={signIn}>{t("nav.devSignIn")}</a>}
  </section></div></>;
}

function ArmoryData({ route }: { route: string }) {
  const { t, lang, date } = useI18n();
  const [version, setVersion] = useState(0);
  const [tab, setTab] = useState<Tab>("gear");
  const source = useApi<ArmoryOverview>("/api/armory", version);
  const entries: Entry[] = [...(source.data?.own ?? []), ...(source.data?.viewed ?? [])];
  const wanted = decodeURIComponent(route.split("?")[0]);
  const [picked, setPicked] = useState("");
  const found = entries.find(e => e.id === (picked || wanted));
  // a link to a character that is neither yours nor allowed by its player shows nothing of it, not somebody else's armory
  const blocked = !found && Boolean(wanted) && !picked && entries.length > 0;
  const current = found ?? (blocked ? undefined : entries[0]);
  return <>
    <PageHead title={t("armory.title")} lead={t("armory.lead")} />
    <div className="page-column armory-page">
      <ConsoleWindow title={t("armory.title")} actions={<button className="link-btn" disabled={source.loading} onClick={() => setVersion(v => v + 1)}>{t("prof.refresh")}</button>}>
        {source.error ? <p className="notice error" role="alert">{t("error.service_unavailable")}</p>
          : !source.data ? <Empty icon="user" title={t("common.loading")}>{t("armory.consent")}</Empty>
          : blocked ? <Empty icon="user" title={t("armory.notAllowedTitle")} action={<button className="btn btn-ghost btn-sm" onClick={() => setPicked(entries[0].id)}>{t("armory.mine")}</button>}>{t("armory.notAllowedText")}</Empty>
          : !current ? <Empty icon="user" title={t("armory.emptyTitle")}>{t("armory.emptyText")}</Empty> : <>
          <div className="armory-head">
            <div className="armory-avatar"><CharacterIcons character={current.character} size={48} /></div>
            <div><span className="hall-eyebrow">{t("armory.title")}</span><h2 className="serif-heading small">{fullName(current.character)}</h2>
              <small>{[CLASSES[current.character.classId ?? 0], RACES[current.character.raceId ?? 0], current.character.level ? `${t("armory.level")} ${current.character.level}` : ""].filter(Boolean).join(" · ")}</small></div>
            {current.kind === "viewed" ? <Tag tone="peach">{t(current.mode === "always" ? "armory.always" : "armory.once")}</Tag> : <Tag tone="green">{t("armory.mine")}</Tag>}
          </div>
          <p className="fine-print armory-observed">{current.kind === "viewed"
            ? t("armory.viewedNote", { name: current.character.name ?? "", date: date(current.observedAt), days: source.data.viewDays })
            : t("armory.ownNote", { date: date(current.observedAt) })}</p>
          <div className="toolbar armory-controls">
            <label className="field"><span>{t("armory.pick")}</span>
              <select value={current.id} onChange={event => setPicked(event.target.value)}>
                {source.data.own.length > 0 && <optgroup label={t("armory.mine")}>{source.data.own.map(e => <option key={e.id} value={e.id}>{fullName(e.character) || t("common.private")}</option>)}</optgroup>}
                {source.data.viewed.length > 0 && <optgroup label={t("armory.viewed")}>{source.data.viewed.map(e => <option key={e.id} value={e.id}>{fullName(e.character)}</option>)}</optgroup>}
              </select></label>
            <div className="segmented" role="tablist">{TABS.map(name => <button key={name} role="tab" aria-selected={tab === name} className={tab === name ? "on" : ""} onClick={() => setTab(name)}>{t(`armory.${name}`)}</button>)}</div>
          </div>
          {tab === "gear" && <Gear entry={current} lang={lang} />}
          {tab === "stats" && <Stats entry={current} lang={lang} />}
          {tab === "talents" && <Talents entry={current} />}
          {tab === "professions" && <Professions entry={current} />}
          {tab === "bags" && <Bags entry={current} />}
        </>}
      </ConsoleWindow>
      <p className="fine-print">{t("armory.consent")}</p>
    </div>
  </>;
}

function useItems() {
  const { data } = useIndex();
  return (id: number) => {
    const row = data?.items.get(id);
    return { name: row?.[1] ?? `#${id}`, quality: row?.[2] ?? 1, icon: itemIconUrl(id, row?.[9]) };
  };
}

function Item({ id, count, label, item }: { id: number; count?: number; label?: string; item: ReturnType<typeof useItems> }) {
  const info = item(id);
  return <a className="armory-item" href={hrefItem(id)}>
    {/* eslint-disable-next-line @next/next/no-img-element -- small bundled item art; a missing file just leaves the frame empty */}
    <img src={info.icon} alt="" width={32} height={32} loading="lazy" onError={event => { event.currentTarget.style.visibility = "hidden"; }} />
    <span><span className={qualityClass(info.quality)}>{info.name}</span>{label && <small>{label}</small>}</span>
    {count !== undefined && count > 1 && <b className="mono">×{count}</b>}
  </a>;
}

function Gear({ entry, lang }: { entry: Entry; lang: Lang }) {
  const { t } = useI18n();
  const item = useItems();
  const bySlot = new Map(entry.armory.equipped.map(e => [e.slot, e.itemId]));
  if (!bySlot.size) return <p className="fine-print">{t("armory.noGear")}</p>;
  return <div className="armory-grid armory-gear">{SLOT_ORDER.map(slot => {
    const id = bySlot.get(slot);
    return id ? <Item key={slot} id={id} label={SLOTS[lang][slot]} item={item} />
      : <div className="armory-item armory-slot-unrecorded" key={slot} title={lang === "cs" ? "Předmět pro tento slot není v záznamu" : "No item recorded for this slot"}>
          <span className="armory-slot-icon" aria-hidden="true">—</span><span><small>{SLOTS[lang][slot]}</small><span>—</span></span>
        </div>;
  })}</div>;
}

function Stats({ entry, lang }: { entry: Entry; lang: Lang }) {
  const { t, num } = useI18n();
  const rows = Object.keys(STATS.en).filter(key => entry.armory.stats[key] !== undefined);
  if (!rows.length) return <p className="fine-print">{t("armory.noStats")}</p>;
  return <table className="data-table"><tbody>{rows.map(key => <tr key={key}><td>{STATS[lang][key]}</td><td className="mono">{num(entry.armory.stats[key])}</td></tr>)}</tbody></table>;
}

function Talents({ entry }: { entry: Entry }) {
  const { t } = useI18n();
  if (!entry.armory.talents.length) return <p className="fine-print">{t("armory.noTalents")}</p>;
  return <div className="armory-trees">{entry.armory.talents.map((tree, index) => <section key={`${tree.name}${index}`} className="record-detail">
    <div className="detail-heading"><h3>{tree.name || `#${index + 1}`}</h3><Tag tone="lilac">{t("armory.points", { count: tree.spent })}</Tag></div>
    <ul className="armory-talents">{tree.ranks.map(([id, rank, name]) => <li key={id}><span>{name || `#${id}`}</span><b className="mono">{rank}</b></li>)}</ul>
  </section>)}</div>;
}

function Professions({ entry }: { entry: Entry }) {
  const { t } = useI18n();
  if (!entry.armory.professions.length) return <p className="fine-print">{t("armory.noProf")}</p>;
  return <div className="armory-grid">{entry.armory.professions.map(p => <div key={p.id} className="armory-item">
    <span><span>{p.name || `#${p.id}`}</span>{p.max ? <progress value={p.skill ?? 0} max={p.max} aria-label={p.name} /> : null}</span>
    <b className="mono">{p.skill ?? "?"}/{p.max ?? "?"}</b>
  </div>)}</div>;
}

function Bags({ entry }: { entry: Entry }) {
  const { t } = useI18n();
  const item = useItems();
  if (!entry.armory.bags.length) return <p className="fine-print">{entry.kind === "viewed" ? t("armory.noBagsViewed") : t("armory.noBags")}</p>;
  return <div className="armory-grid">{entry.armory.bags.map(b => <Item key={b.itemId} id={b.itemId} count={b.count} item={item} />)}</div>;
}

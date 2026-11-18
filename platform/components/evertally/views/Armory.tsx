"use client";
import { useState } from "react";
import { useI18n, type Lang } from "@/lib/i18n";
import type { ArmoryOverview, OwnArmory, ViewedArmory } from "@/lib/armory";
import { useApi } from "../api";
import { CLASSES, RACES } from "../data";
import { itemIconUrl, qualityClass, hrefItem, useIndex } from "../db/store";
import { CharacterIcons, fullName } from "../Identity";
import type { User } from "../types";
import { ConsoleWindow, Empty, Tag } from "../ui";
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

// Since 2026-11-18 every character is public (lib/publish.ts ALL_PUBLIC): the armory opens on the list of all characters
// and a click opens one of them, signed in or not. Gear, stats, talents and professions are public; the bags only for your
// own characters and for those whose player allowed you in the game (/api/armory).
type PublicEntry = { kind: "public"; id: string; character: OwnArmory["character"]; observedAt: number; armory: OwnArmory["armory"] };
type Shown = Entry | PublicEntry;

export function ArmoryView({ user, route }: { user: User | null; signIn: string | null; authReady: boolean; route: string }) {
  const { t } = useI18n();
  const wanted = decodeURIComponent(route.split("?")[0] ?? "");
  return <>
    <PageHead title={t("armory.title")} lead={t("armory.leadPublic")} />
    <div className="page-column armory-page">
      {wanted ? <ArmoryCharacter key={wanted} id={wanted} user={user} /> : <ArmoryList user={user} />}
      <p className="fine-print">{t("armory.publicNote")}</p>
    </div>
  </>;
}

function ArmoryList({ user }: { user: User | null }) {
  const { t, date } = useI18n();
  const [query, setQuery] = useState("");
  const list = useApi<{ characters: PublicEntry[] }>(`/api/armory-public${query.trim() ? `?q=${encodeURIComponent(query.trim())}` : ""}`);
  const mine = useApi<ArmoryOverview>(user ? "/api/armory" : null);
  const own = mine.data?.own ?? [], viewed = mine.data?.viewed ?? [];
  const row = (e: { id: string; character: OwnArmory["character"]; observedAt: number }, tag?: string) => (
    <a key={e.id} className="armory-row" href={`#armory/${encodeURIComponent(e.id)}`}>
      <CharacterIcons character={e.character} size={32} />
      <span className="armory-row-name"><b>{fullName(e.character)}</b><small>{[CLASSES[e.character.classId ?? 0], RACES[e.character.raceId ?? 0]].filter(Boolean).join(" · ")}</small></span>
      {tag && <Tag tone="green">{tag}</Tag>}
      <span className="mono armory-row-level">{e.character.level ? `${t("armory.level")} ${e.character.level}` : ""}</span>
      <small className="armory-row-date">{date(e.observedAt)}</small>
    </a>
  );
  return <ConsoleWindow title={t("armory.title")}>
    <label className="field armory-search"><span>{t("armory.search")}</span>
      <input type="search" value={query} onChange={event => setQuery(event.target.value)} placeholder={t("armory.searchHint")} /></label>
    {(own.length > 0 || viewed.length > 0) && !query && <section className="armory-list">
      <h3 className="hall-eyebrow">{t("armory.yours")}</h3>
      {own.map(e => row(e, t("armory.mine")))}
      {viewed.map(e => row(e, t(e.mode === "always" ? "armory.always" : "armory.once")))}
    </section>}
    <section className="armory-list">
      <h3 className="hall-eyebrow">{t("armory.all")}</h3>
      {list.error ? <p className="notice error" role="alert">{t("error.service_unavailable")}</p>
        : !list.data ? <p className="fine-print">{t("common.loading")}</p>
        : list.data.characters.length === 0 ? <Empty icon="user" title={t("armory.emptyTitle")}>{t("armory.emptyPublic")}</Empty>
        : list.data.characters.map(e => row(e))}
    </section>
  </ConsoleWindow>;
}

function ArmoryCharacter({ id, user }: { id: string; user: User | null }) {
  const { t, lang, date } = useI18n();
  const [tab, setTab] = useState<Tab>("gear");
  const isPrivateView = id.startsWith("v:");
  const open = useApi<PublicEntry>(isPrivateView ? null : `/api/armory-character/${encodeURIComponent(id)}`);
  const mine = useApi<ArmoryOverview>(user ? "/api/armory" : null);
  // your own character, or one whose player allowed you: with its bags
  const allowed: Entry | undefined = [...(mine.data?.own ?? []), ...(mine.data?.viewed ?? [])].find(e => e.id === id)
    ?? (open.data ? (mine.data?.viewed ?? []).find(e => fullName(e.character).toLowerCase() === fullName(open.data!.character).toLowerCase()) : undefined);
  const current: Shown | undefined = allowed ?? open.data ?? undefined;
  const back = <a className="btn btn-ghost btn-sm" href="#armory">← {t("armory.back")}</a>;
  return <ConsoleWindow title={t("armory.title")} actions={back}>
    {!current ? (open.error ? <Empty icon="user" title={t("armory.notFoundTitle")} action={back}>{t("armory.notFoundText")}</Empty>
      : <p className="fine-print">{t("common.loading")}</p>) : <>
      <div className="armory-head">
        <div className="armory-avatar"><CharacterIcons character={current.character} size={48} /></div>
        <div><span className="hall-eyebrow">{t("armory.title")}</span><h2 className="serif-heading small">{fullName(current.character)}</h2>
          <small>{[CLASSES[current.character.classId ?? 0], RACES[current.character.raceId ?? 0], current.character.level ? `${t("armory.level")} ${current.character.level}` : ""].filter(Boolean).join(" · ")}</small></div>
        {current.kind === "viewed" ? <Tag tone="peach">{t(current.mode === "always" ? "armory.always" : "armory.once")}</Tag> : current.kind === "own" ? <Tag tone="green">{t("armory.mine")}</Tag> : null}
      </div>
      <p className="fine-print armory-observed">{t(current.kind === "own" ? "armory.ownNote" : "armory.asOf", { date: date(current.observedAt) })}</p>
      <div className="toolbar armory-controls">
        <div className="segmented" role="tablist">{TABS.map(name => <button key={name} role="tab" aria-selected={tab === name} className={tab === name ? "on" : ""} onClick={() => setTab(name)}>{t(`armory.${name}`)}</button>)}</div>
      </div>
      {tab === "gear" && <Gear entry={current} lang={lang} />}
      {tab === "stats" && <Stats entry={current} lang={lang} />}
      {tab === "talents" && <Talents entry={current} />}
      {tab === "professions" && <Professions entry={current} />}
      {tab === "bags" && (current.kind === "public" ? <p className="fine-print">{t("armory.bagsPermission")}</p> : <Bags entry={current} />)}
    </>}
  </ConsoleWindow>;
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

export function Gear({ entry, lang }: { entry: { armory: Pick<Entry["armory"], "equipped"> }; lang: Lang }) {
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

export function Stats({ entry, lang }: { entry: { armory: Pick<Entry["armory"], "stats"> }; lang: Lang }) {
  const { t, num } = useI18n();
  const rows = Object.keys(STATS.en).filter(key => entry.armory.stats[key] !== undefined);
  if (!rows.length) return <p className="fine-print">{t("armory.noStats")}</p>;
  return <table className="data-table"><tbody>{rows.map(key => <tr key={key}><td>{STATS[lang][key]}</td><td className="mono">{num(entry.armory.stats[key])}</td></tr>)}</tbody></table>;
}

export function Talents({ entry }: { entry: { armory: Pick<Entry["armory"], "talents"> } }) {
  const { t } = useI18n();
  if (!entry.armory.talents.length) return <p className="fine-print">{t("armory.noTalents")}</p>;
  return <div className="armory-trees">{entry.armory.talents.map((tree, index) => <section key={`${tree.name}${index}`} className="record-detail">
    <div className="detail-heading"><h3>{tree.name || `#${index + 1}`}</h3><Tag tone="lilac">{t("armory.points", { count: tree.spent })}</Tag></div>
    <ul className="armory-talents">{tree.ranks.map(([id, rank, name]) => <li key={id}><span>{name || `#${id}`}</span><b className="mono">{rank}</b></li>)}</ul>
  </section>)}</div>;
}

function Professions({ entry }: { entry: Shown }) {
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

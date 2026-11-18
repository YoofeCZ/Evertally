"use client";
/* eslint-disable @next/next/no-img-element -- bundled class icons and the game's own floor maps */
// The window of one dungeon or raid visit, opened like the window of a fight: the bosses of the place and how each went, the
// ordinary enemies apart from them, the group, the loot, what happened in order, and the map of the place.
import { useEffect, useMemo, useRef, useState } from "react";
import { clock, moneyText, whenOf, type Chronicle, type Fight, type Instance } from "@/lib/chronicle";
import { instanceReport } from "@/lib/chronicle-instance";
import { CLASS_COLORS, CLASSES } from "../data";
import { IconChip, ItemIcon, NpcIcon, TypeIcon, classIconUrl } from "./ChronicleArt";
import { num } from "./ChronicleFight";

const T = {
  en: {
    close: "Close", prev: "Previous visit", next: "Next visit", dungeon: "Dungeon", raid: "Raid", inside: "Still inside", left: "Left",
    tabs: { overview: "Overview", bosses: "Bosses", enemies: "Enemies", loot: "Loot", story: "What happened", map: "Map" } as Record<string, string>,
    duration: "Time inside", bosses: "Bosses", kills: "Enemies killed", deaths: "Deaths", items: "Items", money: "Money", xp: "Experience",
    group: "Group", you: "you", role: { tank: "Tank", healer: "Healer", dps: "Damage" } as Record<string, string>, level: "level",
    killed: "Defeated", wiped: "Wiped", unseen: "Not met", attempts: "attempts", wipes: "wipes", openFight: "Open the fight", extra: "Not in the dungeon journal",
    rare: "rare", enemiesNote: "Everything killed here that is not one of the bosses.", trash: "Fights with the other enemies", fightKills: "killed",
    noEnemies: "No other kills were recorded here.", noLoot: "No loot was recorded here.", noStory: "Nothing else was recorded here.",
    mapNote: "The game does not give the character's position inside a dungeon, so the route stops at the entrance. The map is the game's own.",
    floor: "Floor", jump: "Jump there", damage: "Damage", healing: "Healing", taken: "Taken", seen: "seen", times: "×",
    story: { boss: "Boss", combat: "Fight", death: "Died", loot: "Loot", level: "Level", quest: "Quest", kill: "Defeated", dungeon: "Entrance" } as Record<string, string>,
    unknownPlace: "This place is not in the dungeon journal yet, so its bosses are not known.",
    fight: "Fight", bossFights: "Boss fights", npcFights: "Fights with other enemies", count: "fights", inCombat: "in combat", perSecond: "/s",
    attempt: "Attempt", result: { kill: "Defeated", wipe: "Wiped", win: "Victory", loss: "Defeat", ended: "Ended", interrupted: "Interrupted" } as Record<string, string>,
    openWhole: "Open the whole fight", noMeasure: "This fight's numbers were not recorded.", noFight: "Only the kill was recorded, not the fight.", groupDamage: "Group damage",
  },
  cs: {
    close: "Zavřít", prev: "Předchozí návštěva", next: "Další návštěva", dungeon: "Dungeon", raid: "Raid", inside: "Pořád uvnitř", left: "Odchod",
    tabs: { overview: "Přehled", bosses: "Bossové", enemies: "Nepřátelé", loot: "Loot", story: "Průběh", map: "Mapa" } as Record<string, string>,
    duration: "Čas uvnitř", bosses: "Bossové", kills: "Zabitých nepřátel", deaths: "Smrti", items: "Předmětů", money: "Peníze", xp: "Zkušenosti",
    group: "Parta", you: "ty", role: { tank: "Tank", healer: "Léčitel", dps: "Poškození" } as Record<string, string>, level: "úroveň",
    killed: "Poražen", wiped: "Neúspěch", unseen: "Nepotkán", attempts: "pokusů", wipes: "neúspěchů", openFight: "Otevřít souboj", extra: "Není v deníku dungeonu",
    rare: "vzácný", enemiesNote: "Všechno, co tu padlo, kromě bossů.", trash: "Souboje s ostatními nepřáteli", fightKills: "zabito",
    noEnemies: "Jiná zabití se tu nezaznamenala.", noLoot: "Žádný loot se tu nezaznamenal.", noStory: "Nic dalšího se tu nezaznamenalo.",
    mapNote: "Hra uvnitř dungeonu polohu postavy nedává, proto trasa končí u vchodu. Mapa je přímo ze hry.",
    floor: "Patro", jump: "Přejít tam", damage: "Poškození", healing: "Léčení", taken: "Utrženo", seen: "viděno", times: "×",
    story: { boss: "Boss", combat: "Souboj", death: "Smrt", loot: "Loot", level: "Úroveň", quest: "Quest", kill: "Poražen", dungeon: "Vstup" } as Record<string, string>,
    unknownPlace: "Tohle místo zatím v deníku dungeonů není, takže jeho bossové nejsou známí.",
    fight: "Souboj", bossFights: "Souboje s bossy", npcFights: "Souboje s ostatními nepřáteli", count: "soubojů", inCombat: "v boji", perSecond: "/s",
    attempt: "Pokus", result: { kill: "Poražen", wipe: "Neúspěch", win: "Vítězství", loss: "Porážka", ended: "Ukončen", interrupted: "Přerušen" } as Record<string, string>,
    openWhole: "Otevřít celý souboj", noMeasure: "Čísla tohoto souboje se nezaznamenala.", noFight: "Zaznamenalo se jen zabití, ne souboj.", groupDamage: "Poškození party",
  },
};
const QUALITY = ["#9d9d9d", "#ffffff", "#1eff00", "#0070dd", "#a335ee", "#ff8000"];
type Words = typeof T.en;
const sum = (list: readonly Fight[], key: "dmg" | "heal" | "taken") => list.some(f => f.me[key] !== undefined) ? list.reduce((a, f) => a + (f.me[key] ?? 0), 0) : undefined;

/** The numbers of a set of fights together: how many, how long in combat, what the character did and took. */
function FightTotals({ list, w }: { list: readonly Fight[]; w: Words }) {
  const time = list.reduce((a, f) => a + f.d, 0);
  const dmg = sum(list, "dmg"), heal = sum(list, "heal"), taken = sum(list, "taken");
  return (
    <div className="chr-tiles is-small">
      <div className="chr-tile"><b>{list.length}</b><span>{w.count}</span></div>
      <div className="chr-tile"><b>{clock(time)}</b><span>{w.inCombat}</span></div>
      <div className="chr-tile" style={{ ["--tone" as string]: "#ff9a3c" }}><b>{num(dmg)}</b><span>{w.damage}</span>{dmg !== undefined && time > 0 && <small>{num(dmg / time)}{w.perSecond}</small>}</div>
      <div className="chr-tile" style={{ ["--tone" as string]: "#5fd08f" }}><b>{num(heal)}</b><span>{w.healing}</span></div>
      <div className="chr-tile" style={{ ["--tone" as string]: "#e2786a" }}><b>{num(taken)}</b><span>{w.taken}</span></div>
    </div>
  );
}

/** One fight inside the window: its result and length, the character's numbers, the group's damage and the way to the whole fight. */
function FightCard({ fight, index, label, from, w, onOpen }: { fight: Fight; index: number; label: string; from: number; w: Words; onOpen: (i: number) => void }) {
  const won = fight.result === "kill" || fight.result === "win", lost = fight.result === "wipe" || fight.result === "loss";
  const group = [...(fight.group ?? [])].filter(m => m.dmg !== undefined).sort((a, b) => (b.dmg ?? 0) - (a.dmg ?? 0));
  const top = group[0]?.dmg || 1;
  const measured = [fight.me.dmg, fight.me.heal, fight.me.taken].some(v => v !== undefined);
  return (
    <div className={`chr-inst-fight-card${won ? " is-win" : lost ? " is-loss" : ""}`}>
      <div className="chr-inst-fight-head">
        <b>{label}</b>
        <span>{clock(fight.t - from)} · {clock(fight.d)} · {w.result[fight.result] ?? fight.result}</span>
        <button type="button" className="chr-btn" onClick={() => onOpen(index)}>{w.openWhole}</button>
      </div>
      {measured ? <div className="chr-tiles is-small">
        <div className="chr-tile" style={{ ["--tone" as string]: "#ff9a3c" }}><b>{num(fight.me.dmg)}</b><span>{w.damage}</span>{fight.me.dmg !== undefined && fight.d > 0 && <small>{num(fight.me.dmg / fight.d)}{w.perSecond}</small>}</div>
        <div className="chr-tile" style={{ ["--tone" as string]: "#5fd08f" }}><b>{num(fight.me.heal)}</b><span>{w.healing}</span></div>
        <div className="chr-tile" style={{ ["--tone" as string]: "#e2786a" }}><b>{num(fight.me.taken)}</b><span>{w.taken}</span></div>
        {fight.me.deaths ? <div className="chr-tile"><b>{fight.me.deaths}</b><span>{w.deaths}</span></div> : null}
      </div> : <p className="chr-muted">{w.noMeasure}</p>}
      {group.length > 1 && <ol className="chr-inst-meter" aria-label={w.groupDamage}>{group.map(m => (
        <li key={m.name} className={m.me ? "is-me" : ""} style={{ ["--c" as string]: CLASS_COLORS[m.classId] ?? "#69ccf0" }}>
          <i style={{ width: `${((m.dmg ?? 0) / top) * 100}%` }} /><b>{m.name.split("-")[0]}</b><strong>{num(m.dmg)}</strong>
        </li>
      ))}</ol>}
    </div>
  );
}

export function InstanceWindow({ c, inst, index, count, lang, onClose, onStep, onOpenFight, onSeek }: {
  c: Chronicle; inst: Instance; index: number; count: number; lang: string; onClose: () => void; onStep: (delta: number) => void; onOpenFight: (index: number) => void; onSeek: (t: number) => void;
}) {
  const w = T[lang === "cs" ? "cs" : "en"];
  const r = useMemo(() => instanceReport(c, inst), [c, inst]);
  type Tab = "overview" | "bosses" | "enemies" | "loot" | "story" | "map";
  const tabs: Tab[] = ["overview", ...(r.bosses.length ? ["bosses" as Tab] : []), "enemies", "loot", "story", ...(r.info?.floors?.length ? ["map" as Tab] : [])];
  const [chosen, setTab] = useState<Tab>("overview");
  const tab = tabs.includes(chosen) ? chosen : "overview";
  const [floor, setFloor] = useState(0);
  const dialog = useRef<HTMLElement>(null);
  useEffect(() => { dialog.current?.focus({ preventScroll: true }); }, []);
  const raid = inst.detail === "Raid" || r.info?.type === "raid";
  const when = new Date(whenOf(c, r.from) * 1000).toLocaleString(lang === "cs" ? "cs-CZ" : "en-GB", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });
  const sub = [raid ? w.raid : w.dungeon, r.info?.lvl ? `${r.info.lvl[0]}–${r.info.lvl[1]}` : null, r.info?.players ? `${r.info.players}` : null].filter(Boolean).join(" · ");
  const known = r.bosses.filter(b => !b.extra).length;
  const jump = (t: number) => { onSeek(t); onClose(); };
  const bossFights = r.bosses.flatMap(b => b.fights).map(i => c.fights?.[i]).filter((f): f is Fight => !!f);
  const npcFights = r.trash.map(x => x.fight);
  const fightButton = (i: number | undefined) => i === undefined ? null : <button type="button" className="chr-open" onClick={() => onOpenFight(i)} title={w.openFight} aria-label={w.openFight}>›</button>;
  return (
    <div className="chr-scrim" onClick={onClose}>
      <section ref={dialog} className="chr-card chr-fight chr-inst" role="dialog" aria-modal="true" tabIndex={-1} aria-label={inst.name} onClick={event => event.stopPropagation()} onKeyDown={event => { if (event.key !== "Escape") event.stopPropagation(); }}>
        <header>
          <IconChip k={raid ? "travel.raid" : "travel.instance"} size={48} />
          <div className="chr-fight-title">
            <h2>{inst.name}</h2>
            <p>{sub} · {clock(r.to - r.from)} · {when}</p>
          </div>
          <span className={`chr-result ${r.open ? "is-neutral" : known && r.bossKills >= known ? "is-win" : "is-neutral"}`}>{r.open ? w.inside : known ? `${r.bossKills}/${known} ${w.bosses.toLowerCase()}` : w.left}</span>
          <div className="chr-fight-nav">
            <button type="button" onClick={() => onStep(-1)} disabled={index <= 0} aria-label={w.prev}>‹</button>
            <button type="button" onClick={() => onStep(1)} disabled={index >= count - 1} aria-label={w.next}>›</button>
            <button type="button" onClick={onClose} aria-label={w.close}>×</button>
          </div>
        </header>
        <nav className="chr-tabs" role="tablist">{tabs.map(id => <button key={id} type="button" role="tab" aria-selected={tab === id} className={tab === id ? "is-on" : ""} onClick={() => setTab(id)}>{w.tabs[id]}</button>)}</nav>

        <div className="chr-fight-body">
          {tab === "overview" && <>
            <div className="chr-tiles">
              <div className="chr-tile"><b>{clock(r.to - r.from)}</b><span>{w.duration}</span></div>
              {known > 0 && <div className="chr-tile" style={{ ["--tone" as string]: "#a78bfa" }}><b>{r.bossKills}/{known}</b><span>{w.bosses}</span></div>}
              <div className="chr-tile"><b>{num(r.kills - r.bossKills)}</b><span>{w.kills}</span></div>
              <div className="chr-tile" style={{ ["--tone" as string]: "#e2786a" }}><b>{r.deaths.length}</b><span>{w.deaths}</span></div>
              <div className="chr-tile"><b>{num(r.loot.reduce((a, x) => a + x.n, 0))}</b><span>{w.items}</span></div>
              <div className="chr-tile" style={{ ["--tone" as string]: "#f2c04b" }}><b>{moneyText(r.copper)}</b><span>{w.money}</span></div>
              {r.xp > 0 && <div className="chr-tile" style={{ ["--tone" as string]: "#7fb2ff" }}><b>{num(r.xp)}</b><span>{w.xp}</span></div>}
            </div>
            {bossFights.length > 0 && <><h3 className="chr-inst-h">{w.bossFights}</h3><FightTotals list={bossFights} w={w} /></>}
            {npcFights.length > 0 && <><h3 className="chr-inst-h">{w.npcFights}</h3><FightTotals list={npcFights} w={w} /></>}
            <h3 className="chr-inst-h">{w.group}</h3>
            <ol className="chr-meters chr-party">{r.party.map(p => (
              <li key={p.name} className={p.me ? "is-me" : ""}>
                {p.classId !== undefined ? <img src={classIconUrl(p.classId)} alt="" width={28} height={28} /> : <i />}
                <span className="chr-bar-row" style={{ ["--c" as string]: CLASS_COLORS[p.classId ?? 0] ?? "#69ccf0" }}>
                  <b>{p.name.split("-")[0]}{p.me ? ` · ${w.you}` : ""}</b>
                  <small>{[p.role ? w.role[p.role] : null, p.classId !== undefined ? CLASSES[p.classId] : null, p.level ? `${w.level} ${p.level}` : null].filter(Boolean).join(" · ")}</small>
                </span>
                {p.meter && <strong title={`${w.damage} · ${w.healing} · ${w.taken}`}>{num(p.meter.dmg)} · {num(p.meter.heal)}</strong>}
              </li>
            ))}</ol>
            {r.bosses.length > 0 && <>
              <h3 className="chr-inst-h">{w.bosses}</h3>
              <ul className="chr-inst-bosses is-compact">{r.bosses.map(b => <li key={b.name} className={`is-${b.status}`}><NpcIcon id={b.npc} name={b.name} size={26} /><b>{b.name}</b><span>{w[b.status]}{b.t !== undefined ? ` · ${clock(b.t - r.from)}` : ""}</span></li>)}</ul>
            </>}
            {!r.info && <p className="chr-muted">{w.unknownPlace}</p>}
          </>}

          {tab === "bosses" && <ul className="chr-inst-bosses is-detail">{r.bosses.map(b => (
            <li key={b.name} className={`is-${b.status}`}>
              <details open={b.status !== "unseen"}>
                <summary>
                  <NpcIcon id={b.npc} name={b.name} size={40} />
                  <div><b>{b.name}{b.rare ? ` · ${w.rare}` : ""}</b>
                    <small>{[w[b.status], b.t !== undefined ? clock(b.t - r.from) : null, b.d !== undefined ? `${w.duration.toLowerCase()} ${clock(b.d)}` : null,
                      b.fights.length > 1 ? `${b.fights.length} ${w.attempts}` : null, b.wipes ? `${b.wipes} ${w.wipes}` : null, b.extra ? w.extra : null].filter(Boolean).join(" · ")}</small></div>
                  {b.t !== undefined && <button type="button" className="chr-btn" onClick={event => { event.preventDefault(); jump(b.t!); }}>{w.jump}</button>}
                </summary>
                {b.fights.map((i, n) => c.fights?.[i] && <FightCard key={i} fight={c.fights[i]} index={i} from={r.from} w={w} onOpen={onOpenFight} label={b.fights.length > 1 ? `${w.attempt} ${n + 1}` : w.fight} />)}
                {b.status !== "unseen" && b.fights.length === 0 && <p className="chr-muted">{w.noFight}</p>}
              </details>
            </li>
          ))}</ul>}

          {tab === "enemies" && <>
            <p className="chr-muted">{w.enemiesNote}</p>
            {r.enemies.length === 0 ? <p className="chr-muted">{w.noEnemies}</p> : <table className="chr-spells chr-inst-table">
              <tbody>{r.enemies.map(e => <tr key={e.name}><td><NpcIcon name={e.name} size={24} /> {e.name}</td><td>{e.count}{w.times}</td><td>{e.xp ? `+${num(e.xp)} XP` : ""}</td><td>{clock(e.first - r.from)}</td></tr>)}</tbody>
            </table>}
            {r.trash.length > 0 && <>
              <h3 className="chr-inst-h">{w.npcFights}</h3>
              <FightTotals list={npcFights} w={w} />
              {r.trash.map(x => <FightCard key={x.index} fight={x.fight} index={x.index} from={r.from} w={w} onOpen={onOpenFight} label={`${x.fight.name}${x.kills ? ` · ${x.kills} ${w.fightKills}` : ""}`} />)}
            </>}
            {r.deaths.length > 0 && <>
              <h3 className="chr-inst-h">{w.deaths}</h3>
              <ul className="chr-inst-list">{r.deaths.map((d, i) => <li key={i} className="is-death"><span>{clock(d.t - r.from)}</span><b>{d.text}</b>{fightButton(d.f)}</li>)}</ul>
            </>}
          </>}

          {tab === "loot" && (r.loot.length === 0 ? <p className="chr-muted">{w.noLoot}</p> : <ul className="chr-inst-list">{r.loot.map(x => (
            <li key={x.name}><ItemIcon id={x.id} q={x.q} size={26} /><b style={{ color: QUALITY[x.q] ?? "#fff" }}>{x.name}</b><small>{x.n > 1 ? `${x.n}${w.times} · ` : ""}{clock(x.t - r.from)}</small></li>
          ))}{r.copper !== 0 && <li><IconChip k="loot.money" size={26} /><b>{moneyText(r.copper)}</b></li>}</ul>)}

          {tab === "story" && (r.story.length === 0 ? <p className="chr-muted">{w.noStory}</p> : <ol className="chr-inst-list is-story">{r.story.map((e, i) => (
            <li key={i} className={e.k === "death" ? "is-death" : e.k === "boss" || e.k === "kill" ? "is-boss" : ""}>
              <button type="button" className="chr-inst-jump" onClick={() => jump(e.t)}><span>{clock(e.t - r.from)}</span>
                {e.k === "loot" ? <ItemIcon id={e.id} q={e.q} size={22} /> : <TypeIcon k={e.k === "kill" ? "combat.boss" : e.k === "dungeon" ? "travel.instance" : e.k === "combat" ? "combat.fight" : e.k === "boss" ? "combat.boss" : e.k === "death" ? "combat.death" : e.k === "level" ? "char.level" : "quest.turnin"} size={16} />}
                <em>{w.story[e.k] ?? e.k}</em><b>{e.text}</b></button>
              {fightButton(e.f)}
            </li>
          ))}</ol>)}

          {tab === "map" && r.info?.floors && <>
            {r.info.floors.length > 1 && <nav className="chr-chips">{r.info.floors.map((f, i) => <button key={f.img} type="button" className={`chr-inst-floor${i === floor ? " is-on" : ""}`} onClick={() => setFloor(i)}>{f.name ?? `${w.floor} ${i + 1}`}</button>)}</nav>}
            <figure className="chr-inst-map"><img src={r.info.floors[Math.min(floor, r.info.floors.length - 1)].img} alt={r.info.floors[Math.min(floor, r.info.floors.length - 1)].name ?? inst.name} /></figure>
            <p className="chr-muted">{w.mapNote}</p>
          </>}
        </div>
      </section>
    </div>
  );
}

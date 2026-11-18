"use client";
// The replay of a recorded journey: a map you can move and zoom freely (or let it follow the character), a timeline with the
// zones, dungeons and notable moments, the numbers so far, filters, a calendar of the days played, and the list of everything
// that happened. It runs entirely in the browser from one recording.
import { useCallback, useEffect, useMemo, useRef, useState, type PointerEvent as ReactPointerEvent, type ReactNode } from "react";
import { useI18n } from "@/lib/i18n";
import {
  ALL_TYPES, CATEGORIES, FIGHT_JOIN, TYPE_KEYS, buildIndex, categoryOf, clock, countByCategory, countByType, daysOf, demoChronicle, eventAt, eventsBetween, fightAt, fightBlocks, fightProgress,
  instanceAt, instanceSummary, instances, journeyTimeOf, moneyText, parseChronicle, passes, positionAt, sessionAt, statsAt, totalsAt, typeKey, visits, whenOf,
  type Aura, type Category, type Chronicle, type ChronicleEvent, type Day, type Instance,
} from "@/lib/chronicle";
import { routePoints, routeSegments, type RouteSegment } from "@/lib/chronicle-route";
import { CLASS_COLORS, CLASSES, RACES } from "../data";
import { DiscordGlyph, Icon } from "../ui";
import { api, useApi } from "../api";
import type { User } from "../types";
import { useMaps } from "../db/store";
import { PagedSearch, Pager, usePaged } from "../Paged";
import type { MapDefinition } from "../world-map";
import { FightWindow, num } from "./ChronicleFight";
import { InstanceWindow } from "./ChronicleInstance";
import { crossedFight } from "@/lib/chronicle-replay";
import { MAX_SOUND_SPEED, Sfx, pickCues } from "@/lib/chronicle-sound";
import { INK, IconChip, ItemIcon, MARK_COLOR, Portrait, SpellIcon, TypeIcon, classIconUrl, drawIcon, hasIcon } from "./ChronicleArt";

const SPEEDS = [1, 5, 20, 60, 200] as const;
const COLORS: Record<Category, string> = { quests: "#f2c04b", combat: "#e2786a", loot: "#c9c4d6", professions: "#5fb98d", travel: "#7fb2ff", character: "#a78bfa" };
const QUALITY = ["#9d9d9d", "#ffffff", "#1eff00", "#0070dd", "#a335ee", "#ff8000"];
// Only what matters along the line of time: quests, dungeons, fights, deaths, levels, flights. Jumps, casts, mounts and auras
// are a click away in the filters, not the default: hundreds of them drowned the rest.
const SHOWN_ON_TIMELINE = ["quest.accept", "quest.turnin", "quest.abandon", "combat.fight", "combat.boss", "combat.pvp", "combat.death", "travel.instance", "travel.raid", "travel.flight", "char.level"];
/** Marks of fights closer together than this (seconds of the journey) are one mark, like their block in the fight lane. */
const FIGHT_KEYS = new Set(["combat.fight", "combat.kill", "combat.pvp"]);
const SHOWN_ON_MAP = ["quest.accept", "quest.turnin", "quest.abandon", "combat.fight", "combat.kill", "combat.death", "combat.boss", "combat.pvp", "char.level", "travel.instance", "travel.raid", "travel.flight"];

const TEXT = {
  en: {
    of: "The journey of", toPlay: "to play", forHelp: "for shortcuts", helpTitle: "Keyboard",
    keys: [["Space", "Play / pause"], ["← →", "Back / forward 10 s (Shift: 60 s)"], ["F", "Follow the character"], ["M", "Show or hide the moments"], ["+  −", "Faster / slower"], ["Drag, wheel", "Move and zoom the map"], ["?", "This help"]] as [string, string][],
    title: "Journey replay", heading: "Chronicle", lead: "Journeys that players chose to share: where the character walked, what it finished and found, on a timeline you can scrub.",
    period: "Period", allTime: "All", periodDays: "days", composing: "Composing…", failed: "The journey could not be loaded.",
    emptyTitle: "Nothing recorded for this period.", sample: "See a sample with generated data",
    howto: "A journey is composed from what the addon records and the Bridge sends: the route, zones, quests, loot, levels, dungeons and bosses.",
    publicHead: "Public chronicles", searchList: "Search by character or realm", noMatch: "No chronicle matches the search.", previous: "Previous", next: "Next", pagesLabel: "Pages", noPublic: "Nobody has shared a chronicle for this period yet. Players turn it on with “Share my chronicle” in the addon, or in Account on the website.",
    privateTag: "not public", sessionsOf: ["session", "sessions"], eventsOf: "moments", whenPlayed: "Played", hours: "h", minutes: "min",
    demo: "Play the demo", open: "Open a recording", drop: "or drop a recording file here",
    note: "The addon does not write recordings yet. The demo is a generated journey, not a real player's. A real recording uses the same format.",
    bad: "This file is not a valid recording.", unreadable: "The file could not be read.", loading: "Loading maps…",
    play: "Play", pause: "Pause", replay: "Play again", speed: "Speed", follow: "Follow the character", skipFights: "Skip fights (keep playing)", idle: "Skip quiet stretches", moments: "Moments", full: "Full screen", backPreview: "Back to preview",
    searchMoments: "Search the recording", older: "Earlier", newer: "Later", followMoments: "Follow playback", buffs: "Buffs", debuffs: "Debuffs", noAuras: "No active effects recorded.", aurasUnavailable: "Effects were not readable at this moment.", noSheet: "No attributes recorded for this moment.", solo: "Solo", party: "Party", raid: "Raid", groupMember: "Member", outcome: "Outcome", source: "Source", coverage: "Coverage", notRecorded: "Not recorded", groupTotal: "Whole instance summary", unknownPosition: "No map position recorded for this moment.",
    actionNames: { cast: "Cast", cast_start: "Casting", cast_failed: "Cast failed", jump: "Jumped", mount: "Mounted", dismount: "Dismounted", item: "Used" } as Record<string, string>, auraNames: { gain: "Gained", loss: "Lost", refresh: "Refreshed" } as Record<string, string>, resultNames: { kill: "Defeated", wipe: "Wipe", win: "Victory", loss: "Defeat", ended: "Ended", interrupted: "Interrupted" } as Record<string, string>,
    wallet: "Money held", lifetime: "Total time played", gear: "Gear", moneyChange: "money change", otherSkills: "Other skills",
    difficulty: "Difficulty", groupSize: "Group size", groupDamage: "Group damage", groupShare: "of the group's damage", bySpell: "By spell", speaker: "Speaker", dialogue: "NPC dialogue", say: "says", more: "Show all", less: "Show less",
    sofar: "So far", quests: "quests done", kills: "kills", xp: "XP", money: "money", items: "items", places: "places", deaths: "deaths", skills: "Skills", professions: "Professions",
    sheet: "Sheet", copyLink: "Copy link", copied: "Link copied", itemLevel: "Item level", attributes: "Attributes", enhancements: "Enhancements", notedAt: "Stats as noted at", recorded: "recorded", played: "of play",
    earlier: "earlier moments not shown", later: "later moments not shown", what: "What happened", where: "Where", type: "Type", amount: "Amount", reward: "Experience", fight: "Fight", attempt: "Attempt",
    into: "into the journey", session: "session", back: "Back to the start", none: "Nothing to show here yet.", level: "Level",
    killsList: "Kills", itemsList: "Items", centre: "Centre on the character", zoomIn: "Zoom in", zoomOut: "Zoom out",
    show: "Show", reset: "Reset", tabs: { timeline: "Timeline", map: "Map", icon: "Character icon" } as Record<string, string>,
    tabNote: { timeline: "Badges and hairlines along the line of time.", map: "Markers placed on the map.", icon: "Messages that rise above the character." } as Record<string, string>,
    quality: ["Poor", "Common", "Uncommon", "Rare", "Epic"], andBetter: "and better",
    days: "Days", lastDay: "Last day played", whole: "Whole journey", pickDays: "Pick a day, then another to watch everything between them.", menu: "Settings",
    inInstance: "In", wiped: "wiped after", killedIn: "killed in", pull: "attempt",
    cat: { quests: "Quests", combat: "Combat", loot: "Loot and money", professions: "Professions", travel: "Travel", character: "Character" } as Record<Category, string>,
    types: { "quest.accept": "Quests accepted", "quest.turnin": "Quests turned in", "quest.abandon": "Quests abandoned", "combat.kill": "Kills", "combat.death": "Deaths", "combat.boss": "Boss encounters", "combat.pvp": "PvP matches", "loot.item": "Loot", "loot.money": "Money", "prof.skill": "Skill-ups", "travel.flight": "Flight paths", "travel.instance": "Instances", "travel.zone": "Zones", "char.level": "Levels", "char.group": "Group changes", "char.emote": "Emotes" } as Record<string, string>,
    kind: { quest: "Quest", kill: "Kill", loot: "Loot", money: "Money", level: "Level", skill: "Skill", zone: "Zone", death: "Death", dungeon: "Dungeon", travel: "Travel", boss: "Boss", group: "Group", emote: "Emote", pvp: "PvP" } as Record<string, string>,
    accepted: "Accepted", done: "Completed", handed: "Handed in", abandoned: "Abandoned", defeated: "Defeated", wipedOn: "Wiped on", victory: "Victory", defeat: "Defeat",
    openFight: "Open the fight", openInstance: "Open the dungeon", sound: "Sound", volume: "Volume", win: "Victory", loss: "Defeat", damage: "Damage", healing: "Healing", taken: "Taken", inFight: "In combat",
  },
  cs: {
    of: "Cesta postavy", toPlay: "přehrát", forHelp: "zkratky", helpTitle: "Klávesy",
    keys: [["Mezerník", "Přehrát / pozastavit"], ["← →", "Zpět / vpřed o 10 s (Shift: 60 s)"], ["F", "Sledovat postavu"], ["M", "Zobrazit nebo skrýt momenty"], ["+  −", "Rychleji / pomaleji"], ["Tažení, kolečko", "Posun a přiblížení mapy"], ["?", "Tato nápověda"]] as [string, string][],
    title: "Přehrání cesty", heading: "Kronika", lead: "Cesty, které hráči sami sdílejí: kudy postava šla, co dokončila a našla, na časové ose, po které můžeš posouvat.",
    period: "Období", allTime: "Vše", periodDays: "dní", composing: "Skládám…", failed: "Cestu se nepodařilo načíst.",
    emptyTitle: "Za toto období nic není zaznamenáno.", sample: "Ukázka s vygenerovanými daty",
    howto: "Cesta se skládá z toho, co addon zapisuje a Bridge posílá: trasa, zóny, questy, loot, úrovně, dungeony a bossové.",
    publicHead: "Veřejné kroniky", searchList: "Hledat postavu nebo realm", noMatch: "Hledání neodpovídá žádná kronika.", previous: "Předchozí", next: "Další", pagesLabel: "Stránky", noPublic: "Za toto období zatím nikdo žádnou kroniku nesdílí. Hráč ji zapne volbou „Sdílet mou kroniku“ v addonu nebo v Účtu na webu.",
    privateTag: "neveřejná", sessionsOf: ["hraní", "hraní"], eventsOf: "momentů", whenPlayed: "Hráno", hours: "h", minutes: "min",
    demo: "Přehrát ukázku", open: "Otevřít záznam", drop: "nebo sem přetáhni soubor se záznamem",
    note: "Addon záznamy zatím nezapisuje. Ukázka je vygenerovaná cesta, ne skutečného hráče. Skutečný záznam bude mít stejný formát.",
    bad: "Tento soubor není platný záznam.", unreadable: "Soubor se nepodařilo přečíst.", loading: "Načítám mapy…",
    play: "Přehrát", pause: "Pozastavit", replay: "Přehrát znovu", speed: "Rychlost", follow: "Sledovat postavu", skipFights: "Přeskakovat souboje (nezastavovat)", idle: "Přeskakovat klidné úseky", moments: "Momenty", full: "Celá obrazovka", backPreview: "Zpět na náhled",
    searchMoments: "Hledat v záznamu", older: "Starší", newer: "Novější", followMoments: "Sledovat přehrávání", buffs: "Buffy", debuffs: "Debuffy", noAuras: "Nejsou zaznamenané žádné aktivní efekty.", aurasUnavailable: "Efekty v tomto okamžiku nebyly čitelné.", noSheet: "Pro tento okamžik nejsou zaznamenané atributy.", solo: "Bez skupiny", party: "Parta", raid: "Raid", groupMember: "Člen", outcome: "Výsledek", source: "Zdroj", coverage: "Pokrytí", notRecorded: "Nezaznamenáno", groupTotal: "Souhrn celé instance", unknownPosition: "Pro tento okamžik není zaznamenaná poloha na mapě.",
    actionNames: { cast: "Použito", cast_start: "Sesílání", cast_failed: "Kouzlo selhalo", jump: "Skok", mount: "Nasednutí", dismount: "Sesednutí", item: "Použito" } as Record<string, string>, auraNames: { gain: "Získáno", loss: "Ztraceno", refresh: "Obnoveno" } as Record<string, string>, resultNames: { kill: "Poražen", wipe: "Neúspěch", win: "Vítězství", loss: "Porážka", ended: "Ukončen", interrupted: "Přerušen" } as Record<string, string>,
    wallet: "Stav peněz", lifetime: "Celkem odehráno", gear: "Výbava", moneyChange: "změna peněz", otherSkills: "Ostatní dovednosti",
    difficulty: "Obtížnost", groupSize: "Velikost skupiny", groupDamage: "Poškození skupiny", groupShare: "poškození skupiny", bySpell: "Podle kouzel", speaker: "Mluvčí", dialogue: "Hlášky NPC", say: "říká", more: "Zobrazit vše", less: "Méně",
    sofar: "Zatím", quests: "questů hotovo", kills: "zabití", xp: "XP", money: "peníze", items: "předmětů", places: "míst", deaths: "smrtí", skills: "Dovednosti", professions: "Profese",
    sheet: "Postava", copyLink: "Kopírovat odkaz", copied: "Odkaz zkopírován", itemLevel: "Úroveň výbavy", attributes: "Atributy", enhancements: "Vylepšení", notedAt: "Staty zaznamenané v", recorded: "zaznamenáno", played: "hraní",
    earlier: "dřívějších momentů se nezobrazuje", later: "pozdějších momentů se nezobrazuje", what: "Co se stalo", where: "Kde", type: "Druh", amount: "Množství", reward: "Zkušenosti", fight: "Souboj", attempt: "Pokus",
    into: "od začátku cesty", session: "hraní", back: "Zpět na začátek", none: "Zatím tu není co ukázat.", level: "Úroveň",
    killsList: "Zabití", itemsList: "Předměty", centre: "Vycentrovat na postavu", zoomIn: "Přiblížit", zoomOut: "Oddálit",
    show: "Zobrazit", reset: "Obnovit", tabs: { timeline: "Časová osa", map: "Mapa", icon: "Ikona postavy" } as Record<string, string>,
    tabNote: { timeline: "Značky a čáry podél časové osy.", map: "Značky umístěné na mapě.", icon: "Zprávy, které stoupají nad postavou." } as Record<string, string>,
    quality: ["Špatná", "Obyčejná", "Neobvyklá", "Vzácná", "Epická"], andBetter: "a lepší",
    days: "Dny", lastDay: "Poslední hraný den", whole: "Celá cesta", pickDays: "Vyber den a pak další a uvidíš vše mezi nimi.", menu: "Nastavení",
    inInstance: "V", wiped: "neúspěch po", killedIn: "poražen za", pull: "pokus",
    cat: { quests: "Questy", combat: "Boj", loot: "Loot a peníze", professions: "Profese", travel: "Cestování", character: "Postava" } as Record<Category, string>,
    types: { "quest.accept": "Přijaté questy", "quest.turnin": "Odevzdané questy", "quest.abandon": "Opuštěné questy", "combat.kill": "Zabití", "combat.death": "Smrti", "combat.boss": "Souboje s bossy", "combat.pvp": "PvP zápasy", "loot.item": "Loot", "loot.money": "Peníze", "prof.skill": "Zlepšení dovedností", "travel.flight": "Letecké cesty", "travel.instance": "Instance", "travel.zone": "Zóny", "char.level": "Úrovně", "char.group": "Změny skupiny", "char.emote": "Emoty" } as Record<string, string>,
    kind: { quest: "Quest", kill: "Zabití", loot: "Loot", money: "Peníze", level: "Úroveň", skill: "Dovednost", zone: "Zóna", death: "Smrt", dungeon: "Dungeon", travel: "Cestování", boss: "Boss", group: "Skupina", emote: "Emote", pvp: "PvP" } as Record<string, string>,
    accepted: "Přijato", done: "Splněno", handed: "Odevzdáno", abandoned: "Opuštěno", defeated: "Poražen", wipedOn: "Neúspěch na", victory: "Vítězství", defeat: "Porážka",
    openFight: "Otevřít souboj", openInstance: "Otevřít dungeon", sound: "Zvuk", volume: "Hlasitost", win: "Vítězství", loss: "Porážka", damage: "Poškození", healing: "Léčení", taken: "Utrženo", inFight: "V boji",
  },
};
type Words = typeof TEXT.en;
Object.assign(TEXT.en.types, { "combat.fight": "All fights", "action.cast": "Spell casts", "action.jump": "Jumps", "action.mount": "Mount changes", "action.item": "Items used", "action.other": "Other actions", "aura.gain": "Effects gained", "aura.loss": "Effects lost", "aura.refresh": "Effects refreshed", "char.state": "Character snapshots" });
Object.assign(TEXT.cs.types, { "combat.fight": "Všechny souboje", "action.cast": "Použitá kouzla", "action.jump": "Skoky", "action.mount": "Nasednutí a sesednutí", "action.item": "Použité předměty", "action.other": "Další akce", "aura.gain": "Získané efekty", "aura.loss": "Ztracené efekty", "aura.refresh": "Obnovené efekty", "char.state": "Snímky postavy" });
Object.assign(TEXT.en.kind, { combat: "Fight", action: "Action", aura: "Effect", state: "Character state" });
Object.assign(TEXT.cs.kind, { combat: "Souboj", action: "Akce", aura: "Efekt", state: "Stav postavy" });
TEXT.en.types['char.speech'] = 'NPC dialogue'; TEXT.cs.types['char.speech'] = 'Hlášky NPC';
TEXT.en.types['travel.raid'] = 'Raids'; TEXT.cs.types['travel.raid'] = 'Raidy';
TEXT.en.kind.speech = 'NPC dialogue'; TEXT.cs.kind.speech = 'Hláška NPC';
TEXT.en.actionNames.item_attempt = "Use requested";
TEXT.cs.actionNames.item_attempt = "Pokus o použití";

/** The text of a moment, as it is listed and as it floats above the character. */
function popup(e: ChronicleEvent, w: Words): { text: string; color: string } {
  switch (e.k) {
    case "quest": return { text: `${e.a === "accept" ? w.accepted : e.a === "abandon" ? w.abandoned : e.a === "turnin" ? w.handed : w.done}: ${e.text}${e.xp ? ` +${e.xp} XP` : ""}`, color: COLORS.quests };
    case "kill": return { text: `${e.text}${e.xp ? ` +${e.xp} XP` : ""}`, color: COLORS.combat };
    case "boss": return { text: `${e.a === "wipe" ? w.wipedOn : w.defeated} ${e.text}`, color: e.a === "wipe" ? COLORS.combat : "#7be0a0" };
    case "pvp": return { text: `${e.a === "win" ? w.victory : w.defeat}: ${e.text}`, color: e.a === "win" ? "#7be0a0" : COLORS.combat };
    case "loot": return { text: `${e.text}${e.n && e.n > 1 ? ` ×${e.n}` : ""}`, color: QUALITY[e.q ?? 1] };
    case "money": return { text: moneyText(e.n ?? 0), color: "#f2c04b" };
    case "skill": return { text: `${e.text} ${e.max ? `${e.n}/${e.max}` : e.n}`, color: COLORS.professions };
    case "level": return { text: `${w.level} ${e.n}!`, color: COLORS.character };
    case "death": return { text: e.text, color: COLORS.combat };
    case "combat": return { text: `${e.a === "start" ? w.inFight : w.fight}: ${e.text}${e.d !== undefined ? ` · ${clock(e.d)}` : ""}`, color: COLORS.combat };
    case "action": return { text: e.a === "jump" ? w.actionNames.jump : `${w.actionNames[e.a ?? ""] ?? w.kind.action}: ${e.text}`, color: COLORS.character };
    case "aura": return { text: `${w.auraNames[e.a ?? "gain"] ?? w.kind.aura}: ${e.text}${e.stacks && e.stacks > 1 ? ` ×${e.stacks}` : ""}`, color: e.helpful ? COLORS.professions : COLORS.combat };
    case "state": return { text: e.text, color: COLORS.character };
    case "speech": return { text: `${e.speaker ?? e.text} ${w.say}: ${e.message ?? ""}`, color: "#d3c3a3" };
    default: return { text: e.text, color: COLORS.travel };
  }
}
const nameOf = (maps: readonly MapDefinition[], key: string, lang: string) => {
  const m = maps.find(x => x.key === key);
  return m ? (lang === "cs" ? m.nameCs : m.nameEn) : key.replace(/-/g, " ").replace(/^./, s => s.toUpperCase());
};
const hue = (key: string) => { let h = 0; for (const ch of key) h = (h * 31 + ch.charCodeAt(0)) % 360; return h; };
const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v));

type Cam = { x: number; y: number; z: number };
type ZoneArt = { key: string; img: HTMLImageElement | null; w: number; h: number };
type StageProps = { follow: boolean; overview: boolean; reduced: boolean; words: Words; mapTypes: ReadonlySet<string>; iconTypes: ReadonlySet<string>; minQ: number; onFree: () => void };
export type StageApi = { zoom: (factor: number) => void };

/**
 * The map: the zone picture under a camera that follows the character or is moved by hand (drag, wheel, pinch, double click),
 * with the trail, the markers of what happened and the messages that rise above the character.
 */
function Stage({ c, maps, timeRef, props, onApi }: { c: Chronicle; maps: readonly MapDefinition[]; timeRef: { current: number }; props: StageProps; onApi: (api: StageApi) => void }) {
  const canvas = useRef<HTMLCanvasElement>(null);
  const live = useRef(props);
  useEffect(() => { live.current = props; });
  const classColor = CLASS_COLORS[c.character.classId] ?? "#69ccf0";
  useEffect(() => {
    const el = canvas.current;
    const ctx = el?.getContext("2d");
    if (!el || !ctx) return;
    const images = new Map<string, HTMLImageElement>();
    const portrait = new Image();
    portrait.src = classIconUrl(c.character.classId);
    const art = (key: string): ZoneArt => {
      const def = maps.find(m => m.key === key);
      if (!def) return { key, img: null, w: 1000, h: 667 };
      let img = images.get(def.image);
      if (!img) { img = new Image(); img.decoding = "async"; img.src = def.image; images.set(def.image, img); }
      return { key, img: img.complete && img.naturalWidth ? img : null, w: def.width, h: def.height };
    };
    let cw = 0, ch = 0, raf = 0, lastNow = performance.now();
    const resize = () => {
      const dpr = Math.min(2, window.devicePixelRatio || 1);
      cw = el.clientWidth; ch = el.clientHeight;
      el.width = Math.max(1, Math.floor(cw * dpr)); el.height = Math.max(1, Math.floor(ch * dpr));
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    };
    resize();
    const observer = new ResizeObserver(resize);
    observer.observe(el);

    const cam: Cam = { x: 0.5, y: 0.5, z: 1 };
    const free: Cam = { x: 0.5, y: 0.5, z: 1 };
    let zone = -1, fadeStart = -1e9, wasFollow = live.current.follow;
    let previous: { art: ZoneArt; cam: Cam } | null = null;
    const longest = visits(c).reduce((best, v) => (v.to - v.from > best.span ? { zone: v.zone, span: v.to - v.from } : best), { zone: 0, span: -1 }).zone;
    const overviewStep = Math.max(1, Math.ceil(c.path.length / 900));
    const histories = new Map<number, RouteSegment[]>();
    for (const segment of routeSegments(c)) {
      const list = histories.get(segment.zone) ?? [];
      list.push(segment); histories.set(segment.zone, list);
    }
    const paths = new Map<RouteSegment, Path2D>();
    const routePath = (segment: RouteSegment, map: ZoneArt, from: number, to: number) => {
      const whole = from <= segment.from && to >= segment.to;
      const saved = whole ? paths.get(segment) : undefined;
      if (saved) return saved;
      const path = new Path2D();
      routePoints(segment, from, to).forEach((p, i) => { if (i) path.lineTo(p[2] * map.w, p[3] * map.h); else path.moveTo(p[2] * map.w, p[3] * map.h); });
      if (whole) paths.set(segment, path);
      return path;
    };

    const base = (a: ZoneArt) => Math.min(cw / a.w, ch / a.h);
    const place = (a: ZoneArt, k: Cam, u: number, v: number): [number, number] => {
      const s = base(a) * k.z;
      return [cw / 2 + (u - k.x) * a.w * s, ch / 2 + (v - k.y) * a.h * s];
    };
    const drawZone = (a: ZoneArt, k: Cam, alpha: number) => {
      const s = base(a) * k.z;
      const [x0, y0] = place(a, k, 0, 0);
      ctx.globalAlpha = alpha;
      if (a.img) { ctx.drawImage(a.img, x0, y0, a.w * s, a.h * s); ctx.fillStyle = "rgba(9,8,16,0.28)"; ctx.fillRect(x0, y0, a.w * s, a.h * s); }
      else { ctx.fillStyle = "#1c1a28"; ctx.fillRect(x0, y0, a.w * s, a.h * s); }
      ctx.globalAlpha = 1;
    };

    // ---- moving the map by hand
    const here = () => art(c.zones[Math.max(0, zone)]);
    /** Take the map out of "follow": the view stays where it is and the page is told. */
    const release = () => { if (live.current.follow) { Object.assign(free, cam); live.current.onFree(); } };
    const zoomAt = (px: number, py: number, factor: number) => {
      release();
      const a = here();
      const s = base(a) * cam.z;
      const u = (px - cw / 2) / (a.w * s) + cam.x, v = (py - ch / 2) / (a.h * s) + cam.y;
      const z = clamp(cam.z * factor, 0.5, 9);
      const s2 = base(a) * z;
      cam.x = clamp(u - (px - cw / 2) / (a.w * s2), 0, 1); cam.y = clamp(v - (py - ch / 2) / (a.h * s2), 0, 1); cam.z = z;
      Object.assign(free, cam);
    };
    const pointers = new Map<number, { x: number; y: number }>();
    let pinch = 0;
    const spot = (e: { clientX: number; clientY: number }) => { const r = el.getBoundingClientRect(); return { x: e.clientX - r.left, y: e.clientY - r.top }; };
    const down = (e: PointerEvent) => { if (live.current.overview) return; el.setPointerCapture(e.pointerId); pointers.set(e.pointerId, spot(e)); el.classList.add("is-drag"); pinch = 0; };
    const move = (e: PointerEvent) => {
      const old = pointers.get(e.pointerId);
      if (!old) return;
      const now = spot(e);
      pointers.set(e.pointerId, now);
      if (pointers.size === 2) {
        const [p, q] = [...pointers.values()];
        const dist = Math.hypot(p.x - q.x, p.y - q.y);
        if (pinch) zoomAt((p.x + q.x) / 2, (p.y + q.y) / 2, dist / pinch);
        pinch = dist;
      } else if (pointers.size === 1 && (now.x !== old.x || now.y !== old.y)) {
        release();
        const a = here(), s = base(a) * cam.z;
        cam.x = clamp(cam.x - (now.x - old.x) / (a.w * s), 0, 1); cam.y = clamp(cam.y - (now.y - old.y) / (a.h * s), 0, 1);
        Object.assign(free, cam);
      }
    };
    const up = (e: PointerEvent) => { pointers.delete(e.pointerId); pinch = 0; if (!pointers.size) el.classList.remove("is-drag"); };
    const wheel = (e: WheelEvent) => { if (live.current.overview) return; e.preventDefault(); const p = spot(e); zoomAt(p.x, p.y, Math.exp(-e.deltaY * 0.0016)); };
    const dbl = (e: MouseEvent) => { if (live.current.overview) return; const r = el.getBoundingClientRect(); zoomAt(e.clientX - r.left, e.clientY - r.top, 1.8); };
    el.addEventListener("pointerdown", down); el.addEventListener("pointermove", move); el.addEventListener("pointerup", up); el.addEventListener("pointercancel", up);
    el.addEventListener("wheel", wheel, { passive: false }); el.addEventListener("dblclick", dbl);
    onApi({ zoom: factor => zoomAt(cw / 2, ch / 2, factor) });

    const draw = (now: number) => {
      const p = live.current;
      const dt = Math.min(0.1, (now - lastNow) / 1000); lastNow = now;
      const t = timeRef.current;
      const pos = positionAt(c, t);
      ctx.clearRect(0, 0, cw, ch);
      const bg = ctx.createRadialGradient(cw / 2, ch / 2, 0, cw / 2, ch / 2, Math.max(cw, ch) * 0.7);
      bg.addColorStop(0, "#1b1930"); bg.addColorStop(1, "#0b0b12");
      ctx.fillStyle = bg; ctx.fillRect(0, 0, cw, ch);
      if (!pos) { raf = requestAnimationFrame(draw); return; }
      if (p.overview) {
        // before the start: the zone where most of the journey happened, with the whole way through it
        const a = art(c.zones[longest]);
        const whole: Cam = { x: 0.5, y: 0.5, z: 0.92 };
        drawZone(a, whole, 1);
        ctx.lineCap = "round"; ctx.lineJoin = "round"; ctx.shadowColor = "rgba(90,170,255,0.9)"; ctx.shadowBlur = 8;
        ctx.strokeStyle = "rgba(105,185,255,0.85)"; ctx.lineWidth = 2.4; ctx.beginPath();
        let pen = false;
        for (let i = 0; i < c.path.length; i += overviewStep) {
          const q = c.path[i];
          if (q[1] !== longest) { pen = false; continue; }
          const [sx, sy] = place(a, whole, q[2], q[3]);
          if (pen) ctx.lineTo(sx, sy); else ctx.moveTo(sx, sy);
          pen = true;
        }
        ctx.stroke(); ctx.shadowBlur = 0;
        raf = requestAnimationFrame(draw);
        return;
      }
      const map = art(c.zones[pos.zone]);
      if (wasFollow && !p.follow) Object.assign(free, cam);
      wasFollow = p.follow;
      // following keeps the zoom the visitor chose, but never closer in than a comfortable minimum
      const target: Cam = p.follow ? { x: pos.x, y: pos.y, z: Math.max(cam.z, 2.6) } : free;
      if (zone !== pos.zone) {
        if (zone >= 0 && !p.reduced) { previous = { art: art(c.zones[zone]), cam: { ...cam } }; fadeStart = now; }
        zone = pos.zone;
        Object.assign(free, { x: 0.5, y: 0.5, z: 1 });
        Object.assign(cam, p.follow ? target : free);
      } else {
        const k = 1 - Math.exp(-dt * (p.follow ? 5 : 8));
        cam.x += (target.x - cam.x) * k; cam.y += (target.y - cam.y) * k; cam.z += (target.z - cam.z) * k;
      }
      const fade = Math.min(1, (now - fadeStart) / 900);
      if (previous && fade < 1) drawZone(previous.art, previous.cam, 1); else previous = null;
      drawZone(map, cam, previous ? fade : 1);

      // Every earlier visit stays a solid dark line. Only unknown gaps are disconnected; real fights colour their own stretch red.
      const history = histories.get(pos.zone) ?? [];
      const scale = base(map) * cam.z;
      ctx.save();
      ctx.translate(cw / 2 - cam.x * map.w * scale, ch / 2 - cam.y * map.h * scale);
      ctx.scale(scale, scale); ctx.lineCap = "round"; ctx.lineJoin = "round";
      for (const segment of history) {
        if (segment.from >= t) break;
        const path = routePath(segment, map, -Infinity, t);
        ctx.strokeStyle = "rgba(9,12,22,.88)"; ctx.lineWidth = 5 / scale; ctx.stroke(path);
        ctx.strokeStyle = segment.combat ? "#9b414a" : "#326a97"; ctx.lineWidth = 2.8 / scale; ctx.stroke(path);
      }
      for (const segment of history) {
        if (segment.from >= t) break;
        if (segment.to < t - 150) continue;
        const path = routePath(segment, map, t - 150, t);
        ctx.shadowColor = segment.combat ? "rgba(255,83,98,.7)" : "rgba(90,170,255,.7)"; ctx.shadowBlur = 6;
        ctx.strokeStyle = segment.combat ? "#ff6b75" : "#71c8ff"; ctx.lineWidth = 3.2 / scale; ctx.stroke(path);
      }
      ctx.restore(); ctx.shadowBlur = 0;
      const [px, py] = place(map, cam, pos.x, pos.y);

      // what happened along the way in this zone (only the kinds the filter allows)
      const inCombat = fightAt(c, t) >= 0;
      ctx.textAlign = "center"; ctx.textBaseline = "middle";
      const badge = (x: number, y: number, r: number, key: string) => {
        ctx.shadowColor = "rgba(0,0,0,0.55)"; ctx.shadowBlur = 5;
        ctx.fillStyle = MARK_COLOR[key] ?? "#7fb2ff"; ctx.strokeStyle = "#14121c"; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(x, y, r, 0, 7); ctx.fill(); ctx.stroke();
        ctx.shadowBlur = 0;
        drawIcon(ctx, key, x, y, r * 1.35, INK[key] ?? "#fff");
      };
      for (const e of eventsBetween(c, -1e-6, t)) {
        if (e.zone !== pos.zone || e.x === undefined || e.y === undefined || !p.mapTypes.has(typeKey(e))) continue;
        const [ex, ey] = place(map, cam, e.x, e.y);
        if (ex < -20 || ey < -20 || ex > cw + 20 || ey > ch + 20) continue;
        const key = typeKey(e);
        if (e.k === "kill") { ctx.fillStyle = `rgba(226,120,106,${Math.max(0.15, 0.85 - (t - e.t) / 400)})`; ctx.beginPath(); ctx.arc(ex, ey, 3.2, 0, 7); ctx.fill(); }
        else if (hasIcon(key)) badge(ex, ey, key === "combat.boss" ? 12 : 10, key);
      }

      // the character, with a ring that pulses and turns red in a fight
      const pulse = p.reduced ? 0.5 : (Math.sin(now / 320) + 1) / 2;
      const ring = inCombat ? "255,107,117" : "105,204,240";
      ctx.strokeStyle = `rgba(${ring},${0.85 - pulse * 0.6})`; ctx.lineWidth = 2.5;
      ctx.beginPath(); ctx.arc(px, py, 17 + pulse * 10, 0, 7); ctx.stroke();
      ctx.shadowColor = "rgba(0,0,0,0.6)"; ctx.shadowBlur = 9;
      ctx.fillStyle = classColor; ctx.beginPath(); ctx.arc(px, py, 14, 0, 7); ctx.fill(); ctx.shadowBlur = 0;
      if (portrait.complete && portrait.naturalWidth) { ctx.save(); ctx.beginPath(); ctx.arc(px, py, 11.5, 0, 7); ctx.clip(); ctx.drawImage(portrait, px - 11.5, py - 11.5, 23, 23); ctx.restore(); }
      ctx.strokeStyle = "#fff"; ctx.lineWidth = 2.5; ctx.beginPath(); ctx.arc(px, py, 13, 0, 7); ctx.stroke();

      // messages rise from the character and fade: the newest nearest to it
      const recent = eventsBetween(c, t - 5, t).filter(e => e.k !== "zone" && passes(e, p.iconTypes, p.minQ)).slice(-5);
      ctx.font = "600 13px Inter, sans-serif"; ctx.lineJoin = "round";
      recent.forEach((e, i) => {
        const age = t - e.t, m = popup(e, p.words);
        const fadeOut = Math.min(1, Math.max(0, (5 - age) / 1.5));
        const rise = p.reduced ? 0 : Math.min(age, 3) * 5;
        const y = py - 36 - (recent.length - 1 - i) * 20 - rise;
        const label = m.text.length > 110 ? `${m.text.slice(0,107)}…` : m.text;
        ctx.globalAlpha = fadeOut; ctx.lineWidth = 4; ctx.strokeStyle = "rgba(10,9,18,0.92)"; ctx.strokeText(label, px, y);
        ctx.fillStyle = m.color; ctx.fillText(label, px, y); ctx.globalAlpha = 1;
      });
      raf = requestAnimationFrame(draw);
    };
    raf = requestAnimationFrame(draw);
    return () => {
      cancelAnimationFrame(raf); observer.disconnect();
      el.removeEventListener("pointerdown", down); el.removeEventListener("pointermove", move); el.removeEventListener("pointerup", up); el.removeEventListener("pointercancel", up);
      el.removeEventListener("wheel", wheel); el.removeEventListener("dblclick", dbl);
    };
  }, [c, maps, timeRef, classColor, onApi]);
  return <canvas ref={canvas} className="chr-canvas" role="img" aria-label={c.character.name} />;
}

/** The shortest stretch the timeline can be zoomed to, in seconds of the journey. */
const MIN_VIEW = 20;
/**
 * The bar at the bottom: zones and dungeons as stretches, the chosen moments as badges, how busy it was, and a playhead to drag.
 * It can be zoomed (wheel, pinch, + and −) and moved (shift + wheel, the bar below, or dragging it); the playback itself still runs over
 * the whole journey, the zoom only decides how much of it is drawn.
 */
function Timeline({ c, maps, time, dom, types, minQ, instanceList, onSeek, onOpenFight, onOpenInstance, lang }: {
  c: Chronicle; maps: readonly MapDefinition[]; time: number; dom: { from: number; to: number }; types: ReadonlySet<string>; minQ: number; instanceList: readonly Instance[]; onSeek: (t: number) => void; onOpenFight: (index: number) => void; onOpenInstance: (index: number) => void; lang: string;
}) {
  const domSpan = Math.max(1, dom.to - dom.from);
  const [zoom, setZoom] = useState<{ from: number; to: number } | null>(null);
  // the view is always inside the whole stretch; a changed stretch (another day picked) starts again from all of it
  const view = useMemo(() => {
    if (!zoom) return dom;
    const span = clamp(zoom.to - zoom.from, Math.min(MIN_VIEW, domSpan), domSpan);
    const from = clamp(zoom.from, dom.from, dom.to - span);
    return { from, to: from + span };
  }, [zoom, dom, domSpan]);
  useEffect(() => { setZoom(null); }, [dom.from, dom.to]);
  const span = Math.max(1, view.to - view.from);
  const zoomed = domSpan / span > 1.02;
  const runs = useMemo(() => visits(c).filter(r => r.to > view.from && r.from < view.to), [c, view.from, view.to]);
  const bars = useRef<HTMLCanvasElement>(null);
  const track = useRef<HTMLDivElement>(null);
  const root = useRef<HTMLDivElement>(null);
  const rail = useRef<HTMLDivElement>(null);
  const dragging = useRef(false);
  const [hover, setHover] = useState<number | null>(null);
  const pct = (t: number) => `${clamp(((t - view.from) / span) * 100, 0, 100)}%`;

  /** Shows a stretch of the journey, or all of it when it is (nearly) the whole. */
  const show = useCallback((from: number, to: number) => {
    const length = clamp(to - from, Math.min(MIN_VIEW, domSpan), domSpan);
    // remembered at once too: several wheel ticks can arrive before the next draw
    if (length >= domSpan * 0.98) { live.current.view = dom; live.current.span = domSpan; setZoom(null); return; }
    const start = clamp(from, dom.from, dom.to - length);
    live.current.view = { from: start, to: start + length }; live.current.span = length;
    setZoom({ from: start, to: start + length });
  }, [dom, domSpan]);
  const live = useRef({ view, span, show });
  live.current = { view, span, show };
  /** Zoom by `factor` (below 1 closer) keeping the moment at fraction `anchor` of the bar where it is. */
  const zoomBy = useCallback((factor: number, anchor = 0.5) => {
    const { view: v, span: sp, show: apply } = live.current;
    const length = sp * factor, focus = v.from + sp * anchor;
    apply(focus - length * anchor, focus + length * (1 - anchor));
  }, []);
  const panBy = useCallback((seconds: number) => { const { view: v, show: apply } = live.current; apply(v.from + seconds, v.to + seconds); }, []);

  // wheel: zoom around the pointer; with shift (or sideways) it moves. Listened to by hand because React's wheel is passive.
  useEffect(() => {
    const el = root.current;
    if (!el) return;
    const wheel = (event: WheelEvent) => {
      const box = el.getBoundingClientRect();
      if (!box.width) return;
      event.preventDefault();
      const sideways = event.shiftKey || Math.abs(event.deltaX) > Math.abs(event.deltaY);
      const delta = sideways ? (Math.abs(event.deltaX) > Math.abs(event.deltaY) ? event.deltaX : event.deltaY) : event.deltaY;
      if (sideways) panBy((delta / box.width) * live.current.span);
      else zoomBy(Math.exp(clamp(delta, -300, 300) * 0.0016), clamp((event.clientX - box.left) / box.width, 0, 1));
    };
    el.addEventListener("wheel", wheel, { passive: false });
    return () => el.removeEventListener("wheel", wheel);
  }, [zoomBy, panBy]);

  // while it plays, the view turns the page when the playhead leaves it; a view the viewer moved away from the playhead is left alone
  const lastTime = useRef(time);
  useEffect(() => {
    const was = lastTime.current;
    lastTime.current = time;
    if (!zoomed || time >= view.from && time <= view.to || !(was >= view.from && was <= view.to)) return;
    show(time - span * 0.15, time + span * 0.85);
  }, [time, zoomed, view.from, view.to, span, show]);

  const marks = useMemo(() => {
    const out: { t: number; key: string; label: string }[] = [];
    const gap = span / 240;
    const last: Record<string, number> = {};
    for (const e of eventsBetween(c, view.from, view.to)) {
      const key = typeKey(e);
      if (!hasIcon(key) || !passes(e, types, minQ) || e.t - (last[key] ?? -1e9) < (FIGHT_KEYS.has(key) ? Math.max(gap, FIGHT_JOIN) : gap)) continue;
      last[key] = e.t; out.push({ t: e.t, key, label: e.text });
    }
    return out;
  }, [c, view.from, view.to, span, types, minQ]);
  const levels = useMemo(() => eventsBetween(c, view.from, view.to).filter(e => e.k === "level").map(e => ({ t: e.t, n: e.n ?? 0 })), [c, view.from, view.to]);
  // fights that follow within a minute are one block: click it for its first fight
  const fights = useMemo(() => fightBlocks(c.fights).filter(b => b.end >= view.from && b.t <= view.to), [c, view.from, view.to]);
  useEffect(() => {
    const el = bars.current;
    const ctx = el?.getContext("2d");
    if (!el || !ctx) return;
    const W = el.width = 600, H = el.height = 20, n = 200;
    const bins = new Array<number>(n).fill(0);
    for (const e of eventsBetween(c, view.from, view.to)) bins[Math.min(n - 1, Math.floor(((e.t - view.from) / span) * n))]++;
    const peak = Math.max(1, ...bins);
    ctx.clearRect(0, 0, W, H);
    bins.forEach((v, i) => { if (!v) return; const h = Math.max(2, (v / peak) * H); ctx.fillStyle = "rgba(167,139,250,0.65)"; ctx.fillRect((i / n) * W, H - h, W / n - 0.6, h); });
  }, [c, view.from, span, view.to]);
  const at = (event: { clientX: number }) => {
    const box = track.current?.getBoundingClientRect();
    return box ? clamp(view.from + ((event.clientX - box.left) / box.width) * span, dom.from, dom.to) : view.from;
  };
  const down = (event: ReactPointerEvent) => { dragging.current = true; (event.currentTarget as HTMLElement).setPointerCapture(event.pointerId); onSeek(at(event)); };
  const move = (event: ReactPointerEvent) => { setHover(at(event)); if (dragging.current) onSeek(at(event)); };
  const band = (from: number, to: number) => ({ left: pct(from), width: `calc(${(clamp(to, view.from, view.to) - clamp(from, view.from, view.to)) / span * 100}% - 2px)` });

  // the bar below: the part shown, to drag, or click beside it to jump there
  const grab = useRef<{ x: number; from: number } | null>(null);
  const thumbDown = (event: ReactPointerEvent) => { event.stopPropagation(); (event.currentTarget as HTMLElement).setPointerCapture(event.pointerId); grab.current = { x: event.clientX, from: view.from }; };
  const thumbMove = (event: ReactPointerEvent) => {
    const box = rail.current?.getBoundingClientRect();
    if (!grab.current || !box?.width) return;
    show(grab.current.from + ((event.clientX - grab.current.x) / box.width) * domSpan, grab.current.from + ((event.clientX - grab.current.x) / box.width) * domSpan + span);
  };
  const railDown = (event: ReactPointerEvent) => {
    const box = rail.current?.getBoundingClientRect();
    if (!box?.width) return;
    const centre = dom.from + ((event.clientX - box.left) / box.width) * domSpan;
    show(centre - span / 2, centre + span / 2);
  };
  return (
    <div className="chr-timeline" ref={root}>
      <div className="chr-levels" aria-hidden="true">{levels.map(l => <span key={l.t} style={{ left: pct(l.t) }}>{l.n}</span>)}</div>
      <div className="chr-zones">
        {runs.map((r, i) => <span key={i} aria-hidden="true" style={{ ...band(r.from, r.to), background: `hsl(${hue(c.zones[r.zone])} 38% 30% / .92)` }}>{nameOf(maps, c.zones[r.zone], lang)}</span>)}
        {instanceList.map((x, i) => ({ x, i })).filter(({ x }) => (x.to ?? c.duration) > view.from && x.from < view.to).map(({ x, i }) => <button type="button" key={`i${i}`} className="chr-instance" style={band(x.from, x.to ?? c.duration)} title={x.name} onClick={() => { onSeek(x.from); onOpenInstance(i); }}><TypeIcon k={x.detail === "Raid" ? "travel.raid" : "travel.instance"} size={12} /> {x.name}</button>)}
      </div>
      {fights.length > 0 && <div className="chr-combat-lane" role="group" aria-label={lang === "cs" ? "Souboje" : "Fights"}>
        {fights.map(b => {
          const list = b.indices.map(i => c.fights![i]);
          const label = list.length === 1 ? `${list[0].name} · ${clock(list[0].d)}`
            : `${lang === "cs" ? `${list.length} souboje` : `${list.length} fights`} · ${clock(b.end - b.t)}: ${[...new Set(list.map(f => f.name))].slice(0, 4).join(", ")}${list.length > 4 ? "…" : ""}`;
          return <button key={b.indices[0]} type="button" style={{ left: pct(b.t), width: `${(clamp(b.end, view.from, view.to) - clamp(b.t, view.from, view.to)) / span * 100}%` }} title={label} aria-label={label} onClick={() => { onSeek(b.t); onOpenFight(b.indices[0]); }} />;
        })}
      </div>}
      <div ref={track} className="chr-track" role="slider" tabIndex={-1} aria-label="Timeline" aria-valuemin={Math.round(dom.from)} aria-valuemax={Math.round(dom.to)} aria-valuenow={Math.round(time)} aria-valuetext={clock(time)}
        onPointerDown={down} onPointerMove={move} onPointerUp={() => { dragging.current = false; }} onPointerLeave={() => setHover(null)}>
        <i className="chr-fill" style={{ width: pct(time) }} />
        {marks.map((m, i) => <b key={i} className="chr-mark" style={{ left: pct(m.t), ["--mark" as string]: MARK_COLOR[m.key], color: INK[m.key] ?? "#fff" }} title={m.label}><TypeIcon k={m.key} size={12} /></b>)}
        <u className="chr-head" style={{ left: pct(time) }} />
        {hover !== null && <em className="chr-hover" style={{ left: pct(hover) }}>{clock(hover)}</em>}
      </div>
      <canvas ref={bars} className="chr-bars" aria-hidden="true" />
      <div className="chr-tzoom">
        <button type="button" onClick={() => zoomBy(1.8)} disabled={!zoomed} aria-label="Zoom out" title="−">−</button>
        <button type="button" onClick={() => zoomBy(1 / 1.8)} disabled={span <= Math.min(MIN_VIEW, domSpan) + 0.5} aria-label="Zoom in" title="+">+</button>
        <button type="button" onClick={() => setZoom(null)} disabled={!zoomed} aria-label="Fit" title="1:1">⤢</button>
        <div ref={rail} className={`chr-rail${zoomed ? " is-zoomed" : ""}`} onPointerDown={railDown}>
          <span className="chr-thumb" style={{ left: `${((view.from - dom.from) / domSpan) * 100}%`, width: `${(span / domSpan) * 100}%` }}
            onPointerDown={thumbDown} onPointerMove={thumbMove} onPointerUp={() => { grab.current = null; }} />
        </div>
        <small>{zoomed ? `×${(domSpan / span).toFixed(domSpan / span < 10 ? 1 : 0)}` : ""}</small>
      </div>
    </div>
  );
}

/** One collapsible block of the left panel. */
const Block = ({ title, children, open = true }: { title: string; children: ReactNode; open?: boolean }) => (
  <details className="chr-block" open={open}><summary>{title}</summary>{children}</details>
);
function MomentIcon({ event, size = 26 }: { event: ChronicleEvent; size?: number }) {
  if (event.k === "loot" || event.k === "action" && event.a === "item") return <ItemIcon id={event.id} q={event.q} size={size} />;
  if (event.k === "aura" || event.k === "action" && event.a?.startsWith("cast")) return <SpellIcon id={event.id} icon={event.icon} label={event.text} helpful={event.helpful} size={size} />;
  return <IconChip k={typeKey(event)} size={size} />;
}
function AuraGrid({ auras, at }: { auras: readonly Aura[]; at: number }) {
  return <ul className="chr-auras">{auras.map((a, i) => {
    const remaining = a.expiresAt === undefined ? null : Math.max(0, a.expiresAt - at);
    return <li key={`${a.id ?? a.text}-${i}`} className={a.helpful ? "is-helpful" : "is-harmful"} title={`${a.text}${a.stacks && a.stacks > 1 ? ` ×${a.stacks}` : ""}${remaining !== null ? ` · ${clock(remaining)}` : ""}`}>
      <SpellIcon id={a.id} icon={a.icon} label={a.text} helpful={a.helpful} size={30} />
      {a.stacks !== undefined && a.stacks > 1 && <b>{a.stacks}</b>}{remaining !== null && <small>{clock(remaining)}</small>}
    </li>;
  })}</ul>;
}
const ICONS: Record<string, string> = {
  moments: "M5 4h11a2 2 0 0 1 2 2v13H7a2 2 0 0 1-2-2V4zm2 3v10h9V6H7zm1.5 2h6v1.5h-6V9zm0 3h6v1.5h-6V12z",
  days: "M7 2v2H5a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2h-2V2h-2v2H9V2H7zm-2 8h14v9H5v-9z",
  filter: "M3 5h18l-7 8v6l-4-2v-4L3 5z",
  menu: "M4 6h16v2H4V6zm0 5h16v2H4v-2zm0 5h16v2H4v-2z",
  character: "M12 3a4 4 0 1 0 0 8 4 4 0 0 0 0-8zM4 20v-3c0-3 4-4.5 8-4.5s8 1.5 8 4.5v3H4z",
};
const Glyph = ({ name }: { name: string }) => <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true"><path d={ICONS[name]} fill="currentColor" /></svg>;

function Calendar({ days, range, onPick, w, lang }: { days: readonly Day[]; range: { from: number; to: number } | null; onPick: (r: { from: number; to: number } | null) => void; w: Words; lang: string }) {
  const [first, setFirst] = useState<Day | null>(null);
  const byKey = useMemo(() => new Map(days.map(d => [d.key, d])), [days]);
  const peak = Math.max(1, ...days.map(d => d.events));
  const months = useMemo(() => {
    if (!days.length) return [];
    const parse = (k: string) => { const [y, m] = k.split("-").map(Number); return y * 12 + (m - 1); };
    const lo = parse(days[0].key), hi = parse(days[days.length - 1].key);
    const out: { y: number; m: number }[] = [];
    for (let i = hi; i >= Math.max(lo, hi - 5); i--) out.push({ y: Math.floor(i / 12), m: i % 12 });
    return out;
  }, [days]);
  const pick = (d: Day) => {
    if (!first) { setFirst(d); onPick({ from: d.from, to: d.to }); return; }
    onPick({ from: Math.min(first.from, d.from), to: Math.max(first.to, d.to) }); setFirst(null);
  };
  const monthName = (y: number, m: number) => new Date(y, m, 1).toLocaleDateString(lang === "cs" ? "cs-CZ" : "en-GB", { month: "long", year: "numeric" });
  const weekday = (i: number) => new Date(2024, 0, 1 + i).toLocaleDateString(lang === "cs" ? "cs-CZ" : "en-GB", { weekday: "narrow" });
  return (
    <div>
      <div className="chr-pop-actions">
        <button type="button" onClick={() => { const d = days[days.length - 1]; if (d) { setFirst(null); onPick({ from: d.from, to: d.to }); } }}>{w.lastDay}</button>
        <button type="button" onClick={() => { setFirst(null); onPick(null); }}>{w.whole}</button>
      </div>
      {months.map(({ y, m }) => {
        const lead = (new Date(y, m, 1).getDay() + 6) % 7, count = new Date(y, m + 1, 0).getDate();
        return (
          <section key={`${y}-${m}`} className="chr-month">
            <h4>{monthName(y, m)}</h4>
            <div className="chr-grid">
              {Array.from({ length: 7 }, (_, i) => <b key={`h${i}`}>{weekday(i)}</b>)}
              {Array.from({ length: lead }, (_, i) => <i key={`l${i}`} />)}
              {Array.from({ length: count }, (_, i) => {
                const key = `${y}-${String(m + 1).padStart(2, "0")}-${String(i + 1).padStart(2, "0")}`;
                const d = byKey.get(key);
                const inRange = d && range && d.from >= range.from - 1e-6 && d.to <= range.to + 1e-6;
                return d
                  ? <button key={key} type="button" className={inRange ? "is-range" : ""} style={{ ["--heat" as string]: 0.25 + 0.6 * (d.events / peak) }} onClick={() => pick(d)}>{i + 1}</button>
                  : <span key={key}>{i + 1}</span>;
              })}
            </div>
          </section>
        );
      })}
      <p className="chr-muted">{w.pickDays}</p>
    </div>
  );
}

function Filters({ w, counts, sets, minQ, setMinQ, setSets, defaults }: {
  w: Words; counts: Record<string, number>; sets: Record<string, ReadonlySet<string>>; minQ: number; setMinQ: (q: number) => void;
  setSets: (tab: string, next: ReadonlySet<string>) => void; defaults: Record<string, ReadonlySet<string>>;
}) {
  const [tab, setTab] = useState<"timeline" | "map" | "icon">("timeline");
  const set = sets[tab];
  const flip = (keys: string[], on: boolean) => { const next = new Set(set); for (const k of keys) { if (on) next.add(k); else next.delete(k); } setSets(tab, next); };
  return (
    <div>
      <div className="chr-pop-head"><h3>{w.show}</h3><button type="button" onClick={() => { for (const t of ["timeline", "map", "icon"]) setSets(t, defaults[t]); setMinQ(2); }}>{w.reset}</button></div>
      <div className="chr-seg" role="tablist">{(["timeline", "map", "icon"] as const).map(id => <button key={id} type="button" role="tab" aria-selected={tab === id} className={tab === id ? "is-on" : ""} onClick={() => setTab(id)}>{w.tabs[id]}</button>)}</div>
      <p className="chr-muted">{w.tabNote[tab]}</p>
      <div className="chr-quality"><span>{w.itemsList}</span><b>{w.quality[Math.min(4, minQ)]} {minQ > 0 ? w.andBetter : ""}</b></div>
      <div className="chr-seg is-quality">{w.quality.map((name, q) => <button key={name} type="button" className={q === minQ ? "is-on" : ""} style={{ ["--q" as string]: QUALITY[q] }} onClick={() => setMinQ(q)}>{name}</button>)}</div>
      {CATEGORIES.map(cat => {
        const keys = TYPE_KEYS[cat];
        const on = keys.filter(k => set.has(k)).length;
        return (
          <fieldset key={cat} className="chr-group">
            <label className="chr-check is-master"><input type="checkbox" checked={on === keys.length} ref={el => { if (el) el.indeterminate = on > 0 && on < keys.length; }} onChange={event => flip(keys, event.target.checked)} /> {w.cat[cat]}</label>
            <div>{keys.map(k => (
              <label key={k} className="chr-check" style={{ ["--mark" as string]: MARK_COLOR[k] }}>
                <input type="checkbox" checked={set.has(k)} onChange={event => flip([k], event.target.checked)} /> <span className="chr-key"><TypeIcon k={k} size={13} /></span> {w.types[k]} <small>{counts[k] ?? 0}</small>
              </label>
            ))}</div>
          </fieldset>
        );
      })}
    </div>
  );
}

/** The ring of the start screen: the whole journey as coloured stretches, each in the colour of what filled it most. */
function journeyRing(c: Chronicle): { d: string; color: string; opacity: number }[] {
  const n = 96, gap = 0.018, r0 = 70, r1 = 90;
  const bins = Array.from({ length: n }, () => ({ total: 0, by: {} as Record<string, number> }));
  for (const e of c.events) { const b = bins[Math.min(n - 1, Math.floor((e.t / c.duration) * n))]; const cat = categoryOf(e.k); b.total++; b.by[cat] = (b.by[cat] ?? 0) + 1; }
  const peak = Math.max(1, ...bins.map(b => b.total));
  const point = (a: number, r: number) => `${(100 + r * Math.sin(a)).toFixed(2)} ${(100 - r * Math.cos(a)).toFixed(2)}`;
  return bins.map((b, i) => {
    const a0 = (i / n) * Math.PI * 2 + gap, a1 = ((i + 1) / n) * Math.PI * 2 - gap;
    const top = Object.entries(b.by).sort((x, y) => y[1] - x[1])[0];
    return {
      d: `M ${point(a0, r1)} A ${r1} ${r1} 0 0 1 ${point(a1, r1)} L ${point(a1, r0)} A ${r0} ${r0} 0 0 0 ${point(a0, r0)} Z`,
      color: top ? COLORS[top[0] as Category] : "#ffffff", opacity: top ? 0.45 + 0.55 * (b.total / peak) : 0.1,
    };
  });
}
const DEFAULT_SETS = { timeline: new Set(SHOWN_ON_TIMELINE), map: new Set(SHOWN_ON_MAP), icon: new Set(ALL_TYPES.filter(key => key !== "char.state")) } as Record<string, ReadonlySet<string>>;

type Slice = { at: number; to: number };
/**
 * `compact` is the small replay on the home page: it plays by itself (without sound, over and over), shows only the map and the character, and
 * a click expands the same replay, preserving its position. `fullHref` also lets the link open in a new tab.
 */
/** Copies the address of the opened chronicle (#chronicle/<id>) so it can be sent to someone. */
function CopyLink({ label, done }: { label: string; done: string }) {
  const [copied, setCopied] = useState(false);
  const copy = async () => {
    try { await navigator.clipboard.writeText(window.location.href); setCopied(true); setTimeout(() => setCopied(false), 2000); } catch { window.prompt(label, window.location.href); }
  };
  return <button type="button" className="chr-copy-link" onClick={() => void copy()}>{copied ? `✓ ${done}` : `🔗 ${label}`}</button>;
}

function Player({ c, maps, onBack, slice, compact = false, fullHref = "#chronicle", profileId }: { c: Chronicle; maps: readonly MapDefinition[]; onBack: () => void; slice?: Slice | null; compact?: boolean; fullHref?: string; profileId?: string }) {
  // arriving from a highlight: the stretch of the journey it is about, played at once
  const first = useMemo(() => {
    if (!slice) return null;
    const from = journeyTimeOf(c, slice.at), to = journeyTimeOf(c, slice.to);
    return to - from >= 1 ? { from: Math.max(0, from - 5), to: Math.min(c.duration, to + 5) } : null;
  }, [c, slice]);
  const { lang } = useI18n();
  const w = TEXT[lang === "cs" ? "cs" : "en"];
  const index = useMemo(() => buildIndex(c), [c]);
  const counts = useMemo(() => countByCategory(c), [c]);
  const typeCounts = useMemo(() => countByType(c), [c]);
  const days = useMemo(() => daysOf(c), [c]);
  const instanceList = useMemo(() => instances(c), [c]);
  /** the visit a dungeon moment (entering or leaving) belongs to */
  const instanceIndexOf = (e: ChronicleEvent) => instanceList.findIndex(x => e.a === "leave" ? x.to === e.t : x.from === e.t);
  const root = useRef<HTMLDivElement>(null);
  const transport = useRef<HTMLElement>(null);
  const toolbar = useRef<HTMLDivElement>(null);
  const handledFights = useRef(new Set<number>());
  const stage = useRef<StageApi | null>(null);
  const [expanded, setExpanded] = useState(false);
  const mini = compact && !expanded;
  const timeRef = useRef(first?.from ?? 0);
  const [time, setTime] = useState(first?.from ?? 0);
  const [playing, setPlaying] = useState(first !== null || compact);
  const [started, setStarted] = useState(first !== null || compact);
  const [help, setHelp] = useState(false);
  // the small replay shows its stretch in about a minute
  const previewSpeed = Math.round(clamp((first ? first.to - first.from : c.duration) / 60, 1, 1500));
  const [speed, setSpeed] = useState<number>(compact ? previewSpeed : 20);
  const [follow, setFollow] = useState(true);
  const [skipIdle, setSkipIdle] = useState(true);
  const [skipFights, setSkipFightsState] = useState(() => typeof window !== "undefined" && window.localStorage.getItem("evertally.chronicle.skipFights") === "1");
  const setSkipFights = (on: boolean) => { setSkipFightsState(on); try { window.localStorage.setItem("evertally.chronicle.skipFights", on ? "1" : "0"); } catch { /* private mode */ } };
  const [panel, setPanel] = useState(() => typeof window === "undefined" || window.innerWidth > 900);
  const [sheet, setSheet] = useState(() => typeof window === "undefined" || window.innerWidth > 900);
  const [eventQuery, setEventQuery] = useState("");
  const [historyStart, setHistoryStart] = useState<number | null>(null);
  const [pickedEvent, setPickedEvent] = useState<ChronicleEvent | null>(null);
  const [detailExpanded, setDetailExpanded] = useState(false);
  const [pop, setPop] = useState<null | "days" | "filters" | "menu">(null);
  const [range, setRange] = useState<{ from: number; to: number } | null>(first);
  const [filters, setFilters] = useState<ReadonlySet<Category>>(new Set(CATEGORIES));
  const [sets, setSetsState] = useState<Record<string, ReadonlySet<string>>>(DEFAULT_SETS);
  const [minQ, setMinQ] = useState(2);
  const [openFight, setOpenFight] = useState<number | null>(null);
  const [openInstance, setOpenInstance] = useState<number | null>(null);
  const [autoFight, setAutoFight] = useState(false);
  const [soundOn, setSoundOn] = useState(!compact);
  const [volume, setVolume] = useState(0.5);
  const sfx = useRef<Sfx | null>(null);
  const reduced = useMemo(() => typeof window !== "undefined" && window.matchMedia("(prefers-reduced-motion: reduce)").matches, []);
  const dom = useMemo(() => range ?? { from: 0, to: c.duration }, [range, c.duration]);
  const playbackEnd = openFight !== null && c.fights?.[openFight] ? Math.min(dom.to, c.fights[openFight].t + c.fights[openFight].d) : dom.to;
  const showFight = useCallback((i: number, automatic = false) => {
    handledFights.current.add(i);
    setOpenFight(i); setAutoFight(automatic); setPlaying(false);
  }, []);
  const showInstance = useCallback((i: number) => { setOpenInstance(i); setPlaying(false); }, []);
  const closeInstance = useCallback(() => {
    setOpenInstance(null);
    requestAnimationFrame(() => root.current?.focus({ preventScroll: true }));
  }, []);
  const closeFight = useCallback(() => {
    setOpenFight(null); setAutoFight(false);
    requestAnimationFrame(() => root.current?.focus({ preventScroll: true }));
  }, []);
  useEffect(() => {
    if (mini || !root.current || !transport.current || !toolbar.current) return;
    const element = root.current, bar = transport.current, top = toolbar.current;
    const measure = () => {
      const bounds = element.getBoundingClientRect();
      element.style.setProperty("--chr-bar-space", `${Math.ceil(bounds.bottom - bar.getBoundingClientRect().top + 12)}px`);
      element.style.setProperty("--chr-panels-top", `${Math.ceil(top.getBoundingClientRect().bottom - bounds.top + 10)}px`);
    };
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(element, { box: "border-box" }); observer.observe(bar, { box: "border-box" }); observer.observe(top, { box: "border-box" });
    return () => observer.disconnect();
  }, [mini]);

  useEffect(() => {
    if (!playing) return;
    let raf = 0, last = performance.now(), ui = 0;
    const tick = (now: number) => {
      // wall-clock time: only a long pause (a hidden tab) is cut short, so a slow frame rate does not slow the playback
      const dt = Math.min(0.5, (now - last) / 1000); last = now;
      const next = c.events[eventAt(c, timeRef.current) + 1];
      const rate = speed * (skipIdle && next && next.t - timeRef.current > 20 ? 4 : 1);
      const before = timeRef.current;
      const after = Math.min(playbackEnd, before + dt * rate);
      if (!mini && !skipFights && openFight === null && c.fights?.length) {
        for (const i of handledFights.current) if (before < c.fights[i].t) handledFights.current.delete(i);
        const entering = crossedFight(c.fights, before, after, handledFights.current);
        if (entering >= 0) {
          timeRef.current = Math.max(before, c.fights[entering].t); setTime(timeRef.current);
          showFight(entering, true);
          return;
        }
      }
      timeRef.current = after;
      // a few sounds for what just happened (none at high speed or after a jump)
      if (soundOn && sfx.current?.ready && speed <= MAX_SOUND_SPEED && timeRef.current - before < 10) for (const cue of pickCues(eventsBetween(c, before, timeRef.current))) sfx.current.play(cue);
      if (now - ui > 100) { ui = now; setTime(timeRef.current); }
      if (timeRef.current >= playbackEnd) { setTime(playbackEnd); setPlaying(false); return; }
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [playing, speed, skipIdle, skipFights, c, playbackEnd, soundOn, mini, openFight, showFight]);
  useEffect(() => { sfx.current?.setVolume(volume); }, [volume]);
  useEffect(() => () => sfx.current?.close(), []);

  const seek = useCallback((t: number) => { timeRef.current = clamp(t, dom.from, dom.to); setTime(timeRef.current); setPickedEvent(null); }, [dom.from, dom.to]);
  const toggle = useCallback(() => { setStarted(true); setPickedEvent(null); setHistoryStart(null); if (soundOn) { sfx.current ??= new Sfx(); sfx.current.unlock(); sfx.current.setVolume(volume); } if (!playing && timeRef.current >= dom.to) { handledFights.current.clear(); seek(dom.from); } setPlaying(p => !p); }, [playing, dom.to, dom.from, seek, soundOn, volume]);
  useEffect(() => { setHistoryStart(null); setPickedEvent(null); }, [filters, minQ, eventQuery]);
  useEffect(() => {
    // the small replay begins again a moment after it ends
    if (!mini || playing || time < dom.to) return;
    const id = window.setTimeout(() => { seek(dom.from); setPlaying(true); }, 2500);
    return () => window.clearTimeout(id);
  }, [mini, playing, time, dom.from, dom.to, seek]);
  const collapse = useCallback(() => {
    setExpanded(false); setSpeed(previewSpeed); setPlaying(true); setFollow(true);
    setHelp(false); setPop(null); setOpenFight(null); setAutoFight(false); setSoundOn(false);
    sfx.current?.close(); sfx.current = null;
    if (document.fullscreenElement === root.current) void document.exitFullscreen().catch(() => {});
    requestAnimationFrame(() => root.current?.querySelector<HTMLAnchorElement>(".chr-mini-open")?.focus({ preventScroll: true }));
  }, [previewSpeed]);
  useEffect(() => {
    if (!expanded) return;
    const el = root.current;
    const overflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    el?.focus({ preventScroll: true });
    let wasFullscreen = document.fullscreenElement === el;
    const changed = () => {
      if (document.fullscreenElement === el) { wasFullscreen = true; el?.focus({ preventScroll: true }); }
      else if (wasFullscreen) collapse();
    };
    document.addEventListener("fullscreenchange", changed);
    return () => {
      document.body.style.overflow = overflow;
      document.removeEventListener("fullscreenchange", changed);
    };
  }, [expanded, collapse]);
  const expand = () => {
    if (timeRef.current >= dom.to) seek(dom.from);
    setSheet(window.innerWidth > 900); setPanel(window.innerWidth > 900);
    setExpanded(true); setStarted(true); setPlaying(true); setSpeed(20);
    // Browsers without fullscreen support keep the viewport-sized player, with the same close controls.
    if (root.current?.requestFullscreen) void root.current.requestFullscreen().catch(() => {});
  };
  const pickRange = useCallback((r: { from: number; to: number } | null) => { setRange(r); const t = r ? r.from : 0; timeRef.current = t; setTime(t); }, []);
  const onFree = useCallback(() => setFollow(false), []);
  const onApi = useCallback((api: StageApi) => { stage.current = api; }, []);
  const ring = useMemo(() => journeyRing(c), [c]);
  const total = useMemo(() => totalsAt(index, c.duration), [index, c]);

  const totals = totalsAt(index, time);
  const pos = positionAt(c, time);
  const zoneName = pos ? nameOf(maps, c.zones[pos.zone], lang) : "";
  const shown = useMemo(() => {
    const needle = eventQuery.trim().toLocaleLowerCase();
    return c.events.filter(e => filters.has(categoryOf(e.k)) && (e.k !== "loot" || e.q === undefined || e.q >= minQ) && (!needle || `${e.text} ${e.message ?? ""} ${e.speaker ?? ""} ${e.detail ?? ""} ${e.a ?? ""}`.toLocaleLowerCase().includes(needle)));
  }, [c, filters, minQ, eventQuery]);
  const split = useMemo(() => { let lo = 0, hi = shown.length; while (lo < hi) { const mid = (lo + hi) >> 1; if (shown[mid].t <= time) lo = mid + 1; else hi = mid; } return lo; }, [shown, time]);
  const listStart = Math.min(historyStart ?? Math.max(0, split - 12), Math.max(0, shown.length - 32));
  const list = shown.slice(listStart, listStart + 32);
  const currentEvent = pickedEvent ?? (split > 0 ? shown[split - 1] : null);
  const selectEvent = (e: ChronicleEvent) => { seek(e.t); setPickedEvent(e); setPlaying(false); };
  const selectedFight = currentEvent?.f !== undefined ? c.fights?.[currentEvent.f] : undefined;
  const selectedProgress = selectedFight ? fightProgress(selectedFight, time - selectedFight.t) : undefined;
  const selectedFinished = selectedFight && time >= selectedFight.t + selectedFight.d;
  const selectedGroupDamage = selectedFinished && selectedFight.coverage !== "partial" && selectedFight.coverage !== "unavailable" && selectedFight.group?.length && selectedFight.group.every(m => m.dmg !== undefined) ? selectedFight.group.reduce((total, m) => total + m.dmg!, 0) : undefined;
  const stats = statsAt(c, time);
  const skillValues = stats?.skills ? { ...stats.skills } : { ...totals.skills };
  if (stats?.skills) for (const e of eventsBetween(c, stats.t, time)) if (e.k === "skill" && e.n !== undefined) skillValues[e.text] = [e.n, e.max ?? skillValues[e.text]?.[1] ?? e.n];
  const professionSet = new Set(stats?.professions ?? []);
  const skillRows = (rows: [string, [number, number]][]) => rows.map(([name, [v, max]]) => <div key={name} className="chr-skill"><span>{name}</span><b>{v}/{max}</b><i><u style={{ width: `${max > 0 ? clamp(v / max * 100, 0, 100) : 0}%` }} /></i></div>);
  const inside = instanceAt(instanceList, time);
  const insideSummary = inside ? instanceSummary(c, inside, time) : null;
  const insideFights = useMemo(() => inside ? (c.fights ?? []).map((f, index) => ({ f, index })).filter(({ f }) => f.t >= inside.from && f.t <= (inside.to ?? c.duration) && f.t <= time) : [], [c, inside, time]);
  const recentWindow = useMemo(() => {
    const kills = new Map<string, number>(), items = new Map<string, { n: number; q: number; id?: number }>();
    for (const e of eventsBetween(c, selectedFight ? selectedFight.t - 1e-6 : inside ? inside.from - 1e-6 : time - 90, selectedFight ? Math.min(time, selectedFight.t + selectedFight.d) : time)) {
      if (e.k === "kill") kills.set(e.text, (kills.get(e.text) ?? 0) + 1);
      else if (e.k === "loot" && (e.q === undefined || e.q >= minQ)) { const x = items.get(e.text); items.set(e.text, { n: (x?.n ?? 0) + (e.n ?? 1), q: e.q ?? 1, id: e.id }); }
    }
    return { kills: [...kills].sort((a, b) => b[1] - a[1]), items: [...items] };
  }, [c, time, minQ, selectedFight, inside]);
  const liveFight = fightAt(c, time);
  const live = liveFight >= 0 ? c.fights![liveFight] : null;
  const liveNow = live ? fightProgress(live, time - live.t) : null;
  const when = (t: number) => new Date(whenOf(c, t) * 1000).toLocaleString(lang === "cs" ? "cs-CZ" : "en-GB", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit", second: "2-digit" });
  const cls = CLASSES[c.character.classId] as unknown;
  const className = typeof cls === "string" ? cls : (cls as { name?: string } | undefined)?.name ?? "";
  const color = CLASS_COLORS[c.character.classId] ?? "#69ccf0";
  const setSets = (tab: string, next: ReadonlySet<string>) => setSetsState(prev => ({ ...prev, [tab]: next }));

  const key = (event: React.KeyboardEvent) => {
    const target = event.target as HTMLElement;
    if (event.key === "Escape" && openFight === null && openInstance !== null) { event.preventDefault(); event.stopPropagation(); closeInstance(); return; }
    if (event.key === "Escape" && (openFight !== null || pop || help)) { event.preventDefault(); event.stopPropagation(); closeFight(); setPop(null); setHelp(false); return; }
    if (event.key === "Escape" && expanded) { event.preventDefault(); collapse(); return; }
    if (event.key === "Tab" && expanded) {
      const controls = Array.from(root.current?.querySelectorAll<HTMLElement>("button, a[href], input, [tabindex='0']") ?? []).filter(el => !el.hasAttribute("disabled") && el.getClientRects().length);
      const first = controls[0], last = controls[controls.length - 1];
      if (event.shiftKey && (target === first || target === root.current)) { event.preventDefault(); last?.focus(); }
      else if (!event.shiftKey && (target === last || target === root.current)) { event.preventDefault(); first?.focus(); }
      return;
    }
    if (target !== root.current && target.closest("button, a, input, select, textarea")) return;
    const big = event.shiftKey ? 60 : 10;
    if (event.key === "?") setHelp(v => !v);
    else if (event.key === "Escape") { setHelp(false); setPop(null); closeFight(); }
    else if (event.key === " ") { event.preventDefault(); toggle(); }
    else if (event.key === "ArrowRight") { event.preventDefault(); seek(timeRef.current + big); }
    else if (event.key === "ArrowLeft") { event.preventDefault(); seek(timeRef.current - big); }
    else if (event.key === "f") setFollow(v => !v);
    else if (event.key === "m") setPanel(v => !v);
    else if (event.key === "+" || event.key === "=") setSpeed(s => SPEEDS[Math.min(SPEEDS.length - 1, SPEEDS.indexOf(s as (typeof SPEEDS)[number]) + 1)]);
    else if (event.key === "-") setSpeed(s => SPEEDS[Math.max(0, SPEEDS.indexOf(s as (typeof SPEEDS)[number]) - 1)]);
  };
  const fullscreen = () => { if (document.fullscreenElement) void document.exitFullscreen().catch(() => {}); else if (root.current?.requestFullscreen) void root.current.requestFullscreen().catch(() => {}); };
  const stat = (v: string, l: string) => <div key={l}><dt>{v}</dt><dd>{l}</dd></div>;

  if (mini) {
    return (
      <div ref={root} className="chr chr-mini" aria-label={w.title}>
        <Stage c={c} maps={maps} timeRef={timeRef} onApi={onApi} props={{ follow: true, overview: false, reduced, words: w, mapTypes: sets.map, iconTypes: sets.icon, minQ, onFree }} />
        <div className="chr-vignette" aria-hidden="true" />
        {!pos && <p className="chr-position-note">{w.unknownPosition}</p>}
        <div className="chr-mini-info"><b>{c.character.name}</b><span>{zoneName}</span></div>
        <div className="chr-mini-clock">{clock(time)}</div>
        <a className="chr-mini-open" href={fullHref} aria-label={`${w.full}: ${c.character.name}`} onClick={event => {
          if (event.button !== 0 || event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return;
          event.preventDefault(); expand();
        }}><span>⛶ {w.full}</span></a>
      </div>
    );
  }

  return (
    <div ref={root} className={`chr${started ? "" : " is-intro"}${expanded ? " is-expanded" : ""}`} tabIndex={0} onKeyDown={key} role={expanded ? "dialog" : undefined} aria-modal={expanded || undefined} aria-label={w.title}>
      <Stage c={c} maps={maps} timeRef={timeRef} onApi={onApi} props={{ follow, overview: !started, reduced, words: w, mapTypes: sets.map, iconTypes: sets.icon, minQ, onFree }} />
      <div className="chr-vignette" aria-hidden="true" />
      {!pos && started && <p className="chr-position-note">{w.unknownPosition}</p>}
      <div className="chr-top" ref={toolbar}>
        <button type="button" className="chr-btn" onClick={expanded ? collapse : onBack}><Icon name="map" size={15} /> {expanded ? w.backPreview : w.back}</button>
        <span className="chr-spacer" />
        <div className="chr-pill">
          <button type="button" className={sheet ? "is-on" : ""} onClick={() => { setSheet(v => !v); if (!sheet && window.innerWidth <= 900) setPanel(false); }} aria-pressed={sheet} aria-label={w.sheet} title={w.sheet}><Glyph name="character" /></button>
          <button type="button" className={panel ? "is-on" : ""} onClick={() => { setPanel(v => !v); if (!panel && window.innerWidth <= 900) setSheet(false); }} aria-pressed={panel} aria-label={w.moments} title={w.moments}><Glyph name="moments" /></button>
          <button type="button" className={pop === "days" ? "is-on" : ""} onClick={() => setPop(p => (p === "days" ? null : "days"))} aria-pressed={pop === "days"} aria-label={w.days} title={w.days}><Glyph name="days" /></button>
          <button type="button" className={pop === "filters" ? "is-on" : ""} onClick={() => setPop(p => (p === "filters" ? null : "filters"))} aria-pressed={pop === "filters"} aria-label={w.show} title={w.show}><Glyph name="filter" /></button>
          <button type="button" className={pop === "menu" ? "is-on" : ""} onClick={() => setPop(p => (p === "menu" ? null : "menu"))} aria-pressed={pop === "menu"} aria-label={w.menu} title={w.menu}><Glyph name="menu" /></button>
        </div>
      </div>

      {!started && (
        <div className="chr-intro">
          <p className="chr-eyebrow">{w.of}</p>
          <h1 style={{ color: "#d4a574" }}>{c.character.name}</h1>
          <p className="chr-sub">{[className, c.character.guild ? `<${c.character.guild}>` : null, `${w.level} ${total.level}`].filter(Boolean).join(" · ")}</p>
          <p className="chr-when">{w.whenPlayed} {datesText(c.sessions?.[0]?.at ?? c.startedAt, c.startedAt + c.duration, lang)} · {durationText(c.duration, w)}</p>
          <button type="button" className="chr-ring" onClick={toggle} aria-label={w.play}>
            <svg viewBox="0 0 200 200" aria-hidden="true">{ring.map((seg, i) => <path key={i} d={seg.d} fill={seg.color} opacity={seg.opacity} />)}</svg>
            <span><svg viewBox="0 0 24 24" width="34" height="34" aria-hidden="true"><path d="M8 5v14l11-7z" fill="currentColor" /></svg></span>
          </button>
          <p className="chr-big"><b>{clock(c.duration)}</b> {w.played} <b>{total.kills.toLocaleString()}</b> {w.kills} <b>{total.quests}</b> {w.quests} <b>{total.items.toLocaleString()}</b> {w.items} <b>{total.places}</b> {w.places}</p>
          <p className="chr-hint"><kbd>{lang === "cs" ? "Mezerník" : "Space"}</kbd> {w.toPlay} <i /> <kbd>?</kbd> {w.forHelp}</p>
        </div>
      )}
      {help && (
        <div className="chr-help" role="dialog" aria-label={w.helpTitle} onClick={() => setHelp(false)}>
          <div><h3>{w.helpTitle}</h3><dl>{w.keys.map(([k, v]) => <div key={k}><dt><kbd>{k}</kbd></dt><dd>{v}</dd></div>)}</dl></div>
        </div>
      )}

      {pop && (
        <div className="chr-card chr-pop" role="dialog" aria-label={pop === "days" ? w.days : pop === "filters" ? w.show : w.menu}>
          <button type="button" className="chr-x" onClick={() => setPop(null)} aria-label="×">×</button>
          {pop === "days" && <><h3 className="chr-pop-title">{w.days}</h3><Calendar days={days} range={range} onPick={pickRange} w={w} lang={lang} /></>}
          {pop === "filters" && <Filters w={w} counts={typeCounts} sets={sets} minQ={minQ} setMinQ={setMinQ} setSets={setSets} defaults={DEFAULT_SETS} />}
          {pop === "menu" && (
            <div className="chr-menu">
              <h3 className="chr-pop-title">{w.menu}</h3>
              <label className="chr-check"><input type="checkbox" checked={follow} onChange={event => setFollow(event.target.checked)} /> {w.follow}</label>
              <label className="chr-check"><input type="checkbox" checked={skipIdle} onChange={event => setSkipIdle(event.target.checked)} /> {w.idle}</label>
              <label className="chr-check"><input type="checkbox" checked={skipFights} onChange={event => setSkipFights(event.target.checked)} /> {w.skipFights}</label>
              <label className="chr-check"><input type="checkbox" checked={soundOn} onChange={event => setSoundOn(event.target.checked)} /> {w.sound}</label>
              <label className="chr-volume"><span>{w.volume}</span><input type="range" min={0} max={1} step={0.05} value={volume} onChange={event => setVolume(Number(event.target.value))} /></label>
              <div className="chr-quality"><span>{w.speed}</span></div>
              <div className="chr-seg">{SPEEDS.map(s => <button key={s} type="button" className={speed === s ? "is-on" : ""} onClick={() => setSpeed(s)}>{s}×</button>)}</div>
              <button type="button" className="chr-btn" onClick={fullscreen}>⛶ {w.full}</button>
            </div>
          )}
        </div>
      )}

      {sheet && <aside className="chr-card chr-left is-open" aria-label={w.sheet}>
        <header>
          <Portrait classId={c.character.classId} raceId={c.character.raceId} level={totals.level} color={color} />
          <div><h2 style={{ color }}>{c.character.name}</h2>
            <p>{[stats?.race ?? c.character.race ?? (c.character.raceId ? RACES[c.character.raceId] : null), stats?.spec, className, stats?.faction ?? c.character.faction].filter(Boolean).join(" · ")}</p>
            {(stats?.guild ?? c.character.guild) && <p className="chr-guild">&lt;{stats?.guild ?? c.character.guild}&gt;</p>}</div>
        </header>
        <p className="chr-where"><strong>{zoneName}</strong>{pos && <span>{(pos.x * 100).toFixed(1)}, {(pos.y * 100).toFixed(1)}</span>}</p>
        <p className="chr-wallet"><span>{w.wallet}</span><b>{stats?.copper !== undefined ? moneyText(stats.copper) : "–"}</b></p>
        <p className="chr-played">{clock(time)} {w.recorded}{stats?.played !== undefined ? ` · ${w.lifetime}: ${playedText(stats.played + Math.max(0, time - (stats.playedAt ?? stats.t)), w)}` : ""}</p>
        {profileId && <p className="chr-profile-links"><a href={`#character/${encodeURIComponent(profileId)}`}>{w.sheet} ↗</a><a href={`#armory/${encodeURIComponent(profileId)}`}>Armory ↗</a>{!compact && <CopyLink label={w.copyLink} done={w.copied} />}</p>}
        {stats?.roster !== undefined && <Block title={stats.groupType === "raid" ? `${w.raid} · ${stats.roster.length}` : stats.groupType === "party" ? `${w.party} · ${stats.roster.length}` : w.solo} open={stats.roster.length <= 5}>
          <ul className="chr-roster">{stats.roster.map((member, i) => <li key={member.guid ?? `${member.name}-${i}`}>
            <span className="chr-member-icon" style={member.classId ? { backgroundImage: `url(${classIconUrl(member.classId)})` } : undefined} aria-hidden="true" />
            <span><b style={{ color: member.classId ? CLASS_COLORS[member.classId] : undefined }}>{member.name ?? `${w.groupMember} ${i + 1}`}</b><small>{[member.role, member.level !== undefined ? `${w.level} ${member.level}` : null].filter(Boolean).join(" · ")}</small></span>
          </li>)}</ul>
        </Block>}
        {stats?.aurasKnown === false && <p className="chr-muted">{w.aurasUnavailable}</p>}
        {stats?.aurasKnown === true && <>
          {stats.auras?.some(a => a.helpful) && <Block title={w.buffs}><AuraGrid auras={stats.auras.filter(a => a.helpful)} at={whenOf(c, time)} /></Block>}
          {stats.auras?.some(a => !a.helpful) && <Block title={w.debuffs}><AuraGrid auras={stats.auras.filter(a => !a.helpful)} at={whenOf(c, time)} /></Block>}
          {!stats.auras?.length && <p className="chr-muted">{w.noAuras}</p>}
        </>}
        <Block title={w.sofar}>
          <dl className="chr-stats">{stat(String(totals.quests), w.quests)}{stat(String(totals.kills), w.kills)}{stat(totals.xp.toLocaleString(), w.xp)}{stat(moneyText(totals.copper), w.moneyChange)}{stat(String(totals.items), w.items)}{stat(String(totals.places), w.places)}</dl>
          {totals.deaths > 0 && <p className="chr-deaths">{totals.deaths} {w.deaths}</p>}
        </Block>
        {stats && (stats.attrs !== undefined || stats.enh !== undefined || stats.ilvl !== undefined) ? (
          <Block title={w.sheet}>
            {stats.ilvl !== undefined && <p className="chr-ilvl"><span>{w.itemLevel}</span><b>{stats.ilvl}</b></p>}
            {stats.attrs && stats.attrs.length > 0 && <><h4>{w.attributes}</h4><dl className="chr-rows">{stats.attrs.map(([n, v]) => <div key={n}><dt>{n}</dt><dd>{v.toLocaleString()}</dd></div>)}</dl></>}
            {stats.enh && stats.enh.length > 0 && <><h4>{w.enhancements}</h4><dl className="chr-rows">{stats.enh.map(([n, v]) => <div key={n}><dt>{n}</dt><dd>{v}</dd></div>)}</dl></>}
            <p className="chr-muted">{w.notedAt} {clock(stats.sheetAt ?? stats.t)}</p>
          </Block>
        ) : <p className="chr-muted">{w.noSheet}</p>}
        {stats?.equipped !== undefined && <Block title={w.gear} open={false}><div className="chr-gear">{stats.equipped.map(item => <a key={item.slot} href={`#database/items/${item.itemId}`} title={`#${item.itemId} · ${lang === "cs" ? "Pozice" : "Slot"} ${item.slot}`}><ItemIcon id={item.itemId} size={32} /><small>{item.slot}</small></a>)}</div></Block>}
        {Object.keys(skillValues).length > 0 && (
          <Block title={w.skills}>
            {professionSet.size > 0 && <><h4>{w.professions}</h4>{skillRows(Object.entries(skillValues).filter(([name]) => professionSet.has(name)))}</>}
            {Object.keys(skillValues).some(name => !professionSet.has(name)) && <><h4>{w.otherSkills}</h4>{skillRows(Object.entries(skillValues).filter(([name]) => !professionSet.has(name)))}</>}
          </Block>
        )}
      </aside>}

      {inside && insideSummary && (
        <aside className="chr-card chr-instance-card">
          <h3>{w.inInstance} {inside.name}</h3>
          <button type="button" className="chr-btn is-on chr-instance-open" onClick={() => showInstance(instanceList.findIndex(x => x.from === inside.from))}>{w.openInstance}</button>
          {inside.detail && <p className="chr-muted">{inside.detail}</p>}
          <dl className="chr-stats is-row">{stat(String(insideSummary.kills), w.kills)}{stat(String(insideSummary.deaths), w.deaths)}{stat(String(insideSummary.items), w.items)}{stat(moneyText(insideSummary.copper), w.money)}</dl>
          <ul className="chr-bosses">
            {insideFights.map(({ f, index }) => <li key={`fight-${index}`} className={`${f.result === "wipe" || f.result === "loss" ? "is-wipe" : "is-kill"} is-link`}>
              <button type="button" className="chr-instance-fight" onClick={() => showFight(index)}><strong>{f.name}</strong><span>{clock(Math.min(f.d, Math.max(0, time - f.t)))} · {time < f.t + f.d ? w.inFight : w.resultNames[f.result] ?? f.result}</span></button>
            </li>)}
            {insideSummary.bosses.filter(b => b.f === undefined).map((b, i) => (
              <li key={i} className={`${b.a === "wipe" || b.a === "loss" ? "is-wipe" : "is-kill"}${b.f !== undefined ? " is-link" : ""}`} onClick={b.f !== undefined ? () => showFight(b.f!) : undefined}>
                <strong>{b.text}{b.n && b.n > 1 ? ` · ${w.pull} ${b.n}` : ""}</strong>
                <span>{b.k === "pvp" ? (b.a === "win" ? w.win : w.loss) : b.a === "wipe" ? w.wiped : w.killedIn} {clock(b.d ?? 0)}</span>
                {b.detail && <small>{b.detail}</small>}
              </li>
            ))}
          </ul>
        </aside>
      )}

      {panel && (
        <aside className="chr-card chr-right">
          <div className="chr-history-tools">
          <label className="chr-event-search"><span>{w.searchMoments}</span><input type="search" value={eventQuery} onChange={event => setEventQuery(event.target.value)} /></label>
          <div className="chr-chips" role="group" aria-label={w.moments}>
            {CATEGORIES.map(cat => (
              <button key={cat} type="button" className={filters.has(cat) ? "is-on" : ""} aria-pressed={filters.has(cat)} style={{ ["--chip" as string]: COLORS[cat] }}
                onClick={() => setFilters(prev => { const next = new Set(prev); if (next.has(cat)) next.delete(cat); else next.add(cat); return next; })}>{w.cat[cat]} <b>{counts[cat]}</b></button>
            ))}
          </div>
          <div className="chr-moment-pages"><button type="button" disabled={listStart === 0} onClick={() => setHistoryStart(Math.max(0, listStart - 32))}>{w.older}</button><button type="button" onClick={() => { setHistoryStart(null); setEventQuery(""); }}>{w.followMoments}</button><button type="button" disabled={listStart + list.length >= shown.length} onClick={() => setHistoryStart(listStart + 32)}>{w.newer}</button></div>
          </div>
          <div className="chr-history-list" aria-label={w.moments}>
          {listStart > 0 && <p className="chr-muted">{listStart} {w.earlier}</p>}
          <ol className="chr-moments">
            {list.length === 0 && <li className="chr-muted">{w.none}</li>}
            {list.map((e, i) => (
              <li key={`${listStart + i}-${e.t}-${e.k}`} className={e === currentEvent ? "is-current" : ""} style={{ ["--chip" as string]: COLORS[categoryOf(e.k)] }}>
                <button type="button" className="chr-moment-main" onClick={() => selectEvent(e)} aria-current={e === currentEvent ? "true" : undefined}><time>{clock(e.t)}</time><MomentIcon event={e} /><span className="chr-moment-copy"><b>{e.k === "speech" ? `${e.speaker ?? e.text}: ${(e.message ?? "").slice(0,150)}` : popup(e, w).text}</b>{(e.actor || e.detail) && <small>{[e.actor, e.detail].filter(Boolean).join(" · ")}</small>}</span></button>
                {e.f !== undefined && <button type="button" className="chr-open" onClick={() => { selectEvent(e); showFight(e.f!); }} aria-label={`${w.openFight}: ${c.fights?.[e.f]?.name ?? e.text}`} title={w.openFight}>›</button>}
                {e.k === "dungeon" && e.f === undefined && instanceIndexOf(e) >= 0 && <button type="button" className="chr-open" onClick={() => { selectEvent(e); showInstance(instanceIndexOf(e)); }} aria-label={`${w.openInstance}: ${e.text}`} title={w.openInstance}>›</button>}
              </li>
            ))}
          </ol>
          {shown.length - listStart - list.length > 0 && <p className="chr-muted">{shown.length - listStart - list.length} {w.later}</p>}
          </div>
          <div className="chr-selection" role="region" aria-label={w.what}>
          {currentEvent && (
            <section className="chr-detail">
              <div className="chr-detail-head"><MomentIcon event={currentEvent} size={38} /><h3>{currentEvent.k === "speech" ? `${currentEvent.speaker ?? currentEvent.text} ${w.say}` : popup(currentEvent, w).text}</h3></div>
              <p className="chr-muted">{clock(currentEvent.t)} {w.into} · {when(currentEvent.t)}{c.sessions?.length ? ` · ${w.session} ${sessionAt(c, currentEvent.t) + 1}` : ""}</p>
              {currentEvent.message && <blockquote className="chr-dialogue">{currentEvent.message}</blockquote>}
              {currentEvent.f !== undefined && <button type="button" className="chr-btn is-on" onClick={() => showFight(currentEvent.f!)}>{w.openFight}</button>}
              {currentEvent.k === "dungeon" && instanceIndexOf(currentEvent) >= 0 && <button type="button" className="chr-btn is-on" onClick={() => showInstance(instanceIndexOf(currentEvent))}>{w.openInstance}</button>}
              {currentEvent.k === "kill" && currentEvent.f === undefined && <p className="chr-muted">{lang === "cs" ? "Tento záznam obsahuje zabití a zkušenosti. Průběh ani začátek souboje se tehdy nezaznamenal." : "This record contains the kill and experience. The course and start of the fight were not recorded."}</p>}
              <h4>{w.what}</h4>
              <dl>
                <div><dt>{w.type}</dt><dd>{w.kind[currentEvent.k]}{currentEvent.a ? ` · ${currentEvent.a}` : ""}</dd></div>
                {currentEvent.actor && <div><dt>{lang === "cs" ? "Kdo" : "Who"}</dt><dd>{currentEvent.actor}</dd></div>}
                {currentEvent.target && <div><dt>{lang === "cs" ? "Na koho" : "Target"}</dt><dd>{currentEvent.target}</dd></div>}
                {currentEvent.zone !== undefined && <div><dt>{w.where}</dt><dd>{nameOf(maps, c.zones[currentEvent.zone], lang)}{currentEvent.x !== undefined && currentEvent.y !== undefined ? ` ${(currentEvent.x * 100).toFixed(1)}, ${(currentEvent.y * 100).toFixed(1)}` : ""}</dd></div>}
                {currentEvent.xp ? <div><dt>{w.reward}</dt><dd>+{currentEvent.xp} XP</dd></div> : null}
                {currentEvent.k === "loot" && currentEvent.n ? <div><dt>{w.amount}</dt><dd>×{currentEvent.n}</dd></div> : null}
                {currentEvent.d !== undefined ? <div><dt>{w.fight}</dt><dd>{clock(currentEvent.d)}{currentEvent.k === "boss" && currentEvent.n ? ` · ${w.attempt} ${currentEvent.n}` : ""}</dd></div> : null}
                {currentEvent.k === "aura" && <><div><dt>{w.type}</dt><dd>{currentEvent.helpful ? w.buffs : w.debuffs}</dd></div>{currentEvent.stacks !== undefined && <div><dt>{w.amount}</dt><dd>{currentEvent.stacks}</dd></div>}</>}
                {selectedFight && <>
                  <div><dt>{w.difficulty}</dt><dd>{selectedFight.difficulty ?? "–"}</dd></div><div><dt>{w.groupSize}</dt><dd>{selectedFight.size ?? selectedFight.group?.length ?? "–"}</dd></div>
                  <div><dt>{w.outcome}</dt><dd>{selectedFinished ? w.resultNames[selectedFight.result] : w.inFight}</dd></div>
                  <div><dt>{w.damage}</dt><dd>{num(selectedProgress?.dmg)}</dd></div><div><dt>{w.healing}</dt><dd>{num(selectedProgress?.heal)}</dd></div><div><dt>{w.taken}</dt><dd>{num(selectedProgress?.taken)}</dd></div>
                  {selectedGroupDamage !== undefined && selectedGroupDamage > 0 && <><div><dt>{w.groupDamage}</dt><dd>{num(selectedGroupDamage)}</dd></div>{selectedFight.me.dmg !== undefined && <div><dt>{w.damage}</dt><dd>{(selectedFight.me.dmg / selectedGroupDamage * 100).toFixed(1)} % {w.groupShare}</dd></div>}</>}
                  <div><dt>{w.source}</dt><dd>{selectedFight.source === "damage_meter" ? (lang === "cs" ? "Herní měřič po souboji" : "Game meter after combat") : selectedFight.source ?? w.notRecorded}</dd></div>
                </>}
                {currentEvent.detail ? <div><dt>{w.what}</dt><dd>{currentEvent.detail}</dd></div> : null}
              </dl>
              {selectedFight && selectedFinished && selectedFight.me.dealt.length > 0 && <><h4>{w.bySpell}</h4><ul className="chr-direct-spells">{(detailExpanded ? selectedFight.me.dealt : selectedFight.me.dealt.slice(0,6)).map((row,i) => <li key={`${row.id ?? row.name}-${i}`}><SpellIcon id={row.id} label={row.name} size={20} /><span>{row.name}{row.casts !== undefined && <small> ×{row.casts}</small>}</span><b>{num(row.total)}</b></li>)}</ul>{selectedFight.me.dealt.length > 6 && <button type="button" className="chr-btn" onClick={() => setDetailExpanded(v=>!v)}>{detailExpanded?w.less:w.more}</button>}</>}
              {currentEvent.summary && <><h4>{w.groupTotal}</h4><dl><div><dt>{w.damage}</dt><dd>{num(currentEvent.summary.me.dmg)}</dd></div><div><dt>{w.healing}</dt><dd>{num(currentEvent.summary.me.heal)}</dd></div><div><dt>{w.taken}</dt><dd>{num(currentEvent.summary.me.taken)}</dd></div></dl>
                {currentEvent.summary.group?.map((member, i) => <p className="chr-summary-member" key={`${member.name}-${i}`}><b>{member.name}</b><span>{w.damage} {num(member.dmg)} · {w.healing} {num(member.heal)} · {w.taken} {num(member.taken)}</span></p>)}
              </>}
            </section>
          )}
          {(recentWindow.kills.length > 0 || recentWindow.items.length > 0) && (
            <><section className="chr-recent">
              <div><h4>{w.killsList}</h4>{(detailExpanded?recentWindow.kills:recentWindow.kills.slice(0,8)).map(([n, k]) => <p key={n}><span title={n}>{n}</span>{k > 1 && <b>×{k}</b>}</p>)}</div>
              <div><h4>{w.itemsList}</h4>{(detailExpanded?recentWindow.items:recentWindow.items.slice(-8)).map(([n, x]) => <p key={n} style={{ color: QUALITY[x.q] }}><ItemIcon id={x.id} q={x.q} size={20} /><span title={n}>{x.id ? <a href={`#database/items/${x.id}`}>{n}</a> : n}</span>{x.n > 1 && <b>×{x.n}</b>}</p>)}</div>
            </section>{(recentWindow.kills.length>8||recentWindow.items.length>8) && <button type="button" className="chr-btn" onClick={()=>setDetailExpanded(v=>!v)}>{detailExpanded?w.less:w.more}</button>}</>
          )}
          </div>
        </aside>
      )}

      {live && liveNow && openFight === null && (
        <button type="button" className={`chr-card chr-hud${sheet || panel ? " has-side-panel" : ""}`} onClick={() => showFight(liveFight)} aria-label={`${w.inFight}: ${live.name}`}>
          <IconChip k={live.kind === "pvp" ? "combat.pvp" : live.kind === "combat" ? "combat.fight" : "combat.boss"} size={32} />
          <span className="chr-hud-name"><b>{live.name}</b><small>{w.inFight} · {clock(time - live.t)} / {clock(live.d)}</small></span>
          <span className="chr-hud-num" style={{ ["--s" as string]: "#ff9a3c" }}><b>{num(liveNow.dmg)}</b><small>{w.damage}</small></span>
          <span className="chr-hud-num" style={{ ["--s" as string]: "#5fd08f" }}><b>{num(liveNow.heal)}</b><small>{w.healing}</small></span>
          <span className="chr-hud-num" style={{ ["--s" as string]: "#e2786a" }}><b>{num(liveNow.taken)}</b><small>{w.taken}</small></span>
        </button>
      )}
      {openInstance !== null && instanceList[openInstance] && (
        <InstanceWindow key={openInstance} c={c} inst={instanceList[openInstance]} index={openInstance} count={instanceList.length} lang={lang}
          onClose={closeInstance} onStep={delta => setOpenInstance(clamp(openInstance + delta, 0, instanceList.length - 1))} onOpenFight={showFight} onSeek={seek} />
      )}
      {openFight !== null && c.fights?.[openFight] && (
        <FightWindow key={openFight} fight={c.fights[openFight]} index={openFight} count={c.fights.length} c={c} lang={lang} time={time} autoPlay={autoFight}
          onClose={closeFight} onContinue={() => { seek(c.fights![openFight].t + c.fights![openFight].d); closeFight(); setPlaying(true); }} onStep={delta => showFight(clamp(openFight + delta, 0, c.fights!.length - 1))} onSeek={seek} />
      )}

      <div className={`chr-zoom${panel ? " is-shifted" : ""}`}>
        <button type="button" onClick={() => stage.current?.zoom(1.5)} aria-label={w.zoomIn}>+</button>
        <button type="button" onClick={() => stage.current?.zoom(1 / 1.5)} aria-label={w.zoomOut}>−</button>
        <button type="button" className={follow ? "is-on" : ""} onClick={() => setFollow(true)} aria-label={w.centre} title={w.centre}>
          <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true"><circle cx="12" cy="12" r="3.2" fill="none" stroke="currentColor" strokeWidth="2" /><path d="M12 2v5M12 17v5M2 12h5M17 12h5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" /></svg>
        </button>
      </div>

      <footer className="chr-bar" ref={transport} inert={openFight !== null || openInstance !== null}>
        <button type="button" className="chr-play" onClick={toggle} aria-label={playing ? w.pause : time >= dom.to ? w.replay : w.play}>
          {playing ? <svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true"><rect x="6" y="5" width="4" height="14" rx="1" fill="currentColor" /><rect x="14" y="5" width="4" height="14" rx="1" fill="currentColor" /></svg>
            : <svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true"><path d="M8 5v14l11-7z" fill="currentColor" /></svg>}
        </button>
        <Timeline c={c} maps={maps} time={time} dom={dom} types={sets.timeline} minQ={minQ} instanceList={instanceList} onSeek={seek} onOpenFight={showFight} onOpenInstance={showInstance} lang={lang} />
        <div className="chr-clock"><b>{clock(time)} / {clock(c.duration)}</b><span>{when(time)}</span></div>
        <button type="button" className={`chr-speed chr-sound${soundOn ? "" : " is-off"}`} aria-pressed={soundOn} aria-label={w.sound} title={w.sound}
          onClick={() => { if (!soundOn) { sfx.current ??= new Sfx(); sfx.current.unlock(); sfx.current.setVolume(volume); } setSoundOn(v => !v); }}>
          <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true"><path d="M4 9.5v5h3.5L12 19V5L7.5 9.5H4z" fill="currentColor" />{soundOn ? <path d="M15 8.5a4.5 4.5 0 0 1 0 7M17.5 6a8 8 0 0 1 0 12" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" /> : <path d="M15.5 9.5l5 5m0-5l-5 5" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" />}</svg>
        </button>
        <button type="button" className="chr-speed" onClick={() => setSpeed(s => SPEEDS[(SPEEDS.indexOf(s as (typeof SPEEDS)[number]) + 1) % SPEEDS.length])} aria-label={w.speed}>{speed}×</button>
      </footer>
    </div>
  );
}

type Listing = { profileId: string; name: string; realm: string | null; classId: number | null; level: number | null; shared: boolean; own: boolean; summary: { seconds: number; sessions: number; from: number; to: number; events: number; zones: number } };
/** "14 h 58 min", "42 min": how long a recording is, written out. */
function durationText(seconds: number, w: Pick<Words, "hours" | "minutes">): string {
  const minutes = Math.max(1, Math.round(seconds / 60));
  return minutes >= 60 ? `${Math.floor(minutes / 60)} ${w.hours} ${String(minutes % 60).padStart(2, "0")} ${w.minutes}` : `${minutes} ${w.minutes}`;
}
function playedText(seconds: number, w: Pick<Words, "hours" | "minutes">): string {
  const minutes = Math.floor(Math.max(0, seconds) / 60), days = Math.floor(minutes / 1440), hours = Math.floor(minutes / 60) % 24;
  return `${days ? `${days} d ` : ""}${days || hours ? `${hours} ${w.hours} ` : ""}${minutes % 60} ${w.minutes}`;
}
/** "3. 8. – 9. 8. 2026" or the one day. */
function datesText(from: number, to: number, lang: string): string {
  const locale = lang === "cs" ? "cs-CZ" : "en-GB";
  const day = (t: number) => new Date(t * 1000).toLocaleDateString(locale, { day: "numeric", month: "numeric", year: "numeric" });
  const a = day(from), b = day(to);
  return a === b ? a : `${a} – ${b}`;
}

/** The small replay of the home page: plays on its own, a click opens the full replay. */
export function MiniPlayer({ c, maps, slice, fullHref, profileId }: { c: Chronicle; maps: readonly MapDefinition[]; slice?: { at: number; to: number } | null; fullHref: string; profileId?: string }) {
  return <Player key={`${c.startedAt}-${c.duration}-${slice?.at ?? 0}`} c={c} maps={maps} onBack={() => {}} slice={slice} compact fullHref={fullHref} profileId={profileId} />;
}

/** The page: the public chronicles, newest played first, each with how long it is and when it was played; or a recording file. `#chronicle/<id>` opens one; `#chronicle/demo` plays a sample. */
export function ChronicleView({ route }: { route: string; user?: User | null; signIn?: string | null }) {
  const { lang } = useI18n();
  const w = TEXT[lang === "cs" ? "cs" : "en"];
  const maps = useMaps();
  const [target, query = ""] = route.split("?");
  const params = new URLSearchParams(query);
  const sliceAt = Number(params.get("at")), sliceTo = Number(params.get("to")), linkDays = Number(params.get("days")) || 0;
  const demoRequested = target === "demo";
  const [opened, setOpened] = useState<Chronicle | null>(null);
  const [slice, setSlice] = useState<Slice | null>(null);
  const [problem, setProblem] = useState("");
  const [over, setOver] = useState(false);
  const [days, setDays] = useState(0);   // 0: the whole history
  const [busy, setBusy] = useState<string | null>(null);
  const [empty, setEmpty] = useState(false);
  const list = useApi<{ chronicles?: Listing[] }>(`/api/chronicles?days=${days}`);
  const demo = useMemo(() => (demoRequested ? demoChronicle() : null), [demoRequested]);
  const chronicle = opened ?? demo;

  const read = async (file: File | undefined) => {
    if (!file) return;
    if (file.size > 40_000_000) { setProblem(w.bad); return; }
    try {
      const parsed = parseChronicle(JSON.parse(await file.text()));
      if (parsed) { setOpened(parsed); setProblem(""); } else setProblem(w.bad);
    } catch { setProblem(w.unreadable); }
  };
  const load = async (profile: string, span = days, part: Slice | null = null) => {
    setBusy(profile); setProblem(""); setEmpty(false); setSlice(part);
    try {
      const data = await api<{ chronicle: unknown }>(`/api/chronicle?profile=${encodeURIComponent(profile)}&days=${span}`);
      const parsed = data.chronicle ? parseChronicle(data.chronicle) : null;
      if (parsed) setOpened(parsed); else setEmpty(true);
    } catch { setProblem(w.failed); } finally { setBusy(null); }
  };
  // a link to one chronicle (#chronicle/<id>) opens it straight away
  useEffect(() => {
    if (target && target !== "demo") void load(target, linkDays, sliceAt > 0 && sliceTo > sliceAt ? { at: sliceAt, to: sliceTo } : null);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [target, sliceAt, sliceTo, linkDays]);

  const chronicles = useMemo(() => list.data?.chronicles ?? [], [list.data]);
  const paged = usePaged(chronicles, c => [c.name, c.realm].filter(Boolean).join(" "));
  if (chronicle) {
    if (!maps.data) return <div className="chr-start"><p className="muted">{w.loading}</p></div>;
    return <Player key={`${chronicle.startedAt}-${chronicle.duration}-${slice?.at ?? 0}`} c={chronicle} maps={maps.data} slice={slice} profileId={target && target !== "demo" ? target : undefined} onBack={() => { setOpened(null); setSlice(null); window.location.hash = "chronicle"; }} />;
  }
  return (
    <div className="chr-start page-column">
      <h1>{w.heading}</h1>
      <p className="chr-lead">{w.lead}</p>
      <section className="chr-pick">
        <div className="chr-periods" role="group" aria-label={w.period}>
          <span>{w.period}</span>
          {[0, 30, 14, 7].map(n => <button key={n} type="button" className={days === n ? "is-on" : ""} aria-pressed={days === n} onClick={() => { setDays(n); setEmpty(false); }}>{n === 0 ? w.allTime : `${n} ${w.periodDays}`}</button>)}
        </div>
        <h2>{w.publicHead}</h2>
        {list.data && !chronicles.length && <p className="muted">{w.noPublic}</p>}
        {chronicles.length > 0 && <PagedSearch value={paged.query} onChange={paged.setQuery} placeholder={w.searchList} />}
        {chronicles.length > 0 && !paged.total && <p className="muted">{w.noMatch}</p>}
        <ul className="chr-chars">
          {paged.rows.map(c => (
            <li key={c.profileId}>
              <span className="chr-char-icon" style={c.classId ? { backgroundImage: `url(${classIconUrl(c.classId)})` } : undefined} aria-hidden="true" />
              <span>
                <b>{c.name}</b>{c.realm ? <small> · {c.realm}</small> : null}{c.level ? <small> · {w.level} {c.level}</small> : null}{!c.shared && <small className="chr-tag"> · {w.privateTag}</small>}
                <small className="chr-meta"><b>{durationText(c.summary.seconds, w)}</b> · {c.summary.sessions} {w.sessionsOf[c.summary.sessions === 1 ? 0 : 1]} · {datesText(c.summary.from, c.summary.to, lang)} · {c.summary.events.toLocaleString()} {w.eventsOf}</small>
              </span>
              <button type="button" className="btn btn-primary btn-sm" disabled={busy !== null} onClick={() => { window.location.hash = `chronicle/${encodeURIComponent(c.profileId)}${days ? `?days=${days}` : ""}`; }}>{busy === c.profileId ? w.composing : w.play}</button>
            </li>
          ))}
        </ul>
        <Pager page={paged.page} pages={paged.pages} onPage={paged.setPage} previous={w.previous} next={w.next} label={w.pagesLabel} />
        {empty && <div className="pp-notice" role="status"><b>{w.emptyTitle}</b><br />{w.howto}</div>}
      </section>
      {problem && <p className="pp-notice" role="alert">{problem}</p>}
      <div className={`chr-drop${over ? " is-over" : ""}`}
        onDragOver={event => { event.preventDefault(); setOver(true); }} onDragLeave={() => setOver(false)}
        onDrop={event => { event.preventDefault(); setOver(false); void read(event.dataTransfer.files[0]); }}>
        <label className="btn btn-ghost">{w.open}<input type="file" accept="application/json,.json" hidden onChange={event => void read(event.target.files?.[0])} /></label>
        <span className="muted small">{w.drop}</span>
        <a className="chr-sample" href="#chronicle/demo">{w.sample}</a>
      </div>
    </div>
  );
}

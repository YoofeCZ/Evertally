"use client";
/* eslint-disable @next/next/no-img-element -- small bundled icons with explicit dimensions and fallback */
import { useEffect, useId, useState } from "react";
import type { Character, Run } from "./types";
import { CLASSES, RACES, duration } from "./data";
import { useI18n } from "@/lib/i18n";
import { useApi } from "./api";

/** Bundled art only; failures become a fixed-size fallback instead of a broken image. */
export function GameIcon({ group, id, label, size = 26 }: { group: "classes" | "races" | "items"; id?: number | string | null; label: string; size?: number }) {
  const [failed, setFailed] = useState("");
  const valid = typeof id === "number" ? Number.isSafeInteger(id) && id > 0 : typeof id === "string" && /^[1-9]\d*$/.test(id);
  const src = valid ? `/media/identity/${group}/${id}.${group === "items" ? "jpg" : "png"}` : "";
  return <span className={`game-icon game-icon-${group}`} style={{ width: size, height: size }} role="img" aria-label={label} title={label}>
    {src && failed !== src ? <img src={src} alt="" width={size} height={size} loading="lazy" decoding="async" onError={() => setFailed(src)} /> : <span aria-hidden="true">?</span>}
  </span>;
}

export function CharacterIcons({ character, size = 22 }: { character?: Partial<Character> | null; size?: number }) {
  return <span className="character-icons"><GameIcon group="classes" id={character?.classId} size={size} label={CLASSES[character?.classId ?? 0] ?? "Unknown class"} /><GameIcon group="races" id={character?.raceId} size={size} label={RACES[character?.raceId ?? 0] ?? "Unknown race"} /></span>;
}

/** The whole name as the game writes it: Name-Realm. A character without a known realm keeps just the name. */
export function fullName(character?: Partial<Character> | null): string {
  const name = character?.name?.trim();
  if (!name) return "";
  const realm = character?.realm?.trim();
  return realm ? `${name}-${realm}` : name;
}

export function CharacterBadge({ character, unnamed }: { character?: Character | null; unnamed: string }) {
  return <span className="character-badge"><CharacterIcons character={character} /><span><CharacterName character={character} unnamed={unnamed} /><small>{[CLASSES[character?.classId ?? 0], RACES[character?.raceId ?? 0], character?.level].filter(Boolean).join(" · ")}</small></span></span>;
}

type ProfileResult = { profile: Character; zones: { mapId: number; mapName?: string; visits: number; lastVisited?: number }[]; runs: Run[] };

/** Names open a bounded profile with visited zones, never player coordinates. */
export function CharacterName({ character, unnamed }: { character?: Character | null; unnamed: string }) {
  const { lang, date } = useI18n();
  const cs = lang === "cs", region = useId();
  const [open, setOpen] = useState(false);
  const [position, setPosition] = useState({ left: 20, top: 90 });
  useEffect(() => {
    if (!open) return;
    const dismiss = (event: KeyboardEvent) => { if (event.key === "Escape") setOpen(false); };
    window.addEventListener("keydown", dismiss);
    return () => window.removeEventListener("keydown", dismiss);
  }, [open]);
  const data = useApi<ProfileResult>(open && character?.id ? `/api/profiles/${encodeURIComponent(character.id)}` : null);
  if (!character?.name || !character.id) return <span>{fullName(character) || unnamed}</span>;
  const zones = Array.isArray(data.data?.zones) ? data.data.zones : [];
  const runs = Array.isArray(data.data?.runs) ? data.data.runs : [];
  return <span className="profile-anchor"><button type="button" className="profile-name" aria-expanded={open} aria-controls={region} onClick={event => { const rect = event.currentTarget.getBoundingClientRect(); setPosition({ left: Math.max(15, Math.min(rect.left, window.innerWidth - 335)), top: Math.max(15, rect.bottom + 340 > window.innerHeight ? rect.top - 340 : rect.bottom + 8) }); setOpen(!open); }}>{fullName(character)}</button>
    {open && <span className="profile-preview" style={position} role="region" id={region} aria-label={cs ? "Profil postavy" : "Character profile"}>
      <span className="profile-heading"><strong>{fullName(character)}</strong><button type="button" className="profile-close" onClick={() => setOpen(false)} aria-label={cs ? "Zavřít profil" : "Close profile"}>×</button></span>
      {data.loading ? <span>{cs ? "Načítání profilu…" : "Loading profile…"}</span> : data.error ? <span>{cs ? "Profil není veřejný nebo není dostupný." : "This profile is private or unavailable."}</span> : <>
        <span className="profile-section-title">{cs ? "Navštívené oblasti" : "Visited zones"} · {zones.length}</span>
        {zones.length ? zones.slice(0, 12).map(zone => <span className="profile-entry" key={zone.mapId}><span>{zone.mapName || `#${zone.mapId}`}<small>{date(zone.lastVisited)}</small></span><span>{zone.visits}×</span></span>) : <span>{cs ? "Zatím žádné sdílené návštěvy oblastí." : "No shared zone visits yet."}</span>}
        {zones.length > 12 && <small>+{zones.length - 12}</small>}
        <span className="profile-section-title">{cs ? "Zaznamenané výpravy" : "Recorded runs"} · {runs.length}</span>
        {runs.slice(0, 5).map(run => <span className="profile-entry" key={run.id}><span>{run.name}</span><span className="mono">{duration(run.durationMs)}</span></span>)}
        <a className="profile-armory" href={`#armory/${encodeURIComponent(character.id)}`}>{cs ? "Armory: výbava, statistiky, talenty, profese, tašky" : "Armory: gear, stats, talents, professions, bags"}</a>
        <small className="profile-privacy">{cs ? "Pouze navštívené oblasti. Přesná poloha ani živé sledování hráče se nezobrazuje." : "Visited zones only. No exact player location or live tracking is displayed."}</small>
      </>}
    </span>}
  </span>;
}

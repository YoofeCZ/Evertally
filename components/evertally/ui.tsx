"use client";
import { Fragment, useState, type ReactNode } from "react";
import { useI18n } from "@/lib/i18n";
import type { Run } from "./types";
import { duration } from "./data";
import { RunDetails } from "./Details";
import { CharacterBadge } from "./Identity";
export { CLASSES, RACES, duration } from "./data";

const ICONS: Record<string, ReactNode> = {
  sword: <path d="M14.5 3H21v6.5L9 21.5 2.5 15 14.5 3ZM11 7l6 6M2.5 21.5l4-4" />,
  trophy: <path d="M7 4h10v5a5 5 0 0 1-10 0V4Zm0 2H3v1.5C3 10 5 11 7 11m10-5h4v1.5c0 2.5-2 3.5-4 3.5M12 14v5m-4 2h8" />,
  map: <path d="m3 6 6-2.5 6 2.5 6-2.5v14.5L15 20.5 9 18l-6 2.5V6Zm6-2.5V18m6-12v14.5" />,
  sync: <path d="M20 8a8 8 0 0 0-14.3-2.5L3 8m0-5v5h5m12 8a8 8 0 0 1-14.3 2.5L3 16m18 5v-5h-5" />,
  user: <path d="M12 12a4.5 4.5 0 1 0 0-9 4.5 4.5 0 0 0 0 9Zm-8 9a8 8 0 0 1 16 0" />,
  compass: <path d="M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18Zm3.5-12.5-2 5-5 2 2-5 5-2Z" />,
  arrow: <path d="M5 12h14m-6-6 6 6-6 6" />,
  download: <path d="M12 4v11m-4.5-4.5L12 15l4.5-4.5M4 17v3h16v-3" />,
  upload: <path d="M12 16V5m-4.5 4.5L12 5l4.5 4.5M4 17v3h16v-3" />,
  check: <path d="m5 12.5 4.5 4.5L19 7.5" />,
  close: <path d="m6 6 12 12M18 6 6 18" />,
  lock: <path d="M6 10h12v10H6V10Zm2.5 0V7.5a3.5 3.5 0 0 1 7 0V10" />,
  globe: <path d="M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18Zm-9-9h18M12 3c3 3.5 3 14.5 0 18-3-3.5-3-14.5 0-18Z" />,
  shield: <path d="M12 3 4.5 6v5.5C4.5 16 8 19.5 12 21c4-1.5 7.5-5 7.5-9.5V6L12 3Zm-3.5 9 2.5 2.5 4.5-5" />,
  laptop: <path d="M5 5h14v10H5V5Zm-3 13h20" />,
  book: <path d="M12 6.5C9.5 4.8 6.5 4.5 3.5 5v14c3-.5 6-.2 8.5 1.5 2.5-1.7 5.5-2 8.5-1.5V5c-3-.5-6-.2-8.5 1.5Zm0 0v14" />,
  anvil: <path d="M3 7h18l-4 5h-4v4h4v3H7v-3h3v-4H7L3 7Z" />,
  route: <path d="M6 19a2 2 0 1 0 0-4 2 2 0 0 0 0 4Zm12-10a2 2 0 1 0 0-4 2 2 0 0 0 0 4ZM8 17h6.5a3.5 3.5 0 0 0 0-7h-5a3.5 3.5 0 0 1 0-7H16" />,
  guild: <path d="M9 11a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7Zm-6.5 9a6.5 6.5 0 0 1 13 0M16.5 4.3a3.5 3.5 0 0 1 0 6.4M18 14.2a6.5 6.5 0 0 1 3.5 5.8" />,
  search: <path d="M10.5 17a6.5 6.5 0 1 0 0-13 6.5 6.5 0 0 0 0 13Zm5-1.5L21 21" />,
  info: <path d="M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18Zm0-10v6m0-9.5v.5" />,
  trash: <path d="M4 7h16M9 7V4h6v3m-9 0 1 13h10l1-13" />,
  logout: <path d="M15 4h4v16h-4M10 8l-4 4 4 4m-4-4h10" />,
};

export function Icon({ name, size = 18 }: { name: string; size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      {ICONS[name] ?? ICONS.info}
    </svg>
  );
}

export function DiscordGlyph({ size = 18 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
      <path d="M19.6 5.3A17 17 0 0 0 15.4 4l-.5 1.1a15.7 15.7 0 0 0-4.8 0L9.6 4a17 17 0 0 0-4.2 1.3C2.7 9.3 2 13.2 2.4 17a17 17 0 0 0 5.2 2.6l1.1-1.8a11 11 0 0 1-1.7-.8l.4-.3a12.2 12.2 0 0 0 10.4 0l.4.3c-.5.3-1.1.6-1.7.8l1.1 1.8a17 17 0 0 0 5.2-2.6c.5-4.4-.8-8.3-2.8-11.7ZM8.9 14.7c-1 0-1.9-1-1.9-2.1s.8-2.1 1.9-2.1 1.9 1 1.9 2.1-.8 2.1-1.9 2.1Zm6.2 0c-1 0-1.9-1-1.9-2.1s.8-2.1 1.9-2.1 1.9 1 1.9 2.1-.8 2.1-1.9 2.1Z" />
    </svg>
  );
}

/** Tally marks in a roundel: four strokes and the closing slash. */
export function Logo({ size = 30 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 32 32" fill="none" aria-hidden="true">
      <circle cx="16" cy="16" r="14.5" stroke="currentColor" strokeOpacity=".35" />
      <path d="M10.5 10v12M14 10v12M17.5 10v12M21 10v12" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" />
      <path d="M8 19.5 23.5 12" stroke="#a78bfa" strokeWidth="1.8" strokeLinecap="round" />
    </svg>
  );
}

// Deterministic pseudo-random so the server and the browser draw the same stars.
function seeded(seed: number) {
  let value = seed;
  return () => {
    value = (value * 1664525 + 1013904223) % 4294967296;
    return value / 4294967296;
  };
}
const random = seeded(7);
const STARS = Array.from({ length: 140 }, () => ({ x: random() * 1440, y: random() * 380, r: random() < 0.08 ? 1.4 : 0.4 + random() * 0.7, o: 0.25 + random() * 0.7 }));

/** Painted dusk over a mountain range with a distant keep. Original artwork, SVG only. */
export function DuskSky() {
  return (
    <svg className="dusk-sky" viewBox="0 0 1440 640" preserveAspectRatio="xMidYMid slice" aria-hidden="true">
      <defs>
        <linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#120f22" />
          <stop offset=".38" stopColor="#2a2148" />
          <stop offset=".62" stopColor="#56406d" />
          <stop offset=".8" stopColor="#9a6a7c" />
          <stop offset="1" stopColor="#d79a86" />
        </linearGradient>
        <radialGradient id="moonGlow" cx=".5" cy=".5" r=".5">
          <stop offset="0" stopColor="#fff4e6" stopOpacity=".9" />
          <stop offset=".25" stopColor="#f4d9c6" stopOpacity=".35" />
          <stop offset="1" stopColor="#f4d9c6" stopOpacity="0" />
        </radialGradient>
        <filter id="soft" x="-20%" y="-50%" width="140%" height="200%"><feGaussianBlur stdDeviation="14" /></filter>
        <filter id="softer" x="-20%" y="-50%" width="140%" height="200%"><feGaussianBlur stdDeviation="28" /></filter>
        <linearGradient id="ridgeFar" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#4a3a62" /><stop offset="1" stopColor="#2c2342" /></linearGradient>
        <linearGradient id="ridgeMid" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#2b2240" /><stop offset="1" stopColor="#1b162b" /></linearGradient>
      </defs>
      <rect width="1440" height="640" fill="url(#sky)" />
      {STARS.map((s, i) => <circle key={i} cx={s.x.toFixed(1)} cy={s.y.toFixed(1)} r={s.r.toFixed(2)} fill="#fff" opacity={s.o.toFixed(2)} />)}
      <circle cx="1080" cy="170" r="150" fill="url(#moonGlow)" />
      <circle cx="1080" cy="170" r="22" fill="#fbeee0" opacity=".92" />
      <g filter="url(#softer)" opacity=".55">
        <ellipse cx="300" cy="300" rx="420" ry="38" fill="#c98d97" />
        <ellipse cx="1150" cy="330" rx="380" ry="30" fill="#e2a58f" />
      </g>
      <g filter="url(#soft)" opacity=".7">
        <ellipse cx="520" cy="250" rx="260" ry="22" fill="#7d5f8f" />
        <ellipse cx="980" cy="270" rx="300" ry="20" fill="#8e6a8c" />
        <ellipse cx="180" cy="380" rx="240" ry="18" fill="#b77f88" />
      </g>
      <path d="M0 470 L120 410 L210 440 L330 360 L430 420 L540 380 L650 430 L760 350 L880 410 L990 372 L1100 425 L1220 360 L1330 410 L1440 380 V640 H0Z" fill="url(#ridgeFar)" opacity=".85" />
      {/* Distant keep on the right peak of the far ridge, the only structure in the scene. */}
      <g transform="translate(1194 316)" fill="#2c2342">
        {/* Rock foundation so the walls sit on the slope instead of floating. */}
        <path d="M-10 66 L2 44 H56 L70 66Z" />
        <path d="M0 46V16l5-9 5 9v30z" />
        <path d="M10 46V27h3v-4h3v4h3v-4h3v4h3v-4h3v4h3v-4h3v4h2v19z" />
        <path d="M35 46V10l7-10 7 10v36z" />
        <path d="M49 46V22l4.5-7 4.5 7v24z" />
        <rect x="40.5" y="17" width="3" height="5" fill="#f2c79a" opacity=".85" />
        <rect x="3.5" y="24" width="2.5" height="4" fill="#f2c79a" opacity=".6" />
        <rect x="52" y="30" width="2.5" height="4" fill="#f2c79a" opacity=".5" />
      </g>
      <path d="M0 520 L150 470 L280 505 L420 450 L560 500 L700 460 L840 515 L980 470 L1120 510 L1260 455 L1440 495 V640 H0Z" fill="url(#ridgeMid)" />
      <path d="M0 590 L180 548 L340 580 L520 540 L700 585 L880 552 L1060 590 L1240 545 L1440 575 V640 H0Z" fill="#141120" />
    </svg>
  );
}

function Flap({ char, dim }: { char: string; dim?: boolean }) {
  return <span className={`flap${dim ? " dim" : ""}`}>{char}</span>;
}

/** Departure-board counters. Values are padded so the board keeps its shape. */
export function SplitFlapBoard({ rows }: { rows: { label: string; value: number | null }[] }) {
  return (
    <div className="flap-board" role="table">
      {rows.map((row) => {
        const digits = row.value === null ? "------" : String(Math.min(row.value, 999999)).padStart(6, " ");
        return (
          <div className="flap-row" role="row" key={row.label} aria-label={`${row.label} ${row.value ?? ""}`}>
            <span className="flap-label">{[...row.label.padEnd(12, " ")].map((c, i) => <Flap key={i} char={c} dim />)}</span>
            <span className="flap-value">{[...digits].map((c, i) => <Flap key={`${i}-${c}`} char={c} />)}</span>
          </div>
        );
      })}
    </div>
  );
}

export function ConsoleWindow({ title, actions, children, className = "" }: { title: ReactNode; actions?: ReactNode; children: ReactNode; className?: string }) {
  return (
    <section className={`console ${className}`}>
      <header className="console-bar">
        <span className="console-dots" aria-hidden="true"><i /><i /><i /></span>
        <span className="console-title">{title}</span>
        {actions && <span className="console-actions">{actions}</span>}
      </header>
      <div className="console-body">{children}</div>
    </section>
  );
}

export function Tag({ children, tone = "neutral" }: { children: ReactNode; tone?: "neutral" | "green" | "peach" | "lilac" }) {
  return <span className={`tag tag-${tone}`}>{children}</span>;
}

export function Empty({ icon, title, children, action }: { icon: string; title: string; children: ReactNode; action?: ReactNode }) {
  return (
    <div className="empty">
      <span className="empty-icon"><Icon name={icon} size={22} /></span>
      <h3>{title}</h3>
      <p>{children}</p>
      {action}
    </div>
  );
}

export function resultKey(run: Run) {
  if (run.status === "interrupted") return "result.interrupted" as const;
  if (run.status === "manual") return "result.manual" as const;
  if (run.status === "abandoned") return "result.abandoned" as const;
  if (run.completion === "full_clear") return "result.full_clear" as const;
  if (run.completion === "last_boss") return "result.last_boss" as const;
  if (run.status === "completed") return "result.completed_unknown" as const;
  return "result.visiting" as const;
}

export function RunTable({ runs, compact = false }: { runs: Run[]; compact?: boolean }) {
  const { t, plural, date } = useI18n();
  const [expanded, setExpanded] = useState<string | null>(null);
  return (
    <div className="table-wrap">
      <table className="data-table">
        <thead>
          <tr>
            <th>{t("runs.dungeon")}</th><th>{t("runs.character")}</th>
            {!compact && <th>{t("runs.date")}</th>}
            <th className="num">{t("runs.time")}</th><th>{t("runs.result")}</th>
          </tr>
        </thead>
        <tbody>
          {runs.map((run) => {
            const key = resultKey(run);
            return (
              <Fragment key={run.id}><tr>
                <td><button className="record-toggle" aria-label={t("detail.open", { name: run.name })} aria-expanded={expanded === run.id} aria-controls={`run-detail-${run.id}`} onClick={() => setExpanded(expanded === run.id ? null : run.id)}><span aria-hidden="true">{expanded === run.id ? "−" : "+"}</span><strong>{run.name || `#${run.instanceId ?? "?"}`}</strong></button><small>{run.bossCount == null ? "—" : `${run.bossCount} ${plural(run.bossCount, "runs.boss")}`}</small></td>
                <td><CharacterBadge character={run.character} unnamed={t("common.private")} /></td>
                {!compact && <td className="muted">{date(run.startedAt)}</td>}
                <td className="num mono">{duration(run.durationMs)}</td>
                <td><Tag tone={key === "result.full_clear" ? "green" : key === "result.last_boss" ? "peach" : "neutral"}>{t(key)}</Tag></td>
              </tr>{expanded === run.id && <tr className="record-detail-row" id={`run-detail-${run.id}`}><td colSpan={compact ? 4 : 5}><RunDetails run={run} /></td></tr>}</Fragment>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

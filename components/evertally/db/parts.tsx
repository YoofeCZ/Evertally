"use client";
import { createContext, useCallback, useContext, useEffect, useRef, useState, type ReactNode } from "react";
import { CategoryGlyph, ItemIcon, PoiBadge } from "./icons";
import {
  RANK, hrefDungeon, hrefItem, hrefNpc, hrefQuest, loadItem, qualityClass, useIndex,
  type Index, type ItemDetail, type NpcRow, type QuestRow, type Span, type TipRow,
} from "./store";

// ---- shared index (loaded once per session) --------------------------------------------------
const DbContext = createContext<{ index: Index | null; loading: boolean; error: boolean }>({ index: null, loading: true, error: false });
export function DbProvider({ children }: { children: ReactNode }) {
  const { data, loading, error } = useIndex();
  return <DbContext.Provider value={{ index: data, loading, error }}>{children}</DbContext.Provider>;
}
export const useDb = () => useContext(DbContext);

// ---- tooltip rendering ------------------------------------------------------------------------
function Spans({ spans }: { spans: Span[] }) {
  return <>{spans.map(([text, cls, item], i) => item
    ? <a key={i} className={cls ?? undefined} href={hrefItem(item)}>{text}</a>
    : cls ? <span key={i} className={cls}>{text}</span> : text)}</>;
}

export function Money({ gold, silver, copper }: { gold: number; silver: number; copper: number }) {
  return <span className="money">
    {gold > 0 && <span className="m-gold">{gold}<i /></span>}
    {(silver > 0 || gold > 0) && <span className="m-silver">{silver}<i /></span>}
    <span className="m-copper">{copper}<i /></span>
  </span>;
}

/** The game tooltip: quality-coloured name, two-column rows, effects, set bonuses and sell price. */
export function TipBody({ rows }: { rows: TipRow[] }) {
  return <div className="wow-tip">{rows.map((row, i) => {
    if (row[0] === "S") return <div key={i} className="ts" />;
    if (row[0] === "M") return <div key={i} className="tm">Sell Price: <Money gold={row[1]} silver={row[2]} copper={row[3]} /></div>;
    if (row[0] === "C") return <div key={i} className="tc"><span><Spans spans={row[1]} /></span><span><Spans spans={row[2]} /></span></div>;
    return <div key={i} className={i === 0 ? "tn" : "tl"}><Spans spans={row[1]} /></div>;
  })}</div>;
}

/** Items without a cached tooltip still get the facts we know. */
export function liteRows(name: string, quality: number | null, ilvl: number | null, req: number | null, category?: string | null): TipRow[] {
  const rows: TipRow[] = [["L", [[name, qualityClass(quality)]]]];
  if (category) rows.push(["L", [[category, "q0"]]]);
  if (ilvl) rows.push(["L", [[`Item Level ${ilvl}`, "q"]]]);
  if (req) rows.push(["L", [[`Requires Level ${req}`]]]);
  return rows;
}
export function lineRows(name: string, quality: number | null, slot: string | null, lines: string[] | null): TipRow[] {
  const rows: TipRow[] = [["L", [[name, qualityClass(quality)]]]];
  if (lines?.length) for (const line of lines) rows.push(["L", [[line, /^Equip:|^Use:|^Chance/.test(line) ? "q2" : undefined] as Span]]);
  else if (slot) rows.push(["L", [[slot]]]);
  return rows;
}

// ---- hover card --------------------------------------------------------------------------------
type Hover = { x: number; y: number; rows: TipRow[] } | null;
function useHoverCard(load: () => Promise<TipRow[] | null>) {
  const [hover, setHover] = useState<Hover>(null);
  const timer = useRef<number | null>(null);
  const live = useRef(false);
  const show = useCallback((element: HTMLElement) => {
    live.current = true;
    timer.current = window.setTimeout(() => {
      load().then(rows => {
        if (!live.current || !rows) return;
        const box = element.getBoundingClientRect();
        const width = 330;
        const x = Math.min(window.innerWidth - width - 12, Math.max(12, box.left));
        const below = box.bottom + 8;
        setHover({ x, y: below + 280 > window.innerHeight ? Math.max(12, box.top - 8) : below, rows: below + 280 > window.innerHeight ? rows.map(r => r) : rows });
      }).catch(() => undefined);
    }, 140);
  }, [load]);
  const hide = useCallback(() => {
    live.current = false;
    if (timer.current) window.clearTimeout(timer.current);
    setHover(null);
  }, []);
  useEffect(() => hide, [hide]);
  return { hover, show, hide };
}

function HoverCard({ hover }: { hover: Hover }) {
  if (!hover) return null;
  const flipped = hover.y < 100;
  return <div className="tip-pop" style={{ left: hover.x, top: hover.y, transform: flipped ? undefined : undefined }} role="tooltip"><TipBody rows={hover.rows} /></div>;
}

// ---- entity links -------------------------------------------------------------------------------
export function ItemLink({ id, name, quality, icon = true, count, className = "" }: { id: number; name?: string; quality?: number | null; icon?: boolean; count?: ReactNode; className?: string }) {
  const { index } = useDb();
  const row = index?.items.get(id);
  const label = name ?? row?.[1] ?? `#${id}`;
  const q = quality ?? row?.[2] ?? null;
  const load = useCallback(async (): Promise<TipRow[] | null> => {
    if (!index) return null;
    const detail = await loadItem(index, id);
    if (detail?.tip?.length) return detail.tip;
    const r = index.items.get(id);
    return r ? liteRows(r[1], r[2], r[3], r[4], index.search.cats[r[5]]) : null;
  }, [index, id]);
  const { hover, show, hide } = useHoverCard(load);
  return <>
    <a className={`ilink ${qualityClass(q)} ${className}`} href={hrefItem(id)} onMouseEnter={event => show(event.currentTarget)} onMouseLeave={hide} onFocus={event => show(event.currentTarget)} onBlur={hide}>
      {icon && <ItemIcon id={id} quality={q} category={index?.search.cats[row?.[5] ?? -1]} fileId={row?.[9]} cached={row ? row[8] === 0 : true} size={22} />}
      <span>{label}</span>{count}
    </a>
    <HoverCard hover={hover} />
  </>;
}

/** Loot cell for items that may only exist in the journal (new Forever items without an id yet). */
export function ExtraItem({ name, slot, quality, lines }: { name: string; slot: string | null; quality: number | null; lines: string[] | null }) {
  const load = useCallback(async () => lineRows(name, quality, slot, lines), [name, quality, slot, lines]);
  const { hover, show, hide } = useHoverCard(load);
  return <>
    <span className={`ilink ${qualityClass(quality)}`} tabIndex={0} onMouseEnter={event => show(event.currentTarget)} onMouseLeave={hide} onFocus={event => show(event.currentTarget)} onBlur={hide}>
      <span className={`item-icon ${qualityClass(quality)}`} style={{ width: 22, height: 22 }}><CategoryGlyph category={slot?.split(",")[1]?.trim() ? undefined : undefined} size={13} /></span>
      <span>{name}</span>{slot && <small className="muted"> · {slot}</small>}
    </span>
    <HoverCard hover={hover} />
  </>;
}

export function NpcLink({ id, row, children }: { id: number; row?: NpcRow; children?: ReactNode }) {
  const { index } = useDb();
  const r = row ?? index?.npcs.get(id);
  return <a className="elink" href={hrefNpc(id)}>{children ?? r?.[1] ?? `NPC #${id}`}</a>;
}
export function QuestLink({ id, row }: { id: number; row?: QuestRow }) {
  const { index } = useDb();
  const r = row ?? index?.quests.get(id);
  return <a className="elink quest" href={hrefQuest(id)}><PoiBadge kind="qs" size={16} /><span>{r?.[1] ?? `Quest #${id}`}</span>{r?.[2] ? <small className="muted"> ({r[2]})</small> : null}</a>;
}
export function DungeonLink({ keyName, name }: { keyName: string; name: string }) {
  return <a className="elink" href={hrefDungeon(keyName)}><PoiBadge kind="dungeon" size={16} /><span>{name}</span></a>;
}

export function npcLevel(row: NpcRow | undefined): string {
  if (!row) return "";
  return row[2] === row[3] || !row[3] ? `${row[2] || "??"}` : `${row[2]}–${row[3]}`;
}
export const rankName = (rank: number) => RANK[rank] ?? "";

export function Section({ title, count, children, aside }: { title: ReactNode; count?: number; children: ReactNode; aside?: ReactNode }) {
  return <section className="db-section"><header><h3>{title}{count != null && <span className="count">{count}</span>}</h3>{aside}</header>{children}</section>;
}

export function ItemChips({ ids, limit = 60 }: { ids: number[]; limit?: number }) {
  const [all, setAll] = useState(false);
  const shown = all ? ids : ids.slice(0, limit);
  return <div className="item-grid">{shown.map(id => <ItemLink key={id} id={id} />)}{ids.length > limit && !all && <button type="button" className="link-btn" onClick={() => setAll(true)}>+{ids.length - limit}</button>}</div>;
}

/** Long link lists show the first few entries and a toggle for the rest. */
export function Fold({ items, limit = 10, className = "item-grid" }: { items: ReactNode[]; limit?: number; className?: string }) {
  const [all, setAll] = useState(false);
  return <div className={className}>{all ? items : items.slice(0, limit)}{items.length > limit && <button type="button" className="link-btn" onClick={() => setAll(value => !value)}>{all ? "−" : `+${items.length - limit}`}</button>}</div>;
}

export type { ItemDetail };

"use client";
// A search box and a page switcher for the long public lists (chronicles, highlights): ten rows a page instead of an endless scroll.
import { useMemo, useState } from "react";
import { Icon } from "./ui";

export const PAGE_SIZE = 10;

/** Filters `items` by `query` (every word must appear in the row's text) and cuts the current page out of the result. */
export function usePaged<T>(items: readonly T[], text: (item: T) => string, size = PAGE_SIZE) {
  const [query, setQuery] = useState("");
  // the page belongs to one list and one search; a new list or search starts again on the first page
  const [at, setAt] = useState<{ page: number; items: readonly T[]; query: string }>({ page: 0, items, query: "" });
  const page = at.items === items && at.query === query ? at.page : 0;
  const setPage = (next: number) => setAt({ page: next, items, query });
  const matches = useMemo(() => {
    const words = query.toLocaleLowerCase().split(/\s+/).filter(Boolean);
    if (!words.length) return items;
    return items.filter(item => { const hay = text(item).toLocaleLowerCase(); return words.every(word => hay.includes(word)); });
    // `text` is a pure projection of the row; the list and the query decide the result
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [items, query]);
  const pages = Math.max(1, Math.ceil(matches.length / size));
  const current = Math.min(page, pages - 1);
  return {
    query, setQuery, page: current, pages, setPage, total: matches.length,
    rows: matches.slice(current * size, (current + 1) * size),
  };
}

export function PagedSearch({ value, onChange, placeholder }: { value: string; onChange: (value: string) => void; placeholder: string }) {
  return (
    <label className="search paged-search">
      <Icon name="search" size={16} />
      <input type="search" value={value} onChange={event => onChange(event.target.value)} placeholder={placeholder} aria-label={placeholder} />
    </label>
  );
}

/** Previous / page numbers / next. Hidden when everything fits on one page. */
export function Pager({ page, pages, onPage, previous, next, label }: { page: number; pages: number; onPage: (page: number) => void; previous: string; next: string; label: string }) {
  if (pages <= 1) return null;
  const numbers = pageNumbers(page, pages);
  return (
    <nav className="paged-pager" aria-label={label}>
      <button type="button" className="btn btn-ghost btn-sm" disabled={page === 0} onClick={() => onPage(page - 1)}>← {previous}</button>
      <span className="paged-numbers">
        {numbers.map((n, i) => n === null
          ? <span key={`gap${i}`} className="paged-gap">…</span>
          : <button key={n} type="button" className={n === page ? "is-on" : ""} aria-current={n === page ? "page" : undefined} onClick={() => onPage(n)}>{n + 1}</button>)}
      </span>
      <button type="button" className="btn btn-ghost btn-sm" disabled={page + 1 >= pages} onClick={() => onPage(page + 1)}>{next} →</button>
    </nav>
  );
}

/** First, last and the neighbours of the current page; gaps are null. */
export function pageNumbers(page: number, pages: number): (number | null)[] {
  if (pages <= 7) return Array.from({ length: pages }, (_, i) => i);
  const keep = new Set([0, pages - 1, page - 1, page, page + 1].filter(n => n >= 0 && n < pages));
  const sorted = [...keep].sort((a, b) => a - b);
  const out: (number | null)[] = [];
  for (const n of sorted) { if (out.length && n - (out[out.length - 1] as number) > 1) out.push(null); out.push(n); }
  return out;
}

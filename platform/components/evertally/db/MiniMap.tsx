"use client";
import { useI18n } from "@/lib/i18n";
import { hrefMap, useMaps } from "./store";

/** Static preview of a zone with spawn points; clicking opens the interactive map at that zone. */
export function MiniMap({ zone, points, focus, label, extra }: { zone: string; points: [number, number][]; focus?: string; label?: string; extra?: [number, number][] }) {
  const { lang } = useI18n();
  const maps = useMaps();
  const map = maps.data?.find(entry => entry.key === zone);
  if (!map) return <div className="mini-map is-empty" aria-hidden="true" />;
  const name = label ?? (lang === "cs" ? map.nameCs : map.nameEn);
  return (
    <a className="mini-map" href={hrefMap(zone, focus)} style={{ aspectRatio: `${map.width} / ${map.height}` }} aria-label={name}>
      {/* eslint-disable-next-line @next/next/no-img-element -- bundled zone artwork with intrinsic size */}
      <img src={map.image} alt="" width={map.width} height={map.height} loading="lazy" decoding="async" />
      {(extra ?? []).map(([x, y], i) => <i key={`e${i}`} className="mm-dot mm-extra" style={{ left: `${x}%`, top: `${y}%` }} />)}
      {points.slice(0, 80).map(([x, y], i) => <i key={i} className="mm-dot" style={{ left: `${x}%`, top: `${y}%` }} />)}
      <span className="mm-name">{name}</span>
    </a>
  );
}

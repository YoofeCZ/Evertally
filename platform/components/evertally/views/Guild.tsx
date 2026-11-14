"use client";
import type { CSSProperties, ReactNode } from "react";
import { hasKey, useI18n } from "@/lib/i18n";
import type { GuildDetail, RaidProgress } from "@/lib/guilds";
import { useApi } from "../api";
import { CLASS_COLORS, completed, duration } from "../data";
import { useDungeons } from "../db/store";
import { CharacterIcons, fullName } from "../Identity";
import { parseGuildRoute } from "../rankingRoute";
import type { Run } from "../types";
import { Icon } from "../ui";
import { FactionMark } from "./Rankings";

const ART = "/media/dungeons/blackrock-depths.jpg";
const fold = (value?: string | null) => (value ?? "").toLocaleLowerCase("en").replace(/[^a-z0-9]/g, "");
// loot groups the dungeon guide lists beside the bosses (trash, tier sets, shared loot), never a boss to defeat
const NOT_BOSS = /^(trash\b|all bosses$|tier \d+ sets?$|aq opening$|ahn'qiraj (scarabs|enchants)$)|shared loot$/i;

/** A guild page in the shape of Raider.IO: banner with its place and numbers, raid progress, the shown members and their runs. */
export function GuildView({ route }: { route: string }) {
  const { t, num, date } = useI18n();
  const wanted = parseGuildRoute(route);
  const page = useApi<GuildDetail>(wanted ? `/api/guilds?${new URLSearchParams({ realm: wanted.realm, name: wanted.name })}` : null);
  if (!wanted || page.error) return <div className="page-column lb ch">
    <div className="lb-message ch-missing"><span className="lb-message-icon"><Icon name="lock" size={20} /></span>
      <strong>{t("guild.notFoundTitle")}</strong><p>{t("guild.notFoundText")}</p>
      <a className="lb-btn" href="#rankings/guilds">← {t("guild.back")}</a></div>
  </div>;
  if (!page.data) return <div className="page-column lb ch"><p className="lb-count">{t("common.loading")}</p></div>;

  const g = page.data;
  const color = g.faction === "horde" ? "#e0503f" : g.faction === "alliance" ? "#4f8ff0" : "#ececf0";
  const result = (run: Run) => { const key = `result.${run.completion && completed(run) ? run.completion : run.status ?? "visiting"}`; return hasKey(key) ? t(key) : run.status ?? "—"; };
  const nameOf = new Map(g.roster.map(m => [m.character.id, m.character]));

  return <div className="page-column lb ch">
    <a className="ch-back" href="#rankings/guilds">← {t("guild.back")}</a>
    <section className="ch-banner" style={{ "--class": color, "--lb-art": `url("${ART}")` } as CSSProperties}>
      <div className="ch-identity">
        <span className="gd-crest" aria-hidden="true"><Icon name="shield" size={34} /></span>
        <div className="ch-name">
          <h1>{g.name}</h1>
          <p>{g.realm}<FactionMark faction={g.faction} /> · {t("rankings.membersShort", { count: num(g.members) })}</p>
        </div>
      </div>
      <div className="ch-stats">
        <Stat label={t("guild.rank")} value={`#${num(g.rank)}`} />
        {g.realm && <Stat label={t("guild.realmRank", { realm: g.realm })} value={`#${num(g.realmRank)}`} sub={t("character.of", { total: num(g.realmTotal) })} />}
        <Stat label={t("guild.bosses")} value={num(g.bosses)} />
        <Stat label={t("guild.completions")} value={num(g.completions)} />
        {g.avgLevel != null && <Stat label={t("guild.avgLevel")} value={num(g.avgLevel)} sub={g.maxLevel != null ? `max ${num(g.maxLevel)}` : undefined} />}
        {g.itemLevel != null && <Stat label={t("guild.ilvl")} value={num(g.itemLevel)} />}
      </div>
    </section>
    <p className="ch-note"><Icon name="info" size={14} /> {t("guild.note")}</p>

    <div className="ch-grid">
      <div>
        <Card title={`${t("guild.roster")} · ${num(g.roster.length)}`}>
          <table className="lb-table ch-table">
            <thead><tr><th>{t("runs.character")}</th><th className="num">{t("rankings.level")}</th><th className="num">iLvl</th><th className="num">{t("guild.completions")}</th><th className="num">{t("guild.bosses")}</th><th className="num">{t("guild.lastRun")}</th></tr></thead>
            <tbody>{g.roster.map(m => <tr key={m.character.id}>
              <td><span className="lb-char" style={CLASS_COLORS[m.character.classId ?? 0] ? { "--class": CLASS_COLORS[m.character.classId ?? 0] } as CSSProperties : undefined}>
                <CharacterIcons character={m.character} size={20} />
                <a className="profile-name" href={`#character/${encodeURIComponent(m.character.id)}`}>{fullName(m.character)}</a></span></td>
              <td className="num">{m.character.level ?? "—"}</td>
              <td className="num">{m.itemLevel ?? "—"}</td>
              <td className="num">{num(m.completions)}</td>
              <td className="num">{num(m.bosses)}</td>
              <td className="num">{date(m.lastAt)}</td>
            </tr>)}</tbody>
          </table>
        </Card>
        <Card title={t("guild.recent")}>
          {g.recent.length ? <table className="lb-table ch-table">
            <thead><tr><th>{t("character.instance")}</th><th>{t("runs.character")}</th><th>{t("character.result")}</th><th className="num">{t("character.time")}</th><th className="num">{t("character.date")}</th></tr></thead>
            <tbody>{g.recent.map(run => {
              const who = run.character ? nameOf.get(run.character.id) ?? run.character : null;
              return <tr key={run.id}><td>{run.name}</td><td>{who ? <a className="profile-name" style={{ "--class": CLASS_COLORS[who.classId ?? 0] } as CSSProperties} href={`#character/${encodeURIComponent(who.id)}`}>{who.name}</a> : "—"}</td>
                <td>{result(run)}</td><td className="num">{duration(run.durationMs)}</td><td className="num">{date(run.startedAt)}</td></tr>;
            })}</tbody>
          </table> : <p className="ch-empty">{t("guild.noRuns")}</p>}
        </Card>
      </div>
      <div>
        <RaidProgressCard progress={g.progress} />
      </div>
    </div>
  </div>;
}

/** Raid progress, one block per instance: killed of all bosses with a bar, then every boss with its first kill. */
export function RaidProgressCard({ progress }: { progress: RaidProgress[] }) {
  const { t, num, date } = useI18n();
  const catalog = useDungeons();
  return <section className="ch-card"><h2>{t("progress.title")}</h2>
    {progress.length ? <div className="gp-list">{progress.map(raid => {
      const entry = catalog.data?.entries.find(d => fold(d.name) === fold(raid.instanceName));
      const listed = entry ? entry.bosses.filter(b => !NOT_BOSS.test(b.name) && !b.rare) : [];
      const killedByName = new Map(raid.bosses.map(b => [fold(b.name), b]));
      const extra = raid.bosses.filter(b => !listed.some(l => fold(l.name) === fold(b.name)));
      const rows = [...listed.map(b => ({ key: b.name, name: b.name, kill: killedByName.get(fold(b.name)) ?? null })),
        ...extra.map(b => ({ key: `e${b.encounterId}`, name: b.name ?? `#${b.encounterId}`, kill: b }))];
      const total = listed.length;
      const killed = total ? Math.min(total, raid.bosses.length) : raid.bosses.length;
      return <div key={raid.instanceId ?? raid.instanceName} className="gp-raid">
        <div className="gp-head"><strong>{raid.instanceName}</strong><b>{total ? `${num(killed)}/${num(total)}` : num(killed)}</b></div>
        {total > 0 && <div className="gp-bar" role="presentation"><i style={{ width: `${Math.round(killed / total * 100)}%` }} /></div>}
        <ul>{rows.map(row => <li key={row.key} className={row.kill ? "on" : undefined}>
          <span><Icon name={row.kill ? "check" : "close"} size={12} /> {row.name}</span>
          <small>{row.kill ? `${t("progress.firstKill", { date: date(row.kill.firstAt) })}${row.kill.kills > 1 ? ` · ${num(row.kill.kills)}×` : ""}` : "—"}</small>
        </li>)}</ul>
      </div>;
    })}</div> : <p className="ch-empty">{t("progress.none")}</p>}
  </section>;
}

function Stat({ label, value, sub }: { label: string; value: ReactNode; sub?: string }) {
  return <div className="ch-stat"><small>{label}</small><strong>{value}</strong>{sub && <span>{sub}</span>}</div>;
}

function Card({ title, children }: { title: string; children: ReactNode }) {
  return <section className="ch-card"><h2>{title}</h2>{children}</section>;
}

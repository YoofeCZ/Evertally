// Runs the production SQL of lib/*.ts against a real SQLite (node:sqlite) with the real migrations, behind the D1-shaped Db interface.
import { readFileSync, readdirSync } from "node:fs";
import { DatabaseSync, type SQLInputValue } from "node:sqlite";
import type { Db, Stmt } from "../lib/people";

export function adapter(db: DatabaseSync): Db {
  const make = (sql: string, params: unknown[] = []): Stmt => ({
    bind: (...values) => make(sql, values),
    all: async <T,>() => ({ results: db.prepare(sql).all(...(params as SQLInputValue[])) as T[] }),
    first: async <T,>() => ((db.prepare(sql).get(...(params as SQLInputValue[])) as T | undefined) ?? null),
    run: async () => ({ meta: { changes: Number(db.prepare(sql).run(...(params as SQLInputValue[])).changes) } }),
  });
  return {
    prepare: (sql) => make(sql),
    batch: async (statements) => { db.exec("BEGIN"); try { const out = []; for (const s of statements) out.push(await s.run()); db.exec("COMMIT"); return out; } catch (error) { db.exec("ROLLBACK"); throw error; } },
  };
}

export const t0 = Math.floor(Date.now() / 1000) - 600;

/** Accounts (default: gm, bob, eve) with one character each and a grant that allows route, character and guild. */
export function fixture(names: [string, string][] = [["gm", "Aria"], ["bob", "Bran"], ["eve", "Eve"]]) {
  const sql = new DatabaseSync(":memory:");
  for (const name of readdirSync("drizzle").filter((n) => n.endsWith(".sql")).sort()) sql.exec(readFileSync("drizzle/" + name, "utf8"));
  const grant = sql.prepare("INSERT INTO atlas_grants(id,user_id,producer_id,consent_epoch,since,scopes,created_at) VALUES(?,?,?,?,?,?,0)");
  const profile = sql.prepare('INSERT INTO atlas_profiles(id,user_id,producer_id,character_key,name,realm,class_id,level,"public",last_seen) VALUES(?,?,?,?,?,?,?,?,0,?)');
  for (const [user, name] of names) {
    grant.run("grant-" + user, user, "src-" + user, 1, 0, JSON.stringify(["own_track", "guild_share", "own_character"]));
    profile.run("p-" + user, user, "src-" + user, "k-" + user, name, "Test", 8, 30, t0);
  }
  function addTrack(user: string, at: number, mapId = 1429, x = 0.4, y = 0.6, grantId = "grant-" + user, n = 1) {
    sql.prepare("INSERT INTO atlas_observations(id,user_id,producer_id,event_id,grant_id,kind,scope,observed_at,profile_id,payload,game,evidence) VALUES(?,?,?,?,?,'track.path','own_track',?,?,?,'{}','api_snapshot')")
      .run(`t-${user}-${at}-${n}`, user, "src-" + user, `e-${user}-${at}-${n}`, grantId, at, "p-" + user, JSON.stringify({ mapId, startedAt: at - 20, points: [[0, 0.1, 0.1], [20, x, y]] }));
  }
  return { sql, db: adapter(sql), addTrack };
}

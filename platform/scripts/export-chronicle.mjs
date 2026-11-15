// Composes the journey recording of one character from the PRODUCTION database (read only) and writes it to a file, the same way the website
// does it for a signed-in owner (lib/chronicle-build.ts, with the owner's consents applied). The file opens on the Chronicle page
// ("Open a recording").   node scripts/export-chronicle.mjs "Character name" [days=60] [out.json]
import { build } from "esbuild";
import { spawnSync } from "node:child_process";
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
const [name, daysArg = "60", outArg] = process.argv.slice(2);
if (!name) { console.error('Usage: node scripts/export-chronicle.mjs "Character name" [days=60] [out.json]'); process.exit(2); }
const target = JSON.parse(readFileSync(path.join(root, "deploy/target.json"), "utf8"));
const config = path.join(root, "dist/server/wrangler.production.json");
const cli = path.join(root, "node_modules/wrangler/bin/wrangler.js");

const bundle = await build({
  stdin: { contents: 'export * from "./lib/chronicle-build.ts"; export { CHRONICLE_MAPS } from "./lib/chronicle-maps.ts"; export { findProblem } from "./lib/chronicle.ts";', resolveDir: root, loader: "ts" },
  bundle: true, write: false, format: "esm", platform: "node", target: "node22",
});
const lib = await import("data:text/javascript;base64," + Buffer.from(bundle.outputFiles[0].text).toString("base64"));

const literal = v => (typeof v === "number" ? String(v) : `'${String(v).replace(/'/g, "''")}'`);
function d1(sql) {
  const r = spawnSync(process.execPath, ["--import", pathToFileURL(path.join(root, "scripts/sites-env.mjs")).href, cli, "d1", "execute", target.database.name, "--remote", "--json", "--command", sql, "--config", config], {
    cwd: root, encoding: "utf8", maxBuffer: 256 * 1024 * 1024, env: { ...process.env, CLOUDFLARE_ACCOUNT_ID: target.accountId, WRANGLER_SEND_METRICS: "false" }, windowsHide: true,
  });
  if (r.status !== 0) throw new Error(`wrangler failed: ${(r.stderr || r.stdout).slice(0, 400)}`);
  const parsed = JSON.parse(r.stdout);
  return parsed[0]?.results ?? [];
}
// the production query of the website, with its values written into the text
const db = {
  prepare(sql) {
    const make = values => ({
      bind: (...v) => make(v),
      first: async () => d1(inline(sql, values))[0] ?? null,
      all: async () => ({ results: d1(inline(sql, values)) }),
    });
    return make([]);
  },
};
function inline(sql, values) { let i = 0; return sql.replace(/\?/g, () => literal(values[i++])); }

// the game writes a character as "Name Realm" (a space) or "Name-Realm"
const [first, ...rest] = name.trim().split(/[\s-]+/);
let profiles = d1(`SELECT id,user_id,producer_id,name,realm,class_id,level,last_seen FROM atlas_profiles WHERE name = ${literal(name)} COLLATE NOCASE ORDER BY last_seen DESC`);
if (!profiles.length && rest.length) profiles = d1(`SELECT id,user_id,producer_id,name,realm,class_id,level,last_seen FROM atlas_profiles WHERE name = ${literal(first)} COLLATE NOCASE AND realm = ${literal(rest.join(" "))} COLLATE NOCASE ORDER BY last_seen DESC`);
if (!profiles.length) { console.error(`No character named "${name}" in the production database.`); process.exit(1); }
const p = profiles[0];
console.log(`Character: ${p.name} (${p.realm ?? "no realm"}), level ${p.level}, class ${p.class_id}${profiles.length > 1 ? `; ${profiles.length} with this name, using the newest` : ""}`);
const kinds = d1(`SELECT o.kind AS kind,COUNT(*) AS n,MIN(o.observed_at) AS first,MAX(o.observed_at) AS last FROM atlas_observations o WHERE o.user_id=${literal(p.user_id)} AND o.profile_id=${literal(p.id)} GROUP BY o.kind ORDER BY n DESC`);
console.log("Stored events of this character:");
for (const k of kinds) console.log(`  ${String(k.n).padStart(6)}  ${k.kind}  (${new Date(k.first * 1000).toISOString().slice(0, 16)} to ${new Date(k.last * 1000).toISOString().slice(0, 16)})`);
const scopes = d1(`SELECT DISTINCT g.scopes AS scopes,g.revoked_at AS revoked FROM atlas_grants g WHERE g.user_id=${literal(p.user_id)} AND g.producer_id=${literal(p.producer_id)}`);
console.log("Consents of the account:", scopes.map(s => `${s.scopes}${s.revoked ? " (revoked)" : ""}`).join(" | ") || "none");

const days = Number(daysArg) || 60;
const result = await lib.myChronicle(db, p.user_id, p.id, days, lib.CHRONICLE_MAPS);
console.log(`The website would read ${result?.observations ?? 0} events for the last ${Math.min(60, days)} days.`);
if (!result?.chronicle) { console.error("Nothing to compose for this period (see the list above: the route needs the consent \"My route\", and the events a stored link to the character)."); process.exit(1); }
const c = result.chronicle;
const out = outArg ?? path.join(root, "..", "output", `kronika-${String(p.name).toLowerCase().replace(/[^a-z0-9]+/g, "-")}.json`);
mkdirSync(path.dirname(out), { recursive: true });
writeFileSync(out, JSON.stringify(c));
const by = {};
for (const e of c.events) by[e.k] = (by[e.k] ?? 0) + 1;
console.log(`Written ${out}`);
console.log(`  ${Math.round(c.duration / 60)} min of play in ${c.sessions.length} sessions, ${c.zones.length} zones, route ${c.path.length} points, ${c.events.length} events ${JSON.stringify(by)}`);
console.log(`  check: ${lib.findProblem(c) ?? "valid"}`);

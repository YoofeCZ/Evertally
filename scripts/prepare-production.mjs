import { readFile, writeFile, access } from "node:fs/promises";
import { constants } from "node:fs";
import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

// This helper can prepare a config, validate a dry run and initialise the one
// approved fresh database. It never deploys a Worker or changes a DNS record.
const root = fileURLToPath(new URL("../", import.meta.url));
const target = JSON.parse(await readFile(path.join(root, "deploy/target.json"), "utf8"));
const expected = {
  workerName: "evertally", hostname: "evertally.afstudio.dev",
  accountId: "a355311725afbdb07a231531619a4e01",
  databaseId: "33ca048c-b932-44cd-ba58-cf38aed0fd23", databaseName: "evertally-production",
};
if (target.schemaVersion !== 1 || target.workerName !== expected.workerName || target.hostname !== expected.hostname || target.accountId !== expected.accountId || target.database?.binding !== "DB" || target.database.id !== expected.databaseId || target.database.name !== expected.databaseName || target.database.jurisdiction !== "eu") {
  throw new Error("Production target differs from the explicitly approved Worker/account/database. Review the target before continuing.");
}

const args = new Set(process.argv.slice(2));
for (const arg of args) if (!["--init-db", "--dry-run", "--check-db"].includes(arg)) throw new Error(`Unknown preparation option: ${arg}`);
const generatedPath = path.join(root, "dist/server/wrangler.json");
const productionPath = path.join(root, "dist/server/wrangler.production.json");
const generated = JSON.parse(await readFile(generatedPath, "utf8"));
if (typeof generated.main !== "string" || typeof generated.assets?.directory !== "string" || !Array.isArray(generated.rules) || generated.d1_databases?.length !== 1 || generated.d1_databases[0].binding !== "DB") {
  throw new Error("Unexpected generated Worker config. Build the web app and review its entry point/assets/DB binding.");
}
if (Object.keys(generated.vars ?? {}).some((key) => /secret|token|password|credential/i.test(key))) {
  throw new Error("Generated public vars appear to contain secrets. Keep credentials in Cloudflare secrets, not build config.");
}
await access(path.resolve(path.dirname(generatedPath), generated.main), constants.R_OK);
await access(path.resolve(path.dirname(generatedPath), generated.assets.directory), constants.R_OK);
const production = {
  ...generated,
  name: target.workerName,
  account_id: target.accountId,
  workers_dev: false,
  preview_urls: false,
  routes: [{ pattern: target.hostname, custom_domain: true }],
  d1_databases: [{ binding: "DB", database_name: target.database.name, database_id: target.database.id }],
};
await writeFile(productionPath, `${JSON.stringify(production, null, 2)}\n`);

const cli = path.join(root, "node_modules/wrangler/bin/wrangler.js");
function wrangler(command, json = false) {
  const result = spawnSync(process.execPath, ["--import", pathToFileURL(path.join(root, "scripts/sites-env.mjs")).href, cli, ...command, "--config", productionPath], {
    cwd: root, encoding: "utf8", maxBuffer: 4 * 1024 * 1024,
    env: { ...process.env, CLOUDFLARE_ACCOUNT_ID: target.accountId, WRANGLER_SEND_METRICS: "false" },
    windowsHide: true,
  });
  if (result.error || result.status !== 0) {
    // Wrangler errors may mention account metadata, but this tool never prints
    // environment variables or reads a secrets file.
    throw new Error(`Wrangler ${command.slice(0, 2).join(" ")} failed: ${result.error?.message ?? result.stderr?.trim() ?? "unknown error"}`);
  }
  if (json) {
    try { return JSON.parse(result.stdout); }
    catch { throw new Error(`Wrangler ${command.slice(0, 2).join(" ")} did not return JSON.`); }
  }
  return result.stdout;
}
function verifiedInfo() {
  const info = wrangler(["d1", "info", target.database.name, "--json"], true);
  if (info.uuid !== target.database.id || info.name !== target.database.name || info.jurisdiction !== "eu") throw new Error("D1 identity/jurisdiction mismatch; no SQL was sent.");
  return info;
}
function sql(command) {
  // Wrangler's positional argument accepts a name/binding, not a UUID. The
  // generated config and verifiedInfo pin that exact name to the approved UUID.
  const result = wrangler(["d1", "execute", target.database.name, "--remote", "--yes", "--json", "--command", command], true);
  if (!Array.isArray(result) || result.some((part) => !part.success)) throw new Error("D1 execution did not confirm success.");
  return result.flatMap((part) => part.results ?? []);
}
const userTables = () => sql("SELECT name FROM sqlite_schema WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT IN ('_cf_KV','d1_migrations') ORDER BY name").map((row) => row.name);
const schema = ["atlas_grants", "atlas_observations", "atlas_profiles", "atlas_sources", "atlas_uploads", "et_circle_members", "et_circles", "et_device_codes", "et_devices", "et_forum_posts", "et_forum_threads", "et_friends", "et_game_connections", "et_guild_members", "et_guilds", "et_live_positions", "et_meet_access", "et_meet_rsvps", "et_meets", "et_sessions", "et_sharing", "et_users"];
const summary = { config: path.relative(root, productionPath).replaceAll(path.sep, "/"), worker: target.workerName, hostname: target.hostname, database: target.database.name, databaseId: target.database.id, published: false };

if (args.has("--init-db")) {
  const info = verifiedInfo();
  if (info.num_tables !== 0 || userTables().length !== 0) throw new Error("Initialisation refused: the approved D1 database is not empty. No reset or destructive repair is performed.");
  const migrations = ["0000_fixed_cardiac.sql", "0001_futuristic_invisible_woman.sql", "0002_auth_devices.sql", "0003_people.sql", "0004_circles_meets.sql", "0005_live_positions.sql", "0006_sharing.sql", "0007_game_connections.sql", "0008_forum.sql", "0009_ranking_details.sql"];
  // Review every statement before the first write. The allowlist rejects DML,
  // DROP/REPLACE/PRAGMA and scripts which address attached databases.
  const prepared = [];
  for (const name of migrations) {
    const content = await readFile(path.join(root, "drizzle", name), "utf8");
    const statements = content.replace(/--[^\n]*/g, "").split(";").map((statement) => statement.trim()).filter(Boolean);
    if (!statements.length || statements.some((statement) => !/^(?:CREATE\s+(?:UNIQUE\s+)?(?:TABLE|INDEX)\s+|ALTER\s+TABLE\s+)/i.test(statement) || /\b(?:DROP|DELETE|INSERT|UPDATE|REPLACE|ATTACH|DETACH|TRUNCATE)\b/i.test(statement))) {
      throw new Error(`Migration ${name} contains a statement outside the schema-only allowlist.`);
    }
    prepared.push({ name, content, sha256: createHash("sha256").update(content).digest("hex") });
  }
  for (const migration of prepared) {
    sql(migration.content);
    console.log(`Applied schema migration: ${migration.name} (${migration.sha256.slice(0, 12)})`);
  }
  const tables = userTables();
  if (JSON.stringify(tables) !== JSON.stringify(schema)) throw new Error(`Schema initialised, but the table list differs from the expected ${schema.length} application tables. Inspect it without resetting the database.`);
  const columns = sql("PRAGMA table_info('atlas_observations')").map((row) => row.name);
  if (!columns.includes("character_data")) throw new Error("Historical character snapshot migration was not confirmed.");
  summary.schemaInitialised = true;
  summary.applicationTables = tables;
}
if (args.has("--check-db")) {
  const info = verifiedInfo();
  summary.databaseJurisdiction = info.jurisdiction;
  summary.runningInRegion = info.running_in_region;
  summary.applicationTables = userTables();
  if (JSON.stringify(summary.applicationTables) !== JSON.stringify(schema)) throw new Error("Production schema differs from the current application schema. Apply missing additive migrations before deploying.");
  // Column-only migrations do not change the table list; the leaderboard reads these columns of 0009.
  const profileColumns = sql("PRAGMA table_info('atlas_profiles')").map((row) => row.name);
  const missing = ["show_item_level", "show_guild"].filter((name) => !profileColumns.includes(name));
  if (missing.length) throw new Error(`atlas_profiles lacks ${missing.join(", ")}. Apply drizzle/0009_ranking_details.sql before deploying.`);
}
if (args.has("--dry-run")) {
  const output = wrangler(["deploy", "--dry-run", "--outdir", path.join(root, ".test-artifacts/production-dry-run")]);
  console.log(output.split(/\r?\n/).filter((line) => /Read \d+ files|Total Upload:|--dry-run:/.test(line)).join("\n"));
  summary.dryRun = "passed";
}
console.log(JSON.stringify(summary, null, 2));

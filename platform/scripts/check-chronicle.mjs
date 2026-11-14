// Checks a journey recording against the rules of the website: `node scripts/check-chronicle.mjs recording.json`.
// Exit code 0 = the website would open it, 1 = it would refuse it (and why), 2 = wrong use.
import { build } from "esbuild";
import { readFileSync, statSync } from "node:fs";

const file = process.argv[2];
if (!file) { console.error("Usage: node scripts/check-chronicle.mjs recording.json"); process.exit(2); }
const bundle = await build({ entryPoints: ["lib/chronicle.ts"], bundle: true, write: false, format: "esm", platform: "node", target: "node22" });
const { parseChronicle, findProblem, countByCategory } = await import("data:text/javascript;base64," + Buffer.from(bundle.outputFiles[0].text).toString("base64"));
let raw;
try { raw = JSON.parse(readFileSync(file, "utf8")); } catch (error) { console.error("NOT JSON:", error.message); process.exit(1); }
const problem = findProblem(raw);
if (problem) { console.error("REJECTED:", problem); process.exit(1); }
const c = parseChronicle(raw);
const bytes = statSync(file).size;
const lines = (c.fights ?? []).reduce((n, f) => n + (f.log?.length ?? 0), 0);
console.log(`OK  ${c.character.name}, ${Math.round(c.duration / 60)} min of play, ${c.zones.length} zones`);
console.log(`    path ${c.path.length} points, events ${c.events.length}, fights ${(c.fights ?? []).length} (${lines} log lines), sessions ${(c.sessions ?? []).length}`);
console.log(`    by category: ${JSON.stringify(countByCategory(c))}`);
console.log(`    file ${(bytes / 1024).toFixed(0)} kB${bytes > 40_000_000 ? "  (TOO BIG: the website refuses files over 40 MB)" : ""}`);
if (!c.fights?.length && c.events.some(e => e.k === "boss" || e.k === "pvp")) console.log("    note: boss/pvp moments without fights: they cannot open a fight window");

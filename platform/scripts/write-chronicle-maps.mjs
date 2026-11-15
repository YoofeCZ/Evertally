// Writes docs/kronika/mapy.json: the map keys a recording may use and the game's uiMapIDs each one stands for, taken from the
// website's own map catalogue. Run it after the catalogue changes (a test fails when the file is out of date):
//   node scripts/write-chronicle-maps.mjs
import { readFileSync, writeFileSync } from "node:fs";

const manifest = JSON.parse(readFileSync("public/media/maps/manifest.json", "utf8"));
const maps = manifest.maps.map(m => ({ key: m.key, name: m.nameEn, uiMapIds: [...m.uiMapIds].sort((a, b) => a - b) })).sort((a, b) => a.key.localeCompare(b.key));
writeFileSync("../docs/kronika/mapy.json", JSON.stringify({ note: "Generated from platform/public/media/maps/manifest.json by platform/scripts/write-chronicle-maps.mjs. Do not edit by hand.", maps }, null, 1) + "\n");
console.log(`wrote ${maps.length} maps`);

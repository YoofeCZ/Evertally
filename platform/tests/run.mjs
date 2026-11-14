import { build } from "esbuild";
import { mkdir, readdir } from "node:fs/promises";
import { spawnSync } from "node:child_process";
await mkdir(".test-artifacts",{recursive:true});
const entries=(await readdir("tests")).filter(name=>name.endsWith(".test.ts")).sort();
await build({entryPoints:entries.map(name=>`tests/${name}`),outdir:".test-artifacts",outExtension:{".js":".mjs"},bundle:true,platform:"node",format:"esm",target:"node22"});
const result=spawnSync(process.execPath,["--test",...entries.map(name=>`.test-artifacts/${name.replace(/\.ts$/,".mjs")}`)],{stdio:"inherit"});
process.exit(result.status??1);

#!/usr/bin/env bash
# Nasadí sestavený web (platform/dist) na Raspberry Pi a restartuje službu evertally.
# Spouštět z PC (Git Bash) po `npm run build`. Secrets (.dev.vars) a databáze na Pi zůstávají.
set -euo pipefail
cd "$(dirname "$0")/../.."

PI=pi@192.168.0.93
KEY="$HOME/.ssh/cw-audit-raspberry_ed25519"
[ -f dist/server/wrangler.json ] || { echo "Chybí dist – nejdřív npm run build"; exit 1; }

tar -czf - -C dist server client | ssh -i "$KEY" -o BatchMode=yes "$PI" 'set -e
cd ~/evertally/app
rm -rf dist.new && mkdir dist.new && tar -xzf - -C dist.new
cp -p dist/server/.dev.vars dist.new/server/.dev.vars
node -e "
const fs=require(\"fs\");const c=JSON.parse(fs.readFileSync(\"dist.new/server/wrangler.json\"));
c.name=\"evertally\";c.d1_databases=[{binding:\"DB\",database_name:\"evertally\",database_id:\"00000000-0000-4000-8000-000000000001\"}];
fs.writeFileSync(\"dist.new/server/wrangler.pi.json\",JSON.stringify(c,null,1));"
rm -rf dist.old && mv dist dist.old && mv dist.new dist
systemctl --user restart evertally.service
for i in $(seq 1 30); do curl -sf -o /dev/null http://127.0.0.1:8790/api/status && break; sleep 2; done
curl -s -o /dev/null -w "status %{http_code}\n" http://127.0.0.1:8790/api/status'

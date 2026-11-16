#!/usr/bin/env bash
# Přenese data z produkční D1 (evertally-production) do SQLite na Raspberry Pi.
# Spouštět z PC (Git Bash) v D:\addon\platform. Produkci jen čte (d1 export).
# Na Pi: zastaví web, zazálohuje stávající databázi, nahraje data, web znovu spustí.
set -euo pipefail
cd "$(dirname "$0")/../.."

PI=pi@192.168.0.93
KEY="$HOME/.ssh/cw-audit-raspberry_ed25519"
SSH=(ssh -i "$KEY" -o BatchMode=yes "$PI")
OUT=".test-artifacts/d1-data-$(date -u +%Y%m%dT%H%M%SZ).sql"
mkdir -p .test-artifacts

export CLOUDFLARE_ACCOUNT_ID=a355311725afbdb07a231531619a4e01 WRANGLER_SEND_METRICS=false
node scripts/prepare-production.mjs >/dev/null 2>&1 || true   # vytvoří dist/server/wrangler.production.json
# Wrangler na Node 25/Windows padá až při ukončení (libuv assert) – rozhoduje, jestli vznikl soubor.
node --import ./scripts/sites-env.mjs node_modules/wrangler/bin/wrangler.js d1 export evertally-production \
  --remote --no-schema --output "$OUT" --config dist/server/wrangler.production.json || true
[ -s "$OUT" ] || { echo "Export se nepovedl (limit D1 ještě neobnoven?)"; exit 1; }
grep -q "INSERT INTO" "$OUT" || { echo "Export neobsahuje data"; exit 1; }
echo "Export: $(grep -c '^INSERT' "$OUT") řádků INSERT, $(du -h "$OUT" | cut -f1)"

scp -i "$KEY" -o BatchMode=yes "$OUT" "$PI:/home/pi/evertally/import.sql"
"${SSH[@]}" 'set -e
systemctl --user stop evertally.service
tar -czf ~/evertally/data-backup-$(date -u +%Y%m%dT%H%M%SZ).tgz -C ~/evertally data
cd ~/evertally/app
WRANGLER_SEND_METRICS=false node_modules/.bin/wrangler d1 execute evertally --local --persist-to ~/evertally/data \
  --config dist/server/wrangler.pi.json --file ~/evertally/import.sql >/tmp/import.log 2>&1 || { tail -20 /tmp/import.log; exit 1; }
systemctl --user start evertally.service; sleep 20
curl -s http://127.0.0.1:8790/api/status | head -c 200; echo'

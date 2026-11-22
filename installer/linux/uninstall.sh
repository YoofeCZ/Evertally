#!/bin/sh
# Removes Evertally Bridge for the current user. Settings and the saved pairing stay unless --purge is given.
set -eu

data="${XDG_DATA_HOME:-$HOME/.local/share}"
config="${XDG_CONFIG_HOME:-$HOME/.config}"
prefix="$data/evertally"

units="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
if [ -f "$units/evertally-bridge.service" ]; then
    systemctl --user disable --now evertally-bridge.service >/dev/null 2>&1 || true
    rm -f "$units/evertally-bridge.service"
    systemctl --user daemon-reload >/dev/null 2>&1 || true
fi

for program in EvertallyBackground Evertally; do
    [ -x "$prefix/$program" ] && "$prefix/$program" --stop >/dev/null 2>&1 || true
done
sleep 1

rm -rf "$prefix"
rm -f "$HOME/.local/bin/Evertally" \
      "$data/applications/evertally.desktop" \
      "$data/icons/hicolor/256x256/apps/evertally.png" \
      "$config/autostart/evertally-background.desktop"

if [ "${1:-}" = "--purge" ]; then
    rm -rf "$config/evertally-sync" "$config/Evertally Sync" "$config/gg.Evertally.Evertally-Sync"
    echo "Settings removed. A device token in the system keyring (service \"Evertally Sync\") can be"
    echo "deleted in your keyring app; disconnect this PC on the website to revoke it."
else
    echo "Evertally Bridge removed. Settings and pairing were kept (use --purge to remove them)."
fi

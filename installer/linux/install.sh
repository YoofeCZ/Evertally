#!/bin/sh
# Installs Evertally Bridge for the current user. No root needed; nothing outside $HOME is touched.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
data="${XDG_DATA_HOME:-$HOME/.local/share}"
prefix="$data/evertally"
bin="$HOME/.local/bin"

for file in Evertally EvertallyBackground evertally.png evertally.desktop.in; do
    [ -f "$here/$file" ] || { echo "Missing $file next to install.sh" >&2; exit 1; }
done

# Ask a running copy to quit (cooperatively, the same way the app does it).
for program in EvertallyBackground Evertally; do
    [ -x "$prefix/$program" ] && "$prefix/$program" --stop >/dev/null 2>&1 || true
done
sleep 1

mkdir -p "$prefix" "$bin" "$data/applications" "$data/icons/hicolor/256x256/apps"
install -m 755 "$here/Evertally" "$prefix/Evertally"
install -m 755 "$here/EvertallyBackground" "$prefix/EvertallyBackground"
install -m 644 "$here/evertally.png" "$data/icons/hicolor/256x256/apps/evertally.png"
sed "s|@EXEC@|$prefix/Evertally|" "$here/evertally.desktop.in" > "$data/applications/evertally.desktop"
ln -sf "$prefix/Evertally" "$bin/Evertally"
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$data/applications" >/dev/null 2>&1 || true

# SteamOS (or --service): there is no tray library, and game mode has no desktop at all. A systemd user
# service keeps the bridge running without an icon in both desktop and game mode, and after a restart.
service=0
if [ "${1:-}" = "--service" ] || { [ -r /etc/os-release ] && grep -q '^ID=steamos' /etc/os-release; }; then
    units="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
    mkdir -p "$units"
    cat > "$units/evertally-bridge.service" <<UNIT
[Unit]
Description=Evertally Bridge (sync with the Evertally website, no tray icon)

[Service]
ExecStart=$prefix/Evertally --headless
ExecStop=$prefix/Evertally --stop
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
UNIT
    systemctl --user daemon-reload
    systemctl --user enable evertally-bridge.service >/dev/null 2>&1
    systemctl --user restart evertally-bridge.service
    service=1
fi

echo "Evertally Bridge installed in $prefix"
echo "Open it from the application menu (Evertally Bridge) or run: $bin/Evertally --connection-settings"
if [ "$service" = 1 ]; then
    echo "It runs in the background as a service (also in game mode): systemctl --user status evertally-bridge"
else
    echo "Then right-click the tray icon > \"Start automatically with WoW\"."
    echo "A tray icon needs an AppIndicator / StatusNotifier host (KDE, XFCE and Cinnamon have one;"
    echo "GNOME needs the \"AppIndicator and KStatusNotifierItem Support\" extension). Without one the"
    echo "bridge runs without an icon; install.sh --service keeps it running in the background."
fi

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

echo "Evertally Bridge installed in $prefix"
echo "Start it from the application menu (Evertally Bridge) or run: $bin/Evertally"
echo "Then right-click the tray icon > \"Start automatically with WoW\"."
echo "A tray icon needs an AppIndicator / StatusNotifier host (KDE, XFCE and Cinnamon have one;"
echo "GNOME needs the \"AppIndicator and KStatusNotifierItem Support\" extension)."

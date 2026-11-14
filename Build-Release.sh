#!/usr/bin/env bash
# Linux and macOS counterpart of Build-Release.ps1: builds the bridge and packages it for this system.
#   ./Build-Release.sh [https://server]      (default: https://evertally.afstudio.dev, or $EVERTALLY_SERVER)
# macOS -> releases/Evertally-<version>-macos-<arch>.zip   (Evertally.app, ad-hoc signed)
# Linux -> releases/Evertally-<version>-linux-<arch>.tar.gz (binaries + install.sh, per user, no root)
set -euo pipefail

server="${1:-${EVERTALLY_SERVER:-https://evertally.afstudio.dev}}"
server="${server%/}"
case "$server" in
    https://*|http://127.0.0.1|http://127.0.0.1:*|http://localhost|http://localhost:*|http://\[::1\]|http://\[::1\]:*) ;;
    *) echo "Server musi pouzivat HTTPS nebo lokalni HTTP." >&2; exit 1 ;;
esac

root=$(cd "$(dirname "$0")" && pwd)
native="$root/desktop/native"
releases="$root/releases"
version=$(sed -n 's/^version = "\(.*\)"/\1/p' "$native/Cargo.toml" | head -1)
arch=$(uname -m)

export EVERTALLY_SERVER="$server"
(cd "$native" && cargo build --release)
bin="$native/target/release"
for program in Evertally EvertallyBackground; do
    [ -x "$bin/$program" ] || { echo "Chybi $bin/$program" >&2; exit 1; }
done
mkdir -p "$releases"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

case "$(uname -s)" in
Darwin)
    app="$stage/Evertally.app"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
    cp "$bin/Evertally" "$bin/EvertallyBackground" "$app/Contents/MacOS/"
    sed "s|@VERSION@|$version|g" "$root/installer/macos/Info.plist.in" > "$app/Contents/Info.plist"
    icons="$stage/Evertally.iconset"
    mkdir -p "$icons"
    source_icon="$root/desktop/src-tauri/icons/icon.png"   # 256 x 256
    for size in 16 32 64 128 256; do
        sips -z "$size" "$size" "$source_icon" --out "$icons/icon_${size}x${size}.png" >/dev/null
    done
    cp "$icons/icon_32x32.png" "$icons/icon_16x16@2x.png"
    cp "$icons/icon_64x64.png" "$icons/icon_32x32@2x.png"
    cp "$icons/icon_256x256.png" "$icons/icon_128x128@2x.png"
    rm "$icons/icon_64x64.png"
    iconutil -c icns "$icons" -o "$app/Contents/Resources/Evertally.icns"
    # Ad-hoc signature: a stable identity for the Keychain and Screen Recording prompts. Distribution
    # outside this Mac additionally needs a Developer ID signature and notarization.
    codesign --force --deep --sign - "$app"
    out="$releases/Evertally-$version-macos-$arch.zip"
    rm -f "$out"
    ditto -c -k --keepParent "$app" "$out"
    ;;
Linux)
    dir="$stage/Evertally"
    mkdir -p "$dir"
    cp "$bin/Evertally" "$bin/EvertallyBackground" "$dir/"
    cp "$root/desktop/src-tauri/icons/icon.png" "$dir/evertally.png"
    cp "$root/installer/linux/evertally.desktop.in" "$root/installer/linux/install.sh" "$root/installer/linux/uninstall.sh" "$dir/"
    out="$releases/Evertally-$version-linux-$arch.tar.gz"
    tar -C "$stage" -czf "$out" Evertally
    ;;
*)
    echo "Tento skript je pro Linux a macOS; na Windows pouzij Build-Release.ps1." >&2
    exit 1
    ;;
esac

if command -v shasum >/dev/null 2>&1; then checksum=$(shasum -a 256 "$out" | cut -d' ' -f1); else checksum=$(sha256sum "$out" | cut -d' ' -f1); fi
echo "$checksum  $(basename "$out")" > "$out.sha256"
echo "Sestaveno pro server: $server"
echo "Balicek: $out"
echo "SHA-256: $checksum"

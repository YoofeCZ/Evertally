"""Build the downloads: the add-on ZIP and the native Evertally app, without user data.

Run `cargo build --release` in `desktop/native/` first to include the newest app.
"""
from pathlib import Path
from io import BytesIO
import hashlib
import json
import tomllib
import zipfile

ROOT = Path(__file__).resolve().parents[1]
NAMES = ("Evertally", "Evertally_Export", "Evertally_Map")
APP = ROOT / "desktop" / "native" / "target" / "release" / "Evertally.exe"
out = ROOT / "releases"
out.mkdir(exist_ok=True)
web = ROOT / "platform" / "public" / "downloads"
web.mkdir(parents=True, exist_ok=True)


def describe(name: str, data: bytes, **extra) -> dict:
    return {"file": name, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(), **extra}


sources = []
for name in NAMES:
    folder = ROOT / "addon" / name
    if not folder.is_dir() or not list(folder.glob("*.toc")):
        raise SystemExit(f"Missing authored add-on: {folder}")
    for item in sorted(folder.rglob("*")):
        if item.is_symlink():
            raise SystemExit(f"Symlink not allowed in distribution: {item}")
        if item.is_file() and item.suffix.lower() in {".lua", ".toc", ".xml", ".md", ".txt", ".tga", ".blp"}:
            sources.append(item)

dest = out / "Evertally.zip"
with zipfile.ZipFile(dest, "w", zipfile.ZIP_DEFLATED) as archive:
    for item in sources:
        archive.write(item, item.relative_to(ROOT / "addon").as_posix())
with zipfile.ZipFile(dest) as archive:
    assert archive.testzip() is None
    for item in sources:
        assert archive.read(item.relative_to(ROOT / "addon").as_posix()) == item.read_bytes()
addon = dest.read_bytes()
(web / "Evertally.zip").write_bytes(addon)
manifest = {"addon": describe("Evertally.zip", addon, files=len(sources))}
folder_manifests = {folder: manifest.copy() for folder in (out, web)}

if APP.is_file():
    app = APP.read_bytes()
    # A Windows executable starts with the "MZ" DOS header.
    if app[:2] != b"MZ":
        raise SystemExit(f"Not a Windows executable: {APP}")
    build_file = out / "app-build.json"
    server = "http://127.0.0.1:5173"
    if build_file.is_file():
        build_info = json.loads(build_file.read_text(encoding="utf-8-sig"))
        if build_info["sha256"] != hashlib.sha256(app).hexdigest():
            raise SystemExit("App build metadata does not match executable; run Build-Release.ps1")
        server = build_info["server"]
    version = tomllib.loads((ROOT / "desktop" / "native" / "Cargo.toml").read_text(encoding="utf-8"))["package"]["version"]
    for folder in (out, web):
        target = folder / "Evertally.exe"
        try:
            # Skip identical copies: a running app keeps its own exe locked.
            if not target.is_file() or target.read_bytes() != app:
                target.write_bytes(app)
        except PermissionError:
            if folder != out:
                raise
            # Packaging never closes the user's app to replace its executable.
            target = folder / f"Evertally-{version}-{hashlib.sha256(app).hexdigest()[:8]}.exe"
            target.write_bytes(app)
            print(f"Running app left untouched; latest build: {target.name}")
        folder_manifests[folder]["app"] = describe(target.name, app, version=version, server=server)
    portable = BytesIO()
    with zipfile.ZipFile(portable, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("Evertally.exe", app)
        background = APP.with_name("EvertallyBackground.exe")
        if background.is_file(): archive.write(background,"EvertallyBackground.exe")
        resources=ROOT/"shared/assets"
        if resources.is_dir():
            for resource in sorted(resources.rglob("*")):
                if resource.is_file(): archive.write(resource,"resources/"+resource.relative_to(resources).as_posix())
        archive.writestr("README.txt", (
            "Evertally pro Windows\n\n"
            "Rozbal oba soubory do vlastni slozky a spust Evertally.exe.\n"
            "Mistni prehled funguje bez weboveho uctu a internetu.\n"
            "Settings: cesta k WoW a adresa tveho weboveho serveru.\n"
            f"Vychozi webova adresa: {server}\n"
            "Existujici konfigurace se pri aktualizaci nemeni.\n"
            "Webove sdileni vyzaduje souhlas v addonu a sparovani v Sync.\n"
            "Hra uklada zmeny pri /reload nebo odhlaseni.\n\n"
            "Pri aktualizaci nejdrive sam zavri predchozi Evertally.\n"
            "Starsimu tray klientovi odpovida EvertallySync.exe.\n"
            "Balicek neobsahuje osobni herni data ani prihlasovaci token.\n"
        ))
    portable_data = portable.getvalue()
    with zipfile.ZipFile(BytesIO(portable_data)) as archive:
        assert archive.testzip() is None
        assert archive.read("Evertally.exe") == app
    # The portable bundle includes every offline resource and exceeds Workers'
    # single-asset limit. The public download is the compact solid installer.
    for folder in (out,):
        (folder / "Evertally-Windows.zip").write_bytes(portable_data)
        folder_manifests[folder]["portable"] = describe("Evertally-Windows.zip", portable_data, version=version)
else:
    print(f"warning: {APP} not built; the app download is missing")

for folder in (out, web):
    setup=out/"EvertallySetup.exe"
    setup_manifest=out/"installer-manifest.json"
    if setup.is_file() and setup_manifest.is_file():
        meta=json.loads(setup_manifest.read_text(encoding="utf-8-sig"))
        data=setup.read_bytes()
        if meta["sha256"]!=hashlib.sha256(data).hexdigest(): raise SystemExit("Installer hash mismatch")
        folder_manifests[folder]["installer"]=meta
        if folder==web:(web/"EvertallySetup.exe").write_bytes(data)
    (folder / "manifest.json").write_text(json.dumps(folder_manifests[folder], indent=2) + "\n", encoding="utf-8")
print(json.dumps(folder_manifests[out]))

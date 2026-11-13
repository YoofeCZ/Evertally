# Evertally Sync

Synchronizační knihovna v Rustu a starší aplikace v systémové liště. Aktuální **nativní desktopové okno** je v `../desktop/native`, používá tuto knihovnu bez feature `tray` a nabízí i místní historii bez webu. Distribuční soubor je `releases/Evertally.exe`; starší `EvertallySync.exe` má pouze ikonu v liště.

## Jak funguje

1. Najde instalace WoW (registr, běžné cesty, `wowPath` v konfiguraci) a hlídá složky `WTF/Account/*/SavedVariables`.
2. Když hra zapíše `Evertally_Export.lua` (`/reload`, odhlášení), počká 3 s, než je soubor dopsaný, a přečte ho vlastním parserem. Parser jen převádí data na JSON a žádný Lua kód nespouští (`src/savedvars.rs`, stejná pravidla jako webový import).
3. Pošle jen události, které ještě neodeslala (`state.json`, podle `producerId:consentEpoch`), v dávkách do 500 událostí a 900 KiB.
4. Párování probíhá jako device flow: aplikace dostane kód, uživatel ho potvrdí na webu přes Discord a vybere oblasti dat. Token se ukládá do Správce pověření Windows.

Při výpadku sítě to zkusí znovu každých 5 minut. Když server export odmítne (vypnutý web export, odvolaný souhlas), čeká na další změnu souboru. Odpojení na webu znamená návrat do stavu „nespárováno“.

## Moduly

| Soubor | Účel |
| --- | --- |
| `savedvars.rs` | Datový parser `SavedVariables` → JSON |
| `forum.rs` | Fórum: odeslání příspěvků napsaných ve hře a zápis `ForumData.lua` vedle addonu |
| `local.rs` | Čtení místní historie a postav z `Evertally.lua`, bez uploadu |
| `wow.rs` | Hledání instalací a exportních souborů |
| `upload.rs` | Co odeslat a rozdělení do dávek |
| `api.rs` | HTTP klient (`ureq`, rustls) pro `/api/device/*` |
| `worker.rs` | Vlákno na pozadí: párování, hlídání, upload |
| `ui.rs` | Ikona v liště a menu (`tray-icon`, `tao`) |
| `platform.rs` | Jedna instance, jazyk Windows, autostart, úložiště tokenu |
| `config.rs` | `config.json`, cesty, log |

## Build

```powershell
cargo test
cargo clippy --all-targets -- -W clippy::pedantic
$env:EVERTALLY_SERVER = "https://<doména>"; cargo build --release
```

Bez `EVERTALLY_SERVER` míří build na lokální vývojový web `http://127.0.0.1:5173`. Adresu jde změnit i v `config.json`; mimo localhost je povolené jen `https://`.

`EVERTALLY_SYNC_NO_BROWSER=1` potlačí otevírání prohlížeče při párování (pro automatické testy).

## Závislosti

Verze ověřené `cargo search` / crates.io 9. 11. 2026, všechny poslední stabilní: `tray-icon` 0.26.1, `tao` 0.37.2, `ureq` 3.5.1, `serde` 1.0.229, `serde_json` 1.0.154, `keyring` 4.2.0, `anyhow` 1.0.104, `thiserror` 2.0.21, `winreg` 0.56.0, `open` 5.4.5, `directories` 6.0.0, `gethostname` 1.1.0, `windows-sys` 0.61.2. `notify` je na 8.2.2: verze 9 je zatím jen release candidate.

//! Recognising the World of Warcraft Forever client by its executable path.
//!
//! Three clients exist: `Wow.exe` on Windows, the native macOS app
//! (`…/_forever_/World of Warcraft.app/Contents/MacOS/World of Warcraft`), and `Wow.exe` under Wine,
//! CrossOver or Whisky on Linux or macOS (whose command line carries a Windows path such as
//! `Z:\home\me\wow\_forever_\Wow.exe`). The comparison works on text and understands both separators.
//! Only process names and command lines are read: never game memory, never input.

use std::path::Path;

/// Last path segment of a Windows or Unix path.
fn file_name(path: &str) -> &str {
    path.rsplit(['/', '\\']).next().unwrap_or(path)
}

/// Lower-cased path segments, without the empty ones and without a leading drive letter (`C:`).
fn segments(path: &str) -> Vec<String> {
    let mut parts: Vec<String> = path
        .split(['/', '\\'])
        .filter(|part| !part.is_empty())
        .map(str::to_lowercase)
        .collect();
    if parts
        .first()
        .is_some_and(|first| first.len() == 2 && first.ends_with(':'))
    {
        parts.remove(0);
    }
    parts
}

/// The install folder an executable belongs to (the folder holding `Wow.exe`, or the one holding the
/// native `World of Warcraft.app` bundle), as lower-cased segments. `None` for any other program.
fn install_dir(exe: &str) -> Option<Vec<String>> {
    let mut parts = segments(exe);
    let name = file_name(exe);
    if name.eq_ignore_ascii_case("Wow.exe") {
        parts.pop();
        return Some(parts);
    }
    if name.eq_ignore_ascii_case("World of Warcraft") {
        // …/World of Warcraft.app/Contents/MacOS/World of Warcraft
        let bundle = parts.len().checked_sub(4)?;
        let tail = &parts[bundle..];
        if tail[0] == "world of warcraft.app" && tail[1] == "contents" && tail[2] == "macos" {
            parts.truncate(bundle);
            return Some(parts);
        }
    }
    None
}

/// True for the Forever client: `Wow.exe` or the native macOS app inside a `_forever_` folder, or in
/// the configured WoW folder (or its `_forever_` subfolder).
///
/// Under Wine the configured folder is a Unix path while the process reports a Windows path, so a
/// path that ends the same way (`C:\Games\WoW` against `…/drive_c/Games/WoW`) matches as well; at
/// least two segments must agree so that a lone `WoW` folder elsewhere is not taken for it.
#[must_use]
pub fn is_forever_path(exe: &str, configured: Option<&Path>) -> bool {
    let Some(dir) = install_dir(exe) else {
        return false;
    };
    if dir.last().is_some_and(|name| name == "_forever_") {
        return true;
    }
    let Some(root) = configured.map(|root| root.to_string_lossy().into_owned()) else {
        return false;
    };
    let mut root = segments(&root);
    if root.last().is_some_and(|name| name == "wow.exe") {
        root.pop();
    }
    if root.is_empty() || dir.is_empty() {
        return false;
    }
    let mut forever = root.clone();
    forever.push("_forever_".to_owned());
    dir == root
        || dir == forever
        || (dir.len() >= 2 && (root.ends_with(&dir) || forever.ends_with(&dir)))
}

#[cfg(unix)]
mod processes {
    use super::{file_name, is_forever_path};
    use std::{collections::BTreeSet, path::Path};
    use sysinfo::{ProcessRefreshKind, ProcessesToUpdate, System, UpdateKind};

    /// Executable names of the game clients that make an addon update wait.
    const GAME_NAMES: [&str; 5] = [
        "wow.exe",
        "wowclassic.exe",
        "wowclassicb.exe",
        "wowclassicera.exe",
        "world of warcraft",
    ];

    /// `None` when the operating system refuses to list processes.
    fn snapshot() -> Option<System> {
        let mut system = System::new().ok()?;
        system.refresh_processes_specifics(
            ProcessesToUpdate::All,
            true,
            ProcessRefreshKind::nothing()
                .with_cmd(UpdateKind::Always)
                .with_exe(UpdateKind::Always),
        );
        Some(system)
    }

    /// Arguments that can name the game executable. Wine rewrites its command line to the Windows
    /// path of the program it runs; the native executable path is the fallback.
    fn candidates(process: &sysinfo::Process) -> Vec<String> {
        let mut found: Vec<String> = process
            .cmd()
            .iter()
            .map(|arg| arg.to_string_lossy().into_owned())
            .collect();
        if let Some(exe) = process.exe() {
            found.push(exe.to_string_lossy().into_owned());
        }
        found
    }

    /// Process ids of running Forever clients.
    #[must_use]
    pub fn forever_processes(configured: Option<&Path>) -> BTreeSet<u32> {
        let Some(system) = snapshot() else {
            return BTreeSet::new();
        };
        system
            .processes()
            .iter()
            .filter(|(_, process)| {
                candidates(process)
                    .iter()
                    .any(|path| is_forever_path(path, configured))
            })
            .map(|(pid, _)| pid.as_u32())
            .collect()
    }

    /// Whether any WoW client runs (an addon update then asks the player to restart the game).
    #[must_use]
    pub fn game_running() -> bool {
        let Some(system) = snapshot() else {
            return false;
        };
        system.processes().values().any(|process| {
            let name = process.name().to_string_lossy().to_lowercase();
            GAME_NAMES.contains(&name.as_str())
                || candidates(process)
                    .iter()
                    .any(|arg| GAME_NAMES.contains(&file_name(arg).to_lowercase().as_str()))
        })
    }
}

#[cfg(unix)]
pub use processes::{forever_processes, game_running};

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_forever_or_the_explicit_install_is_matched() {
        assert!(is_forever_path(r"D:\World of Warcraft\_forever_\Wow.exe", None));
        assert!(is_forever_path("/home/me/wow/_forever_/Wow.exe", None));
        assert!(!is_forever_path(r"D:\World of Warcraft\_retail_\Wow.exe", None));
        assert!(!is_forever_path(r"D:\Game\WowVoiceProxy.exe", Some(Path::new(r"D:\Game"))));
        assert!(is_forever_path(r"D:\Custom\Wow.exe", Some(Path::new(r"D:\Custom"))));
        assert!(is_forever_path(r"d:\custom\wow.EXE", Some(Path::new(r"D:\Custom\Wow.exe"))));
        assert!(is_forever_path(
            r"D:\Custom\_forever_\Wow.exe",
            Some(Path::new(r"D:\Custom"))
        ));
    }

    #[test]
    fn a_wine_process_matches_the_unix_path_of_the_configured_folder() {
        let root = Path::new("/home/me/Games/wow");
        // `Z:` maps the whole Unix tree.
        assert!(is_forever_path(r"Z:\home\me\Games\wow\Wow.exe", Some(root)));
        // `C:` is the prefix's `drive_c`.
        let prefix = Path::new("/home/me/.wine/drive_c/Games/WoW");
        assert!(is_forever_path(r"C:\Games\WoW\Wow.exe", Some(prefix)));
        assert!(is_forever_path(r"C:\Games\WoW\_forever_\Wow.exe", Some(prefix)));
        // A different folder, or a single shared segment, is not the configured install.
        assert!(!is_forever_path(r"C:\Games\Other\Wow.exe", Some(prefix)));
        assert!(!is_forever_path(
            r"C:\WoW\Wow.exe",
            Some(Path::new("/home/me/.wine/drive_c/Games/WoW"))
        ));
        assert!(!is_forever_path(r"Z:\home\me\Games\wow\Wow.exe", None));
    }

    #[test]
    fn the_native_macos_client_is_matched_by_its_app_bundle() {
        let app = "/Applications/World of Warcraft/_forever_/World of Warcraft.app/Contents/MacOS/World of Warcraft";
        assert!(is_forever_path(app, None));
        // Another flavor of the same game is not Forever.
        assert!(!is_forever_path(
            "/Applications/World of Warcraft/_anniversary_/World of Warcraft.app/Contents/MacOS/World of Warcraft",
            None
        ));
        // …unless the player explicitly chose that folder.
        let other = "/Applications/World of Warcraft/_anniversary_/World of Warcraft.app/Contents/MacOS/World of Warcraft";
        assert!(is_forever_path(other, Some(Path::new("/Applications/World of Warcraft/_anniversary_"))));
        assert!(is_forever_path(app, Some(Path::new("/Applications/World of Warcraft"))));
        // The Battle.net launcher and loose binaries named alike are not the game.
        assert!(!is_forever_path(
            "/Applications/World of Warcraft/_forever_/World of Warcraft Launcher.app/Contents/MacOS/World of Warcraft Launcher",
            None
        ));
        assert!(!is_forever_path("/usr/local/bin/World of Warcraft", None));
        assert!(!is_forever_path("/x/_forever_/Other.app/Contents/MacOS/World of Warcraft", None));
    }

    #[test]
    fn unrelated_names_never_match() {
        assert!(!is_forever_path("", None));
        assert!(!is_forever_path("/usr/bin/wine64-preloader", Some(Path::new("/usr/bin"))));
        assert!(!is_forever_path("/home/me/wow/_forever_", None));
    }
}

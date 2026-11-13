//! Finds `Evertally_Export.lua` files in World of Warcraft installations.

use std::path::{Path, PathBuf};

/// The file written by the `Evertally_Export` addon (account-wide saved variable).
pub const EXPORT_FILE: &str = "Evertally_Export.lua";
/// The single variable that file may contain.
pub const EXPORT_VARIABLE: &str = "EvertallyExportDB";

/// Install folders worth checking, most specific first.
#[must_use]
pub fn candidate_roots(configured: Option<&Path>) -> Vec<PathBuf> {
    let mut roots = Vec::new();
    if let Some(path) = configured {
        roots.push(path.to_path_buf());
    }
    if let Some(path) = registry_install_path() {
        // InstallPath usually points at a flavor folder such as `_retail_`.
        if let Some(parent) = path.parent() {
            roots.push(parent.to_path_buf());
        }
        roots.push(path);
    }
    for drive in b'C'..=b'Z' {
        let drive = format!("{}:\\", drive as char);
        for suffix in [
            "World of Warcraft",
            r"Program Files (x86)\World of Warcraft",
            r"Program Files\World of Warcraft",
            r"Games\World of Warcraft",
        ] {
            roots.push(Path::new(&drive).join(suffix));
        }
    }
    let mut unique = Vec::new();
    for root in roots {
        if root.is_dir() && !unique.contains(&root) {
            unique.push(root);
        }
    }
    unique
}

#[cfg(windows)]
fn registry_install_path() -> Option<PathBuf> {
    use winreg::RegKey;
    use winreg::enums::HKEY_LOCAL_MACHINE;
    let key = RegKey::predef(HKEY_LOCAL_MACHINE)
        .open_subkey(r"SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft")
        .ok()?;
    let value: String = key.get_value("InstallPath").ok()?;
    let trimmed = value.trim_end_matches(['\\', '/']);
    (!trimmed.is_empty()).then(|| PathBuf::from(trimmed))
}

#[cfg(not(windows))]
fn registry_install_path() -> Option<PathBuf> {
    None
}

/// Every `WTF/Account/<account>/SavedVariables` folder below the roots, including
/// flavor folders like `_forever_` and `_retail_`. The export file may not exist yet.
#[must_use]
pub fn saved_variables_dirs(roots: &[PathBuf]) -> Vec<PathBuf> {
    let mut dirs = Vec::new();
    for root in roots {
        let mut flavors = vec![root.clone()];
        if let Ok(entries) = std::fs::read_dir(root) {
            for entry in entries.flatten() {
                let name = entry.file_name();
                let name = name.to_string_lossy();
                if name.len() > 2
                    && name.starts_with('_')
                    && name.ends_with('_')
                    && entry.path().is_dir()
                {
                    flavors.push(entry.path());
                }
            }
        }
        for flavor in flavors {
            let Ok(accounts) = std::fs::read_dir(flavor.join("WTF").join("Account")) else {
                continue;
            };
            for account in accounts.flatten() {
                let dir = account.path().join("SavedVariables");
                if dir.is_dir() && !dirs.contains(&dir) {
                    dirs.push(dir);
                }
            }
        }
    }
    dirs
}

/// Whether a changed path is the export file (case-insensitive, like Windows).
#[must_use]
pub fn is_export_file(path: &Path) -> bool {
    path.file_name()
        .is_some_and(|name| name.to_string_lossy().eq_ignore_ascii_case(EXPORT_FILE))
}

/// The main SavedVariables file contains the forum outbox.
#[must_use]
pub fn is_forum_file(path: &Path) -> bool {
    path.file_name()
        .is_some_and(|name| name.to_string_lossy().eq_ignore_ascii_case("Evertally.lua"))
}

#[cfg(test)]
mod tests {
    use super::*;

    struct TempDir(PathBuf);
    impl Drop for TempDir {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }

    #[test]
    fn finds_account_folders_in_flavor_directories() {
        let root = std::env::temp_dir().join(format!("evertally-wow-test-{}", std::process::id()));
        let _guard = TempDir(root.clone());
        for path in [
            "_forever_/WTF/Account/123#1/SavedVariables",
            "_retail_/WTF/Account/ACC/SavedVariables",
            "_forever_/WTF/Account/123#1/Realm/Char/SavedVariables",
            "Data",
        ] {
            std::fs::create_dir_all(root.join(path)).expect("create test dirs");
        }
        let mut dirs = saved_variables_dirs(std::slice::from_ref(&root));
        dirs.sort();
        assert_eq!(
            dirs,
            vec![
                root.join("_forever_/WTF/Account/123#1/SavedVariables"),
                root.join("_retail_/WTF/Account/ACC/SavedVariables")
            ]
        );
    }

    #[test]
    fn export_file_match_ignores_case_and_other_files() {
        assert!(is_export_file(Path::new(
            r"C:\x\SavedVariables\evertally_export.LUA"
        )));
        assert!(!is_export_file(Path::new(
            r"C:\x\SavedVariables\Evertally.lua"
        )));
        assert!(!is_export_file(Path::new(
            r"C:\x\SavedVariables\Evertally_Export.lua.bak"
        )));
        assert!(is_forum_file(Path::new(
            r"C:\x\SavedVariables\evertally.LUA"
        )));
        assert!(!is_forum_file(Path::new(
            r"C:\x\SavedVariables\Evertally.lua.bak"
        )));
        assert!(!is_forum_file(Path::new(
            r"C:\x\SavedVariables\Evertally_Export.lua"
        )));
    }
}

//! The app's own choices beside the connection (`prefs.json` in the settings folder): whether updates of the add-on
//! and of the app download by themselves, and whether the first-run guide was gone through.

use std::fs;
use std::path::Path;

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

pub const FILE: &str = "prefs.json";

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Prefs {
    /// Download and install new versions of the add-on and of the app by themselves (the tray's "Check for updates"
    /// works either way).
    pub auto_update: bool,
    /// The first-run guide was finished or skipped.
    pub onboarded: bool,
}

impl Default for Prefs {
    fn default() -> Self {
        Self { auto_update: true, onboarded: true }
    }
}

/// The saved choices. Without `prefs.json`: updates on, and the guide counts as done when the app ran before (its
/// `config.json` is there), so players who had the app before it got the guide do not see it.
#[must_use]
pub fn load(dir: &Path) -> Prefs {
    match fs::read_to_string(dir.join(FILE)) {
        Ok(text) => serde_json::from_str(&text).unwrap_or_default(),
        Err(_) => Prefs { onboarded: dir.join("config.json").is_file(), ..Prefs::default() },
    }
}

/// Writes the choices (a temporary file renamed over the old one).
///
/// # Errors
/// The settings folder cannot be written.
pub fn save(dir: &Path, prefs: &Prefs) -> Result<()> {
    let path = dir.join(FILE);
    let temp = path.with_extension("json.tmp");
    fs::write(&temp, serde_json::to_vec_pretty(prefs)?).with_context(|| format!("write {}", temp.display()))?;
    fs::rename(&temp, &path).with_context(|| format!("write {}", path.display()))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dir(name: &str) -> std::path::PathBuf {
        let dir = std::env::temp_dir().join(format!("evertally-prefs-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn a_new_install_gets_the_guide_and_updates_on() {
        let d = dir("new");
        assert_eq!(load(&d), Prefs { auto_update: true, onboarded: false });
        fs::remove_dir_all(&d).unwrap();
    }

    #[test]
    fn an_app_that_ran_before_skips_the_guide() {
        let d = dir("old");
        fs::write(d.join("config.json"), "{}").unwrap();
        assert_eq!(load(&d), Prefs { auto_update: true, onboarded: true });
        fs::remove_dir_all(&d).unwrap();
    }

    #[test]
    fn choices_are_kept_and_a_missing_field_takes_its_default() {
        let d = dir("kept");
        save(&d, &Prefs { auto_update: false, onboarded: true }).unwrap();
        assert_eq!(load(&d), Prefs { auto_update: false, onboarded: true });
        fs::write(d.join(FILE), r#"{"onboarded":false}"#).unwrap();
        assert_eq!(load(&d), Prefs { auto_update: true, onboarded: false });
        fs::remove_dir_all(&d).unwrap();
    }
}

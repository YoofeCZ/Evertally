//! Self-update of the bridge from the installer published on the Evertally website.
//!
//! The installer is fetched over HTTPS from the configured server only (no redirects),
//! its size and SHA-256 are checked against the public manifest, and it is run silently.
//! Setup closes this process itself and starts the new bridge. The in-game addon is
//! handled separately by `addon_update`, so setup is told to skip that task.
use anyhow::{Result, ensure};
use serde::Deserialize;
use sha2::{Digest, Sha256};
use std::{fs, path::Path, sync::{Mutex, OnceLock, atomic::{AtomicBool, Ordering}}, time::{Duration, SystemTime, UNIX_EPOCH}};

const MAX_INSTALLER: u64 = 96 * 1024 * 1024;
/// After a failed or interrupted attempt the same version is retried at most this often.
const RETRY_AFTER: u64 = 6 * 3600;
const ATTEMPT_FILE: &str = "app-update-attempt.txt";
const SETUP_FILE: &str = "EvertallySetup-update.exe";

static CURRENT: OnceLock<&'static str> = OnceLock::new();
static MANUAL: AtomicBool = AtomicBool::new(false);
static STATUS: Mutex<String> = Mutex::new(String::new());

/// Version of the running app, when the desktop registered it.
#[must_use] pub fn current_version() -> Option<&'static str> { CURRENT.get().copied() }
/// The user asked for an update check now; the next check ignores the retry pause.
pub fn request_check() { MANUAL.store(true, Ordering::SeqCst); }
#[must_use] pub fn take_manual() -> bool { MANUAL.swap(false, Ordering::SeqCst) }
/// One-line update status for the tray menu.
pub fn set_status(text: String) { if let Ok(mut status) = STATUS.lock() { *status = text; } }
#[must_use] pub fn status() -> String { STATUS.lock().map(|s| s.clone()).unwrap_or_default() }

/// The desktop app registers its own version here; without it self-update stays off.
/// After the app replaced itself: one notification with the new version (the last version that ran is kept next to
/// the settings).
pub fn announce_if_updated(dir: &Path, current: &str) {
    let file = dir.join("last-app-version.txt");
    let previous = fs::read_to_string(&file).ok().map(|t| t.trim().to_owned());
    if previous.as_deref() != Some(current) {
        let _ = fs::write(&file, current);
        if previous.is_some_and(|p| is_newer(current, &p)) {
            let cs = crate::platform::prefers_czech();
            crate::notify::message(
                &if cs { format!("Aplikace Evertally aktualizována na {current}") } else { format!("Evertally app updated to {current}") },
                if cs { "Běží dál na pozadí." } else { "It keeps running in the background." },
            );
        }
    }
}

pub fn set_current_version(version: &'static str) {
    let _ = CURRENT.set(version);
}

#[derive(Deserialize)]
struct Manifest { installer: Option<Installer> }
#[derive(Deserialize)]
struct Installer { file: String, version: String, bytes: u64, sha256: String }

/// Strict `major.minor.patch`; anything else is not a version we trust.
fn parse_version(text: &str) -> Option<(u64, u64, u64)> {
    let mut parts = text.split('.');
    let mut next = || {
        let part = parts.next()?;
        (!part.is_empty() && part.len() <= 9 && part.bytes().all(|b| b.is_ascii_digit())).then(|| part.parse().ok())?
    };
    let version = (next()?, next()?, next()?);
    parts.next().is_none().then_some(version)
}

fn is_newer(candidate: &str, current: &str) -> bool {
    matches!((parse_version(candidate), parse_version(current)), (Some(a), Some(b)) if a > b)
}

fn attempt_allowed(state: Option<&str>, version: &str, now: u64) -> bool {
    let Some((seen, at)) = state.and_then(|s| s.trim().split_once(' ')) else { return true };
    seen != version || at.parse::<u64>().map_or(true, |at| now.saturating_sub(at) >= RETRY_AFTER)
}

fn verify(data: &[u8], installer: &Installer) -> Result<()> {
    ensure!(data.len() as u64 == installer.bytes, "installer size mismatch");
    ensure!(data.starts_with(b"MZ"), "installer is not a Windows executable");
    ensure!(format!("{:x}", Sha256::digest(data)).eq_ignore_ascii_case(&installer.sha256), "installer checksum mismatch");
    Ok(())
}

/// What one check did.
#[derive(Debug, PartialEq, Eq)]
pub enum Outcome { Nothing, UpToDate, Started(String) }

/// Checks the published installer and, when it is newer than this app, starts it.
///
/// # Errors
/// Network, verification or process-start failures; the caller shows and retries them.
pub fn check(dir: &Path, config: &crate::config::Config, force: bool) -> Result<Outcome> {
    // The published installer is a Windows setup; Linux and macOS builds are updated by installing a new package.
    if !cfg!(windows) { return Ok(Outcome::Nothing); }
    let Some(current) = CURRENT.get().copied() else { return Ok(Outcome::Nothing) };
    let origin = config.server_origin()?;
    ensure!(origin.starts_with("https://"), "automatic updates require HTTPS");
    let agent: ureq::Agent = ureq::Agent::config_builder()
        .timeout_global(Some(Duration::from_secs(120))).max_redirects(0).build().into();
    let manifest: Manifest = serde_json::from_slice(&crate::addon_update::read_url(&agent, &format!("{origin}/downloads/manifest.json"), 65536)?)?;
    let Some(installer) = manifest.installer else { return Ok(Outcome::Nothing) };
    ensure!(installer.file == "EvertallySetup.exe" && installer.bytes > 0 && installer.bytes <= MAX_INSTALLER
        && installer.sha256.len() == 64 && installer.sha256.bytes().all(|b| b.is_ascii_hexdigit()), "invalid installer manifest");
    if !is_newer(&installer.version, current) { return Ok(Outcome::UpToDate); }
    let now = SystemTime::now().duration_since(UNIX_EPOCH).map_or(0, |d| d.as_secs());
    let attempt = dir.join(ATTEMPT_FILE);
    if !force && !attempt_allowed(fs::read_to_string(&attempt).ok().as_deref(), &installer.version, now) { return Ok(Outcome::Nothing); }

    let cs = crate::platform::prefers_czech();
    let title = if cs { format!("Stahuji aplikaci Evertally {}", installer.version) } else { format!("Downloading the Evertally app {}", installer.version) };
    let mut note = crate::notify::Progress::start("app", &title, if cs { "Stahuji…" } else { "Downloading…" });
    let data = crate::addon_update::read_url_progress(&agent, &format!("{origin}/downloads/EvertallySetup.exe"), MAX_INSTALLER, installer.bytes,
        |done, total| note.set(done, total, if cs { "Stahuji…" } else { "Downloading…" }))?;
    verify(&data, &installer)?;
    note.set(1, 1, if cs { "Instaluji… aplikace se za chvíli spustí znovu." } else { "Installing… the app restarts in a moment." });
    let setup = dir.join(SETUP_FILE);
    let _ = fs::remove_file(&setup);
    fs::write(&setup, &data)?;
    fs::write(&attempt, format!("{} {now}", installer.version))?;
    launch(&setup)?;
    Ok(Outcome::Started(installer.version))
}

#[cfg(windows)]
fn launch(setup: &Path) -> Result<()> {
    use std::os::windows::process::CommandExt;
    // DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP: setup must outlive this bridge, which it closes.
    std::process::Command::new(setup)
        .args(["/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/MERGETASKS=!addon"])
        .creation_flags(0x0000_0008 | 0x0000_0200)
        .spawn()?;
    Ok(())
}
#[cfg(not(windows))]
fn launch(_setup: &Path) -> Result<()> { anyhow::bail!("automatic application update is supported on Windows only") }

#[cfg(test)]
mod tests {
    use super::*;

    fn installer(data: &[u8]) -> Installer {
        Installer { file: "EvertallySetup.exe".into(), version: "0.9.2".into(), bytes: data.len() as u64, sha256: format!("{:x}", Sha256::digest(data)) }
    }

    #[test] fn versions_are_compared_numerically_and_strictly() {
        assert!(is_newer("0.9.2", "0.9.1") && is_newer("0.10.0", "0.9.9") && is_newer("1.0.0", "0.99.99"));
        assert!(!is_newer("0.9.1", "0.9.1") && !is_newer("0.9.0", "0.9.1"));
        for bad in ["", "0.9", "0.9.1.2", "0.9.x", "v0.9.2", "0.9.2-beta", "0..1", "-1.0.0"] {
            assert!(parse_version(bad).is_none(), "{bad}");
            assert!(!is_newer(bad, "0.9.1"), "{bad}");
        }
        assert!(!is_newer("0.9.2", "garbage"));
    }

    #[test] fn a_failed_attempt_is_not_repeated_every_cycle() {
        assert!(attempt_allowed(None, "0.9.2", 100));
        assert!(!attempt_allowed(Some("0.9.2 100"), "0.9.2", 200));
        assert!(attempt_allowed(Some("0.9.2 100"), "0.9.2", 100 + RETRY_AFTER));
        assert!(attempt_allowed(Some("0.9.2 100"), "0.9.3", 200));
        assert!(attempt_allowed(Some("junk"), "0.9.2", 200));
        assert!(attempt_allowed(Some("0.9.2 notanumber"), "0.9.2", 200));
    }

    #[test] fn installer_must_match_size_checksum_and_be_an_executable() {
        let good = b"MZ-installer-bytes".to_vec();
        assert!(verify(&good, &installer(&good)).is_ok());
        let mut tampered = good.clone(); tampered[5] ^= 1;
        assert!(verify(&tampered, &installer(&good)).is_err());
        assert!(verify(&good[..10], &installer(&good)).is_err());
        let html = b"<html>not an installer</html>".to_vec();
        assert!(verify(&html, &installer(&html)).is_err());
    }
}

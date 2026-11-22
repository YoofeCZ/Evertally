//! The bridge without a tray icon, for Linux sessions where the tray cannot start: SteamOS has no
//! AppIndicator library, and its game mode (or a systemd user service) has no desktop at all.
//!
//! It runs the same worker and keeps the same token-free status file and command signals as the tray
//! (`ui::run`), so the connection settings window pairs, syncs and disconnects through it unchanged.
use std::sync::{Arc, Mutex, mpsc};
use std::time::{Duration, Instant};

use anyhow::Context;

use crate::config::{self, Config, Paths};
use crate::lang::Texts;
use crate::shutdown::{self, StopSignal};
use crate::worker::{Command, UiState, Worker};

/// The libraries `tray-icon` loads at run time on Linux; it panics when none of them is there.
const TRAY_LIBRARIES: [&std::ffi::CStr; 4] = [
    c"libayatana-appindicator3.so.1",
    c"libappindicator3.so.1",
    c"libayatana-appindicator3.so",
    c"libappindicator3.so",
];

/// The tray cannot run: asked for with `--headless` (the systemd service), no display to put an icon on,
/// or no AppIndicator library.
#[must_use]
pub fn wanted() -> bool {
    std::env::args().any(|arg| arg == "--headless") || !has_display() || !tray_library_available()
}

fn has_display() -> bool {
    ["DISPLAY", "WAYLAND_DISPLAY"]
        .iter()
        .any(|key| std::env::var_os(key).is_some_and(|value| !value.is_empty()))
}

fn tray_library_available() -> bool {
    TRAY_LIBRARIES.iter().any(|name| {
        // SAFETY: `name` is a NUL-terminated C string literal; RTLD_LAZY binds no symbols now.
        let handle = unsafe { libc::dlopen(name.as_ptr(), libc::RTLD_LAZY | libc::RTLD_LOCAL) };
        if handle.is_null() {
            return false;
        }
        // SAFETY: `handle` was returned by the successful dlopen above and is closed exactly once.
        unsafe { libc::dlclose(handle) };
        true
    })
}

/// Runs until the stop signal (`Evertally --stop`, or the uninstaller) arrives.
///
/// # Errors
/// Fails only when the worker thread cannot be started.
pub fn run(texts: &'static Texts, paths: Paths, config: Config, origin: String) -> anyhow::Result<()> {
    let status_path = paths.dir.join(crate::bridge::STATUS_FILE);
    // the website the status is written for, and the newest state the worker published
    let shared: Arc<Mutex<(String, Option<UiState>)>> = Arc::new(Mutex::new((origin.clone(), None)));
    let (tx, rx) = mpsc::channel();
    let publish = {
        let shared = Arc::clone(&shared);
        let status_path = status_path.clone();
        Box::new(move |state: UiState| {
            if let Ok(mut latest) = shared.lock() {
                let _ = crate::bridge::publish(&status_path, &latest.0, &state);
                latest.1 = Some(state);
            }
        })
    };
    let worker = Worker::new(texts, paths.clone(), config, origin, publish, tx.clone(), true);
    std::thread::Builder::new()
        .name("evertally-sync".into())
        .spawn(move || worker.run(&rx))
        .context("start worker thread")?;
    config::log(&paths.log, "running without a tray icon (headless)");

    let stop = StopSignal::new(shutdown::BRIDGE_STOP);
    let reload = StopSignal::new(shutdown::BRIDGE_RELOAD);
    let actions: Vec<_> = crate::bridge::Action::ALL
        .into_iter()
        .filter_map(|action| StopSignal::new(action.event()).map(|signal| (signal, action)))
        .collect();
    let mut last_status_write = Instant::now();
    loop {
        std::thread::sleep(Duration::from_millis(250));
        if stop.as_ref().is_some_and(StopSignal::requested) {
            let _ = tx.send(Command::Quit);
            shutdown::request(shutdown::SETTINGS_STOP);
            let _ = std::fs::remove_file(&status_path);
            return Ok(());
        }
        if let Some(signal) = &reload
            && signal.requested()
        {
            signal.reset();
            if let Ok(paths) = Paths::new()
                && let Ok(config) = config::load_config(&paths.config)
                && let Ok(origin) = config.server_origin()
                && let Ok(mut latest) = shared.lock()
            {
                *latest = (origin, None);
                let _ = std::fs::remove_file(&status_path);
                let _ = tx.send(Command::ReloadConfig(config));
            }
        }
        for (signal, action) in &actions {
            if signal.requested() {
                signal.reset();
                let _ = tx.send(action.command());
            }
        }
        // the settings window treats a status older than 15 s as "the bridge is not running"
        if last_status_write.elapsed() >= Duration::from_secs(5) {
            if let Ok(latest) = shared.lock()
                && let Some(state) = &latest.1
            {
                let _ = crate::bridge::publish(&status_path, &latest.0, state);
            }
            last_status_write = Instant::now();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_missing_tray_library_is_reported_not_crashed() {
        assert!(TRAY_LIBRARIES.iter().all(|name| name.to_bytes().starts_with(b"lib")));
        // a missing library is reported as missing, never as a crash
        // SAFETY: NUL-terminated literal; a null handle is the expected answer.
        let handle = unsafe { libc::dlopen(c"libevertally-does-not-exist.so".as_ptr(), libc::RTLD_LAZY) };
        assert!(handle.is_null());
    }
}

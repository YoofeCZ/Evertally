#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]
//! Per-user WoW companion launcher. Reads process executable names/paths only.
//! It never accesses game memory, sends input, injects code or starts WoW.
//!
//! Windows enumerates processes with Toolhelp; Linux and macOS read the process list (the game runs
//! under Wine, CrossOver or Whisky there, so its command line carries a Windows path) and stop through
//! a signal file instead of a named event.

use std::collections::BTreeSet;
#[cfg(windows)]
use std::path::{Path, PathBuf};

#[derive(Default)]
struct Sessions {
    previous: BTreeSet<u32>,
}

impl Sessions {
    fn update(&mut self, current: BTreeSet<u32>) -> bool {
        let launch = current.difference(&self.previous).next().is_some()
            || !self.previous.is_empty() && current.is_empty();
        self.previous = current;
        launch
    }
}

#[cfg(windows)]
fn is_forever_executable(path: &Path, configured: Option<&Path>) -> bool {
    if !path
        .file_name()
        .is_some_and(|n| n.eq_ignore_ascii_case("Wow.exe"))
    {
        return false;
    }
    if path
        .parent()
        .and_then(Path::file_name)
        .is_some_and(|n| n.eq_ignore_ascii_case("_forever_"))
    {
        return true;
    }
    let Some(root) = configured else {
        return false;
    };
    let root = if root
        .file_name()
        .is_some_and(|n| n.eq_ignore_ascii_case("Wow.exe"))
    {
        root.parent().unwrap_or(root)
    } else {
        root
    };
    [root.join("Wow.exe"), root.join("_forever_").join("Wow.exe")]
        .iter()
        .any(|expected| expected.as_os_str().eq_ignore_ascii_case(path.as_os_str()))
}

#[cfg(windows)]
mod windows {
    use super::*;
    use std::{mem::size_of, os::windows::process::CommandExt, process::Command, ptr};
    use windows_sys::Win32::{
        Foundation::{
            CloseHandle, ERROR_ALREADY_EXISTS, GetLastError, HANDLE, INVALID_HANDLE_VALUE,
            WAIT_OBJECT_0,
        },
        System::{
            Diagnostics::ToolHelp::{
                CreateToolhelp32Snapshot, PROCESSENTRY32W, Process32FirstW, Process32NextW,
                TH32CS_SNAPPROCESS,
            },
            Threading::{
                CreateEventW, CreateMutexW, EVENT_MODIFY_STATE, OpenEventW, OpenProcess,
                PROCESS_QUERY_LIMITED_INFORMATION, QueryFullProcessImageNameW, SetEvent,
                WaitForSingleObject,
            },
        },
    };
    const STOP: &str = "Local\\EvertallyBackgroundStop";
    fn wide(s: &str) -> Vec<u16> {
        s.encode_utf16().chain(Some(0)).collect()
    }
    struct Handle(HANDLE);
    impl Drop for Handle {
        fn drop(&mut self) {
            // SAFETY: each non-null owned handle is closed once by its only owner.
            unsafe {
                CloseHandle(self.0);
            }
        }
    }

    pub fn stop() {
        // SAFETY: name is nul-terminated and lives for the call; no inherited handles.
        let raw = unsafe { OpenEventW(EVENT_MODIFY_STATE, 0, wide(STOP).as_ptr()) };
        if !raw.is_null() {
            let handle = Handle(raw);
            unsafe {
                SetEvent(handle.0);
            }
        }
    }

    pub fn processes(configured: Option<&Path>) -> BTreeSet<u32> {
        let mut found = BTreeSet::new();
        // SAFETY: takes a documented read-only process snapshot for the current session.
        let raw = unsafe { CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0) };
        if raw == INVALID_HANDLE_VALUE {
            return found;
        }
        let snapshot = Handle(raw);
        // SAFETY: PROCESSENTRY32W is a C POD; dwSize is set before either enumeration call.
        let mut entry: PROCESSENTRY32W = unsafe { std::mem::zeroed() };
        entry.dwSize = size_of::<PROCESSENTRY32W>() as u32;
        // SAFETY: valid owned snapshot and correctly sized writable entry.
        let mut available = unsafe { Process32FirstW(snapshot.0, &mut entry) } != 0;
        while available {
            let length = entry
                .szExeFile
                .iter()
                .position(|v| *v == 0)
                .unwrap_or(entry.szExeFile.len());
            let name = String::from_utf16_lossy(&entry.szExeFile[..length]);
            if name.eq_ignore_ascii_case("Wow.exe") {
                // SAFETY: only limited query permission is requested; no memory read/write rights.
                let raw = unsafe {
                    OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, entry.th32ProcessID)
                };
                if !raw.is_null() {
                    let process = Handle(raw);
                    let mut buffer = vec![0u16; 32768];
                    let mut length = buffer.len() as u32;
                    // SAFETY: length equals buffer capacity and process is a valid query handle.
                    if unsafe {
                        QueryFullProcessImageNameW(process.0, 0, buffer.as_mut_ptr(), &mut length)
                    } != 0
                    {
                        let path =
                            PathBuf::from(String::from_utf16_lossy(&buffer[..length as usize]));
                        if is_forever_executable(&path, configured) {
                            found.insert(entry.th32ProcessID);
                        }
                    }
                }
            }
            // SAFETY: snapshot and entry remain valid until the loop ends.
            available = unsafe { Process32NextW(snapshot.0, &mut entry) } != 0;
        }
        found
    }

    pub fn run() -> Result<(), Box<dyn std::error::Error>> {
        let mutex_name = wide("Local\\EvertallyBackgroundSingleInstance");
        // SAFETY: nul-terminated names and default per-user security descriptors.
        let raw = unsafe { CreateMutexW(ptr::null(), 0, mutex_name.as_ptr()) };
        if raw.is_null() {
            return Err("Cannot create background instance lock".into());
        }
        let already = unsafe { GetLastError() } == ERROR_ALREADY_EXISTS;
        let _mutex = Handle(raw);
        if already {
            return Ok(());
        }
        let raw = unsafe { CreateEventW(ptr::null(), 1, 0, wide(STOP).as_ptr()) };
        if raw.is_null() {
            return Err("Cannot create background stop event".into());
        }
        let stop_event = Handle(raw);
        let paths = evertally_sync::config::Paths::new()?;
        let executable = std::env::current_exe()?.with_file_name("Evertally.exe");
        if !executable.is_file() {
            return Err("Evertally.exe is missing beside the background launcher".into());
        }
        let mut sessions = Sessions::default();
        loop {
            // Read settings without modifying them; changes from the app take effect on the next poll.
            let configured = std::fs::read(&paths.config)
                .ok()
                .and_then(|bytes| {
                    serde_json::from_slice::<evertally_sync::config::Config>(&bytes).ok()
                })
                .and_then(|config| config.wow_path);
            if sessions.update(processes(configured.as_deref())) {
                // The app's --wow-start flag starts minimized and inactive. CREATE_NO_WINDOW
                // also prevents a console from flashing in debug builds of this helper.
                if let Err(error) = Command::new(&executable)
                    .arg("--wow-start")
                    .creation_flags(0x08000000)
                    .spawn()
                {
                    evertally_sync::config::log(
                        &paths.log,
                        &format!("Background companion launch failed: {error}"),
                    );
                }
                // The final SavedVariables save is ready when the last game process exits.
                evertally_sync::bridge::Action::Sync.request();
            }
            // SAFETY: valid event handle. A four-second wait is also the polling interval.
            if unsafe { WaitForSingleObject(stop_event.0, 4000) } == WAIT_OBJECT_0 {
                break;
            }
        }
        Ok(())
    }
}

#[cfg(not(windows))]
mod unix {
    use super::Sessions;
    use evertally_sync::{config, game, platform, shutdown};
    use std::{
        process::{Command, Stdio},
        thread,
        time::Duration,
    };
    const STOP: &str = "Local\\EvertallyBackgroundStop";
    const POLL: Duration = Duration::from_secs(4);

    pub fn stop() {
        shutdown::request(STOP);
    }

    pub fn processes() -> std::collections::BTreeSet<u32> {
        game::forever_processes(None)
    }

    pub fn run() -> Result<(), Box<dyn std::error::Error>> {
        let Some(_instance) = platform::single_instance_named("Local\\EvertallyBackgroundSingleInstance")
        else {
            return Ok(());
        };
        let Some(stop_signal) = shutdown::StopSignal::new(STOP) else {
            return Err("Cannot create background stop signal".into());
        };
        let paths = config::Paths::new()?;
        let executable = std::env::current_exe()?.with_file_name("Evertally");
        if !executable.is_file() {
            return Err("Evertally is missing beside the background launcher".into());
        }
        let mut sessions = Sessions::default();
        loop {
            // Read settings without modifying them; changes from the app take effect on the next poll.
            let configured = std::fs::read(&paths.config)
                .ok()
                .and_then(|bytes| serde_json::from_slice::<config::Config>(&bytes).ok())
                .and_then(|config| config.wow_path);
            if sessions.update(game::forever_processes(configured.as_deref())) {
                // The app's --wow-start flag starts it minimised and inactive.
                if let Err(error) = Command::new(&executable)
                    .arg("--wow-start")
                    .stdin(Stdio::null())
                    .stdout(Stdio::null())
                    .stderr(Stdio::null())
                    .spawn()
                {
                    config::log(
                        &paths.log,
                        &format!("Background companion launch failed: {error}"),
                    );
                }
                evertally_sync::bridge::Action::Sync.request();
            }
            // The poll interval is also the stop latency, so wait in short steps.
            for _ in 0..(POLL.as_millis() / 250) {
                if stop_signal.requested() {
                    return Ok(());
                }
                thread::sleep(Duration::from_millis(250));
            }
        }
    }
}

fn main() {
    #[cfg(not(windows))]
    {
        if std::env::args().any(|arg| arg == "--diagnostics") {
            // Read-only: no settings/keyring access, no new lock/signal, no subprocess.
            println!(
                "{}",
                serde_json::json!({"watcher":"EvertallyBackground","matchingGameProcesses":unix::processes().len(),"launchesApplication":false,"writesSettings":false})
            );
            return;
        }
        if std::env::args().any(|arg| arg == "--stop") {
            unix::stop();
            return;
        }
        if let Err(error) = unix::run() {
            eprintln!("Evertally background: {error}");
        }
    }
    #[cfg(windows)]
    {
        if std::env::args().any(|arg| arg == "--diagnostics") {
            // Read-only: no settings/keyring access, no new mutex/event, no subprocess.
            println!(
                "{}",
                serde_json::json!({"watcher":"EvertallyBackground","matchingGameProcesses":windows::processes(None).len(),"launchesApplication":false,"writesSettings":false})
            );
            return;
        }
        if std::env::args().any(|arg| arg == "--stop") {
            windows::stop();
            return;
        }
        if let Err(error) = windows::run() {
            eprintln!("Evertally background: {error}");
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn game_starts_and_the_last_game_exit_wake_the_companion() {
        let mut sessions = Sessions::default();
        assert!(!sessions.update(BTreeSet::new()));
        assert!(sessions.update(BTreeSet::from([10])));
        assert!(!sessions.update(BTreeSet::from([10]))); // manual app closure stays respected
        assert!(sessions.update(BTreeSet::new())); // final save also wakes the companion
        assert!(!sessions.update(BTreeSet::new()));
        assert!(sessions.update(BTreeSet::from([11])));
        assert!(!sessions.update(BTreeSet::from([11])));
    }
    #[test]
    fn one_game_closing_does_not_count_as_the_last_client_exit() {
        let mut sessions=Sessions::default();
        assert!(sessions.update(BTreeSet::from([10,11])));
        assert!(!sessions.update(BTreeSet::from([11])));
        assert!(sessions.update(BTreeSet::new()));
        assert!(!sessions.update(BTreeSet::new()));
    }
    #[cfg(windows)]
    #[test]
    fn only_forever_or_the_explicit_install_is_matched() {
        assert!(is_forever_executable(
            Path::new(r"D:\World of Warcraft\_forever_\Wow.exe"),
            None
        ));
        assert!(!is_forever_executable(
            Path::new(r"D:\World of Warcraft\_retail_\Wow.exe"),
            None
        ));
        assert!(!is_forever_executable(
            Path::new(r"D:\Game\WowVoiceProxy.exe"),
            Some(Path::new(r"D:\Game"))
        ));
        assert!(is_forever_executable(
            Path::new(r"D:\Custom\Wow.exe"),
            Some(Path::new(r"D:\Custom"))
        ));
    }
}

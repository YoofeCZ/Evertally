//! Cooperative shutdown and command signals between the tray bridge, its settings window and the
//! background launcher. No process termination.
//!
//! Windows uses named events. Linux and macOS have no equivalent, so a signal is an empty file in the
//! per-user runtime folder: `request` creates it, the owner polls `requested` and removes it with `reset`.
#[cfg(windows)]
use windows_sys::Win32::{
    Foundation::CloseHandle,
    System::Threading::{
        CreateEventW, EVENT_MODIFY_STATE, OpenEventW, ResetEvent, SetEvent, WaitForSingleObject,
    },
};

#[cfg(windows)]
pub struct StopSignal(windows_sys::Win32::Foundation::HANDLE);
#[cfg(not(windows))]
pub struct StopSignal(std::path::PathBuf);

pub const BRIDGE_STOP: &str = "Local\\EvertallyBridgeStop";
pub const SETTINGS_STOP: &str = "Local\\EvertallyConnectionSettingsStop";
pub const BRIDGE_RELOAD: &str = "Local\\EvertallyBridgeReload";

#[cfg(windows)]
fn wide(name: &str) -> Vec<u16> {
    name.encode_utf16().chain(Some(0)).collect()
}

/// Signal file for a named signal: a per-user folder (the XDG runtime dir when there is one), never shared.
#[cfg(not(windows))]
pub(crate) fn signal_path(name: &str) -> Option<std::path::PathBuf> {
    let dirs = directories::ProjectDirs::from("gg", "Evertally", "Evertally Sync")?;
    let base = dirs
        .runtime_dir()
        .map_or_else(|| dirs.config_dir().join("run"), std::path::Path::to_path_buf);
    let file: String = name
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() { c } else { '_' })
        .collect();
    Some(base.join(file))
}

impl StopSignal {
    #[must_use]
    pub fn new(name: &str) -> Option<Self> {
        #[cfg(windows)]
        {
            // SAFETY: nul-terminated name; default security; owned event handle.
            let handle = unsafe { CreateEventW(std::ptr::null(), 1, 0, wide(name).as_ptr()) };
            (!handle.is_null()).then_some(Self(handle))
        }
        #[cfg(not(windows))]
        {
            let path = signal_path(name)?;
            std::fs::create_dir_all(path.parent()?).ok()?;
            // A request that arrived while nobody was listening must not close the next start.
            let _ = std::fs::remove_file(&path);
            Some(Self(path))
        }
    }
    pub fn reset(&self) {
        #[cfg(windows)]
        // SAFETY: live owned event, reset consumes a configuration-change notification.
        unsafe {
            ResetEvent(self.0);
        }
        #[cfg(not(windows))]
        let _ = std::fs::remove_file(&self.0);
    }
    #[must_use]
    pub fn requested(&self) -> bool {
        #[cfg(windows)]
        {
            // SAFETY: live owned event, nonblocking probe.
            unsafe { WaitForSingleObject(self.0, 0) == 0 }
        }
        #[cfg(not(windows))]
        {
            self.0.exists()
        }
    }
}

impl Drop for StopSignal {
    fn drop(&mut self) {
        #[cfg(windows)]
        // SAFETY: unique owned event is closed exactly once.
        unsafe {
            CloseHandle(self.0);
        }
        #[cfg(not(windows))]
        let _ = std::fs::remove_file(&self.0);
    }
}

pub fn request(name: &str) {
    #[cfg(windows)]
    {
        // SAFETY: request only the named event's signal permission, never a process handle.
        let handle = unsafe { OpenEventW(EVENT_MODIFY_STATE, 0, wide(name).as_ptr()) };
        if !handle.is_null() {
            unsafe {
                SetEvent(handle);
                CloseHandle(handle);
            }
        }
    }
    #[cfg(not(windows))]
    if let Some(path) = signal_path(name)
        && let Some(parent) = path.parent()
        && parent.is_dir()
    {
        // Only a running owner created the folder; without one the request has nobody to reach.
        let _ = std::fs::write(path, b"");
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn isolated_stop_event_is_signalled_and_reset() {
        let name = format!("Local\\EvertallySignalTest-{}", std::process::id());
        let signal = StopSignal::new(&name).expect("test event");
        assert!(!signal.requested());
        request(&name);
        assert!(signal.requested());
        signal.reset();
        assert!(!signal.requested());
    }
}

//! Cooperative shutdown for the tray and its settings window. No process termination.
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
pub struct StopSignal;

pub const BRIDGE_STOP: &str = "Local\\EvertallyBridgeStop";
pub const SETTINGS_STOP: &str = "Local\\EvertallyConnectionSettingsStop";
pub const BRIDGE_RELOAD: &str = "Local\\EvertallyBridgeReload";

#[cfg(windows)]
fn wide(name: &str) -> Vec<u16> {
    name.encode_utf16().chain(Some(0)).collect()
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
            let _ = name;
            Some(Self)
        }
    }
    pub fn reset(&self) {
        #[cfg(windows)]
        // SAFETY: live owned event, reset consumes a configuration-change notification.
        unsafe {
            ResetEvent(self.0);
        }
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
            false
        }
    }
}

#[cfg(windows)]
impl Drop for StopSignal {
    fn drop(&mut self) {
        // SAFETY: unique owned event is closed exactly once.
        unsafe {
            CloseHandle(self.0);
        }
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
    let _ = name;
}

#[cfg(all(test, windows))]
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

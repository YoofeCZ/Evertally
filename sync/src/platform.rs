//! Windows integration: single instance, UI language, autostart and the token store.

use anyhow::{Context, Result};

const KEYRING_SERVICE: &str = "Evertally Sync";
const RUN_KEY: &str = r"Software\Microsoft\Windows\CurrentVersion\Run";
const RUN_VALUE: &str = "EvertallySync";

#[cfg(windows)]
fn background_executable() -> Result<std::path::PathBuf> {
    Ok(std::env::current_exe()
        .context("locate executable")?
        .with_file_name("EvertallyBackground.exe"))
}

/// Holds the named mutex for the lifetime of the process.
pub struct InstanceGuard(#[cfg(windows)] windows_sys::Win32::Foundation::HANDLE);

impl Drop for InstanceGuard {
    fn drop(&mut self) {
        #[cfg(windows)]
        // SAFETY: the handle came from a successful CreateMutexW call and is closed exactly once here.
        unsafe {
            windows_sys::Win32::Foundation::CloseHandle(self.0);
        }
    }
}

/// Returns `None` when another Evertally Sync is already running for this user.
#[cfg(windows)]
#[must_use]
pub fn single_instance() -> Option<InstanceGuard> {
    use windows_sys::Win32::Foundation::{ERROR_ALREADY_EXISTS, GetLastError};
    use windows_sys::Win32::System::Threading::CreateMutexW;
    let name: Vec<u16> = "Local\\EvertallySyncSingleInstance"
        .encode_utf16()
        .chain(Some(0))
        .collect();
    // SAFETY: `name` is a NUL-terminated UTF-16 string that outlives the call; null security
    // attributes request the default descriptor.
    let handle = unsafe { CreateMutexW(std::ptr::null(), 0, name.as_ptr()) };
    if handle.is_null() {
        return None;
    }
    // SAFETY: reads the calling thread's last-error value right after CreateMutexW.
    let already_running = unsafe { GetLastError() } == ERROR_ALREADY_EXISTS;
    let guard = InstanceGuard(handle);
    (!already_running).then_some(guard)
}

#[cfg(not(windows))]
#[must_use]
pub fn single_instance() -> Option<InstanceGuard> {
    Some(InstanceGuard())
}

/// Czech Windows gets Czech texts; everything else gets English.
#[must_use]
pub fn prefers_czech() -> bool {
    #[cfg(windows)]
    {
        // SAFETY: no arguments, returns a LANGID by value.
        let lang_id = unsafe { windows_sys::Win32::Globalization::GetUserDefaultUILanguage() };
        lang_id & 0x3ff == 0x05 // LANG_CZECH primary language id
    }
    #[cfg(not(windows))]
    {
        std::env::var("LANG").is_ok_and(|lang| lang.starts_with("cs"))
    }
}

#[cfg(windows)]
#[must_use]
pub fn autostart_enabled() -> bool {
    use winreg::{RegKey, enums::HKEY_CURRENT_USER};
    RegKey::predef(HKEY_CURRENT_USER)
        .open_subkey(RUN_KEY)
        .and_then(|key| key.get_value::<String, _>(RUN_VALUE))
        .is_ok_and(|registered| {
            background_executable()
                .is_ok_and(|exe| registered.eq_ignore_ascii_case(&format!("\"{}\"", exe.display())))
        })
}

/// # Errors
/// Fails when the per-user Run key cannot be written.
#[cfg(windows)]
pub fn set_autostart(enabled: bool) -> Result<()> {
    use winreg::{RegKey, enums::HKEY_CURRENT_USER};
    let (key, _) = RegKey::predef(HKEY_CURRENT_USER)
        .create_subkey(RUN_KEY)
        .context("open Run key")?;
    if enabled {
        let exe = background_executable()?;
        if !exe.is_file() {
            anyhow::bail!(
                "The background launcher is missing. Reinstall Evertally to enable start with WoW."
            );
        }
        key.set_value(RUN_VALUE, &format!("\"{}\"", exe.display()))
            .context("write Run value")?;
        use std::os::windows::process::CommandExt;
        std::process::Command::new(exe)
            .creation_flags(0x08000000)
            .spawn()
            .context("start background launcher")?;
    } else if key.get_value::<String, _>(RUN_VALUE).is_ok() {
        key.delete_value(RUN_VALUE).context("delete Run value")?;
        if let Ok(exe) = background_executable() {
            use std::os::windows::process::CommandExt;
            let _ = std::process::Command::new(exe)
                .arg("--stop")
                .creation_flags(0x08000000)
                .spawn();
        }
    }
    Ok(())
}

#[cfg(not(windows))]
#[must_use]
pub fn autostart_enabled() -> bool {
    false
}

#[cfg(not(windows))]
pub fn set_autostart(_enabled: bool) -> Result<()> {
    anyhow::bail!("autostart is only supported on Windows")
}

/// Device token in the OS credential store (Windows Credential Manager), keyed by server.
pub struct TokenStore {
    account: String,
}

impl TokenStore {
    #[must_use]
    pub fn new(server_origin: &str) -> Self {
        Self {
            account: server_origin.to_owned(),
        }
    }

    fn entry(&self) -> Result<keyring::Entry> {
        keyring::Entry::new(KEYRING_SERVICE, &self.account).context("open credential store")
    }

    #[must_use]
    pub fn load(&self) -> Option<String> {
        self.entry().ok()?.get_password().ok()
    }

    /// # Errors
    /// Fails when the credential store rejects the write.
    pub fn save(&self, token: &str) -> Result<()> {
        self.entry()?
            .set_password(token)
            .context("store device token")
    }

    pub fn clear(&self) {
        if let Ok(entry) = self.entry() {
            let _ = entry.delete_credential();
        }
    }
}

/// Local wall-clock time as `HH:MM` for status lines.
#[must_use]
pub fn local_time() -> String {
    #[cfg(windows)]
    {
        let mut time = windows_sys::Win32::Foundation::SYSTEMTIME {
            wYear: 0,
            wMonth: 0,
            wDayOfWeek: 0,
            wDay: 0,
            wHour: 0,
            wMinute: 0,
            wSecond: 0,
            wMilliseconds: 0,
        };
        // SAFETY: `time` is a valid, writable SYSTEMTIME for the duration of the call.
        unsafe { windows_sys::Win32::System::SystemInformation::GetLocalTime(&raw mut time) };
        format!("{:02}:{:02}", time.wHour, time.wMinute)
    }
    #[cfg(not(windows))]
    {
        crate::config::utc_timestamp(std::time::SystemTime::now())[11..16].to_owned()
    }
}

/// Shows a blocking error dialog; used only when the app cannot start at all.
pub fn error_dialog(message: &str) {
    #[cfg(windows)]
    {
        use windows_sys::Win32::UI::WindowsAndMessaging::{MB_ICONERROR, MB_OK, MessageBoxW};
        let text: Vec<u16> = message.encode_utf16().chain(Some(0)).collect();
        let title: Vec<u16> = "Evertally Sync".encode_utf16().chain(Some(0)).collect();
        // SAFETY: both strings are NUL-terminated UTF-16 buffers alive for the call; no owner window.
        unsafe {
            MessageBoxW(
                std::ptr::null_mut(),
                text.as_ptr(),
                title.as_ptr(),
                MB_OK | MB_ICONERROR,
            )
        };
    }
    #[cfg(not(windows))]
    eprintln!("{message}");
}

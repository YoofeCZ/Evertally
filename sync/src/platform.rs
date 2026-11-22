//! Operating system integration: single instance, UI language, autostart and the token store.
//! Windows uses the registry and named mutexes; Linux and macOS use lock files, XDG autostart
//! entries / launchd agents and the system keyring.

use anyhow::{Context, Result};

const KEYRING_SERVICE: &str = "Evertally Sync";
#[cfg(windows)]
const RUN_KEY: &str = r"Software\Microsoft\Windows\CurrentVersion\Run";
#[cfg(windows)]
const RUN_VALUE: &str = "EvertallySync";

fn background_executable() -> Result<std::path::PathBuf> {
    let name = if cfg!(windows) {
        "EvertallyBackground.exe"
    } else {
        "EvertallyBackground"
    };
    Ok(std::env::current_exe()
        .context("locate executable")?
        .with_file_name(name))
}

/// Holds the named mutex (Windows) or the advisory lock file (Linux, macOS) for the lifetime of the process.
#[cfg(windows)]
pub struct InstanceGuard(windows_sys::Win32::Foundation::HANDLE);
// The file is only held: the advisory lock lives exactly as long as it stays open.
#[cfg(not(windows))]
pub struct InstanceGuard(#[allow(dead_code)] Option<std::fs::File>);

#[cfg(windows)]
impl Drop for InstanceGuard {
    fn drop(&mut self) {
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
    single_instance_named("Local\\EvertallySyncSingleInstance")
}

#[cfg(windows)]
#[must_use]
pub fn single_instance_named(event_name: &str) -> Option<InstanceGuard> {
    use windows_sys::Win32::Foundation::{ERROR_ALREADY_EXISTS, GetLastError};
    use windows_sys::Win32::System::Threading::CreateMutexW;
    let name: Vec<u16> = event_name.encode_utf16().chain(Some(0)).collect();
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
    single_instance_named("Local\\EvertallySyncSingleInstance")
}

/// `flock` on a per-user file: the kernel drops it when the process dies, so it never goes stale.
/// When the lock file cannot be created the app still starts (better two icons than none).
#[cfg(not(windows))]
#[must_use]
pub fn single_instance_named(name: &str) -> Option<InstanceGuard> {
    let Some(path) = crate::shutdown::signal_path(&format!("{name}.lock")) else {
        return Some(InstanceGuard(None));
    };
    let opened = path
        .parent()
        .map_or(Ok(()), std::fs::create_dir_all)
        .and_then(|()| {
            std::fs::OpenOptions::new()
                .create(true)
                .truncate(false)
                .write(true)
                .open(&path)
        });
    let Ok(file) = opened else {
        return Some(InstanceGuard(None));
    };
    match file.try_lock() {
        Ok(()) => Some(InstanceGuard(Some(file))),
        Err(std::fs::TryLockError::WouldBlock) => None,
        Err(std::fs::TryLockError::Error(_)) => Some(InstanceGuard(None)),
    }
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
        static CZECH: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
        *CZECH.get_or_init(|| {
            let from_env = ["LC_ALL", "LC_MESSAGES", "LANGUAGE", "LANG"]
                .iter()
                .filter_map(|key| std::env::var(key).ok())
                .find(|value| !value.is_empty());
            #[cfg(target_os = "macos")]
            {
                // Apps started from Finder or launchd have no LANG; the system language list is authoritative.
                let system = std::process::Command::new("defaults")
                    .args(["read", "-g", "AppleLanguages"])
                    .output()
                    .ok()
                    .and_then(|out| String::from_utf8(out.stdout).ok())
                    .and_then(|text| first_quoted(&text).map(str::to_owned));
                if let Some(language) = system {
                    return is_czech_locale(&language);
                }
            }
            from_env.is_some_and(|value| is_czech_locale(&value))
        })
    }
}

/// `cs`, `cs_CZ.UTF-8`, `cs-CZ` and a `LANGUAGE` list such as `cs:en` (first entry wins).
#[cfg(not(windows))]
fn is_czech_locale(value: &str) -> bool {
    let first = value.split(':').next().unwrap_or_default().trim();
    first == "cs" || first.starts_with("cs_") || first.starts_with("cs-") || first.starts_with("cs.")
}

/// First `"…"` string of macOS's `AppleLanguages` property list output.
#[cfg(not(windows))]
fn first_quoted(text: &str) -> Option<&str> {
    let start = text.find('"')? + 1;
    let len = text[start..].find('"')?;
    Some(&text[start..start + len])
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

/// Run value that starts the tray app itself when the user signs in to Windows (independent of the WoW watcher).
#[cfg(windows)]
const LOGIN_VALUE: &str = "EvertallyStartup";

/// The tray app (`Evertally.exe`) beside the running executable.
#[cfg(windows)]
fn tray_executable() -> Result<std::path::PathBuf> {
    Ok(std::env::current_exe()
        .context("locate executable")?
        .with_file_name("Evertally.exe"))
}

/// Whether the tray app starts when the user signs in to Windows.
#[cfg(windows)]
#[must_use]
pub fn login_start_enabled() -> bool {
    use winreg::{RegKey, enums::HKEY_CURRENT_USER};
    RegKey::predef(HKEY_CURRENT_USER)
        .open_subkey(RUN_KEY)
        .and_then(|key| key.get_value::<String, _>(LOGIN_VALUE))
        .is_ok_and(|registered| {
            tray_executable()
                .is_ok_and(|exe| registered.eq_ignore_ascii_case(&format!("\"{}\"", exe.display())))
        })
}

/// Starts (or stops starting) the tray app at sign-in. Nothing is launched now: the app is already running.
///
/// # Errors
/// Fails when the per-user Run key cannot be written or the app is missing.
#[cfg(windows)]
pub fn set_login_start(enabled: bool) -> Result<()> {
    use winreg::{RegKey, enums::HKEY_CURRENT_USER};
    let (key, _) = RegKey::predef(HKEY_CURRENT_USER)
        .create_subkey(RUN_KEY)
        .context("open Run key")?;
    if enabled {
        let exe = tray_executable()?;
        anyhow::ensure!(exe.is_file(), "Evertally.exe is missing. Reinstall Evertally.");
        key.set_value(LOGIN_VALUE, &format!("\"{}\"", exe.display()))
            .context("write Run value")?;
    } else if key.get_value::<String, _>(LOGIN_VALUE).is_ok() {
        key.delete_value(LOGIN_VALUE).context("delete Run value")?;
    }
    Ok(())
}

/// Start at sign-in is offered on Windows only; elsewhere the WoW watcher covers it.
#[cfg(not(windows))]
#[must_use]
pub fn login_start_enabled() -> bool {
    false
}

/// # Errors
/// Always on Linux and macOS: not offered there.
#[cfg(not(windows))]
pub fn set_login_start(_enabled: bool) -> Result<()> {
    anyhow::bail!("Start with the system is available on Windows only.")
}

/// Label of the launchd agent on macOS.
#[cfg(not(windows))]
const LAUNCH_AGENT_LABEL: &str = "dev.afstudio.evertally.background";

/// XDG autostart entry (Linux) or launchd agent (macOS) that starts the background launcher at login.
#[cfg(not(windows))]
fn autostart_file() -> Option<std::path::PathBuf> {
    let base = directories::BaseDirs::new()?;
    #[cfg(target_os = "macos")]
    {
        Some(
            base.home_dir()
                .join("Library/LaunchAgents")
                .join(format!("{LAUNCH_AGENT_LABEL}.plist")),
        )
    }
    #[cfg(not(target_os = "macos"))]
    {
        Some(base.config_dir().join("autostart/evertally-background.desktop"))
    }
}

/// Value of the `Exec` key: quoted per the Desktop Entry spec, then escaped as a desktop-file string.
#[cfg(not(windows))]
#[cfg_attr(target_os = "macos", allow(dead_code))]
fn desktop_entry(exe: &std::path::Path) -> String {
    let mut quoted = String::new();
    for c in exe.to_string_lossy().chars() {
        match c {
            '"' | '`' | '$' | '\\' => {
                quoted.push('\\');
                quoted.push(c);
            }
            '%' => quoted.push_str("%%"),
            _ => quoted.push(c),
        }
    }
    let exec = format!("\"{quoted}\"").replace('\\', "\\\\");
    format!(
        "[Desktop Entry]\nType=Application\nName=Evertally Bridge\nComment=Starts the Evertally bridge when World of Warcraft starts\nExec={exec}\nTerminal=false\nNoDisplay=true\nX-GNOME-Autostart-enabled=true\n"
    )
}

#[cfg(not(windows))]
#[cfg_attr(not(target_os = "macos"), allow(dead_code))]
fn launch_agent(exe: &std::path::Path) -> String {
    let path = exe
        .to_string_lossy()
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;");
    format!(
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\">\n<dict>\n\t<key>Label</key>\n\t<string>{LAUNCH_AGENT_LABEL}</string>\n\t<key>ProgramArguments</key>\n\t<array>\n\t\t<string>{path}</string>\n\t</array>\n\t<key>RunAtLoad</key>\n\t<true/>\n\t<key>ProcessType</key>\n\t<string>Background</string>\n</dict>\n</plist>\n"
    )
}

#[cfg(not(windows))]
fn autostart_contents(exe: &std::path::Path) -> String {
    #[cfg(target_os = "macos")]
    {
        launch_agent(exe)
    }
    #[cfg(not(target_os = "macos"))]
    {
        desktop_entry(exe)
    }
}

#[cfg(not(windows))]
fn spawn_detached(exe: &std::path::Path, args: &[&str]) -> std::io::Result<std::process::Child> {
    use std::process::Stdio;
    std::process::Command::new(exe)
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
}

#[cfg(not(windows))]
#[must_use]
pub fn autostart_enabled() -> bool {
    let (Some(file), Ok(exe)) = (autostart_file(), background_executable()) else {
        return false;
    };
    std::fs::read_to_string(file).is_ok_and(|text| text == autostart_contents(&exe))
}

/// # Errors
/// Fails when the autostart entry cannot be written or the background launcher is missing.
#[cfg(not(windows))]
pub fn set_autostart(enabled: bool) -> Result<()> {
    let file = autostart_file().context("no home folder for the autostart entry")?;
    let exe = background_executable()?;
    if enabled {
        if !exe.is_file() {
            anyhow::bail!(
                "The background launcher is missing. Reinstall Evertally to enable start with WoW."
            );
        }
        if let Some(parent) = file.parent() {
            std::fs::create_dir_all(parent).context("create autostart folder")?;
        }
        std::fs::write(&file, autostart_contents(&exe)).context("write autostart entry")?;
        spawn_detached(&exe, &[]).context("start background launcher")?;
    } else {
        match std::fs::remove_file(&file) {
            Ok(()) => {
                let _ = spawn_detached(&exe, &["--stop"]);
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
            Err(error) => return Err(error).context("delete autostart entry"),
        }
    }
    Ok(())
}

/// Set by the bridge running without a desktop session (no tray: SteamOS, its game mode, a systemd
/// service). The keyring there is often locked or not running at all (KWallet lives in the KDE session),
/// so the token is kept in the private `0600` file, which every mode can read.
#[cfg(not(windows))]
static PREFER_TOKEN_FILE: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

/// Keep the device token in the private settings file instead of the system keyring (see [`TokenStore`]).
#[cfg(not(windows))]
pub fn prefer_token_file() {
    PREFER_TOKEN_FILE.store(true, std::sync::atomic::Ordering::Relaxed);
}

/// Device token in the OS credential store (Windows Credential Manager, macOS Keychain, the Secret
/// Service on Linux), keyed by server. A Linux session without a Secret Service (headless, no keyring
/// daemon) falls back to a private `0600` file in the settings folder instead of failing to pair.
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

    #[cfg(not(windows))]
    fn fallback_file(&self) -> Option<std::path::PathBuf> {
        use sha2::{Digest, Sha256};
        let dirs = directories::ProjectDirs::from("gg", "Evertally", "Evertally Sync")?;
        let digest = format!("{:x}", Sha256::digest(self.account.as_bytes()));
        Some(dirs.config_dir().join(format!("token-{}.key", &digest[..16])))
    }

    #[cfg(not(windows))]
    fn write_fallback(&self, token: &str) -> Result<()> {
        use std::{io::Write, os::unix::fs::OpenOptionsExt};
        let path = self.fallback_file().context("no settings folder")?;
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).context("create settings folder")?;
        }
        let mut file = std::fs::OpenOptions::new()
            .create(true)
            .write(true)
            .truncate(true)
            .mode(0o600)
            .open(&path)
            .context("store device token")?;
        file.write_all(token.as_bytes()).context("store device token")
    }

    #[cfg(not(windows))]
    fn read_fallback(&self) -> Option<String> {
        let text = std::fs::read_to_string(self.fallback_file()?).ok()?;
        let token = text.trim();
        (!token.is_empty()).then(|| token.to_owned())
    }

    #[must_use]
    pub fn load(&self) -> Option<String> {
        #[cfg(not(windows))]
        if PREFER_TOKEN_FILE.load(std::sync::atomic::Ordering::Relaxed) {
            if let Some(token) = self.read_fallback() {
                return Some(token);
            }
            // paired earlier in a desktop session: moved into the file once, so game mode finds it too
            let token = self.entry().ok().and_then(|entry| entry.get_password().ok())?;
            let _ = self.write_fallback(&token);
            return Some(token);
        }
        let stored = self
            .entry()
            .ok()
            .and_then(|entry| entry.get_password().ok());
        #[cfg(not(windows))]
        let stored = stored.or_else(|| self.read_fallback());
        stored
    }

    /// # Errors
    /// Fails when neither the credential store nor (off Windows) the fallback file accepts the write.
    pub fn save(&self, token: &str) -> Result<()> {
        #[cfg(not(windows))]
        if PREFER_TOKEN_FILE.load(std::sync::atomic::Ordering::Relaxed) {
            return self.write_fallback(token);
        }
        let stored = self
            .entry()
            .and_then(|entry| entry.set_password(token).context("store device token"));
        #[cfg(not(windows))]
        {
            if stored.is_ok() {
                if let Some(file) = self.fallback_file() {
                    let _ = std::fs::remove_file(file);
                }
                return Ok(());
            }
            self.write_fallback(token)
        }
        #[cfg(windows)]
        stored
    }

    pub fn clear(&self) {
        if let Ok(entry) = self.entry() {
            let _ = entry.delete_credential();
        }
        #[cfg(not(windows))]
        if let Some(file) = self.fallback_file() {
            let _ = std::fs::remove_file(file);
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
        // SAFETY: `time` is a valid time_t, `parts` a writable zeroed `tm`; localtime_r is thread-safe.
        let parts = unsafe {
            let time = libc::time(std::ptr::null_mut());
            let mut parts: libc::tm = std::mem::zeroed();
            libc::localtime_r(&raw const time, &raw mut parts);
            parts
        };
        format!("{:02}:{:02}", parts.tm_hour, parts.tm_min)
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
    {
        eprintln!("{message}");
        // Best effort: the message goes in as an argument, never through a shell or a script string.
        #[cfg(target_os = "macos")]
        let _ = std::process::Command::new("osascript")
            .args([
                "-e",
                "on run argv",
                "-e",
                "display dialog (item 1 of argv) with title \"Evertally Bridge\" buttons {\"OK\"} default button 1 with icon stop",
                "-e",
                "end run",
                "--",
                message,
            ])
            .status();
        #[cfg(not(target_os = "macos"))]
        {
            let shown = std::process::Command::new("zenity")
                .args(["--error", "--title=Evertally Bridge", "--no-markup", "--text", message])
                .status()
                .is_ok_and(|status| status.success());
            if !shown {
                let _ = std::process::Command::new("kdialog")
                    .args(["--title", "Evertally Bridge", "--error", message])
                    .status();
            }
        }
    }
}

#[cfg(all(test, not(windows)))]
mod tests {
    use super::*;
    use std::path::Path;

    #[test]
    fn desktop_entry_quotes_paths_with_spaces_and_specials() {
        let text = desktop_entry(Path::new("/home/a b/$x/100%/Evertally\"Background"));
        assert!(text.contains("Exec=\"/home/a b/\\\\$x/100%%/Evertally\\\\\"Background\"\n"), "{text}");
        assert!(text.starts_with("[Desktop Entry]\n"));
    }

    #[test]
    fn launch_agent_escapes_xml_and_runs_at_login() {
        let text = launch_agent(Path::new("/Applications/A&B <x>/EvertallyBackground"));
        assert!(text.contains("<string>/Applications/A&amp;B &lt;x&gt;/EvertallyBackground</string>"));
        assert!(text.contains("<key>RunAtLoad</key>\n\t<true/>"));
        assert!(text.contains(LAUNCH_AGENT_LABEL));
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn launch_agent_is_a_valid_property_list() {
        let path = std::env::temp_dir().join(format!("evertally-agent-test-{}.plist", std::process::id()));
        std::fs::write(&path, launch_agent(Path::new("/Applications/Evertally Bridge.app/Contents/MacOS/EvertallyBackground"))).unwrap();
        let lint = std::process::Command::new("plutil").arg("-lint").arg(&path).output().unwrap();
        let _ = std::fs::remove_file(&path);
        assert!(lint.status.success(), "{}", String::from_utf8_lossy(&lint.stdout));
    }

    #[test]
    fn czech_locales_are_recognised() {
        for yes in ["cs", "cs_CZ.UTF-8", "cs-CZ", "cs:en", "cs.UTF-8"] {
            assert!(is_czech_locale(yes), "{yes}");
        }
        for no in ["", "en_US.UTF-8", "csb_PL", "sk_SK", "en:cs", "C"] {
            assert!(!is_czech_locale(no), "{no}");
        }
        assert_eq!(first_quoted("(\n    \"cs-CZ\",\n    \"en-CZ\"\n)"), Some("cs-CZ"));
        assert_eq!(first_quoted("()"), None);
    }

    #[test]
    fn second_instance_is_refused_until_the_first_exits() {
        let name = format!("Local\\EvertallyInstanceTest-{}", std::process::id());
        let first = single_instance_named(&name).expect("first instance");
        assert!(single_instance_named(&name).is_none(), "lock must be held");
        drop(first);
        // A child process forked at this very moment (other tests spawn some) still holds the inherited
        // descriptor until it execs; the lock is free right after, never earlier.
        let released = (0..100).any(|_| {
            single_instance_named(&name).is_some() || {
                std::thread::sleep(std::time::Duration::from_millis(20));
                false
            }
        });
        assert!(released, "lock must be released on exit");
        let _ = std::fs::remove_file(crate::shutdown::signal_path(&format!("{name}.lock")).unwrap());
    }

    #[test]
    fn local_time_is_hh_mm() {
        let time = local_time();
        assert_eq!(time.len(), 5, "{time}");
        assert_eq!(&time[2..3], ":");
    }
}

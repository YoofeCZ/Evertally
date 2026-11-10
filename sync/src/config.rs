//! Settings, file locations and a tiny append-only log.

use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};

/// Server used when `config.json` does not override it. Release builds set
/// `EVERTALLY_SERVER` at compile time; development builds talk to the local preview.
pub const DEFAULT_SERVER: &str = match option_env!("EVERTALLY_SERVER") {
    Some(server) => server,
    None => "http://127.0.0.1:5173",
};
const LOG_LIMIT_BYTES: u64 = 1024 * 1024;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Config {
    pub server: String,
    /// Optional World of Warcraft folder, for installs the app cannot find itself.
    pub wow_path: Option<PathBuf>,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            server: DEFAULT_SERVER.to_owned(),
            wow_path: None,
        }
    }
}

impl Config {
    /// The server origin without a trailing slash.
    ///
    /// # Errors
    /// Plain `http` is refused except for a loopback preview, so the device token
    /// is never sent unencrypted over a network.
    pub fn server_origin(&self) -> Result<String> {
        let origin = self.server.trim().trim_end_matches('/').to_owned();
        let uri: ureq::http::Uri = origin
            .parse()
            .context("server must be a valid origin URL")?;
        let authority = uri.authority().context("server URL has no host")?;
        if authority.as_str().contains('@')
            || uri.path() != "/" && !uri.path().is_empty()
            || uri.query().is_some()
            || origin.contains('#')
            || authority.port().is_some() && authority.port_u16().is_none()
        {
            bail!("server must contain only a scheme, host and optional port");
        }
        let loopback = uri.scheme_str() == Some("http")
            && matches!(uri.host(), Some("127.0.0.1" | "localhost" | "[::1]"));
        if !(uri.scheme_str() == Some("https") || loopback) {
            bail!("server must use https:// (got {origin})");
        }
        Ok(origin)
    }
}

/// Where settings, upload state and the log live.
#[derive(Debug, Clone)]
pub struct Paths {
    pub config: PathBuf,
    pub state: PathBuf,
    pub log: PathBuf,
    pub dir: PathBuf,
}

impl Paths {
    /// # Errors
    /// Fails when the user profile has no application data folder.
    pub fn new() -> Result<Self> {
        let dirs = directories::ProjectDirs::from("gg", "Evertally", "Evertally Sync")
            .context("no application data folder")?;
        let dir = dirs.config_dir().to_path_buf();
        fs::create_dir_all(&dir).with_context(|| format!("create {}", dir.display()))?;
        Ok(Self {
            config: dir.join("config.json"),
            state: dir.join("state.json"),
            log: dir.join("sync.log"),
            dir,
        })
    }
}

/// Loads `config.json`, writing the defaults on first run so the user can edit them.
///
/// # Errors
/// Fails when an existing file is not valid JSON.
pub fn load_config(path: &Path) -> Result<Config> {
    if let Ok(text) = fs::read_to_string(path) {
        return serde_json::from_str(&text).with_context(|| format!("invalid {}", path.display()));
    }
    let config = Config::default();
    fs::write(path, serde_json::to_string_pretty(&config)?)
        .with_context(|| format!("write {}", path.display()))?;
    Ok(config)
}

/// Appends one line to the log. Never pass secrets here.
pub fn log(path: &Path, message: &str) {
    if fs::metadata(path).is_ok_and(|m| m.len() > LOG_LIMIT_BYTES) {
        let _ = fs::rename(path, path.with_extension("log.old"));
    }
    if let Ok(mut file) = OpenOptions::new().create(true).append(true).open(path) {
        let _ = writeln!(file, "{} {message}", utc_timestamp(SystemTime::now()));
    }
}

/// `YYYY-MM-DD HH:MM:SSZ` without a date-time dependency.
#[must_use]
pub fn utc_timestamp(time: SystemTime) -> String {
    let secs = time.duration_since(UNIX_EPOCH).map_or(0, |d| d.as_secs());
    let days = i64::try_from(secs / 86_400).unwrap_or(0);
    let rem = secs % 86_400;
    // Civil-from-days (Howard Hinnant), valid for the proleptic Gregorian calendar.
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = yoe + era * 400 + i64::from(month <= 2);
    format!(
        "{year:04}-{month:02}-{day:02} {:02}:{:02}:{:02}Z",
        rem / 3600,
        rem / 60 % 60,
        rem % 60
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    #[test]
    #[allow(clippy::duration_suboptimal_units)] // instants given as Unix seconds, not spans
    fn timestamp_formats_known_instants() {
        assert_eq!(utc_timestamp(UNIX_EPOCH), "1970-01-01 00:00:00Z");
        assert_eq!(
            utc_timestamp(UNIX_EPOCH + Duration::from_secs(1_794_236_400)),
            "2026-11-09 15:00:00Z"
        );
        assert_eq!(
            utc_timestamp(UNIX_EPOCH + Duration::from_secs(951_782_400)),
            "2000-02-29 00:00:00Z"
        );
    }

    #[test]
    fn only_https_or_loopback_servers_are_accepted() {
        let with = |server: &str| {
            Config {
                server: server.to_owned(),
                wow_path: None,
            }
            .server_origin()
        };
        assert_eq!(
            with("https://evertally.example/").expect("https ok"),
            "https://evertally.example"
        );
        assert!(with("http://127.0.0.1:5173").is_ok());
        assert!(with("http://localhost").is_ok());
        assert!(with("http://evertally.example").is_err());
        assert!(with("http://127.0.0.1.evil.example").is_err());
        assert!(with("http://127.0.0.1:80@evil.example").is_err());
        assert!(with("https://evertally.example/path").is_err());
        assert!(with("https://evertally.example?token=x").is_err());
        assert!(with("https://evertally.example#fragment").is_err());
        assert!(with("http://[::1]:5173").is_ok());
        assert!(with("ftp://x").is_err());
    }
}

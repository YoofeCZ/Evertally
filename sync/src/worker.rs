//! Background thread: pairing, watching export files and uploading new records.

use std::collections::{HashMap, HashSet};
use std::path::PathBuf;
use std::sync::mpsc::{Receiver, RecvTimeoutError, Sender};
use std::time::{Duration, Instant, SystemTime};

use notify::{RecommendedWatcher, RecursiveMode, Watcher};

use crate::api::{ApiError, Client, PollResult};
use crate::config::{self, Config, Paths};
use crate::lang::{Texts, fill};
use crate::platform::{self, TokenStore};
use crate::savedvars;
use crate::upload::{self, Plan, UploadState};
use crate::wow;

/// `WoW` rewrites the file in several steps; wait for it to settle before reading.
const SETTLE: Duration = Duration::from_secs(3);
/// Catch-up and retry interval when nothing happens.
const TICK: Duration = Duration::from_mins(5);

pub enum Command {
    FileChanged(PathBuf),
    SyncNow,
    Pair,
    CancelPair,
    ReloadConfig(Config),
    Unpair,
    Quit,
}

#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UiState {
    pub status: String,
    pub tooltip: String,
    pub paired: bool,
    /// Set while a pairing waits for approval; the desktop app approves it in its own window.
    pub pairing_code: Option<String>,
    /// Watched `SavedVariables` folders.
    pub folders: Vec<String>,
}

enum FileResult {
    Uploaded(u64),
    UpToDate,
    Disabled,
    Unpaired,
    /// Temporary problem (network, server busy); try again later.
    Retry,
    /// The server refused this file version; wait until the file changes.
    Rejected(String),
}

pub struct Worker {
    texts: &'static Texts,
    paths: Paths,
    config: Config,
    client: Client,
    tokens: TokenStore,
    token: Option<String>,
    state: UploadState,
    publish: Box<dyn Fn(UiState) + Send>,
    tx: Sender<Command>,
    watcher: Option<RecommendedWatcher>,
    dirs: Vec<PathBuf>,
    processed: HashMap<PathBuf, SystemTime>,
    first_run: bool,
    open_browser: bool,
}

impl Worker {
    #[must_use]
    pub fn new(
        texts: &'static Texts,
        paths: Paths,
        config: Config,
        origin: String,
        publish: Box<dyn Fn(UiState) + Send>,
        tx: Sender<Command>,
        open_browser: bool,
    ) -> Self {
        let tokens = TokenStore::new(&origin);
        let first_run = !paths.state.exists();
        let token = config
            .server_origin()
            .ok()
            .filter(|value| value == &origin)
            .and_then(|_| tokens.load());
        Self {
            texts,
            state: UploadState::load(&paths.state),
            token,
            tokens,
            client: Client::new(origin),
            paths,
            config,
            publish,
            tx,
            watcher: None,
            dirs: Vec::new(),
            processed: HashMap::new(),
            first_run,
            open_browser,
        }
    }

    fn log(&self, message: &str) {
        config::log(&self.paths.log, message);
    }

    fn show(&self, status: String) {
        let tooltip = format!("Evertally Sync\n{status}");
        (self.publish)(UiState {
            tooltip: tooltip.chars().take(120).collect(),
            status,
            paired: self.token.is_some(),
            pairing_code: None,
            folders: self.folders(),
        });
    }

    fn folders(&self) -> Vec<String> {
        self.dirs.iter().map(|d| d.display().to_string()).collect()
    }

    pub fn run(mut self, rx: &Receiver<Command>) {
        self.show(self.texts.starting.to_owned());
        self.refresh_watch();
        if let Err(error) = self.config.server_origin() {
            self.show(format!("{error}"));
        } else if self.token.is_none() {
            // The native window always starts locally. Only the legacy tray app
            // starts pairing on first launch, as it has no main window.
            if self.first_run && self.open_browser {
                let _ = self.state.save(&self.paths.state);
                if !self.pair(rx) {
                    return;
                }
            } else {
                self.show(self.texts.not_paired.to_owned());
            }
        } else {
            self.sync_all(false);
        }

        let mut dirty: HashSet<PathBuf> = HashSet::new();
        let mut settle_at: Option<Instant> = None;
        loop {
            let timeout = settle_at.map_or(TICK, |at| at.saturating_duration_since(Instant::now()));
            match rx.recv_timeout(timeout) {
                Ok(Command::FileChanged(path)) => {
                    dirty.insert(path);
                    settle_at = Some(Instant::now() + SETTLE);
                }
                Ok(Command::SyncNow) => {
                    self.refresh_watch();
                    self.sync_all(true);
                }
                Ok(Command::Pair) => {
                    if !self.pair(rx) {
                        return;
                    }
                }
                Ok(Command::CancelPair) => {}
                Ok(Command::ReloadConfig(config)) => {
                    self.reload_config(config);
                    dirty.clear();
                    settle_at = None;
                }
                Ok(Command::Unpair) => {
                    self.tokens.clear();
                    self.token = None;
                    self.log("disconnected by user");
                    self.show(self.texts.not_paired.to_owned());
                }
                Ok(Command::Quit) | Err(RecvTimeoutError::Disconnected) => return,
                Err(RecvTimeoutError::Timeout) => {
                    if settle_at.take().is_some() {
                        let paths: Vec<PathBuf> = dirty.drain().collect();
                        self.sync_paths(&paths, true);
                    } else {
                        self.refresh_watch();
                        self.sync_all(false);
                    }
                }
            }
        }
    }

    fn reload_config(&mut self, config: Config) {
        let origin = match config.server_origin() {
            Ok(origin) => origin,
            Err(error) => {
                self.show(format!("{error}"));
                return;
            }
        };
        if origin != self.client.origin() || self.config.server_origin().is_err() {
            // Device credentials belong to one origin. Never forward a token to
            // another server, or reuse its upload cursor there.
            self.tokens = TokenStore::new(&origin);
            self.token = self.tokens.load();
            self.client = Client::new(origin);
            self.state = UploadState::default();
            let _ = self.state.save(&self.paths.state);
        }
        self.config = config;
        self.watcher = None;
        self.dirs.clear();
        self.processed.clear();
        self.refresh_watch();
        if self.token.is_some() {
            self.sync_all(true);
        } else {
            self.show(self.texts.not_paired.to_owned());
        }
    }

    /// (Re)discovers account folders and watches any new ones.
    fn refresh_watch(&mut self) {
        let roots = wow::candidate_roots(self.config.wow_path.as_deref());
        let dirs = wow::saved_variables_dirs(&roots);
        if self.watcher.is_none() {
            let tx = self.tx.clone();
            let watcher =
                notify::recommended_watcher(move |result: notify::Result<notify::Event>| {
                    if let Ok(event) = result {
                        for path in event.paths.into_iter().filter(|p| wow::is_export_file(p)) {
                            let _ = tx.send(Command::FileChanged(path));
                        }
                    }
                });
            match watcher {
                Ok(watcher) => self.watcher = Some(watcher),
                Err(error) => self.log(&format!("file watcher unavailable: {error}")),
            }
        }
        for dir in dirs {
            if self.dirs.contains(&dir) {
                continue;
            }
            if let Some(watcher) = self.watcher.as_mut()
                && let Err(error) = watcher.watch(&dir, RecursiveMode::NonRecursive)
            {
                self.log(&format!("cannot watch {}: {error}", dir.display()));
                continue;
            }
            self.log(&format!("watching {}", dir.display()));
            self.dirs.push(dir);
        }
    }

    fn sync_all(&mut self, force: bool) {
        if self.dirs.is_empty() {
            self.show(self.texts.no_wow.to_owned());
            return;
        }
        let files: Vec<PathBuf> = self
            .dirs
            .iter()
            .map(|dir| dir.join(wow::EXPORT_FILE))
            .filter(|path| path.is_file())
            .collect();
        if files.is_empty() {
            if self.token.is_some() {
                self.show(fill(
                    self.texts.watching,
                    &[("count", &self.dirs.len().to_string())],
                ));
            }
            return;
        }
        self.sync_paths(&files, force);
    }

    fn sync_paths(&mut self, files: &[PathBuf], force: bool) {
        if self.token.is_none() {
            return;
        }
        let mut uploaded = 0;
        let mut disabled = false;
        let mut problem: Option<String> = None;
        let mut retry = false;
        for path in files {
            let Ok(modified) = std::fs::metadata(path).and_then(|m| m.modified()) else {
                continue;
            };
            if !force && self.processed.get(path) == Some(&modified) {
                continue;
            }
            match self.sync_file(path) {
                FileResult::Uploaded(count) => uploaded += count,
                FileResult::UpToDate => {}
                FileResult::Disabled => disabled = true,
                FileResult::Unpaired => {
                    self.tokens.clear();
                    self.token = None;
                    self.show(self.texts.disconnected.to_owned());
                    return;
                }
                FileResult::Retry => {
                    retry = true;
                    continue;
                }
                FileResult::Rejected(message) => problem = Some(message),
            }
            self.processed.insert(path.clone(), modified);
        }
        let time = platform::local_time();
        let status = if uploaded > 0 {
            fill(
                self.texts.uploaded,
                &[("count", &uploaded.to_string()), ("time", &time)],
            )
        } else if let Some(message) = problem {
            message
        } else if retry {
            self.texts.offline.to_owned()
        } else if disabled {
            self.texts.export_off.to_owned()
        } else {
            fill(self.texts.up_to_date, &[("time", &time)])
        };
        self.show(status);
    }

    fn sync_file(&mut self, path: &PathBuf) -> FileResult {
        let Some(token) = self.token.clone() else {
            return FileResult::Unpaired;
        };
        let text = match std::fs::read_to_string(path) {
            Ok(text) => text,
            Err(error) => {
                self.log(&format!("cannot read {}: {error}", path.display()));
                return FileResult::Retry;
            }
        };
        let envelope = match savedvars::parse_assignment(&text, wow::EXPORT_VARIABLE) {
            Ok(value) => value,
            Err(error) => {
                // Usually a half-written file; the next change event retries.
                self.log(&format!("cannot parse {}: {error}", path.display()));
                return FileResult::Retry;
            }
        };
        let (source, batches) = match upload::plan(&envelope, &self.state) {
            Ok(Plan::Disabled) => return FileResult::Disabled,
            Ok(Plan::UpToDate) => return FileResult::UpToDate,
            Ok(Plan::Send {
                source, batches, ..
            }) => (source, batches),
            Err(error) => return FileResult::Rejected(format!("{error}")),
        };
        let mut accepted = 0;
        for batch in &batches {
            match self.client.upload(&token, batch) {
                Ok(result) => {
                    accepted += result.accepted;
                    self.state.mark(&source, upload::batch_ids(batch));
                    if let Err(error) = self.state.save(&self.paths.state) {
                        self.log(&format!("cannot save state: {error:#}"));
                    }
                    self.log(&format!(
                        "uploaded batch: {} accepted, {} duplicates",
                        result.accepted, result.duplicates
                    ));
                }
                Err(ApiError::Server { status: 401, .. }) => {
                    self.log("device token rejected; unpaired");
                    return FileResult::Unpaired;
                }
                Err(ApiError::Server {
                    status,
                    code,
                    message,
                }) if status < 500 && status != 429 => {
                    self.log(&format!("upload refused ({code})"));
                    return FileResult::Rejected(message);
                }
                Err(error) => {
                    self.log(&format!("upload failed, will retry: {error}"));
                    return FileResult::Retry;
                }
            }
        }
        FileResult::Uploaded(accepted)
    }

    /// Runs the pairing flow. Returns `false` when the app should quit.
    fn pair(&mut self, rx: &Receiver<Command>) -> bool {
        if let Err(error) = self.config.server_origin() {
            self.show(format!("{error}"));
            return true;
        }
        let device = gethostname::gethostname()
            .to_string_lossy()
            .chars()
            .take(60)
            .collect::<String>();
        let pairing = match self.client.start_pairing(&device) {
            Ok(pairing) => pairing,
            Err(error) => {
                self.log(&format!("pairing could not start: {error}"));
                self.show(self.texts.offline.to_owned());
                return true;
            }
        };
        // The user code is shown in the tray too; it is not a secret.
        self.log(&format!(
            "pairing started for {device}, code {}",
            pairing.user_code
        ));
        if self.open_browser {
            open_browser(&pairing.verification_uri_complete);
        }
        let code = pairing.user_code.clone();
        (self.publish)(UiState {
            status: fill(self.texts.pairing, &[("code", &code)]),
            tooltip: fill(self.texts.pairing_tooltip, &[("code", &code)]),
            paired: false,
            pairing_code: Some(code.clone()),
            folders: self.folders(),
        });

        let deadline = Instant::now() + Duration::from_secs(pairing.expires_in.max(30));
        let mut interval = Duration::from_secs(pairing.interval.clamp(2, 30));
        loop {
            match rx.recv_timeout(interval) {
                Ok(Command::Quit) | Err(RecvTimeoutError::Disconnected) => return false,
                Ok(Command::CancelPair) => {
                    self.show(if self.token.is_some() {
                        "Pairing cancelled; previous connection retained.".to_owned()
                    } else {
                        self.texts.not_paired.to_owned()
                    });
                    return true;
                }
                Ok(Command::Unpair) => {
                    self.tokens.clear();
                    self.token = None;
                    self.show(self.texts.not_paired.to_owned());
                    return true;
                }
                Ok(Command::ReloadConfig(config)) => {
                    self.reload_config(config);
                    return true;
                }
                Ok(Command::Pair) if self.open_browser => {
                    open_browser(&pairing.verification_uri_complete);
                }
                Ok(_) | Err(RecvTimeoutError::Timeout) => {}
            }
            if Instant::now() > deadline {
                self.show(self.texts.pairing_expired.to_owned());
                return true;
            }
            match self.client.poll_pairing(&pairing.device_code) {
                Ok(PollResult::Pending { interval: next }) => {
                    if next > 0 {
                        interval = Duration::from_secs(next.clamp(2, 30));
                    }
                }
                Ok(PollResult::Approved { token, user }) => {
                    if let Err(error) = self.tokens.save(&token) {
                        self.log(&format!("cannot store token: {error:#}"));
                    }
                    self.token = Some(token);
                    // A different website account may have approved this code.
                    // Replaying is safe: the API deduplicates events per owner.
                    self.state = UploadState::default();
                    self.processed.clear();
                    let _ = self.state.save(&self.paths.state);
                    self.log("paired");
                    self.show(fill(self.texts.paired_as, &[("name", &user.display_name)]));
                    self.refresh_watch();
                    self.sync_all(true);
                    return true;
                }
                Err(error) if error.code() == "access_denied" => {
                    self.show(self.texts.pairing_declined.to_owned());
                    return true;
                }
                Err(error) if error.code() == "expired_token" => {
                    self.show(self.texts.pairing_expired.to_owned());
                    return true;
                }
                Err(_) => {}
            }
        }
    }
}

/// Opens the pairing page. `EVERTALLY_SYNC_NO_BROWSER` skips it for automated tests.
fn open_browser(url: &str) {
    if std::env::var_os("EVERTALLY_SYNC_NO_BROWSER").is_none() {
        let _ = open::that(url);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Arc, Mutex, mpsc};

    #[test]
    fn invalid_server_keeps_pairing_disabled_instead_of_using_fallback() {
        let dir = std::env::temp_dir().join("evertally-invalid-server-test");
        let paths = Paths {
            config: dir.join("config.json"),
            state: dir.join("state.json"),
            log: dir.join("sync.log"),
            dir,
        };
        let states = Arc::new(Mutex::new(Vec::new()));
        let observed = states.clone();
        let (tx, rx) = mpsc::channel();
        tx.send(Command::Pair).expect("queue pair");
        tx.send(Command::Quit).expect("queue quit");
        let worker = Worker::new(
            &crate::lang::EN,
            paths,
            Config {
                server: "http://invalid.example".to_owned(),
                wow_path: None,
            },
            "http://127.0.0.1:9".to_owned(),
            Box::new(move |state| observed.lock().expect("states").push(state)),
            tx,
            false,
        );
        assert!(worker.token.is_none());
        worker.run(&rx);
        let states = states.lock().expect("states");
        assert!(
            states
                .iter()
                .any(|state| state.status.contains("must use https"))
        );
        assert!(
            states
                .iter()
                .all(|state| state.status != crate::lang::EN.offline)
        );
        assert!(
            states
                .iter()
                .all(|state| !state.paired && state.pairing_code.is_none())
        );
    }

    #[test]
    fn native_first_launch_stays_local_until_pair_is_requested() {
        let dir = std::env::temp_dir().join(format!(
            "evertally-native-start-test-{}",
            std::process::id()
        ));
        let paths = Paths {
            config: dir.join("config.json"),
            state: dir.join("state.json"),
            log: dir.join("sync.log"),
            dir,
        };
        assert!(!paths.state.exists());
        let states = Arc::new(Mutex::new(Vec::new()));
        let observed = states.clone();
        let (tx, rx) = mpsc::channel();
        tx.send(Command::Quit).expect("queue quit");
        let config = Config {
            server: "https://unpaired-native-start-test.invalid".to_owned(),
            wow_path: None,
        };
        let worker = Worker::new(
            &crate::lang::EN,
            paths,
            config.clone(),
            config.server.clone(),
            Box::new(move |state| observed.lock().expect("states").push(state)),
            tx,
            false,
        );
        worker.run(&rx);
        let states = states.lock().expect("states");
        assert!(
            states
                .iter()
                .any(|state| state.status == crate::lang::EN.not_paired)
        );
        assert!(
            states
                .iter()
                .all(|state| !state.paired && state.pairing_code.is_none())
        );
    }
}

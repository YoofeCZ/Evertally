//! Background thread: pairing, watching export files and uploading new records.

use std::collections::{HashMap, HashSet};
use std::path::PathBuf;
use std::sync::{Arc, Mutex, mpsc::{Receiver, RecvTimeoutError, Sender}};
use std::time::{Duration, Instant, SystemTime};

use notify::{RecommendedWatcher, RecursiveMode, Watcher};

use crate::api::{ApiError, Client, LiveResult, PollResult};
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
/// How often the forum is exchanged with the website while the app runs (a save of the game's files triggers it at once).
const FORUM_EVERY: Duration = Duration::from_mins(3);

pub enum Command {
    FileChanged(PathBuf),
    SyncNow,
    Pair,
    CancelPair,
    ReloadConfig(Config),
    Unpair,
    Quit,
    AddonStatus(String),
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UiState {
    #[serde(default)]
    pub live_status: Option<String>,
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
    open_browser: bool,
    live_poll: Instant,
    forum_poll: Instant,
    live_sent: Option<(String, u64)>,
    live_status: Option<String>,
    /// Who plays, learned from the exported file: what a live marker is resolved against.
    identity: crate::optical::Identity,
    marker_fresh: crate::optical::Freshness,
    base_status: String,
    addon_forum_lock: Arc<Mutex<()>>,
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
            open_browser,
            live_poll: Instant::now() - Duration::from_secs(5),
            forum_poll: Instant::now() - FORUM_EVERY,
            live_sent: None,
            live_status: None,
            identity: crate::optical::Identity::default(),
            marker_fresh: crate::optical::Freshness::default(),
            base_status: String::new(),
            addon_forum_lock: Arc::new(Mutex::new(())),
        }
    }

    fn log(&self, message: &str) {
        config::log(&self.paths.log, message);
    }

    fn show(&mut self, status: String) {
        self.base_status = status.clone();
        let tooltip = format!("Evertally Sync\n{status}");
        (self.publish)(UiState {
            live_status: self.live_status.clone(),
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
        // Network and archive work must never pause live positions or forum sync.
        // Dropping this sender when the worker exits stops the updater thread.
        let (update_stop, update_rx)=std::sync::mpsc::channel::<()>();
        let update_tx=self.tx.clone();
        let config_path=self.paths.config.clone();
        let addon_lock=Arc::clone(&self.addon_forum_lock);
        std::thread::spawn(move || {
            let mut updater=crate::addon_update::Updater::new(config_path.parent().unwrap_or_else(||std::path::Path::new(".")));let mut last=String::new();
            loop {
                let mut wait=Duration::from_secs(300);
                let config=if config_path.is_file(){crate::config::load_config(&config_path)}else{Err(anyhow::anyhow!("no config"))};
                let result=match &config {Ok(config)=>updater.check(config,&addon_lock),Err(_)=>Ok(None)};
                // A newer published installer replaces this app; setup closes the bridge and starts the new one.
                let app=match &config {Ok(config)=>crate::app_update::check(config_path.parent().unwrap_or_else(||std::path::Path::new(".")),config),Err(_)=>Ok(crate::app_update::Outcome::Nothing)};
                let cs=crate::platform::prefers_czech();
                let message=match result {
                    Ok(Some(true))=>if cs {"Addon je aktuální"}else{"Addon is up to date"}.to_owned(),
                    Ok(Some(false))=>{wait=Duration::from_secs(30);if cs {"Aktualizace addonu čeká na zavření WoW"}else{"Addon update waits for WoW to close"}.to_owned()},
                    Ok(None)=>String::new(),
                    Err(error)=>{wait=Duration::from_secs(60);format!("{}: {error}",if cs {"Aktualizace addonu selhala"}else{"Addon update failed"})},
                };
                let message=match app {
                    Ok(crate::app_update::Outcome::Started(version))=>format!("{} {version}",if cs {"Instaluji novou verzi aplikace"}else{"Installing new app version"}),
                    Ok(crate::app_update::Outcome::Nothing)=>message,
                    Err(error)=>{wait=Duration::from_secs(60);format!("{}: {error}",if cs {"Aktualizace aplikace selhala"}else{"App update failed"})},
                };
                if !message.is_empty() && message!=last {let _=update_tx.send(Command::AddonStatus(message.clone()));last=message;}
                match update_rx.recv_timeout(wait) {Ok(())|Err(RecvTimeoutError::Disconnected)=>break,Err(RecvTimeoutError::Timeout)=>{}}
            }
        });
        if let Err(error) = self.config.server_origin() {
            self.show(format!("{error}"));
        } else if self.token.is_none() {
            // Background startup must never steal focus or open a browser.
            // Pairing is an explicit action in the tray menu.
            self.show(self.texts.not_paired.to_owned());
        } else {
            self.sync_all(false);
        }

        let mut dirty: HashSet<PathBuf> = HashSet::new();
        let mut settle_at: Option<Instant> = None;
        let mut last_rescan = Instant::now();
        loop {
            if self.token.is_some() && self.live_poll.elapsed() >= Duration::from_secs(2) {
                self.live_step();
                self.live_poll = Instant::now();
            }
            if self.token.is_some() && self.forum_poll.elapsed() >= FORUM_EVERY {
                self.forum_poll = Instant::now();
                self.forum_step();
            }
            let timeout = settle_at
                .map_or(TICK, |at| at.saturating_duration_since(Instant::now()))
                .min(Duration::from_secs(2));
            match rx.recv_timeout(timeout) {
                Ok(Command::FileChanged(path)) => {
                    dirty.insert(path);
                    settle_at = Some(Instant::now() + SETTLE);
                }
                Ok(Command::AddonStatus(message)) => { self.log(&message);self.show(message); }
                Ok(Command::SyncNow) => {
                    self.refresh_watch();
                    self.sync_all(true);
                    self.forum_poll = Instant::now() - FORUM_EVERY;
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
                    self.live_status = None;
                    self.live_sent = None;
                    self.log("disconnected by user");
                    self.show(self.texts.not_paired.to_owned());
                }
                Ok(Command::Quit) | Err(RecvTimeoutError::Disconnected) => {drop(update_stop);return},
                Err(RecvTimeoutError::Timeout) => {
                    if settle_at.is_some_and(|at| at <= Instant::now()) {
                        settle_at = None;
                        let paths: Vec<PathBuf> = dirty
                            .drain()
                            .filter(|path| wow::is_export_file(path))
                            .collect();
                        if !paths.is_empty() {
                            self.sync_paths(&paths, true);
                        }
                        // the game saved its files: what was written in game is now in them
                        self.forum_poll = Instant::now() - FORUM_EVERY;
                    } else if last_rescan.elapsed() >= TICK {
                        last_rescan = Instant::now();
                        self.refresh_watch();
                        self.sync_all(false);
                    }
                }
            }
        }
    }

    /// Sends the forum posts written in game and writes the website's forum next to the addon. Never changes the status line:
    /// the forum is an extra, and a failure here must not hide the state of the export upload.
    fn forum_step(&mut self) {
        let Some(token) = self.token.clone() else {
            return;
        };
        if self.dirs.is_empty() {
            return;
        }
        let addon_lock=Arc::clone(&self.addon_forum_lock);
        let Ok(_guard)=addon_lock.lock() else { self.log("forum: addon update lock unavailable");return; };
        let outbox = crate::forum::read_outboxes(&self.dirs);
        let answer = match self.client.forum(&token, &outbox) {
            Ok(answer) => answer,
            Err(ApiError::Server { status: 401, .. }) => {
                self.log("forum: device token rejected; unpaired");
                self.tokens.clear();
                self.token = None;
                self.show(self.texts.disconnected.to_owned());
                return;
            }
            Err(error) => {
                self.log(&format!("forum: {error}"));
                return;
            }
        };
        if !outbox.is_empty() {
            self.log(&format!(
                "forum: sent {} written in game, accepted {}, already known {}, refused {}",
                outbox.len(),
                answer["accepted"],
                answer["duplicates"],
                answer["rejected"]
            ));
        }
        for dir in self.dirs.clone() {
            let Some(addon) = crate::forum::addon_folder(&dir) else {
                continue;
            };
            let text = crate::forum::data_file_for_addon(&answer, &addon);
            match crate::forum::write_if_changed(&addon.join(crate::forum::DATA_FILE), &text) {
                Ok(true) => self.log(&format!("forum: updated {}", addon.display())),
                Ok(false) => {}
                Err(error) => self.log(&format!("forum: cannot write {}: {error}", addon.display())),
            }
        }
    }

    fn live_step(&mut self) {
        let Some(token) = self.token.clone() else {
            return;
        };
        let marker = crate::optical::capture(self.config.wow_path.as_deref());
        let status = if let Some(marker) = marker {
            // Not compared with the PC's clock (it can be far off); the server checks the time.
            if !self.marker_fresh.moving(marker.t, Instant::now()) {
                self.texts.live_stale.to_owned()
            } else if let Ok(packet) = self.identity.resolve(&marker) {
                let character = packet.c["id"].as_str().unwrap_or("").to_owned();
                if self.live_sent.as_ref() == Some(&(character.clone(), packet.t)) {
                    return;
                }
                match self.client.live(&token, &packet) {
                    Ok(result) => self.record_live_result(character, packet.t, &result),
                    Err(ApiError::Server { status: 401, .. }) => {
                        self.token = None;
                        self.tokens.clear();
                        self.texts.disconnected.to_owned()
                    }
                    Err(error) => fill(self.texts.live_failed, &[("error", &error.to_string())]),
                }
            } else if self
                .identity
                .resolve(&marker)
                .is_err_and(|error| error == crate::optical::Unresolved::AmbiguousCharacter)
            {
                self.texts.live_ambiguous.to_owned()
            } else {
                self.texts.live_unknown.to_owned()
            }
        } else {
            self.texts.live_waiting.to_owned()
        };
        if self.live_status.as_ref() != Some(&status) {
            self.live_status = Some(status);
            self.show(self.base_status.clone());
        }
    }

    fn record_live_result(&mut self, character: String, at: u64, result: &LiveResult) -> String {
        // Acknowledged samples, including ignored duplicates, need not be retried every poll.
        // A new timestamp is still sent normally, without advancing the last accepted point on the server.
        self.live_sent = Some((character, at));
        if result.accepted == 1 {
            fill(self.texts.live_sent, &[("time", &platform::local_time())])
        } else {
            self.texts.live_ignored.to_owned()
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
            self.live_sent = None;
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
                        for path in event
                            .paths
                            .into_iter()
                            .filter(|p| wow::is_export_file(p) || wow::is_forum_file(p))
                        {
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
        self.identity.absorb(&envelope);
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
            live_status: self.live_status.clone(),
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
    fn only_a_stored_live_reply_reports_sent_and_ignored_samples_are_not_retried() {
        let dir =
            std::env::temp_dir().join(format!("evertally-live-result-test-{}", std::process::id()));
        let paths = Paths {
            config: dir.join("config.json"),
            state: dir.join("state.json"),
            log: dir.join("sync.log"),
            dir,
        };
        let (tx, _rx) = mpsc::channel();
        // An invalid origin prevents reading any real token. This test invokes neither capture nor HTTP.
        let mut worker = Worker::new(
            &crate::lang::EN,
            paths,
            Config {
                server: "http://invalid.example".into(),
                wow_path: None,
            },
            "http://127.0.0.1:9".into(),
            Box::new(|_| {}),
            tx,
            false,
        );
        let ignored = LiveResult {
            accepted: 0,
            expires_at: 130,
        };
        let status = worker.record_live_result("guid".into(), 100, &ignored);
        assert_eq!(status, crate::lang::EN.live_ignored);
        assert_eq!(worker.live_sent, Some(("guid".into(), 100)));
        let stored = LiveResult {
            accepted: 1,
            expires_at: 132,
        };
        let status = worker.record_live_result("guid".into(), 102, &stored);
        assert!(status.starts_with("Live position sent"));
        assert_eq!(worker.live_sent, Some(("guid".into(), 102)));
    }

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
    fn tray_first_launch_stays_local_until_pair_is_requested() {
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
            true,
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

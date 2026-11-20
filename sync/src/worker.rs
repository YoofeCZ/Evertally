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
/// Every stored live sample rewrites several database rows, and the free hosting tier allows only 100k writes a day.
const LIVE_EVERY: Duration = Duration::from_secs(10);
/// A position is sent only on an event (first sample, another map, the website asked) and otherwise this often.
const LIVE_HEARTBEAT: Duration = Duration::from_mins(5);
/// Catch-up and retry interval when nothing happens.
const TICK: Duration = Duration::from_mins(5);
const RETRY_EVERY: Duration = Duration::from_secs(30);
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
    CheckUpdate,
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
    rejected: HashMap<PathBuf, (SystemTime, String)>,
    retry_files: HashSet<PathBuf>,
    retry_at: Instant,
    open_browser: bool,
    /// The paired state last written for the addon (`None`: not yet).
    told_paired: Option<bool>,
    live_poll: Instant,
    forum_poll: Instant,
    live_sent: Option<(String, u64)>,
    /// The character and map of the last position sent, and when: what decides whether the next one says anything new.
    live_last: Option<(String, u32, Instant)>,
    /// The website asked where the player is; the next readable position is sent at once.
    locate: bool,
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
            rejected: HashMap::new(),
            retry_files: HashSet::new(),
            retry_at: Instant::now(),
            open_browser,
            told_paired: None,
            live_poll: Instant::now() - Duration::from_secs(5),
            forum_poll: Instant::now() - FORUM_EVERY,
            live_sent: None,
            live_last: None,
            locate: false,
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
        let update_trigger=update_stop.clone();
        let update_tx=self.tx.clone();
        let config_path=self.paths.config.clone();
        let addon_lock=Arc::clone(&self.addon_forum_lock);
        // Music control for the in-game player: commands from the pixel strip, the library back as MusicData.lua.
        let music_tx=self.tx.clone();
        crate::music::spawn(self.paths.config.clone(), move |note| { let _=music_tx.send(Command::AddonStatus(note)); });
        std::thread::spawn(move || {
            let mut updater=crate::addon_update::Updater::new(config_path.parent().unwrap_or_else(||std::path::Path::new(".")));let mut last=String::new();
            let mut community_at:Option<Instant>=None;
            loop {
                let mut wait=Duration::from_secs(300);
                let config=if config_path.is_file(){crate::config::load_config(&config_path)}else{Err(anyhow::anyhow!("no config"))};
                // This local proof works offline and without a paired device.
                if let Ok(config)=&config
                    && let Err(error)=crate::addon_update::write_installation_receipts(config,&addon_lock) {
                    let _=update_tx.send(Command::AddonStatus(format!("Installation receipt: {error}")));
                }
                // Updates download by themselves only when the player keeps that on (prefs.json); the tray's
                // "Check for updates" asks anyway.
                let manual=crate::app_update::take_manual();if manual {last.clear();}
                let auto=manual || crate::prefs::load(config_path.parent().unwrap_or_else(||std::path::Path::new("."))).auto_update;
                let result=match &config {Ok(config) if auto=>updater.check(config,&addon_lock),_=>Ok(None)};
                if let Ok(config)=&config {let _=crate::addon_update::write_installation_receipts(config,&addon_lock);}
                // A newer published installer replaces this app; setup closes the bridge and starts the new one.
                let app=match &config {Ok(config) if auto=>crate::app_update::check(config_path.parent().unwrap_or_else(||std::path::Path::new(".")),config,manual),_=>Ok(crate::app_update::Outcome::Nothing)};
                let cs=crate::platform::prefers_czech();
                // The website's public facts for the in-game Website facts page: once an hour, and on a manual check.
                let community_note=match &config {
                    Ok(config) if manual || community_at.is_none_or(|at|at.elapsed()>=Duration::from_secs(3600)) => {
                        community_at=Some(Instant::now());
                        // The public leaderboard for the unit tooltip travels with the facts; one failing does not stop the other.
                        match config.server_origin() {
                            Ok(origin)=>{
                                let roots=crate::addon_update::roots(config);
                                let facts=crate::community::sync(&origin,&roots).err().map(|error|format!("{}: {error}",if cs {"Webová fakta se nenačetla"}else{"Website facts failed"}));
                                let ranks=crate::ranking::sync(&origin,&roots).err().map(|error|format!("{}: {error}",if cs {"Žebříček se nenačetl"}else{"Leaderboard failed"}));
                                facts.or(ranks)
                            }
                            Err(error)=>Some(format!("{}: {error}",if cs {"Webová fakta se nenačetla"}else{"Website facts failed"})),
                        }
                    }
                    _=>None,
                };
                let message=match result {
                    Ok(Some(crate::addon_update::Status::UpToDate))=>if cs {"Addon je aktuální"}else{"Addon is up to date"}.to_owned(),
                    Ok(Some(crate::addon_update::Status::Updated{version,restart}))=>{
                        let version=version.map(|v|format!(" {v}")).unwrap_or_default();
                        match (restart,cs) {
                            (true,true)=>format!("Addon aktualizován na{version}: restartuj WoW (/reload nestačí)"),
                            (true,false)=>format!("Addon updated to{version}: restart WoW (/reload is not enough)"),
                            (false,true)=>format!("Addon aktualizován na{version}"),
                            (false,false)=>format!("Addon updated to{version}"),
                        }
                    }
                    Ok(Some(crate::addon_update::Status::Waiting))=>{wait=Duration::from_secs(30);if cs {"Aktualizace addonu čeká na zavření WoW"}else{"Addon update waits for WoW to close"}.to_owned()},
                    Ok(None)=>String::new(),
                    Err(error)=>{wait=Duration::from_secs(60);format!("{}: {error}",if cs {"Aktualizace addonu selhala"}else{"Addon update failed"})},
                };
                let message=match app {
                    Ok(crate::app_update::Outcome::Started(version))=>format!("{} {version}",if cs {"Instaluji novou verzi aplikace"}else{"Installing new app version"}),
                    Ok(crate::app_update::Outcome::UpToDate) if message==if cs {"Addon je aktuální"}else{"Addon is up to date"} =>if cs {"Aplikace i addon jsou aktuální"}else{"App and addon are up to date"}.to_owned(),
                    Ok(crate::app_update::Outcome::Nothing|crate::app_update::Outcome::UpToDate)=>message,
                    Err(error)=>{wait=Duration::from_secs(60);format!("{}: {error}",if cs {"Aktualizace aplikace selhala"}else{"App update failed"})},
                };
                let message=match community_note {Some(note) if message.is_empty()=>note,_=>message};
                if !message.is_empty() {crate::app_update::set_status(message.clone());}
                if !message.is_empty() && message!=last {let _=update_tx.send(Command::AddonStatus(message.clone()));last=message;}
                match update_rx.recv_timeout(wait) {Err(RecvTimeoutError::Disconnected)=>break,Ok(())|Err(RecvTimeoutError::Timeout)=>{}}
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
            self.tell_addon_paired();
            if self.token.is_some() && !self.retry_files.is_empty() && self.retry_at.elapsed() >= RETRY_EVERY {
                self.retry_at = Instant::now();
                let files: Vec<_> = self.retry_files.iter().cloned().collect();
                self.sync_paths(&files, true);
            }
            if self.token.is_some() && self.live_poll.elapsed() >= LIVE_EVERY {
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
                // Update status has its own tray row and bridge snapshot field.
                // It must never overwrite the actual pairing/synchronization state.
                Ok(Command::AddonStatus(message)) => { self.log(&message); }
                Ok(Command::CheckUpdate) => {
                    crate::app_update::request_check();let _=update_trigger.send(());
                    let text=if crate::platform::prefers_czech() {"Kontroluji aktualizace…"}else{"Checking for updates…"};
                    crate::app_update::set_status(text.to_owned());
                }
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
                    self.live_last = None;
                    self.log("disconnected by user");
                    self.show(self.texts.not_paired.to_owned());
                }
                Ok(Command::Quit) | Err(RecvTimeoutError::Disconnected) => {drop(update_stop);return},
                Err(RecvTimeoutError::Timeout) => {
                    if settle_at.is_some_and(|at| at <= Instant::now()) {
                        settle_at = None;
                        let requests: Vec<PathBuf> = dirty.iter().filter(|path| wow::is_forum_file(path)).cloned().collect();
                        for path in requests {
                            if !self.game_requests(&path, rx) {
                                return;
                            }
                        }
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
        // The website asked where the player is: read the marker and send one position now.
        if answer["locate"].as_bool() == Some(true) && !self.locate {
            self.locate = true;
            self.live_poll = Instant::now() - LIVE_EVERY;
        }
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
                // Every stored position costs the server several written rows, so only something new is sent.
                let due = self.locate
                    || self.live_last.as_ref().is_none_or(|(who, map, at)| {
                        *who != character || *map != packet.m || at.elapsed() >= LIVE_HEARTBEAT
                    });
                if !due {
                    return;
                }
                match self.client.live(&token, &packet) {
                    Ok(result) => {
                        self.live_last = Some((character.clone(), packet.m, Instant::now()));
                        self.locate = false;
                        self.record_live_result(character, packet.t, &result)
                    }
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
            self.live_last = None;
            let _ = self.state.save(&self.paths.state);
        }
        self.config = config;
        self.watcher = None;
        self.dirs.clear();
        self.processed.clear();
        self.rejected.clear();
        self.retry_files.clear();
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
            if !force && let Some((before, message)) = self.rejected.get(path) && before == &modified {
                problem = Some(message.clone());
                continue;
            }
            self.rejected.remove(path);
            self.retry_files.remove(path);
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
                    if self.retry_files.is_empty() { self.retry_at = Instant::now(); }
                    self.retry_files.insert(path.clone());
                    continue;
                }
                FileResult::Rejected(message) => {
                    self.rejected.insert(path.clone(), (modified, message.clone()));
                    problem = Some(message);
                    continue;
                }
            }
            self.processed.insert(path.clone(), modified);
        }
        let time = platform::local_time();
        self.rejected.retain(|path, (before, _)| std::fs::metadata(path).and_then(|m|m.modified()).is_ok_and(|at|at==*before));
        problem = problem.or_else(|| self.rejected.values().next().map(|(_,message)|message.clone()));
        let status = if let Some(message) = problem {
            message
        } else if retry || !self.retry_files.is_empty() {
            self.texts.offline.to_owned()
        } else if uploaded > 0 {
            fill(
                self.texts.uploaded,
                &[("count", &uploaded.to_string()), ("time", &time)],
            )
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
            Ok(Plan::UpToDate) => { self.acknowledge(path, &envelope); return FileResult::UpToDate; }
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
                    self.acknowledge(path, &envelope);
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

    fn acknowledge(&self, path: &std::path::Path, envelope: &serde_json::Value) {
        let Some(folder)=path.parent() else {return};
        let Ok(_guard)=self.addon_forum_lock.lock() else {return};
        if let Err(error)=crate::ack::write(folder,envelope,&self.state) {
            self.log(&format!("cannot acknowledge uploaded export: {error:#}"));
        }
    }

    /// Runs the pairing flow. Returns `false` when the app should quit.
    fn pair(&mut self, rx: &Receiver<Command>) -> bool {
        let open = self.open_browser;
        self.pair_opening(rx, open)
    }

    /// Acts on what the player asked for in the game (see [`crate::game_requests`]). Returns `false` when the app should quit.
    fn game_requests(&mut self, path: &std::path::Path, rx: &Receiver<Command>) -> bool {
        let Ok(text) = std::fs::read_to_string(path) else { return true };
        let Some(requests) = crate::game_requests::extract(&text) else { return true };
        let file = self.paths.dir.join("game-requests.json");
        let mut handled = crate::game_requests::load(&file);
        let (pair, autostart) = crate::game_requests::pending(requests, handled);
        if pair.is_none() && autostart.is_none() {
            return true;
        }
        if let Some((on, at)) = autostart {
            handled.autostart_at = at;
            if crate::platform::autostart_enabled() != on {
                match crate::platform::set_autostart(on) {
                    Ok(()) => self.log(&format!("start with WoW turned {} in the game", if on { "on" } else { "off" })),
                    Err(error) => self.log(&format!("start with WoW could not be changed: {error:#}")),
                }
            }
        }
        if let Some(at) = pair {
            handled.pair_at = at;
        }
        if let Err(error) = crate::game_requests::save(&file, handled) {
            self.log(&format!("cannot remember the game's request: {error}"));
        }
        self.told_paired = None; // the autostart line changed too: write the file for the addon again
        self.tell_addon_paired();
        match pair {
            Some(at) if self.token.is_none() && crate::game_requests::fresh(at, crate::bridge::now()) => {
                self.log("pairing requested in the game");
                self.pair_opening(rx, true)
            }
            _ => true,
        }
    }

    /// Writes the paired state (and the start-with-WoW state) into the file the addon reads, when it changed.
    fn tell_addon_paired(&mut self) {
        let paired = self.token.is_some();
        if self.told_paired == Some(paired) {
            return;
        }
        self.told_paired = Some(paired);
        crate::addon_update::set_paired(paired);
        if let Err(error) = crate::addon_update::write_installation_receipts(&self.config, &self.addon_forum_lock) {
            self.log(&format!("installation receipt: {error:#}"));
        }
    }

    fn pair_opening(&mut self, rx: &Receiver<Command>, browser: bool) -> bool {
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
        if browser {
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

    fn scratch_worker(label:&str)->(Worker,Arc<Mutex<Vec<UiState>>>,PathBuf){
        let dir=std::env::temp_dir().join(format!("evertally-sync-{label}-{}",std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let paths=Paths{config:dir.join("config.json"),state:dir.join("state.json"),log:dir.join("sync.log"),dir:dir.clone()};
        let states=Arc::new(Mutex::new(Vec::new()));let capture=Arc::clone(&states);
        let (tx,_)=mpsc::channel();
        let mut worker=Worker::new(&crate::lang::EN,paths,Config{server:"http://invalid.example".into(),wow_path:None},"http://127.0.0.1:9".into(),Box::new(move|state|capture.lock().unwrap().push(state)),tx,false);
        worker.token=Some("fixture-token".into());
        (worker,states,dir)
    }

    #[test]
    fn rejected_unchanged_exports_never_turn_into_up_to_date_on_rescan(){
        let (mut worker,states,dir)=scratch_worker("rejection");
        let path=dir.join(wow::EXPORT_FILE);std::fs::write(&path,"fixture").unwrap();
        let at=std::fs::metadata(&path).unwrap().modified().unwrap();
        worker.rejected.insert(path.clone(),(at,"Batch refused".into()));
        worker.sync_paths(&[path.clone()],false);
        worker.sync_paths(&[],false);
        assert!(states.lock().unwrap().iter().all(|s|s.status=="Batch refused"));
        assert!(!worker.processed.contains_key(&path));
        std::fs::remove_file(path).unwrap();
    }

    #[test]
    fn partial_save_is_queued_for_retry_and_cleared_only_after_a_readable_save(){
        let (mut worker,states,dir)=scratch_worker("retry");
        let path=dir.join(wow::EXPORT_FILE);std::fs::write(&path,[255]).unwrap();
        worker.sync_paths(&[path.clone()],true);
        assert!(worker.retry_files.contains(&path));assert!(!worker.processed.contains_key(&path));
        assert_eq!(states.lock().unwrap().last().unwrap().status,crate::lang::EN.offline);
        std::fs::write(&path,"EvertallyExportDB={enabled=true,producerId='fixture',consentEpoch=1,events={}}").unwrap();
        worker.sync_paths(&[path.clone()],true);
        assert!(!worker.retry_files.contains(&path));assert!(worker.processed.contains_key(&path));
        std::fs::remove_file(path).unwrap();
    }

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
        tx.send(Command::AddonStatus("Addon updated to 0.9.22".into())).expect("queue update status");
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
        assert!(states.iter().all(|state|state.status!="Addon updated to 0.9.22"),"update notifications must not replace synchronization state");
    }
}

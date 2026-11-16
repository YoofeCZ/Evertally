//! Music for the in-game player (`addon/Evertally/Music.lua`).
//!
//! The game cannot reach the network or play a stream, so the app does it. Commands come from the pixel strip the addon
//! draws in the corner of the game window (`optical::decode_command`, read a few times a second); the library goes back
//! in `MusicData.lua`, which the game loads at login and `/reload`. Playback control goes through the Windows media
//! controls, so it works with any player; Spotify (Web API with the player's own Client ID) and YouTube Music (an app
//! window of Chrome or Edge) add the library, playing a chosen item and search. No input is sent to the game and no game
//! memory is read.
pub mod command;
pub mod library;
pub mod spotify;
pub mod youtube;
#[cfg(windows)]
pub mod media;

use command::{Command, Source};
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

const POLL: Duration = Duration::from_millis(150);
const DUCKED: f32 = 0.3;

/// What the player chose, kept next to the app's settings (`music.json`); no secrets (the Spotify sign-in is in the
/// Windows credential store).
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct State {
    pub source: Option<Source>,
    pub spotify_client_id: Option<String>,
    #[serde(skip)]
    pub volume_before_duck: Option<f32>,
}

impl State {
    #[must_use]
    pub fn load(path: &Path) -> Self {
        std::fs::read_to_string(path).ok().and_then(|t| serde_json::from_str(&t).ok()).unwrap_or_default()
    }
    pub fn save(&self, path: &Path) {
        if let Ok(text) = serde_json::to_string_pretty(self) {
            let _ = std::fs::write(path, text);
        }
    }
}

fn now() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)
}

/// A loopback port held while a music thread runs: the bridge and the settings window may both start a worker, and two
/// readers of the strip would act on every command twice (pause, then play again).
const LOCK_PORT: u16 = 47_833;

/// Starts the music thread unless one already runs on this PC; it lives as long as the app.
pub fn spawn(config_path: PathBuf, log: impl Fn(String) + Send + 'static) {
    let Ok(lock) = std::net::TcpListener::bind(("127.0.0.1", LOCK_PORT)) else {
        return;
    };
    let _ = std::thread::Builder::new().name("music".into()).spawn(move || {
        let _lock = lock;
        run(&config_path, &log);
    });
}

struct Music {
    dir: PathBuf,
    state: State,
    spotify: Option<spotify::Spotify>,
    /// The library last written, so a search only adds its results instead of reading everything again.
    last: Option<library::Library>,
}

impl Music {
    fn profile(&self) -> PathBuf {
        self.dir.join("youtube-music-profile")
    }

    fn spotify(&mut self) -> Option<&mut spotify::Spotify> {
        let id = self.state.spotify_client_id.clone()?;
        if self.spotify.is_none() {
            self.spotify = Some(spotify::Spotify::new(&id));
        }
        self.spotify.as_mut()
    }

    fn library(&mut self, config_path: &Path) -> anyhow::Result<usize> {
        let library = match self.state.source {
            Some(Source::Youtube) => youtube::library(&self.profile())?,
            _ => {
                let profile_free = self.spotify().ok_or_else(|| anyhow::anyhow!("enter your Spotify Client ID in the game's music window first"))?;
                if !profile_free.signed_in() {
                    profile_free.sign_in()?;
                }
                profile_free.library()?
            }
        };
        self.last = Some(library);
        self.write(config_path)
    }

    fn write(&mut self, config_path: &Path) -> anyhow::Result<usize> {
        // what Windows says plays right now is fresher than what the service reported with the library
        #[cfg(windows)]
        if let Ok((_, Some(title))) = media::now_playing()
            && let Some(library) = self.last.as_mut()
        {
            library.now_playing = Some(library::Item { name: title, ..library::Item::default() });
        }
        let library = self.last.as_ref().ok_or_else(|| anyhow::anyhow!("no library yet"))?;
        let config = crate::config::load_config(config_path)?;
        Ok(library::write(&crate::addon_update::roots(&config), library, now())?)
    }

    /// The search results go into the library file under their own tab; the window and the playing song are left alone.
    fn search(&mut self, text: &str, config_path: &Path) -> anyhow::Result<usize> {
        let found = match self.state.source {
            Some(Source::Youtube) => youtube::search(&self.profile(), text)?,
            _ => self.spotify().ok_or_else(|| anyhow::anyhow!("enter your Spotify Client ID first"))?.search(text)?,
        };
        if self.last.as_ref().is_none_or(|l| Some(l.source) != self.state.source.or(Some(Source::Spotify))) {
            self.library(config_path)?;
        }
        if let Some(library) = self.last.as_mut() {
            library.search = found;
            library.query = Some(text.to_owned());
        }
        self.write(config_path)
    }

    fn play(&mut self, id: &str, within: Option<&str>) -> anyhow::Result<()> {
        if id.starts_with("yt:") {
            youtube::play(&self.profile(), id, within)
        } else if let Some(s) = self.spotify() {
            s.play(id, within)
        } else {
            Ok(open::that(id)?)
        }
    }

    fn handle(&mut self, command: Command, config_path: &Path) -> anyhow::Result<String> {
        let state_path = self.dir.join("music.json");
        match command {
            Command::Source(source) => {
                self.state.source = Some(source);
                self.state.save(&state_path);
                if source == Source::Youtube {
                    youtube::ensure_window(&self.profile())?;
                }
                Ok(format!("music: source {source:?}"))
            }
            Command::SpotifyClient(id) => {
                self.state.spotify_client_id = Some(id);
                self.state.source = Some(Source::Spotify);
                self.state.save(&state_path);
                self.spotify = None;
                if let Some(s) = self.spotify() {
                    s.sign_in()?;
                }
                Ok("music: Spotify connected".into())
            }
            Command::Library => self.library(config_path).map(|n| format!("music: library written to {n} folder(s)")),
            Command::PlayItem(id) => {
                self.play(&id, None)?;
                Ok(format!("music: play {id}"))
            }
            Command::PlayInPlaylist { song, playlist } => {
                self.play(&song, Some(&playlist))?;
                Ok(format!("music: play {song} in {playlist}"))
            }
            Command::Search(text) => self.search(&text, config_path).map(|n| format!("music: search results written to {n} folder(s)")),
            Command::SpotifyDashboard => {
                open::that(spotify::DASHBOARD)?;
                Ok("music: Spotify dashboard opened".into())
            }
            Command::Open => {
                match self.state.source {
                    Some(Source::Youtube) => youtube::ensure_window(&self.profile())?,
                    _ => open::that("spotify:")?,
                }
                Ok("music: open".into())
            }
            other => self.control(&other),
        }
    }

    #[cfg(windows)]
    fn control(&mut self, command: &Command) -> anyhow::Result<String> {
        match command {
            Command::Toggle => media::toggle()?,
            Command::Play => media::play()?,
            Command::Pause => media::pause()?,
            Command::Next => media::next()?,
            Command::Previous => media::previous()?,
            Command::VolumeUp | Command::VolumeDown => {
                let level = media::volume()?.unwrap_or(1.0);
                let step = if *command == Command::VolumeUp { 0.1 } else { -0.1 };
                media::set_volume(level + step)?;
            }
            Command::Duck => {
                if self.state.volume_before_duck.is_none() {
                    let level = media::volume()?.unwrap_or(1.0);
                    self.state.volume_before_duck = Some(level);
                    media::set_volume(level * DUCKED)?;
                }
            }
            Command::Unduck => {
                if let Some(level) = self.state.volume_before_duck.take() {
                    media::set_volume(level)?;
                }
            }
            _ => {}
        }
        Ok(format!("music: {command:?}"))
    }

    #[cfg(not(windows))]
    fn control(&mut self, command: &Command) -> anyhow::Result<String> {
        Err(anyhow::anyhow!("music control needs Windows ({command:?})"))
    }
}

/// What the notification says when a setup command arrives (playback buttons stay quiet).
fn heard(command: &Command, cs: bool) -> Option<&'static str> {
    Some(match command {
        Command::SpotifyClient(_) if cs => "Přihlášení ke Spotify: otevírám prohlížeč.",
        Command::SpotifyClient(_) => "Spotify sign-in: opening the browser.",
        Command::Library if cs => "Načítám knihovnu…",
        Command::Library => "Reading the library…",
        Command::Search(_) if cs => "Hledám…",
        Command::Search(_) => "Searching…",
        Command::Source(Source::Youtube) if cs => "Zdroj hudby: YouTube Music.",
        Command::Source(Source::Youtube) => "Music source: YouTube Music.",
        Command::Source(Source::Spotify) if cs => "Zdroj hudby: Spotify.",
        Command::Source(Source::Spotify) => "Music source: Spotify.",
        Command::SpotifyDashboard if cs => "Otevírám Spotify Dashboard.",
        Command::SpotifyDashboard => "Opening the Spotify Dashboard.",
        _ => return None,
    })
}

/// What the notification says when a command that the game waits for is done.
fn done(command: &Command, cs: bool) -> Option<&'static str> {
    Some(match command {
        Command::SpotifyClient(_) if cs => "Spotify je připojený. Ve hře stiskni Obnovit knihovnu.",
        Command::SpotifyClient(_) => "Spotify is connected. Press Refresh library in the game.",
        Command::Library | Command::Search(_) if cs => "Hotovo. Ve hře stiskni Načíst knihovnu (reload).",
        Command::Library | Command::Search(_) => "Done. Press Load library (reload) in the game.",
        _ => return None,
    })
}

fn run(config_path: &Path, log: &dyn Fn(String)) {
    #[cfg(windows)]
    media::init_thread();
    let dir = config_path.parent().map(Path::to_path_buf).unwrap_or_default();
    let mut music = Music { state: State::load(&dir.join("music.json")), dir, spotify: None, last: None };
    let mut last: Option<(u8, String)> = None;
    let mut wow_path = None;
    let mut config_read = Instant::now() - Duration::from_secs(60);
    loop {
        if config_read.elapsed() >= Duration::from_secs(30) {
            config_read = Instant::now();
            wow_path = crate::config::load_config(config_path).ok().and_then(|c| c.wow_path);
        }
        #[cfg(windows)]
        let frame = crate::optical::capture_with(wow_path.as_deref(), crate::optical::decode_command);
        #[cfg(not(windows))]
        let frame: Option<crate::optical::CommandFrame> = { let _ = &wow_path; None };
        if let Some(frame) = frame {
            // The same command stays on screen for 0.6 s: it is acted on once.
            let key = (frame.seq, frame.text.clone());
            if last.as_ref() != Some(&key) {
                last = Some(key);
                if let Some(command) = command::parse(&frame.text) {
                    // A setup step the player pressed in the game gets a Windows notification at once: it is the only way the
                    // player can tell the app heard the game (nothing goes back into the game before a reload).
                    let cs = crate::platform::prefers_czech();
                    let heard = heard(&command, cs);
                    if let Some(text) = &heard {
                        crate::notify::message(if cs { "Evertally slyší hru" } else { "Evertally hears the game" }, text);
                    }
                    let done = done(&command, cs);
                    match music.handle(command, config_path) {
                        Ok(note) => {
                            if let Some(text) = done {
                                crate::notify::message("Evertally", text);
                            }
                            log(note);
                        }
                        Err(error) => {
                            crate::notify::message(if cs { "Evertally: hudba nefunguje" } else { "Evertally: music failed" }, &error.to_string());
                            log(format!("music: {error}"));
                        }
                    }
                }
            }
        }
        std::thread::sleep(POLL);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_choice_survives_a_restart_without_the_ducked_volume() {
        let dir = std::env::temp_dir().join(format!("evertally-music-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("music.json");
        let state = State { source: Some(Source::Youtube), spotify_client_id: Some("ab".into()), volume_before_duck: Some(0.5) };
        state.save(&path);
        let back = State::load(&path);
        assert_eq!(back.source, Some(Source::Youtube));
        assert_eq!(back.volume_before_duck, None);
        let _ = std::fs::remove_dir_all(dir);
    }
}

//! Spotify through the Web API with the player's own developer Client ID.
//!
//! A new Spotify app may only be used by a handful of accounts its owner adds by hand, so every player creates their own
//! (free, five minutes, guided in the game) and gives Evertally its Client ID. The ID is public; the sign-in is PKCE with a
//! loopback redirect (`http://127.0.0.1:8765/callback`), so no secret exists anywhere. The refresh token is kept in the
//! Windows credential store. Starting a given playlist or song through the API needs Spotify Premium; without it the
//! item opens in the Spotify app instead.
use super::library::{Item, Library};
use super::command::Source;
use anyhow::{Context, Result, anyhow, ensure};
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::io::{BufRead, BufReader, Write};
use std::net::TcpListener;
use std::time::{Duration, Instant};

pub const REDIRECT: &str = "http://127.0.0.1:8765/callback";
/// Where a player creates their own Spotify app (and so their Client ID).
pub const DASHBOARD: &str = "https://developer.spotify.com/dashboard";
const SCOPES: &str = "playlist-read-private user-library-read user-read-recently-played user-read-playback-state user-modify-playback-state user-read-currently-playing";
const KEYRING_SERVICE: &str = "Evertally Spotify";
const API: &str = "https://api.spotify.com/v1";
/// The most Spotify's search gives per type since February 2026.
const SEARCH_LIMIT: u32 = 10;
const _: () = assert!(SEARCH_LIMIT <= 10, "Spotify answers HTTP 400 to a larger search limit");

/// URL-safe base64 without padding (RFC 4648 §5), as PKCE wants it.
#[must_use]
pub fn base64url(bytes: &[u8]) -> String {
    const ABC: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    let mut out = String::with_capacity(bytes.len() * 4 / 3 + 2);
    for chunk in bytes.chunks(3) {
        let n = (u32::from(chunk[0]) << 16) | (u32::from(*chunk.get(1).unwrap_or(&0)) << 8) | u32::from(*chunk.get(2).unwrap_or(&0));
        for i in 0..=chunk.len() {
            out.push(ABC[((n >> (18 - 6 * i)) & 63) as usize] as char);
        }
    }
    out
}

/// The PKCE challenge of a verifier: base64url(SHA-256(verifier)).
#[must_use]
pub fn challenge(verifier: &str) -> String {
    base64url(&Sha256::digest(verifier.as_bytes()))
}

fn random(len: usize) -> Result<String> {
    let mut bytes = vec![0u8; len];
    getrandom::fill(&mut bytes).map_err(|e| anyhow!("no random source: {e}"))?;
    Ok(base64url(&bytes))
}

fn encode(value: &str) -> String {
    let mut out = String::new();
    for b in value.bytes() {
        if b.is_ascii_alphanumeric() || b"-_.~".contains(&b) {
            out.push(b as char);
        } else {
            out.push_str(&format!("%{b:02X}"));
        }
    }
    out
}

fn agent() -> ureq::Agent {
    ureq::Agent::config_builder()
        .timeout_global(Some(Duration::from_secs(20)))
        .http_status_as_error(false)
        .user_agent(concat!("EvertallySync/", env!("CARGO_PKG_VERSION")))
        .build()
        .into()
}

fn read(response: &mut ureq::http::Response<ureq::Body>) -> Result<Value> {
    let text = response.body_mut().read_to_string()?;
    if text.trim().is_empty() {
        return Ok(Value::Null);
    }
    serde_json::from_str(&text).context("Spotify sent something that is not JSON")
}

pub struct Spotify {
    client_id: String,
    access: Option<(String, Instant)>,
}

impl Spotify {
    #[must_use]
    pub fn new(client_id: &str) -> Self {
        Self { client_id: client_id.to_owned(), access: None }
    }

    fn store(&self) -> Result<keyring::Entry> {
        keyring::Entry::new(KEYRING_SERVICE, &self.client_id).context("open credential store")
    }

    #[must_use]
    pub fn signed_in(&self) -> bool {
        self.store().is_ok_and(|e| e.get_password().is_ok())
    }

    /// Opens Spotify's sign-in page in the browser and waits (up to five minutes) for the redirect to the loopback address.
    pub fn sign_in(&mut self) -> Result<()> {
        let verifier = random(48)?;
        let state = random(12)?;
        let listener = TcpListener::bind("127.0.0.1:8765").context("port 8765 on this PC is taken")?;
        listener.set_nonblocking(true)?;
        let url = format!(
            "https://accounts.spotify.com/authorize?client_id={}&response_type=code&redirect_uri={}&code_challenge_method=S256&code_challenge={}&state={}&scope={}",
            encode(&self.client_id), encode(REDIRECT), challenge(&verifier), state, encode(SCOPES)
        );
        open::that(&url).context("cannot open the browser")?;
        let deadline = Instant::now() + Duration::from_secs(300);
        let code = loop {
            ensure!(Instant::now() < deadline, "Spotify sign-in timed out");
            match listener.accept() {
                Ok((stream, _)) => {
                    stream.set_nonblocking(false)?;
                    let mut line = String::new();
                    BufReader::new(&stream).read_line(&mut line)?;
                    let query = line.split_whitespace().nth(1).and_then(|p| p.split_once('?')).map(|(_, q)| q.to_owned()).unwrap_or_default();
                    let param = |name: &str| query.split('&').find_map(|kv| kv.strip_prefix(&format!("{name}="))).map(str::to_owned);
                    let ok = param("state").as_deref() == Some(state.as_str()) && param("code").is_some();
                    let body = if ok { "Evertally: Spotify is connected. You can close this tab. / Spotify je připojený, kartu můžeš zavřít." } else { "Evertally: Spotify sign-in failed. / Přihlášení ke Spotify se nepovedlo." };
                    let mut writer = &stream;
                    let _ = write!(writer, "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}", body.len());
                    if ok {
                        break param("code").unwrap_or_default();
                    }
                    if param("error").is_some() {
                        return Err(anyhow!("Spotify refused the sign-in"));
                    }
                }
                Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => std::thread::sleep(Duration::from_millis(200)),
                Err(e) => return Err(e.into()),
            }
        };
        let mut response = agent()
            .post("https://accounts.spotify.com/api/token")
            .send_form([
                ("grant_type", "authorization_code"),
                ("code", code.as_str()),
                ("redirect_uri", REDIRECT),
                ("client_id", self.client_id.as_str()),
                ("code_verifier", verifier.as_str()),
            ])?;
        let value = read(&mut response)?;
        self.keep(&value)
    }

    fn keep(&mut self, value: &Value) -> Result<()> {
        let access = value["access_token"].as_str().context("Spotify gave no access token")?;
        let expires = value["expires_in"].as_u64().unwrap_or(3600);
        self.access = Some((access.to_owned(), Instant::now() + Duration::from_secs(expires.saturating_sub(60))));
        if let Some(refresh) = value["refresh_token"].as_str() {
            self.store()?.set_password(refresh).context("cannot keep the Spotify sign-in")?;
        }
        Ok(())
    }

    fn token(&mut self) -> Result<String> {
        if let Some((token, until)) = &self.access
            && Instant::now() < *until
        {
            return Ok(token.clone());
        }
        let refresh = self.store()?.get_password().context("not signed in to Spotify")?;
        let mut response = agent()
            .post("https://accounts.spotify.com/api/token")
            .send_form([("grant_type", "refresh_token"), ("refresh_token", refresh.as_str()), ("client_id", self.client_id.as_str())])?;
        let value = read(&mut response)?;
        self.keep(&value)?;
        self.access.as_ref().map(|(t, _)| t.clone()).context("no Spotify token")
    }

    fn get(&mut self, path: &str) -> Result<Value> {
        let token = self.token()?;
        let mut response = agent().get(&format!("{API}{path}")).header("Authorization", &format!("Bearer {token}")).call()?;
        let status = response.status().as_u16();
        let value = read(&mut response)?;
        // Spotify's own reason ("Invalid limit") goes into the notification and the log, not just the number
        ensure!((200..300).contains(&status), "Spotify answered HTTP {status}: {}", value["error"]["message"].as_str().unwrap_or("no reason given"));
        Ok(value)
    }

    /// Playlists, liked songs and recently played, at most 50 of each, what plays now, and the songs of each playlist.
    pub fn library(&mut self) -> Result<Library> {
        let playlists = self.get("/me/playlists?limit=50")?;
        let liked = self.get("/me/tracks?limit=50")?;
        let recent = self.get("/me/player/recently-played?limit=50").unwrap_or(Value::Null);
        let now = self.get("/me/player/currently-playing").unwrap_or(Value::Null);
        let mut library = parse_library(&playlists, &liked, &recent, &now);
        for playlist in library.playlists.iter_mut().take(super::library::MAX_OPENED) {
            playlist.tracks = self.playlist_tracks(&playlist.id);
        }
        Ok(library)
    }

    /// The first songs of a playlist. Spotify gives them only for the player's own and collaborative playlists to an app
    /// in development mode (which every player's own app is), so a refusal leaves the playlist closed, not the library.
    fn playlist_tracks(&mut self, uri: &str) -> Vec<Item> {
        let Some(id) = uri.strip_prefix("spotify:playlist:") else { return Vec::new() };
        let mut out = Vec::new();
        let mut offset = 0;
        while out.len() < super::library::MAX_TRACKS {
            let Ok(page) = self.get(&format!("/playlists/{}/items?limit=50&offset={offset}", encode(id))) else { break };
            let before = out.len();
            out.extend(parse_playlist_items(&page));
            let fetched = page["items"].as_array().map_or(0, Vec::len);
            if fetched == 0 || page["next"].is_null() || out.len() == before {
                break;
            }
            offset += fetched;
        }
        out.truncate(super::library::MAX_TRACKS);
        out
    }

    /// Spotify's search (songs and playlists), for the game's list; works without Premium. Since February 2026 Spotify
    /// refuses a `limit` above 10 (HTTP 400), which left the game's results empty with `limit=20`.
    pub fn search(&mut self, text: &str) -> Result<Vec<Item>> {
        let value = self.get(&format!("/search?type=track,playlist&limit={SEARCH_LIMIT}&q={}", encode(text)))?;
        Ok(parse_search(&value))
    }

    /// Plays a `spotify:` item; with `within` (a playlist) a song plays inside it, so the playlist goes on after it.
    /// Without Premium (HTTP 403) or without a device, the item opens in the Spotify app instead.
    pub fn play(&mut self, uri: &str, within: Option<&str>) -> Result<()> {
        let body = match within {
            Some(context) => serde_json::json!({"context_uri":context,"offset":{"uri":uri}}),
            None if uri.starts_with("spotify:track:") => serde_json::json!({"uris":[uri]}),
            None => serde_json::json!({"context_uri":uri}),
        };
        let played = self.token().and_then(|token| {
            let response = agent()
                .put(&format!("{API}/me/player/play"))
                .header("Authorization", &format!("Bearer {token}"))
                .header("Content-Type", "application/json")
                .send(serde_json::to_vec(&body)?.as_slice())?;
            Ok(response.status().is_success())
        });
        if !played.unwrap_or(false) {
            open::that(uri).context("cannot open Spotify")?;
        }
        Ok(())
    }
}

#[must_use]
pub fn parse_search(value: &Value) -> Vec<Item> {
    let mut out: Vec<Item> = value["tracks"]["items"].as_array().into_iter().flatten().filter_map(track).collect();
    out.extend(value["playlists"]["items"].as_array().into_iter().flatten().filter_map(|p| {
        Some(Item {
            id: p["uri"].as_str()?.to_owned(),
            name: p["name"].as_str()?.to_owned(),
            artist: p["owner"]["display_name"].as_str().map(str::to_owned),
            ..Item::default()
        })
    }));
    out
}

fn track(value: &Value) -> Option<Item> {
    Some(Item {
        id: value["uri"].as_str()?.to_owned(),
        name: value["name"].as_str()?.to_owned(),
        artist: value["artists"][0]["name"].as_str().map(str::to_owned),
        ..Item::default()
    })
}

/// A page of `/playlists/{id}/items`: each entry has the song under `item` (named `track` before February 2026);
/// podcast episodes and local files without a `spotify:track:` URI are left out.
#[must_use]
pub fn parse_playlist_items(value: &Value) -> Vec<Item> {
    value["items"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|e| track(if e["item"].is_object() { &e["item"] } else { &e["track"] }))
        .filter(|t| t.id.starts_with("spotify:track:"))
        .collect()
}

#[must_use]
pub fn parse_library(playlists: &Value, liked: &Value, recent: &Value, now: &Value) -> Library {
    let list = |v: &Value| v["items"].as_array().cloned().unwrap_or_default();
    Library {
        source: Source::Spotify,
        playlists: list(playlists)
            .iter()
            .filter_map(|p| {
                Some(Item {
                    id: p["uri"].as_str()?.to_owned(),
                    name: p["name"].as_str()?.to_owned(),
                    artist: p["owner"]["display_name"].as_str().map(str::to_owned),
                    // `items` since February 2026, `tracks` before
                    count: p["items"]["total"].as_u64().or_else(|| p["tracks"]["total"].as_u64()).and_then(|n| u32::try_from(n).ok()),
                    ..Item::default()
                })
            })
            .collect(),
        liked: list(liked).iter().filter_map(|i| track(&i["track"])).collect(),
        recent: list(recent).iter().filter_map(|i| track(&i["track"])).collect(),
        now_playing: track(&now["item"]),
        search: Vec::new(),
        query: None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn pkce_challenge_matches_the_rfc_7636_example() {
        assert_eq!(challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM");
        assert_eq!(base64url(b"f"), "Zg");
        assert_eq!(base64url(b"foobar"), "Zm9vYmFy");
    }

    #[test]
    fn search_answers_list_songs_then_playlists_and_skip_empty_slots() {
        let found = parse_search(&json!({"tracks":{"items":[{"uri":"spotify:track:1","name":"Lose Yourself","artists":[{"name":"Eminem"}]}]},
            "playlists":{"items":[null,{"uri":"spotify:playlist:p","name":"This Is Eminem","owner":{"display_name":"Spotify"}}]}}));
        assert_eq!(found.iter().map(|i| i.name.as_str()).collect::<Vec<_>>(), ["Lose Yourself", "This Is Eminem"]);
    }

    #[test]
    fn the_library_is_read_from_spotify_answers() {
        let lib = parse_library(
            &json!({"items":[{"uri":"spotify:playlist:abc","name":"Leveling","owner":{"display_name":"me"},"tracks":{"total":40}},{"name":"no uri"}]}),
            &json!({"items":[{"track":{"uri":"spotify:track:1","name":"Song","artists":[{"name":"Čechomor"}]}}]}),
            &Value::Null,
            &json!({"item":{"uri":"spotify:track:2","name":"Now","artists":[]}}),
        );
        assert_eq!(lib.playlists.len(), 1);
        assert_eq!(lib.playlists[0].count, Some(40));
        assert_eq!(lib.liked[0].artist.as_deref(), Some("Čechomor"));
        assert!(lib.recent.is_empty());
        assert_eq!(lib.now_playing.map(|n| n.name), Some("Now".to_owned()));
        let renamed = parse_library(&json!({"items":[{"uri":"spotify:playlist:x","name":"New","items":{"total":7}}]}), &Value::Null, &Value::Null, &Value::Null);
        assert_eq!(renamed.playlists[0].count, Some(7));
    }

    #[test]
    fn playlist_pages_give_songs_under_item_or_the_old_track() {
        let songs = parse_playlist_items(&json!({"items":[
            {"item":{"uri":"spotify:track:1","name":"New field","artists":[{"name":"A"}]}},
            {"track":{"uri":"spotify:track:2","name":"Old field","artists":[]}},
            {"item":{"uri":"spotify:episode:3","name":"A podcast"}},
            {"item":null}]}));
        assert_eq!(songs.iter().map(|s| s.name.as_str()).collect::<Vec<_>>(), ["New field", "Old field"]);
    }}

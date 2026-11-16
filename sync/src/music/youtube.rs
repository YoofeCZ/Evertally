//! YouTube Music in an app window of the player's Chrome or Edge, with a profile of its own (browsers no longer let other
//! programs drive the everyday profile). The window is driven through the browser's DevTools protocol on a loopback port:
//! open a playlist, a song or a search, and read the library from the page the player is signed in to. YouTube Music has
//! no public API for a personal library, so this reads what the signed-in page reads; a change on YouTube's side can break
//! the library list, never the playback controls (those go through Windows, see `media.rs`).
use super::command::Source;
use super::library::{Item, Library};
use anyhow::{Context, Result, anyhow};
use serde_json::{Value, json};
use std::net::TcpStream;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

pub const PORT: u16 = 9233;
const HOME: &str = "https://music.youtube.com/";

/// The installed Chrome or Edge, Chrome first.
#[must_use]
pub fn browser() -> Option<PathBuf> {
    let mut candidates = Vec::new();
    for var in ["ProgramFiles", "ProgramFiles(x86)", "LOCALAPPDATA"] {
        if let Some(base) = std::env::var_os(var) {
            let base = PathBuf::from(base);
            candidates.push(base.join("Google/Chrome/Application/chrome.exe"));
            candidates.push(base.join("Microsoft/Edge/Application/msedge.exe"));
        }
    }
    candidates.sort_by_key(|p| !p.to_string_lossy().to_ascii_lowercase().contains("chrome"));
    candidates.into_iter().find(|p| p.is_file())
}

fn devtools_up() -> bool {
    TcpStream::connect_timeout(&([127, 0, 0, 1], PORT).into(), Duration::from_millis(300)).is_ok()
}

/// Starts the YouTube Music window unless it already runs; `profile` is the window's own browser profile folder.
pub fn ensure_window(profile: &Path) -> Result<()> {
    if devtools_up() {
        return Ok(());
    }
    let exe = browser().context("neither Chrome nor Edge is installed")?;
    std::fs::create_dir_all(profile)?;
    std::process::Command::new(exe)
        .arg(format!("--app={HOME}"))
        .arg(format!("--user-data-dir={}", profile.display()))
        .arg(format!("--remote-debugging-port={PORT}"))
        .arg("--remote-allow-origins=http://127.0.0.1")
        .arg("--autoplay-policy=no-user-gesture-required")
        .arg("--no-first-run")
        .spawn()
        .context("cannot start the YouTube Music window")?;
    let deadline = Instant::now() + Duration::from_secs(15);
    while Instant::now() < deadline {
        if devtools_up() {
            return Ok(());
        }
        std::thread::sleep(Duration::from_millis(300));
    }
    Err(anyhow!("the YouTube Music window did not start"))
}

fn page_socket() -> Result<String> {
    let agent: ureq::Agent = ureq::Agent::config_builder().timeout_global(Some(Duration::from_secs(5))).build().into();
    let list: Value = serde_json::from_str(&agent.get(&format!("http://127.0.0.1:{PORT}/json/list")).call()?.body_mut().read_to_string()?)?;
    list.as_array()
        .into_iter()
        .flatten()
        .find(|t| t["type"] == "page" && t["url"].as_str().is_some_and(|u| u.starts_with(HOME)))
        .and_then(|t| t["webSocketDebuggerUrl"].as_str().map(str::to_owned))
        .filter(|u| u.starts_with(&format!("ws://127.0.0.1:{PORT}/")))
        .context("no YouTube Music page in the window")
}

/// One DevTools call on the YouTube Music page.
fn call(method: &str, params: Value) -> Result<Value> {
    let url = page_socket()?;
    let (mut socket, _) = tungstenite::connect(url.as_str()).context("cannot reach the YouTube Music window")?;
    if let tungstenite::stream::MaybeTlsStream::Plain(stream) = socket.get_ref() {
        // the library reads every playlist's songs too (in batches, a few seconds each)
        stream.set_read_timeout(Some(Duration::from_secs(90)))?;
    }
    socket.send(tungstenite::Message::text(json!({"id":1,"method":method,"params":params}).to_string()))?;
    loop {
        let message = socket.read()?;
        if let tungstenite::Message::Text(text) = message {
            let value: Value = serde_json::from_str(text.as_str())?;
            if value["id"] == 1 {
                let _ = socket.close(None);
                if let Some(error) = value.get("error") {
                    return Err(anyhow!("YouTube Music window: {error}"));
                }
                return Ok(value["result"].clone());
            }
        }
    }
}

fn navigate(url: &str) -> Result<()> {
    call("Page.navigate", json!({"url":url})).map(|_| ())
}

fn encode(text: &str) -> String {
    text.bytes()
        .map(|b| if b.is_ascii_alphanumeric() || b"-_.~".contains(&b) { (b as char).to_string() } else { format!("%{b:02X}") })
        .collect()
}

/// `yt:playlist:ID` plays the playlist, `yt:video:ID` the song; a song `within` a playlist plays there, so the playlist
/// goes on after it.
pub fn play(profile: &Path, id: &str, within: Option<&str>) -> Result<()> {
    ensure_window(profile)?;
    navigate(&watch_url(id, within)?)
}

fn watch_url(id: &str, within: Option<&str>) -> Result<String> {
    if let Some(list) = id.strip_prefix("yt:playlist:") {
        return Ok(format!("{HOME}watch?list={}", encode(list)));
    }
    let video = id.strip_prefix("yt:video:").ok_or_else(|| anyhow!("not a YouTube Music item"))?;
    Ok(match within.and_then(|w| w.strip_prefix("yt:playlist:")) {
        Some(list) => format!("{HOME}watch?v={}&list={}", encode(video), encode(list)),
        None => format!("{HOME}watch?v={}", encode(video)),
    })
}

/// Searches YouTube Music in the background of the page (the window keeps playing) and returns songs and playlists.
pub fn search(profile: &Path, text: &str) -> Result<Vec<Item>> {
    ensure_window(profile)?;
    let query = serde_json::to_string(text)?;
    let script = SEARCH_JS.replace("__QUERY__", &query);
    let result = call("Runtime.evaluate", json!({"expression":script,"awaitPromise":true,"returnByValue":true}))?;
    let text = result["result"]["value"].as_str().context("the YouTube Music page gave no search results")?;
    let value: Value = serde_json::from_str(text)?;
    Ok(parse_library(&json!({"playlists": value})).map(|l| l.playlists).unwrap_or_default())
}

/// Like the library script, for one search: the same signed-in request YouTube Music's own search box sends.
const SEARCH_JS: &str = r#"(async () => {
  const c = (window.ytcfg && ytcfg.data_) || {};
  const sap = (document.cookie.match(/(?:^|; )SAPISID=([^;]+)/) || [])[1];
  const headers = {'content-type': 'application/json', 'x-youtube-client-name': '67', 'x-youtube-client-version': c.INNERTUBE_CLIENT_VERSION || ''};
  if (sap) {
    const t = Math.floor(Date.now() / 1000);
    const buf = await crypto.subtle.digest('SHA-1', new TextEncoder().encode(t + ' ' + sap + ' ' + location.origin));
    headers['authorization'] = 'SAPISIDHASH ' + t + '_' + [...new Uint8Array(buf)].map(b => b.toString(16).padStart(2, '0')).join('');
  }
  const text = r => (r && r.runs && r.runs.map(x => x.text).join('')) || '';
  const r = await fetch('/youtubei/v1/search?prettyPrint=false' + (c.INNERTUBE_API_KEY ? '&key=' + c.INNERTUBE_API_KEY : ''),
    {method: 'POST', credentials: 'include', headers, body: JSON.stringify({context: c.INNERTUBE_CONTEXT, query: __QUERY__})});
  const out = [];
  (function walk(o) {
    if (!o || typeof o !== 'object' || out.length >= 40) return;
    const row = o.musicResponsiveListItemRenderer;
    if (row) {
      const cols = row.flexColumns || [];
      const col = i => text(((cols[i] || {}).musicResponsiveListItemFlexColumnRenderer || {}).text);
      const video = row.playlistItemData && row.playlistItemData.videoId;
      const browse = ((row.navigationEndpoint || {}).browseEndpoint || {}).browseId || '';
      if (video) out.push({id: 'yt:video:' + video, name: col(0), artist: col(1)});
      else if (browse.startsWith('VL')) out.push({id: 'yt:playlist:' + browse.slice(2), name: col(0), artist: col(1)});
    }
    for (const k in o) walk(o[k]);
  })(await r.json());
  return JSON.stringify(out);
})()"#;

/// Runs in the page: asks YouTube Music's own interface for the library pages, signed in as the page is (the same
/// SAPISID hash the page itself sends), and returns plain lists. Nothing leaves the PC.
const LIBRARY_JS: &str = r#"(async () => {
  const c = (window.ytcfg && ytcfg.data_) || {};
  const sap = (document.cookie.match(/(?:^|; )SAPISID=([^;]+)/) || [])[1];
  const headers = {'content-type': 'application/json', 'x-youtube-client-name': '67', 'x-youtube-client-version': c.INNERTUBE_CLIENT_VERSION || ''};
  if (sap) {
    const t = Math.floor(Date.now() / 1000);
    const buf = await crypto.subtle.digest('SHA-1', new TextEncoder().encode(t + ' ' + sap + ' ' + location.origin));
    headers['authorization'] = 'SAPISIDHASH ' + t + '_' + [...new Uint8Array(buf)].map(b => b.toString(16).padStart(2, '0')).join('');
  }
  const text = r => (r && r.runs && r.runs.map(x => x.text).join('')) || '';
  async function browse(id) {
    const r = await fetch('/youtubei/v1/browse?prettyPrint=false' + (c.INNERTUBE_API_KEY ? '&key=' + c.INNERTUBE_API_KEY : ''),
      {method: 'POST', credentials: 'include', headers, body: JSON.stringify({context: c.INNERTUBE_CONTEXT, browseId: id})});
    const out = [];
    (function walk(o) {
      if (!o || typeof o !== 'object' || out.length >= 200) return;
      const two = o.musicTwoRowItemRenderer;
      if (two) {
        const b = (two.navigationEndpoint || {}).browseEndpoint || {};
        if (b.browseId && b.browseId.startsWith('VL')) out.push({id: 'yt:playlist:' + b.browseId.slice(2), name: text(two.title), artist: text(two.subtitle)});
      }
      const row = o.musicResponsiveListItemRenderer;
      if (row && row.playlistItemData && row.playlistItemData.videoId) {
        const cols = row.flexColumns || [];
        const col = i => text(((cols[i] || {}).musicResponsiveListItemFlexColumnRenderer || {}).text);
        out.push({id: 'yt:video:' + row.playlistItemData.videoId, name: col(0), artist: col(1)});
      }
      for (const k in o) walk(o[k]);
    })(await r.json());
    return out;
  }
  const now = (document.querySelector('ytmusic-player-bar .title') || {}).textContent || '';
  const playlists = await browse('FEmusic_liked_playlists');
  // the songs of each playlist, so the game can open one: 8 at a time, a playlist that fails stays closed
  const opened = playlists.slice(0, 50);
  for (let i = 0; i < opened.length; i += 8) {
    await Promise.all(opened.slice(i, i + 8).map(async p => {
      try { p.tracks = (await browse('VL' + p.id.slice('yt:playlist:'.length))).filter(t => t.id.startsWith('yt:video:')).slice(0, 100); } catch (e) {}
    }));
  }
  return JSON.stringify({playlists, liked: await browse('FEmusic_liked_videos'),
    recent: await browse('FEmusic_history'), now: now.trim()});
})()"#;

pub fn library(profile: &Path) -> Result<Library> {
    ensure_window(profile)?;
    let result = call("Runtime.evaluate", json!({"expression":LIBRARY_JS,"awaitPromise":true,"returnByValue":true}))?;
    let text = result["result"]["value"].as_str().context("the YouTube Music page gave no library (signed in?)")?;
    parse_library(&serde_json::from_str(text)?)
}

fn items(list: &Value) -> Vec<Item> {
    list.as_array()
        .into_iter()
        .flatten()
        .filter_map(|v| {
            Some(Item {
                id: v["id"].as_str()?.to_owned(),
                name: v["name"].as_str().filter(|n| !n.is_empty())?.to_owned(),
                artist: v["artist"].as_str().filter(|a| !a.is_empty()).map(str::to_owned),
                count: None,
                tracks: items(&v["tracks"]),
            })
        })
        .collect()
}

pub fn parse_library(value: &Value) -> Result<Library> {
    let list = |key: &str| items(&value[key]);
    let now = value["now"].as_str().filter(|n| !n.is_empty()).map(|n| Item { name: n.to_owned(), ..Item::default() });
    Ok(Library { source: Source::Youtube, playlists: list("playlists"), liked: list("liked"), recent: list("recent"), now_playing: now, search: Vec::new(), query: None })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_page_answer_becomes_a_library() {
        let lib = parse_library(&json!({"playlists":[{"id":"yt:playlist:PLx","name":"Mix","artist":"me"},{"id":"yt:playlist:PLy","name":""}],
            "liked":[{"id":"yt:video:abc","name":"Song","artist":"Čechomor"}],"recent":[],"now":"Song"})).unwrap();
        assert_eq!(lib.playlists.len(), 1);
        assert_eq!(lib.liked[0].artist.as_deref(), Some("Čechomor"));
        assert_eq!(lib.now_playing.map(|n| n.name), Some("Song".to_owned()));
    }

    #[test]
    fn playlist_songs_come_along_and_play_inside_their_playlist() {
        let lib = parse_library(&json!({"playlists":[{"id":"yt:playlist:PLx","name":"Mix",
            "tracks":[{"id":"yt:video:v1","name":"One","artist":"A"},{"id":"yt:video:v2","name":""}]}]})).unwrap();
        assert_eq!(lib.playlists[0].tracks.iter().map(|t| t.name.as_str()).collect::<Vec<_>>(), ["One"]);
        assert_eq!(watch_url("yt:video:v1", Some("yt:playlist:PLx")).unwrap(), "https://music.youtube.com/watch?v=v1&list=PLx");
        assert_eq!(watch_url("yt:video:v1", None).unwrap(), "https://music.youtube.com/watch?v=v1");
        assert_eq!(watch_url("yt:playlist:PLx", Some("yt:playlist:other")).unwrap(), "https://music.youtube.com/watch?list=PLx");
        assert!(watch_url("spotify:track:1", None).is_err());
    }

    #[test]
    fn urls_are_encoded() {
        assert_eq!(encode("AC/DC & Čech"), "AC%2FDC%20%26%20%C4%8Cech");
    }
}

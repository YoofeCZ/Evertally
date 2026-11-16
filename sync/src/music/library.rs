//! `MusicData.lua`: the player's library (playlists, liked songs, recently played) for the in-game music browser.
//! Data only, loaded by the game at login and `/reload`; every text is escaped and bounded.
use super::command::Source;
use std::path::PathBuf;

pub const DATA_FILE: &str = "MusicData.lua";
pub const PLACEHOLDER: &str = "-- Placeholder. The Evertally desktop app writes your music library here (Spotify or YouTube Music); the game loads it at login and /reload.\nEvertallyMusicData = nil\n";
const MAX_ITEMS: usize = 200;
/// Songs kept per playlist for opening it in the game; the whole playlist still plays when it is started.
pub const MAX_TRACKS: usize = 100;
/// Playlists whose songs are read with the library (one request each).
pub const MAX_OPENED: usize = 50;

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Item {
    pub id: String,
    pub name: String,
    pub artist: Option<String>,
    pub count: Option<u32>,
    /// A playlist's songs; empty for a song, or when the service would not give them.
    pub tracks: Vec<Item>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Library {
    pub source: Source,
    pub playlists: Vec<Item>,
    pub liked: Vec<Item>,
    pub recent: Vec<Item>,
    pub now_playing: Option<Item>,
    /// The latest search from the game: what was searched and what came back.
    pub search: Vec<Item>,
    pub query: Option<String>,
}

/// Whether the game's fonts draw `c`. Latin, Greek, Cyrillic and common punctuation do; emoji, arrows, CJK and the
/// invisible joiners show as empty boxes (a playlist called "D&B 🔥🔥"), so they are left out.
fn drawable(c: char) -> bool {
    let n = u32::from(c);
    n < 0x2190 && !c.is_control() && c != '|' && !(0x200B..=0x200F).contains(&n) && !(0x2060..=0x206F).contains(&n)
}

fn clean(text: &str, max: usize) -> String {
    // the game's own escape character and control codes never reach a FontString
    let kept: String = text.chars().filter(|c| drawable(*c)).take(max).collect();
    kept.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn valid_id(id: &str) -> bool {
    !id.is_empty() && id.len() <= 100 && id.bytes().all(|b| b.is_ascii_alphanumeric() || b"-_.:".contains(&b))
}

fn items(out: &mut String, key: &str, list: &[Item]) {
    out.push_str(key);
    out.push_str("={\n");
    for item in list.iter().filter(|i| valid_id(&i.id)).take(MAX_ITEMS) {
        entry(out, item, true);
        out.push_str(",\n");
    }
    out.push_str("},\n");
}

/// One `{id=…,name=…}`. A name made only of what the game cannot draw is written empty: the game shows "untitled"
/// rather than losing the playlist.
fn entry(out: &mut String, item: &Item, with_tracks: bool) {
    out.push_str("{id=");
    crate::forum::lua_string(out, &item.id);
    out.push_str(",name=");
    crate::forum::lua_string(out, &clean(&item.name, 120));
    if let Some(artist) = item.artist.as_deref().map(|a| clean(a, 80)).filter(|a| !a.is_empty()) {
        out.push_str(",artist=");
        crate::forum::lua_string(out, &artist);
    }
    if let Some(count) = item.count {
        out.push_str(&format!(",count={count}"));
    }
    if with_tracks && !item.tracks.is_empty() {
        out.push_str(",tracks={");
        for track in item.tracks.iter().filter(|t| valid_id(&t.id)).take(MAX_TRACKS) {
            entry(out, track, false);
            out.push(',');
        }
        out.push('}');
    }
    out.push('}');
}

/// The Lua text of the library, generated at `now` (unix seconds).
#[must_use]
pub fn data_file(library: &Library, now: u64) -> String {
    let mut out = String::from("-- Written by the Evertally app: your music library. Data only.\nEvertallyMusicData = {\nschemaVersion=1,\n");
    out.push_str(match library.source {
        Source::Spotify => "source=\"spotify\",\n",
        Source::Youtube => "source=\"youtube\",\n",
    });
    out.push_str(&format!("generatedAt={now},\n"));
    if let Some(now) = &library.now_playing {
        let name = clean(&now.name, 120);
        if !name.is_empty() {
            out.push_str("nowPlaying={name=");
            crate::forum::lua_string(&mut out, &name);
            out.push_str("},\n");
        }
    }
    items(&mut out, "playlists", &library.playlists);
    items(&mut out, "liked", &library.liked);
    items(&mut out, "recent", &library.recent);
    if let Some(query) = library.query.as_deref().map(|q| clean(q, 100)).filter(|q| !q.is_empty()) {
        out.push_str("searchQuery=");
        crate::forum::lua_string(&mut out, &query);
        out.push_str(",\n");
        items(&mut out, "search", &library.search);
    }
    out.push_str("}\n");
    out
}

/// Writes the library into every Evertally folder; returns how many changed.
pub fn write(addons: &[PathBuf], library: &Library, now: u64) -> std::io::Result<usize> {
    let text = data_file(library, now);
    let mut changed = 0;
    for dir in addons {
        let folder = dir.join("Evertally");
        if folder.is_dir() && crate::forum::write_if_changed(&folder.join(DATA_FILE), &text)? {
            changed += 1;
        }
    }
    Ok(changed)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_file_is_data_only_with_escaped_and_bounded_text() {
        let library = Library {
            source: Source::Spotify,
            playlists: vec![
                Item { id: "spotify:playlist:abc".into(), name: "Leveling \"Mix\"|cffff0000".into(), count: Some(40), ..Item::default() },
                Item { id: "bad id".into(), name: "Broken".into(), ..Item::default() },
            ],
            liked: vec![Item { id: "spotify:track:1".into(), name: "Píseň".into(), artist: Some("Čechomor".into()), ..Item::default() }],
            recent: vec![],
            now_playing: Some(Item { name: "Píseň".into(), ..Item::default() }),
            search: vec![Item { id: "spotify:track:9".into(), name: "Lose Yourself".into(), artist: Some("Eminem".into()), ..Item::default() }],
            query: Some("eminem".into()),
        };
        let lua = data_file(&library, 1_794_000_000);
        assert!(lua.contains(r#"{id="spotify:playlist:abc",name="Leveling \"Mix\"cffff0000",count=40},"#), "{lua}");
        assert!(!lua.contains("Broken"));
        assert!(lua.contains(r#"artist="Čechomor""#));
        let parsed = crate::savedvars::parse_assignment(&lua, "EvertallyMusicData").expect("data only");
        assert_eq!(parsed["source"], "spotify");
        assert_eq!(parsed["nowPlaying"]["name"], "Píseň");
        assert_eq!(parsed["playlists"].as_array().map(Vec::len), Some(1));
        assert_eq!(parsed["searchQuery"], "eminem");
        assert_eq!(parsed["search"][0]["name"], "Lose Yourself");
        assert!(crate::savedvars::parse_assignment(PLACEHOLDER, "EvertallyMusicData").is_ok());
    }

    #[test]
    fn playlists_carry_their_songs_and_names_lose_what_the_game_cannot_draw() {
        let song = |id: &str, name: &str| Item { id: id.into(), name: name.into(), ..Item::default() };
        let mut many: Vec<Item> = (0..150).map(|i| song(&format!("yt:video:v{i}"), "x")).collect();
        many.insert(0, song("bad id", "Broken song"));
        let library = Library {
            source: Source::Youtube,
            playlists: vec![
                Item { id: "yt:playlist:PLa".into(), name: "D&B \u{1F525}\u{1F525}".into(), tracks: many, ..Item::default() },
                Item { id: "yt:playlist:PLb".into(), name: "\u{1F3B5}\u{1F3B6}\u{200D}\u{FE0F}".into(), ..Item::default() },
            ],
            liked: vec![song("yt:video:l", "Liked")],
            recent: vec![],
            now_playing: None,
            search: vec![],
            query: None,
        };
        let lua = data_file(&library, 1);
        assert!(!lua.contains("Broken song"));
        let parsed = crate::savedvars::parse_assignment(&lua, "EvertallyMusicData").expect("data only");
        assert_eq!(parsed["playlists"][0]["name"], "D&B");
        assert_eq!(parsed["playlists"][0]["tracks"].as_array().map(Vec::len), Some(MAX_TRACKS));
        assert_eq!(parsed["playlists"][1]["name"], "", "kept, the game names it");
        assert!(parsed["playlists"][1].get("tracks").is_none());
        assert!(parsed["liked"][0].get("tracks").is_none());
        assert_eq!(clean("Hudba  \u{2022} Mardyx", 120), "Hudba \u{2022} Mardyx");
    }
}

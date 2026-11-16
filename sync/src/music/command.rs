//! The commands the in-game player (`Music.lua`) draws into the pixel strip.

/// The music service the player picked in the game.
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Source {
    Spotify,
    Youtube,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Command {
    Toggle,
    Play,
    Pause,
    Next,
    Previous,
    VolumeUp,
    VolumeDown,
    /// An NPC talks: lower the music; [`Command::Unduck`] restores it.
    Duck,
    Unduck,
    Source(Source),
    /// The player's own Spotify developer Client ID (a public value, see `spotify.rs`).
    SpotifyClient(String),
    /// Read the library again and write `MusicData.lua`.
    Library,
    /// Play a playlist or song of the library: `spotify:playlist:…`, `spotify:track:…`, `yt:playlist:…`, `yt:video:…`.
    PlayItem(String),
    /// Play a song inside the playlist it was opened from (`m:pt:<song>@<playlist>`), so the playlist goes on after it.
    PlayInPlaylist { song: String, playlist: String },
    Search(String),
    /// Bring the music app or window up.
    Open,
    /// Open Spotify's developer dashboard in the browser, where the player creates their own Client ID.
    SpotifyDashboard,
}

fn item_id(id: &str) -> bool {
    !id.is_empty()
        && id.len() <= 100
        && id.bytes().all(|b| b.is_ascii_alphanumeric() || b"-_.:".contains(&b))
        && (id.starts_with("spotify:") || id.starts_with("yt:"))
}

/// Parses `m:…` texts; anything else (other addons' strips, damaged text) is `None`.
#[must_use]
pub fn parse(text: &str) -> Option<Command> {
    let rest = text.strip_prefix("m:")?;
    Some(match rest {
        "toggle" => Command::Toggle,
        "play" => Command::Play,
        "pause" => Command::Pause,
        "next" => Command::Next,
        "prev" => Command::Previous,
        "vol+" => Command::VolumeUp,
        "vol-" => Command::VolumeDown,
        "duck" => Command::Duck,
        "unduck" => Command::Unduck,
        "lib" => Command::Library,
        "open" => Command::Open,
        "spdev" => Command::SpotifyDashboard,
        "src:spotify" => Command::Source(Source::Spotify),
        "src:youtube" => Command::Source(Source::Youtube),
        _ => {
            if let Some(id) = rest.strip_prefix("pl:") {
                return item_id(id).then(|| Command::PlayItem(id.to_owned()));
            }
            if let Some((song, playlist)) = rest.strip_prefix("pt:").and_then(|r| r.split_once('@')) {
                let same_service = song.split(':').next() == playlist.split(':').next();
                return (item_id(song) && item_id(playlist) && same_service)
                    .then(|| Command::PlayInPlaylist { song: song.to_owned(), playlist: playlist.to_owned() });
            }
            if let Some(text) = rest.strip_prefix("find:") {
                let text = text.trim();
                return (!text.is_empty() && text.len() <= 100).then(|| Command::Search(text.to_owned()));
            }
            if let Some(id) = rest.strip_prefix("spid:") {
                return (id.len() == 32 && id.bytes().all(|b| b.is_ascii_hexdigit())).then(|| Command::SpotifyClient(id.to_ascii_lowercase()));
            }
            return None;
        }
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn known_commands_parse_and_everything_else_is_ignored() {
        assert_eq!(parse("m:next"), Some(Command::Next));
        assert_eq!(parse("m:spdev"), Some(Command::SpotifyDashboard));
        assert_eq!(parse("m:src:youtube"), Some(Command::Source(Source::Youtube)));
        assert_eq!(parse("m:pl:spotify:playlist:37i9dQZF1DXcBWIGoYBM5M"), Some(Command::PlayItem("spotify:playlist:37i9dQZF1DXcBWIGoYBM5M".into())));
        assert_eq!(parse("m:pl:yt:playlist:PLabc-_1"), Some(Command::PlayItem("yt:playlist:PLabc-_1".into())));
        assert_eq!(parse("m:find:  Cechomor "), Some(Command::Search("Cechomor".into())));
        assert_eq!(
            parse("m:pt:spotify:track:1@spotify:playlist:p"),
            Some(Command::PlayInPlaylist { song: "spotify:track:1".into(), playlist: "spotify:playlist:p".into() })
        );
        assert_eq!(parse("m:pt:yt:video:v@spotify:playlist:p"), None);
        assert_eq!(parse("m:pt:spotify:track:1"), None);
        assert_eq!(parse("m:spid:0123456789ABCDEF0123456789abcdef"), Some(Command::SpotifyClient("0123456789abcdef0123456789abcdef".into())));
        for bad in ["next", "m:pl:http://evil", "m:pl:spotify:a b", "m:find:", "m:spid:123", "m:rm -rf", "m:src:winamp"] {
            assert_eq!(parse(bad), None, "{bad}");
        }
    }
}

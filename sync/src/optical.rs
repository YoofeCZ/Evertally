//! Reads the addon's live-position marker in a bounded 128 x 6 pixel strip in the Forever window's top-left corner,
//! while that corner is visible on screen. Pixels stay in RAM. No screenshots, process memory, input automation or image uploads.
//!
//! The marker is four reference shades (a ramp from black to 19 % grey) followed by data pixels, 6 bits each (2 bits per
//! colour channel). Reading the ramp first makes the decoding independent of what the game does to dark colours.
//! The payload names the character and connection snapshot by short keys; the rest (producer, name, class, ...)
//! comes from the exported file the bridge already reads, see [`Identity`].
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use std::collections::{HashMap, HashSet};
use std::path::Path;
use std::time::{Duration, Instant};

/// Pixels read from the window: the ramp and the data.
pub const WIDTH: usize = 128;
pub const HEIGHT: usize = 6;
const REFS: usize = 4;
const V2_WIDTH: usize = 39;
const BYTES: usize = 531;

/// What the server's live endpoint takes (`platform/lib/live.ts`).
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct LivePacket {
    pub v: u8,
    pub p: String,
    pub e: u64,
    pub s: u64,
    pub b: u8,
    pub t: u64,
    pub c: Value,
    pub g: Value,
    pub m: u32,
    pub x: u32,
    pub y: u32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub r: Option<Connections>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum ConnectionKind {
    Friend,
    Group,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Connection {
    pub name: String,
    pub realm: String,
    pub kind: ConnectionKind,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Connections {
    pub key: u32,
    #[serde(default)]
    pub entries: Vec<Connection>,
    #[serde(default)]
    pub tokens: Option<Vec<ConnectionToken>>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct ConnectionToken {
    pub key: u32,
    pub kind: ConnectionKind,
}

impl Serialize for Connections {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        use serde::ser::SerializeStruct;
        let mut object = serializer.serialize_struct("Connections", 2)?;
        object.serialize_field("key", &self.key)?;
        if let Some(tokens) = &self.tokens {
            object.serialize_field("tokens", tokens)?;
        } else {
            object.serialize_field("entries", &self.entries)?;
        }
        object.end()
    }
}

impl Connections {
    /// Validates the bounded list and its Adler-32 key using the same UTF-8 bytes as the addon.
    fn valid(&self) -> bool {
        if self.tokens.is_some() || self.entries.len() > 100 {
            return false;
        }
        let mut rows = Vec::with_capacity(self.entries.len());
        for entry in &self.entries {
            if entry.name.is_empty()
                || entry.realm.is_empty()
                || entry.name.len() > 120
                || entry.realm.len() > 120
                || entry.name.chars().any(char::is_control)
                || entry
                    .realm
                    .chars()
                    .any(|c| c.is_control() && !ascii_whitespace(c))
            {
                return false;
            }
            let kind = match entry.kind {
                ConnectionKind::Friend => "friend",
                ConnectionKind::Group => "group",
            };
            let realm: String = entry
                .realm
                .chars()
                .filter(|c| !ascii_whitespace(*c))
                .collect();
            if realm.is_empty() {
                return false;
            }
            rows.push(format!(
                "{kind}\0{}\0{}\n",
                entry.name.to_ascii_lowercase(),
                realm.to_ascii_lowercase()
            ));
        }
        rows.sort_unstable();
        if rows.windows(2).any(|pair| pair[0] == pair[1]) {
            return false;
        }
        adler32(rows.concat().as_bytes()) == self.key
    }
}

fn ascii_whitespace(c: char) -> bool {
    matches!(c, ' ' | '\t' | '\n' | '\r' | '\u{b}' | '\u{c}')
}

/// What the marker itself carries.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Marker {
    pub b: u8,
    pub e: u16,
    pub s: u32,
    pub t: u32,
    pub m: u16,
    pub x: u32,
    pub y: u32,
    pub key: u32,
    pub r: Option<u32>,
    pub tokens: Option<Vec<ConnectionToken>>,
}

#[must_use]
pub fn adler32(bytes: &[u8]) -> u32 {
    let (mut a, mut b) = (1u32, 0u32);
    for byte in bytes {
        a = (a + u32::from(*byte)) % 65521;
        b = (b + a) % 65521;
    }
    (b << 16) | a
}

fn fletcher16(bytes: &[u8]) -> u16 {
    let (mut c0, mut c1) = (0u16, 0u16);
    for byte in bytes {
        c0 = (c0 + u16::from(*byte)) % 255;
        c1 = (c1 + c0) % 255;
    }
    (c1 << 8) | c0
}

/// Decodes the pixels (BGRA, `WIDTH` x `HEIGHT`).
#[must_use]
pub fn decode(pixels: &[u8]) -> Option<Marker> {
    if pixels.len() < V2_WIDTH * 4
        || pixels.len() > WIDTH * HEIGHT * 4
        || !pixels.len().is_multiple_of(4)
    {
        return None;
    }
    // Reference ramp per colour channel: pixel k carries shade k on every channel (BGRA order: B=0, G=1, R=2).
    let mut refs = [[0f32; REFS]; 3];
    let mut tolerance = f32::MAX;
    for (channel, row) in refs.iter_mut().enumerate() {
        let offset = 2 - channel; // R, G, B
        for (k, slot) in row.iter_mut().enumerate() {
            *slot = f32::from(pixels[k * 4 + offset]);
        }
        for k in 1..REFS {
            let gap = row[k] - row[k - 1];
            // Strictly rising with room to tell the shades apart; a flat or reversed ramp is not our marker.
            if gap < 3.0 {
                return None;
            }
            tolerance = tolerance.min(gap * 0.45);
        }
    }
    let index = |channel: usize, value: u8| -> Option<u32> {
        let v = f32::from(value);
        let (best, distance) = refs[channel]
            .iter()
            .enumerate()
            .map(|(k, r)| (k, (v - r).abs()))
            .min_by(|a, b| a.1.total_cmp(&b.1))?;
        (distance <= tolerance).then_some(best as u32)
    };
    let (mut bytes, mut acc, mut bits) = (Vec::with_capacity(BYTES + 1), 0u32, 0u32);
    let mut needed = BYTES;
    for i in 0..pixels.len() / 4 - REFS {
        let p = (REFS + i) * 4;
        let symbol = (index(0, pixels[p + 2])? << 4)
            | (index(1, pixels[p + 1])? << 2)
            | index(2, pixels[p])?;
        acc = (acc << 6) | symbol;
        bits += 6;
        while bits >= 8 {
            bits -= 8;
            bytes.push(((acc >> bits) & 255) as u8);
            if bytes.len() == 1 {
                needed = match bytes[0] {
                    2 => 26,
                    3 => 30,
                    4 => 31,
                    _ => return None,
                };
            }
            if bytes[0] == 4 && bytes.len() == 29 {
                if bytes[28] > 100 {
                    return None;
                }
                needed = 31 + usize::from(bytes[28]) * 5;
            }
        }
        acc &= (1 << bits) - 1;
        if bytes.len() >= needed {
            break;
        }
    }
    if bytes.len() < needed {
        return None;
    }
    let checksum = needed - 2;
    if fletcher16(&bytes[..checksum]) != u16::from_be_bytes([bytes[checksum], bytes[checksum + 1]])
    {
        return None;
    }
    let u24 = |at: usize| {
        u32::from(bytes[at]) << 16 | u32::from(bytes[at + 1]) << 8 | u32::from(bytes[at + 2])
    };
    let roster_key =
        (bytes[0] >= 3).then(|| u32::from_be_bytes([bytes[24], bytes[25], bytes[26], bytes[27]]));
    let tokens = if bytes[0] == 4 {
        let mut tokens = Vec::with_capacity(usize::from(bytes[28]));
        for entry in bytes[29..checksum].chunks_exact(5) {
            let kind = match entry[0] {
                0 => ConnectionKind::Friend,
                1 => ConnectionKind::Group,
                _ => return None,
            };
            tokens.push(ConnectionToken {
                kind,
                key: u32::from_be_bytes([entry[1], entry[2], entry[3], entry[4]]),
            });
        }
        if token_hash(&tokens)? != roster_key? {
            return None;
        }
        Some(tokens)
    } else {
        None
    };
    let marker = Marker {
        b: bytes[1],
        e: u16::from_be_bytes([bytes[2], bytes[3]]),
        s: u32::from_be_bytes([bytes[4], bytes[5], bytes[6], bytes[7]]),
        t: u32::from_be_bytes([bytes[8], bytes[9], bytes[10], bytes[11]]),
        m: u16::from_be_bytes([bytes[12], bytes[13]]),
        x: u24(14),
        y: u24(17),
        key: u32::from_be_bytes([bytes[20], bytes[21], bytes[22], bytes[23]]),
        r: roster_key,
        tokens,
    };
    // The same sanity limits the server applies; own character (4) and own route (16) must be consented.
    (marker.m != 0 && marker.x <= 100_000 && marker.y <= 100_000 && marker.b & 20 == 20)
        .then_some(marker)
}

fn token_hash(tokens: &[ConnectionToken]) -> Option<u32> {
    if tokens.len() > 100 {
        return None;
    }
    let mut rows: Vec<_> = tokens
        .iter()
        .map(|token| {
            format!(
                "{}\0{}\n",
                match token.kind {
                    ConnectionKind::Friend => "friend",
                    ConnectionKind::Group => "group",
                },
                token.key
            )
        })
        .collect();
    rows.sort_unstable();
    if rows.windows(2).any(|pair| pair[0] == pair[1]) {
        return None;
    }
    Some(adler32(rows.concat().as_bytes()))
}

/// Whether the marker is still being redrawn. The marker's time is the game's server time, which is right; the PC's own clock
/// may be many seconds off (17 s behind when this was found), so the time is never compared with it. The marker only has to
/// keep changing; the server checks the time against its own clock.
#[derive(Debug, Default)]
pub struct Freshness {
    last: Option<(u32, Instant)>,
}

impl Freshness {
    /// How long the same marker may stay on screen before it counts as stuck (the addon redraws every two seconds).
    pub const STALL: Duration = Duration::from_secs(15);

    pub fn moving(&mut self, t: u32, now: Instant) -> bool {
        match self.last {
            Some((seen, since)) if seen == t => now.saturating_duration_since(since) < Self::STALL,
            _ => {
                self.last = Some((t, now));
                true
            }
        }
    }
}

/// Why a marker could not become a live packet.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Unresolved {
    /// The exported file has no producer yet (nothing exported so far).
    NoProducer,
    /// This character is not in the exported file yet; one `/reload` or logout writes it.
    UnknownCharacter,
    /// The short key names more than one character/producer; guessing could upload another identity.
    AmbiguousCharacter,
}

#[derive(Debug)]
struct CharacterIdentity {
    producer: String,
    observed_at: u64,
    character: Value,
    game: Value,
}

/// What the bridge learned from exported files. A producer belongs to its character, never the last file read.
#[derive(Debug, Default)]
pub struct Identity {
    has_producer: bool,
    characters: HashMap<u32, CharacterIdentity>,
    ambiguous: HashSet<u32>,
    connections: HashMap<String, Connections>,
}

const CHARACTER_FIELDS: [&str; 6] = ["id", "name", "realm", "classId", "raceId", "level"];
const GAME_FIELDS: [&str; 5] = ["product", "build", "interface", "region", "realm"];

fn pick(source: &Value, fields: &[&str]) -> Option<Value> {
    let object = source.as_object()?;
    let mut out = Map::new();
    for field in fields {
        if let Some(value) = object.get(*field) {
            out.insert((*field).to_owned(), value.clone());
        }
    }
    Some(Value::Object(out))
}

impl Identity {
    /// Takes in one parsed `EvertallyExportDB`.
    pub fn absorb(&mut self, envelope: &Value) {
        let envelope_producer = envelope["producerId"]
            .as_str()
            .filter(|p| !p.is_empty() && p.len() <= 180);
        self.has_producer |= envelope_producer.is_some();
        if let Some(producer) = envelope_producer {
            // Missing/invalid metadata replaces the old list with no usable snapshot for this producer.
            self.connections.remove(producer);
            if let Ok(snapshot) =
                serde_json::from_value::<Connections>(envelope["connections"].clone())
                && snapshot.valid()
            {
                self.connections.insert(producer.to_owned(), snapshot);
            }
        }
        let Some(events) = envelope["events"].as_array() else {
            return;
        };
        for event in events {
            let event_producer = event["producerId"]
                .as_str()
                .filter(|p| !p.is_empty() && p.len() <= 180);
            if envelope_producer
                .zip(event_producer)
                .is_some_and(|(a, b)| a != b)
            {
                // A foreign event cannot change the identity supplied by this export.
                continue;
            }
            let Some(producer) = envelope_producer.or(event_producer) else {
                continue;
            };
            self.has_producer = true;
            let (Some(character), Some(game)) = (
                pick(&event["character"], &CHARACTER_FIELDS),
                pick(&event["game"], &GAME_FIELDS),
            ) else {
                continue;
            };
            let Some(id) = character["id"].as_str().filter(|id| !id.is_empty()) else {
                continue;
            };
            if GAME_FIELDS.iter().any(|f| game.get(*f).is_none()) {
                continue;
            }
            let at = event["observedAt"].as_u64().unwrap_or(0);
            let key = adler32(id.as_bytes());
            if self.ambiguous.contains(&key) {
                continue;
            }
            if self.characters.get(&key).is_some_and(|known| {
                known.producer != producer || known.character["id"] != character["id"]
            }) {
                self.characters.remove(&key);
                self.ambiguous.insert(key);
            } else if self
                .characters
                .get(&key)
                .is_none_or(|known| known.observed_at <= at)
            {
                self.characters.insert(
                    key,
                    CharacterIdentity {
                        producer: producer.to_owned(),
                        observed_at: at,
                        character,
                        game,
                    },
                );
            }
        }
    }

    /// The packet the server takes for this marker.
    pub fn resolve(&self, marker: &Marker) -> Result<LivePacket, Unresolved> {
        if !self.has_producer {
            return Err(Unresolved::NoProducer);
        }
        if self.ambiguous.contains(&marker.key) {
            return Err(Unresolved::AmbiguousCharacter);
        }
        let known = self
            .characters
            .get(&marker.key)
            .ok_or(Unresolved::UnknownCharacter)?;
        Ok(LivePacket {
            v: 1,
            p: known.producer.clone(),
            e: u64::from(marker.e),
            s: u64::from(marker.s),
            b: marker.b,
            t: u64::from(marker.t),
            c: known.character.clone(),
            g: known.game.clone(),
            m: u32::from(marker.m),
            x: marker.x,
            y: marker.y,
            r: marker.r.map(|key| {
                if let Some(tokens) = &marker.tokens {
                    return Connections {
                        key,
                        entries: vec![],
                        tokens: Some(tokens.clone()),
                    };
                }
                self.connections
                    .get(&known.producer)
                    .filter(|snapshot| snapshot.key == key)
                    .cloned()
                    .unwrap_or(Connections {
                        key,
                        entries: vec![],
                        tokens: None,
                    })
            }),
        })
    }
}

#[cfg(not(windows))]
pub fn capture(_configured: Option<&Path>) -> Option<Marker> {
    None
}

/// True for the Forever client: `Wow.exe` inside a `_forever_` folder, or inside the configured WoW folder.
#[cfg(windows)]
fn is_forever(exe: &Path, configured: Option<&Path>) -> bool {
    exe.file_name()
        .is_some_and(|n| n.eq_ignore_ascii_case("Wow.exe"))
        && (exe
            .parent()
            .and_then(Path::file_name)
            .is_some_and(|n| n.eq_ignore_ascii_case("_forever_"))
            || configured.is_some_and(|root| {
                [root.join("Wow.exe"), root.join("_forever_/Wow.exe")]
                    .iter()
                    .any(|p| p.as_os_str().eq_ignore_ascii_case(exe.as_os_str()))
            }))
}

/// Reads the marker from the Forever window while its top-left corner is what the user sees there. The window does not have to
/// be the one in front (a second monitor, two windows side by side); it has to be shown, not minimised, and not covered at
/// corners of the strip. Only this bounded rectangle is read, and decoding stops at the versioned frame length.
#[cfg(windows)]
pub fn capture(configured: Option<&Path>) -> Option<Marker> {
    use std::{
        mem::{size_of, zeroed},
        ptr,
    };
    use windows_sys::Win32::{
        Foundation::{CloseHandle, HWND, LPARAM, POINT, RECT},
        Graphics::Gdi::*,
        System::Threading::{
            OpenProcess, PROCESS_QUERY_LIMITED_INFORMATION, QueryFullProcessImageNameW,
        },
        UI::{
            HiDpi::{DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2, SetThreadDpiAwarenessContext},
            WindowsAndMessaging::{
                EnumWindows, GA_ROOT, GetAncestor, GetClientRect, GetForegroundWindow,
                GetWindowThreadProcessId, IsIconic, IsWindowVisible, WindowFromPoint,
            },
        },
    };

    struct Search<'a> {
        configured: Option<&'a Path>,
        found: Vec<HWND>,
    }
    // SAFETY: the caller passes a pointer to a live `Search`; handles are checked and closed here.
    unsafe extern "system" fn visit(hwnd: HWND, lparam: LPARAM) -> i32 {
        unsafe {
            let search = &mut *(lparam as *mut Search);
            if IsWindowVisible(hwnd) == 0 || IsIconic(hwnd) != 0 {
                return 1;
            }
            let mut pid = 0;
            GetWindowThreadProcessId(hwnd, &mut pid);
            if pid == 0 {
                return 1;
            }
            let process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, pid);
            if process.is_null() {
                return 1;
            }
            let mut name = vec![0u16; 32768];
            let mut len = name.len() as u32;
            let ok = QueryFullProcessImageNameW(process, 0, name.as_mut_ptr(), &mut len);
            CloseHandle(process);
            if ok != 0 {
                let exe = std::path::PathBuf::from(String::from_utf16_lossy(&name[..len as usize]));
                if is_forever(&exe, search.configured) {
                    search.found.push(hwnd);
                }
            }
            1
        }
    }

    // SAFETY: all handles are checked; buffers are sized for the requested bounded rectangle.
    // Every acquired GDI handle and the thread's DPI context are restored before return.
    unsafe {
        let mut search = Search {
            configured,
            found: Vec::new(),
        };
        EnumWindows(Some(visit), ptr::addr_of_mut!(search) as LPARAM);
        let foreground = GetForegroundWindow();
        if let Some(at) = search.found.iter().position(|hwnd| *hwnd == foreground) {
            search.found.swap(0, at);
        }
        let previous = SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
        // A covered or uninitialised WoW window must not hide another visible client's marker.
        let result = search.found.into_iter().find_map(|hwnd| {
            let mut rect: RECT = zeroed();
            if GetClientRect(hwnd, &mut rect) == 0
                || rect.right < WIDTH as i32
                || rect.bottom < HEIGHT as i32
            {
                return None;
            }
            let mut origin = POINT { x: 0, y: 0 };
            if ClientToScreen(hwnd, &mut origin) == 0 {
                return None;
            }
            // Both ends of the marker must belong to the Forever window on screen (nothing lies over it).
            let shown = |x: i32, y: i32| {
                let at = WindowFromPoint(POINT { x, y });
                !at.is_null() && GetAncestor(at, GA_ROOT) == hwnd
            };
            let visible = || {
                [origin.x, origin.x + WIDTH as i32 - 1]
                    .into_iter()
                    .all(|x| {
                        [origin.y, origin.y + HEIGHT as i32 - 1]
                            .into_iter()
                            .all(|y| shown(x, y))
                    })
            };
            if !visible() {
                return None;
            }
            let screen = GetDC(ptr::null_mut());
            if screen.is_null() {
                return None;
            }
            let dc = CreateCompatibleDC(screen);
            if dc.is_null() {
                ReleaseDC(ptr::null_mut(), screen);
                return None;
            }
            let bitmap = CreateCompatibleBitmap(screen, WIDTH as i32, HEIGHT as i32);
            if bitmap.is_null() {
                DeleteDC(dc);
                ReleaseDC(ptr::null_mut(), screen);
                return None;
            }
            let old = SelectObject(dc, bitmap);
            // Recheck right before capturing, so a window that just moved over the corner is not read.
            let copied = visible()
                && BitBlt(
                    dc,
                    0,
                    0,
                    WIDTH as i32,
                    HEIGHT as i32,
                    screen,
                    origin.x,
                    origin.y,
                    SRCCOPY,
                ) != 0;
            SelectObject(dc, old);
            let mut info: BITMAPINFO = zeroed();
            info.bmiHeader.biSize = size_of::<BITMAPINFOHEADER>() as u32;
            info.bmiHeader.biWidth = WIDTH as i32;
            info.bmiHeader.biHeight = -(HEIGHT as i32);
            info.bmiHeader.biPlanes = 1;
            info.bmiHeader.biBitCount = 32;
            info.bmiHeader.biCompression = BI_RGB;
            let mut pixels = vec![0u8; WIDTH * HEIGHT * 4];
            let read = copied
                && GetDIBits(
                    dc,
                    bitmap,
                    0,
                    HEIGHT as u32,
                    pixels.as_mut_ptr().cast(),
                    &mut info,
                    DIB_RGB_COLORS,
                ) == HEIGHT as i32;
            DeleteObject(bitmap);
            DeleteDC(dc);
            ReleaseDC(ptr::null_mut(), screen);
            if read && visible() {
                decode(&pixels)
            } else {
                None
            }
        });
        if !previous.is_null() {
            SetThreadDpiAwarenessContext(previous);
        }
        result
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    const FIXTURE: &str = include_str!("../../tests/lua/fixtures/optical.json");

    /// The pixels the Lua addon draws, as BGRA bytes, run through `shade` the way a game could alter dark colours.
    fn pixels_of(fixture: &Value, shade: impl Fn(u64) -> u8) -> Vec<u8> {
        let mut out = Vec::new();
        for px in fixture["pixels"].as_array().unwrap() {
            let c: Vec<u64> = px
                .as_array()
                .unwrap()
                .iter()
                .map(|v| v.as_u64().unwrap())
                .collect();
            out.extend_from_slice(&[shade(c[2]), shade(c[1]), shade(c[0]), 255]);
        }
        out
    }

    fn fixture() -> Value {
        serde_json::from_str(FIXTURE).unwrap()
    }

    #[test]
    fn decodes_the_actual_lua_addon_pixels() {
        let f = fixture();
        let marker = decode(&pixels_of(&f, |v| v as u8)).expect("Lua-to-Rust pixel decode");
        let p = &f["packet"];
        assert_eq!(
            (
                marker.b,
                u64::from(marker.e),
                u64::from(marker.s),
                u64::from(marker.t)
            ),
            (
                p["b"].as_u64().unwrap() as u8,
                p["e"].as_u64().unwrap(),
                p["s"].as_u64().unwrap(),
                p["t"].as_u64().unwrap()
            )
        );
        assert_eq!(
            (
                u64::from(marker.m),
                u64::from(marker.x),
                u64::from(marker.y)
            ),
            (
                p["m"].as_u64().unwrap(),
                p["x"].as_u64().unwrap(),
                p["y"].as_u64().unwrap()
            )
        );
        assert_eq!(u64::from(marker.key), p["key"].as_u64().unwrap());
        assert_eq!(marker.r.map(u64::from), p.get("r").and_then(Value::as_u64));
        assert_eq!(
            marker.key,
            adler32(f["guid"].as_str().unwrap().as_bytes()),
            "the Lua and Rust Adler-32 agree"
        );
    }

    #[test]
    fn survives_what_the_game_did_to_dark_colours_on_screen() {
        // Measured on screen: 85 -> 78, 170 -> 164, 255 -> 251, i.e. roughly 1.012 * v - 8, clamped at 0.
        let f = fixture();
        let measured = |v: u64| (1.0118 * v as f64 - 8.0).round().clamp(0.0, 255.0) as u8;
        assert!(decode(&pixels_of(&f, measured)).is_some(), "linear offset");
        // a gamma-like curve, and a brightness lift
        assert!(
            decode(&pixels_of(
                &f,
                |v| (255.0 * (v as f64 / 255.0).powf(0.8)).round() as u8
            ))
            .is_some(),
            "gamma"
        );
        assert!(
            decode(&pixels_of(&f, |v| (v + 5).min(255) as u8)).is_some(),
            "brightness"
        );
    }

    #[test]
    fn rejects_damage_and_things_that_are_not_the_marker() {
        let f = fixture();
        let good = pixels_of(&f, |v| v as u8);
        assert!(decode(&good).is_some());
        assert!(decode(&good[..40]).is_none(), "short read");
        assert!(decode(&[0; WIDTH * HEIGHT * 4]).is_none(), "black");
        assert!(
            decode(&[90; WIDTH * HEIGHT * 4]).is_none(),
            "flat grey has no ramp"
        );
        let mut damaged = good.clone();
        damaged[(REFS + 7) * 4 + 1] = 200; // a data pixel far from every shade
        assert!(decode(&damaged).is_none(), "colour that is no shade");
        let mut flipped = good.clone();
        let i = (REFS + 9) * 4 + 2;
        flipped[i] = if flipped[i] == 0 { 16 } else { 0 }; // another valid shade: the checksum must catch it
        assert!(decode(&flipped).is_none(), "a wrong but valid shade");
        let mut reversed = good;
        for k in 0..REFS {
            let value = [48u8, 32, 16, 0][k];
            reversed[k * 4..k * 4 + 3].copy_from_slice(&[value, value, value]);
        }
        assert!(
            decode(&reversed).is_none(),
            "a ramp that falls instead of rises"
        );
    }

    fn export() -> Value {
        json!({
            "enabled": true, "consentEpoch": 1, "producerId": "6af21659-7cf6a641-33466dad",
            "events": [
                {"producerId": "6af21659-7cf6a641-33466dad", "observedAt": 100, "kind": "character.snapshot",
                 "character": {"id": "Player-TEST-own", "name": "Old", "realm": "R", "classId": 1, "raceId": 1, "level": 5, "extra": true},
                 "game": {"product": "forever", "build": "70862", "interface": 16001, "region": "3", "realm": "R", "extra": 1}},
                {"producerId": "6af21659-7cf6a641-33466dad", "observedAt": 200, "kind": "character.snapshot",
                 "character": {"id": "Player-TEST-own", "name": "Mardyx", "realm": "R", "classId": 1, "raceId": 1, "level": 6},
                 "game": {"product": "forever", "build": "70862", "interface": 16001, "region": "3", "realm": "R"}},
                {"observedAt": 300, "kind": "x", "character": {"id": "Player-NO-GAME", "name": "N"}},
            ]
        })
    }

    #[test]
    fn a_marker_is_fresh_while_it_changes_whatever_the_pc_clock_says() {
        let base = Instant::now();
        let mut fresh = Freshness::default();
        assert!(fresh.moving(1_794_415_004, base), "first sight");
        assert!(
            fresh.moving(1_794_415_004, base + Duration::from_secs(14)),
            "the same marker for less than 15 s"
        );
        assert!(
            !fresh.moving(1_794_415_004, base + Duration::from_secs(16)),
            "stuck marker"
        );
        assert!(
            fresh.moving(1_794_415_006, base + Duration::from_secs(17)),
            "it moved again"
        );
        assert!(!fresh.moving(1_794_415_006, base + Duration::from_secs(40)));
    }

    #[test]
    fn a_marker_becomes_the_packet_the_server_takes_from_the_exported_file() {
        let f = fixture();
        let marker = decode(&pixels_of(&f, |v| v as u8)).unwrap();
        let mut identity = Identity::default();
        assert_eq!(
            identity.resolve(&marker).unwrap_err(),
            Unresolved::NoProducer
        );
        identity.absorb(&export());
        let packet = identity.resolve(&marker).expect("known character");
        assert_eq!(packet.v, 1);
        assert_eq!(packet.p, "6af21659-7cf6a641-33466dad");
        assert_eq!(
            packet.c["name"], "Mardyx",
            "the newest snapshot of the character wins"
        );
        assert_eq!(
            packet.c.as_object().unwrap().len(),
            6,
            "only the fields the server's strict schema allows"
        );
        assert_eq!(packet.g.as_object().unwrap().len(), 5);
        assert_eq!((packet.m, packet.x, packet.y), (1429, 42345, 65123));
        // the server's strict schema: serialises with exactly its field names
        let wire = serde_json::to_value(&packet).unwrap();
        for field in ["v", "p", "e", "s", "b", "t", "c", "g", "m", "x", "y"] {
            assert!(wire.get(field).is_some(), "{field}");
        }
        let stranger = Marker {
            key: marker.key ^ 1,
            ..marker
        };
        assert_eq!(
            identity.resolve(&stranger).unwrap_err(),
            Unresolved::UnknownCharacter
        );
        let mut game_less = Identity::default();
        game_less.absorb(&export());
        assert_eq!(
            game_less.characters.len(),
            1,
            "a character seen without a game object is not usable"
        );
    }

    fn identity_export(producer: &str, guid: &str, seen: u64) -> Value {
        json!({"producerId":producer,"events":[{"producerId":producer,"observedAt":seen,
            "character":{"id":guid,"name":"Fixture","realm":"R","classId":1,"raceId":1,"level":5},
            "game":{"product":"forever","build":"70862","interface":16001,"region":"3","realm":"R"}}]})
    }

    fn marker_for(guid: &str) -> Marker {
        Marker {
            b: 20,
            e: 1,
            s: 100,
            t: 200,
            m: 1429,
            x: 50000,
            y: 50000,
            key: adler32(guid.as_bytes()),
            r: None,
            tokens: None,
        }
    }

    #[test]
    fn multiple_export_files_keep_each_characters_own_producer() {
        let mut identity = Identity::default();
        identity.absorb(&identity_export("producer-one", "Player-TEST-111", 100));
        identity.absorb(&identity_export("producer-two", "Player-TEST-222", 200));
        assert_eq!(
            identity.resolve(&marker_for("Player-TEST-111")).unwrap().p,
            "producer-one"
        );
        assert_eq!(
            identity.resolve(&marker_for("Player-TEST-222")).unwrap().p,
            "producer-two"
        );
        identity.absorb(&json!({"producerId":"unrelated-file","events":[]}));
        assert_eq!(
            identity.resolve(&marker_for("Player-TEST-111")).unwrap().p,
            "producer-one"
        );
    }

    #[test]
    fn one_guid_from_different_producers_is_ambiguous_in_either_read_order() {
        for producers in [["one", "two"], ["two", "one"]] {
            let mut identity = Identity::default();
            for producer in producers {
                identity.absorb(&identity_export(producer, "Player-TEST-111", 100));
            }
            assert_eq!(
                identity
                    .resolve(&marker_for("Player-TEST-111"))
                    .unwrap_err(),
                Unresolved::AmbiguousCharacter
            );
            // Another newer snapshot cannot make a previously ambiguous marker safe to guess.
            identity.absorb(&identity_export(producers[0], "Player-TEST-111", 300));
            assert_eq!(
                identity
                    .resolve(&marker_for("Player-TEST-111"))
                    .unwrap_err(),
                Unresolved::AmbiguousCharacter
            );
        }
    }

    #[test]
    fn different_guids_with_the_same_short_key_are_never_mistaken_for_one_another() {
        let first = "Player-TEST-123";
        let second = "Player-TEST-204";
        assert_ne!(first, second);
        assert_eq!(adler32(first.as_bytes()), adler32(second.as_bytes()));
        let mut identity = Identity::default();
        identity.absorb(&identity_export("producer", first, 100));
        identity.absorb(&identity_export("producer", second, 200));
        assert_eq!(
            identity.resolve(&marker_for(first)).unwrap_err(),
            Unresolved::AmbiguousCharacter
        );
    }

    #[test]
    fn a_foreign_event_cannot_relabel_the_exports_character() {
        let mut envelope = identity_export("one", "Player-TEST-111", 100);
        envelope["events"][0]["producerId"] = json!("foreign");
        let mut identity = Identity::default();
        identity.absorb(&envelope);
        assert_eq!(
            identity
                .resolve(&marker_for("Player-TEST-111"))
                .unwrap_err(),
            Unresolved::UnknownCharacter
        );
    }

    #[test]
    fn v2_marker_still_decodes_from_its_original_size_or_a_padded_v3_capture() {
        let f: Value =
            serde_json::from_str(include_str!("../../tests/lua/fixtures/optical-v2.json")).unwrap();
        let pixels = pixels_of(&f, |v| v as u8);
        assert_eq!(pixels.len(), V2_WIDTH * 4);
        let old = decode(&pixels).unwrap();
        assert_eq!(old.r, None);
        let mut padded = pixels;
        padded.resize(WIDTH * HEIGHT * 4, 255);
        assert_eq!(
            decode(&padded),
            Some(old),
            "v2 stops before normal game pixels in the extra capture width"
        );
    }

    #[test]
    fn v3_marker_requires_its_complete_lua_payload() {
        let f: Value =
            serde_json::from_str(include_str!("../../tests/lua/fixtures/optical-v3.json")).unwrap();
        assert_eq!(
            f["bytes"][0], 3,
            "the main fixture is generated by the current Lua v3 addon"
        );
        let pixels = pixels_of(&f, |v| v as u8);
        assert_eq!(pixels.len(), 44 * 4);
        assert_eq!(
            decode(&pixels).unwrap().r,
            Some(f["packet"]["r"].as_u64().unwrap() as u32)
        );
        assert!(
            decode(&pixels[..V2_WIDTH * 4]).is_none(),
            "a truncated v3 sample cannot fall back to v2"
        );
    }

    fn connection_snapshot(entries: Value, canonical: &str) -> Value {
        json!({"key":adler32(canonical.as_bytes()),"entries":entries})
    }

    #[test]
    fn v3_connection_metadata_uses_its_producer_and_the_exact_current_hash() {
        let entries = json!([{"name":"Bob","realm":"Test Realm","kind":"friend"}]);
        let snapshot = connection_snapshot(entries, "friend\0bob\0testrealm\n");
        let key = snapshot["key"].as_u64().unwrap() as u32;
        let mut envelope = identity_export("one", "Player-TEST-111", 100);
        envelope["connections"] = snapshot.clone();
        let mut identity = Identity::default();
        identity.absorb(&envelope);
        let marker = Marker {
            r: Some(key),
            ..marker_for("Player-TEST-111")
        };
        let packet = identity.resolve(&marker).unwrap();
        assert_eq!(packet.r.unwrap().entries[0].name, "Bob");
        identity.absorb(&identity_export("two", "Player-TEST-222", 200));
        let other = Marker {
            r: Some(key),
            ..marker_for("Player-TEST-222")
        };
        assert!(
            identity
                .resolve(&other)
                .unwrap()
                .r
                .unwrap()
                .entries
                .is_empty(),
            "another producer does not inherit the list"
        );
        let changed = Marker {
            r: Some(key ^ 1),
            ..marker.clone()
        };
        let clear = identity.resolve(&changed).unwrap().r.unwrap();
        assert_eq!(clear.key, key ^ 1);
        assert!(
            clear.entries.is_empty(),
            "new live key clears stale permissions immediately"
        );
        envelope["connections"]["entries"][0]["name"] = json!("Mallory");
        identity.absorb(&envelope);
        assert!(
            identity
                .resolve(&marker)
                .unwrap()
                .r
                .unwrap()
                .entries
                .is_empty(),
            "a declared key cannot authenticate changed metadata"
        );
        let mut fresh = identity_export("one", "Player-TEST-111", 300);
        fresh["connections"] = snapshot;
        identity.absorb(&fresh);
        assert_eq!(
            identity.resolve(&marker).unwrap().r.unwrap().entries.len(),
            1
        );
        identity.absorb(&identity_export("one", "Player-TEST-111", 400));
        assert!(
            identity
                .resolve(&marker)
                .unwrap()
                .r
                .unwrap()
                .entries
                .is_empty(),
            "missing metadata invalidates the previous cached list"
        );
        let v2 = identity.resolve(&marker_for("Player-TEST-111")).unwrap();
        assert!(
            serde_json::to_value(v2).unwrap().get("r").is_none(),
            "v2 does not introduce a connection permission"
        );
    }

    #[test]
    fn connection_hash_sorts_utf8_rows_and_only_folds_ascii() {
        let snapshot = connection_snapshot(
            json!([
                {"name":"ÄBC","realm":"Test\t Realm\u{b}","kind":"group"},
                {"name":"Bob","realm":"Test Realm","kind":"friend"}
            ]),
            "friend\0bob\0testrealm\ngroup\0Äbc\0testrealm\n",
        );
        let parsed: Connections = serde_json::from_value(snapshot).unwrap();
        assert!(parsed.valid());
        let mut reversed = parsed;
        reversed.entries.reverse();
        assert!(reversed.valid());
    }

    #[test]
    fn connection_hash_matches_the_lua_snapshot_with_non_ascii_names() {
        // Generated by A.ConnectionsSnapshot() with these fixture friend API records.
        let snapshot: Connections = serde_json::from_value(json!({"key":1574309862u32,"entries":[
            {"kind":"friend","name":"Bob","realm":"testrealm"},
            {"kind":"friend","name":"ÄBC","realm":"Test Realm"}
        ]}))
        .unwrap();
        assert!(snapshot.valid());
    }

    #[test]
    fn an_empty_lua_entries_table_is_an_explicit_empty_connection_list() {
        let parsed = crate::savedvars::parse_assignment(
            "EvertallyExportDB = {connections={key=1,entries={}}}",
            "EvertallyExportDB",
        )
        .unwrap();
        let snapshot: Connections = serde_json::from_value(parsed["connections"].clone()).unwrap();
        assert!(snapshot.entries.is_empty());
        assert!(snapshot.valid());
    }

    #[test]
    fn invalid_or_unbounded_connection_lists_are_not_used() {
        let valid = json!({"name":"Bob","realm":"Realm","kind":"friend"});
        for entries in [
            json!([valid.clone(), valid.clone()]),
            json!([{"name":"","realm":"R","kind":"friend"}]),
            json!([{"name":"x".repeat(121),"realm":"R","kind":"friend"}]),
            json!([{"name":"é".repeat(61),"realm":"R","kind":"friend"}]),
            json!([{"name":"Bob","realm":"R\0","kind":"friend"}]),
            Value::Array(vec![valid; 101]),
        ] {
            let parsed: Connections =
                serde_json::from_value(json!({"key":1,"entries":entries})).unwrap();
            assert!(!parsed.valid());
        }
        assert!(
            serde_json::from_value::<Connections>(
                json!({"key":1,"entries":[{"name":"Bob","realm":"Realm","kind":"guild"}]})
            )
            .is_err()
        );
    }

    fn v4_bytes(tokens: &[ConnectionToken]) -> Vec<u8> {
        let f: Value =
            serde_json::from_str(include_str!("../../tests/lua/fixtures/optical-v3.json")).unwrap();
        let mut bytes: Vec<u8> = f["bytes"].as_array().unwrap()[..24]
            .iter()
            .map(|b| b.as_u64().unwrap() as u8)
            .collect();
        bytes[0] = 4;
        bytes.extend_from_slice(&token_hash(tokens).unwrap_or(0).to_be_bytes());
        bytes.push(tokens.len() as u8);
        for token in tokens {
            bytes.push(match token.kind {
                ConnectionKind::Friend => 0,
                ConnectionKind::Group => 1,
            });
            bytes.extend_from_slice(&token.key.to_be_bytes());
        }
        bytes.extend_from_slice(&fletcher16(&bytes).to_be_bytes());
        bytes
    }

    fn raster_bytes(bytes: &[u8]) -> Vec<u8> {
        let mut pixels = Vec::new();
        for level in [0u8, 16, 32, 48] {
            pixels.extend_from_slice(&[level, level, level, 255]);
        }
        let (mut acc, mut bits) = (0u32, 0u32);
        let mut pixel = |symbol: u32| {
            pixels.extend_from_slice(&[
                ((symbol % 4) * 16) as u8,
                ((symbol / 4 % 4) * 16) as u8,
                ((symbol / 16) * 16) as u8,
                255,
            ])
        };
        for byte in bytes {
            acc = acc << 8 | u32::from(*byte);
            bits += 8;
            while bits >= 6 {
                bits -= 6;
                pixel((acc >> bits) & 63);
            }
            acc &= (1 << bits) - 1;
        }
        if bits > 0 {
            pixel(acc << (6 - bits));
        }
        pixels
    }

    #[test]
    fn a_new_party_is_forwarded_directly_from_v4_without_reloading_saved_metadata() {
        let mut identity = Identity::default();
        identity.absorb(&export());
        let friend = ConnectionToken {
            key: adler32(b"bob\0testrealm"),
            kind: ConnectionKind::Friend,
        };
        let party = ConnectionToken {
            key: adler32(b"alice\0testrealm"),
            kind: ConnectionKind::Group,
        };
        let first = decode(&raster_bytes(&v4_bytes(std::slice::from_ref(&friend)))).unwrap();
        let initial = identity.resolve(&first).unwrap().r.unwrap();
        assert_eq!(initial.tokens, Some(vec![friend.clone()]));
        // No second absorb: the new group is read only from pixels of the next sample.
        let next = decode(&raster_bytes(&v4_bytes(&[friend.clone(), party.clone()]))).unwrap();
        let updated = identity.resolve(&next).unwrap().r.unwrap();
        assert_ne!(initial.key, updated.key);
        assert_eq!(updated.tokens, Some(vec![friend, party]));
        let wire = serde_json::to_value(updated).unwrap();
        assert!(wire.get("tokens").is_some());
        assert!(wire.get("entries").is_none());
        let clear = decode(&raster_bytes(&v4_bytes(&[]))).unwrap();
        let gone = identity.resolve(&clear).unwrap().r.unwrap();
        assert_eq!(gone.key, 1);
        assert_eq!(gone.tokens, Some(vec![]));
    }

    #[test]
    fn v4_token_hash_matches_the_lua_snapshot_for_non_ascii_names() {
        // A.ConnectionsTokensSnapshot() for Bob/testrealm and ÄBC/Test Realm.
        let tokens = vec![
            ConnectionToken {
                key: 566232325,
                kind: ConnectionKind::Friend,
            },
            ConnectionToken {
                key: 764675550,
                kind: ConnectionKind::Friend,
            },
        ];
        assert_eq!(token_hash(&tokens), Some(2814773428));
        assert!(
            tokens
                .iter()
                .any(|token| token.key == adler32("Äbc\0testrealm".as_bytes()))
        );
        assert!(
            tokens
                .iter()
                .any(|token| token.key == adler32(b"bob\0testrealm"))
        );
        assert_eq!(
            decode(&raster_bytes(&v4_bytes(&tokens))).unwrap().r,
            Some(2814773428)
        );
    }

    #[test]
    fn v4_bounds_checksum_and_exact_frame_length_are_enforced() {
        let tokens: Vec<_> = (0..100)
            .map(|key| ConnectionToken {
                key,
                kind: ConnectionKind::Friend,
            })
            .collect();
        let bytes = v4_bytes(&tokens);
        assert_eq!(bytes.len(), 531);
        let raster = raster_bytes(&bytes);
        assert_eq!(raster.len(), 712 * 4);
        let decoded = decode(&raster).unwrap();
        assert_eq!(decoded.tokens.unwrap().len(), 100);
        assert!(decode(&raster[..raster.len() - 4]).is_none());
        let mut padded = raster;
        padded.resize(WIDTH * HEIGHT * 4, 251);
        assert!(
            decode(&padded).is_some(),
            "normal pixels after the framed data are never decoded"
        );
        let mut corrupt = bytes.clone();
        corrupt[30] ^= 1;
        assert!(decode(&raster_bytes(&corrupt)).is_none());
        let mut unknown_kind = bytes.clone();
        unknown_kind[29] = 2;
        let checksum = fletcher16(&unknown_kind[..529]);
        unknown_kind[529..].copy_from_slice(&checksum.to_be_bytes());
        assert!(decode(&raster_bytes(&unknown_kind)).is_none());
        let mut oversized = bytes;
        oversized[28] = 101;
        assert!(decode(&raster_bytes(&oversized)).is_none());
        assert!(
            decode(&raster_bytes(&v4_bytes(&[
                tokens[0].clone(),
                tokens[0].clone()
            ])))
            .is_none(),
            "duplicate tokens are not a valid roster"
        );
    }
}

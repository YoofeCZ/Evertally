//! What the player asks this app to do from inside the game: "pair this PC" and "start with WoW".
//!
//! An addon cannot start programs or talk to them while the game runs. The addon keeps the request in
//! `EvertallyDB.bridgeRequest`; the game writes it to `Evertally.lua` at `/reload`, logout or exit, and the app,
//! which watches that folder, acts on it. Only that one small table is read, with the data-only parser.
//! What was already handled is remembered next to the app's state, so an old request never repeats.
use std::path::Path;

use serde::{Deserialize, Serialize};
use serde_json::Value;

/// A pairing request older than this is stale: the player has long moved on.
pub const PAIR_FRESH_SECS: u64 = 15 * 60;
/// WoW writes the top-level keys of `EvertallyDB` with exactly one tab of indentation.
const OPEN: &str = "\n\t[\"bridgeRequest\"] = {";
const CLOSE: &str = "\n\t}";
const MAX_SNIPPET: usize = 4096;

/// The requests found in the file.
#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct Requests {
    /// When the player pressed "Pair" in the game.
    pub pair_at: Option<u64>,
    /// The "start the app with WoW" choice and when it was made.
    pub autostart: Option<(bool, u64)>,
}

/// The newest request of each kind this app has already acted on.
#[derive(Debug, Default, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct Handled {
    #[serde(default)]
    pub pair_at: u64,
    #[serde(default)]
    pub autostart_at: u64,
}

fn stamp(value: &Value) -> Option<u64> {
    value.as_u64().or_else(|| value.as_f64().filter(|v| v.is_finite() && *v >= 0.0).map(|v| v as u64))
}

/// Reads `bridgeRequest` out of the text of `Evertally.lua`. `None` when there is none or it is malformed.
#[must_use]
pub fn extract(source: &str) -> Option<Requests> {
    let open = source.find(OPEN)?;
    let body = open + OPEN.len() - 1;
    let close = body + source.get(body..)?.find(CLOSE)? + CLOSE.len();
    let table = source.get(body..close)?;
    if table.len() > MAX_SNIPPET {
        return None;
    }
    let value = crate::savedvars::parse_assignment(&format!("R = {table}"), "R").ok()?;
    let pair_at = value.get("pairAt").and_then(stamp).filter(|at| *at > 0);
    let autostart = match (value.get("autostart").and_then(Value::as_bool), value.get("autostartAt").and_then(stamp)) {
        (Some(on), Some(at)) if at > 0 => Some((on, at)),
        _ => None,
    };
    Some(Requests { pair_at, autostart })
}

/// What to do now, given what was already handled: `(pair, autostart)`; both `None` means nothing.
#[must_use]
pub fn pending(requests: Requests, handled: Handled) -> (Option<u64>, Option<(bool, u64)>) {
    let pair = requests.pair_at.filter(|at| *at > handled.pair_at);
    let autostart = requests.autostart.filter(|(_, at)| *at > handled.autostart_at);
    (pair, autostart)
}

/// Whether a pairing request made at `at` is still worth acting on.
#[must_use]
pub fn fresh(at: u64, now: u64) -> bool {
    now.saturating_sub(at) <= PAIR_FRESH_SECS && at <= now + 300
}

#[must_use]
pub fn load(path: &Path) -> Handled {
    std::fs::read_to_string(path).ok().and_then(|text| serde_json::from_str(&text).ok()).unwrap_or_default()
}

/// # Errors
/// Fails when the file cannot be written.
pub fn save(path: &Path, handled: Handled) -> std::io::Result<()> {
    std::fs::write(path, serde_json::to_string(&handled).unwrap_or_default())
}

#[cfg(test)]
mod tests {
    use super::*;

    const FILE: &str = "\nEvertallyDB = {\n\t[\"runs\"] = {\n\t\t{\n\t\t\t[\"id\"] = 1,\n\t\t},\n\t},\n\t[\"bridgeRequest\"] = {\n\t\t[\"pairAt\"] = 1794760000,\n\t\t[\"autostart\"] = true,\n\t\t[\"autostartAt\"] = 1794760005,\n\t},\n\t[\"settings\"] = {\n\t},\n}\nEvertallyPeersDB = {\n}\n";

    #[test]
    fn reads_only_the_request_table() {
        let found = extract(FILE).expect("request");
        assert_eq!(found, Requests { pair_at: Some(1_794_760_000), autostart: Some((true, 1_794_760_005)) });
    }

    #[test]
    fn no_request_or_a_broken_one_is_nothing() {
        assert_eq!(extract("EvertallyDB = {\n\t[\"runs\"] = {\n\t},\n}\n"), None);
        assert_eq!(extract("EvertallyDB = {\n\t[\"bridgeRequest\"] = {\n\t\tos.execute(\"x\"),\n\t},\n}\n"), None);
        let partial = extract("EvertallyDB = {\n\t[\"bridgeRequest\"] = {\n\t\t[\"autostart\"] = false,\n\t},\n}\n").expect("table");
        assert_eq!(partial, Requests::default(), "a choice without its time is not acted on");
    }

    #[test]
    fn a_handled_request_never_repeats() {
        let requests = extract(FILE).expect("request");
        let (pair, autostart) = pending(requests, Handled::default());
        assert_eq!((pair, autostart), (Some(1_794_760_000), Some((true, 1_794_760_005))));
        let done = Handled { pair_at: 1_794_760_000, autostart_at: 1_794_760_005 };
        assert_eq!(pending(requests, done), (None, None));
    }

    #[test]
    fn only_a_recent_pairing_request_opens_pairing() {
        assert!(fresh(1000, 1000 + 60));
        assert!(!fresh(1000, 1000 + PAIR_FRESH_SECS + 1));
        assert!(!fresh(10_000, 1000), "a request from the future is a broken clock, not a request");
    }
}

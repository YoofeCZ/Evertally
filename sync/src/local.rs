//! Reads the addon's own history (`Evertally.lua`) for the desktop app. Read-only and local:
//! nothing here is uploaded.

use std::collections::HashMap;
use std::io::Read;
use std::path::{Path, PathBuf};

use serde::Serialize;
use serde_json::{Value, json};

use crate::savedvars;

/// The account-wide file the game writes for the main addon.
pub const DB_FILE: &str = "Evertally.lua";
const VARIABLES: [&str; 2] = ["EvertallyDB", "EvertallyPeersDB"];
const MAX_RUNS: usize = 300;
/// Bound allocations before parsing even when a damaged file contains one huge string.
const MAX_HISTORY_BYTES: u64 = 64 * 1024 * 1024;

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AccountData {
    /// `WoW` account folder, e.g. `464515418#1`.
    pub account: String,
    /// Game flavor folder, e.g. `_forever_`.
    pub flavor: String,
    pub characters: Vec<Value>,
    pub runs: Vec<Value>,
    pub events: Vec<Value>,
    pub event_count: usize,
    pub run_count: usize,
    pub web_enabled: bool,
    pub sharing_enabled: bool,
    pub peers: usize,
    /// Why the file could not be read (for example while the game is writing it).
    pub error: Option<String>,
}

/// Reads every `Evertally.lua` next to the given `SavedVariables` folders, newest data first.
#[must_use]
pub fn read_accounts(dirs: &[PathBuf], max_events: usize) -> Vec<AccountData> {
    dirs.iter()
        .filter_map(|dir| {
            let file = dir.join(DB_FILE);
            file.is_file().then(|| read_account(dir, &file, max_events))
        })
        .collect()
}

fn read_account(dir: &Path, file: &Path, max_events: usize) -> AccountData {
    let account = dir
        .parent()
        .and_then(Path::file_name)
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_default();
    let flavor = dir
        .ancestors()
        .filter_map(Path::file_name)
        .map(|n| n.to_string_lossy().into_owned())
        .find(|n| n.len() > 2 && n.starts_with('_') && n.ends_with('_'))
        .unwrap_or_default();
    let mut data = AccountData {
        account,
        flavor,
        characters: Vec::new(),
        runs: Vec::new(),
        events: Vec::new(),
        event_count: 0,
        run_count: 0,
        web_enabled: false,
        sharing_enabled: false,
        peers: 0,
        error: None,
    };
    let parsed = read_history(file).and_then(|text| {
        savedvars::parse_assignments(&text, &VARIABLES).map_err(|e| e.to_string())
    });
    let vars = match parsed {
        Ok(vars) => vars,
        Err(error) => {
            data.error = Some(error);
            return data;
        }
    };
    let Some(db) = vars.get("EvertallyDB").filter(|db| db.is_object()) else {
        data.error = Some("EvertallyDB is missing or is not a history table".to_owned());
        return data;
    };
    if db.get("schemaVersion").is_some_and(|version| version != 1) {
        data.error = Some("Unsupported Evertally history version".to_owned());
        return data;
    }
    let (Some(events), Some(runs)) = (db["events"].as_array(), db["runs"].as_array()) else {
        data.error = Some("EvertallyDB must contain events and runs arrays".to_owned());
        return data;
    };
    data.event_count = events.len();
    data.run_count = runs.len();
    data.events = newest(events, max_events, |event| timestamp(event, "observedAt"));
    data.runs = newest(runs, MAX_RUNS, |run| {
        run.get("endedAt")
            .and_then(Value::as_f64)
            .unwrap_or_else(|| timestamp(run, "startedAt"))
    });
    data.web_enabled = db["settings"]["web"] == Value::Bool(true);
    data.sharing_enabled = db["settings"]["ingame"] == Value::Bool(true);
    data.peers = vars
        .get("EvertallyPeersDB")
        .and_then(|p| p["peers"].as_object())
        .map_or(0, serde_json::Map::len);
    data.characters = characters(events, runs);
    data
}

fn read_history(path: &Path) -> Result<String, String> {
    let file = std::fs::File::open(path).map_err(|error| error.to_string())?;
    if file.metadata().map_err(|error| error.to_string())?.len() > MAX_HISTORY_BYTES {
        return Err("Evertally history exceeds the 64 MiB limit".to_owned());
    }
    // `take` also bounds reads if the game grows the file after the metadata check.
    let mut text = String::new();
    file.take(MAX_HISTORY_BYTES + 1)
        .read_to_string(&mut text)
        .map_err(|error| error.to_string())?;
    if text.len() as u64 > MAX_HISTORY_BYTES {
        return Err("Evertally history exceeds the 64 MiB limit".to_owned());
    }
    Ok(text)
}

fn timestamp(value: &Value, field: &str) -> f64 {
    value[field].as_f64().unwrap_or(0.0)
}

/// Imported files need not have been appended in timestamp order. Preserve the later
/// append first when observations have the same timestamp, as the addon does.
fn newest(items: &[Value], limit: usize, at: impl Fn(&Value) -> f64) -> Vec<Value> {
    let mut ordered: Vec<_> = items.iter().rev().collect();
    ordered.sort_by(|a, b| at(b).total_cmp(&at(a)));
    ordered.into_iter().take(limit).cloned().collect()
}

/// Own characters seen in events and runs, latest snapshot per character id.
fn characters(events: &[Value], runs: &[Value]) -> Vec<Value> {
    let mut latest: HashMap<String, (f64, Value)> = HashMap::new();
    let snapshots = events
        .iter()
        .map(|e| (&e["character"], e["observedAt"].as_f64().unwrap_or(0.0)))
        .chain(runs.iter().map(|r| {
            (
                &r["character"],
                r["endedAt"]
                    .as_f64()
                    .or_else(|| r["startedAt"].as_f64())
                    .unwrap_or(0.0),
            )
        }));
    for (character, at) in snapshots {
        let Some(id) = character["id"].as_str() else {
            continue;
        };
        if latest.get(id).is_none_or(|(seen, _)| at >= *seen) {
            let summary = json!({
                "id": id, "name": character["name"], "realm": character["realm"], "classId": character["classId"],
                "raceId": character["raceId"], "level": character["level"], "lastSeen": at,
            });
            latest.insert(id.to_owned(), (at, summary));
        }
    }
    let mut list: Vec<(f64, Value)> = latest.into_values().collect();
    list.sort_by(|a, b| b.0.total_cmp(&a.0));
    list.into_iter().map(|(_, v)| v).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_history_newest_first_with_characters() {
        let root =
            std::env::temp_dir().join(format!("evertally-local-test-{}", std::process::id()));
        let dir = root.join("_forever_/WTF/Account/ACC#1/SavedVariables");
        std::fs::create_dir_all(&dir).expect("create dirs");
        let lua = r#"
EvertallyDB = {
    ["settings"] = { ["web"] = true, ["ingame"] = false },
    ["events"] = {
        { ["kind"] = "quest.accepted", ["observedAt"] = 100, ["character"] = { ["id"] = "Player-1", ["name"] = "Mardyx", ["level"] = 9, ["classId"] = 8 }, ["payload"] = { ["questId"] = 1 } },
        { ["kind"] = "character.level", ["observedAt"] = 200, ["character"] = { ["id"] = "Player-1", ["name"] = "Mardyx", ["level"] = 10, ["classId"] = 8 }, ["payload"] = { ["level"] = 10 } },
    },
    ["runs"] = {},
}
EvertallyPeersDB = { ["peers"] = { ["Someone-Realm"] = { ["runs"] = {} } } }
"#;
        std::fs::write(dir.join(DB_FILE), lua).expect("write file");
        let accounts = read_accounts(&[dir.clone(), root.join("missing")], 10);
        let _ = std::fs::remove_dir_all(&root);
        assert_eq!(accounts.len(), 1);
        let account = &accounts[0];
        assert_eq!(
            (account.account.as_str(), account.flavor.as_str()),
            ("ACC#1", "_forever_")
        );
        assert_eq!(
            (
                account.event_count,
                account.web_enabled,
                account.sharing_enabled,
                account.peers
            ),
            (2, true, false, 1)
        );
        assert_eq!(account.events[0]["kind"], "character.level");
        assert_eq!(account.characters.len(), 1);
        assert_eq!(account.characters[0]["level"], 10);
    }

    #[test]
    fn unreadable_file_reports_an_error_instead_of_failing() {
        let root = std::env::temp_dir().join(format!("evertally-local-bad-{}", std::process::id()));
        std::fs::create_dir_all(&root).expect("create dir");
        std::fs::write(root.join(DB_FILE), "EvertallyDB = {").expect("write file");
        let accounts = read_accounts(std::slice::from_ref(&root), 10);
        let _ = std::fs::remove_dir_all(&root);
        assert!(accounts[0].error.is_some());
    }

    #[test]
    fn incomplete_or_wrong_main_history_is_not_a_successful_empty_snapshot() {
        let root =
            std::env::temp_dir().join(format!("evertally-local-schema-{}", std::process::id()));
        std::fs::create_dir_all(&root).expect("create dir");
        for source in [
            "-- empty while writing",
            "EvertallyPeersDB = {}",
            "EvertallyDB = nil",
            "EvertallyDB = {}",
            "EvertallyDB = { events = false, runs = {} }",
            "EvertallyDB = { schemaVersion = 2, events = {}, runs = {} }",
        ] {
            std::fs::write(root.join(DB_FILE), source).expect("write file");
            let accounts = read_accounts(std::slice::from_ref(&root), 10);
            assert!(accounts[0].error.is_some(), "accepted: {source}");
        }
        let _ = std::fs::remove_dir_all(root);
    }

    #[test]
    fn oversized_history_is_rejected_before_reading_it() {
        let root =
            std::env::temp_dir().join(format!("evertally-local-limit-{}", std::process::id()));
        std::fs::create_dir_all(&root).expect("create dir");
        let file = std::fs::File::create(root.join(DB_FILE)).expect("create file");
        file.set_len(MAX_HISTORY_BYTES + 1).expect("extend file");
        drop(file);
        let accounts = read_accounts(std::slice::from_ref(&root), 10);
        let _ = std::fs::remove_dir_all(root);
        assert!(
            accounts[0]
                .error
                .as_deref()
                .is_some_and(|error| error.contains("64 MiB"))
        );
    }

    #[test]
    fn newest_events_use_observation_time_and_limit_after_sorting() {
        let events = vec![
            json!({"observedAt": 300, "kind": "newest"}),
            json!({"observedAt": 200, "kind": "first-at-time"}),
            json!({"observedAt": 100, "kind": "oldest"}),
            json!({"observedAt": 200, "kind": "last-at-time"}),
        ];
        let sorted = newest(&events, 3, |event| timestamp(event, "observedAt"));
        let kinds: Vec<_> = sorted
            .iter()
            .map(|event| event["kind"].as_str().expect("kind"))
            .collect();
        assert_eq!(kinds, ["newest", "last-at-time", "first-at-time"]);
    }

    #[test]
    fn retained_run_keeps_its_own_character_and_latest_level() {
        let events = vec![json!({
            "kind": "character.snapshot", "observedAt": 100,
            "character": {"id": "Player-1", "name": "Mardyx", "realm": "Forever", "classId": 8, "raceId": 5, "level": 9}
        })];
        let runs = vec![json!({
            "runId": "producer:run", "name": "Ragefire Chasm", "instanceId": 389, "instanceType": "party",
            "startedAt": 150, "endedAt": 200, "durationMs": 50000, "status": "completed",
            "completion": "last_boss", "rankEligible": false, "bossCount": 1,
            "character": {"id": "Player-1", "name": "Mardyx", "realm": "Forever", "classId": 8, "raceId": 5, "level": 10}
        })];
        let own = characters(&events, &runs);
        assert_eq!(own.len(), 1);
        assert_eq!(own[0]["level"], 10);
        assert_eq!(own[0]["realm"], "Forever");
        assert_eq!(own[0]["lastSeen"], 200.0);
    }
}

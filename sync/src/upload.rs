//! Which events still need uploading, and how to split them into server-sized batches.

use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::Path;

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use serde_json::Value;

/// The server accepts at most 500 events and 1 MiB per request; stay below both.
pub const MAX_BATCH_EVENTS: usize = 500;
pub const MAX_BATCH_BYTES: usize = 900 * 1024;

/// Event ids already accepted by the server, per `producerId:consentEpoch`.
/// A new consent epoch (web export re-enabled in game) starts a fresh set.
#[derive(Debug, Default, Serialize, Deserialize)]
pub struct UploadState {
    uploaded: HashMap<String, HashSet<String>>,
}

impl UploadState {
    #[must_use]
    pub fn load(path: &Path) -> Self {
        fs::read_to_string(path)
            .ok()
            .and_then(|text| serde_json::from_str(&text).ok())
            .unwrap_or_default()
    }

    /// # Errors
    /// Fails when the state file cannot be written.
    pub fn save(&self, path: &Path) -> Result<()> {
        let temp = path.with_extension("json.tmp");
        fs::write(&temp, serde_json::to_vec(self)?)
            .with_context(|| format!("write {}", temp.display()))?;
        fs::rename(&temp, path).with_context(|| format!("replace {}", path.display()))
    }

    pub fn mark(&mut self, source: &str, ids: impl IntoIterator<Item = String>) {
        self.uploaded
            .entry(source.to_owned())
            .or_default()
            .extend(ids);
    }

    #[must_use]
    pub fn contains(&self, source: &str, id: &str) -> bool {
        self.uploaded
            .get(source)
            .is_some_and(|set| set.contains(id))
    }
}

/// What a parsed export file asks for.
#[derive(Debug, PartialEq)]
pub enum Plan {
    /// Web export is switched off in the addon; nothing may be sent.
    Disabled,
    /// Everything in the file is already on the server.
    UpToDate,
    /// Batches to send for `source`, each a complete export envelope.
    Send {
        source: String,
        batches: Vec<Value>,
        events: usize,
    },
}

/// Decides what to upload from one export envelope.
///
/// # Errors
/// Fails when the envelope lacks the fields every addon export has.
pub fn plan(envelope: &Value, state: &UploadState) -> Result<Plan> {
    if envelope["enabled"] != Value::Bool(true) {
        return Ok(Plan::Disabled);
    }
    let producer = envelope["producerId"]
        .as_str()
        .context("export has no producerId")?;
    let epoch = envelope["consentEpoch"]
        .as_i64()
        .context("export has no consentEpoch")?;
    let source = format!("{producer}:{epoch}");
    let events = envelope["events"]
        .as_array()
        .context("export has no events list")?;
    let pending: Vec<&Value> = events
        .iter()
        .filter(|e| {
            e["eventId"]
                .as_str()
                .is_some_and(|id| !state.contains(&source, id))
        })
        .collect();
    if pending.is_empty() {
        return Ok(Plan::UpToDate);
    }
    let count = pending.len();
    Ok(Plan::Send {
        batches: batches(envelope, &pending)?,
        source,
        events: count,
    })
}

fn batches(envelope: &Value, pending: &[&Value]) -> Result<Vec<Value>> {
    let mut out = Vec::new();
    let mut current: Vec<Value> = Vec::with_capacity(MAX_BATCH_EVENTS.min(pending.len()));
    let mut bytes = 0;
    for event in pending {
        let mut projected = (*event).clone();
        let kind = projected["kind"].as_str().unwrap_or("").to_owned();
        let world = kind.starts_with("quest.")
            || kind.starts_with("npc.")
            || kind.starts_with("vendor.")
            || kind.starts_with("loot.")
            || kind == "zone.visited";
        let exact_npc =
            kind == "npc.observed" && projected["payload"]["positionMethod"] == "unit_position";
        if world
            && !exact_npc
            && let Some(payload) = projected["payload"].as_object_mut()
        {
            payload.remove("x");
            payload.remove("y");
            payload.remove("z");
        }
        let size = serde_json::to_vec(&projected)?.len() + 1;
        if !current.is_empty()
            && (current.len() == MAX_BATCH_EVENTS || bytes + size > MAX_BATCH_BYTES)
        {
            out.push(with_events(envelope, std::mem::take(&mut current)));
            bytes = 0;
        }
        bytes += size;
        current.push(projected);
    }
    if !current.is_empty() {
        out.push(with_events(envelope, current));
    }
    Ok(out)
}

fn with_events(envelope: &Value, events: Vec<Value>) -> Value {
    let mut batch = envelope.clone();
    batch["events"] = Value::Array(events);
    batch
}

/// Event ids contained in one batch, to mark after the server accepted it.
#[must_use]
pub fn batch_ids(batch: &Value) -> Vec<String> {
    batch["events"]
        .as_array()
        .map(|events| {
            events
                .iter()
                .filter_map(|e| e["eventId"].as_str().map(str::to_owned))
                .collect()
        })
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn envelope(count: usize, payload_len: usize) -> Value {
        let events: Vec<Value> = (0..count).map(|i| json!({ "eventId": format!("p:s:{i}"), "kind": "quest.turned_in", "payload": { "title": "x".repeat(payload_len) } })).collect();
        json!({ "schemaVersion": 1, "enabled": true, "producerId": "p", "consentEpoch": 3, "since": 1, "scopes": ["world_facts"], "events": events })
    }

    #[test]
    fn disabled_export_sends_nothing() {
        let mut value = envelope(3, 1);
        value["enabled"] = json!(false);
        assert_eq!(
            plan(&value, &UploadState::default()).expect("plan"),
            Plan::Disabled
        );
    }

    #[test]
    fn historical_player_coordinates_never_leave_the_desktop() {
        let mut value = envelope(1, 1);
        value["events"][0]["payload"] =
            json!({"mapId":1426,"x":0.4,"y":0.7,"positionMethod":"player_interaction"});
        let Plan::Send { batches, .. } = plan(&value, &UploadState::default()).expect("plan")
        else {
            panic!("expected send")
        };
        assert!(batches[0]["events"][0]["payload"]["x"].is_null());
        assert!(batches[0]["events"][0]["payload"]["y"].is_null());
        assert_eq!(value["events"][0]["payload"]["x"], json!(0.4));
    }

    #[test]
    fn own_route_and_guild_snapshot_are_forwarded_unchanged() {
        // Unlike world facts, a route is the point the player chose to share (own_track); the server enforces the scope.
        let mut value = envelope(2, 1);
        let route = json!({"mapId":1429,"mapSystem":"ui_map","startedAt":100,"points":[[0,0.5,0.5],[10,0.51,0.5]]});
        let guild = json!({"guildName":"Dawn","rankIndex":0,"roster":[{"name":"Bran","rankIndex":3,"level":22,"classId":8}]});
        value["events"][0]["kind"] = json!("track.path");
        value["events"][0]["payload"] = route.clone();
        value["events"][1]["kind"] = json!("guild.snapshot");
        value["events"][1]["payload"] = guild.clone();
        let Plan::Send { batches, .. } = plan(&value, &UploadState::default()).expect("plan")
        else {
            panic!("expected send")
        };
        assert_eq!(batches[0]["events"][0]["payload"], route);
        assert_eq!(batches[0]["events"][1]["payload"], guild);
    }

    #[test]
    fn splits_by_event_count_and_keeps_envelope_fields() {
        let Plan::Send {
            batches,
            events,
            source,
        } = plan(&envelope(1201, 1), &UploadState::default()).expect("plan")
        else {
            panic!("expected send")
        };
        assert_eq!((events, source.as_str()), (1201, "p:3"));
        assert_eq!(
            batches
                .iter()
                .map(|b| b["events"].as_array().map_or(0, Vec::len))
                .collect::<Vec<_>>(),
            vec![500, 500, 201]
        );
        assert!(batches.iter().all(|b| b["producerId"] == "p"
            && b["consentEpoch"] == 3
            && b["scopes"] == json!(["world_facts"])));
    }

    #[test]
    fn splits_by_size_under_the_server_limit() {
        let Plan::Send { batches, .. } =
            plan(&envelope(40, 60_000), &UploadState::default()).expect("plan")
        else {
            panic!("expected send")
        };
        assert!(batches.len() > 1);
        assert!(
            batches
                .iter()
                .all(|b| serde_json::to_vec(b).map_or(usize::MAX, |v| v.len()) < 1024 * 1024)
        );
    }

    #[test]
    fn already_uploaded_events_are_skipped_per_consent_epoch() {
        let value = envelope(3, 1);
        let mut state = UploadState::default();
        state.mark("p:3", ["p:s:0".to_owned(), "p:s:1".to_owned()]);
        let Plan::Send { batches, .. } = plan(&value, &state).expect("plan") else {
            panic!("expected send")
        };
        assert_eq!(batch_ids(&batches[0]), vec!["p:s:2"]);
        state.mark("p:3", ["p:s:2".to_owned()]);
        assert_eq!(plan(&value, &state).expect("plan"), Plan::UpToDate);
        // A new epoch is a new consent: nothing counts as sent yet.
        let mut next = value.clone();
        next["consentEpoch"] = json!(4);
        assert!(matches!(
            plan(&next, &state).expect("plan"),
            Plan::Send { events: 3, .. }
        ));
    }

    #[test]
    fn state_survives_save_and_load() {
        let path =
            std::env::temp_dir().join(format!("evertally-state-test-{}.json", std::process::id()));
        let mut state = UploadState::default();
        state.mark("p:1", ["a".to_owned()]);
        state.save(&path).expect("save");
        assert!(UploadState::load(&path).contains("p:1", "a"));
        let _ = fs::remove_file(path);
    }
}

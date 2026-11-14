//! Local, token-free status for the optional Web sync window and bounded command signals.
use crate::{
    shutdown,
    worker::{Command, UiState},
};
use serde::{Deserialize, Serialize};
use std::{
    path::Path,
    time::{SystemTime, UNIX_EPOCH},
};

pub const STATUS_FILE: &str = "bridge-status.json";

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Snapshot {
    pub at: u64,
    pub server: String,
    pub state: UiState,
    #[serde(default)]
    pub update_status: String,
}

pub fn now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_secs())
}

pub fn publish(path: &Path, server: &str, state: &UiState) -> std::io::Result<()> {
    let bytes = serde_json::to_vec(&Snapshot {
        at: now(),
        server: server.to_owned(),
        state: state.clone(),
        update_status: crate::app_update::status(),
    })?;
    let temp = path.with_extension("json.tmp");
    std::fs::write(&temp, bytes)?;
    std::fs::rename(temp, path)
}

#[must_use]
pub fn read(path: &Path, at: u64) -> Option<Snapshot> {
    if std::fs::metadata(path).ok()?.len() > 64 * 1024 {
        return None;
    }
    let snapshot: Snapshot = serde_json::from_slice(&std::fs::read(path).ok()?).ok()?;
    (snapshot.at <= at.saturating_add(2) && at.saturating_sub(snapshot.at) <= 15)
        .then_some(snapshot)
}

#[derive(Clone, Copy)]
pub enum Action {
    Pair,
    CancelPair,
    Unpair,
    Sync,
}
impl Action {
    pub const ALL: [Self; 4] = [Self::Pair, Self::CancelPair, Self::Unpair, Self::Sync];
    pub fn event(self) -> &'static str {
        match self {
            Self::Pair => "Local\\EvertallyBridgePair",
            Self::CancelPair => "Local\\EvertallyBridgeCancelPair",
            Self::Unpair => "Local\\EvertallyBridgeUnpair",
            Self::Sync => "Local\\EvertallyBridgeSync",
        }
    }
    pub fn command(self) -> Command {
        match self {
            Self::Pair => Command::Pair,
            Self::CancelPair => Command::CancelPair,
            Self::Unpair => Command::Unpair,
            Self::Sync => Command::SyncNow,
        }
    }
    pub fn request(self) {
        shutdown::request(self.event());
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn status_is_token_free_and_expires_after_bridge_disappears() {
        let path = std::env::temp_dir().join(format!(
            "evertally-bridge-state-test-{}.json",
            std::process::id()
        ));
        let state = UiState {
            live_status: None,
            status: "Waiting for approval".into(),
            tooltip: "Bridge".into(),
            paired: false,
            pairing_code: Some("ABCD1234".into()),
            folders: vec![],
        };
        publish(&path, "https://evertally.afstudio.dev", &state).expect("status file");
        let at = now();
        assert_eq!(
            read(&path, at)
                .expect("fresh snapshot")
                .state
                .pairing_code
                .as_deref(),
            Some("ABCD1234")
        );
        assert!(read(&path, at + 16).is_none());
        assert!(read(&path, at.saturating_sub(3)).is_none());
        let mut value: serde_json::Value =
            serde_json::from_slice(&std::fs::read(&path).unwrap()).unwrap();
        assert!(value["state"].get("token").is_none());
        assert!(value["updateStatus"].is_string());
        assert!(value["state"].get("updateStatus").is_none());
        value.as_object_mut().unwrap().remove("updateStatus");
        std::fs::write(&path,serde_json::to_vec(&value).unwrap()).unwrap();
        assert_eq!(read(&path,at).unwrap().update_status, "", "older bridge snapshots remain readable");
        std::fs::remove_file(path).unwrap();
    }
}

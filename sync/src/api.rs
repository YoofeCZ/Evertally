//! Blocking HTTP client for the Evertally device API.

use std::time::Duration;

use serde::Deserialize;
use serde::de::DeserializeOwned;
use serde_json::{Value, json};
use thiserror::Error;

#[derive(Debug, Error)]
pub enum ApiError {
    /// The server answered with an error body (`{ error: { code, message } }`).
    #[error("{message}")]
    Server {
        status: u16,
        code: String,
        message: String,
    },
    /// No usable answer: offline, DNS, TLS, timeout or a non-JSON reply.
    #[error("cannot reach the server: {0}")]
    Network(String),
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn live_reply_distinguishes_stored_and_ignored_points() {
        let stored: LiveResult =
            serde_json::from_value(json!({"accepted":1,"expiresAt":130})).unwrap();
        let ignored: LiveResult =
            serde_json::from_value(json!({"accepted":0,"expiresAt":130})).unwrap();
        assert_eq!((stored.accepted, stored.expires_at), (1, 130));
        assert_eq!(ignored.accepted, 0);
        for malformed in [
            json!({}),
            json!({"accepted":true,"expiresAt":130}),
            json!({"accepted":-1,"expiresAt":130}),
            json!({"accepted":1}),
        ] {
            assert!(serde_json::from_value::<LiveResult>(malformed).is_err());
        }
    }
}

impl ApiError {
    #[must_use]
    pub fn code(&self) -> &str {
        match self {
            Self::Server { code, .. } => code,
            Self::Network(_) => "network",
        }
    }
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Pairing {
    pub device_code: String,
    pub user_code: String,
    pub verification_uri_complete: String,
    pub expires_in: u64,
    pub interval: u64,
}

#[derive(Debug, Deserialize)]
#[serde(tag = "status")]
pub enum PollResult {
    #[serde(rename = "pending")]
    Pending {
        #[serde(default)]
        interval: u64,
    },
    #[serde(rename = "approved")]
    Approved { token: String, user: PairedUser },
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PairedUser {
    pub display_name: String,
}

#[derive(Debug, Deserialize)]
pub struct UploadResult {
    pub accepted: u64,
    pub duplicates: u64,
}

/// A live request can succeed without storing a point (for example, an older or duplicate sample).
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LiveResult {
    pub accepted: u64,
    pub expires_at: u64,
}

pub struct Client {
    agent: ureq::Agent,
    origin: String,
}

impl Client {
    pub fn live(
        &self,
        token: &str,
        packet: &crate::optical::LivePacket,
    ) -> Result<LiveResult, ApiError> {
        self.post(
            "/api/device/live",
            &serde_json::to_value(packet).map_err(|e| ApiError::Network(e.to_string()))?,
            Some(token),
        )
    }
    #[must_use]
    pub fn new(origin: String) -> Self {
        let agent: ureq::Agent = ureq::Agent::config_builder()
            .timeout_global(Some(Duration::from_secs(45)))
            .http_status_as_error(false)
            .user_agent(concat!("EvertallySync/", env!("CARGO_PKG_VERSION")))
            .build()
            .into();
        Self { agent, origin }
    }

    #[must_use]
    pub fn origin(&self) -> &str {
        &self.origin
    }

    fn post<T: DeserializeOwned>(
        &self,
        path: &str,
        body: &Value,
        token: Option<&str>,
    ) -> Result<T, ApiError> {
        let url = format!("{}{path}", self.origin);
        let mut request = self.agent.post(&url);
        if let Some(token) = token {
            request = request.header("Authorization", &format!("Bearer {token}"));
        }
        let mut response = request
            .send_json(body)
            .map_err(|e| ApiError::Network(e.to_string()))?;
        let status = response.status().as_u16();
        let text = response
            .body_mut()
            .read_to_string()
            .map_err(|e| ApiError::Network(e.to_string()))?;
        let value: Value = serde_json::from_str(&text)
            .map_err(|_| ApiError::Network(format!("unexpected reply (HTTP {status})")))?;
        if (200..300).contains(&status) {
            return serde_json::from_value(value)
                .map_err(|e| ApiError::Network(format!("unexpected reply: {e}")));
        }
        let code = value["error"]["code"]
            .as_str()
            .unwrap_or("error")
            .to_owned();
        let message = value["error"]["message"]
            .as_str()
            .unwrap_or("request failed")
            .to_owned();
        Err(ApiError::Server {
            status,
            code,
            message,
        })
    }

    /// Starts pairing; the user approves `user_code` on the website.
    ///
    /// # Errors
    /// Network or server failure.
    pub fn start_pairing(&self, device_name: &str) -> Result<Pairing, ApiError> {
        self.post("/api/device/start", &json!({ "name": device_name }), None)
    }

    /// # Errors
    /// `access_denied` when declined, `expired_token` when expired or already used.
    pub fn poll_pairing(&self, device_code: &str) -> Result<PollResult, ApiError> {
        self.post(
            "/api/device/poll",
            &json!({ "deviceCode": device_code }),
            None,
        )
    }

    /// Uploads one export batch (at most 500 events, under 1 MiB).
    ///
    /// # Errors
    /// `invalid_token` (401) means the app was disconnected on the website.
    pub fn upload(&self, token: &str, batch: &Value) -> Result<UploadResult, ApiError> {
        self.post(
            "/api/device/upload",
            &json!({ "export": batch }),
            Some(token),
        )
    }
}

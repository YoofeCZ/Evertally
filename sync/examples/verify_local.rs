//! Synthetic local integration only: no windows, credentials or live game files.
use anyhow::{Context, Result, ensure};
use evertally_sync::{
    api::Client,
    config::Config,
    savedvars,
    upload::{self, Plan, UploadState},
};
fn main() -> Result<()> {
    let server = std::env::var("EVERTALLY_TEST_BASE")?;
    let uri: ureq::http::Uri = server.parse()?;
    ensure!(
        matches!(uri.host(), Some("127.0.0.1" | "[::1]" | "localhost")),
        "Test server must be loopback"
    );
    let origin = Config {
        server,
        wow_path: None,
    }
    .server_origin()?;
    let token = std::env::var("EVERTALLY_TEST_TOKEN")?;
    let file = std::env::args()
        .nth(1)
        .context("Expected synthetic export fixture")?;
    let text = std::fs::read_to_string(file)?;
    let export = savedvars::parse_assignment(&text, "EvertallyExportDB")?;
    ensure!(
        export["producerId"]
            .as_str()
            .is_some_and(|id| id.starts_with("integration-")),
        "Synthetic fixture required"
    );
    let mut state = UploadState::default();
    let Plan::Send {
        source, batches, ..
    } = upload::plan(&export, &state)?
    else {
        anyhow::bail!("Expected pending synthetic events")
    };
    let client = Client::new(origin);
    let mut accepted = 0;
    let mut duplicates = 0;
    for batch in &batches {
        accepted += client.upload(&token, batch)?.accepted;
        state.mark(&source, upload::batch_ids(batch));
        duplicates += client.upload(&token, batch)?.duplicates;
    }
    ensure!(
        matches!(upload::plan(&export, &state)?, Plan::UpToDate),
        "Upload cursor did not advance"
    );
    println!(
        "{}",
        serde_json::json!({"accepted":accepted,"duplicates":duplicates,"pending":0,"mode":"synthetic-local-only"})
    );
    Ok(())
}

//! Evertally Sync: uploads new records from the Evertally addon's export file to the
//! Evertally website after the game saves them.
//!
//! The library is shared by the standalone tray app (`tray` feature, this crate's binary)
//! and the Evertally desktop app (Tauri), which embeds the website and these modules.

pub mod api;
pub mod config;
pub mod lang;
pub mod local;
pub mod platform;
pub mod savedvars;
#[cfg(feature = "tray")]
pub mod ui;
pub mod upload;
pub mod worker;
pub mod wow;

/// Starts the tray app. Returns only on startup errors; quitting exits the process.
///
/// # Errors
/// Fails when settings cannot be read or the server address is not allowed.
#[cfg(feature = "tray")]
pub fn run() -> anyhow::Result<()> {
    use anyhow::Context;
    use std::sync::mpsc;
    use std::thread;
    use tao::event_loop::EventLoopBuilder;

    use crate::config::Paths;
    use crate::ui::UserEvent;
    use crate::worker::Worker;

    let Some(_instance) = platform::single_instance() else {
        // Already running for this user: the existing tray icon is the app.
        return Ok(());
    };
    let paths = Paths::new()?;
    let config = config::load_config(&paths.config)?;
    let origin = config
        .server_origin()
        .with_context(|| format!("check \"server\" in {}", paths.config.display()))?;
    let texts = if platform::prefers_czech() {
        &lang::CS
    } else {
        &lang::EN
    };
    config::log(
        &paths.log,
        &format!("start v{} server={origin}", env!("CARGO_PKG_VERSION")),
    );

    let (tx, rx) = mpsc::channel();
    let event_loop = EventLoopBuilder::<UserEvent>::with_user_event().build();
    let proxy = event_loop.create_proxy();
    let publish = Box::new(move |state| {
        let _ = proxy.send_event(UserEvent::State(state));
    });
    let worker = Worker::new(
        texts,
        paths.clone(),
        config,
        origin.clone(),
        publish,
        tx.clone(),
        true,
    );
    thread::Builder::new()
        .name("evertally-sync".into())
        .spawn(move || worker.run(&rx))
        .context("start worker thread")?;
    ui::run(event_loop, texts, paths.dir, origin, tx)
}

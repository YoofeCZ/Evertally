//! Evertally Sync: uploads new records from the Evertally addon's export file to the
//! Evertally website after the game saves them.
//!
//! The tray bridge and its connection settings share this library.

pub mod api;
mod ack;
pub mod addon_update;
pub mod app_update;
pub mod community;
pub mod bridge;
pub mod config;
pub mod forum;
pub mod game;
pub mod game_requests;
pub mod lang;
pub mod local;
pub mod music;
pub mod notify;
pub mod optical;
pub mod platform;
pub mod ranking;
pub mod savedvars;
#[cfg(not(windows))]
pub mod screen;
pub mod shutdown;
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
    // Keep the tray and its repair settings available even when the local file is damaged.
    let config = config::load_config(&paths.config).unwrap_or_else(|_| config::Config {
        server: String::new(),
        wow_path: None,
    });
    let origin = config
        .server_origin()
        .unwrap_or_else(|_| config::DEFAULT_SERVER.to_owned());
    let texts = if platform::prefers_czech() {
        &lang::CS
    } else {
        &lang::EN
    };
    config::log(
        &paths.log,
        &format!("start v{} server={origin}", env!("CARGO_PKG_VERSION")),
    );

    // one notification after the app replaced itself with a newer version
    crate::app_update::announce_if_updated(&paths.dir, env!("CARGO_PKG_VERSION"));
    let (tx, rx) = mpsc::channel();
    #[allow(unused_mut)] // only the macOS branch below mutates it
    let mut event_loop = EventLoopBuilder::<UserEvent>::with_user_event().build();
    #[cfg(target_os = "macos")]
    {
        // Menu bar icon only: no Dock icon, and starting with WoW never takes focus from the game.
        use tao::platform::macos::{ActivationPolicy, EventLoopExtMacOS};
        event_loop.set_activation_policy(ActivationPolicy::Accessory);
        event_loop.set_activate_ignoring_other_apps(false);
    }
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

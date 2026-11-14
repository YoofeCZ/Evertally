//! Tray icon and menu on the main thread.

use std::path::PathBuf;
use std::sync::mpsc::Sender;
use std::time::{Duration, Instant};

use tao::event::{Event, StartCause};
use tao::event_loop::{ControlFlow, EventLoop};
use tray_icon::menu::{CheckMenuItem, Menu, MenuEvent, MenuItem, PredefinedMenuItem};
use tray_icon::{Icon, TrayIcon, TrayIconBuilder};

use crate::lang::Texts;
use crate::platform;
use crate::worker::{Command, UiState};

type Shape = Box<dyn Fn(f32, f32) -> f32>;

pub enum UserEvent {
    Menu(MenuEvent),
    State(UiState),
    SettingsClosed,
    ReloadSettings,
}

/// Runs the tray until the user quits. Never returns.
pub fn run(
    event_loop: EventLoop<UserEvent>,
    texts: &'static Texts,
    settings_dir: PathBuf,
    mut site: String,
    tx: Sender<Command>,
) -> ! {
    let proxy = event_loop.create_proxy();
    MenuEvent::set_event_handler(Some(move |event| {
        let _ = proxy.send_event(UserEvent::Menu(event));
    }));

    let status = MenuItem::new(texts.starting, false, None);
    let sync = MenuItem::new(texts.sync_now, true, None);
    let version = MenuItem::new(
        format!("Evertally Bridge {}", crate::app_update::current_version().unwrap_or("?")),
        false,
        None,
    );
    let update_line = MenuItem::new(texts.update_idle, false, None);
    let check_update = MenuItem::new(texts.check_updates, true, None);
    let mut shown_update = String::new();
    let open_site = MenuItem::new(texts.open_site, true, None);
    let pair = MenuItem::new(texts.pair, true, None);
    let settings = MenuItem::new(texts.settings, true, None);
    let pairing_code = MenuItem::new("", false, None);
    let cancel_pair = MenuItem::new(texts.cancel_pair, false, None);
    let folders = MenuItem::new(texts.no_folders, false, None);
    let autostart = CheckMenuItem::new(texts.autostart, true, platform::autostart_enabled(), None);
    let folder = MenuItem::new(texts.open_folder, true, None);
    let quit = MenuItem::new(texts.quit, true, None);
    let menu = Menu::new();
    let _ = menu.append_items(&[
        &version,
        &update_line,
        &PredefinedMenuItem::separator(),
        &status,
        &folders,
        &PredefinedMenuItem::separator(),
        &sync,
        &check_update,
        &open_site,
        &pair,
        &pairing_code,
        &cancel_pair,
        &PredefinedMenuItem::separator(),
        &autostart,
        &settings,
        &folder,
        &PredefinedMenuItem::separator(),
        &quit,
    ]);

    let mut tray: Option<TrayIcon> = None;
    let mut paired = false;
    let stop = crate::shutdown::StopSignal::new(crate::shutdown::BRIDGE_STOP);
    let reload = crate::shutdown::StopSignal::new(crate::shutdown::BRIDGE_RELOAD);
    let settings_proxy = event_loop.create_proxy();
    let status_path = settings_dir.join(crate::bridge::STATUS_FILE);
    let mut latest_state: Option<UiState> = None;
    let mut last_status_write = Instant::now();
    let actions: Vec<_> = crate::bridge::Action::ALL
        .into_iter()
        .filter_map(|action| {
            crate::shutdown::StopSignal::new(action.event()).map(|signal| (signal, action))
        })
        .collect();
    event_loop.run(move |event, _, control_flow| {
        *control_flow = ControlFlow::WaitUntil(Instant::now() + Duration::from_millis(250));
        if stop
            .as_ref()
            .is_some_and(crate::shutdown::StopSignal::requested)
        {
            let _ = tx.send(Command::Quit);
            crate::shutdown::request(crate::shutdown::SETTINGS_STOP);
            let _ = std::fs::remove_file(&status_path);
            tray = None;
            *control_flow = ControlFlow::Exit;
            return;
        }
        if let Some(signal) = &reload
            && signal.requested()
        {
            signal.reset();
            let _ = settings_proxy.send_event(UserEvent::ReloadSettings);
        }
        for (signal, action) in &actions {
            if signal.requested() {
                signal.reset();
                let _ = tx.send(action.command());
            }
        }
        let update_text = crate::app_update::status();
        if !update_text.is_empty() && update_text != shown_update {
            update_line.set_text(&update_text);
            shown_update = update_text;
        }
        if last_status_write.elapsed() >= Duration::from_secs(5) {
            if let Some(state) = &latest_state {
                let _ = crate::bridge::publish(&status_path, &site, state);
            }
            last_status_write = Instant::now();
        }
        match event {
            // The icon must be created once the loop runs (required on macOS, harmless elsewhere).
            Event::NewEvents(StartCause::Init) => {
                match TrayIconBuilder::new()
                    .with_menu(Box::new(menu.clone()))
                    .with_tooltip("Evertally Bridge")
                    .with_icon(icon())
                    .build()
                {
                    Ok(icon) => tray = Some(icon),
                    Err(error) => {
                        platform::error_dialog(&format!("Evertally Bridge: {error}"));
                        let _ = tx.send(Command::Quit);
                        *control_flow = ControlFlow::Exit;
                    }
                }
            }
            Event::UserEvent(UserEvent::State(state)) => {
                let _ = crate::bridge::publish(&status_path, &site, &state);
                latest_state = Some(state.clone());
                status.set_text(&state.status);
                paired = state.paired;
                pair.set_text(if paired { texts.unpair } else { texts.pair });
                let pending = state.pairing_code.is_some();
                pair.set_enabled(!pending);
                cancel_pair.set_enabled(pending);
                pairing_code.set_text(state.pairing_code.as_deref().unwrap_or(texts.no_pairing));
                folders.set_text(crate::lang::fill(
                    texts.folders,
                    &[("count", &state.folders.len().to_string())],
                ));
                sync.set_enabled(paired);
                if let Some(tray) = &tray {
                    let _ = tray.set_tooltip(Some(&state.tooltip));
                }
            }
            Event::UserEvent(UserEvent::SettingsClosed) => {
                settings.set_enabled(true);
            }
            Event::UserEvent(UserEvent::ReloadSettings) => {
                if let Ok(paths) = crate::config::Paths::new()
                    && let Ok(config) = crate::config::load_config(&paths.config)
                    && let Ok(origin) = config.server_origin()
                {
                    site = origin;
                    latest_state = None;
                    let _ = std::fs::remove_file(&status_path);
                    let _ = tx.send(Command::ReloadConfig(config));
                }
                autostart.set_checked(platform::autostart_enabled());
            }
            Event::UserEvent(UserEvent::Menu(event)) => {
                let id = &event.id;
                if id == check_update.id() {
                    let _ = tx.send(Command::CheckUpdate);
                } else if id == sync.id() {
                    let _ = tx.send(Command::SyncNow);
                } else if id == open_site.id() {
                    let _ = open::that(&site);
                } else if id == pair.id() {
                    let _ = tx.send(if paired {
                        Command::Unpair
                    } else {
                        Command::Pair
                    });
                } else if id == autostart.id() {
                    if platform::set_autostart(autostart.is_checked()).is_err() {
                        autostart.set_checked(platform::autostart_enabled());
                    }
                } else if id == cancel_pair.id() {
                    let _ = tx.send(Command::CancelPair);
                } else if id == settings.id() {
                    settings.set_enabled(false);
                    let proxy = settings_proxy.clone();
                    std::thread::spawn(move || {
                        if let Ok(exe) = std::env::current_exe() {
                            let _ = std::process::Command::new(exe)
                                .arg("--connection-settings")
                                .status();
                        }
                        let _ = proxy.send_event(UserEvent::SettingsClosed);
                    });
                } else if id == folder.id() {
                    let _ = open::that(&settings_dir);
                } else if id == quit.id() {
                    let _ = tx.send(Command::Quit);
                    crate::shutdown::request(crate::shutdown::SETTINGS_STOP);
                    let _ = std::fs::remove_file(&status_path);
                    tray = None;
                    *control_flow = ControlFlow::Exit;
                }
            }
            _ => {}
        }
    })
}

/// The Evertally tally mark, rasterised with 4x4 supersampling (no image files needed).
// Coordinates stay within 0..32 and channels within 0..=255, so these casts are exact.
#[allow(
    clippy::cast_precision_loss,
    clippy::cast_possible_truncation,
    clippy::cast_sign_loss
)]
fn icon() -> Icon {
    const SIZE: u32 = 32;
    let mut rgba = vec![0_u8; (SIZE * SIZE * 4) as usize];
    let segment_distance = |px: f32, py: f32, (ax, ay): (f32, f32), (bx, by): (f32, f32)| {
        let (dx, dy) = (bx - ax, by - ay);
        let t = (((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)).clamp(0.0, 1.0);
        ((px - ax - t * dx).powi(2) + (py - ay - t * dy).powi(2)).sqrt()
    };
    let rounded_box = |px: f32, py: f32| {
        let (qx, qy) = ((px - 16.0).abs() - 9.0, (py - 16.0).abs() - 9.0);
        qx.max(0.0).hypot(qy.max(0.0)) + qx.max(qy).min(0.0) - 6.5
    };
    let layers: [([u8; 3], Shape); 3] = [
        ([0x13, 0x11, 0x1c], Box::new(rounded_box)),
        (
            [0xf7, 0xf7, 0xf8],
            Box::new(move |x, y| {
                [10.5, 14.0, 17.5, 21.0]
                    .iter()
                    .map(|&lx| segment_distance(x, y, (lx, 9.5), (lx, 22.5)))
                    .fold(f32::MAX, f32::min)
                    - 1.15
            }),
        ),
        (
            [0xa7, 0x8b, 0xfa],
            Box::new(move |x, y| segment_distance(x, y, (7.5, 20.0), (24.5, 12.0)) - 1.35),
        ),
    ];
    for y in 0..SIZE {
        for x in 0..SIZE {
            let index = ((y * SIZE + x) * 4) as usize;
            let mut pixel = [0.0_f32; 4];
            for (color, shape) in &layers {
                let mut coverage = 0.0;
                for sy in 0..4 {
                    for sx in 0..4 {
                        let (fx, fy) = (
                            x as f32 + (sx as f32 + 0.5) / 4.0,
                            y as f32 + (sy as f32 + 0.5) / 4.0,
                        );
                        if shape(fx, fy) <= 0.0 {
                            coverage += 1.0 / 16.0;
                        }
                    }
                }
                for channel in 0..3 {
                    pixel[channel] =
                        pixel[channel] * (1.0 - coverage) + f32::from(color[channel]) * coverage;
                }
                pixel[3] = pixel[3] * (1.0 - coverage) + 255.0 * coverage;
            }
            for (slot, value) in rgba[index..index + 4].iter_mut().zip(pixel) {
                *slot = value.round().clamp(0.0, 255.0) as u8;
            }
        }
    }
    Icon::from_rgba(rgba, SIZE, SIZE)
        .unwrap_or_else(|_| unreachable!("a 32x32 RGBA buffer is always a valid icon"))
}

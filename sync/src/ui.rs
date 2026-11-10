//! Tray icon and menu on the main thread.

use std::path::PathBuf;
use std::sync::mpsc::Sender;

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
}

/// Runs the tray until the user quits. Never returns.
pub fn run(
    event_loop: EventLoop<UserEvent>,
    texts: &'static Texts,
    settings_dir: PathBuf,
    site: String,
    tx: Sender<Command>,
) -> ! {
    let proxy = event_loop.create_proxy();
    MenuEvent::set_event_handler(Some(move |event| {
        let _ = proxy.send_event(UserEvent::Menu(event));
    }));

    let status = MenuItem::new(texts.starting, false, None);
    let sync = MenuItem::new(texts.sync_now, true, None);
    let open_site = MenuItem::new(texts.open_site, true, None);
    let pair = MenuItem::new(texts.pair, true, None);
    let autostart = CheckMenuItem::new(texts.autostart, true, platform::autostart_enabled(), None);
    let folder = MenuItem::new(texts.open_folder, true, None);
    let quit = MenuItem::new(texts.quit, true, None);
    let menu = Menu::new();
    let _ = menu.append_items(&[
        &status,
        &PredefinedMenuItem::separator(),
        &sync,
        &open_site,
        &pair,
        &PredefinedMenuItem::separator(),
        &autostart,
        &folder,
        &PredefinedMenuItem::separator(),
        &quit,
    ]);

    let mut tray: Option<TrayIcon> = None;
    let mut paired = false;
    event_loop.run(move |event, _, control_flow| {
        *control_flow = ControlFlow::Wait;
        match event {
            // The icon must be created once the loop runs (required on macOS, harmless elsewhere).
            Event::NewEvents(StartCause::Init) => {
                tray = TrayIconBuilder::new()
                    .with_menu(Box::new(menu.clone()))
                    .with_tooltip("Evertally Sync")
                    .with_icon(icon())
                    .build()
                    .ok();
            }
            Event::UserEvent(UserEvent::State(state)) => {
                status.set_text(&state.status);
                paired = state.paired;
                pair.set_text(if paired { texts.unpair } else { texts.pair });
                sync.set_enabled(paired);
                if let Some(tray) = &tray {
                    let _ = tray.set_tooltip(Some(&state.tooltip));
                }
            }
            Event::UserEvent(UserEvent::Menu(event)) => {
                let id = &event.id;
                if id == sync.id() {
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
                } else if id == folder.id() {
                    let _ = open::that(&settings_dir);
                } else if id == quit.id() {
                    let _ = tx.send(Command::Quit);
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

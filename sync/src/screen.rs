//! Linux and macOS: a small zone in the top-left corner of the Forever window, in RAM, for
//! [`crate::optical::find_marker`]. Windows has its own exact reader in `optical.rs`.
//!
//! Only a bounded zone (at most [`ZONE_WIDTH`] x [`ZONE_HEIGHT`] pixels) is read, only from windows of
//! the Forever process, and nothing is stored or sent as an image. The zone is larger than the marker
//! strip because window frames and title bars on these systems shift the game's own corner.
//!
//! * macOS: the zone of the screen under the window (what the player sees there), through the system
//!   capture API. macOS asks the player once for the Screen Recording permission.
//! * Linux: the window's own pixels through the X11 protocol; Wine and Proton windows are X11 clients,
//!   also under Wayland (XWayland). A pure Wayland session offers no way to read other windows.

use std::path::Path;

/// Largest zone read from a window, in pixels.
pub const ZONE_WIDTH: usize = 320;
pub const ZONE_HEIGHT: usize = 200;

/// A captured zone: BGRA, row-major, `width * height * 4` bytes.
pub struct Zone {
    pub width: usize,
    pub height: usize,
    pub bgra: Vec<u8>,
}

/// Offers the zone of each visible Forever window (the focused one first) to `look` until it returns a result.
#[cfg(target_os = "macos")]
pub fn capture_with<T>(configured: Option<&Path>, mut look: impl FnMut(&Zone) -> Option<T>) -> Option<T> {
    use xcap::{Monitor, Window};
    let pids = crate::game::forever_processes(configured);
    if pids.is_empty() {
        return None;
    }
    let monitors = Monitor::all().ok()?;
    let mut windows: Vec<Window> = Window::all()
        .ok()?
        .into_iter()
        .filter(|window| {
            window.pid().is_ok_and(|pid| pids.contains(&pid))
                && window.is_minimized().is_ok_and(|minimised| !minimised)
        })
        .collect();
    windows.sort_by_key(|window| !window.is_focused().unwrap_or(false));
    for window in windows {
        let (Ok(x), Ok(y), Ok(width), Ok(height)) =
            (window.x(), window.y(), window.width(), window.height())
        else {
            continue;
        };
        let Some(monitor) = monitors.iter().find(|monitor| {
            matches!(
                (monitor.x(), monitor.y(), monitor.width(), monitor.height()),
                (Ok(mx), Ok(my), Ok(mw), Ok(mh))
                    if x >= mx && y >= my && x < mx + mw as i32 && y < my + mh as i32
            )
        }) else {
            continue;
        };
        let (Ok(mx), Ok(my), Ok(mw), Ok(mh)) =
            (monitor.x(), monitor.y(), monitor.width(), monitor.height())
        else {
            continue;
        };
        // Window and monitor are in points; the zone stays inside both.
        let (local_x, local_y) = ((x - mx) as u32, (y - my) as u32);
        let zone_w = width.min(ZONE_WIDTH as u32).min(mw - local_x);
        let zone_h = height.min(ZONE_HEIGHT as u32).min(mh - local_y);
        if zone_w < 64 || zone_h < 4 {
            continue;
        }
        let Ok(image) = monitor.capture_region(local_x, local_y, zone_w, zone_h) else {
            continue;
        };
        let (width, height) = (image.width() as usize, image.height() as usize);
        let mut bgra = image.into_raw();
        for pixel in bgra.chunks_exact_mut(4) {
            pixel.swap(0, 2); // RGBA -> BGRA
        }
        if let Some(found) = look(&Zone { width, height, bgra }) {
            return Some(found);
        }
    }
    None
}

/// Offers the zone of each visible Forever window (the focused one first) to `look` until it returns a result.
#[cfg(target_os = "linux")]
pub fn capture_with<T>(configured: Option<&Path>, mut look: impl FnMut(&Zone) -> Option<T>) -> Option<T> {
    use x11rb::{
        connection::Connection,
        protocol::xproto::{AtomEnum, ConnectionExt, ImageFormat, ImageOrder},
        rust_connection::RustConnection,
    };
    let pids = crate::game::forever_processes(configured);
    if pids.is_empty() {
        return None;
    }
    // No DISPLAY (a headless session) simply means there is nothing to read.
    let (conn, screen_number) = RustConnection::connect(None).ok()?;
    let setup = conn.setup();
    let root = setup.roots.get(screen_number)?.root;
    let msb_first = setup.image_byte_order == ImageOrder::MSB_FIRST;
    let atom = |name: &[u8]| {
        conn.intern_atom(false, name)
            .ok()?
            .reply()
            .ok()
            .map(|reply| reply.atom)
    };
    let (client_list, wm_pid, wm_state, hidden, active) = (
        atom(b"_NET_CLIENT_LIST")?,
        atom(b"_NET_WM_PID")?,
        atom(b"_NET_WM_STATE")?,
        atom(b"_NET_WM_STATE_HIDDEN")?,
        atom(b"_NET_ACTIVE_WINDOW")?,
    );
    let property = |window: u32, name: u32, kind: AtomEnum, len: u32| {
        conn.get_property(false, window, name, kind, 0, len)
            .ok()?
            .reply()
            .ok()
    };
    let focused = property(root, active, AtomEnum::WINDOW, 1)
        .and_then(|reply| reply.value32()?.next())
        .unwrap_or(0);
    let mut windows: Vec<u32> = property(root, client_list, AtomEnum::WINDOW, 4096)?
        .value32()?
        .collect();
    windows.sort_by_key(|window| *window != focused);
    for window in windows {
        let pid = property(window, wm_pid, AtomEnum::CARDINAL, 1).and_then(|reply| reply.value32()?.next());
        if !pid.is_some_and(|pid| pids.contains(&pid)) {
            continue;
        }
        let minimised = property(window, wm_state, AtomEnum::ATOM, 32)
            .and_then(|reply| Some(reply.value32()?.any(|state| state == hidden)))
            .unwrap_or(false);
        if minimised {
            continue;
        }
        let Some(geometry) = conn.get_geometry(window).ok().and_then(|cookie| cookie.reply().ok()) else {
            continue;
        };
        let zone_w = geometry.width.min(ZONE_WIDTH as u16);
        let zone_h = geometry.height.min(ZONE_HEIGHT as u16);
        if zone_w < 64 || zone_h < 4 {
            continue;
        }
        let Some(image) = conn
            .get_image(ImageFormat::Z_PIXMAP, window, 0, 0, zone_w, zone_h, u32::MAX)
            .ok()
            .and_then(|cookie| cookie.reply().ok())
        else {
            continue;
        };
        // Only 32 bits per pixel (the usual TrueColor layout) is read; anything else is skipped.
        let bits = setup
            .pixmap_formats
            .iter()
            .find(|format| format.depth == image.depth)
            .map(|format| format.bits_per_pixel);
        let (width, height) = (usize::from(zone_w), usize::from(zone_h));
        if bits != Some(32) || image.data.len() != width * height * 4 {
            continue;
        }
        let mut bgra = image.data;
        if msb_first {
            for pixel in bgra.chunks_exact_mut(4) {
                pixel.reverse(); // XRGB -> BGRX
            }
        }
        if let Some(found) = look(&Zone { width, height, bgra }) {
            return Some(found);
        }
    }
    None
}

/// Other Unix systems: nothing to read.
#[cfg(not(any(windows, target_os = "macos", target_os = "linux")))]
pub fn capture_with<T>(_configured: Option<&Path>, _look: impl FnMut(&Zone) -> Option<T>) -> Option<T> {
    None
}

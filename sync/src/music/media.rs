//! Windows media controls (the play / pause / skip a media keyboard reaches) and the volume of the playing app.
//! Works with whatever plays: the Spotify app, the YouTube Music window, a browser. Nothing is sent to the game.
use anyhow::{Context, Result};
use windows::Media::Control::{GlobalSystemMediaTransportControlsSession as Session, GlobalSystemMediaTransportControlsSessionManager as Manager};
use windows::Win32::Media::Audio::{IAudioSessionControl2, IAudioSessionManager2, IMMDeviceEnumerator, ISimpleAudioVolume, MMDeviceEnumerator, eMultimedia, eRender};
use windows::Win32::System::Com::{CLSCTX_ALL, COINIT_MULTITHREADED, CoCreateInstance, CoInitializeEx};
use windows::core::Interface;

/// Once per thread that uses the controls.
pub fn init_thread() {
    // SAFETY: plain COM initialisation of the calling thread; a second call on the same thread only returns S_FALSE.
    let _ = unsafe { CoInitializeEx(None, COINIT_MULTITHREADED) };
}

fn session() -> Result<Session> {
    let manager = Manager::RequestAsync()?.join()?;
    manager.GetCurrentSession().context("nothing is playing on this PC")
}

pub fn toggle() -> Result<()> {
    session()?.TryTogglePlayPauseAsync()?.join()?;
    Ok(())
}
pub fn play() -> Result<()> {
    session()?.TryPlayAsync()?.join()?;
    Ok(())
}
pub fn pause() -> Result<()> {
    session()?.TryPauseAsync()?.join()?;
    Ok(())
}
pub fn next() -> Result<()> {
    session()?.TrySkipNextAsync()?.join()?;
    Ok(())
}
pub fn previous() -> Result<()> {
    session()?.TrySkipPreviousAsync()?.join()?;
    Ok(())
}

/// The app that plays now, as Windows names it (`Spotify.exe`, `Chrome`, `MSEdge`…), and the song.
pub fn now_playing() -> Result<(String, Option<String>)> {
    let session = session()?;
    let app = session.SourceAppUserModelId()?.to_string();
    let title = session.TryGetMediaPropertiesAsync()?.join().ok().and_then(|p| {
        let title = p.Title().ok()?.to_string();
        let artist = p.Artist().ok().map(|a| a.to_string()).unwrap_or_default();
        (!title.is_empty()).then(|| if artist.is_empty() { title } else { format!("{title} - {artist}") })
    });
    Ok((app, title))
}

/// True when the audio session of process `exe` (file name) belongs to the media app `app`.
#[must_use]
pub fn same_app(app: &str, exe: &str) -> bool {
    let app = app.to_ascii_lowercase();
    let stem = exe.to_ascii_lowercase();
    let stem = stem.strip_suffix(".exe").unwrap_or(&stem);
    !stem.is_empty() && (app.contains(stem) || (stem == "msedge" && app.contains("edge")) || (stem == "chrome" && app.contains("chrome")))
}

fn exe_of(pid: u32) -> Option<String> {
    use windows_sys::Win32::Foundation::CloseHandle;
    use windows_sys::Win32::System::Threading::{OpenProcess, PROCESS_QUERY_LIMITED_INFORMATION, QueryFullProcessImageNameW};
    // SAFETY: the handle is checked and closed; the buffer is sized for the longest path.
    unsafe {
        let process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, pid);
        if process.is_null() {
            return None;
        }
        let mut name = vec![0u16; 32768];
        let mut len = name.len() as u32;
        let ok = QueryFullProcessImageNameW(process, 0, name.as_mut_ptr(), &mut len);
        CloseHandle(process);
        (ok != 0).then(|| {
            let path = String::from_utf16_lossy(&name[..len as usize]);
            path.rsplit(['\\', '/']).next().unwrap_or_default().to_owned()
        })
    }
}

/// The volume controls of every audio session of the playing app.
fn volumes(app: &str) -> Result<Vec<ISimpleAudioVolume>> {
    // SAFETY: COM calls on interfaces the system hands out; every interface is reference counted by the `windows` crate.
    unsafe {
        let devices: IMMDeviceEnumerator = CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_ALL)?;
        let device = devices.GetDefaultAudioEndpoint(eRender, eMultimedia)?;
        let manager: IAudioSessionManager2 = device.Activate(CLSCTX_ALL, None)?;
        let sessions = manager.GetSessionEnumerator()?;
        let mut out = Vec::new();
        for i in 0..sessions.GetCount()? {
            let control = sessions.GetSession(i)?;
            let Ok(control2) = control.cast::<IAudioSessionControl2>() else { continue };
            let Ok(pid) = control2.GetProcessId() else { continue };
            if exe_of(pid).is_some_and(|exe| same_app(app, &exe))
                && let Ok(volume) = control.cast::<ISimpleAudioVolume>()
            {
                out.push(volume);
            }
        }
        Ok(out)
    }
}

/// The playing app's own volume (0..1), as the Windows volume mixer shows it.
pub fn volume() -> Result<Option<f32>> {
    let (app, _) = now_playing()?;
    // SAFETY: see `volumes`.
    Ok(volumes(&app)?.first().and_then(|v| unsafe { v.GetMasterVolume() }.ok()))
}

pub fn set_volume(level: f32) -> Result<()> {
    let (app, _) = now_playing()?;
    for v in volumes(&app)? {
        // SAFETY: see `volumes`.
        unsafe { v.SetMasterVolume(level.clamp(0.0, 1.0), std::ptr::null())? };
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn audio_sessions_are_matched_to_the_media_app() {
        assert!(same_app("Spotify.exe", "Spotify.exe"));
        assert!(same_app("Chrome", "chrome.exe"));
        assert!(same_app("MSEdge", "msedge.exe"));
        assert!(!same_app("Spotify.exe", "Wow.exe"));
        assert!(!same_app("Spotify.exe", ".exe"));
    }
}

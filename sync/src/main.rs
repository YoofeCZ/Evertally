// No console window in release builds; debug builds keep it for diagnostics.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    if let Err(error) = evertally_sync::run() {
        evertally_sync::platform::error_dialog(&format!(
            "Evertally Sync could not start:\n{error:#}"
        ));
        std::process::exit(1);
    }
}

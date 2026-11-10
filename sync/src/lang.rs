//! Tray texts. English by default, Czech on a Czech Windows.

pub struct Texts {
    pub starting: &'static str,
    pub not_paired: &'static str,
    pub pairing: &'static str,
    pub pairing_tooltip: &'static str,
    pub pairing_expired: &'static str,
    pub pairing_declined: &'static str,
    pub paired_as: &'static str,
    pub no_wow: &'static str,
    pub watching: &'static str,
    pub up_to_date: &'static str,
    pub uploaded: &'static str,
    pub export_off: &'static str,
    pub offline: &'static str,
    pub disconnected: &'static str,
    pub sync_now: &'static str,
    pub open_site: &'static str,
    pub pair: &'static str,
    pub unpair: &'static str,
    pub autostart: &'static str,
    pub open_folder: &'static str,
    pub quit: &'static str,
    pub settings: &'static str,
    pub cancel_pair: &'static str,
    pub no_pairing: &'static str,
    pub no_folders: &'static str,
    pub folders: &'static str,
}

pub const EN: Texts = Texts {
    starting: "Starting…",
    not_paired: "Not paired with Evertally",
    pairing: "Approve code {code} in your browser",
    pairing_tooltip: "Evertally Sync: approve code {code}",
    pairing_expired: "Pairing expired. Choose “Pair this PC” again.",
    pairing_declined: "Pairing was declined on the website.",
    paired_as: "Paired as {name}",
    no_wow: "World of Warcraft not found. Choose its folder in Connection settings.",
    watching: "Watching {count} WoW account folder(s)",
    up_to_date: "Up to date · {time}",
    uploaded: "Uploaded {count} new record(s) · {time}",
    export_off: "Web export is off in game. Type /etally web on",
    offline: "Server unreachable, will retry",
    disconnected: "This PC was disconnected on the website",
    sync_now: "Sync now",
    open_site: "Open Evertally website",
    pair: "Pair this PC…",
    unpair: "Disconnect this PC",
    autostart: "Start automatically with WoW",
    open_folder: "Open settings folder",
    quit: "Quit",
    settings: "Web sync and settings…",
    cancel_pair: "Cancel pairing",
    no_pairing: "No pairing in progress",
    no_folders: "Looking for WoW folders…",
    folders: "WoW account folders: {count}",
};

pub const CS: Texts = Texts {
    starting: "Spouštím…",
    not_paired: "Nespárováno s Evertally",
    pairing: "Potvrď kód {code} v prohlížeči",
    pairing_tooltip: "Evertally Sync: potvrď kód {code}",
    pairing_expired: "Párování vypršelo. Zvol znovu „Spárovat tento počítač“.",
    pairing_declined: "Párování bylo na webu odmítnuto.",
    paired_as: "Spárováno jako {name}",
    no_wow: "World of Warcraft nenalezen. Vyber jeho složku v Nastavení spojení.",
    watching: "Hlídám složky účtů WoW: {count}",
    up_to_date: "Vše odesláno · {time}",
    uploaded: "Odesláno nových záznamů: {count} · {time}",
    export_off: "Webový export je ve hře vypnutý. Napiš /etally web on",
    offline: "Server je nedostupný, zkusím to znovu",
    disconnected: "Tento počítač byl na webu odpojen",
    sync_now: "Synchronizovat teď",
    open_site: "Otevřít web Evertally",
    pair: "Spárovat tento počítač…",
    unpair: "Odpojit tento počítač",
    autostart: "Spouštět automaticky s WoW",
    open_folder: "Otevřít složku s nastavením",
    quit: "Ukončit",
    settings: "Web sync a nastavení…",
    cancel_pair: "Zrušit párování",
    no_pairing: "Párování právě neprobíhá",
    no_folders: "Hledám složky WoW…",
    folders: "Složky účtů WoW: {count}",
};

/// Fills `{name}` placeholders.
#[must_use]
pub fn fill(template: &str, pairs: &[(&str, &str)]) -> String {
    pairs
        .iter()
        .fold(template.to_owned(), |text, (key, value)| {
            text.replace(&format!("{{{key}}}"), value)
        })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fills_placeholders() {
        assert_eq!(
            fill(EN.pairing, &[("code", "ABCD-EFGH")]),
            "Approve code ABCD-EFGH in your browser"
        );
        assert_eq!(
            fill(CS.uploaded, &[("count", "3"), ("time", "18:00")]),
            "Odesláno nových záznamů: 3 · 18:00"
        );
    }
}

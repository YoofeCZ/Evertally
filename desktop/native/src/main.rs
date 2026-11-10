#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod catalog;
mod community;
mod identity;
mod map;
mod model;
mod preview;

use std::path::PathBuf;
use std::sync::mpsc::{self, Receiver, Sender};
use std::time::{Duration, Instant};

use eframe::egui::{self, Color32, RichText, Stroke, Vec2};
use evertally_sync::{
    config::{self, Config, Paths},
    lang,
    local::{self, AccountData},
    platform,
    worker::{Command, UiState, Worker},
    wow,
};
use serde::{Deserialize, Serialize};
use serde_json::Value;

const CANVAS: Color32 = Color32::from_rgb(19, 17, 28);
const PANEL: Color32 = Color32::from_rgb(28, 26, 40);
const NAVY: Color32 = Color32::from_rgb(27, 33, 50);
const VIOLET: Color32 = Color32::from_rgb(167, 139, 250);
const MUTED: Color32 = Color32::from_rgb(161, 160, 171);
const GREEN: Color32 = Color32::from_rgb(95, 185, 141);
const PEACH: Color32 = Color32::from_rgb(234, 179, 138);
const DANGER: Color32 = Color32::from_rgb(226, 120, 106);
const BORDER: Color32 = Color32::from_rgb(49, 46, 63);
const ICON: &[u8] = include_bytes!("../../src-tauri/icons/icon.png");
const LOCAL_REFRESH: Duration = Duration::from_secs(10);
const MAX_EVENTS: usize = 1_000;

#[derive(Clone, Copy, Default, PartialEq, Serialize, Deserialize)]
enum Language {
    #[default]
    En,
    Cs,
}

#[derive(Default, Serialize, Deserialize)]
#[serde(default)]
struct Preferences {
    language: Language,
}

#[derive(Clone, Copy, Default, PartialEq)]
enum View {
    #[default]
    Overview,
    Characters,
    Runs,
    Atlas,
    Map,
    Database,
    Community,
    Sync,
    Settings,
}

impl View {
    const ALL: [Self; 9] = [
        Self::Overview,
        Self::Characters,
        Self::Runs,
        Self::Atlas,
        Self::Map,
        Self::Database,
        Self::Community,
        Self::Sync,
        Self::Settings,
    ];
    fn title(self, cs: bool) -> &'static str {
        match (self, cs) {
            (Self::Overview, false) => "Overview",
            (Self::Overview, true) => "Přehled",
            (Self::Characters, false) => "Characters",
            (Self::Characters, true) => "Postavy",
            (Self::Runs, false) => "Dungeon journal",
            (Self::Runs, true) => "Deník výprav",
            (Self::Atlas, false) => "Collected data",
            (Self::Atlas, true) => "Nasbíraná data",
            (Self::Map, false) => "World map",
            (Self::Map, true) => "Mapa světa",
            (Self::Database, false) => "Database & guides",
            (Self::Database, true) => "Databáze a návody",
            (Self::Community, false) => "Rankings & activity",
            (Self::Community, true) => "Žebříčky a aktivita",
            (Self::Sync, false) => "Web sync",
            (Self::Sync, true) => "Webová synchronizace",
            (Self::Settings, false) => "Settings",
            (Self::Settings, true) => "Nastavení",
        }
    }
}

struct Scan {
    accounts: Vec<AccountData>,
    dirs: Vec<PathBuf>,
    configured: Option<PathBuf>,
}

struct App {
    paths: Paths,
    config: Config,
    prefs: Preferences,
    view: View,
    accounts: Vec<AccountData>,
    dirs: Vec<PathBuf>,
    local_rx: Option<Receiver<Scan>>,
    last_scan: Option<Instant>,
    sync_rx: Receiver<UiState>,
    tx: Sender<Command>,
    state: UiState,
    logo: Option<egui::TextureHandle>,
    query: String,
    selected_account: String,
    run_filter: u8,
    server_edit: String,
    wow_edit: String,
    notice: Option<(String, bool)>,
    autostart: bool,
    screenshot: Option<PathBuf>,
    exit_after_screenshot: bool,
    offline_preview: bool,
    icons: identity::Icons,
    world_map: map::WorldMap,
    atlas_filter: u8,
    database: catalog::Database,
    community: community::Community,
}

impl App {
    fn new(
        cc: &eframe::CreationContext<'_>,
        paths: Paths,
        config: Config,
        startup_error: Option<String>,
    ) -> Self {
        if std::env::args().any(|arg| arg == "--wow-start") {
            cc.egui_ctx
                .send_viewport_cmd(egui::ViewportCommand::Minimized(true));
        }
        Self::new_context(&cc.egui_ctx, paths, config, startup_error, true)
    }

    /// Shared UI construction; the offline renderer never starts a worker,
    /// loads credentials, opens a browser or creates any OS window.
    fn new_context(
        ctx: &egui::Context,
        paths: Paths,
        config: Config,
        startup_error: Option<String>,
        start_worker: bool,
    ) -> Self {
        style(ctx);
        let mut prefs: Preferences = std::fs::read(paths.dir.join("desktop.json"))
            .ok()
            .and_then(|bytes| serde_json::from_slice(&bytes).ok())
            .unwrap_or_default();
        // Optional QA override does not change the user's saved preference.
        if let Some(language) = argument("--language") {
            match language.as_str() {
                "cs" => prefs.language = Language::Cs,
                "en" => prefs.language = Language::En,
                _ => {}
            }
        }
        let logo = image::load_from_memory(ICON).ok().map(|image| {
            let image = image.to_rgba8();
            ctx.load_texture(
                "evertally-logo",
                egui::ColorImage::from_rgba_unmultiplied(
                    [image.width() as usize, image.height() as usize],
                    image.as_raw(),
                ),
                egui::TextureOptions::LINEAR,
            )
        });
        let (tx, rx) = mpsc::channel();
        let (state_tx, sync_rx) = mpsc::channel();
        let publish_ctx = ctx.clone();
        let publish = Box::new(move |state| {
            let _ = state_tx.send(state);
            publish_ctx.request_repaint();
        });
        // Invalid local settings must not prevent the journal from opening.
        let origin = config
            .server_origin()
            .unwrap_or_else(|_| config::DEFAULT_SERVER.to_owned());
        if start_worker {
            let worker = Worker::new(
                if prefs.language == Language::Cs {
                    &lang::CS
                } else {
                    &lang::EN
                },
                paths.clone(),
                config.clone(),
                origin,
                publish,
                tx.clone(),
                false,
            );
            std::thread::spawn(move || worker.run(&rx));
        }
        let community = community::Community::new(paths.dir.join("community.json"));
        let mut app = Self {
            server_edit: config.server.clone(),
            wow_edit: config
                .wow_path
                .as_ref()
                .map(|p| p.display().to_string())
                .unwrap_or_default(),
            paths,
            config,
            prefs,
            view: View::Overview,
            accounts: vec![],
            dirs: vec![],
            local_rx: None,
            last_scan: None,
            sync_rx,
            tx,
            state: UiState {
                status: "Starting…".into(),
                tooltip: String::new(),
                paired: false,
                pairing_code: None,
                folders: vec![],
            },
            logo,
            query: String::new(),
            selected_account: String::new(),
            run_filter: 0,
            notice: startup_error.map(|e| (e, true)),
            autostart: platform::autostart_enabled(),
            screenshot: argument("--screenshot").map(PathBuf::from),
            exit_after_screenshot: std::env::args().any(|arg| arg == "--exit-after-screenshot"),
            offline_preview: !start_worker,
            icons: identity::Icons::default(),
            world_map: map::WorldMap::new(),
            atlas_filter: 0,
            database: catalog::Database::new(),
            community,
        };
        app.view = match argument("--view").as_deref() {
            Some("characters") => View::Characters,
            Some("runs") => View::Runs,
            Some("atlas") => View::Atlas,
            Some("map") => View::Map,
            Some("database") => View::Database,
            Some("community") => View::Community,
            Some("sync") => View::Sync,
            Some("settings") => View::Settings,
            _ => View::Overview,
        };
        if start_worker {
            app.refresh_local(ctx);
        } else {
            // A deterministic file snapshot for windowless previews. No queue,
            // file watcher or network worker is created in this branch.
            app.dirs =
                wow::saved_variables_dirs(&wow::candidate_roots(app.config.wow_path.as_deref()));
            app.accounts = local::read_accounts(&app.dirs, MAX_EVENTS);
            app.last_scan = Some(Instant::now());
            app.screenshot = None;
            app.exit_after_screenshot = false;
            app.state.status = "Offline preview · web synchronization is not running".into();
        }
        app
    }

    fn cs(&self) -> bool {
        self.prefs.language == Language::Cs
    }
    fn t<'a>(&self, en: &'a str, cs: &'a str) -> &'a str {
        if self.cs() { cs } else { en }
    }

    fn refresh_local(&mut self, ctx: &egui::Context) {
        if self.local_rx.is_some() {
            return;
        }
        let (tx, rx) = mpsc::channel();
        let configured = self.config.wow_path.clone();
        let ctx = ctx.clone();
        self.local_rx = Some(rx);
        std::thread::spawn(move || {
            let dirs = wow::saved_variables_dirs(&wow::candidate_roots(configured.as_deref()));
            let accounts = local::read_accounts(&dirs, MAX_EVENTS);
            let _ = tx.send(Scan {
                accounts,
                dirs,
                configured,
            });
            ctx.request_repaint();
        });
    }

    fn tick(&mut self, ctx: &egui::Context) {
        if self.offline_preview {
            return;
        }
        while let Ok(state) = self.sync_rx.try_recv() {
            self.state = state;
        }
        let scan = self.local_rx.as_ref().and_then(|rx| rx.try_recv().ok());
        if let Some(scan) = scan {
            self.local_rx = None;
            if scan.configured == self.config.wow_path {
                model::merge_accounts(&mut self.accounts, scan.accounts);
                self.dirs = scan.dirs;
                self.last_scan = Some(Instant::now());
            } else {
                self.last_scan = None;
            }
        }
        if self.local_rx.is_none()
            && self
                .last_scan
                .is_none_or(|last| last.elapsed() >= LOCAL_REFRESH)
        {
            self.refresh_local(ctx);
        }
        ctx.request_repaint_after(Duration::from_millis(500));
    }

    fn filtered_accounts(&self) -> impl Iterator<Item = &AccountData> {
        self.accounts
            .iter()
            .filter(|a| self.selected_account.is_empty() || account_key(a) == self.selected_account)
    }

    fn characters(&self) -> Vec<(&AccountData, &Value)> {
        let mut rows: Vec<_> = self
            .filtered_accounts()
            .flat_map(|a| a.characters.iter().map(move |c| (a, c)))
            .collect();
        rows.sort_by(|a, b| {
            b.1["lastSeen"]
                .as_f64()
                .unwrap_or(0.0)
                .total_cmp(&a.1["lastSeen"].as_f64().unwrap_or(0.0))
        });
        rows
    }

    fn runs(&self) -> Vec<(&AccountData, &Value)> {
        let mut rows: Vec<_> = self
            .filtered_accounts()
            .flat_map(|a| a.runs.iter().map(move |r| (a, r)))
            .collect();
        rows.sort_by(|a, b| {
            b.1["startedAt"]
                .as_f64()
                .unwrap_or(0.0)
                .total_cmp(&a.1["startedAt"].as_f64().unwrap_or(0.0))
        });
        rows
    }

    fn events(&self) -> Vec<(&AccountData, &Value)> {
        let mut rows: Vec<_> = self
            .filtered_accounts()
            .flat_map(|a| a.events.iter().map(move |e| (a, e)))
            .collect();
        rows.sort_by(|a, b| {
            b.1["observedAt"]
                .as_f64()
                .unwrap_or(0.0)
                .total_cmp(&a.1["observedAt"].as_f64().unwrap_or(0.0))
        });
        rows
    }

    fn nav(&mut self, ui: &mut egui::Ui) {
        ui.add_space(10.0);
        ui.horizontal(|ui| {
            if let Some(logo) = &self.logo {
                ui.image((logo.id(), Vec2::splat(37.0)));
            }
            ui.label(RichText::new("Evertally").size(24.0).strong());
        });
        ui.add_space(3.0);
        ui.label(
            RichText::new("WORLD OF WARCRAFT COMPANION")
                .size(9.0)
                .color(MUTED)
                .extra_letter_spacing(1.1),
        );
        ui.add_space(34.0);
        ui.label(
            RichText::new(self.t("JOURNAL", "DENÍK"))
                .size(10.0)
                .color(MUTED)
                .extra_letter_spacing(1.5),
        );
        ui.add_space(10.0);
        for view in View::ALL {
            if view == View::Sync {
                ui.add_space(24.0);
            }
            let selected = self.view == view;
            let (rect, response) =
                ui.allocate_exact_size(Vec2::new(ui.available_width(), 43.0), egui::Sense::click());
            if selected || response.hovered() {
                ui.painter().rect_filled(
                    rect,
                    8.0,
                    if selected {
                        Color32::from_rgb(45, 35, 65)
                    } else {
                        PANEL
                    },
                );
            }
            nav_icon(
                ui.painter(),
                rect.min + Vec2::new(21.0, 21.0),
                view,
                if selected { VIOLET } else { MUTED },
            );
            ui.painter().text(
                rect.min + Vec2::new(43.0, 21.5),
                egui::Align2::LEFT_CENTER,
                view.title(self.cs()),
                egui::FontId::proportional(14.0),
                if selected { Color32::WHITE } else { MUTED },
            );
            if response.clicked() {
                self.view = view;
                self.query.clear();
            }
            response.widget_info(|| {
                egui::WidgetInfo::selected(
                    egui::Role::Button,
                    true,
                    selected,
                    view.title(self.cs()),
                )
            });
            response.on_hover_text(view.title(self.cs()));
            ui.add_space(3.0);
        }
        ui.add_space(24.0);
        card(PANEL).show(ui, |ui| {
            ui.horizontal(|ui| {
                dot(ui, GREEN);
                ui.label(
                    RichText::new(self.t("Local journal", "Místní deník"))
                        .strong()
                        .size(13.0),
                );
            });
            ui.label(
                RichText::new(self.t("Always here. Even offline.", "Dostupný i bez internetu."))
                    .size(11.0)
                    .color(MUTED),
            );
            ui.add_space(7.0);
            ui.label(
                RichText::new(self.t("Web sharing is optional.", "Sdílení na web je volitelné."))
                    .size(11.0)
                    .color(MUTED),
            );
        });
        ui.add_space(18.0);
        ui.horizontal(|ui| {
            for (language, label) in [(Language::En, "EN"), (Language::Cs, "CS")] {
                if ui
                    .selectable_label(self.prefs.language == language, label)
                    .clicked()
                {
                    self.prefs.language = language;
                    if let Ok(bytes) = serde_json::to_vec_pretty(&self.prefs) {
                        let _ = std::fs::write(self.paths.dir.join("desktop.json"), bytes);
                    }
                }
            }
            ui.label(
                RichText::new(format!("v{}", env!("CARGO_PKG_VERSION")))
                    .size(10.0)
                    .color(MUTED),
            );
        });
    }

    fn heading(&mut self, ui: &mut egui::Ui) {
        ui.horizontal(|ui| {
            ui.vertical(|ui| {
                ui.label(
                    RichText::new(self.t("EVERTALLY / DESKTOP", "EVERTALLY / APLIKACE"))
                        .size(10.0)
                        .color(VIOLET)
                        .extra_letter_spacing(1.3),
                );
                ui.add_space(7.0);
                ui.label(RichText::new(self.view.title(self.cs())).size(31.0));
            });
            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                if ui
                    .add_enabled(
                        self.local_rx.is_none(),
                        egui::Button::new(self.t("Refresh files", "Načíst soubory")),
                    )
                    .clicked()
                {
                    self.refresh_local(ui.ctx());
                }
            });
        });
        ui.add_space(14.0);
        ui.horizontal(|ui| {
            let selected_label = self
                .accounts
                .iter()
                .find(|a| account_key(a) == self.selected_account)
                .map(|a| format!("{} · {}", a.flavor, a.account))
                .unwrap_or_else(|| self.t("All local accounts", "Všechny místní účty").into());
            egui::ComboBox::from_id_salt("account")
                .selected_text(selected_label)
                .width(230.0)
                .show_ui(ui, |ui| {
                    let all = self.t("All local accounts", "Všechny místní účty");
                    ui.selectable_value(&mut self.selected_account, String::new(), all);
                    for account in &self.accounts {
                        ui.selectable_value(
                            &mut self.selected_account,
                            account_key(account),
                            format!("{} · {}", account.flavor, account.account),
                        );
                    }
                });
            ui.add_space(7.0);
            ui.label(
                RichText::new(if self.local_rx.is_some() {
                    self.t("Reading local files…", "Načítám místní soubory…")
                } else {
                    self.t("Saved on this PC", "Uloženo v tomto počítači")
                })
                .size(12.0)
                .color(MUTED),
            );
        });
        if let Some((text, error)) = &self.notice {
            ui.add_space(10.0);
            ui.colored_label(if *error { DANGER } else { GREEN }, text);
        }
        for account in self.filtered_accounts().filter(|a| a.error.is_some()) {
            ui.add_space(6.0);
            ui.colored_label(
                PEACH,
                format!(
                    "{}: {}",
                    account.account,
                    self.t(
                        "File unreadable. Retaining the last good snapshot if available.",
                        "Soubor nelze přečíst. Pokud je dostupný, zůstává poslední správný snímek."
                    )
                ),
            )
            .on_hover_text(account.error.as_deref().unwrap_or_default());
        }
        ui.add_space(23.0);
    }

    fn overview(&self, ui: &mut egui::Ui) {
        let character_count = self.characters().len();
        let run_count: usize = self.filtered_accounts().map(|a| a.run_count).sum();
        let event_count: usize = self.filtered_accounts().map(|a| a.event_count).sum();
        let peers: usize = self.filtered_accounts().map(|a| a.peers).sum();
        ui.columns(4, |cols| {
            for (col, (value, label, color)) in cols.iter_mut().zip([
                (character_count, self.t("CHARACTERS", "POSTAVY"), VIOLET),
                (
                    run_count,
                    self.t("RETAINED VISITS", "ULOŽENÉ NÁVŠTĚVY"),
                    PEACH,
                ),
                (
                    event_count,
                    self.t("RETAINED EVENTS", "ULOŽENÉ UDÁLOSTI"),
                    GREEN,
                ),
                (peers, self.t("IN-GAME PEERS", "HRÁČI VE HŘE"), MUTED),
            ]) {
                metric(col, value, label, color);
            }
        });
        ui.add_space(25.0);
        section(
            ui,
            self.t("Latest characters", "Poslední postavy"),
            self.t(
                "From your own saved snapshots",
                "Z vlastních uložených snímků",
            ),
        );
        let characters = self.characters();
        if characters.is_empty() {
            self.empty(ui);
        } else {
            for (account, character) in characters.into_iter().take(3) {
                self.character_row(ui, account, character);
            }
        }
        ui.add_space(23.0);
        section(
            ui,
            self.t("Recent dungeon visits", "Poslední návštěvy dungeonů"),
            self.t(
                "An observed visit is not proof of a full clear.",
                "Zaznamenaná návštěva nedokazuje dokončení celého dungeonu.",
            ),
        );
        let runs = self.runs();
        if runs.is_empty() {
            hint(
                ui,
                self.t(
                    "No saved visits yet. The addon records them while you play.",
                    "Zatím žádné uložené návštěvy. Addon je zaznamenává při hraní.",
                ),
            );
        }
        for (account, run) in runs.into_iter().take(4) {
            self.run_row(ui, account, run, false);
        }
        ui.add_space(18.0);
        hint(ui,self.t("WoW saves addon data on /reload or logout. This app reads those files every 10 seconds.","WoW ukládá data addonu při /reload nebo odhlášení. Aplikace je čte každých 10 sekund."));
    }

    fn character_row(&self, ui: &mut egui::Ui, account: &AccountData, character: &Value) {
        card(PANEL).show(ui, |ui| {
            ui.horizontal(|ui| {
                let color = class_color(character["classId"].as_u64());
                let class = model::class_name(character["classId"].as_u64());
                self.icons
                    .show(ui, "classes", character["classId"].as_u64(), 40.0, class);
                self.icons.show(
                    ui,
                    "races",
                    character["raceId"].as_u64(),
                    34.0,
                    model::race_name(character["raceId"].as_u64()),
                );
                ui.add_space(5.0);
                ui.vertical(|ui| {
                    ui.label(
                        RichText::new(model::text(character, "name"))
                            .size(16.0)
                            .strong()
                            .color(color),
                    );
                    ui.label(
                        RichText::new(format!(
                            "{} · {} · {}",
                            model::text(character, "realm"),
                            class,
                            model::race_name(character["raceId"].as_u64())
                        ))
                        .size(12.0)
                        .color(MUTED),
                    );
                });
                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    ui.label(
                        RichText::new(format!("Lv. {}", model::number(character, "level")))
                            .size(20.0)
                            .color(VIOLET),
                    );
                    ui.label(RichText::new(&account.flavor).size(11.0).color(MUTED));
                });
            });
        });
        ui.add_space(6.0);
    }

    fn characters_view(&self, ui: &mut egui::Ui) {
        let rows: Vec<_> = self
            .characters()
            .into_iter()
            .filter(|(_, c)| model::matches(c, &self.query))
            .collect();
        hint(ui,self.t("Character details reflect the latest snapshot retained by your addon, not a live armory.","Údaje postavy odpovídají poslednímu snímku uloženému addonem, nikoli živému armory."));
        ui.add_space(15.0);
        if rows.is_empty() {
            self.empty(ui);
        }
        for (account, character) in rows {
            self.character_row(ui, account, character);
            ui.indent((account_key(account), model::text(character, "id")), |ui| {
                ui.label(
                    RichText::new(format!(
                        "{} · {} · {} UTC",
                        account.account,
                        model::text(character, "id"),
                        model::timestamp(character["lastSeen"].as_f64()).trim_end_matches('Z')
                    ))
                    .size(11.0)
                    .color(MUTED),
                );
                let visits = model::visited_zones(&[account], character["id"].as_str());
                if !visits.is_empty() {
                    egui::CollapsingHeader::new(self.t("Visited zones", "Navštívené zóny"))
                        .id_salt(("visits", account_key(account), model::text(character, "id")))
                        .show(ui, |ui| {
                            for visit in visits {
                                ui.label(format!(
                                    "{} · {} {}",
                                    visit.name,
                                    visit.count,
                                    self.t("visits", "návštěv")
                                ));
                            }
                            ui.weak(self.t(
                                "Zone history only. Exact player positions are not displayed.",
                                "Pouze historie zón. Přesné pozice hráče se nezobrazují.",
                            ));
                        });
                }
            });
            ui.add_space(12.0);
        }
    }

    fn run_row(&self, ui: &mut egui::Ui, account: &AccountData, run: &Value, details: bool) {
        let status = model::text(run, "status");
        let (label, color) = match status {
            "completed" => (
                self.t("Last boss observed", "Zaznamenán poslední boss"),
                GREEN,
            ),
            "interrupted" => (self.t("Interrupted", "Přerušeno"), PEACH),
            "manual" => (self.t("Manually ended", "Ručně ukončeno"), MUTED),
            _ => (status, MUTED),
        };
        card(PANEL).show(ui,|ui| {
            ui.horizontal(|ui| {
                self.icons.show(ui,"classes",run["character"]["classId"].as_u64(),32.0,model::class_name(run["character"]["classId"].as_u64()));
                self.icons.show(ui,"races",run["character"]["raceId"].as_u64(),28.0,model::race_name(run["character"]["raceId"].as_u64()));
                ui.vertical(|ui| {
                    ui.label(RichText::new(model::text(run,"name")).size(17.0).strong());
                    ui.label(RichText::new(format!("{} · {} · {}",model::text(&run["character"],"name"),model::text(run,"instanceType"),model::timestamp(run["startedAt"].as_f64()))).size(11.0).color(MUTED));
                });
                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center),|ui| {
                    ui.label(RichText::new(model::duration(run["durationMs"].as_u64())).size(24.0).monospace().color(VIOLET));
                });
            });
            ui.add_space(7.0);
            ui.horizontal_wrapped(|ui| {
                ui.colored_label(color,label);
                ui.label(RichText::new(format!("· {} {} · {} {} · {} {}", model::number(run,"bossCount"),self.t("bosses","bossů"),model::number(run,"groupSize"),self.t("players","hráčů"),model::number(run,"deaths"),self.t("deaths","úmrtí"))).size(12.0).color(MUTED));
            });
            if details {
                egui::CollapsingHeader::new(self.t("Run details","Podrobnosti výpravy")).id_salt((account_key(account),model::text(run,"runId"))).show(ui,|ui| {
                    ui.label(RichText::new(self.t("Unranked observation. Timing cannot certify a complete or competitive clear.","Nesoutěžní pozorování. Čas nepotvrzuje kompletní ani soutěžní průchod.")).size(12.0).color(PEACH));
                    ui.label(format!("{}: {} · {}: {}",self.t("Instance","Instance"),model::number(run,"instanceId"),self.t("Difficulty","Obtížnost"),model::number(run,"difficultyId")));
                    ui.label(format!("{}: {} · {}: {}",self.t("Account","Účet"),account.account,self.t("Completion","Dokončení"),model::text(run,"completion")));
                    if let Some(bosses) = run["bosses"].as_array() {
                        for boss in bosses { ui.label(format!("• {} · {}",model::text(boss,"name"),model::timestamp(boss["killedAt"].as_f64()))); }
                    }
                    json_details(ui,run,self.cs());
                });
            }
        });
        ui.add_space(8.0);
    }

    fn runs_view(&mut self, ui: &mut egui::Ui) {
        ui.horizontal_wrapped(|ui| {
            for (filter, label) in [
                (0, self.t("All visits", "Všechny návštěvy")),
                (1, self.t("Last boss observed", "Poslední boss")),
                (2, self.t("Interrupted", "Přerušené")),
                (3, self.t("Manually ended", "Ručně ukončené")),
            ] {
                ui.selectable_value(&mut self.run_filter, filter, label);
            }
        });
        ui.add_space(12.0);
        hint(ui,self.t("Retained journal, newest first. Up to 300 latest visits per local account are displayed. Times are addon observations; leaderboards require separate verified rules.","Uložený deník od nejnovějších. Zobrazuje se až 300 posledních návštěv na místní účet. Časy jsou pozorování addonu; žebříčky vyžadují samostatná ověřená pravidla."));
        ui.add_space(14.0);
        let rows: Vec<_> = self
            .runs()
            .into_iter()
            .filter(|(_, r)| {
                model::matches(r, &self.query)
                    && match self.run_filter {
                        1 => r["status"] == "completed",
                        2 => r["status"] == "interrupted",
                        3 => r["status"] == "manual",
                        _ => true,
                    }
            })
            .collect();
        if rows.is_empty() {
            hint(
                ui,
                self.t(
                    "No saved runs match this filter.",
                    "Tomuto filtru neodpovídají žádné uložené výpravy.",
                ),
            );
        }
        for (account, run) in rows {
            self.run_row(ui, account, run, true);
        }
    }

    fn atlas(&mut self, ui: &mut egui::Ui) {
        ui.horizontal_wrapped(|ui| {
            for (filter, en, cs) in [
                (0, "All records", "Všechny záznamy"),
                (1, "Quests", "Questy"),
                (2, "NPC / vendors", "NPC / obchodníci"),
                (3, "Items / loot", "Itemy / kořist"),
                (4, "Professions", "Profese"),
            ] {
                let label = self.t(en, cs);
                ui.selectable_value(&mut self.atlas_filter, filter, label);
            }
        });
        ui.add_space(12.0);
        let events = self.events();
        let categories = [
            ("quest.", self.t("QUEST EVENTS", "ÚKOLY")),
            ("npc.", self.t("NPC OBSERVATIONS", "POZOROVÁNÍ NPC")),
            ("loot.", self.t("LOOT EVENTS", "KOŘIST")),
            ("profession.", self.t("PROFESSIONS", "PROFESE")),
        ];
        ui.columns(4, |cols| {
            for (col, (prefix, label)) in cols.iter_mut().zip(categories) {
                metric(
                    col,
                    events
                        .iter()
                        .filter(|(_, e)| model::text(e, "kind").starts_with(prefix))
                        .count(),
                    label,
                    VIOLET,
                );
            }
        });
        ui.add_space(15.0);
        hint(ui,self.t("Counts below cover only the latest 1,000 retained events per account. This is your local sample, not a complete database of the realm.","Počty zde zahrnují pouze posledních 1 000 uložených událostí na účet. Jde o tvůj místní vzorek, nikoli úplnou databázi realmu."));
        ui.add_space(20.0);
        section(
            ui,
            self.t("Observed in your world", "Pozorováno ve tvém světě"),
            self.t(
                "Latest 300 matching events · UTC timestamps",
                "Posledních 300 odpovídajících událostí · čas v UTC",
            ),
        );
        let rows: Vec<_> = events
            .into_iter()
            .filter(|(_, e)| {
                let kind = model::text(e, "kind");
                model::matches(e, &self.query)
                    && match self.atlas_filter {
                        1 => kind.starts_with("quest."),
                        2 => kind.starts_with("npc.") || kind.starts_with("vendor."),
                        3 => kind.starts_with("loot."),
                        4 => {
                            kind.starts_with("profession.")
                                || kind.starts_with("craft.")
                                || kind.starts_with("cooldown.")
                        }
                        _ => true,
                    }
            })
            .take(300)
            .collect();
        if rows.is_empty() {
            self.empty(ui);
        }
        for (account, event) in rows {
            card(PANEL)
                .inner_margin(egui::Margin::same(12))
                .show(ui, |ui| {
                    ui.set_min_width(ui.available_width());
                    let kind = model::text(event, "kind");
                    let payload = &event["payload"];
                    ui.horizontal(|ui| {
                        if let Some(item) = payload["itemId"].as_u64() {
                            self.icons.show(
                                ui,
                                "items",
                                Some(item),
                                35.0,
                                self.t("Item icon", "Ikona itemu"),
                            );
                        }
                        ui.vertical(|ui| {
                            let name = payload["name"]
                                .as_str()
                                .or_else(|| payload["title"].as_str())
                                .or_else(|| payload["mapName"].as_str())
                                .or_else(|| payload["itemName"].as_str());
                            if let Some(name) = name {
                                ui.label(RichText::new(name).size(16.0).strong());
                            }
                            ui.label(RichText::new(event_label(kind, self.cs())).color(VIOLET));
                        });
                        if let Some(quantity) = payload["quantity"].as_u64() {
                            ui.label(format!("× {quantity}"));
                        }
                    });
                    egui::CollapsingHeader::new(
                        RichText::new(self.t("Saved details", "Uložené podrobnosti")).color(MUTED),
                    )
                    .id_salt((account_key(account), model::text(event, "eventId")))
                    .show(ui, |ui| {
                        ui.label(RichText::new(kind).monospace().size(11.0).color(MUTED));
                        if let Some(map_id) = payload["mapId"].as_u64() {
                            ui.label(format!("{}: #{}", self.t("Zone", "Zóna"), map_id));
                        }
                        for (key, en, cs) in [
                            ("npcId", "NPC ID", "NPC ID"),
                            ("questId", "Quest ID", "ID questu"),
                            ("itemId", "Item ID", "ID itemu"),
                            ("skill", "Skill", "Dovednost"),
                            ("maxSkill", "Maximum skill", "Maximum dovednosti"),
                        ] {
                            if let Some(value) = payload.get(key).filter(|v| !v.is_null()) {
                                ui.label(format!("{}: {value}", self.t(en, cs)));
                            }
                        }
                        if let Some(recipes) = payload["recipes"].as_array() {
                            ui.label(format!(
                                "{}: {}",
                                self.t("Recorded recipes", "Zaznamenané recepty"),
                                recipes.len()
                            ));
                            for recipe in recipes.iter().take(200) {
                                ui.horizontal(|ui| {
                                    ui.label(recipe["name"].as_str().unwrap_or("—"));
                                    ui.weak(format!("#{}", model::number(recipe, "recipeId")));
                                    if let Some(learned) = recipe["learned"].as_bool() {
                                        ui.weak(if learned {
                                            self.t("Learned", "Naučeno")
                                        } else {
                                            self.t("Not learned", "Nenaučeno")
                                        });
                                    }
                                });
                            }
                        }
                        if let Some(items) = payload["items"].as_array() {
                            ui.label(format!(
                                "{}: {}",
                                self.t("Vendor items", "Zboží obchodníka"),
                                items.len()
                            ));
                            for item in items.iter().take(100) {
                                ui.horizontal(|ui| {
                                    self.icons.show(
                                        ui,
                                        "items",
                                        item["itemId"].as_u64(),
                                        26.0,
                                        item["name"].as_str().unwrap_or("Item"),
                                    );
                                    ui.label(item["name"].as_str().unwrap_or("—"));
                                    if let Some(price) = item["price"].as_u64() {
                                        ui.weak(format!(
                                            "{}g {}s {}c",
                                            price / 10000,
                                            price / 100 % 100,
                                            price % 100
                                        ));
                                    }
                                    if let Some(stock) = item["quantity"].as_i64() {
                                        ui.weak(if stock < 0 {
                                            self.t("Unlimited", "Neomezeně").to_owned()
                                        } else {
                                            format!("× {stock}")
                                        });
                                    }
                                });
                            }
                        }
                        if let Some(ready) = payload["readyAt"].as_f64() {
                            let now = std::time::SystemTime::now()
                                .duration_since(std::time::UNIX_EPOCH)
                                .unwrap_or_default()
                                .as_secs_f64();
                            let remaining = (ready - now).max(0.0);
                            ui.label(format!(
                                "{}: {}",
                                self.t(
                                    "Cooldown from saved snapshot",
                                    "Cooldown z uloženého snímku"
                                ),
                                if remaining == 0.0 {
                                    self.t("Ready", "Připraveno").to_owned()
                                } else {
                                    model::duration(Some((remaining * 1000.0) as u64))
                                }
                            ));
                        }
                        egui::CollapsingHeader::new(self.t("Raw fields", "Datová pole"))
                            .show(ui, |ui| json_details(ui, payload, self.cs()));
                    });
                    ui.label(
                        RichText::new(format!(
                            "{} · {} · {}",
                            model::text(&event["character"], "name"),
                            model::timestamp(event["observedAt"].as_f64()),
                            account.flavor
                        ))
                        .size(11.0)
                        .color(MUTED),
                    );
                });
            ui.add_space(5.0);
        }
    }

    fn map_view(&mut self, ui: &mut egui::Ui) {
        let cs = self.cs();
        let selected = &self.selected_account;
        let accounts: Vec<_> = self
            .accounts
            .iter()
            .filter(|a| selected.is_empty() || account_key(a) == *selected)
            .collect();
        self.world_map.show(ui, &accounts, cs);
    }

    fn sync(&mut self, ui: &mut egui::Ui) {
        card(NAVY).inner_margin(egui::Margin::same(22)).show(ui,|ui| {
            ui.horizontal(|ui| { dot(ui,if self.state.paired {GREEN} else {MUTED}); ui.label(RichText::new(if self.state.paired {self.t("This PC is paired","Tento počítač je spárovaný")} else {self.t("Your journal stays local","Tvůj deník zůstává místní")}).size(23.0)); });
            ui.add_space(12.0);
            ui.label(&self.state.status);
            ui.add_space(12.0);
            ui.label(RichText::new(self.t("Pairing is optional. Local characters and history work without an account. Uploads use only Evertally_Export.lua after you opt in inside WoW.","Párování je volitelné. Místní postavy a historie fungují bez účtu. Odesílá se pouze Evertally_Export.lua po zapnutí exportu ve WoW.")).color(MUTED));
            ui.add_space(17.0);
            ui.horizontal_wrapped(|ui| {
                if self.state.paired {
                    if primary(ui,self.t("Sync now","Synchronizovat teď")).clicked() { let _ = self.tx.send(Command::SyncNow); }
                    if ui.button(self.t("Disconnect this PC","Odpojit tento počítač")).clicked() { let _ = self.tx.send(Command::Unpair); }
                } else if self.state.pairing_code.is_none()
                    && primary(ui,self.t("Pair this PC","Spárovat tento počítač")).clicked() { let _ = self.tx.send(Command::Pair); }
                if ui.button(self.t("Open website","Otevřít web")).clicked() { self.open_url(self.config.server_origin()); }
            });
        });
        if let Some(code) = self.state.pairing_code.clone() {
            ui.add_space(18.0);
            card(PANEL).show(ui, |ui| {
                ui.label(self.t(
                    "Approve this code on the Evertally website:",
                    "Potvrď tento kód na webu Evertally:",
                ));
                ui.add_space(9.0);
                ui.label(RichText::new(&code).monospace().size(36.0).color(VIOLET));
                ui.add_space(12.0);
                ui.horizontal_wrapped(|ui| {
                    if primary(ui, self.t("Open pairing page", "Otevřít stránku párování"))
                        .clicked()
                    {
                        self.open_url(
                            self.config
                                .server_origin()
                                .map(|origin| format!("{origin}/link?code={code}")),
                        );
                    }
                    if ui.button(self.t("Copy code", "Zkopírovat kód")).clicked() {
                        ui.ctx().copy_text(code.clone());
                    }
                    if ui.button(self.t("Cancel", "Zrušit")).clicked() {
                        let _ = self.tx.send(Command::CancelPair);
                    }
                });
            });
        }
        ui.add_space(24.0);
        section(
            ui,
            self.t("Export permissions", "Oprávnění exportu"),
            self.t(
                "These switches are controlled in game.",
                "Tyto volby se nastavují ve hře.",
            ),
        );
        if self.accounts.is_empty() {
            hint(
                ui,
                self.t(
                    "No addon data found yet.",
                    "Zatím nebyla nalezena data addonu.",
                ),
            );
        }
        for account in &self.accounts {
            card(PANEL).show(ui, |ui| {
                ui.label(
                    RichText::new(format!("{} · {}", account.flavor, account.account)).strong(),
                );
                ui.horizontal_wrapped(|ui| {
                    ui.colored_label(
                        if account.web_enabled { GREEN } else { MUTED },
                        format!(
                            "{}: {}",
                            self.t("Web export", "Webový export"),
                            self.t(
                                if account.web_enabled { "ON" } else { "OFF" },
                                if account.web_enabled {
                                    "ZAPNUTO"
                                } else {
                                    "VYPNUTO"
                                }
                            )
                        ),
                    );
                    ui.label(RichText::new("  /etally web on").monospace().color(VIOLET));
                });
                ui.label(
                    RichText::new(format!(
                        "{}: {}",
                        self.t("In-game sharing", "Sdílení ve hře"),
                        if account.sharing_enabled {
                            self.t("ON", "ZAPNUTO")
                        } else {
                            self.t("OFF", "VYPNUTO")
                        }
                    ))
                    .color(MUTED),
                );
            });
            ui.add_space(7.0);
        }
        ui.add_space(17.0);
        hint(ui,self.t("After changing consent, type /reload or log out so WoW writes the export. Disconnecting this PC removes its local token; existing web data is managed on the website.","Po změně souhlasu napiš /reload nebo se odhlas, aby WoW uložilo export. Odpojení počítače odstraní místní token; existující webová data se spravují na webu."));
        ui.add_space(18.0);
        ui.label(
            RichText::new(format!(
                "{}: {}",
                self.t("Server", "Server"),
                self.config.server
            ))
            .size(12.0)
            .color(MUTED),
        );
    }

    fn settings(&mut self, ui: &mut egui::Ui) {
        card(PANEL).inner_margin(egui::Margin::same(22)).show(ui,|ui| {
            section(ui,self.t("Your installation","Tvoje instalace"),self.t("Automatic discovery runs across standard WoW locations.","Automatické hledání prochází obvyklá umístění WoW."));
            ui.label(self.t("World of Warcraft folder (optional override)","Složka World of Warcraft (volitelné ruční nastavení)"));
            ui.add(egui::TextEdit::singleline(&mut self.wow_edit).desired_width(f32::INFINITY).hint_text(r"D:\World of Warcraft"));
            ui.add_space(17.0);
            ui.label(self.t("Evertally server URL","Adresa serveru Evertally"));
            ui.add(egui::TextEdit::singleline(&mut self.server_edit).desired_width(f32::INFINITY).hint_text("https://…"));
            ui.label(RichText::new(self.t("HTTPS required. Localhost is allowed for development. No public server is bundled with the app.","Vyžadováno HTTPS. Localhost je povolen pro vývoj. Aplikace neobsahuje veřejný server.")).size(12.0).color(MUTED));
            ui.add_space(18.0);
            if primary(ui,self.t("Save & apply","Uložit a použít")).clicked() { self.save_settings(ui.ctx()); }
        });
        ui.add_space(18.0);
        card(PANEL).show(ui, |ui| {
            let label = self.t(
                "Start with World of Warcraft",
                "Spouštět s World of Warcraft",
            );
            if ui.checkbox(&mut self.autostart, label).changed()
                && let Err(error) = platform::set_autostart(self.autostart)
            {
                self.autostart = platform::autostart_enabled();
                self.notice = Some((error.to_string(), true));
            }
            ui.label(
                RichText::new(self.t(
                    "Closing the window quits this app and its sync worker.",
                    "Zavření okna ukončí aplikaci i její synchronizaci.",
                ))
                .size(12.0)
                .color(MUTED),
            );
            ui.add_space(12.0);
            if ui
                .button(self.t("Open settings & log folder", "Otevřít nastavení a protokol"))
                .clicked()
                && let Err(error) = open::that(&self.paths.dir)
            {
                self.notice = Some((error.to_string(), true));
            }
        });
        ui.add_space(24.0);
        section(
            ui,
            self.t("Detected account folders", "Nalezené složky účtů"),
            self.t(
                "Read-only access to addon files.",
                "Soubory addonu se pouze čtou.",
            ),
        );
        if self.dirs.is_empty() {
            hint(
                ui,
                self.t(
                    "No SavedVariables folders found. Set the WoW folder above, then save.",
                    "Nebyly nalezeny složky SavedVariables. Nastav složku WoW výše a ulož ji.",
                ),
            );
        }
        for dir in &self.dirs {
            ui.label(
                RichText::new(dir.display().to_string())
                    .monospace()
                    .size(11.0)
                    .color(MUTED),
            );
        }
        ui.add_space(18.0);
        hint(ui,self.t("The desktop journal reads Evertally.lua only for local display. Web sync reads the separate consent-filtered Evertally_Export.lua. No game memory, passwords or unrelated SavedVariables are read.","Místní deník čte Evertally.lua pouze pro zobrazení v aplikaci. Synchronizace čte samostatný export Evertally_Export.lua omezený souhlasem. Paměť hry, hesla ani nesouvisející SavedVariables se nečtou."));
    }

    fn save_settings(&mut self, ctx: &egui::Context) {
        let next = Config {
            server: self.server_edit.trim().to_owned(),
            wow_path: (!self.wow_edit.trim().is_empty())
                .then(|| PathBuf::from(self.wow_edit.trim())),
        };
        let validation = next.server_origin().map(|_| ()).and_then(|()| {
            if let Some(path) = &next.wow_path
                && !path.is_dir()
            {
                return Err(std::io::Error::new(
                    std::io::ErrorKind::NotFound,
                    self.t("WoW folder does not exist.", "Složka WoW neexistuje."),
                )
                .into());
            }
            Ok(())
        });
        if let Err(error) = validation {
            self.notice = Some((error.to_string(), true));
            return;
        }
        let saved = serde_json::to_vec_pretty(&next)
            .map_err(|e| e.to_string())
            .and_then(|bytes| {
                let temp = self.paths.config.with_extension("json.tmp");
                std::fs::write(&temp, bytes)
                    .and_then(|()| std::fs::rename(&temp, &self.paths.config))
                    .map_err(|e| e.to_string())
            });
        if let Err(error) = saved {
            self.notice = Some((error, true));
            return;
        }
        if self.config.wow_path != next.wow_path {
            self.accounts.clear();
            self.dirs.clear();
        }
        self.config = next.clone();
        let _ = self.tx.send(Command::ReloadConfig(next));
        self.last_scan = None;
        self.refresh_local(ctx);
        self.notice = Some((
            self.t(
                "Settings saved. Local folders refreshed.",
                "Nastavení uloženo. Místní složky se načítají znovu.",
            )
            .into(),
            false,
        ));
    }

    fn open_url(&mut self, url: Result<String, impl std::fmt::Display>) {
        match url {
            Ok(url) => {
                if let Err(error) = open::that(url) {
                    self.notice = Some((error.to_string(), true));
                }
            }
            Err(error) => self.notice = Some((error.to_string(), true)),
        }
    }

    fn empty(&self, ui: &mut egui::Ui) {
        card(PANEL).inner_margin(egui::Margin::same(24)).show(ui,|ui| {
            ui.label(RichText::new(self.t("Your journal starts in game.","Tvůj deník začíná ve hře.")).size(22.0).color(VIOLET));
            ui.add_space(10.0);
            ui.label(self.t("Enable Evertally in WoW, play, then type /reload or log out. Your saved characters and events will appear here automatically.","Zapni Evertally ve WoW, hraj a poté napiš /reload nebo se odhlas. Uložené postavy a události se zde objeví automaticky."));
            ui.add_space(10.0);
            ui.label(RichText::new(self.t("Already have data? Check your account filter and WoW folder in Settings.","Data už máš? Zkontroluj filtr účtu a složku WoW v Nastavení.")).color(MUTED).size(12.0));
        });
    }
}

impl App {
    fn render_ui(&mut self, ui: &mut egui::Ui) {
        self.tick(ui.ctx());
        egui::Panel::left("navigation")
            .resizable(false)
            .exact_size(228.0)
            .frame(
                egui::Frame::new()
                    .fill(Color32::from_rgb(16, 14, 24))
                    .inner_margin(egui::Margin::same(18)),
            )
            .show(ui, |ui| {
                egui::ScrollArea::vertical()
                    .id_salt("nav-scroll")
                    .show(ui, |ui| self.nav(ui));
            });
        egui::Panel::bottom("footer")
            .resizable(false)
            .frame(
                egui::Frame::new()
                    .fill(CANVAS)
                    .inner_margin(egui::Margin::symmetric(26, 10)),
            )
            .show(ui, |ui| {
                ui.horizontal(|ui| {
                    dot(
                        ui,
                        if self.local_rx.is_some() {
                            VIOLET
                        } else {
                            GREEN
                        },
                    );
                    ui.label(
                        RichText::new(self.t("LOCAL FILES", "MÍSTNÍ SOUBORY"))
                            .size(10.0)
                            .color(MUTED),
                    );
                    let count = self.accounts.len();
                    let noun = if self.cs() {
                        match count {
                            1 => "účet",
                            2..=4 => "účty",
                            _ => "účtů",
                        }
                    } else if count == 1 {
                        "account"
                    } else {
                        "accounts"
                    };
                    ui.label(RichText::new(format!("{count} {noun}")).size(11.0));
                    ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                        ui.label(
                            RichText::new(if self.state.paired {
                                self.t("WEB · PAIRED", "WEB · SPÁROVÁNO")
                            } else {
                                self.t("WEB · NOT PAIRED", "WEB · NESPÁROVÁNO")
                            })
                            .size(10.0)
                            .color(if self.state.paired {
                                VIOLET
                            } else {
                                MUTED
                            }),
                        );
                    });
                });
            });
        egui::CentralPanel::default()
            .frame(
                egui::Frame::new()
                    .fill(CANVAS)
                    .inner_margin(egui::Margin::same(28)),
            )
            .show(ui, |ui| {
                egui::ScrollArea::vertical().id_salt("page").show(ui, |ui| {
                    ui.set_min_width(ui.available_width());
                    self.heading(ui);
                    if matches!(self.view, View::Characters | View::Runs | View::Atlas) {
                        let placeholder = self.t(
                            "Search name, character, ID or event…",
                            "Hledat název, postavu, ID nebo událost…",
                        );
                        ui.add(
                            egui::TextEdit::singleline(&mut self.query)
                                .desired_width(f32::INFINITY)
                                .hint_text(placeholder),
                        );
                        ui.add_space(17.0);
                    }
                    match self.view {
                        View::Overview => self.overview(ui),
                        View::Characters => self.characters_view(ui),
                        View::Runs => self.runs_view(ui),
                        View::Atlas => self.atlas(ui),
                        View::Map => self.map_view(ui),
                        View::Database => {
                            self.database
                                .show(ui, &self.icons, self.prefs.language == Language::Cs)
                        }
                        View::Community => self.community.show(
                            ui,
                            &self.config,
                            &self.icons,
                            self.prefs.language == Language::Cs,
                            self.offline_preview,
                        ),
                        View::Sync => self.sync(ui),
                        View::Settings => self.settings(ui),
                    }
                });
            });
        // An explicit developer flag captures only this app's rendered viewport.
        // It never reads or captures any other desktop window.
        if self.local_rx.is_none()
            && self
                .last_scan
                .is_some_and(|at| at.elapsed() > Duration::from_secs(1))
            && let Some(path) = self.screenshot.take()
        {
            let ctx = ui.ctx().clone();
            let exit_after_screenshot = self.exit_after_screenshot;
            ui.ctx().request_screenshot(move |pixels| {
                let rgba: Vec<u8> = pixels.pixels.iter().flat_map(|p| p.to_array()).collect();
                let saved = image::save_buffer(
                    path,
                    &rgba,
                    pixels.size[0] as u32,
                    pixels.size[1] as u32,
                    image::ColorType::Rgba8,
                );
                if saved.is_ok() && exit_after_screenshot {
                    ctx.send_viewport_cmd(egui::ViewportCommand::Close);
                }
            });
        }
    }
}

impl eframe::App for App {
    fn ui(&mut self, ui: &mut egui::Ui, _frame: &mut eframe::Frame) {
        self.render_ui(ui);
    }
}

impl Drop for App {
    fn drop(&mut self) {
        let _ = self.tx.send(Command::Quit);
    }
}

fn style(ctx: &egui::Context) {
    let mut style = egui::Style {
        visuals: egui::Visuals::dark(),
        ..Default::default()
    };
    style.visuals.panel_fill = CANVAS;
    style.visuals.window_fill = PANEL;
    style.visuals.override_text_color = Some(Color32::from_rgb(247, 247, 248));
    style.visuals.selection.bg_fill = Color32::from_rgb(68, 49, 97);
    style.visuals.selection.stroke = Stroke::new(1.0, VIOLET);
    style.visuals.widgets.inactive.bg_fill = Color32::from_rgb(38, 34, 52);
    style.visuals.widgets.inactive.weak_bg_fill = Color32::from_rgb(38, 34, 52);
    style.visuals.widgets.inactive.bg_stroke = Stroke::new(1.0, BORDER);
    style.visuals.widgets.hovered.bg_fill = Color32::from_rgb(59, 45, 82);
    style.visuals.widgets.hovered.weak_bg_fill = Color32::from_rgb(59, 45, 82);
    style.visuals.widgets.hovered.bg_stroke = Stroke::new(1.0, VIOLET);
    style.visuals.widgets.active.bg_fill = Color32::from_rgb(75, 54, 109);
    style.visuals.hyperlink_color = VIOLET;
    style.spacing.item_spacing = Vec2::new(10.0, 8.0);
    style.spacing.button_padding = Vec2::new(13.0, 9.0);
    style.spacing.interact_size = Vec2::new(38.0, 34.0);
    style
        .text_styles
        .insert(egui::TextStyle::Body, egui::FontId::proportional(14.0));
    style
        .text_styles
        .insert(egui::TextStyle::Button, egui::FontId::proportional(13.0));
    ctx.set_global_style(style);
}

fn card(color: Color32) -> egui::Frame {
    egui::Frame::new()
        .fill(color)
        .corner_radius(10)
        .inner_margin(egui::Margin::same(16))
        .stroke(Stroke::new(1.0, BORDER.gamma_multiply(0.6)))
}
fn primary(ui: &mut egui::Ui, label: &str) -> egui::Response {
    ui.add(
        egui::Button::new(
            RichText::new(label)
                .color(Color32::from_rgb(24, 17, 38))
                .strong(),
        )
        .fill(VIOLET),
    )
}
fn hint(ui: &mut egui::Ui, text: &str) {
    ui.label(RichText::new(text).size(12.0).color(MUTED));
}
fn section(ui: &mut egui::Ui, title: &str, subtitle: &str) {
    ui.label(RichText::new(title).size(21.0));
    ui.label(RichText::new(subtitle).size(12.0).color(MUTED));
    ui.add_space(10.0);
}
fn metric(ui: &mut egui::Ui, value: usize, label: &str, color: Color32) {
    card(PANEL)
        .inner_margin(egui::Margin::same(15))
        .show(ui, |ui| {
            ui.set_min_width(ui.available_width());
            ui.label(
                RichText::new(value.to_string())
                    .size(31.0)
                    .monospace()
                    .color(color),
            );
            ui.add_space(5.0);
            ui.label(
                RichText::new(label)
                    .size(9.0)
                    .color(MUTED)
                    .extra_letter_spacing(0.5),
            );
        });
}
fn dot(ui: &mut egui::Ui, color: Color32) {
    let (r, _) = ui.allocate_exact_size(Vec2::splat(10.0), egui::Sense::hover());
    ui.painter().circle_filled(r.center(), 3.0, color);
}
fn account_key(account: &AccountData) -> String {
    format!("{}/{}", account.flavor, account.account)
}
fn json_details(ui: &mut egui::Ui, value: &Value, cs: bool) {
    let pretty =
        serde_json::to_string_pretty(&model::without_coordinates(value)).unwrap_or_default();
    if ui
        .small_button(if cs { "Zkopírovat data" } else { "Copy data" })
        .clicked()
    {
        ui.ctx().copy_text(pretty.clone());
    }
    ui.add(egui::Label::new(RichText::new(pretty).monospace().size(11.0).color(MUTED)).wrap());
}
fn class_color(id: Option<u64>) -> Color32 {
    match id {
        Some(1) => Color32::from_rgb(199, 156, 110),
        Some(2) => Color32::from_rgb(245, 140, 186),
        Some(3) => Color32::from_rgb(171, 212, 115),
        Some(4) => Color32::from_rgb(245, 233, 125),
        Some(5) => Color32::from_rgb(230, 230, 230),
        Some(6) => Color32::from_rgb(196, 61, 80),
        Some(7) => Color32::from_rgb(76, 140, 244),
        Some(8) => Color32::from_rgb(105, 204, 240),
        Some(9) => Color32::from_rgb(148, 130, 201),
        Some(11) => Color32::from_rgb(255, 140, 70),
        _ => VIOLET,
    }
}
fn event_label(kind: &str, cs: bool) -> &str {
    match (kind, cs) {
        ("quest.accepted", false) => "Quest accepted",
        ("quest.accepted", true) => "Přijatý úkol",
        ("quest.completed", false) => "Quest completed",
        ("quest.completed", true) => "Dokončený úkol",
        ("quest.rewarded", false) => "Quest rewarded",
        ("quest.rewarded", true) => "Odevzdaný úkol",
        ("quest.turned_in", false) => "Quest turned in",
        ("quest.turned_in", true) => "Odevzdaný quest",
        ("quest.abandoned", false) => "Quest abandoned",
        ("quest.abandoned", true) => "Zrušený quest",
        ("zone.visited", false) => "Zone visited",
        ("zone.visited", true) => "Navštívená zóna",
        ("vendor.snapshot", false) => "Vendor inventory",
        ("vendor.snapshot", true) => "Zboží obchodníka",
        ("craft.result", false) => "Crafted item",
        ("craft.result", true) => "Vyrobený předmět",
        ("npc.observed", false) => "NPC observed",
        ("npc.observed", true) => "Pozorované NPC",
        ("loot.received", false) => "Loot received",
        ("loot.received", true) => "Získaná kořist",
        ("character.snapshot", false) => "Character snapshot",
        ("character.snapshot", true) => "Snímek postavy",
        ("character.level", false) => "Level gained",
        ("character.level", true) => "Nová úroveň",
        ("profession.snapshot", false) => "Profession snapshot",
        ("profession.snapshot", true) => "Snímek profesí",
        ("cooldown.snapshot", false) => "Cooldown snapshot",
        ("cooldown.snapshot", true) => "Snímek cooldownů",
        ("instance.entered", false) => "Instance entered",
        ("instance.entered", true) => "Vstup do instance",
        ("run.finished", false) => "Dungeon visit ended",
        ("run.finished", true) => "Ukončená návštěva dungeonu",
        ("run.interrupted", false) => "Dungeon visit interrupted",
        ("run.interrupted", true) => "Přerušená návštěva dungeonu",
        _ => kind,
    }
}
fn nav_icon(painter: &egui::Painter, center: egui::Pos2, view: View, color: Color32) {
    let stroke = Stroke::new(1.4, color);
    match view {
        View::Overview => {
            for (x, y) in [(-5.0, -5.0), (5.0, -5.0), (-5.0, 5.0), (5.0, 5.0)] {
                painter.rect_stroke(
                    egui::Rect::from_center_size(center + Vec2::new(x, y), Vec2::splat(6.0)),
                    1.5,
                    stroke,
                    egui::StrokeKind::Middle,
                );
            }
        }
        View::Characters => {
            painter.circle_stroke(center + Vec2::new(0.0, -4.0), 3.5, stroke);
            painter.line_segment(
                [center + Vec2::new(-7.0, 7.0), center + Vec2::new(-5.0, 2.0)],
                stroke,
            );
            painter.line_segment(
                [center + Vec2::new(-5.0, 2.0), center + Vec2::new(5.0, 2.0)],
                stroke,
            );
            painter.line_segment(
                [center + Vec2::new(5.0, 2.0), center + Vec2::new(7.0, 7.0)],
                stroke,
            );
        }
        View::Runs => {
            painter.rect_stroke(
                egui::Rect::from_center_size(center, Vec2::new(12.0, 16.0)),
                2.0,
                stroke,
                egui::StrokeKind::Middle,
            );
            for y in [-4.0, 0.0, 4.0] {
                painter.line_segment(
                    [center + Vec2::new(-3.0, y), center + Vec2::new(3.0, y)],
                    stroke,
                );
            }
        }
        View::Atlas | View::Map | View::Database | View::Community => {
            painter.circle_stroke(center, 8.0, stroke);
            painter.line_segment(
                [center + Vec2::new(-8.0, 0.0), center + Vec2::new(8.0, 0.0)],
                stroke,
            );
            painter.line_segment(
                [center + Vec2::new(0.0, -8.0), center + Vec2::new(0.0, 8.0)],
                stroke,
            );
        }
        View::Sync => {
            painter.line_segment(
                [
                    center + Vec2::new(-7.0, -3.0),
                    center + Vec2::new(7.0, -3.0),
                ],
                stroke,
            );
            painter.line_segment(
                [center + Vec2::new(7.0, -3.0), center + Vec2::new(3.0, -7.0)],
                stroke,
            );
            painter.line_segment(
                [center + Vec2::new(7.0, 3.0), center + Vec2::new(-7.0, 3.0)],
                stroke,
            );
            painter.line_segment(
                [center + Vec2::new(-7.0, 3.0), center + Vec2::new(-3.0, 7.0)],
                stroke,
            );
        }
        View::Settings => {
            painter.circle_stroke(center, 7.0, stroke);
            painter.circle_stroke(center, 2.5, stroke);
        }
    }
}

fn main() -> eframe::Result {
    // Windowless preview dispatch is first: even startup errors go only to
    // stderr here, never the native error dialog used by the normal app.
    if std::env::args().any(|arg| arg == "--render-preview") {
        let Some(directory) = argument("--render-preview").filter(|value| !value.starts_with("--"))
        else {
            eprintln!("Usage: Evertally --render-preview <output-directory>");
            std::process::exit(2);
        };
        let result = Paths::new()
            .map_err(|e| e.to_string())
            .and_then(|paths| render_preview(paths, PathBuf::from(directory)));
        if let Err(error) = result {
            eprintln!("{error}");
            std::process::exit(1);
        }
        return Ok(());
    }
    let paths = match Paths::new() {
        Ok(paths) => paths,
        Err(error) => {
            platform::error_dialog(&error.to_string());
            return Ok(());
        }
    };
    let (config, startup_error) = match config::load_config(&paths.config) {
        Ok(config) => {
            let error = config.server_origin().err().map(|e| e.to_string());
            (config, error)
        }
        Err(error) => (
            Config {
                server: String::new(),
                ..Config::default()
            },
            Some(format!(
                "Settings could not be read: {error}. Your existing file was preserved."
            )),
        ),
    };
    if std::env::args().any(|arg| arg == "--diagnostics") {
        let dirs = wow::saved_variables_dirs(&wow::candidate_roots(config.wow_path.as_deref()));
        let accounts = local::read_accounts(&dirs, MAX_EVENTS);
        println!(
            "{}",
            serde_json::json!({"version":env!("CARGO_PKG_VERSION"),"savedVariableFolders":dirs.len(),"accounts":accounts.len(),"characters":accounts.iter().map(|a|a.characters.len()).sum::<usize>(),"retainedRuns":accounts.iter().map(|a|a.run_count).sum::<usize>(),"retainedEvents":accounts.iter().map(|a|a.event_count).sum::<usize>(),"readErrors":accounts.iter().filter(|a|a.error.is_some()).count(),"settingsValid":startup_error.is_none(),"mode":"local-read-only"})
        );
        return Ok(());
    }
    let mut viewport = egui::ViewportBuilder::default()
        .with_title("Evertally")
        .with_inner_size([1180.0, 820.0])
        .with_min_inner_size([860.0, 620.0]);
    if std::env::args().any(|arg| arg == "--wow-start") {
        viewport = viewport.with_active(false);
    }
    if let Ok(icon) = eframe::icon_data::from_png_bytes(ICON) {
        viewport = viewport.with_icon(icon);
    }
    let options = eframe::NativeOptions {
        viewport,
        renderer: eframe::Renderer::Glow,
        ..Default::default()
    };
    eframe::run_native(
        "Evertally",
        options,
        Box::new(move |cc| Ok(Box::new(App::new(cc, paths, config, startup_error)))),
    )
}

fn argument(flag: &str) -> Option<String> {
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        if arg == flag {
            return args.next();
        }
    }
    None
}

fn render_preview(paths: Paths, directory: PathBuf) -> Result<(), String> {
    std::fs::create_dir_all(&directory).map_err(|e| e.to_string())?;
    let (config, startup_error) = match std::fs::read(&paths.config)
        .map_err(|e| e.to_string())
        .and_then(|bytes| serde_json::from_slice::<Config>(&bytes).map_err(|e| e.to_string()))
    {
        Ok(config) => (config, None),
        Err(error) => (
            Config {
                server: String::new(),
                ..Config::default()
            },
            Some(error),
        ),
    };
    let (width, height) = (1180, 820);
    let mut files = Vec::new();
    for language in [Language::En, Language::Cs] {
        let ctx = egui::Context::default();
        let mut app = App::new_context(
            &ctx,
            paths.clone(),
            config.clone(),
            startup_error.clone(),
            false,
        );
        app.prefs.language = language;
        app.state.status = app
            .t(
                "Offline preview · web synchronization is not running",
                "Místní náhled · webová synchronizace neběží",
            )
            .into();
        let mut renderer = preview::SoftwareRenderer::default();
        for (view, name) in View::ALL.into_iter().zip([
            "overview",
            "characters",
            "runs",
            "atlas",
            "map",
            "database",
            "community",
            "sync",
            "settings",
        ]) {
            app.view = view;
            let filename = format!(
                "desktop-{name}-{}.png",
                if language == Language::Cs { "cs" } else { "en" }
            );
            let path = directory.join(&filename);
            for pass in 0..3 {
                let input = egui::RawInput {
                    screen_rect: Some(egui::Rect::from_min_size(
                        egui::Pos2::ZERO,
                        Vec2::new(width as f32, height as f32),
                    )),
                    time: Some(f64::from(pass)),
                    ..Default::default()
                };
                let output = ctx.run_ui(input, |ui| app.render_ui(ui));
                renderer.render(&ctx, output, width, height, &path)?;
            }
            files.push(filename);
        }
    }
    println!(
        "{}",
        serde_json::json!({"renderer":"egui CPU meshes","osWindowsCreated":0,"webSyncStarted":false,"files":files})
    );
    Ok(())
}

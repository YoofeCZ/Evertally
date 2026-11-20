#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]
//! Default startup creates a tray icon only. The optional window contains Web sync and connection settings.
mod preview;

use eframe::egui::{self, Color32, RichText};
use evertally_sync::{
    bridge::{self, Action, Snapshot},
    config::{self, Config, Paths},
    platform, prefs, shutdown,
};
use std::path::PathBuf;
type Permission = Option<(bool, Vec<String>)>;
type PermissionCache =
    std::collections::HashMap<PathBuf, (Option<std::time::SystemTime>, Permission)>;

struct ConnectionSettings {
    config_path: PathBuf,
    server: String,
    wow: String,
    autostart: bool,
    original_autostart: bool,
    login_start: bool,
    original_login_start: bool,
    cs: bool,
    message: Option<(String, bool)>,
    stop: Option<shutdown::StopSignal>,
    preview: bool,
    sync_page: bool,
    snapshot: Option<Snapshot>,
    last_poll: std::time::Instant,
    permissions: Vec<Permission>,
    permission_cache: PermissionCache,
    action_until: Option<std::time::Instant>,
    /// Download updates of the add-on and the app by themselves (prefs.json).
    auto_update: bool,
    /// The first-run guide's step while it is open (prefs.json `onboarded` false, or `--onboarding`).
    wizard: Option<usize>,
}

/// The first-run guide's steps: welcome, WoW folder, pairing, start-up, updates, done.
const WIZARD_STEPS: usize = 6;

impl ConnectionSettings {
    fn new(config_path: PathBuf, config: Config, cs: bool, preview: bool) -> Self {
        let autostart = !preview && platform::autostart_enabled();
        let login_start = !preview && platform::login_start_enabled();
        let auto_update = preview || prefs_dir_of(&config_path).is_none_or(|d| prefs::load(&d).auto_update);
        Self {
            config_path,
            server: config.server,
            wow: config
                .wow_path
                .map(|p| p.display().to_string())
                .unwrap_or_default(),
            autostart,
            original_autostart: autostart,
            login_start,
            original_login_start: login_start,
            cs,
            message: None,
            stop: if preview {
                None
            } else {
                shutdown::StopSignal::new(shutdown::SETTINGS_STOP)
            },
            preview,
            sync_page: true,
            snapshot: None,
            last_poll: std::time::Instant::now() - std::time::Duration::from_secs(10),
            permissions: vec![],
            permission_cache: std::collections::HashMap::new(),
            action_until: None,
            auto_update,
            wizard: None,
        }
    }
    fn prefs_dir(&self) -> Option<PathBuf> { prefs_dir_of(&self.config_path) }
    fn save_prefs(&self, onboarded: bool) -> Result<(), String> {
        if self.preview { return Ok(()); }
        let Some(dir) = self.prefs_dir() else { return Ok(()) };
        prefs::save(&dir, &prefs::Prefs { auto_update: self.auto_update, onboarded }).map_err(|e| e.to_string())
    }
    fn candidate(&self) -> Config {
        Config { server: self.server.clone(), wow_path: (!self.wow.trim().is_empty()).then(|| PathBuf::from(self.wow.trim())) }
    }
    /// Saves the connection, the start-up choices and the updates choice (Save settings, the guide's Finish).
    fn save_all(&mut self, onboarded: bool) -> Result<(), String> {
        let candidate = self.candidate();
        validate(&candidate)?;
        if self.preview { return Ok(()); }
        if self.autostart != self.original_autostart { platform::set_autostart(self.autostart).map_err(|e| e.to_string())?; self.original_autostart = self.autostart; }
        if self.login_start != self.original_login_start { platform::set_login_start(self.login_start).map_err(|e| e.to_string())?; self.original_login_start = self.login_start; }
        save_config(&self.config_path, &candidate)?;
        self.save_prefs(onboarded)?;
        shutdown::request(shutdown::BRIDGE_RELOAD);
        Ok(())
    }

    /// The first-run guide: one step at a time, Back / Next, and Skip (everything stays in Connection settings).
    fn wizard_ui(&mut self, ui: &mut egui::Ui, step: usize) {
        let accent = Color32::from_rgb(182, 159, 250);
        let muted = Color32::from_rgb(187, 180, 205);
        ui.label(RichText::new(format!("{} {}/{WIZARD_STEPS}", self.t("Setup", "Průvodce"), step + 1)).color(accent));
        ui.add_space(6.0);
        let para = |ui: &mut egui::Ui, text: &str| { ui.label(RichText::new(text).color(muted)); ui.add_space(4.0); };
        match step {
            0 => {
                ui.label(RichText::new(self.t("Welcome to Evertally", "Vítej v Evertally")).size(24.0));
                ui.add_space(10.0);
                para(ui, self.t("This app runs quietly next to the Windows clock and connects the Evertally add-on in the game with the website:",
                    "Tahle aplikace běží potichu vedle hodin Windows a propojuje addon Evertally ve hře s webem:"));
                for line in [
                    self.t("•  it uploads what the add-on saves: your chronicle, the leaderboard, Armory and your page on the website,", "•  nahrává, co addon uloží: tvoji kroniku, žebříček, Armory a tvoji stránku na webu,"),
                    self.t("•  it shares your live position with your party and guild when you want it,", "•  sdílí tvoji živou polohu s partou a guildou, když chceš,"),
                    self.t("•  it keeps the add-on up to date.", "•  udržuje addon aktuální."),
                ] { para(ui, line); }
                ui.add_space(6.0);
                para(ui, self.t("A few steps and you are done. You can change everything later in Connection settings.",
                    "Pár kroků a máš hotovo. Všechno můžeš později změnit v Nastavení spojení."));
            }
            1 => {
                ui.label(RichText::new(self.t("Where is World of Warcraft?", "Kde je World of Warcraft?")).size(22.0));
                ui.add_space(8.0);
                para(ui, self.t("Leave the field empty and the app finds the game by itself. Fill it in only when it does not.",
                    "Nech pole prázdné a aplikace hru najde sama. Vyplň ho, jen když ji nenajde."));
                let placeholder = self.t("Leave empty to detect automatically", "Prázdné pole = automatické hledání");
                ui.add(egui::TextEdit::singleline(&mut self.wow).hint_text(placeholder).desired_width(f32::INFINITY));
                let (hint_en, hint_cs) = game_folder_hint();
                ui.weak(self.t(hint_en, hint_cs));
                let found = self.snapshot.as_ref().map_or(0, |s| s.state.folders.len());
                if found > 0 {
                    ui.add_space(6.0);
                    ui.colored_label(Color32::LIGHT_GREEN, format!("{} {found}", self.t("Game folders found:", "Nalezené složky hry:")));
                }
            }
            2 => {
                ui.label(RichText::new(self.t("Pair this PC with the website", "Spáruj počítač s webem")).size(22.0));
                ui.add_space(8.0);
                para(ui, self.t("Pairing tells the website that the data from this PC are yours. The website opens: sign in with Discord and approve the code.",
                    "Párování řekne webu, že data z tohohle počítače jsou tvoje. Otevře se web: přihlas se přes Discord a potvrď kód."));
                let state = self.snapshot.as_ref().map(|s| s.state.clone());
                let paired = state.as_ref().is_some_and(|s| s.paired);
                let code = state.as_ref().and_then(|s| s.pairing_code.clone());
                let ready = state.is_some() && self.action_until.is_none_or(|at| std::time::Instant::now() >= at);
                if paired {
                    ui.colored_label(Color32::LIGHT_GREEN, self.t("This PC is paired.", "Tento počítač je spárovaný."));
                } else if let Some(code) = code {
                    ui.label(RichText::new(&code).monospace().size(28.0).color(accent));
                    ui.horizontal_wrapped(|ui| {
                        if ui.button(self.t("Copy code", "Kopírovat kód")).clicked() { ui.ctx().copy_text(code.clone()); }
                        if ui.button(self.t("Open approval page", "Otevřít schvalovací stránku")).clicked() && !self.preview
                            && let Some(snapshot) = &self.snapshot && let Some(url) = approval_url(&snapshot.server, &code) { let _ = open::that(url); }
                    });
                } else if ui.add_enabled(ready, egui::Button::new(self.t("Pair this PC", "Spárovat tento počítač"))).clicked() {
                    self.send(Action::Pair);
                }
                ui.add_space(6.0);
                ui.weak(self.t("Not now? Skip it: you can pair any time from the icon next to the clock.",
                    "Teď ne? Přeskoč to: spárovat můžeš kdykoli z ikony vedle hodin."));
            }
            3 => {
                ui.label(RichText::new(self.t("When should the app start?", "Kdy se má aplikace spouštět?")).size(22.0));
                ui.add_space(8.0);
                let label = self.t("With WoW (it starts when you start the game)", "S WoW (spustí se, když spustíš hru)");
                ui.checkbox(&mut self.autostart, label);
                if cfg!(windows) {
                    let label = self.t("With Windows (in the tray, no window)", "Se startem Windows (v liště, bez okna)");
                    ui.checkbox(&mut self.login_start, label);
                }
                ui.add_space(6.0);
                para(ui, self.t("The app needs to run while you play or right after, so that your games reach the website.",
                    "Aplikace musí běžet, když hraješ nebo hned potom, aby se tvoje hraní dostalo na web."));
            }
            4 => {
                ui.label(RichText::new(self.t("Updates", "Aktualizace")).size(22.0));
                ui.add_space(8.0);
                let label = self.t("Download updates automatically (the add-on and this app)", "Automaticky stahovat aktualizace (addon i tuto aplikaci)");
                ui.checkbox(&mut self.auto_update, label);
                ui.add_space(6.0);
                para(ui, if self.auto_update {
                    self.t("New versions download and install by themselves. A new add-on takes effect after you restart WoW.",
                        "Nové verze se stáhnou a nainstalují samy. Nový addon začne platit po restartu WoW.")
                } else {
                    self.t("Nothing downloads by itself. To update, use Check for updates in the menu of the icon next to the clock.",
                        "Nic se nestáhne samo. Aktualizuješ přes Zkontrolovat aktualizace v nabídce ikony vedle hodin.")
                });
            }
            _ => {
                ui.label(RichText::new(self.t("All set", "Hotovo")).size(24.0));
                ui.add_space(10.0);
                para(ui, self.t("The app now runs next to the clock. In the game, type /etally setup to choose what the add-on does.",
                    "Aplikace teď běží vedle hodin. Ve hře napiš /etally setup a vyber, co má addon dělat."));
                para(ui, self.t("The OpenMap add-on (free, on CurseForge) shows your party members and gathering places on the map.",
                    "Addon OpenMap (zdarma, na CurseForge) ukáže na mapě spoluhráče a místa sbírání."));
                if ui.button(self.t("Get OpenMap", "Získat OpenMap")).clicked() && !self.preview {
                    let _ = open::that("https://www.curseforge.com/wow/addons/openmap");
                }
            }
        }
        if let Some((message, error)) = &self.message {
            ui.add_space(6.0);
            ui.colored_label(if *error { Color32::LIGHT_RED } else { Color32::LIGHT_GREEN }, message);
        }
        ui.add_space(18.0);
        ui.horizontal(|ui| {
            if step > 0 && ui.button(self.t("Back", "Zpět")).clicked() { self.message = None; self.wizard = Some(step - 1); }
            let last = step + 1 >= WIZARD_STEPS;
            let next = if last { self.t("Finish", "Dokončit") } else { self.t("Next", "Další") };
            if ui.add(egui::Button::new(RichText::new(next).strong()).fill(Color32::from_rgb(110, 86, 200))).clicked() {
                self.message = None;
                if step == 1 && let Err(error) = validate(&self.candidate()) {
                    self.message = Some((error, true));
                } else if last {
                    match self.save_all(true) {
                        Ok(()) => { self.wizard = None; self.sync_page = true; }
                        Err(error) => self.message = Some((error, true)),
                    }
                } else {
                    self.wizard = Some(step + 1);
                }
            }
            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                if ui.button(self.t("Skip setup", "Přeskočit průvodce")).clicked() {
                    let _ = self.save_prefs(true);
                    self.wizard = None;
                    self.sync_page = true;
                }
            });
        });
    }
    fn t<'a>(&self, en: &'a str, cs: &'a str) -> &'a str {
        if self.cs { cs } else { en }
    }

    fn show(&mut self, root: &mut egui::Ui) {
        if !self.preview && self.last_poll.elapsed() >= std::time::Duration::from_secs(1) {
            self.snapshot = self
                .config_path
                .parent()
                .and_then(|p| bridge::read(&p.join(bridge::STATUS_FILE), bridge::now()));
            self.permissions = self
                .snapshot
                .as_ref()
                .map(|s| {
                    s.state
                        .folders
                        .iter()
                        .take(100)
                        .map(|folder| {
                            let path = PathBuf::from(folder);
                            let modified =
                                std::fs::metadata(path.join(evertally_sync::wow::EXPORT_FILE))
                                    .and_then(|m| m.modified())
                                    .ok();
                            if let Some((before, permission)) = self.permission_cache.get(&path)
                                && before == &modified
                            {
                                return permission.clone();
                            }
                            let permission = export_permission(&path);
                            self.permission_cache
                                .insert(path, (modified, permission.clone()));
                            permission
                        })
                        .collect()
                })
                .unwrap_or_default();
            self.last_poll = std::time::Instant::now();
        }
        let ctx = root.ctx().clone();
        if self
            .stop
            .as_ref()
            .is_some_and(shutdown::StopSignal::requested)
        {
            ctx.send_viewport_cmd(egui::ViewportCommand::Close);
        }
        ctx.request_repaint_after(std::time::Duration::from_millis(250));
        egui::CentralPanel::default().frame(egui::Frame::new().fill(Color32::from_rgb(19,17,28)).inner_margin(24)).show(root, |ui| { egui::ScrollArea::vertical().show(ui,|ui| {
            ui.horizontal(|ui| {
                ui.heading("Evertally Bridge");
                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    ui.selectable_value(&mut self.cs, true, "CS");
                    ui.selectable_value(&mut self.cs, false, "EN");
                });
            });
            if self.wizard.is_none() { ui.horizontal(|ui| {
                ui.selectable_value(&mut self.sync_page,true,"Web sync");
                let title=self.t("Connection settings", "Nastavení spojení");
                ui.selectable_value(&mut self.sync_page,false,title);
            }); }
            ui.separator();
            if let Some(step) = self.wizard { self.wizard_ui(ui, step); return; }
            if self.sync_page { self.web_sync(ui); return; }
            ui.label(RichText::new(self.t("Connection settings", "Nastavení spojení")).size(20.0));
            ui.add_space(8.0);
            let (place_en, place_cs) = tray_place();
            ui.label(format!("{} {}", self.t(place_en, place_cs), self.t("Pairing and transfer status are on the Web sync tab.", "Párování a stav přenosu najdeš na kartě Web sync.")));
            ui.add_space(16.0);
            ui.label(self.t("Evertally website", "Web Evertally"));
            ui.add(egui::TextEdit::singleline(&mut self.server).desired_width(f32::INFINITY));
            ui.add_space(12.0);
            ui.label(self.t("World of Warcraft folder", "Složka World of Warcraft"));
            let placeholder = self.t("Leave empty to detect automatically", "Prázdné pole = automatické hledání");
            ui.add(egui::TextEdit::singleline(&mut self.wow).hint_text(placeholder).desired_width(f32::INFINITY));
            let (hint_en, hint_cs) = game_folder_hint();
            ui.weak(self.t(hint_en, hint_cs));
            ui.add_space(12.0);
            let label = self.t("Start the bridge automatically with WoW", "Spouštět most automaticky s WoW");
            ui.checkbox(&mut self.autostart, label);
            if cfg!(windows) {
                let label = self.t("Start with Windows (in the tray, no window)", "Spouštět při startu Windows (v liště, bez okna)");
                ui.checkbox(&mut self.login_start, label);
            }
            let label = self.t("Download updates automatically (the add-on and this app)", "Automaticky stahovat aktualizace (addon i tuto aplikaci)");
            ui.checkbox(&mut self.auto_update, label);
            if !self.auto_update {
                ui.weak(self.t("Updates: Check for updates in the menu of the icon next to the clock.", "Aktualizace: Zkontrolovat aktualizace v nabídce ikony vedle hodin."));
            }
            if ui.button(self.t("Run the setup again", "Spustit průvodce znovu")).clicked() { self.message = None; self.wizard = Some(0); }
            ui.add_space(14.0);
            ui.label(self.t("Map, database, rankings and your history are on the website. The addon works inside the game.", "Mapu, databázi, žebříčky a historii najdeš na webu. Addon funguje přímo ve hře."));
            ui.weak(self.t("Live position reads the addon marker while the game corner is visible, including on a second monitor. Enable Website export, My character, My route and Live position on the website.", "Živá poloha čte značku addonu, když je vidět levý horní roh hry, i na druhém monitoru. Zapni Webový export, Moji postavu, Moji trasu a Živou polohu na webu."));
            ui.add_space(16.0);
            ui.horizontal(|ui| {
                if ui.button(self.t("Save settings", "Uložit nastavení")).clicked() && !self.preview {
                    let onboarded = self.prefs_dir().is_none_or(|d| prefs::load(&d).onboarded);
                    let result = self.save_all(onboarded);
                    self.message = Some(match result { Ok(()) => (self.t("Saved. The bridge will apply the connection.", "Uloženo. Most použije nové spojení.").to_owned(), false), Err(error) => (error, true) });
                }
                if ui.button(self.t("Close", "Zavřít")).clicked() { ctx.send_viewport_cmd(egui::ViewportCommand::Close); }
            });
            if let Some((message, error)) = &self.message { ui.colored_label(if *error {Color32::LIGHT_RED} else {Color32::LIGHT_GREEN}, message); }
            ui.add_space(12.0);
            ui.weak(format!("Evertally Bridge {}", env!("CARGO_PKG_VERSION")));
        }); });
    }

    fn send(&mut self, action: Action) {
        if self.preview {
            return;
        }
        action.request();
        self.action_until = Some(std::time::Instant::now() + std::time::Duration::from_secs(2));
    }

    fn web_sync(&mut self, ui: &mut egui::Ui) {
        let snapshot = self.snapshot.clone();
        let state = snapshot.as_ref().map(|s| &s.state);
        let ready = state.is_some()
            && self
                .action_until
                .is_none_or(|at| std::time::Instant::now() >= at);
        ui.add_space(12.0);
        egui::Frame::new().fill(Color32::from_rgb(27,33,50)).corner_radius(10).inner_margin(20).show(ui,|ui| {
            ui.set_min_width(ui.available_width());
            let paired=state.is_some_and(|s|s.paired);
            let code=state.and_then(|s|s.pairing_code.as_deref());
            ui.label(RichText::new(if paired {self.t("This PC is paired", "Tento počítač je spárovaný")} else if code.is_some() {self.t("Pair this PC", "Spárovat tento počítač")} else {self.t("This PC is not paired", "Tento počítač není spárovaný")}).size(22.0));
            ui.add_space(9.0);
            ui.label(state.map_or(self.t("Starting the background bridge…", "Spouštím most na pozadí…"),|s|s.status.as_str()));
            if let Some(snapshot)=self.snapshot.as_ref().filter(|s|!s.update_status.is_empty()) {
                ui.label(RichText::new(&snapshot.update_status).color(Color32::from_rgb(187,180,205)));
            }
            if let Some(status)=state.and_then(|s|s.live_status.as_deref()){ui.label(RichText::new(status).color(Color32::from_rgb(143,213,175)));}
            if let Some(code)=code {
                ui.add_space(8.0);
                ui.label(RichText::new(code).monospace().size(28.0).color(Color32::from_rgb(182,159,250)));
                ui.label(self.t("Approve this code on the website. The browser confirms your Discord account.", "Potvrď tento kód na webu. Prohlížeč ověří tvůj účet Discord."));
                ui.horizontal_wrapped(|ui| {
                    if ui.button(self.t("Copy code", "Kopírovat kód")).clicked() { ui.ctx().copy_text(code.to_owned()); }
                    if ui.button(self.t("Open approval page", "Otevřít schvalovací stránku")).clicked() && !self.preview
                        && let Some(snapshot)=&snapshot && let Some(url)=approval_url(&snapshot.server,code) { let _=open::that(url); }
                    if ui.add_enabled(ready,egui::Button::new(self.t("Cancel pairing", "Zrušit párování"))).clicked() { self.send(Action::CancelPair); }
                });
            } else {
                if !paired {
                    // The first thing a new player sees after the installer: what to do, in order.
                    ui.add_space(10.0);
                    ui.label(RichText::new(self.t("How to start", "Jak začít")).strong().size(16.0));
                    for step in [
                        self.t(
                            "1. Click Pair this PC. The website opens: sign in with Discord and approve the code.",
                            "1. Klikni na Spárovat tento počítač. Otevře se web: přihlas se přes Discord a potvrď kód.",
                        ),
                        self.t(
                            "2. In the game open Evertally > Settings and turn on \"Prepare own data for the website\". To be seen by other players, also turn on \"Show my characters in the public leaderboard on the website\".",
                            "2. Ve hře otevři Evertally > Nastavení a zapni „Připravovat vlastní data pro web“. Aby tě viděli ostatní hráči, zapni i „Ukázat mé postavy ve veřejném žebříčku na webu“.",
                        ),
                        self.t(
                            "3. Play. After /reload or logging out, this bridge uploads new records by itself.",
                            "3. Hraj. Po /reload nebo odhlášení most sám nahraje nové záznamy.",
                        ),
                    ] {
                        ui.label(step);
                    }
                }
                ui.add_space(10.0);
                ui.horizontal_wrapped(|ui| {
                    if paired {
                        if ui.add_enabled(ready,egui::Button::new(self.t("Sync now", "Synchronizovat teď"))).clicked() {self.send(Action::Sync);}
                        if ui.add_enabled(ready,egui::Button::new(self.t("Disconnect this PC", "Odpojit tento počítač"))).clicked() {self.send(Action::Unpair);}
                    } else if ui.add_enabled(ready,egui::Button::new(self.t("Pair this PC", "Spárovat tento počítač"))).clicked() { self.send(Action::Pair); }
                    if ui.button(self.t("Open website", "Otevřít web")).clicked() && !self.preview {
                        let server=snapshot.as_ref().map_or(self.server.as_str(),|s|s.server.as_str());
                        if let Ok(origin)=(Config {server:server.to_owned(),wow_path:None}).server_origin() { let _=open::that(origin); }
                    }
                });
            }
        });
        ui.add_space(12.0);
        ui.horizontal_wrapped(|ui| {
            if ui.button(self.t("Get OpenMap", "Získat OpenMap")).clicked() && !self.preview {
                let _ = open::that("https://www.curseforge.com/wow/addons/openmap");
            }
            if ui.button(self.t("Open app downloads", "Otevřít stažení aplikace")).clicked() && !self.preview {
                let _ = open::that("https://evertally.afstudio.dev/#sync");
            }
        });
        ui.add_space(18.0);
        ui.label(RichText::new(self.t("Export permissions", "Oprávnění exportu")).size(18.0));
        ui.weak(self.t(
            "Change these choices in the game. Pairing does not enable extra data.",
            "Tyto volby měníš ve hře. Párování samo nepovolí další data.",
        ));
        if self.permissions.is_empty() {
            ui.label(self.t(
                "No saved export found yet. Check the WoW folder in Connection settings.",
                "Zatím není nalezen uložený export. Zkontroluj cestu k WoW v Nastavení spojení.",
            ));
        }
        for (i, permission) in self.permissions.iter().enumerate() {
            ui.add_space(6.0);
            ui.label(format!("{} {}", self.t("WoW account", "Účet WoW"), i + 1));
            if let Some((enabled, scopes)) = permission {
                ui.colored_label(
                    if *enabled {
                        Color32::LIGHT_GREEN
                    } else {
                        Color32::LIGHT_GRAY
                    },
                    if *enabled {
                        self.t("Web export: ON", "Webový export: ZAPNUTO")
                    } else {
                        self.t("Web export: OFF", "Webový export: VYPNUTO")
                    },
                );
                ui.weak(
                    scopes
                        .iter()
                        .map(|s| scope_name(s, self.cs))
                        .collect::<Vec<_>>()
                        .join(" · "),
                );
            } else {
                ui.weak(self.t(
                    "Export is missing or unreadable",
                    "Export chybí nebo jej nelze přečíst",
                ));
            }
        }
        ui.add_space(16.0);
        ui.weak(self.t("Live position sends without /reload while the game corner is visible. Other history arrives after /reload or logout.", "Živá poloha se přenáší bez /reload, když je vidět levý horní roh hry. Ostatní historie se ukládá při /reload či odhlášení."));
        if let Some(snapshot) = &snapshot {
            ui.weak(format!("Server: {}", snapshot.server));
        }
        ui.add_space(12.0);
        if ui.button(self.t("Hide window", "Skrýt okno")).clicked() {
            ui.ctx().send_viewport_cmd(egui::ViewportCommand::Close);
        }
    }
}

/// The settings folder (prefs.json lives beside config.json).
fn prefs_dir_of(config_path: &std::path::Path) -> Option<PathBuf> {
    config_path.parent().filter(|p| !p.as_os_str().is_empty()).map(std::path::Path::to_path_buf)
}

/// What the WoW folder field expects, per operating system.
fn game_folder_hint() -> (&'static str, &'static str) {
    if cfg!(target_os = "macos") {
        (
            "Choose the folder with World of Warcraft.app (or Wow.exe under Wine) or its parent containing _forever_.",
            "Zadej složku s World of Warcraft.app (nebo Wow.exe pod Wine) nebo jejího rodiče obsahujícího _forever_.",
        )
    } else if cfg!(windows) {
        (
            "Choose the folder with Wow.exe or its parent containing _forever_.",
            "Zadej složku s Wow.exe nebo jejího rodiče obsahujícího _forever_.",
        )
    } else {
        (
            "Choose the folder with Wow.exe (inside the Wine prefix) or its parent containing _forever_.",
            "Zadej složku s Wow.exe (uvnitř Wine prefixu) nebo jejího rodiče obsahujícího _forever_.",
        )
    }
}

/// Where the bridge's icon lives, per operating system.
fn tray_place() -> (&'static str, &'static str) {
    if cfg!(target_os = "macos") {
        ("The bridge runs in the menu bar.", "Most běží v horní liště macOS.")
    } else if cfg!(windows) {
        ("The bridge runs next to the Windows clock.", "Most běží vedle hodin Windows.")
    } else {
        ("The bridge runs in the system tray.", "Most běží v systémové liště.")
    }
}

fn scope_name(scope: &str, cs: bool) -> &str {
    match (scope, cs) {
        ("world_facts", true) => "Herní svět",
        ("own_runs", true) => "Moje výpravy",
        ("own_character", true) => "Moje postava",
        ("own_professions", true) => "Moje profese",
        ("own_track", true) => "Moje trasa",
        ("guild_share", true) => "Můj cech",
        _ => scope,
    }
}

fn export_permission(folder: &std::path::Path) -> Option<(bool, Vec<String>)> {
    let path = folder.join(evertally_sync::wow::EXPORT_FILE);
    if std::fs::metadata(&path).ok()?.len() > 16 * 1024 * 1024 {
        return None;
    }
    let text = std::fs::read_to_string(path).ok()?;
    let data =
        evertally_sync::savedvars::parse_assignment(&text, evertally_sync::wow::EXPORT_VARIABLE)
            .ok()?;
    let enabled = data["enabled"].as_bool()?;
    let scopes = data["scopes"]
        .as_array()
        .map(|a| {
            a.iter()
                .filter_map(|s| s.as_str().map(str::to_owned))
                .collect()
        })
        .unwrap_or_default();
    Some((enabled, scopes))
}

fn approval_url(server: &str, code: &str) -> Option<String> {
    if code.len() > 20
        || code.is_empty()
        || !code.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-')
    {
        return None;
    }
    let origin = Config {
        server: server.to_owned(),
        wow_path: None,
    }
    .server_origin()
    .ok()?;
    Some(format!("{origin}/link?code={code}"))
}

fn validate(config: &Config) -> Result<(), String> {
    config.server_origin().map_err(|e| e.to_string())?;
    if let Some(path) = &config.wow_path
        && !holds_game(path)
        && !holds_game(&path.join("_forever_"))
    {
        return Err("Složka musí obsahovat hru (Wow.exe nebo World of Warcraft.app), nebo její podsložku _forever_.".into());
    }
    Ok(())
}

/// Whether `dir` holds an entry of that name (a file, or a folder when `folder`), ignoring case: Linux file
/// systems are case-sensitive, the game's are not.
fn has_entry(dir: &std::path::Path, name: &str, folder: bool) -> bool {
    std::fs::read_dir(dir).is_ok_and(|entries| {
        entries.flatten().any(|entry| {
            entry.file_name().to_string_lossy().eq_ignore_ascii_case(name)
                && if folder { entry.path().is_dir() } else { entry.path().is_file() }
        })
    })
}

/// The Windows / Wine client or the native macOS app is in this folder.
fn holds_game(dir: &std::path::Path) -> bool {
    has_entry(dir, "Wow.exe", false) || has_entry(dir, "World of Warcraft.app", true)
}

fn save_config(path: &std::path::Path, config: &Config) -> Result<(), String> {
    let bytes = serde_json::to_vec_pretty(config).map_err(|e| e.to_string())?;
    if path.is_file() {
        std::fs::copy(path, path.with_extension("json.bak")).map_err(|e| e.to_string())?;
    }
    let temp = path.with_extension("json.tmp");
    std::fs::write(&temp, bytes).map_err(|e| e.to_string())?;
    std::fs::rename(temp, path).map_err(|e| e.to_string())
}

impl eframe::App for ConnectionSettings {
    fn ui(&mut self, ui: &mut egui::Ui, _frame: &mut eframe::Frame) {
        self.show(ui);
    }
}

fn style(ctx: &egui::Context) {
    let mut style = egui::Style {
        visuals: egui::Visuals::dark(),
        ..Default::default()
    };
    style.visuals.override_text_color = Some(Color32::from_rgb(235, 233, 241));
    style.visuals.weak_text_color = Some(Color32::from_rgb(172, 169, 187));
    style.spacing.item_spacing = egui::vec2(10.0, 8.0);
    style.spacing.button_padding = egui::vec2(14.0, 9.0);
    style
        .text_styles
        .insert(egui::TextStyle::Body, egui::FontId::proportional(14.0));
    ctx.set_global_style(style);
}

fn main() {
    if let Err(error) = run() {
        if std::env::args()
            .any(|arg| arg == "--render-preview" || arg == "--diagnostics" || arg == "--live-check")
        {
            eprintln!("Evertally Bridge: {error}");
        } else {
            platform::error_dialog(&format!("Evertally Bridge: {error}"));
        }
        std::process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let args: Vec<String> = std::env::args().collect();
    if args.iter().any(|a| a == "--stop") {
        shutdown::request(shutdown::BRIDGE_STOP);
        shutdown::request(shutdown::SETTINGS_STOP);
        return Ok(());
    }
    if args.iter().any(|a| a == "--diagnostics") {
        println!(
            "{}",
            serde_json::json!({"version":env!("CARGO_PKG_VERSION"),"mode":"tray-bridge","mainWindow":false,"webMap":true,"liveWebPosition":true,"gameVerified":false})
        );
        return Ok(());
    }
    if args.iter().any(|a| a == "--live-check") {
        let paths = Paths::new().map_err(|e| e.to_string())?;
        let config = config::load_config(&paths.config).map_err(|e| e.to_string())?;
        let packet = evertally_sync::optical::capture(config.wow_path.as_deref());
        // Read-only diagnostic: no window, input, network, character name or token output.
        println!(
            "{}",
            match packet {
                Some(p) => serde_json::json!({"decoded":true,"mapId":p.m,"observedAt":p.t}),
                None =>
                    serde_json::json!({"decoded":false,"reason":"No readable addon marker in a visible WoW window"}),
            }
        );
        return Ok(());
    }
    if let Some(at) = args.iter().position(|a| a == "--render-preview") {
        let output = args.get(at + 1).ok_or("Missing preview directory")?;
        std::fs::create_dir_all(output).map_err(|e| e.to_string())?;
        for cs in [true, false] {
            for page in ["settings", "paired", "pairing", "unpaired", "wizard0", "wizard1", "wizard2", "wizard3", "wizard4", "wizard5"] {
                let ctx = egui::Context::default();
                style(&ctx);
                let mut app = ConnectionSettings::new(PathBuf::new(), Config::default(), cs, true);
                app.sync_page = page != "settings";
                app.wizard = page.strip_prefix("wizard").and_then(|n| n.parse().ok());
                app.snapshot = Some(Snapshot {
                    at: bridge::now(),
                    server: config::DEFAULT_SERVER.to_owned(),
                    update_status: if cs {"Aplikace i addon jsou aktuální"}else{"App and addon are up to date"}.to_owned(),
                    state: evertally_sync::worker::UiState {
                        live_status: (page == "paired").then(|| {
                            if cs {
                                "Živá poloha odeslána · zkušební náhled"
                            } else {
                                "Live position sent · preview fixture"
                            }
                            .into()
                        }),
                        status: if cs {
                            "Zkušební náhled spojení"
                        } else {
                            "Connection preview fixture"
                        }
                        .to_owned(),
                        tooltip: String::new(),
                        paired: page == "paired",
                        pairing_code: (page == "pairing").then(|| "TESTABCD".to_owned()),
                        folders: vec![],
                    },
                });
                app.permissions = vec![Some((
                    true,
                    vec![
                        "world_facts".into(),
                        "own_runs".into(),
                        "own_character".into(),
                        "own_track".into(),
                    ],
                ))];
                let mut renderer = preview::SoftwareRenderer::default();
                for _ in 0..3 {
                    let input = egui::RawInput {
                        screen_rect: Some(egui::Rect::from_min_size(
                            egui::Pos2::ZERO,
                            egui::vec2(680.0, 660.0),
                        )),
                        ..Default::default()
                    };
                    let output_frame = ctx.run_ui(input, |ui| app.show(ui));
                    renderer.render(
                        &ctx,
                        output_frame,
                        680,
                        660,
                        &PathBuf::from(output).join(format!(
                            "bridge-{page}-{}.png",
                            if cs { "cs" } else { "en" }
                        )),
                    )?;
                }
            }
        }
        return Ok(());
    }
    if !args.iter().any(|a| a == "--connection-settings") {
        evertally_sync::app_update::set_current_version(env!("CARGO_PKG_VERSION"));
        return evertally_sync::run().map_err(|e| e.to_string());
    }
    let Some(_instance) = platform::single_instance_named("Local\\EvertallyConnectionSettings")
    else {
        return Ok(());
    };
    // Opening settings from Start also starts the tray bridge; its mutex prevents duplicates.
    let executable = std::env::current_exe().map_err(|e| e.to_string())?;
    std::process::Command::new(executable)
        .spawn()
        .map_err(|e| e.to_string())?;
    let paths = Paths::new().map_err(|e| e.to_string())?;
    let (config, error) = match config::load_config(&paths.config) {
        Ok(config) => (config, None),
        Err(error) => (Config::default(), Some(error.to_string())),
    };
    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_title("Evertally — spojení")
            .with_inner_size([680.0, 660.0])
            .with_min_inner_size([600.0, 500.0]),
        ..Default::default()
    };
    eframe::run_native(
        "Evertally Bridge",
        options,
        Box::new(move |cc| {
            style(&cc.egui_ctx);
            let first = !prefs::load(&paths.dir).onboarded || std::env::args().any(|a| a == "--onboarding");
            let mut app =
                ConnectionSettings::new(paths.config, config, platform::prefers_czech(), false);
            if first { app.wizard = Some(0); }
            app.message = error.map(|e| (e, true));
            Ok(Box::new(app))
        }),
    )
    .map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn pairing_links_stay_on_the_configured_origin_and_reject_markup() {
        assert_eq!(
            approval_url("https://evertally.afstudio.dev", "TEST-ABCD").as_deref(),
            Some("https://evertally.afstudio.dev/link?code=TEST-ABCD")
        );
        assert!(approval_url("https://evertally.afstudio.dev", "a&next=evil").is_none());
        assert!(approval_url("http://insecure.example", "TESTABCD").is_none());
    }
    #[test]
    fn game_folder_is_recognised_whatever_the_case_of_wow_exe() {
        let root = std::env::temp_dir().join(format!("evertally-validate-test-{}", std::process::id()));
        std::fs::create_dir_all(root.join("_forever_")).unwrap();
        std::fs::write(root.join("_forever_/WOW.EXE"), b"").unwrap();
        let config = |path: PathBuf| Config { server: "https://evertally.afstudio.dev".into(), wow_path: Some(path) };
        assert!(validate(&config(root.clone())).is_ok());
        assert!(validate(&config(root.join("_forever_"))).is_ok());
        assert!(validate(&config(root.join("missing"))).is_err());
        std::fs::remove_dir_all(&root).unwrap();
    }

    #[test]
    fn the_native_macos_app_bundle_counts_as_the_game() {
        let root = std::env::temp_dir().join(format!("evertally-validate-app-{}", std::process::id()));
        std::fs::create_dir_all(root.join("_forever_/World of Warcraft.app")).unwrap();
        let config = |path: PathBuf| Config { server: "https://evertally.afstudio.dev".into(), wow_path: Some(path) };
        assert!(validate(&config(root.clone())).is_ok());
        assert!(validate(&config(root.join("_forever_"))).is_ok());
        std::fs::remove_dir_all(&root).unwrap();
    }

    #[test]
    fn refuses_insecure_servers_and_non_game_paths() {
        assert!(
            validate(&Config {
                server: "http://example.com".into(),
                wow_path: None
            })
            .is_err()
        );
        assert!(
            validate(&Config {
                server: "https://evertally.afstudio.dev".into(),
                wow_path: Some(PathBuf::from("missing-test-game"))
            })
            .is_err()
        );
        assert!(
            validate(&Config {
                server: "https://evertally.afstudio.dev".into(),
                wow_path: None
            })
            .is_ok()
        );
    }
}

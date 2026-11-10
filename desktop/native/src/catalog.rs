//! Installed reference data, kept separate from the user's observations.
use crate::{
    identity::{self, Icons},
    model,
};
use eframe::egui::{self, Color32, RichText};
use serde_json::Value;
use std::collections::BTreeMap;

const KINDS: [(&str, &str, &str); 5] = [
    ("items", "Items", "Itemy"),
    ("quests", "Quests", "Questy"),
    ("npcs", "NPC & services", "NPC a služby"),
    ("instances", "Dungeons & raids", "Dungeony a raidy"),
    ("guides", "Guides", "Návody"),
];

pub struct Database {
    tables: BTreeMap<String, Vec<Value>>,
    errors: Vec<String>,
    kind: usize,
    query: String,
    selected: Option<Value>,
    last_filter: Option<(usize, String)>,
    matching: Vec<usize>,
}

impl Database {
    pub fn new() -> Self {
        let mut db = Self {
            tables: BTreeMap::new(),
            errors: vec![],
            kind: 0,
            query: String::new(),
            selected: None,
            last_filter: None,
            matching: vec![],
        };
        if let Some(root) = identity::resource_root() {
            for (key, _, _) in KINDS {
                let file = root.join("catalog").join(format!("{key}.json"));
                let data = std::fs::metadata(&file)
                    .ok()
                    .filter(|m| m.len() <= 64 * 1024 * 1024)
                    .and_then(|_| std::fs::read(&file).ok())
                    .and_then(|bytes| serde_json::from_slice::<Value>(&bytes).ok());
                if let Some(data) = data.filter(|d| d["schemaVersion"] == 1)
                    && let Some(entries) = data["entries"].as_array()
                {
                    db.tables.insert(key.into(), entries.clone());
                    continue;
                }
                db.errors.push(key.into());
            }
        }
        db
    }

    pub fn show(&mut self, ui: &mut egui::Ui, icons: &Icons, cs: bool) {
        let t = |en, cz| if cs { cz } else { en };
        ui.horizontal_wrapped(|ui| {
            for (index, (key, en, cz)) in KINDS.iter().enumerate() {
                let count = self.tables.get(*key).map_or(0, Vec::len);
                if ui
                    .selectable_value(&mut self.kind, index, format!("{} · {count}", t(*en, *cz)))
                    .changed()
                {
                    self.selected = None;
                    self.query.clear();
                }
            }
        });
        ui.add_space(10.0);
        ui.add(
            egui::TextEdit::singleline(&mut self.query)
                .hint_text(t(
                    "Search name, ID, level or source…",
                    "Hledat název, ID, úroveň nebo zdroj…",
                ))
                .desired_width(f32::INFINITY),
        );
        ui.weak(t("Reference catalog from installed resources. Your own sightings are in Collected data.","Referenční databáze z instalovaných podkladů. Vlastní pozorování jsou v Nasbíraných datech."));
        let (key, _, _) = KINDS[self.kind];
        let entries = self.tables.get(key).map(Vec::as_slice).unwrap_or(&[]);
        if entries.is_empty() {
            ui.add_space(18.0);
            ui.heading(t(
                "No reference entries installed",
                "Referenční záznamy nejsou nainstalované",
            ));
            ui.label(t("Install or update the data resource package. Nothing is invented from missing data.","Nainstaluj nebo aktualizuj datové podklady. Chybějící data se nedoplňují odhadem."));
            if self.errors.iter().any(|error| error == key) {
                ui.weak(t(
                    "The matching resource file is missing or invalid.",
                    "Příslušný datový soubor chybí nebo není platný.",
                ));
            }
            return;
        }
        let query = self.query.trim().to_lowercase();
        if self.last_filter.as_ref() != Some(&(self.kind, query.clone())) {
            self.matching = entries
                .iter()
                .enumerate()
                .filter(|(_, entry)| {
                    query.is_empty() || entry.to_string().to_lowercase().contains(&query)
                })
                .map(|(index, _)| index)
                .collect();
            self.last_filter = Some((self.kind, query));
        }
        ui.label(format!(
            "{}: {} / {}",
            t("Results", "Výsledky"),
            self.matching.len(),
            entries.len()
        ));
        if let Some(selected) = &self.selected {
            egui::Frame::new()
                .fill(Color32::from_rgb(33, 28, 46))
                .corner_radius(8)
                .inner_margin(16)
                .show(ui, |ui| {
                    let name = entry_name(selected);
                    ui.heading(name);
                    if let Some(id) = selected["id"].as_u64().filter(|_| key == "items") {
                        icons.show(ui, "items", Some(id), 48.0, name);
                    }
                    if let Some(source) = selected["sourceLabel"].as_str() {
                        ui.weak(source);
                    }
                    for (field, en, cz) in [
                        ("id", "ID", "ID"),
                        ("level", "Level", "Úroveň"),
                        ("requiredLevel", "Required level", "Potřebná úroveň"),
                        ("minLevel", "Minimum level", "Minimální úroveň"),
                        ("maxLevel", "Maximum level", "Maximální úroveň"),
                        ("itemLevel", "Item level", "Úroveň itemu"),
                        ("slot", "Slot", "Slot"),
                        ("className", "Type", "Typ"),
                        ("quality", "Quality", "Kvalita"),
                        ("type", "Category", "Kategorie"),
                    ] {
                        if let Some(value) = selected.get(field).filter(|v| !v.is_null()) {
                            ui.label(format!("{}: {}", t(en, cz), display(value)));
                        }
                    }
                    for field in ["description", "body", "objective", "text"] {
                        if let Some(value) = selected[field].as_str() {
                            ui.label(value);
                        }
                    }
                    for (field, en, cz) in [
                        ("objectives", "Objectives", "Cíle"),
                        ("starts", "Quest givers", "Zadavatelé"),
                        ("ends", "Turn-in NPCs", "Odevzdání"),
                        ("startsQuests", "Starts quests", "Zadává questy"),
                        ("endsQuests", "Ends quests", "Přijímá questy"),
                        ("bosses", "Bosses", "Bossové"),
                        ("loot", "Loot", "Kořist"),
                        ("sources", "Sources", "Zdroje"),
                    ] {
                        if let Some(values) = selected[field].as_array().filter(|v| !v.is_empty()) {
                            ui.label(RichText::new(t(en, cz)).strong());
                            for value in values.iter().take(100) {
                                ui.label(format!("• {}", display(value)));
                            }
                        }
                    }
                    if let Some(steps) = selected["steps"].as_array() {
                        for (i, step) in steps.iter().enumerate() {
                            ui.add_space(8.0);
                            ui.label(
                                RichText::new(format!(
                                    "{}. {}",
                                    i + 1,
                                    step["title"].as_str().unwrap_or("")
                                ))
                                .strong(),
                            );
                            if let Some(body) = step["body"].as_str() {
                                ui.label(body);
                            }
                        }
                    }
                    // Coordinates are excluded even from the reference-data debug panel.
                    egui::CollapsingHeader::new(t("Reference fields", "Referenční pole")).show(
                        ui,
                        |ui| {
                            ui.add(
                                egui::Label::new(
                                    RichText::new(
                                        serde_json::to_string_pretty(&model::without_coordinates(
                                            selected,
                                        ))
                                        .unwrap_or_default(),
                                    )
                                    .monospace()
                                    .size(11.0),
                                )
                                .wrap(),
                            );
                        },
                    );
                });
            if ui
                .small_button(t("Close details", "Zavřít podrobnosti"))
                .clicked()
            {
                self.selected = None;
            }
            ui.add_space(12.0);
        }
        egui::ScrollArea::vertical()
            .id_salt("catalog-results")
            .max_height(600.0)
            .show(ui, |ui| {
                for entry in self.matching.iter().take(250).map(|index| &entries[*index]) {
                    ui.horizontal(|ui| {
                        if key == "items" {
                            icons.show(ui, "items", entry["id"].as_u64(), 30.0, entry_name(entry));
                        }
                        if ui
                            .selectable_label(
                                self.selected
                                    .as_ref()
                                    .is_some_and(|selected| selected["id"] == entry["id"]),
                                entry_name(entry),
                            )
                            .clicked()
                        {
                            self.selected = Some(entry.clone());
                        }
                        ui.weak(format!("#{}", display(&entry["id"])));
                        if let Some(level) = entry["level"]
                            .as_u64()
                            .or_else(|| entry["requiredLevel"].as_u64())
                        {
                            ui.weak(format!("Lv. {level}"));
                        }
                    });
                    ui.separator();
                }
            });
        if self.matching.len() > 250 {
            ui.weak(t(
                "Showing the first 250 matches. Refine the search to find another record.",
                "Zobrazuje se prvních 250 shod. Upřesni hledání pro další záznamy.",
            ));
        }
    }
}

pub fn entry_name(entry: &Value) -> &str {
    entry["name"]
        .as_str()
        .or_else(|| entry["title"].as_str())
        .unwrap_or("—")
}
fn display(value: &Value) -> String {
    match value {
        Value::String(text) => text.clone(),
        _ => value.to_string(),
    }
}

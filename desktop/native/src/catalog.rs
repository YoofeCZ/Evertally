//! Installed reference data, kept separate from the user's observations.
use crate::{
    identity::{self, Icons},
    model,
};
use eframe::egui::{self, Color32, RichText};
use serde_json::{Value, json};
use std::{
    collections::BTreeMap,
    path::{Path, PathBuf},
};

const KINDS: [(&str, &str, &str); 6] = [
    ("items", "Items", "Itemy"),
    ("quests", "Quests", "Questy"),
    ("npcs", "NPC & services", "NPC a služby"),
    ("instances", "Dungeons & raids", "Dungeony a raidy"),
    ("recipes", "Recipes", "Recepty"),
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
    db_root: Option<PathBuf>,
}

// The web and desktop use the same compact search index and the same detail shards.
fn search_entries(data: &Value, kind: &str) -> Option<Vec<Value>> {
    let rows = data[kind].as_array()?;
    Some(rows.iter().filter_map(|value| {
        let row = value.as_array()?;
        let id = row.first()?.as_u64()?;
        let name = row.get(1)?.as_str()?;
        let shard = match kind { "items" | "npcs" => row.get(7), "quests" => row.get(6), _ => None }?;
        let mut entry = json!({"id":id, "name":name, "shard":shard, "sourceLabel":"Evertally reference database"});
        match kind {
            "items" => { entry["quality"] = row.get(2)?.clone(); entry["itemLevel"] = row.get(3)?.clone(); entry["requiredLevel"] = row.get(4)?.clone(); }
            "npcs" => { entry["minLevel"] = row.get(2)?.clone(); entry["maxLevel"] = row.get(3)?.clone(); entry["services"] = row.get(5)?.clone(); }
            "quests" => { entry["level"] = row.get(2)?.clone(); entry["requiredLevel"] = row.get(3)?.clone(); }
            _ => return None,
        }
        Some(entry)
    }).collect())
}

fn detail(root: &Path, kind: &str, entry: &Value) -> Option<Value> {
    let shard = entry["shard"].as_u64()?;
    let id = entry["id"].as_u64()?;
    let path = root.join(kind).join(format!("{shard}.json"));
    if std::fs::metadata(&path).ok()?.len() > 8 * 1024 * 1024 {
        return None;
    }
    let data: Value = serde_json::from_slice(&std::fs::read(path).ok()?).ok()?;
    let mut full = data.get(id.to_string())?.clone();
    let object = full.as_object_mut()?;
    object.insert("shard".into(), json!(shard));
    // Reuse labels and details already present in the native catalogue.
    for (short, long) in [
        ("q", "quality"),
        ("ilvl", "itemLevel"),
        ("req", "requiredLevel"),
        ("lvl", "level"),
        ("src", "sources"),
        ("startNpc", "starts"),
        ("endNpc", "ends"),
    ] {
        if let Some(value) = object.get(short).cloned() {
            object.entry(long).or_insert(value);
        }
    }
    Some(full)
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
            db_root: None,
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
            let web_db = root.join("db");
            if let Some(search) = std::fs::read(web_db.join("search.json"))
                .ok()
                .and_then(|bytes| serde_json::from_slice::<Value>(&bytes).ok())
            {
                for key in ["items", "npcs", "quests"] {
                    if let Some(entries) = search_entries(&search, key) {
                        db.tables.insert(key.into(), entries);
                    }
                }
                db.db_root = Some(web_db.clone());
            }
            for (file, kind, field) in [
                ("dungeons.json", "instances", "entries"),
                ("recipes.json", "recipes", "recipes"),
            ] {
                if let Some(entries) = std::fs::read(web_db.join(file))
                    .ok()
                    .and_then(|bytes| serde_json::from_slice::<Value>(&bytes).ok())
                    .and_then(|data| data[field].as_array().cloned())
                {
                    db.tables.insert(kind.into(), entries);
                }
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
                        } else if let Some(values) = selected[field].as_array() {
                            for value in values.iter().filter_map(Value::as_str) {
                                ui.label(value);
                            }
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
                        ("reagents", "Materials", "Suroviny"),
                        ("rewards", "Rewards", "Odměny"),
                        ("tips", "Tips", "Tipy"),
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
                                    step["title"]
                                        .as_str()
                                        .or_else(|| step[0].as_str())
                                        .unwrap_or("")
                                ))
                                .strong(),
                            );
                            if let Some(body) = step["body"].as_str().or_else(|| step[1].as_str()) {
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
                                self.selected.as_ref().is_some_and(|selected| {
                                    if !entry["id"].is_null() {
                                        selected["id"] == entry["id"]
                                    } else {
                                        selected["key"] == entry["key"] && !entry["key"].is_null()
                                    }
                                }),
                                entry_name(entry),
                            )
                            .clicked()
                        {
                            self.selected = Some(
                                self.db_root
                                    .as_ref()
                                    .and_then(|root| detail(root, key, entry))
                                    .unwrap_or_else(|| entry.clone()),
                            );
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn web_search_index_becomes_desktop_entries_without_losing_shard() {
        let data = json!({"items": [[25,"Sword",2,4,1,0,0,7,1]], "npcs": [[9,"Guard",4,6,0,["vendor"],1,3,"zone"]], "quests": [[12,"Find it",5,3,"zone","A",2]]});
        let items = search_entries(&data, "items").unwrap();
        assert_eq!(items[0]["name"], "Sword");
        assert_eq!(items[0]["shard"], 7);
        assert_eq!(items[0]["itemLevel"], 4);
        assert_eq!(
            search_entries(&data, "npcs").unwrap()[0]["services"][0],
            "vendor"
        );
        assert_eq!(search_entries(&data, "quests").unwrap()[0]["shard"], 2);
    }
}

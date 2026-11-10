//! Explicitly refreshed public summaries. Never receives or persists player coordinates.
use crate::{identity, model};
use eframe::egui::{self, RichText};
use evertally_sync::config::Config;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{
    collections::HashMap,
    path::PathBuf,
    sync::mpsc::{self, Receiver},
    time::{Duration, SystemTime, UNIX_EPOCH},
};

const MAX_BYTES: u64 = 2 * 1024 * 1024;
#[derive(Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Entry {
    name: String,
    class_id: Option<u64>,
    race_id: Option<u64>,
    count: u64,
}
#[derive(Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Zone {
    map_id: u64,
    contributors: u64,
    observations: u64,
}
#[derive(Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Snapshot {
    origin: String,
    fetched_at: u64,
    entries: Vec<Entry>,
    zones: Vec<Zone>,
    window_hours: u64,
    min_contributors: u64,
}
fn short(value: &Value) -> String {
    value
        .as_str()
        .unwrap_or("")
        .chars()
        .filter(|c| !c.is_control() && *c != '|')
        .take(160)
        .collect()
}
fn id(value: &Value) -> Option<u64> {
    value.as_u64().filter(|v| (1..=100).contains(v))
}

fn project(origin: String, rankings: &Value, activity: &Value) -> Result<Snapshot, String> {
    let list = rankings["entries"]
        .as_array()
        .ok_or("Invalid rankings response")?;
    let areas = activity["zones"]
        .as_array()
        .ok_or("Invalid zone activity response")?;
    let threshold = activity["minContributors"].as_u64().unwrap_or(3).max(3);
    let entries = list
        .iter()
        .take(200)
        .filter_map(|row| {
            let count = row["count"].as_u64().filter(|v| *v <= 1_000_000_000)?;
            let name = short(&row["character"]["name"]);
            Some(Entry {
                name: if name.is_empty() { "—".into() } else { name },
                count,
                class_id: id(&row["character"]["classId"]),
                race_id: id(&row["character"]["raceId"]),
            })
        })
        .collect();
    let zones = areas
        .iter()
        .take(1000)
        .filter_map(|row| {
            if row["mapSystem"] != "ui_map" {
                return None;
            }
            let map_id = row["mapId"]
                .as_u64()
                .filter(|v| *v > 0 && *v <= 1_000_000)?;
            let contributors = row["contributors"]
                .as_u64()
                .filter(|v| *v >= threshold && *v <= 1_000_000_000)?;
            Some(Zone {
                map_id,
                contributors,
                observations: row["observations"].as_u64().unwrap_or(0).min(1_000_000_000),
            })
        })
        .collect();
    Ok(Snapshot {
        origin,
        entries,
        zones,
        min_contributors: threshold,
        window_hours: activity["windowHours"].as_u64().unwrap_or(24).clamp(1, 168),
        fetched_at: SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_or(0, |v| v.as_secs()),
    })
}

fn fetch(origin: String) -> Result<Snapshot, String> {
    let agent: ureq::Agent = ureq::Agent::config_builder()
        .timeout_global(Some(Duration::from_secs(15)))
        .max_redirects(0)
        .build()
        .into();
    let get = |path: &str| -> Result<Value, String> {
        let mut response = agent
            .get(format!("{origin}{path}"))
            .call()
            .map_err(|error| error.to_string())?;
        response
            .body_mut()
            .with_config()
            .limit(MAX_BYTES)
            .read_json::<Value>()
            .map_err(|error| error.to_string())
    };
    project(
        origin.clone(),
        &get("/api/leaderboards?metric=count")?,
        &get("/api/activity")?,
    )
}

pub struct Community {
    cache: PathBuf,
    snapshot: Option<Snapshot>,
    pending: Option<Receiver<Result<Snapshot, String>>>,
    error: Option<String>,
    zone_names: HashMap<u64, String>,
}
impl Community {
    pub fn new(cache: PathBuf) -> Self {
        let snapshot = std::fs::metadata(&cache)
            .ok()
            .filter(|m| m.len() <= MAX_BYTES)
            .and_then(|_| std::fs::read(&cache).ok())
            .and_then(|b| serde_json::from_slice::<Snapshot>(&b).ok())
            .filter(|s| s.entries.len() <= 200 && s.zones.len() <= 1000 && s.min_contributors >= 3)
            .map(|mut s| {
                s.zones.retain(|z| z.contributors >= s.min_contributors);
                s
            });
        let maps = identity::resource_root()
            .and_then(|p| std::fs::read(p.join("maps/manifest.json")).ok())
            .and_then(|b| serde_json::from_slice::<Value>(&b).ok());
        let zone_names = maps
            .as_ref()
            .and_then(|v| v["maps"].as_array())
            .into_iter()
            .flatten()
            .flat_map(|m| {
                let name = short(&m["nameEn"]);
                m["uiMapIds"]
                    .as_array()
                    .into_iter()
                    .flatten()
                    .filter_map(Value::as_u64)
                    .map(move |id| (id, name.clone()))
            })
            .collect();
        Self {
            cache,
            snapshot,
            pending: None,
            error: None,
            zone_names,
        }
    }
    pub fn show(
        &mut self,
        ui: &mut egui::Ui,
        config: &Config,
        icons: &identity::Icons,
        cs: bool,
        offline_preview: bool,
    ) {
        let t = |en, cz| if cs { cz } else { en };
        let origin = config.server_origin();
        if let Some(receiver) = &self.pending {
            match receiver.try_recv() {
                Ok(result) => {
                    self.pending = None;
                    match result {
                        Ok(snapshot) => {
                            if !offline_preview && let Ok(bytes) = serde_json::to_vec(&snapshot) {
                                let _ = std::fs::write(&self.cache, bytes);
                            }
                            self.snapshot = Some(snapshot);
                            self.error = None;
                        }
                        Err(error) => self.error = Some(error),
                    }
                }
                Err(mpsc::TryRecvError::Disconnected) => {
                    self.pending = None;
                    self.error = Some(
                        t(
                            "The request stopped. Try again.",
                            "Načítání se zastavilo. Zkus to znovu.",
                        )
                        .into(),
                    );
                }
                Err(mpsc::TryRecvError::Empty) => {}
            }
        }
        ui.horizontal_wrapped(|ui| {
            if ui
                .add_enabled(
                    !offline_preview && self.pending.is_none() && origin.is_ok(),
                    egui::Button::new(t("Refresh community data", "Načíst komunitní data")),
                )
                .clicked()
                && let Ok(origin) = &origin
            {
                let (tx, rx) = mpsc::channel();
                let origin = origin.clone();
                let context = ui.ctx().clone();
                self.pending = Some(rx);
                std::thread::spawn(move || {
                    let _ = tx.send(fetch(origin));
                    context.request_repaint();
                });
            }
            if self.pending.is_some() {
                ui.spinner();
                ui.label(t("Loading…", "Načítání…"));
            }
        });
        if offline_preview {
            ui.label(t(
                "Offline preview. No web requests are made.",
                "Místní náhled. Žádné webové požadavky se neodesílají.",
            ));
        }
        if let Err(error) = &origin {
            ui.colored_label(crate::DANGER, error.to_string());
        }
        if let Some(error) = &self.error {
            ui.colored_label(
                crate::DANGER,
                format!("{} {error}", t("Could not refresh:", "Nelze obnovit:")),
            );
        }
        let Some(snapshot) = self
            .snapshot
            .as_ref()
            .filter(|s| origin.as_ref().is_ok_and(|o| *o == s.origin))
        else {
            ui.add_space(20.);
            ui.label(t("Refresh to load public rankings and zone summaries. Your own history remains offline.","Načti veřejné žebříčky a souhrny oblastí. Vlastní historie zůstává dostupná offline."));
            return;
        };
        ui.label(
            RichText::new(format!(
                "{} {} · {}",
                t("Cached snapshot", "Uložený snímek"),
                evertally_sync::config::utc_timestamp(
                    UNIX_EPOCH + Duration::from_secs(snapshot.fetched_at)
                ),
                snapshot.origin
            ))
            .small()
            .color(crate::MUTED),
        );
        ui.add_space(18.);
        ui.heading(t(
            "Completed dungeon participations",
            "Dokončené účasti ve výpravách",
        ));
        ui.label(t("Only shared completed participations. Several party members can each report the same group run. Speed records remain disabled until game rules are verified.","Pouze sdílené dokončené účasti. Více členů skupiny může zaznamenat stejný průchod. Rychlostní rekordy čekají na ověření herních pravidel."));
        if snapshot.entries.is_empty() {
            ui.label(t(
                "No public completed runs yet.",
                "Zatím nejsou veřejné dokončené výpravy.",
            ));
        }
        egui::Grid::new("community-rankings")
            .striped(true)
            .spacing([14., 10.])
            .show(ui, |ui| {
                for (index, entry) in snapshot.entries.iter().enumerate() {
                    ui.label(format!("#{}", index + 1));
                    ui.horizontal(|ui| {
                        icons.show(
                            ui,
                            "classes",
                            entry.class_id,
                            23.,
                            model::class_name(entry.class_id),
                        );
                        icons.show(
                            ui,
                            "races",
                            entry.race_id,
                            23.,
                            model::race_name(entry.race_id),
                        );
                        ui.label(&entry.name);
                    });
                    ui.label(entry.count.to_string());
                    ui.end_row();
                }
            });
        ui.add_space(24.);
        ui.heading(t("Visited-zone activity", "Aktivita navštívených oblastí"));
        ui.label(format!(
            "{} {} {} · {} {}",
            t("Last", "Posledních"),
            snapshot.window_hours,
            t("hours", "hodin"),
            t(
                "Minimum contributors per zone:",
                "Nejméně přispěvatelů v oblasti:"
            ),
            snapshot.min_contributors
        ));
        ui.label(t("Distinct contributing accounts with recorded visits. These are not online counts or realm population. No names, player pins or exact player positions are available.","Různé zapojené účty se zaznamenanou návštěvou. Nejde o online hráče ani populaci realmu. Neobsahuje jména, hráčské piny nebo přesné pozice hráčů."));
        if snapshot.zones.is_empty() {
            ui.label(t(
                "No zone meets the publication threshold yet.",
                "Žádná oblast zatím nedosáhla hranice pro zveřejnění.",
            ));
        }
        egui::Grid::new("community-zones")
            .striped(true)
            .spacing([24., 10.])
            .show(ui, |ui| {
                ui.strong(t("Zone", "Oblast"));
                ui.strong(t("Contributors", "Přispěvatelé"));
                ui.strong(t("Visits", "Návštěvy"));
                ui.end_row();
                for zone in &snapshot.zones {
                    ui.label(
                        self.zone_names
                            .get(&zone.map_id)
                            .cloned()
                            .unwrap_or_else(|| format!("Map #{}", zone.map_id)),
                    );
                    ui.label(zone.contributors.to_string());
                    ui.label(zone.observations.to_string());
                    ui.end_row();
                }
            });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn activity_strips_identities_coordinates_and_small_groups() {
        let value=project("https://example.test".into(),&serde_json::json!({"entries":[]}),&serde_json::json!({"minContributors":1,"zones":[{"mapId":1426,"mapSystem":"ui_map","contributors":3,"observations":7,"x":0.5,"name":"Secret"},{"mapId":1411,"mapSystem":"ui_map","contributors":2,"observations":2}]})).unwrap();
        assert_eq!(value.zones.len(), 1);
        let json = serde_json::to_string(&value).unwrap();
        assert!(!json.contains("Secret"));
        assert!(!json.contains("\"x\""));
        assert_eq!(value.min_contributors, 3);
    }
    #[test]
    fn rankings_are_bounded_and_keep_only_public_identity_fields() {
        let row = serde_json::json!({"character":{"name":"Test","classId":1,"raceId":2,"x":0.9,"token":"secret"},"count":4});
        let value = project(
            "https://example.test".into(),
            &serde_json::json!({"entries":vec![row;250]}),
            &serde_json::json!({"zones":[]}),
        )
        .unwrap();
        assert_eq!(value.entries.len(), 200);
        assert_eq!(value.entries[0].count, 4);
        assert!(!serde_json::to_string(&value).unwrap().contains("secret"));
    }
}

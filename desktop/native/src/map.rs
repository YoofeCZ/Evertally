//! Offline zone maps and world observations. No character coordinates or live tracking.
use std::{
    collections::{BTreeMap, HashMap},
    path::Path,
};

use eframe::egui::{self, Color32, Pos2, Rect, RichText, Stroke, TextureHandle, Vec2};
use evertally_sync::local::AccountData;
use serde::Deserialize;
use serde_json::Value;

use crate::{identity, model};

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Zone {
    pub key: String,
    pub name_en: String,
    pub name_cs: String,
    pub image: String,
    pub width: u32,
    pub height: u32,
    #[serde(default)]
    pub ui_map_ids: Vec<u64>,
    #[serde(default)]
    pub bounds: Option<ZoneBounds>,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ZoneBounds {
    pub parent_key: String,
    pub x: f32,
    pub y: f32,
    pub width: f32,
    pub height: f32,
}

impl Zone {
    fn label(&self, cs: bool) -> &str {
        if cs { &self.name_cs } else { &self.name_en }
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Catalog {
    schema_version: u64,
    maps: Vec<Zone>,
}

#[derive(Clone, Debug, Deserialize)]
struct WorldArt {
    kind: String,
    rect: [f32; 4],
}

#[derive(Deserialize)]
struct WorldArtIndex {
    schema: u64,
    maps: HashMap<String, WorldArt>,
}

fn art_opacity(kind: &str, zoom: f32, width: f32) -> f32 {
    if kind == "continent" {
        let z = zoom.log2();
        ((z - 0.05) / 0.3)
            .clamp(0.0, 1.0)
            .min((1.0 - (z - 2.4) / 0.9).clamp(0.0, 1.0))
    } else {
        ((width - 220.0) / 260.0).clamp(0.0, 1.0)
    }
}

fn art_mesh(
    texture: egui::TextureId,
    rect: Rect,
    world: [f32; 4],
    opacity: f32,
    kind: &str,
) -> egui::Mesh {
    let [left, right, top, bottom] = world;
    let mut mesh = egui::Mesh::with_texture(texture);
    let feather = if kind == "continent" {
        0.12
    } else if kind == "city" {
        0.14
    } else {
        0.08
    };
    let coords = [0.0_f32, feather, 1.0 - feather, 1.0];
    for &v in &coords {
        for &u in &coords {
            let x = if (u == 0.0 && (kind != "continent" || left > 0.0))
                || (u == 1.0 && (kind != "continent" || right < 1.0))
            {
                0.0
            } else {
                1.0
            };
            let y = if (v == 0.0 && (kind != "continent" || top > 0.0))
                || (v == 1.0 && (kind != "continent" || bottom < 1.0))
            {
                0.0
            } else {
                1.0
            };
            mesh.vertices.push(egui::epaint::Vertex {
                pos: rect.min + Vec2::new(u * rect.width(), v * rect.height()),
                uv: Pos2::new(u, v),
                color: Color32::from_white_alpha((opacity * x * y * 255.0).round() as u8),
            });
        }
    }
    for y in 0..3_u32 {
        for x in 0..3_u32 {
            let a = y * 4 + x;
            mesh.add_triangle(a, a + 1, a + 4);
            mesh.add_triangle(a + 1, a + 5, a + 4);
        }
    }
    mesh
}

#[derive(Clone, Debug)]
pub struct Point {
    pub name: String,
    pub kind: String,
    pub id: u64,
    pub x: f32,
    pub y: f32,
    pub exact: bool,
    pub count: usize,
    pub database: bool,
    pub source: String,
}

pub fn points(accounts: &[&AccountData], zone: &Zone, filter: u8, query: &str) -> Vec<Point> {
    let mut points: BTreeMap<String, Point> = BTreeMap::new();
    for event in accounts.iter().flat_map(|a| &a.events) {
        let p = &event["payload"];
        let kind = match event["kind"].as_str().unwrap_or("") {
            "npc.observed" => "npc",
            "vendor.snapshot" => "vendor",
            "quest.accepted" | "quest.completed" | "quest.rewarded" | "quest.turned_in" => "quest",
            _ => continue,
        };
        // A player interaction is the player's exact location, not an NPC spawn.
        // It must never become a map marker, even for historical observations.
        if p["positionMethod"] != "unit_position" {
            continue;
        }
        if filter != 0 && !matches!((filter, kind), (1, "npc") | (2, "quest") | (3, "vendor")) {
            continue;
        }
        // All historical collectors used C_Map; explicit other namespaces must not collide.
        if p["mapSystem"].as_str().is_some_and(|s| s != "ui_map")
            || !zone.ui_map_ids.contains(&p["mapId"].as_u64().unwrap_or(0))
        {
            continue;
        }
        let (Some(x), Some(y)) = (p["x"].as_f64(), p["y"].as_f64()) else {
            continue;
        };
        if !x.is_finite()
            || !y.is_finite()
            || !(0.0..=1.0).contains(&x)
            || !(0.0..=1.0).contains(&y)
            || (x == 0.0 && y == 0.0)
        {
            continue;
        }
        let id = p[if kind == "quest" { "questId" } else { "npcId" }]
            .as_u64()
            .unwrap_or(0);
        let name = p["name"]
            .as_str()
            .filter(|s| !s.is_empty())
            .map_or_else(|| format!("{kind} #{id}"), str::to_owned);
        if !query.trim().is_empty()
            && !name.to_lowercase().contains(&query.to_lowercase())
            && !id.to_string().contains(query.trim())
        {
            continue;
        }
        let exact = p["positionMethod"] == "unit_position";
        let key = format!("{kind}:{id}:{:.4}:{:.4}:{exact}", x, y);
        let entry = points.entry(key).or_insert(Point {
            name,
            kind: kind.to_owned(),
            id,
            x: x as f32,
            y: y as f32,
            exact,
            count: 0,
            database: false,
            source: String::new(),
        });
        entry.count += 1;
    }
    points.into_values().take(5000).collect()
}

/// Only the installed reference catalog may supply `npc_database` locations.
fn database_points(entries: &[Value], zone: &Zone, filter: u8, query: &str) -> Vec<Point> {
    let mut points = Vec::new();
    for entry in entries {
        let quest_giver = entry["startsQuests"]
            .as_array()
            .is_some_and(|v| !v.is_empty())
            || entry["endsQuests"]
                .as_array()
                .is_some_and(|v| !v.is_empty());
        let vendor = entry["isVendor"].as_bool() == Some(true)
            || entry["vendor"].as_bool() == Some(true)
            || entry["services"]
                .as_array()
                .is_some_and(|s| s.iter().any(|v| v == "vendor"));
        if (filter == 2 && !quest_giver) || (filter == 3 && !vendor) || filter == 4 {
            continue;
        }
        let Some(id) = entry["id"].as_u64() else {
            continue;
        };
        let name = entry["name"].as_str().unwrap_or("NPC");
        if !query.trim().is_empty()
            && !name.to_lowercase().contains(&query.to_lowercase())
            && !id.to_string().contains(query.trim())
        {
            continue;
        }
        let Some(locations) = entry["locations"].as_array() else {
            continue;
        };
        for p in locations {
            if p["mapSystem"] != "ui_map"
                || p["positionMethod"] != "npc_database"
                || !zone.ui_map_ids.contains(&p["mapId"].as_u64().unwrap_or(0))
            {
                continue;
            }
            let (Some(x), Some(y)) = (p["x"].as_f64(), p["y"].as_f64()) else {
                continue;
            };
            if !x.is_finite()
                || !y.is_finite()
                || !(0.0..=1.0).contains(&x)
                || !(0.0..=1.0).contains(&y)
            {
                continue;
            }
            points.push(Point {
                name: name.into(),
                kind: if filter == 2 {
                    "quest"
                } else if vendor {
                    "vendor"
                } else {
                    "npc"
                }
                .into(),
                id,
                x: x as f32,
                y: y as f32,
                exact: true,
                count: 1,
                database: true,
                source: entry["sourceLabel"]
                    .as_str()
                    .unwrap_or("Reference catalog")
                    .into(),
            });
        }
    }
    points
}

#[derive(Default)]
pub struct WorldMap {
    zones: Vec<Zone>,
    error: Option<String>,
    selected: usize,
    textures: HashMap<String, Option<TextureHandle>>,
    zoom: f32,
    pan: Vec2,
    layer: u8,
    query: String,
    selected_point: Option<Point>,
    reference_npcs: Vec<Value>,
    reference_cache: Option<(usize, u8, String, Vec<Point>)>,
    world_art: HashMap<String, WorldArt>,
    preview_center: Option<[f32; 2]>,
}

impl WorldMap {
    pub fn new() -> Self {
        let mut map = Self {
            zoom: 1.0,
            ..Self::default()
        };
        let loaded = identity::resource_root()
            .ok_or("Map resources are missing")
            .and_then(|root| {
                let bytes = std::fs::read(root.join("maps/manifest.json"))
                    .map_err(|_| "Map catalog is missing")?;
                let catalog: Catalog =
                    serde_json::from_slice(&bytes).map_err(|_| "Map catalog is invalid")?;
                if catalog.schema_version != 1 || catalog.maps.is_empty() {
                    return Err("Unsupported or empty map catalog");
                }
                Ok(catalog
                    .maps
                    .into_iter()
                    .filter(|z| z.width > 0 && z.height > 0 && z.width <= 8192 && z.height <= 8192)
                    .collect::<Vec<_>>())
            });
        match loaded {
            Ok(zones) => map.zones = zones,
            Err(e) => map.error = Some(e.to_owned()),
        }
        map.world_art = identity::resource_root()
            .and_then(|root| std::fs::read(root.join("world/world.json")).ok())
            .and_then(|bytes| serde_json::from_slice::<WorldArtIndex>(&bytes).ok())
            .filter(|world| world.schema == 1)
            .map(|world| world.maps)
            .unwrap_or_default();
        // CPU-only preview can exercise zoom without touching a real window.
        if let Some(value) = std::env::args()
            .skip_while(|arg| arg != "--map-zoom")
            .nth(1)
            && let Ok(zoom) = value.parse::<f32>()
            && zoom.is_finite()
        {
            map.zoom = zoom.clamp(1.0, 8.0);
        }
        let mut center_args = std::env::args().skip_while(|arg| arg != "--map-center");
        if center_args.next().is_some()
            && let (Some(u), Some(v)) = (center_args.next(), center_args.next())
            && let (Ok(u), Ok(v)) = (u.parse::<f32>(), v.parse::<f32>())
            && u.is_finite()
            && v.is_finite()
        {
            map.preview_center = Some([u.clamp(0.0, 1.0), v.clamp(0.0, 1.0)]);
        }
        let mut args = std::env::args();
        if args.any(|arg| arg == "--map-zone")
            && let Some(id) = args.next().and_then(|s| s.parse::<u64>().ok())
            && let Some(index) = map.zones.iter().position(|z| z.ui_map_ids.contains(&id))
        {
            map.selected = index;
        }
        map.reference_npcs = identity::resource_root()
            .and_then(|root| std::fs::read(root.join("catalog/npcs.json")).ok())
            .and_then(|bytes| serde_json::from_slice::<Value>(&bytes).ok())
            .filter(|data| data["schemaVersion"] == 1)
            .and_then(|data| data["entries"].as_array().cloned())
            .unwrap_or_default();
        map
    }

    pub fn show(&mut self, ui: &mut egui::Ui, accounts: &[&AccountData], cs: bool) {
        let t = |en, cz| if cs { cz } else { en };
        if self.zones.is_empty() {
            ui.heading(t(
                "Map resources are not installed",
                "Mapové podklady nejsou nainstalované",
            ));
            ui.label(t("Install or repair the Evertally resource package. Local history stays available.","Nainstaluj nebo oprav mapové podklady Evertally. Místní historie zůstává dostupná."));
            if let Some(error) = &self.error {
                ui.weak(error);
            }
            return;
        }
        ui.horizontal_wrapped(|ui| {
            egui::ComboBox::from_id_salt("offline-zone")
                .selected_text(self.zones[self.selected].label(cs))
                .width(220.0)
                .show_ui(ui, |ui| {
                    for (i, zone) in self.zones.iter().enumerate() {
                        if ui
                            .selectable_value(&mut self.selected, i, zone.label(cs))
                            .changed()
                        {
                            self.zoom = 1.0;
                            self.pan = Vec2::ZERO;
                            self.selected_point = None;
                        }
                    }
                });
            for (value, en, cz) in [
                (0, "All world data", "Všechna světová data"),
                (1, "NPC", "NPC"),
                (2, "Quests", "Questy"),
                (3, "Vendors", "Obchodníci"),
                (4, "Visited zones", "Navštívené zóny"),
            ] {
                ui.selectable_value(&mut self.layer, value, t(en, cz));
            }
        });
        ui.horizontal(|ui| {
            ui.add(
                egui::TextEdit::singleline(&mut self.query)
                    .hint_text(t("Name or ID…", "Název nebo ID…"))
                    .desired_width(230.0),
            );
            if ui.button("−").clicked() {
                self.zoom = (self.zoom / 1.3).max(1.0);
            }
            if ui.button("+").clicked() {
                self.zoom = (self.zoom * 1.3).min(8.0);
            }
            if ui.button(t("Fit map", "Celá mapa")).clicked() {
                self.zoom = 1.0;
                self.pan = Vec2::ZERO;
            }
            ui.weak(format!("{:.0}%", self.zoom * 100.0));
        });
        ui.weak(t("Drag to pan · scroll to zoom · click a world marker. The desktop map does not yet show shared player positions.","Posun tažením · zoom kolečkem · klik na herní místo. Mapa v aplikaci zatím nezobrazuje sdílené polohy hráčů."));
        let zone = self.zones[self.selected].clone();
        let cache_key = (self.selected, self.layer, self.query.clone());
        if self
            .reference_cache
            .as_ref()
            .is_none_or(|(z, l, q, _)| (*z, *l, q) != (cache_key.0, cache_key.1, &cache_key.2))
        {
            self.reference_cache = Some((
                cache_key.0,
                cache_key.1,
                cache_key.2,
                database_points(&self.reference_npcs, &zone, self.layer, &self.query),
            ));
        }
        let mut points = self
            .reference_cache
            .as_ref()
            .map(|(_, _, _, points)| points.clone())
            .unwrap_or_default();
        points.extend(self::points(accounts, &zone, self.layer, &self.query));
        if self.layer == 4 {
            let visits = model::visited_zones(accounts, None);
            let found: Vec<_> = visits
                .iter()
                .filter(|v| zone.ui_map_ids.contains(&v.map_id))
                .collect();
            ui.label(t(
                "Recorded visits in this zone",
                "Uložené návštěvy v této zóně",
            ));
            for visit in &found {
                ui.label(format!(
                    "{} · {} {}",
                    visit.name,
                    visit.count,
                    t("visits", "návštěv")
                ));
            }
            if found.is_empty() {
                ui.weak(t("No recorded visit yet. This layer contains zone history, never player coordinates.","Zatím žádná uložená návštěva. Tato vrstva obsahuje historii zón, nikdy souřadnice hráčů."));
            }
        }
        let texture = self
            .textures
            .entry(zone.key.clone())
            .or_insert_with(|| load_texture(ui.ctx(), &zone))
            .clone();
        let desired = Vec2::new(ui.available_width().max(100.0), 480.0);
        let (viewport, response) = ui.allocate_exact_size(desired, egui::Sense::click_and_drag());
        let painter = ui.painter().with_clip_rect(viewport);
        painter.rect_filled(viewport, 8.0, Color32::from_rgb(15, 17, 23));
        if response.hovered() {
            let scroll = ui.input(|i| i.smooth_scroll_delta.y);
            if scroll.abs() > 0.0 {
                self.zoom = (self.zoom * (scroll * 0.002).exp()).clamp(1.0, 8.0);
            }
            if response.dragged() {
                self.pan += ui.input(|i| i.pointer.delta());
            }
            if response.clicked() {
                response.request_focus();
            }
            if response.has_focus() {
                ui.input(|i| {
                    if i.key_pressed(egui::Key::ArrowLeft) {
                        self.pan.x += 25.0;
                    }
                    if i.key_pressed(egui::Key::ArrowRight) {
                        self.pan.x -= 25.0;
                    }
                    if i.key_pressed(egui::Key::ArrowUp) {
                        self.pan.y += 25.0;
                    }
                    if i.key_pressed(egui::Key::ArrowDown) {
                        self.pan.y -= 25.0;
                    }
                });
            }
        }
        let base_scale =
            (viewport.width() / zone.width as f32).min(viewport.height() / zone.height as f32);
        let size = Vec2::new(zone.width as f32, zone.height as f32) * base_scale * self.zoom;
        if let Some([u, v]) = self.preview_center.take() {
            self.pan = Vec2::new((0.5 - u) * size.x, (0.5 - v) * size.y);
        }
        self.pan.x = self.pan.x.clamp(
            -(size.x - viewport.width()).max(0.0) * 0.5,
            (size.x - viewport.width()).max(0.0) * 0.5,
        );
        self.pan.y = self.pan.y.clamp(
            -(size.y - viewport.height()).max(0.0) * 0.5,
            (size.y - viewport.height()).max(0.0) * 0.5,
        );
        let image_rect = Rect::from_center_size(viewport.center() + self.pan, size);
        if let Some(texture) = texture {
            painter.image(
                texture.id(),
                image_rect,
                Rect::from_min_max(Pos2::ZERO, Pos2::new(1.0, 1.0)),
                Color32::WHITE,
            );
        } else {
            painter.text(
                viewport.center(),
                egui::Align2::CENTER_CENTER,
                t(
                    "Map image is missing. Repair the installation.",
                    "Chybí obrázek mapy. Oprav instalaci.",
                ),
                egui::FontId::proportional(16.0),
                Color32::LIGHT_GRAY,
            );
        }
        if zone.key == "azeroth" && !self.world_art.is_empty() {
            // The same world rectangles and zone textures as the web, loaded
            // only when visible so normal zoom does not decode every map.
            let mut overlays: Vec<_> = self
                .zones
                .iter()
                .filter_map(|z| {
                    let art = self.world_art.get(&z.key)?;
                    if !matches!(art.kind.as_str(), "continent" | "zone" | "city") {
                        return None;
                    }
                    let [l, r, t, b] = art.rect;
                    if ![l, r, t, b].iter().all(|v| v.is_finite()) || r <= l || b <= t {
                        return None;
                    }
                    let rect = Rect::from_min_max(
                        image_rect.min + Vec2::new(l * image_rect.width(), t * image_rect.height()),
                        image_rect.min + Vec2::new(r * image_rect.width(), b * image_rect.height()),
                    );
                    let opacity = art_opacity(&art.kind, self.zoom, rect.width());
                    (opacity > 0.01 && rect.intersects(viewport))
                        .then(|| (z.clone(), art.kind.clone(), rect, opacity, art.rect))
                })
                .collect();
            overlays.sort_by_key(|(_, kind, _, _, _)| match kind.as_str() {
                "continent" => 0,
                "zone" => 1,
                _ => 2,
            });
            for (overlay, kind, rect, opacity, world_rect) in overlays {
                let texture = self
                    .textures
                    .entry(overlay.key.clone())
                    .or_insert_with(|| load_texture(ui.ctx(), &overlay));
                if let Some(texture) = texture {
                    painter.add(egui::Shape::mesh(art_mesh(
                        texture.id(),
                        rect,
                        world_rect,
                        opacity,
                        &kind,
                    )));
                }
            }
        }
        if self.layer != 4 {
            let mut groups = BTreeMap::<(i32, i32), Vec<&Point>>::new();
            for point in &points {
                let pos = image_rect.min
                    + Vec2::new(point.x * image_rect.width(), point.y * image_rect.height());
                if viewport.contains(pos) {
                    groups
                        .entry((
                            ((pos.x - viewport.min.x) / 28.0) as i32,
                            ((pos.y - viewport.min.y) / 28.0) as i32,
                        ))
                        .or_default()
                        .push(point);
                }
            }
            for group in groups.values() {
                let point = group[0];
                let average = group
                    .iter()
                    .fold(Vec2::ZERO, |sum, p| sum + Vec2::new(p.x, p.y))
                    / group.len() as f32;
                let pos = image_rect.min
                    + Vec2::new(
                        average.x * image_rect.width(),
                        average.y * image_rect.height(),
                    );
                let color = match point.kind.as_str() {
                    "quest" => Color32::from_rgb(236, 202, 100),
                    "vendor" => Color32::from_rgb(100, 210, 170),
                    _ => Color32::from_rgb(175, 148, 255),
                };
                if group.len() > 1 {
                    painter.circle_filled(pos, 10.0, Color32::from_rgb(48, 33, 75));
                    painter.circle_stroke(pos, 10.0, Stroke::new(1.0, color));
                    painter.text(
                        pos,
                        egui::Align2::CENTER_CENTER,
                        group.len().to_string(),
                        egui::FontId::proportional(10.0),
                        Color32::WHITE,
                    );
                } else if point.exact {
                    painter.circle_filled(pos, 5.0, color);
                } else {
                    painter.circle_stroke(pos, 6.0, Stroke::new(2.0, color));
                }
                if response.hover_pos().is_some_and(|p| p.distance(pos) < 12.0) {
                    painter.text(
                        pos + Vec2::new(10.0, -10.0),
                        egui::Align2::LEFT_BOTTOM,
                        if group.len() > 1 {
                            t(
                                "NPC locations — zoom to inspect",
                                "Polohy NPC — přibliž pro detail",
                            )
                        } else {
                            &point.name
                        },
                        egui::FontId::proportional(13.0),
                        Color32::WHITE,
                    );
                    if response.clicked() {
                        if group.len() > 1 && self.zoom < 8.0 {
                            let previous = self.zoom;
                            self.zoom = (self.zoom * 2.0).min(8.0);
                            self.pan =
                                (self.pan - (pos - viewport.center())) * (self.zoom / previous);
                        } else {
                            self.selected_point = Some(point.clone());
                        }
                    }
                }
            }
        }
        // Geographic navigation uses static zone rectangles, never player coordinates.
        let mut navigate = None;
        for (index, child) in self.zones.iter().enumerate() {
            if let Some(bounds) = &child.bounds
                && bounds.parent_key == zone.key
            {
                let rect = Rect::from_min_size(
                    image_rect.min
                        + Vec2::new(
                            bounds.x * image_rect.width(),
                            bounds.y * image_rect.height(),
                        ),
                    Vec2::new(
                        bounds.width * image_rect.width(),
                        bounds.height * image_rect.height(),
                    ),
                );
                let hover = response.hover_pos().is_some_and(|p| rect.contains(p));
                painter.rect_stroke(
                    rect,
                    0.0,
                    Stroke::new(
                        if hover { 2.0 } else { 1.0 },
                        Color32::from_rgba_unmultiplied(
                            235,
                            218,
                            167,
                            if hover { 220 } else { 100 },
                        ),
                    ),
                    egui::StrokeKind::Inside,
                );
                painter.text(
                    rect.center(),
                    egui::Align2::CENTER_CENTER,
                    child.label(cs),
                    egui::FontId::proportional(12.0),
                    Color32::WHITE,
                );
                if hover && response.clicked() {
                    navigate = Some(index)
                }
            }
        }
        if let Some(index) = navigate {
            self.selected = index;
            self.zoom = 1.0;
            self.pan = Vec2::ZERO;
            self.selected_point = None;
        }
        ui.horizontal_wrapped(|ui|{ui.colored_label(Color32::from_rgb(175,148,255),"● NPC");ui.colored_label(Color32::from_rgb(236,202,100),t("● Quests","● Questy"));ui.colored_label(Color32::from_rgb(100,210,170),t("● Vendors","● Obchodníci"));ui.weak(t("Only NPC unit positions or database locations. Player interaction coordinates are excluded.","Pouze polohy NPC nebo databázová místa. Souřadnice interakcí hráčů jsou vynechány."));});
        if let Some(point) = &self.selected_point {
            egui::Frame::new()
                .fill(Color32::from_rgb(29, 27, 42))
                .inner_margin(12)
                .corner_radius(6)
                .show(ui, |ui| {
                    ui.label(RichText::new(&point.name).strong());
                    ui.label(format!(
                        "{} #{} · {} {}",
                        point.kind,
                        point.id,
                        point.count,
                        if point.database {
                            t("reference location", "referenční místo")
                        } else {
                            t("observations", "pozorování")
                        }
                    ));
                    ui.weak(if point.database {
                        t(
                            "Reference NPC location from the installed database; no player marker.",
                            "Referenční místo NPC z instalované databáze; bez značky hráče.",
                        )
                    } else {
                        t(
                            "Observed NPC unit position; no player marker.",
                            "Pozorovaná poloha NPC; bez značky hráče.",
                        )
                    });
                    if !point.source.is_empty() {
                        ui.weak(&point.source);
                    }
                });
        } else if points.is_empty() && self.layer != 4 {
            ui.weak(t(
                "No matching world sightings in this zone. The map remains available offline.",
                "V této zóně zatím nejsou odpovídající pozorování. Mapa zůstává dostupná offline.",
            ));
        }
        if let Some(bounds) = &zone.bounds
            && let Some(index) = self.zones.iter().position(|z| z.key == bounds.parent_key)
            && ui.button(t("← Parent map", "← Nadřazená mapa")).clicked()
        {
            self.selected = index;
            self.zoom = 1.0;
            self.pan = Vec2::ZERO;
            self.selected_point = None;
        }
    }
}

fn load_texture(ctx: &egui::Context, zone: &Zone) -> Option<TextureHandle> {
    let file = Path::new(&zone.image).file_name()?;
    let bytes = std::fs::read(identity::resource_root()?.join("maps").join(file)).ok()?;
    let image = image::load_from_memory(&bytes).ok()?.to_rgba8();
    Some(ctx.load_texture(
        format!("world-map-{}", zone.key),
        egui::ColorImage::from_rgba_unmultiplied(
            [image.width() as usize, image.height() as usize],
            image.as_raw(),
        ),
        egui::TextureOptions::LINEAR,
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::{Value, json};

    #[test]
    fn stitched_map_feathers_zone_and_interior_continent_edges() {
        let rect = Rect::from_min_max(Pos2::ZERO, Pos2::new(100.0, 100.0));
        let zone = art_mesh(
            egui::TextureId::default(),
            rect,
            [0.2, 0.4, 0.2, 0.4],
            1.0,
            "zone",
        );
        assert_eq!(zone.vertices[0].color.a(), 0);
        assert_eq!(zone.vertices[5].color.a(), 255);
        let continent = art_mesh(
            egui::TextureId::default(),
            rect,
            [-0.2, 0.6, 0.1, 0.9],
            1.0,
            "continent",
        );
        assert_eq!(continent.vertices[4].color.a(), 255); // outside-world edge remains visible
        assert_eq!(continent.vertices[7].color.a(), 0); // overlapping edge fades out
    }
    fn account(events: Vec<Value>) -> AccountData {
        AccountData {
            account: "test".into(),
            flavor: "_forever_".into(),
            characters: vec![],
            runs: vec![],
            event_count: events.len(),
            run_count: 0,
            events,
            web_enabled: false,
            sharing_enabled: false,
            peers: 0,
            error: None,
        }
    }
    fn zone() -> Zone {
        Zone {
            key: "test".into(),
            name_en: "Test".into(),
            name_cs: "Test".into(),
            image: "/media/maps/test.png".into(),
            width: 100,
            height: 100,
            bounds: None,
            ui_map_ids: vec![1426],
        }
    }
    #[test]
    fn player_snapshots_and_visits_never_become_precise_markers() {
        let a = account(vec![
            json!({"kind":"zone.visited","character":{"name":"Private"},"payload":{"mapId":1426,"x":0.5,"y":0.5}}),
            json!({"kind":"character.snapshot","payload":{"mapId":1426,"x":0.4,"y":0.2}}),
        ]);
        assert!(points(&[&a], &zone(), 0, "").is_empty());
    }
    #[test]
    fn map_namespace_and_nonfinite_or_invalid_coordinates_do_not_leak_wrong_pins() {
        let a = account(vec![
            json!({"kind":"npc.observed","payload":{"npcId":1,"mapId":1426,"mapSystem":"legacy_area","x":0.5,"y":0.5}}),
            json!({"kind":"npc.observed","payload":{"npcId":2,"mapId":1426,"x":1.5,"y":0.5}}),
        ]);
        assert!(points(&[&a], &zone(), 0, "").is_empty());
    }
    #[test]
    fn historical_interactions_are_not_mistaken_for_static_npc_positions() {
        let a = account(vec![
            json!({"kind":"npc.observed","character":{"name":"Private"},"payload":{"npcId":1,"name":"Vendor","mapId":1426,"x":0.5,"y":0.5,"positionMethod":"player_interaction"}}),
        ]);
        assert!(points(&[&a], &zone(), 0, "").is_empty());
    }
    #[test]
    fn exact_npc_observation_retains_only_world_identity() {
        let a = account(vec![
            json!({"kind":"npc.observed","character":{"name":"Private"},"payload":{"npcId":1,"name":"Vendor","mapId":1426,"x":0.5,"y":0.5,"positionMethod":"unit_position"}}),
        ]);
        let p = points(&[&a], &zone(), 0, "");
        assert_eq!(p.len(), 1);
        assert_eq!(p[0].name, "Vendor");
        assert!(p[0].exact);
    }

    #[test]
    fn database_pins_are_accepted_only_from_reference_catalog() {
        let entry = json!({"id":12,"name":"Guide NPC","sourceLabel":"Reference source","locations":[{"mapId":1426,"mapSystem":"ui_map","positionMethod":"npc_database","x":0.3,"y":0.4}]});
        let pins = database_points(std::slice::from_ref(&entry), &zone(), 0, "");
        assert_eq!(pins.len(), 1);
        assert!(pins[0].database);
        let a = account(vec![
            json!({"kind":"npc.observed","payload":{"npcId":12,"mapId":1426,"mapSystem":"ui_map","positionMethod":"npc_database","x":0.3,"y":0.4}}),
        ]);
        assert!(points(&[&a], &zone(), 0, "").is_empty());
    }
}

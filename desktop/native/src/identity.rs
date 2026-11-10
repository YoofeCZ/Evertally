//! Bundled presentation assets. This module never fetches icons or user data.
use std::{cell::RefCell, collections::HashMap, path::PathBuf};

use eframe::egui::{self, Color32, TextureHandle, Vec2};

pub fn resource_root() -> Option<PathBuf> {
    let installed = std::env::current_exe()
        .ok()
        .and_then(|p| p.parent().map(|p| p.join("resources")));
    installed
        .filter(|p| p.join("maps/manifest.json").is_file())
        .or_else(|| {
            let dev = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../shared/assets");
            dev.is_dir().then_some(dev)
        })
}

#[derive(Default)]
pub struct Icons {
    textures: RefCell<HashMap<String, Option<TextureHandle>>>,
}

impl Icons {
    pub fn show(&self, ui: &mut egui::Ui, group: &str, id: Option<u64>, size: f32, label: &str) {
        let key = format!("{group}/{}", id.unwrap_or(0));
        let mut textures = self.textures.borrow_mut();
        let texture = textures.entry(key.clone()).or_insert_with(|| {
            let root = resource_root()?;
            let bytes = ["png", "jpg", "jpeg"].iter().find_map(|ext| {
                let p = root.join("identity").join(format!("{key}.{ext}"));
                std::fs::metadata(&p)
                    .ok()
                    .filter(|m| m.len() <= 2 * 1024 * 1024)?;
                std::fs::read(p).ok()
            })?;
            let image = image::load_from_memory(&bytes).ok()?.to_rgba8();
            Some(ui.ctx().load_texture(
                format!("identity-{key}"),
                egui::ColorImage::from_rgba_unmultiplied(
                    [image.width() as usize, image.height() as usize],
                    image.as_raw(),
                ),
                egui::TextureOptions::LINEAR,
            ))
        });
        if let Some(texture) = texture {
            ui.image((texture.id(), Vec2::splat(size)))
                .on_hover_text(label);
        } else {
            let (rect, response) = ui.allocate_exact_size(Vec2::splat(size), egui::Sense::hover());
            ui.painter()
                .rect_filled(rect, 4.0, Color32::from_rgb(42, 38, 57));
            ui.painter().text(
                rect.center(),
                egui::Align2::CENTER_CENTER,
                "?",
                egui::FontId::proportional(size * 0.55),
                Color32::from_gray(170),
            );
            response.on_hover_text(label);
        }
    }
}

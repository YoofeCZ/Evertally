//! Windowless egui previews. This module rasterises the app's own tessellated
//! shapes in RAM; it never creates a window, opens a graphics device, captures
//! the desktop or sends input to another application.

use std::collections::HashMap;
use std::path::Path;

use eframe::egui::{self, ColorImage, TextureFilter, TextureId, TextureOptions, TextureWrapMode};
use image::{Rgba, RgbaImage};

#[derive(Default)]
pub struct SoftwareRenderer {
    textures: HashMap<TextureId, Texture>,
}

struct Texture {
    image: ColorImage,
    options: TextureOptions,
}

impl SoftwareRenderer {
    /// Paint and save one frame. Keep this renderer with its egui context between
    /// warm-up frames, because font atlases are delivered as incremental patches.
    pub fn render(
        &mut self,
        ctx: &egui::Context,
        mut output: egui::FullOutput,
        width: u32,
        height: u32,
        path: &Path,
    ) -> Result<(), String> {
        let result = self.paint(ctx, &output, width, height);
        // egui requires all texture instructions to be explicitly consumed.
        for id in &output.textures_delta.free {
            self.textures.remove(id);
        }
        output.textures_delta.clear();
        result?.save(path).map_err(|error| error.to_string())
    }

    fn paint(
        &mut self,
        ctx: &egui::Context,
        output: &egui::FullOutput,
        width: u32,
        height: u32,
    ) -> Result<RgbaImage, String> {
        if width == 0 || height == 0 || width > 4096 || height > 4096 {
            return Err("Preview dimensions must be between 1 and 4096 pixels".to_owned());
        }
        let scale = output.pixels_per_point;
        if !scale.is_finite() || scale <= 0.0 {
            return Err("Preview pixels_per_point must be finite and positive".to_owned());
        }
        for (id, deltas) in &output.textures_delta.set {
            for delta in deltas {
                self.update_texture(*id, delta)?;
            }
        }
        let mut canvas = RgbaImage::new(width, height);
        for primitive in ctx.tessellate(output.shapes.clone(), scale) {
            match primitive.primitive {
                egui::epaint::Primitive::Mesh(mesh) => {
                    let texture = self.textures.get(&mesh.texture_id).ok_or_else(|| {
                        format!(
                            "Preview mesh uses an unavailable texture {:?}",
                            mesh.texture_id
                        )
                    })?;
                    if !mesh.is_valid()
                        || !mesh.indices.len().is_multiple_of(3)
                        || mesh.vertices.iter().any(|vertex| {
                            !vertex.pos.x.is_finite()
                                || !vertex.pos.y.is_finite()
                                || !vertex.uv.x.is_finite()
                                || !vertex.uv.y.is_finite()
                        })
                    {
                        return Err("Preview contains an invalid triangle mesh".to_owned());
                    }
                    for triangle in mesh.indices.chunks_exact(3) {
                        let vertices = [
                            mesh.vertices[triangle[0] as usize],
                            mesh.vertices[triangle[1] as usize],
                            mesh.vertices[triangle[2] as usize],
                        ];
                        paint_triangle(&mut canvas, texture, vertices, primitive.clip_rect, scale);
                    }
                }
                egui::epaint::Primitive::Callback(_) => {
                    return Err(
                        "Windowless previews do not support native paint callbacks".to_owned()
                    );
                }
            }
        }
        Ok(canvas)
    }

    fn update_texture(
        &mut self,
        id: TextureId,
        delta: &egui::epaint::ImageDelta,
    ) -> Result<(), String> {
        let egui::ImageData::Color(image) = &delta.image;
        let [width, height] = image.size;
        if width == 0 || height == 0 || width.checked_mul(height) != Some(image.pixels.len()) {
            return Err("Preview texture has invalid dimensions".to_owned());
        }
        if let Some([x, y]) = delta.pos {
            let texture = self
                .textures
                .get_mut(&id)
                .ok_or_else(|| format!("Preview patch has no allocated texture {id:?}"))?;
            if x.checked_add(width)
                .is_none_or(|right| right > texture.image.size[0])
                || y.checked_add(height)
                    .is_none_or(|bottom| bottom > texture.image.size[1])
            {
                return Err("Preview texture patch exceeds its atlas".to_owned());
            }
            for row in 0..height {
                let target = (y + row) * texture.image.size[0] + x;
                texture.image.pixels[target..target + width]
                    .copy_from_slice(&image.pixels[row * width..(row + 1) * width]);
            }
            texture.options = delta.options;
        } else {
            self.textures.insert(
                id,
                Texture {
                    image: image.as_ref().clone(),
                    options: delta.options,
                },
            );
        }
        Ok(())
    }
}

#[derive(Clone, Copy)]
struct Vertex {
    pos: egui::Pos2,
    uv: egui::Pos2,
    color: [f32; 4],
}

impl Vertex {
    fn from_egui(vertex: egui::epaint::Vertex, scale: f32) -> Self {
        Self {
            pos: egui::pos2(vertex.pos.x * scale, vertex.pos.y * scale),
            uv: vertex.uv,
            color: vertex.color.to_array().map(|byte| f32::from(byte) / 255.0),
        }
    }
}

fn edge(a: egui::Pos2, b: egui::Pos2, p: egui::Pos2) -> f32 {
    (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
}

fn top_left(a: egui::Pos2, b: egui::Pos2) -> bool {
    b.y < a.y || b.y == a.y && b.x > a.x
}

fn paint_triangle(
    canvas: &mut RgbaImage,
    texture: &Texture,
    input: [egui::epaint::Vertex; 3],
    clip: egui::Rect,
    scale: f32,
) {
    let mut vertices = input.map(|vertex| Vertex::from_egui(vertex, scale));
    let mut area = edge(vertices[0].pos, vertices[1].pos, vertices[2].pos);
    if area.abs() < 1.0e-8 {
        return;
    }
    if area < 0.0 {
        vertices.swap(1, 2);
        area = -area;
    }
    let [a, b, c] = vertices;
    let clip = egui::Rect::from_min_max(clip.min * scale, clip.max * scale);
    let min_x = a
        .pos
        .x
        .min(b.pos.x)
        .min(c.pos.x)
        .max(clip.min.x)
        .floor()
        .max(0.0) as u32;
    let min_y = a
        .pos
        .y
        .min(b.pos.y)
        .min(c.pos.y)
        .max(clip.min.y)
        .floor()
        .max(0.0) as u32;
    let max_x = a
        .pos
        .x
        .max(b.pos.x)
        .max(c.pos.x)
        .min(clip.max.x)
        .ceil()
        .clamp(0.0, canvas.width() as f32) as u32;
    let max_y = a
        .pos
        .y
        .max(b.pos.y)
        .max(c.pos.y)
        .min(clip.max.y)
        .ceil()
        .clamp(0.0, canvas.height() as f32) as u32;
    let inclusive = [
        top_left(b.pos, c.pos),
        top_left(c.pos, a.pos),
        top_left(a.pos, b.pos),
    ];
    for y in min_y..max_y {
        for x in min_x..max_x {
            let point = egui::pos2(x as f32 + 0.5, y as f32 + 0.5);
            if point.x < clip.min.x
                || point.x >= clip.max.x
                || point.y < clip.min.y
                || point.y >= clip.max.y
            {
                continue;
            }
            let edges = [
                edge(b.pos, c.pos, point),
                edge(c.pos, a.pos, point),
                edge(a.pos, b.pos, point),
            ];
            if edges
                .iter()
                .zip(inclusive)
                .any(|(&value, include)| value < 0.0 || value == 0.0 && !include)
            {
                continue;
            }
            let weights = edges.map(|value| value / area);
            let uv = egui::pos2(
                weights[0] * a.uv.x + weights[1] * b.uv.x + weights[2] * c.uv.x,
                weights[0] * a.uv.y + weights[1] * b.uv.y + weights[2] * c.uv.y,
            );
            let sampled = texture.sample(uv);
            let source = std::array::from_fn(|channel| {
                sampled[channel]
                    * (weights[0] * a.color[channel]
                        + weights[1] * b.color[channel]
                        + weights[2] * c.color[channel])
            });
            blend(canvas.get_pixel_mut(x, y), source);
        }
    }
}

impl Texture {
    fn sample(&self, uv: egui::Pos2) -> [f32; 4] {
        let x = uv.x * self.image.size[0] as f32 - 0.5;
        let y = uv.y * self.image.size[1] as f32 - 0.5;
        if self.options.magnification == TextureFilter::Nearest {
            return self.texel((x + 0.5).floor() as i64, (y + 0.5).floor() as i64);
        }
        let left = x.floor();
        let top = y.floor();
        let dx = x - left;
        let dy = y - top;
        let a = self.texel(left as i64, top as i64);
        let b = self.texel(left as i64 + 1, top as i64);
        let c = self.texel(left as i64, top as i64 + 1);
        let d = self.texel(left as i64 + 1, top as i64 + 1);
        std::array::from_fn(|channel| {
            (a[channel] * (1.0 - dx) + b[channel] * dx) * (1.0 - dy)
                + (c[channel] * (1.0 - dx) + d[channel] * dx) * dy
        })
    }

    fn texel(&self, x: i64, y: i64) -> [f32; 4] {
        let x = wrapped(x, self.image.size[0], self.options.wrap_mode);
        let y = wrapped(y, self.image.size[1], self.options.wrap_mode);
        self.image.pixels[y * self.image.size[0] + x]
            .to_array()
            .map(|byte| f32::from(byte) / 255.0)
    }
}

fn wrapped(index: i64, size: usize, mode: TextureWrapMode) -> usize {
    let size = size as i64;
    match mode {
        TextureWrapMode::ClampToEdge => index.clamp(0, size - 1) as usize,
        TextureWrapMode::Repeat => index.rem_euclid(size) as usize,
        TextureWrapMode::MirroredRepeat => {
            let index = index.rem_euclid(size * 2);
            if index < size {
                index as usize
            } else {
                (size * 2 - index - 1) as usize
            }
        }
    }
}

/// egui's Glow backend multiplies and blends premultiplied sRGBA in gamma
/// space, which is also how its font atlas coverage is encoded.
fn blend(destination: &mut Rgba<u8>, source: [f32; 4]) {
    let inverse_alpha = 1.0 - source[3];
    for (channel, value) in destination.0.iter_mut().enumerate() {
        *value = ((source[channel] + f32::from(*value) / 255.0 * inverse_alpha).clamp(0.0, 1.0)
            * 255.0)
            .round() as u8;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn transparent_edges_use_premultiplied_source_over() {
        let mut destination = Rgba([0, 0, 255, 255]);
        blend(&mut destination, [0.5, 0.0, 0.0, 0.5]);
        assert_eq!(destination, Rgba([128, 0, 128, 255]));
    }

    #[test]
    fn shared_triangle_edge_is_painted_once_and_scissor_is_respected() {
        let texture = Texture {
            image: ColorImage::filled([1, 1], egui::Color32::WHITE),
            options: TextureOptions::NEAREST,
        };
        let color = egui::Color32::from_rgba_premultiplied(128, 0, 0, 128);
        let vertex = |x, y| egui::epaint::Vertex {
            pos: egui::pos2(x, y),
            uv: egui::pos2(0.5, 0.5),
            color,
        };
        let mut canvas = RgbaImage::new(4, 4);
        let clip = egui::Rect::from_min_max(egui::pos2(1.0, 0.0), egui::pos2(4.0, 4.0));
        paint_triangle(
            &mut canvas,
            &texture,
            [vertex(0.0, 0.0), vertex(4.0, 0.0), vertex(0.0, 4.0)],
            clip,
            1.0,
        );
        paint_triangle(
            &mut canvas,
            &texture,
            [vertex(4.0, 0.0), vertex(4.0, 4.0), vertex(0.0, 4.0)],
            clip,
            1.0,
        );
        for y in 0..4 {
            assert_eq!(canvas.get_pixel(0, y), &Rgba([0, 0, 0, 0]));
            for x in 1..4 {
                assert_eq!(canvas.get_pixel(x, y), &Rgba([128, 0, 0, 128]));
            }
        }
    }

    #[test]
    fn texture_patch_updates_only_its_atlas_rectangle() {
        let mut renderer = SoftwareRenderer::default();
        let id = TextureId::Managed(0);
        renderer
            .update_texture(
                id,
                &egui::epaint::ImageDelta::full(
                    ColorImage::filled([3, 2], egui::Color32::BLACK),
                    TextureOptions::LINEAR,
                ),
            )
            .expect("allocate atlas");
        renderer
            .update_texture(
                id,
                &egui::epaint::ImageDelta::partial(
                    [1, 1],
                    ColorImage::filled([1, 1], egui::Color32::WHITE),
                    TextureOptions::LINEAR,
                ),
            )
            .expect("patch atlas");
        let pixels = &renderer.textures[&id].image.pixels;
        assert_eq!(pixels[4], egui::Color32::WHITE);
        assert_eq!(
            pixels
                .iter()
                .filter(|&&pixel| pixel == egui::Color32::WHITE)
                .count(),
            1
        );
        assert!(
            renderer
                .update_texture(
                    id,
                    &egui::epaint::ImageDelta::partial(
                        [3, 1],
                        ColorImage::filled([1, 1], egui::Color32::WHITE),
                        TextureOptions::LINEAR
                    )
                )
                .is_err()
        );
    }
}

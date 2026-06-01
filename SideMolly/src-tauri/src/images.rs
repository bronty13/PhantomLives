// Phase 3 image-ops — watermark stamping + EXIF strip + deterministic
// rename. Pure module (no Tauri dep) so the contract can be tested in
// isolation. Same atomic write-via-tmp pattern as thumbnails.rs.
//
// Watermark: rasterized text (PaperDaisy.ttf shipped in resources) blended
// at configurable opacity over the source image at one of nine
// 3x3-grid positions. Font size and margin are expressed as percentages
// of image height so output looks the same at 1080p and 4K.
//
// EXIF strip: re-encoding via image::DynamicImage::save (or the JPEG
// encoder directly) drops everything that wasn't pixel data — EXIF,
// XMP, IPTC, ICC. That's what we want when posting from a private
// camera roll.
//
// Rename: deterministic template applied to the OUTPUT filename only.
// Source files are never touched.

use std::fs;
use std::io::Cursor;
use std::path::{Path, PathBuf};

use ab_glyph::{FontRef, PxScale};
use image::{DynamicImage, GenericImage, GenericImageView, ImageBuffer, ImageFormat, Rgba, RgbaImage};
use imageproc::drawing::{draw_text_mut, text_size};

#[derive(Debug, thiserror::Error)]
pub enum ImageOpError {
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    #[error("image: {0}")]
    Image(#[from] image::ImageError),
    #[error("font: {0}")]
    Font(String),
    #[error("invalid position: {0}")]
    Position(String),
}

/// Bitflags-ish set of ops the caller wants applied. Order is fixed
/// (watermark → strip_exif → rename) so the output is deterministic
/// regardless of how the caller orders the booleans in the request.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct ImageOps {
    pub watermark: bool,
    pub strip_exif: bool,
    pub rename: bool,
}

impl ImageOps {
    pub fn op_kind(self) -> &'static str {
        match (self.watermark, self.strip_exif, self.rename) {
            (true, true, true) => "watermark_strip_rename",
            (true, true, false) => "watermark_strip",
            (true, false, false) => "watermark",
            (false, true, false) => "strip_exif",
            (false, false, true) => "rename",
            // Any other combo collapses to a "strip+rename" via JPEG
            // re-encode; we treat it as strip_exif for accounting.
            _ => "strip_exif",
        }
    }
}

#[derive(Debug, Clone)]
pub struct WatermarkProfile {
    pub text: String,
    /// 0..=100. 0 = invisible, 100 = solid.
    pub opacity_percent: u8,
    pub position: WatermarkPosition,
    /// Font size as a percentage of image height (e.g. 4.0 = 4%).
    pub font_size_pct: f32,
    /// Distance from edge as a percentage of image height.
    pub margin_pct: f32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WatermarkPosition {
    TopLeft, TopCenter, TopRight,
    MiddleLeft, MiddleCenter, MiddleRight,
    BottomLeft, BottomCenter, BottomRight,
}

impl WatermarkPosition {
    pub fn parse(s: &str) -> Result<Self, ImageOpError> {
        Ok(match s {
            "top-left" => Self::TopLeft,
            "top-center" => Self::TopCenter,
            "top-right" => Self::TopRight,
            "middle-left" => Self::MiddleLeft,
            "middle-center" => Self::MiddleCenter,
            "middle-right" => Self::MiddleRight,
            "bottom-left" => Self::BottomLeft,
            "bottom-center" => Self::BottomCenter,
            "bottom-right" => Self::BottomRight,
            other => return Err(ImageOpError::Position(other.to_string())),
        })
    }
}

/// Process a single source image into `dst` with the requested ops.
/// Atomic via `.sm-tmp.jpg` + rename, like thumbnails.
///
/// `font_bytes` is the bundled PaperDaisy.ttf bytes — caller resolves
/// the resource path once (via Tauri) and reuses across many images.
pub fn process_image(
    src: &Path,
    dst: &Path,
    ops: ImageOps,
    watermark: Option<&WatermarkProfile>,
    font_bytes: &[u8],
    rotation_degrees: i64,
) -> Result<(), ImageOpError> {
    // Load. image::open drops EXIF on decode (we re-encode anyway).
    let mut img: DynamicImage = image::open(src)?;

    // Apply per-file rotation first — watermark/position math should
    // operate on the corrected orientation so the watermark lands in
    // the bottom-right of what the user actually sees.
    img = match rotation_degrees {
        90  => img.rotate90(),
        180 => img.rotate180(),
        270 => img.rotate270(),
        _   => img,
    };

    // Watermark requires an RGBA buffer for alpha blending.
    if ops.watermark {
        if let Some(profile) = watermark {
            if profile.opacity_percent > 0 && !profile.text.is_empty() {
                let mut rgba = img.to_rgba8();
                draw_watermark(&mut rgba, profile, font_bytes)?;
                img = DynamicImage::ImageRgba8(rgba);
            }
        }
    }

    // Write to a sibling tmp file with .jpg extension (re-encode JPEG;
    // drops EXIF on save). Atomic rename to final dst.
    if let Some(parent) = dst.parent() {
        fs::create_dir_all(parent)?;
    }
    let tmp = dst.with_extension("sm-tmp.jpg");

    // Always re-encode as JPEG quality 92 — high-fidelity but smaller
    // than original RAW/PNG. Strips all non-pixel metadata.
    let rgb = img.to_rgb8();
    {
        let mut file = fs::File::create(&tmp)?;
        let mut encoder = image::codecs::jpeg::JpegEncoder::new_with_quality(&mut file, 92);
        encoder.encode_image(&rgb)?;
    }
    if dst.exists() { let _ = fs::remove_file(dst); }
    fs::rename(&tmp, dst)?;
    Ok(())
}

/// Draw `text` in white with a soft dark outline so it stays legible on
/// any background. A plain white watermark vanishes over bright video or
/// pale photos — the PaperDaisy strokes are thin and there was no
/// contrast halo — which is why the watermark "couldn't be seen". The
/// outline gives every glyph a dark edge.
///
/// `fill_alpha` is the user's configured opacity (so the watermark stays
/// as subtle as they asked); the outline alpha is derived from it but
/// floored so even a faint fill reads, and capped so a near-solid fill
/// doesn't grow a heavy black box. `font_size` scales the outline width.
fn draw_text_with_outline(
    canvas: &mut RgbaImage,
    x: i32,
    y: i32,
    scale: PxScale,
    font: &FontRef<'_>,
    text: &str,
    fill_alpha: u8,
    font_size: f32,
) {
    let t = ((font_size / 24.0).round() as i32).max(1);
    let outline_alpha = ((fill_alpha as u16) * 2).clamp(100, 200) as u8;
    let outline = Rgba([0, 0, 0, outline_alpha]);
    // 8-direction stroke at offset `t` — axes + diagonals.
    for (dx, dy) in [
        (-t, 0), (t, 0), (0, -t), (0, t),
        (-t, -t), (-t, t), (t, -t), (t, t),
    ] {
        draw_text_mut(canvas, outline, x + dx, y + dy, scale, font, text);
    }
    draw_text_mut(canvas, Rgba([255, 255, 255, fill_alpha]), x, y, scale, font, text);
}

/// Render `profile.text` onto `img` per the position + opacity in the
/// profile. Mutates `img` in place. Uses the bundled font bytes.
fn draw_watermark(
    img: &mut RgbaImage,
    profile: &WatermarkProfile,
    font_bytes: &[u8],
) -> Result<(), ImageOpError> {
    let font = FontRef::try_from_slice(font_bytes)
        .map_err(|e| ImageOpError::Font(e.to_string()))?;

    let w = img.width() as f32;
    let h = img.height() as f32;
    let font_size = (h * profile.font_size_pct / 100.0).max(12.0);
    let margin = (h * profile.margin_pct / 100.0).max(4.0) as i32;
    let scale = PxScale::from(font_size);

    let (tw, th) = text_size(scale, &font, &profile.text);
    let (tw, th) = (tw as i32, th as i32);
    let w_i = w as i32;
    let h_i = h as i32;

    let (x, y) = match profile.position {
        WatermarkPosition::TopLeft      => (margin,                 margin),
        WatermarkPosition::TopCenter    => ((w_i - tw) / 2,         margin),
        WatermarkPosition::TopRight     => (w_i - tw - margin,      margin),
        WatermarkPosition::MiddleLeft   => (margin,                 (h_i - th) / 2),
        WatermarkPosition::MiddleCenter => ((w_i - tw) / 2,         (h_i - th) / 2),
        WatermarkPosition::MiddleRight  => (w_i - tw - margin,      (h_i - th) / 2),
        WatermarkPosition::BottomLeft   => (margin,                 h_i - th - margin),
        WatermarkPosition::BottomCenter => ((w_i - tw) / 2,         h_i - th - margin),
        WatermarkPosition::BottomRight  => (w_i - tw - margin,      h_i - th - margin),
    };

    let alpha = (profile.opacity_percent as f32 / 100.0 * 255.0) as u8;
    draw_text_with_outline(img, x, y, scale, &font, &profile.text, alpha, font_size);
    Ok(())
}

/// Render the watermark text to a transparent-background RGBA PNG at
/// the given absolute font size (in px). Used by the Phase 4 video
/// pipeline because Homebrew's stock ffmpeg ships without libfreetype
/// (so the `drawtext` filter is unavailable) — overlay-with-PNG works
/// on any ffmpeg build.
///
/// The caller (bundles.rs::enqueue_bundle_video_ops) owns all the
/// resolution math: floor for legibility on tiny clips, cap so the
/// watermark doesn't dominate small frames, and reference height for
/// the user's font_size_pct. Keeping the math out of this function
/// makes it usable for both video-overlay and future image-overlay
/// callers that need the same PNG render path.
pub fn render_watermark_png(
    profile: &WatermarkProfile,
    font_bytes: &[u8],
    font_size_px: f32,
) -> Result<Vec<u8>, ImageOpError> {
    let font = FontRef::try_from_slice(font_bytes)
        .map_err(|e| ImageOpError::Font(e.to_string()))?;
    let font_size = font_size_px.max(12.0);
    let scale = PxScale::from(font_size);
    let (tw, th) = text_size(scale, &font, &profile.text);

    // Breathing room around the glyphs so descenders + edges + the
    // contrast outline don't clip when alpha-composited. Tight crop
    // saves overlay bytes; the `+ outline_t` keeps the stroke in-frame.
    let outline_t = ((font_size / 24.0).round() as u32).max(1);
    let pad: u32 = 6 + outline_t;
    let w = (tw + 2 * pad).max(1);
    let h = (th + 2 * pad).max(1);
    let mut canvas: RgbaImage = ImageBuffer::from_pixel(w, h, Rgba([0, 0, 0, 0]));

    let alpha = (profile.opacity_percent.min(100) as f32 / 100.0 * 255.0) as u8;
    draw_text_with_outline(
        &mut canvas, pad as i32, pad as i32, scale, &font, &profile.text, alpha, font_size,
    );

    let mut out = Vec::with_capacity((w * h * 2) as usize);
    canvas
        .write_to(&mut Cursor::new(&mut out), ImageFormat::Png)?;
    Ok(out)
}

/// Render the Phase 4.5 auto-assembly title card as a full-frame
/// 1920×1080 (or user-configured) PNG. Layout: solid black background,
/// title text centred above frame center at ~8% of frame height, persona
/// watermark below at ~5% of frame height with 85% opacity. Both texts
/// are PaperDaisy.
///
/// PNG instead of ffmpeg's `drawtext` filter because Homebrew's stock
/// ffmpeg lacks libfreetype (same issue we hit on video watermarks —
/// see `render_watermark_png` above). The auto-assemble title pipeline
/// then loops this PNG for the title duration with ffmpeg's `loop`
/// demuxer and adds the fade-in/out via ffmpeg's `fade` filter (which
/// IS in any ffmpeg build).
pub fn render_title_card_png(
    title: &str,
    persona_watermark: &str,
    width: u32,
    height: u32,
    font_bytes: &[u8],
) -> Result<Vec<u8>, ImageOpError> {
    let font = FontRef::try_from_slice(font_bytes)
        .map_err(|e| ImageOpError::Font(e.to_string()))?;

    // Solid-black background — matches the spec's `color=black` source.
    let mut canvas: RgbaImage =
        ImageBuffer::from_pixel(width, height, Rgba([0, 0, 0, 255]));

    let h_f = height as f32;
    let title_size = (h_f * 0.08).max(24.0);
    let persona_size = (h_f * 0.05).max(18.0);
    let gap = (h_f * 0.02) as i32;
    let title_scale = PxScale::from(title_size);
    let persona_scale = PxScale::from(persona_size);

    let (tw_title, th_title) = text_size(title_scale, &font, title);
    let (tw_persona, _th_persona) = text_size(persona_scale, &font, persona_watermark);

    let w_i = width as i32;
    let h_i = height as i32;
    let title_x = (w_i - tw_title as i32) / 2;
    let persona_x = (w_i - tw_persona as i32) / 2;
    // Title sits just above center, persona just below — gap between.
    let title_y = (h_i / 2) - th_title as i32 - gap / 2;
    let persona_y = (h_i / 2) + gap / 2;

    draw_text_mut(
        &mut canvas, Rgba([255, 255, 255, 255]),
        title_x, title_y, title_scale, &font, title,
    );
    let persona_alpha = (0.85 * 255.0) as u8;
    draw_text_mut(
        &mut canvas, Rgba([255, 255, 255, persona_alpha]),
        persona_x, persona_y, persona_scale, &font, persona_watermark,
    );

    let mut out = Vec::with_capacity((width * height * 2) as usize);
    canvas.write_to(&mut Cursor::new(&mut out), ImageFormat::Png)?;
    Ok(out)
}

/// Compute the ffmpeg `overlay` filter's (x, y) expressions for the
/// nine-grid position. `margin_px` is the absolute pixel margin from
/// the edge (overlay x/y are in pixels; variables `W`/`H` are the main
/// video dims, `w`/`h` are the overlay PNG dims).
pub fn overlay_xy_expr(position: WatermarkPosition, margin_px: i32) -> (String, String) {
    match position {
        WatermarkPosition::TopLeft      => (format!("{margin_px}"),         format!("{margin_px}")),
        WatermarkPosition::TopCenter    => ("(W-w)/2".into(),                format!("{margin_px}")),
        WatermarkPosition::TopRight     => (format!("W-w-{margin_px}"),     format!("{margin_px}")),
        WatermarkPosition::MiddleLeft   => (format!("{margin_px}"),         "(H-h)/2".into()),
        WatermarkPosition::MiddleCenter => ("(W-w)/2".into(),                "(H-h)/2".into()),
        WatermarkPosition::MiddleRight  => (format!("W-w-{margin_px}"),     "(H-h)/2".into()),
        WatermarkPosition::BottomLeft   => (format!("{margin_px}"),         format!("H-h-{margin_px}")),
        WatermarkPosition::BottomCenter => ("(W-w)/2".into(),                format!("H-h-{margin_px}")),
        WatermarkPosition::BottomRight  => (format!("W-w-{margin_px}"),     format!("H-h-{margin_px}")),
    }
}

/// Compute a deterministic output filename for a given bundle + file.
/// `position` is the 1-indexed file ordinal within its kind.
///
/// Template currently fixed: `{date}_{persona}_{NN}.jpg`. When
/// `persona` is empty, omits the persona segment. Rename is a pure
/// helper — pair with `process_image` writing to that path.
pub fn rename_output(
    date: &str,
    persona: &str,
    position: i64,
    original_basename: &str,
) -> String {
    let stem = match Path::new(original_basename).file_stem() {
        Some(s) => s.to_string_lossy().to_string(),
        None => original_basename.to_string(),
    };
    let _ = stem; // The current template ignores the stem; kept for
                   // future templating where Robert wants to preserve
                   // a hint of the original name.
    let nn = format!("{:02}", position);
    if persona.is_empty() {
        format!("{date}_{nn}.jpg")
    } else {
        format!("{date}_{persona}_{nn}.jpg")
    }
}

/// Convenience: compose the on-disk output path for a processed file.
/// Layout: `<workspace>/processed/<basename>__<op>.jpg`.
pub fn output_path(workspace: &Path, in_zip_path: &str, op_kind: &str) -> PathBuf {
    let stem = Path::new(in_zip_path)
        .file_stem()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_else(|| "out".to_string());
    workspace.join("processed").join(format!("{stem}__{op_kind}.jpg"))
}

// Used by tests to assemble a tiny RGB image without an external file.
#[allow(dead_code)]
fn test_image(w: u32, h: u32, c: [u8; 3]) -> DynamicImage {
    let mut img = image::ImageBuffer::from_pixel(w, h, image::Rgb(c));
    // Pixel mutation just to keep the rustc warning quiet; not actually
    // needed otherwise.
    let _ = img.get_pixel_mut(0, 0);
    DynamicImage::ImageRgb8(img)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    // The PaperDaisy bytes shipped with SideMolly's resource bundle.
    const PAPER_DAISY: &[u8] = include_bytes!("../resources/fonts/PaperDaisy.ttf");

    fn write_source(dir: &Path, name: &str, color: [u8; 3], w: u32, h: u32) -> PathBuf {
        let p = dir.join(name);
        let img = test_image(w, h, color);
        img.save(&p).unwrap();
        p
    }

    #[test]
    fn strip_exif_only_round_trips() {
        let dir = TempDir::new().unwrap();
        let src = write_source(dir.path(), "src.jpg", [200, 100, 50], 256, 128);
        let dst = dir.path().join("out.jpg");
        let ops = ImageOps { strip_exif: true, ..Default::default() };
        process_image(&src, &dst, ops, None, PAPER_DAISY, 0).unwrap();
        let out = image::open(&dst).unwrap();
        assert_eq!(out.width(), 256);
        assert_eq!(out.height(), 128);
    }

    #[test]
    fn watermark_modifies_corner_pixels() {
        let dir = TempDir::new().unwrap();
        let src = write_source(dir.path(), "src.jpg", [240, 240, 240], 512, 256);
        let dst = dir.path().join("watermarked.jpg");
        let profile = WatermarkProfile {
            text: "TEST".to_string(),
            opacity_percent: 100, // solid for the diff check
            position: WatermarkPosition::BottomRight,
            font_size_pct: 10.0,  // big enough that the glyphs definitely paint
            margin_pct: 2.5,
        };
        let ops = ImageOps { watermark: true, strip_exif: true, ..Default::default() };
        process_image(&src, &dst, ops, Some(&profile), PAPER_DAISY, 0).unwrap();

        let out = image::open(&dst).unwrap().to_rgb8();
        // The bottom-right region should contain SOME non-light-grey
        // pixels — the rasterized "TEST" text drawn at full white over
        // light grey will produce a small but detectable shift.
        let (w, h) = (out.width(), out.height());
        let mut any_changed = false;
        for y in (h * 3 / 4)..h {
            for x in (w * 3 / 4)..w {
                let p = out.get_pixel(x, y);
                if p[0] != 240 || p[1] != 240 || p[2] != 240 {
                    any_changed = true;
                    break;
                }
            }
            if any_changed { break; }
        }
        assert!(any_changed, "bottom-right quadrant should show watermark drawing");

        // Sanity: top-left quadrant should be untouched.
        let p = out.get_pixel(5, 5);
        assert!(
            p[0] >= 235 && p[1] >= 235 && p[2] >= 235,
            "top-left should still be ~light grey, got {p:?}",
        );
    }

    #[test]
    fn watermark_position_top_left_paints_top_left() {
        let dir = TempDir::new().unwrap();
        let src = write_source(dir.path(), "src.jpg", [240, 240, 240], 512, 256);
        let dst = dir.path().join("tl.jpg");
        let profile = WatermarkProfile {
            text: "TEST".to_string(),
            opacity_percent: 100,
            position: WatermarkPosition::TopLeft,
            font_size_pct: 10.0,
            margin_pct: 2.5,
        };
        let ops = ImageOps { watermark: true, ..Default::default() };
        process_image(&src, &dst, ops, Some(&profile), PAPER_DAISY, 0).unwrap();
        let out = image::open(&dst).unwrap().to_rgb8();
        let (w, h) = (out.width(), out.height());

        let mut tl_changed = false;
        for y in 5..(h / 4) {
            for x in 5..(w / 4) {
                let p = out.get_pixel(x, y);
                if p[0] != 240 || p[1] != 240 || p[2] != 240 { tl_changed = true; break; }
            }
            if tl_changed { break; }
        }
        assert!(tl_changed, "top-left should show drawing for TopLeft position");
    }

    #[test]
    fn zero_opacity_is_a_no_op_for_watermark() {
        let dir = TempDir::new().unwrap();
        let src = write_source(dir.path(), "src.jpg", [240, 240, 240], 256, 128);
        let dst = dir.path().join("invisible.jpg");
        let profile = WatermarkProfile {
            text: "TEST".to_string(),
            opacity_percent: 0, // <- shortcuts inside process_image
            position: WatermarkPosition::BottomRight,
            font_size_pct: 10.0,
            margin_pct: 2.5,
        };
        let ops = ImageOps { watermark: true, ..Default::default() };
        process_image(&src, &dst, ops, Some(&profile), PAPER_DAISY, 0).unwrap();
        // No pixel-level assertion needed; just confirm we got a valid
        // image out and didn't try to draw with 0 opacity.
        let out = image::open(&dst).unwrap();
        assert_eq!(out.width(), 256);
    }

    #[test]
    fn output_path_layout_is_stable() {
        let p = output_path(Path::new("/work/uid"), "FanSite/01_01_IMG_3488.jpg", "watermark_strip");
        assert_eq!(p.to_string_lossy(), "/work/uid/processed/01_01_IMG_3488__watermark_strip.jpg");
    }

    #[test]
    fn rename_template_basic() {
        assert_eq!(rename_output("2026-05-22", "CoC", 1, "IMG_3488.jpg"),
                   "2026-05-22_CoC_01.jpg");
        assert_eq!(rename_output("2026-05-22", "", 7, "anything.png"),
                   "2026-05-22_07.jpg");
        assert_eq!(rename_output("2026-05-22", "PoA", 99, "x"),
                   "2026-05-22_PoA_99.jpg");
    }

    #[test]
    fn op_kind_combination() {
        assert_eq!(ImageOps { watermark: true, strip_exif: true, rename: true }.op_kind(),
                   "watermark_strip_rename");
        assert_eq!(ImageOps { watermark: true, strip_exif: true, rename: false }.op_kind(),
                   "watermark_strip");
        assert_eq!(ImageOps { watermark: true, ..Default::default() }.op_kind(),
                   "watermark");
        assert_eq!(ImageOps { rename: true, ..Default::default() }.op_kind(),
                   "rename");
    }

    #[test]
    fn render_watermark_png_produces_valid_rgba_png() {
        let profile = WatermarkProfile {
            text: "CurseOfCurves".into(), opacity_percent: 20,
            position: WatermarkPosition::BottomRight,
            font_size_pct: 4.0, margin_pct: 2.5,
        };
        // 60px font size — typical sub-HD video output (1440 ref @ 4%).
        let bytes = render_watermark_png(&profile, PAPER_DAISY, 60.0).unwrap();
        // PNG magic bytes.
        assert_eq!(&bytes[0..8], &[0x89, b'P', b'N', b'G', 0x0d, 0x0a, 0x1a, 0x0a]);
        // Decodes back as an RGBA image with non-trivial dimensions.
        let img = image::load_from_memory(&bytes).unwrap().to_rgba8();
        assert!(img.width() > 16);
        assert!(img.height() > 16);
        // Background is transparent — sample a corner that's outside the
        // glyph stroke region.
        let corner = img.get_pixel(0, 0);
        assert_eq!(corner[3], 0, "outside-glyph alpha must be 0 (transparent)");
    }

    #[test]
    fn render_watermark_png_has_dark_outline_for_contrast() {
        // Even at a low fill opacity, the legibility outline must paint
        // some dark, non-transparent pixels so the watermark reads on a
        // bright background (the "can't even see it" fix).
        let profile = WatermarkProfile {
            text: "CurseOfCurves".into(), opacity_percent: 20,
            position: WatermarkPosition::BottomRight,
            font_size_pct: 4.0, margin_pct: 2.5,
        };
        let bytes = render_watermark_png(&profile, PAPER_DAISY, 60.0).unwrap();
        let img = image::load_from_memory(&bytes).unwrap().to_rgba8();
        let mut dark_opaque = false;
        for p in img.pixels() {
            // Outline pixels: dark RGB with meaningful alpha.
            if p[3] > 60 && p[0] < 80 && p[1] < 80 && p[2] < 80 {
                dark_opaque = true;
                break;
            }
        }
        assert!(dark_opaque, "watermark should carry a dark contrast outline");
    }

    #[test]
    fn overlay_xy_expr_bottom_right_uses_w_w_h_h_minus_margin() {
        let (x, y) = overlay_xy_expr(WatermarkPosition::BottomRight, 25);
        assert_eq!(x, "W-w-25");
        assert_eq!(y, "H-h-25");
    }

    #[test]
    fn overlay_xy_expr_middle_center_uses_centered_formula() {
        let (x, y) = overlay_xy_expr(WatermarkPosition::MiddleCenter, 25);
        assert_eq!(x, "(W-w)/2");
        assert_eq!(y, "(H-h)/2");
    }

    #[test]
    fn overlay_xy_expr_top_left_uses_margin_for_both() {
        let (x, y) = overlay_xy_expr(WatermarkPosition::TopLeft, 30);
        assert_eq!(x, "30");
        assert_eq!(y, "30");
    }

    #[test]
    fn position_parse_round_trips_all_nine() {
        for s in &[
            "top-left", "top-center", "top-right",
            "middle-left", "middle-center", "middle-right",
            "bottom-left", "bottom-center", "bottom-right",
        ] {
            WatermarkPosition::parse(s).unwrap_or_else(|_| panic!("failed to parse {s}"));
        }
        assert!(WatermarkPosition::parse("nonsense").is_err());
    }
}

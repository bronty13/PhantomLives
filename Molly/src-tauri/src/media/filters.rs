//! Pure ffmpeg argv / filtergraph builders for the media engine.
//!
//! Everything here is deterministic string construction with no I/O and no
//! Tauri types — so it unit-tests cleanly and is the prime candidate for the
//! future shared `phantomlives-media` crate (see HANDOFF). The frontend
//! pre-computes the output geometry (via `computeOutputSize`) and sends it as
//! pixels, so this layer never re-derives crop math from fractions — that
//! keeps the caption PNG (sized in JS) and ffmpeg's crop/scale pixel-identical.

/// Output geometry for a render, all in pixels. `crop` is the source rectangle
/// to take (sw×sh at sx,sy); `None` means the whole frame. `out_w`/`out_h` are
/// the final dimensions after scaling.
#[derive(Debug, Clone, Copy)]
pub struct Geom {
    pub out_w: u32,
    pub out_h: u32,
    /// (sw, sh, sx, sy) source crop rectangle in pixels.
    pub crop: Option<(u32, u32, u32, u32)>,
}

/// A whole render spec the filtergraph builders consume.
#[derive(Debug, Clone)]
pub struct FilterSpec {
    pub geom: Geom,
    /// True when the source is HDR (PQ/HLG) and must be tone-mapped to SDR.
    pub is_hdr: bool,
    /// Frame rate for GIF output; `None` for MP4/frame.
    pub fps: Option<u32>,
    /// True when a full-frame transparent caption PNG is supplied as input 1.
    pub has_caption: bool,
}

/// Force a dimension even (H.264 / yuv420p chroma needs even W/H), min 2.
fn even(n: u32) -> u32 {
    let v = n.max(2);
    v - (v % 2)
}

/// True for HDR transfer characteristics (ffprobe `color_transfer`): PQ/HDR10
/// (`smpte2084`) or HLG (`arib-std-b67`). iPhone Dolby Vision Profile 8.4 has
/// an HLG-compatible base layer, so it reports one of these and tone-maps via
/// the zscale chain without needing libplacebo.
pub fn is_hdr_transfer(color_transfer: &str) -> bool {
    matches!(color_transfer.trim(), "smpte2084" | "arib-std-b67")
}

/// HDR→SDR tone-map segment (BT.709 SDR out). Empty for SDR sources so they're
/// passed through untouched. Trailing comma so it prepends cleanly. Requires
/// the ffmpeg build to include zimg (zscale) — guaranteed for the bundled
/// static builds (CI guardrail).
fn tonemap_segment(is_hdr: bool) -> String {
    if is_hdr {
        "zscale=t=linear:npl=100,format=gbrpf32le,zscale=p=bt709,\
         tonemap=tonemap=hable:desat=0,zscale=t=bt709:m=bt709:r=tv,format=yuv420p,"
            .to_string()
    } else {
        String::new()
    }
}

/// `tonemap? + crop? + scale` ending at the final even output dims. Adds
/// `,fps=N` when this is a GIF render. No caption / split here.
fn video_chain(spec: &FilterSpec) -> String {
    let mut s = tonemap_segment(spec.is_hdr);
    if let Some((sw, sh, sx, sy)) = spec.geom.crop {
        // Even crop dims + offsets keep chroma aligned.
        s.push_str(&format!(
            "crop={}:{}:{}:{},",
            even(sw),
            even(sh),
            sx - (sx % 2),
            sy - (sy % 2)
        ));
    }
    s.push_str(&format!("scale={}:{}", even(spec.geom.out_w), even(spec.geom.out_h)));
    if let Some(fps) = spec.fps {
        s.push_str(&format!(",fps={fps}"));
    }
    s
}

/// `-filter_complex` for an animated GIF: chain → optional caption overlay →
/// split → palettegen(max_colors) → paletteuse. `colors` is 256/128/64.
pub fn gif_filter_complex(spec: &FilterSpec, colors: u32) -> String {
    let chain = video_chain(spec);
    let pre = if spec.has_caption {
        // Overlay the full-frame caption PNG before palette so its colours count.
        format!("[0:v]{chain}[base];[base][1:v]overlay=0:0[c]")
    } else {
        format!("[0:v]{chain}[c]")
    };
    format!(
        "{pre};[c]split[a][b];\
         [a]palettegen=max_colors={colors}:stats_mode=diff[p];\
         [b][p]paletteuse=dither=sierra2_4a"
    )
}

/// `-filter_complex` for MP4/frame: chain → optional caption overlay, output
/// labelled `[v]` for `-map`.
pub fn simple_filter_complex(spec: &FilterSpec) -> String {
    let chain = video_chain(spec);
    if spec.has_caption {
        format!("[0:v]{chain}[v0];[v0][1:v]overlay=0:0[v]")
    } else {
        format!("[0:v]{chain}[v]")
    }
}

/// Quality knob → GIF palette size. Mirrors the TS `paletteColors`.
pub fn gif_colors(quality: &str) -> u32 {
    match quality {
        "high" => 256,
        "medium" => 128,
        "low" => 64,
        _ => 256,
    }
}

fn fmt_secs(s: f64) -> String {
    // Fixed 3-decimal seconds; avoids locale/exponent surprises in argv.
    format!("{:.3}", s.max(0.0))
}

/// argv for a GIF render. `caption` present ⇒ added as the 2nd input.
pub fn gif_args(
    src: &str,
    out: &str,
    caption: Option<&str>,
    start_sec: f64,
    dur_sec: f64,
    spec: &FilterSpec,
    colors: u32,
) -> Vec<String> {
    let mut a = base_args();
    a.extend(["-ss".into(), fmt_secs(start_sec), "-t".into(), fmt_secs(dur_sec)]);
    a.extend(["-i".into(), src.into()]);
    if let Some(cap) = caption {
        a.extend(["-i".into(), cap.into()]);
    }
    a.extend(["-filter_complex".into(), gif_filter_complex(spec, colors)]);
    a.push(out.into());
    a
}

/// argv for a teaser MP4 render (H.264 + AAC + faststart, ≤100 MB backstop).
pub fn teaser_args(
    src: &str,
    out: &str,
    caption: Option<&str>,
    start_sec: f64,
    dur_sec: f64,
    spec: &FilterSpec,
    include_audio: bool,
    video_max_kbps: u32,
) -> Vec<String> {
    let mut a = base_args();
    a.extend(["-ss".into(), fmt_secs(start_sec), "-t".into(), fmt_secs(dur_sec)]);
    a.extend(["-i".into(), src.into()]);
    if let Some(cap) = caption {
        a.extend(["-i".into(), cap.into()]);
    }
    a.extend(["-filter_complex".into(), simple_filter_complex(spec)]);
    a.extend(["-map".into(), "[v]".into()]);
    if include_audio {
        // `?` makes the audio map optional so silent sources don't error.
        a.extend(["-map".into(), "0:a?".into()]);
    }
    // Quality-first: CRF 20 (visually high) with a `maxrate` ceiling derived
    // from the 100 MB / duration budget, so short clips stay near-lossless and
    // long ones fill the budget without ever overflowing it (no truncation).
    // `veryfast` (was `medium`): CRF targets a *quality* level independent of
    // preset, so the visual result is ~identical — the faster preset just
    // reaches it less efficiently (slightly larger files, comfortably inside
    // the 100 MB budget) in a fraction of the encode time. This is the big
    // lever for Windows software-encode speed without sacrificing how it looks.
    a.extend([
        "-c:v".into(), "libx264".into(),
        "-preset".into(), "veryfast".into(),
        "-crf".into(), "20".into(),
        "-maxrate".into(), format!("{video_max_kbps}k"),
        "-bufsize".into(), format!("{}k", video_max_kbps.saturating_mul(2)),
        "-pix_fmt".into(), "yuv420p".into(),
    ]);
    if include_audio {
        a.extend(["-c:a".into(), "aac".into(), "-b:a".into(), "128k".into()]);
    }
    a.extend([
        "-map_metadata".into(), "-1".into(),
        "-movflags".into(), "+faststart".into(),
        "-fs".into(), "104857600".into(), // 100 MB hard backstop
    ]);
    a.push(out.into());
    a
}

/// Video bitrate ceiling (kbps) that keeps `dur_sec` of output under a
/// `budget_bytes` file-size cap, leaving room for ~128 kbps audio. Used as the
/// x264 `-maxrate` alongside CRF so the encode fills the byte budget without
/// ever overflowing it (no truncation). `floor_kbps` is the lowest value the
/// caller will tolerate. Pure.
///
/// The 0.95 multiplier is muxing/VBR headroom. The 100 Mbps upper clamp keeps
/// the value inside x264's 32-bit `-maxrate`/`-bufsize` range (INT_MAX ≈ 2.147
/// Gbps; `bufsize` is 2×, so the effective ceiling is INT_MAX/2) — without it a
/// sub-0.37 s clip's astronomically high budget made x264 abort with "maxrate
/// out of range". CRF + the caller's `-fs` backstop keep the real file size in
/// check, so 100 Mbps is pure headroom no normal encode approaches.
pub fn size_budget_video_kbps(
    budget_bytes: u64,
    dur_sec: f64,
    include_audio: bool,
    floor_kbps: u32,
) -> u32 {
    let d = dur_sec.max(0.2);
    let total_kbps = (budget_bytes as f64 * 8.0 * 0.95 / d / 1000.0) as u32;
    let audio_kbps = if include_audio { 128 } else { 0 };
    total_kbps.saturating_sub(audio_kbps).clamp(floor_kbps, 100_000)
}

/// Teaser video bitrate ceiling: the ≤100 MB budget with a 1 Mbps floor.
/// Thin wrapper over [`size_budget_video_kbps`] (kept for the teaser callers).
pub fn teaser_video_max_kbps(dur_sec: f64, include_audio: bool) -> u32 {
    size_budget_video_kbps(104_857_600, dur_sec, include_audio, 1000)
}

/// Output dims that scale (w,h) DOWN to fit inside (max_w,max_h) preserving
/// aspect ratio — never upscaling — with even dims (H.264/yuv420p need even
/// W/H). Pure.
pub fn fit_within(w: u32, h: u32, max_w: u32, max_h: u32) -> (u32, u32) {
    let (w, h) = (w.max(1), h.max(1));
    // Scaling factor, capped at 1.0 so we never enlarge a small source.
    let s = (max_w as f64 / w as f64)
        .min(max_h as f64 / h as f64)
        .min(1.0);
    (even((w as f64 * s).round() as u32), even((h as f64 * s).round() as u32))
}

/// Target Full-HD bounding box for the Squish encoder, oriented to match the
/// source: landscape → 1920×1080, portrait → 1080×1920. Capped at the source's
/// own size so a clip already ≤ Full-HD is left alone. Pure.
///
/// NOTE: `w`/`h` are ffprobe's *coded* dims (rotation-unaware). A clip stored
/// landscape with a 90° rotation flag is displayed portrait; `shrink_args` pairs
/// this box with `force_original_aspect_ratio=decrease` so ffmpeg fits the real
/// (auto-rotated) frame inside it without ever distorting — at worst such a clip
/// lands a little smaller than its ideal portrait box, never stretched.
pub fn shrink_box(w: u32, h: u32) -> (u32, u32) {
    let (max_w, max_h) = if w >= h { (1920, 1080) } else { (1080, 1920) };
    fit_within(w, h, max_w, max_h)
}

/// argv for a whole-file "shrink to fit a byte budget" H.264/AAC encode (the
/// Squish feature). CRF 20 quality, capped by a budget-derived `-maxrate` so the
/// encode fills the budget without overflowing it (no truncation); `-fs` is a
/// hard byte backstop that should never trip when the bitrate target holds.
/// Scales to fit the `box_w`×`box_h` bounding box (aspect-preserving, even dims,
/// never upscaling) and tone-maps HDR→SDR. Whole file (no `-ss`/`-t`).
pub fn shrink_args(
    src: &str,
    out: &str,
    box_w: u32,
    box_h: u32,
    video_max_kbps: u32,
    include_audio: bool,
    is_hdr: bool,
    fs_backstop_bytes: u64,
) -> Vec<String> {
    let mut a = base_args();
    a.extend(["-i".into(), src.into()]);
    // `force_original_aspect_ratio=decrease` fits the (auto-rotated) frame inside
    // the box preserving aspect; `force_divisible_by=2` keeps W/H even for x264.
    let vf = format!(
        "{}scale={}:{}:force_original_aspect_ratio=decrease:force_divisible_by=2:flags=lanczos",
        tonemap_segment(is_hdr),
        box_w,
        box_h,
    );
    a.extend(["-vf".into(), vf]);
    a.extend([
        "-c:v".into(), "libx264".into(),
        "-preset".into(), "fast".into(),
        "-crf".into(), "20".into(),
        "-maxrate".into(), format!("{video_max_kbps}k"),
        "-bufsize".into(), format!("{}k", video_max_kbps.saturating_mul(2)),
        "-pix_fmt".into(), "yuv420p".into(),
    ]);
    if include_audio {
        a.extend(["-c:a".into(), "aac".into(), "-b:a".into(), "128k".into()]);
    } else {
        a.push("-an".into());
    }
    a.extend([
        "-map_metadata".into(), "-1".into(),
        "-movflags".into(), "+faststart".into(),
        "-fs".into(), fs_backstop_bytes.to_string(),
    ]);
    a.push(out.into());
    a
}

/// argv for a single-frame JPEG grab.
pub fn frame_args(
    src: &str,
    out: &str,
    caption: Option<&str>,
    time_sec: f64,
    spec: &FilterSpec,
) -> Vec<String> {
    let mut a = base_args();
    a.extend(["-ss".into(), fmt_secs(time_sec)]);
    a.extend(["-i".into(), src.into()]);
    if let Some(cap) = caption {
        a.extend(["-i".into(), cap.into()]);
    }
    a.extend(["-filter_complex".into(), simple_filter_complex(spec)]);
    a.extend(["-map".into(), "[v]".into(), "-frames:v".into(), "1".into(), "-q:v".into(), "2".into()]);
    a.push(out.into());
    a
}

/// argv for a low-res H.264 preview proxy (UI scrubbing of undecodable
/// sources). Whole source, muted, short GOP for snappy seeking.
pub fn proxy_args(src: &str, out: &str, is_hdr: bool) -> Vec<String> {
    let mut a = base_args();
    a.extend(["-i".into(), src.into()]);
    let vf = format!("{}scale=480:-2:flags=fast_bilinear", tonemap_segment(is_hdr));
    a.extend([
        "-vf".into(), vf,
        "-c:v".into(), "libx264".into(),
        "-preset".into(), "ultrafast".into(),
        "-crf".into(), "28".into(),
        "-pix_fmt".into(), "yuv420p".into(),
        "-an".into(),
        "-g".into(), "15".into(),
        "-movflags".into(), "+faststart".into(),
    ]);
    a.push(out.into());
    a
}

/// Common leading args: overwrite, quiet, machine-readable progress on stdout.
fn base_args() -> Vec<String> {
    vec![
        "-y".into(),
        "-hide_banner".into(),
        "-loglevel".into(), "error".into(),
        "-progress".into(), "pipe:1".into(),
        "-nostats".into(),
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    fn spec(crop: Option<(u32, u32, u32, u32)>, is_hdr: bool, fps: Option<u32>, cap: bool) -> FilterSpec {
        FilterSpec { geom: Geom { out_w: 320, out_h: 240, crop }, is_hdr, fps, has_caption: cap }
    }

    #[test]
    fn hdr_transfer_truth_table() {
        assert!(is_hdr_transfer("smpte2084"));
        assert!(is_hdr_transfer("arib-std-b67"));
        assert!(is_hdr_transfer("  smpte2084 ")); // trimmed
        assert!(!is_hdr_transfer("bt709"));
        assert!(!is_hdr_transfer(""));
        assert!(!is_hdr_transfer("unknown"));
    }

    #[test]
    fn tonemap_applied_only_when_hdr() {
        let hdr = video_chain(&spec(None, true, None, false));
        assert!(hdr.contains("zscale=t=linear") && hdr.contains("tonemap="));
        let sdr = video_chain(&spec(None, false, None, false));
        assert!(!sdr.contains("zscale") && !sdr.contains("tonemap"));
        // SDR chain is just the scale.
        assert_eq!(sdr, "scale=320:240");
    }

    #[test]
    fn crop_segment_present_and_even() {
        let c = video_chain(&spec(Some((201, 101, 11, 7)), false, None, false));
        // dims forced even (201→200, 101→100), offsets floored even (11→10, 7→6).
        assert!(c.starts_with("crop=200:100:10:6,scale=320:240"));
    }

    #[test]
    fn no_crop_chain_is_scale_only() {
        assert_eq!(video_chain(&spec(None, false, None, false)), "scale=320:240");
    }

    #[test]
    fn output_dims_forced_even() {
        let c = video_chain(&spec(None, false, None, false));
        // 320x240 already even; verify odd is bumped down.
        let odd = video_chain(&FilterSpec { geom: Geom { out_w: 321, out_h: 241, crop: None }, is_hdr: false, fps: None, has_caption: false });
        assert!(c.contains("scale=320:240"));
        assert!(odd.contains("scale=320:240"));
    }

    #[test]
    fn gif_colors_map() {
        assert_eq!(gif_colors("high"), 256);
        assert_eq!(gif_colors("medium"), 128);
        assert_eq!(gif_colors("low"), 64);
        assert_eq!(gif_colors("???"), 256);
    }

    #[test]
    fn gif_filtergraph_has_palette_pipeline_and_colors() {
        let g = gif_filter_complex(&spec(None, false, Some(12), false), 128);
        assert!(g.contains("split"));
        assert!(g.contains("palettegen=max_colors=128:stats_mode=diff"));
        assert!(g.contains("paletteuse=dither=sierra2_4a"));
        assert!(g.contains("fps=12"));
    }

    #[test]
    fn gif_caption_overlays_before_split() {
        let g = gif_filter_complex(&spec(None, false, Some(10), true), 256);
        let overlay = g.find("overlay=0:0").unwrap();
        let split = g.find("split").unwrap();
        assert!(overlay < split, "caption overlay must precede split so palette includes it");
    }

    #[test]
    fn simple_filtergraph_labels_v_and_overlays_caption() {
        let no_cap = simple_filter_complex(&spec(None, false, None, false));
        assert!(no_cap.ends_with("[v]"));
        assert!(!no_cap.contains("overlay"));
        let cap = simple_filter_complex(&spec(None, false, None, true));
        assert!(cap.contains("overlay=0:0[v]"));
    }

    #[test]
    fn teaser_args_have_h264_aac_faststart_and_optional_audio() {
        let spec = spec(None, false, None, false);
        let with_audio = teaser_args("in.mov", "out.mp4", None, 0.3, 2.7, &spec, true, 8000);
        let joined = with_audio.join(" ");
        assert!(joined.contains("-c:v libx264"));
        assert!(joined.contains("-preset veryfast"));
        assert!(joined.contains("-crf 20"));
        assert!(joined.contains("-maxrate 8000k"));
        assert!(joined.contains("-bufsize 16000k"));
        assert!(joined.contains("-pix_fmt yuv420p"));
        assert!(joined.contains("-movflags +faststart"));
        assert!(joined.contains("-c:a aac"));
        assert!(joined.contains("-map 0:a?"));
        assert!(joined.contains("-ss 0.300 -t 2.700"));
        assert!(joined.contains("-fs 104857600"));

        let no_audio = teaser_args("in.mov", "out.mp4", None, 0.0, 5.0, &spec, false, 8000);
        let j2 = no_audio.join(" ");
        assert!(!j2.contains("-c:a aac"));
        assert!(!j2.contains("0:a?"));
    }

    #[test]
    fn teaser_budget_fits_100mb_and_clamps() {
        // 60s with audio: total ~13.3 Mbps − 128 kbps audio, comfortably > 1 Mbps.
        let k = teaser_video_max_kbps(60.0, true);
        assert!(k > 10_000 && k < 14_000);
        // total bits ≈ (k + 128) kbps * 60s, must stay under 100 MB.
        assert!(((k + 128) as f64) * 1000.0 * 60.0 / 8.0 <= 104_857_600.0);
        // Very long clip clamps to the 1 Mbps floor.
        assert_eq!(teaser_video_max_kbps(100_000.0, true), 1000);
    }

    #[test]
    fn teaser_max_kbps_caps_short_clips_within_x264_range() {
        // x264 `-maxrate`/`-bufsize` take a 32-bit bits/s value (INT_MAX ≈
        // 2.147 Gbps); `bufsize` is 2× maxrate, so maxrate must stay ≤ ~1.07
        // Gbps. The raw 100 MB / duration budget overflowed this for short
        // clips (regression: a ~0.2 s clip emitted 3984460k ≈ 3.98 Gbps and
        // x264 aborted with "maxrate out of range").
        for &dur in &[0.05, 0.1, 0.2, 0.37, 1.0] {
            for &audio in &[true, false] {
                let k = teaser_video_max_kbps(dur, audio);
                assert!(k <= 100_000, "dur={dur} audio={audio} → {k}k exceeds cap");
                // maxrate and 2× bufsize both stay inside x264's INT_MAX bits/s.
                assert!((k as u64) * 2 * 1000 < i32::MAX as u64);
            }
        }
        // The cap actually bites for sub-second clips.
        assert_eq!(teaser_video_max_kbps(0.2, true), 100_000);
    }

    #[test]
    fn fit_within_downscales_preserves_aspect_no_upscale() {
        // 4K landscape into a 1920×1080 box → exactly Full-HD.
        assert_eq!(fit_within(3840, 2160, 1920, 1080), (1920, 1080));
        // Already smaller than the box → left untouched (never enlarged).
        assert_eq!(fit_within(1280, 720, 1920, 1080), (1280, 720));
        // Aspect preserved when only one dim binds; result dims forced even.
        let (w, h) = fit_within(4000, 3000, 1920, 1080); // 4:3 → height binds
        assert_eq!(h, 1080);
        assert_eq!(w, 1440);
        assert_eq!((w % 2, h % 2), (0, 0));
    }

    #[test]
    fn shrink_box_is_orientation_aware_and_capped() {
        assert_eq!(shrink_box(3840, 2160), (1920, 1080)); // 4K landscape
        assert_eq!(shrink_box(2160, 3840), (1080, 1920)); // 4K portrait
        assert_eq!(shrink_box(1080, 1080), (1080, 1080)); // square, already small
        assert_eq!(shrink_box(1280, 720), (1280, 720));   // sub-HD, untouched
    }

    #[test]
    fn size_budget_kbps_fits_budget_and_honors_floor() {
        // ~0.9 GB over 10 min: well within range, fills the budget.
        let k = size_budget_video_kbps(920_000_000, 600.0, true, 300);
        assert!(k > 300 && k < 100_000);
        // (video + audio) bits must stay under the budget.
        assert!(((k + 128) as f64) * 1000.0 * 600.0 / 8.0 <= 920_000_000.0);
        // A very long clip clamps to the (low) shrink floor, not the teaser's.
        assert_eq!(size_budget_video_kbps(920_000_000, 100_000.0, true, 300), 300);
        // Teaser wrapper still uses its 1 Mbps floor — unchanged behaviour.
        assert_eq!(teaser_video_max_kbps(100_000.0, true), 1000);
    }

    #[test]
    fn shrink_args_encode_shape() {
        let with_audio = shrink_args("in.mov", "out.mov", 1920, 1080, 8000, true, false, 990_000_000);
        let j = with_audio.join(" ");
        assert!(j.contains("-c:v libx264"));
        assert!(j.contains("-crf 20"));
        assert!(j.contains("-maxrate 8000k"));
        assert!(j.contains("-bufsize 16000k"));
        assert!(j.contains("scale=1920:1080:force_original_aspect_ratio=decrease:force_divisible_by=2"));
        assert!(j.contains("-movflags +faststart"));
        assert!(j.contains("-fs 990000000"));
        assert!(j.contains("-c:a aac"));
        assert!(!j.contains("-an"));
        // No-audio variant mutes and omits the audio codec.
        let muted = shrink_args("in.mov", "out.mov", 1280, 720, 4000, false, false, 990_000_000).join(" ");
        assert!(muted.contains("-an"));
        assert!(!muted.contains("-c:a aac"));
        // HDR source gets the tonemap chain prepended to the scale.
        let hdr = shrink_args("in.mov", "out.mov", 1920, 1080, 8000, true, true, 990_000_000).join(" ");
        assert!(hdr.contains("zscale=t=linear") && hdr.contains("tonemap="));
    }

    #[test]
    fn caption_added_as_second_input_when_present() {
        let spec = spec(None, false, Some(12), true);
        let args = gif_args("in.mov", "out.gif", Some("cap.png"), 0.0, 3.0, &spec, 256);
        // two -i inputs: source then caption.
        let inputs: Vec<usize> = args.iter().enumerate().filter(|(_, x)| *x == "-i").map(|(i, _)| i).collect();
        assert_eq!(inputs.len(), 2);
        assert_eq!(args[inputs[1] + 1], "cap.png");
    }

    #[test]
    fn frame_args_grab_single_frame() {
        let spec = spec(None, false, None, false);
        let args = frame_args("in.mov", "out.jpg", None, 1.5, &spec).join(" ");
        assert!(args.contains("-frames:v 1"));
        assert!(args.contains("-ss 1.500"));
        assert!(args.contains("-q:v 2"));
    }

    #[test]
    fn proxy_args_are_lowres_muted() {
        let args = proxy_args("in.mov", "proxy.mp4", false).join(" ");
        assert!(args.contains("scale=480:-2"));
        assert!(args.contains("-an"));
        assert!(args.contains("-preset ultrafast"));
        let hdr = proxy_args("in.mov", "proxy.mp4", true).join(" ");
        assert!(hdr.contains("zscale=t=linear"));
    }

    #[test]
    fn all_renders_input_seek_and_emit_progress() {
        let s = spec(None, false, Some(12), false);
        for args in [
            gif_args("i", "o.gif", None, 1.0, 2.0, &s, 256),
            teaser_args("i", "o.mp4", None, 1.0, 2.0, &s, true, 8000),
            frame_args("i", "o.jpg", None, 1.0, &s),
        ] {
            let j = args.join(" ");
            assert!(j.contains("-progress pipe:1"));
            // -ss appears before -i (input seeking).
            let ss = args.iter().position(|x| x == "-ss").unwrap();
            let i = args.iter().position(|x| x == "-i").unwrap();
            assert!(ss < i, "must input-seek (-ss before -i)");
        }
    }
}

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
    a.extend([
        "-c:v".into(), "libx264".into(),
        "-preset".into(), "medium".into(),
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

/// Video bitrate ceiling (kbps) that keeps `dur_sec` under the 100 MB cap,
/// leaving room for audio. Used as x264 `-maxrate` alongside CRF. Pure.
pub fn teaser_video_max_kbps(dur_sec: f64, include_audio: bool) -> u32 {
    let d = dur_sec.max(0.2);
    // 100 MB * 8 bits * 0.95 headroom, in kbits, over the duration.
    let total_kbps = (104_857_600.0 * 8.0 * 0.95 / d / 1000.0) as u32;
    let audio_kbps = if include_audio { 128 } else { 0 };
    total_kbps.saturating_sub(audio_kbps).max(1000)
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
        assert!(joined.contains("-preset medium"));
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

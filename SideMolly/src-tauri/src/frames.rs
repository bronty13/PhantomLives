//! Sampled video frames for the SideMolly Summary grid.
//!
//! Instead of one thumbnail per file, the summary shows a total of N frames
//! (the configurable thumbnail count) sampled across the bundle's videos —
//! distributed evenly (3 videos, N=30 → 10 each), each frame evenly spaced
//! across its own timeline, and **rotation-corrected** (ffmpeg `transpose`,
//! matching auto-assembly) so they display upright.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use rusqlite::{params, Connection};

use crate::bundles::BundleError;
use crate::thumbnails::{ffmpeg_bin, probe_video_duration, transpose_filter};

/// Max width (px) of a sampled frame JPEG; matches the summary grid's column
/// sizing at the embed DPI.
const FRAME_MAX_DIM: u32 = 256;

/// Distribute `total` frames across `n` videos as evenly as possible; the
/// first `total % n` videos get one extra. Pure + unit-tested.
pub fn distribute(total: usize, n: usize) -> Vec<usize> {
    if n == 0 {
        return Vec::new();
    }
    let base = total / n;
    let rem = total % n;
    (0..n).map(|i| base + usize::from(i < rem)).collect()
}

struct VideoRef {
    in_zip_path: String,
    working_path: String,
    rotation_degrees: i64,
}

/// One representative, rotation-corrected frame per video, in bundle order.
/// `frame` is None when the video's working file is missing or ffmpeg fails.
/// Used by the Summary's per-video transcript preview (frame + first line).
pub struct VideoPreviewFrame {
    pub in_zip_path: String,
    pub frame: Option<PathBuf>,
}

/// Sample exactly one frame from each of the bundle's videos. Separate from
/// `sample_bundle_frames` (which distributes a total across videos) because
/// the per-video transcript preview needs a stable 1:1 video→frame mapping.
pub fn sample_per_video_frames(
    conn: &Connection,
    uid: &str,
    out_dir: &Path,
) -> Result<Vec<VideoPreviewFrame>, BundleError> {
    let videos = load_videos(conn, uid)?;
    let _ = fs::remove_dir_all(out_dir);
    fs::create_dir_all(out_dir)?;
    let mut out = Vec::with_capacity(videos.len());
    for (vi, v) in videos.iter().enumerate() {
        let src = Path::new(&v.working_path);
        let frame = if src.exists() {
            sample_one_video(src, v.rotation_degrees, 1, out_dir, vi).into_iter().next()
        } else {
            None
        };
        out.push(VideoPreviewFrame { in_zip_path: v.in_zip_path.clone(), frame });
    }
    Ok(out)
}

/// Sample a total of `total` frames across all of the bundle's videos. Writes
/// JPEGs into `out_dir` (wiped first) and returns their paths in bundle order.
/// Returns an empty Vec when the bundle has no videos — the caller falls back
/// to rotation-corrected image thumbnails. Best-effort per video: a probe or
/// ffmpeg failure just yields fewer frames, never an error.
pub fn sample_bundle_frames(
    conn: &Connection,
    uid: &str,
    total: i64,
    out_dir: &Path,
) -> Result<Vec<PathBuf>, BundleError> {
    let videos = load_videos(conn, uid)?;
    if videos.is_empty() {
        return Ok(Vec::new());
    }

    // Fresh dir each generation so stale frames never linger.
    let _ = fs::remove_dir_all(out_dir);
    fs::create_dir_all(out_dir)?;

    let counts = distribute(total.max(0) as usize, videos.len());
    let mut out: Vec<PathBuf> = Vec::new();
    for (vi, v) in videos.iter().enumerate() {
        let k = counts[vi];
        if k == 0 {
            continue;
        }
        let src = Path::new(&v.working_path);
        if !src.exists() {
            continue;
        }
        out.extend(sample_one_video(src, v.rotation_degrees, k, out_dir, vi));
    }
    Ok(out)
}

fn load_videos(conn: &Connection, uid: &str) -> Result<Vec<VideoRef>, BundleError> {
    let mut stmt = conn.prepare(
        "SELECT in_zip_path, working_path, rotation_degrees FROM bundle_files
          WHERE bundle_uid = ?1 AND kind = 'video'
                AND working_path IS NOT NULL AND working_path <> ''
          ORDER BY CASE WHEN fansite_day_of_month IS NULL THEN 0 ELSE fansite_day_of_month END,
                   position, in_zip_path",
    )?;
    let rows = stmt.query_map(params![uid], |r| {
        Ok(VideoRef {
            in_zip_path: r.get(0)?,
            working_path: r.get(1)?,
            rotation_degrees: r.get(2)?,
        })
    })?;
    let mut v = Vec::new();
    for r in rows {
        v.push(r?);
    }
    Ok(v)
}

/// Extract `k` evenly-spaced, rotation-corrected frames from one video in a
/// single ffmpeg pass (the `fps` filter). Returns the frames actually written.
fn sample_one_video(
    src: &Path,
    rotation_degrees: i64,
    k: usize,
    out_dir: &Path,
    vi: usize,
) -> Vec<PathBuf> {
    let duration = probe_video_duration(src);

    // Filter chain: rotation first (frames upright), then — when we know the
    // duration and want more than one frame — an fps resample to land ~k
    // frames across the timeline, then scale.
    let mut vf = String::new();
    if let Some(t) = transpose_filter(rotation_degrees) {
        vf.push_str(t);
        vf.push(',');
    }
    let spread = matches!(duration, Some(d) if d > 0.0) && k > 1;
    if let (true, Some(d)) = (spread, duration) {
        let fps = (k as f64) / d;
        vf.push_str(&format!("fps={fps:.6},"));
    }
    vf.push_str(&format!("scale={FRAME_MAX_DIM}:-2:flags=lanczos"));

    let pattern = out_dir.join(format!("v{vi:02}_%03d.jpg"));
    let mut cmd = Command::new(ffmpeg_bin());
    cmd.args(["-y", "-loglevel", "error"]);
    // Single-frame / unknown-duration path: seek to 1s for a representative
    // (non-black) frame instead of t=0.
    if !spread {
        cmd.args(["-ss", "1"]);
    }
    cmd.arg("-i").arg(src);
    cmd.args(["-vf", &vf]);
    cmd.args(["-frames:v", &k.to_string()]);
    cmd.args(["-q:v", "4"]);
    cmd.arg(&pattern);

    let ok = cmd.status().map(|s| s.success()).unwrap_or(false);
    if !ok {
        return Vec::new();
    }

    let mut produced = Vec::new();
    for n in 1..=k {
        let p = out_dir.join(format!("v{vi:02}_{n:03}.jpg"));
        if p.exists() {
            produced.push(p);
        } else {
            break;
        }
    }
    produced
}

#[cfg(test)]
mod tests {
    use super::distribute;

    #[test]
    fn distribute_even() {
        assert_eq!(distribute(30, 3), vec![10, 10, 10]);
    }

    #[test]
    fn distribute_with_remainder_front_loads() {
        assert_eq!(distribute(30, 4), vec![8, 8, 7, 7]);
        assert_eq!(distribute(10, 3), vec![4, 3, 3]);
        assert_eq!(distribute(7, 2), vec![4, 3]);
    }

    #[test]
    fn distribute_single_video_gets_all() {
        assert_eq!(distribute(30, 1), vec![30]);
    }

    #[test]
    fn distribute_more_videos_than_frames() {
        assert_eq!(distribute(2, 5), vec![1, 1, 0, 0, 0]);
    }

    #[test]
    fn distribute_zero_videos_is_empty() {
        assert_eq!(distribute(30, 0), Vec::<usize>::new());
    }

    #[test]
    fn distribute_sums_to_total() {
        for (total, n) in [(30, 7), (100, 13), (5, 5), (1, 4)] {
            assert_eq!(distribute(total, n).iter().sum::<usize>(), total);
            assert_eq!(distribute(total, n).len(), n);
        }
    }
}

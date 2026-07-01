//! Host/system diagnostics — the load-bearing disk-space gate + cute UI banner
//! status, a host-environment snapshot, and a persistent "black box" log for
//! post-mortems.
//!
//! Distinct from `media::diagnostics`, which inspects the bundled
//! ffmpeg/ffprobe *binaries*. This module is about the machine Molly runs on:
//! how much disk is free (Sallie chronically runs low, which is the leading
//! suspect for the truncated-Squish corruption), what the host looks like, and
//! a rolling log so that when something goes wrong later there is evidence to
//! read instead of a shrug.
//!
//! Disk numbers come from `fs2` (per-path `available_space`/`total_space` —
//! tiny and stable, which matters because they gate real work). The richer env
//! fields (RAM, OS version) come from `sysinfo` and are best-effort.

use std::fs::OpenOptions;
use std::io::Write as _;
use std::path::{Path, PathBuf};

use serde::Serialize;

/// SI-GB thresholds, matching the app's existing 1 GB conventions (Slack's
/// per-file limit, Squish's `ONE_GB`). RED is the hard floor (work is gated);
/// YELLOW is the cute "tidy up soon" warning.
pub const RED_FLOOR_BYTES: u64 = 1_000_000_000; // < 1 GB → gated
pub const YELLOW_BYTES: u64 = 3_000_000_000; //    < 3 GB → warning

/// Multiplier for the operation-aware preflight: Squish's `+faststart` pass and
/// split-publish's "compose whole zip → write parts" both transiently need a
/// second copy on disk, so an operation of size N needs ~2N free to be safe.
pub const OP_HEADROOM_MULTIPLIER: f64 = 2.0;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum DiskTier {
    Red,
    Yellow,
    Green,
}

/// Pure tier classification — unit-tested at the boundaries.
pub fn tier_for(available: u64) -> DiskTier {
    if available < RED_FLOOR_BYTES {
        DiskTier::Red
    } else if available < YELLOW_BYTES {
        DiskTier::Yellow
    } else {
        DiskTier::Green
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DiskStatus {
    pub path: String,
    pub available_bytes: u64,
    pub total_bytes: u64,
    pub tier: DiskTier,
}

/// (available, total) bytes on the volume holding `path`. Best-effort; `None`
/// on error so callers degrade rather than falsely gate.
pub fn disk_space(path: &Path) -> Option<(u64, u64)> {
    let available = fs2::available_space(path).ok()?;
    let total = fs2::total_space(path).ok()?;
    Some((available, total))
}

pub fn disk_status_for(path: &Path) -> Option<DiskStatus> {
    let (available_bytes, total_bytes) = disk_space(path)?;
    Some(DiskStatus {
        path: path.display().to_string(),
        available_bytes,
        total_bytes,
        tier: tier_for(available_bytes),
    })
}

/// Disk status for the volume that holds `~/Downloads` — where both the bundle
/// output and Squish output live. Walks up to the nearest existing ancestor so
/// it works even before `~/Downloads/Molly` has been created.
pub fn downloads_disk_status() -> Option<DiskStatus> {
    let dir = crate::fsutil::downloads_subdir("");
    disk_status_for(&existing_ancestor(&dir))
}

fn existing_ancestor(path: &Path) -> PathBuf {
    let mut p = path;
    loop {
        if p.exists() {
            return p.to_path_buf();
        }
        match p.parent() {
            Some(parent) if parent != p => p = parent,
            _ => return PathBuf::from(std::path::MAIN_SEPARATOR_STR),
        }
    }
}

/// The operation-aware technical gate. An operation whose output is `op_bytes`
/// transiently needs `op_bytes * OP_HEADROOM_MULTIPLIER` (a second copy), and
/// never less than the 1 GB RED floor. Returns the measured status on success,
/// or a Sallie-friendly message on failure.
pub fn require_space_for(op_bytes: u64) -> Result<DiskStatus, String> {
    let status = downloads_disk_status()
        .ok_or_else(|| "Molly couldn't check how much disk space is free.".to_string())?;
    let need = (((op_bytes as f64) * OP_HEADROOM_MULTIPLIER) as u64).max(RED_FLOOR_BYTES);
    if status.available_bytes < need {
        return Err(format!(
            "Not enough disk space — Molly needs about {} free to do this safely, \
             but only {} is available. Please free up some space and try again. 💗",
            human_gb(need),
            human_gb(status.available_bytes),
        ));
    }
    Ok(status)
}

/// Friendly "1.2 GB" rendering (SI). Used in gate messages + diagnostics.
pub fn human_gb(bytes: u64) -> String {
    format!("{:.1} GB", bytes as f64 / 1e9)
}

// ---------------------------------------------------------------------------
// Host environment snapshot
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EnvSnapshot {
    pub app_version: String,
    pub os: String,
    pub os_version: String,
    pub kernel: String,
    pub arch: String,
    pub cpu_count: usize,
    pub mem_total_bytes: u64,
    pub mem_available_bytes: u64,
    pub disk_available_bytes: u64,
    pub disk_total_bytes: u64,
}

/// Collect a best-effort snapshot of the host. Memory + OS strings via
/// `sysinfo`; disk via `fs2`; cpu count via std. Every field degrades to a
/// zero/empty default rather than failing.
pub fn collect_env(app_version: &str) -> EnvSnapshot {
    use sysinfo::System;
    let mut sys = System::new();
    sys.refresh_memory();
    let cpu_count = std::thread::available_parallelism()
        .map(|n| n.get())
        .unwrap_or(0);
    let (disk_available_bytes, disk_total_bytes) = downloads_disk_status()
        .map(|d| (d.available_bytes, d.total_bytes))
        .unwrap_or((0, 0));
    EnvSnapshot {
        app_version: app_version.to_string(),
        os: System::name().unwrap_or_else(|| std::env::consts::OS.to_string()),
        os_version: System::os_version().unwrap_or_default(),
        kernel: System::kernel_version().unwrap_or_default(),
        arch: std::env::consts::ARCH.to_string(),
        cpu_count,
        mem_total_bytes: sys.total_memory(),
        mem_available_bytes: sys.available_memory(),
        disk_available_bytes,
        disk_total_bytes,
    }
}

/// Render the env snapshot as the `[ENVIRONMENT]` block for a bundle's
/// `Molly.log`. Plain KEY: VALUE lines that SideMolly's `parse_molly_log`
/// safely ignores (it only matches known keys).
pub fn render_environment_block(env: &EnvSnapshot) -> String {
    let mut s = String::new();
    s.push_str("[ENVIRONMENT]\n");
    s.push_str(&format!("  Molly version:      {}\n", env.app_version));
    s.push_str(&format!(
        "  OS:                 {} {} (kernel {}) {}\n",
        env.os, env.os_version, env.kernel, env.arch
    ));
    s.push_str(&format!("  CPU cores:          {}\n", env.cpu_count));
    s.push_str(&format!(
        "  Memory:             {} free of {}\n",
        human_gb(env.mem_available_bytes),
        human_gb(env.mem_total_bytes)
    ));
    s.push_str(&format!(
        "  Disk (~/Downloads): {} free of {}\n",
        human_gb(env.disk_available_bytes),
        human_gb(env.disk_total_bytes)
    ));
    s
}

// ---------------------------------------------------------------------------
// Per-bundle diagnostics (travels with the bundle)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct VideoIntegrity {
    pub name: String,
    pub ok: bool,
    pub duration_sec: f64,
    pub codec: String,
    pub size_bytes: u64,
    /// Empty when ok; otherwise the reason it failed the playability probe.
    pub note: String,
}

/// The structured diagnostics payload written into each bundle (as
/// `diagnostics.json`) and mirrored into `Molly.log` — so when a bundle
/// misbehaves later there is captured evidence to read.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BundleDiagnostics {
    pub env: EnvSnapshot,
    pub videos: Vec<VideoIntegrity>,
}

/// Render the `[MEDIA INTEGRITY]` block for a bundle's `Molly.log` — one line
/// per video with its ffprobe verdict. Distinct from Molly.log's existing hash
/// `[INTEGRITY]` block, which proves bytes (not playability). SideMolly's
/// `parse_molly_log` safely ignores these lines.
pub fn render_integrity_block(videos: &[VideoIntegrity]) -> String {
    let mut s = String::new();
    s.push_str("[MEDIA INTEGRITY]\n");
    if videos.is_empty() {
        s.push_str("  (no videos in this bundle)\n");
        return s;
    }
    for v in videos {
        if v.ok {
            s.push_str(&format!(
                "  OK    {}  ({:.1}s, {}, {:.0} MB)\n",
                v.name,
                v.duration_sec,
                v.codec,
                v.size_bytes as f64 / 1e6
            ));
        } else {
            s.push_str(&format!("  FAIL  {}  — {}\n", v.name, v.note));
        }
    }
    s
}

// ---------------------------------------------------------------------------
// Black-box log (persistent, local) + panic hook
// ---------------------------------------------------------------------------

/// Append a timestamped line to the rolling black-box log under the app data
/// dir. Never panics; every failure is swallowed (a diagnostics writer must
/// never break the thing it's observing). Light rotation at ~2 MB.
pub fn blackbox_log(app_data_dir: &Path, line: &str) {
    let path = app_data_dir.join("diagnostics.log");
    let stamp = chrono::Local::now().format("%Y-%m-%d %H:%M:%S%.3f");
    let _ = (|| -> std::io::Result<()> {
        std::fs::create_dir_all(app_data_dir)?;
        if let Ok(meta) = std::fs::metadata(&path) {
            if meta.len() > 2_000_000 {
                let _ = std::fs::rename(&path, app_data_dir.join("diagnostics.log.1"));
            }
        }
        let mut f = OpenOptions::new().create(true).append(true).open(&path)?;
        writeln!(f, "{stamp}  {line}")
    })();
}

/// Install a panic hook that appends the panic (location + message +
/// backtrace) to the black-box log, then chains to the previous hook. Call
/// once at startup. This is the "stack" capture — a crash leaves a trace.
pub fn install_panic_hook(app_data_dir: PathBuf) {
    let default = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        let bt = std::backtrace::Backtrace::force_capture();
        let loc = info
            .location()
            .map(|l| format!("{}:{}", l.file(), l.line()))
            .unwrap_or_else(|| "<unknown>".into());
        let msg = info
            .payload()
            .downcast_ref::<&str>()
            .map(|s| s.to_string())
            .or_else(|| info.payload().downcast_ref::<String>().cloned())
            .unwrap_or_else(|| "<non-string panic payload>".into());
        blackbox_log(&app_data_dir, &format!("PANIC at {loc}: {msg}\n{bt}"));
        default(info);
    }));
}

// ---------------------------------------------------------------------------
// Tauri command
// ---------------------------------------------------------------------------

/// Frontend disk-space check — powers the cute banner + the "Recheck" button.
/// Returns `None` only if the volume can't be measured at all.
#[tauri::command]
pub fn disk_status<R: tauri::Runtime>(_handle: tauri::AppHandle<R>) -> Option<DiskStatus> {
    downloads_disk_status()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tier_boundaries() {
        assert_eq!(tier_for(0), DiskTier::Red);
        assert_eq!(tier_for(RED_FLOOR_BYTES - 1), DiskTier::Red);
        assert_eq!(tier_for(RED_FLOOR_BYTES), DiskTier::Yellow); // exactly 1 GB is not gated
        assert_eq!(tier_for(YELLOW_BYTES - 1), DiskTier::Yellow);
        assert_eq!(tier_for(YELLOW_BYTES), DiskTier::Green); // exactly 3 GB is fine
        assert_eq!(tier_for(50_000_000_000), DiskTier::Green);
    }

    #[test]
    fn human_gb_is_si() {
        assert_eq!(human_gb(1_000_000_000), "1.0 GB");
        assert_eq!(human_gb(2_500_000_000), "2.5 GB");
    }

    #[test]
    fn env_block_renders_known_keys() {
        let env = EnvSnapshot {
            app_version: "1.35.0".into(),
            os: "macOS".into(),
            os_version: "26.0".into(),
            kernel: "25.0.0".into(),
            arch: "aarch64".into(),
            cpu_count: 10,
            mem_total_bytes: 16_000_000_000,
            mem_available_bytes: 4_000_000_000,
            disk_available_bytes: 2_000_000_000,
            disk_total_bytes: 500_000_000_000,
        };
        let block = render_environment_block(&env);
        assert!(block.starts_with("[ENVIRONMENT]"));
        assert!(block.contains("Molly version:      1.35.0"));
        assert!(block.contains("CPU cores:          10"));
        assert!(block.contains("2.0 GB free of 500.0 GB"));
    }
}

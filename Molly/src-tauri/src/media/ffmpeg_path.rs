//! Resolve the ffmpeg / ffprobe binaries. Order:
//!   1. Settings override directory (media_settings.json) — power users / SideMolly.
//!   2. Bundled binary under <resource_dir>/resources/ffmpeg/ (the default for Sallie).
//!   3. Conventional PATH locations (Homebrew on the dev Mac).
//!   4. Bare name (let the OS resolve via PATH).
//!
//! Resolved fresh each call (a few `is_file` stats) so a Settings change takes
//! effect without a restart. The pure resolver `resolve_in` takes plain inputs
//! so it lifts cleanly into the shared crate.

use std::path::{Path, PathBuf};
use tauri::{AppHandle, Manager, Runtime};
use tokio::sync::OnceCell;

use crate::media::settings;

fn exe_name(stem: &str) -> String {
    if cfg!(target_os = "windows") {
        format!("{stem}.exe")
    } else {
        stem.to_string()
    }
}

/// PATH candidates where a system ffmpeg typically lives (dev Mac / Linux).
fn path_candidates(name: &str) -> Vec<PathBuf> {
    ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        .iter()
        .map(|d| Path::new(d).join(name))
        .collect()
}

/// Pure resolver: given an optional override dir, the bundled dir, and the
/// binary stem, return the first existing path, else the bare name.
fn resolve_in(override_dir: Option<&Path>, bundled_dir: Option<&Path>, stem: &str) -> PathBuf {
    let name = exe_name(stem);
    if let Some(dir) = override_dir {
        let p = dir.join(&name);
        if p.is_file() {
            return p;
        }
    }
    if let Some(dir) = bundled_dir {
        let p = dir.join(&name);
        if p.is_file() {
            return p;
        }
    }
    for c in path_candidates(&name) {
        if c.is_file() {
            return c;
        }
    }
    PathBuf::from(name)
}

fn bundled_dir<R: Runtime>(handle: &AppHandle<R>) -> Option<PathBuf> {
    // Tauri 2 nests bundle.resources under <resource_dir>/resources/<path>.
    handle
        .path()
        .resource_dir()
        .ok()
        .map(|r| r.join("resources").join("ffmpeg"))
}

fn override_dir<R: Runtime>(handle: &AppHandle<R>) -> Option<PathBuf> {
    let app_data = handle.path().app_data_dir().ok()?;
    settings::load(&app_data).ffmpeg_dir.map(PathBuf::from)
}

pub fn ffmpeg_bin<R: Runtime>(handle: &AppHandle<R>) -> PathBuf {
    resolve_in(
        override_dir(handle).as_deref(),
        bundled_dir(handle).as_deref(),
        "ffmpeg",
    )
}

pub fn ffprobe_bin<R: Runtime>(handle: &AppHandle<R>) -> PathBuf {
    resolve_in(
        override_dir(handle).as_deref(),
        bundled_dir(handle).as_deref(),
        "ffprobe",
    )
}

/// Whether the resolved ffmpeg has the `zscale` (libzimg) filter — required by
/// the HDR→SDR tonemap chain. The bundled static builds always do (CI
/// guardrail); a system/override ffmpeg might not (e.g. some Homebrew builds),
/// in which case we skip tone-mapping rather than hard-fail. Probed once.
pub async fn supports_zscale<R: Runtime>(handle: &AppHandle<R>) -> bool {
    static ZSCALE: OnceCell<bool> = OnceCell::const_new();
    *ZSCALE
        .get_or_init(|| async {
            let bin = ffmpeg_bin(handle);
            match tokio::process::Command::new(&bin)
                .args(["-hide_banner", "-filters"])
                .output()
                .await
            {
                Ok(o) => String::from_utf8_lossy(&o.stdout)
                    .lines()
                    .any(|l| l.split_whitespace().nth(1) == Some("zscale")),
                Err(_) => false,
            }
        })
        .await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn exe_name_platform() {
        if cfg!(target_os = "windows") {
            assert_eq!(exe_name("ffmpeg"), "ffmpeg.exe");
        } else {
            assert_eq!(exe_name("ffmpeg"), "ffmpeg");
        }
    }

    #[test]
    fn resolver_falls_back_to_bare_name() {
        let got = resolve_in(None, None, "definitely-not-a-real-binary-xyz");
        assert_eq!(got, PathBuf::from(exe_name("definitely-not-a-real-binary-xyz")));
    }

    #[test]
    fn resolver_prefers_override_then_bundled() {
        let tmp = std::env::temp_dir().join(format!("molly-ffpath-{}", std::process::id()));
        let over = tmp.join("over");
        let bund = tmp.join("bund");
        std::fs::create_dir_all(&over).unwrap();
        std::fs::create_dir_all(&bund).unwrap();
        let name = exe_name("ffmpeg");
        std::fs::write(over.join(&name), b"x").unwrap();
        std::fs::write(bund.join(&name), b"x").unwrap();
        // override wins
        assert_eq!(resolve_in(Some(&over), Some(&bund), "ffmpeg"), over.join(&name));
        // bundled wins when no override file
        assert_eq!(resolve_in(None, Some(&bund), "ffmpeg"), bund.join(&name));
        std::fs::remove_dir_all(&tmp).ok();
    }
}

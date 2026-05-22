// Auto-managed ATW bot install.
//
// Molly ships `repost.js` + a stripped `package.json` (no Playwright
// Chromium postinstall) as bundled resources. On first use, we copy
// them from the .app's resource_dir into app_data/atw-bot/ and run
// `npm install` there. On subsequent uses, we check the vendored
// VERSION marker against the installed copy and refresh if Molly
// upgraded the bot.
//
// We deliberately don't touch the .app bundle at runtime — bundled
// resources are conceptually read-only (they get clobbered on Molly
// updates anyway). The app-data copy is where node_modules lives.

use std::fs;
use std::path::{Path, PathBuf};
use std::time::Duration;

use serde::Serialize;
use tauri::{AppHandle, Manager, Runtime};
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command;

use crate::atw_settings;
use crate::crypto::CryptoError;

const BOT_DIRNAME: &str = "atw-bot";

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SetupState {
    pub bot_dir: String,
    pub files_copied: bool,
    pub installed_version: Option<String>,
    pub bundled_version: Option<String>,
    pub needs_npm_install: bool,
    pub node_modules_present: bool,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct InstallResult {
    pub status: String, // "success" | "failed"
    pub summary: String,
    pub log_excerpt: String,
    pub elapsed_seconds: u64,
}

/// Resolve the effective bot directory for this install.
///
/// - If `atw_settings.bot_dir` is set: respect the override (power-user mode).
/// - Otherwise: `app_data/atw-bot/` (auto-managed).
pub fn effective_bot_dir<R: Runtime>(handle: &AppHandle<R>) -> Result<PathBuf, CryptoError> {
    let app_data = handle
        .path()
        .app_data_dir()
        .map_err(|e| CryptoError::Internal(format!("app_data_dir: {e}")))?;
    let settings = atw_settings::load(&app_data);
    if let Some(override_path) = settings.bot_dir {
        return Ok(PathBuf::from(override_path));
    }
    Ok(app_data.join(BOT_DIRNAME))
}

fn read_marker_version(path: &Path) -> Option<String> {
    let mut p = path.to_path_buf();
    p.push("VERSION");
    fs::read_to_string(&p).ok().map(|s| s.trim().to_string())
}

fn resource_dir<R: Runtime>(handle: &AppHandle<R>) -> Result<PathBuf, CryptoError> {
    handle
        .path()
        .resource_dir()
        .map_err(|e| CryptoError::Internal(format!("resource_dir: {e}")))
}

fn bundled_bot_source<R: Runtime>(handle: &AppHandle<R>) -> Result<PathBuf, CryptoError> {
    // Tauri 2 nests bundled resources under <resource_dir>/resources/<relative_path>
    // for files declared in `bundle.resources` of tauri.conf.json.
    let res = resource_dir(handle)?;
    Ok(res.join("resources").join(BOT_DIRNAME))
}

/// Probe both the bundled (read-only, in-bundle) and the installed
/// (writable, in app_data) bot dirs and return a snapshot of state.
pub fn inspect<R: Runtime>(handle: &AppHandle<R>) -> Result<SetupState, CryptoError> {
    let bot_dir = effective_bot_dir(handle)?;
    let bundled = bundled_bot_source(handle).ok();

    let installed_version = read_marker_version(&bot_dir);
    let bundled_version = bundled.as_ref().and_then(|p| read_marker_version(p));
    let files_copied = bot_dir.join("repost.js").is_file()
        && bot_dir.join("package.json").is_file();
    let node_modules_present = bot_dir.join("node_modules").is_dir();
    let needs_npm_install = files_copied && !node_modules_present;
    Ok(SetupState {
        bot_dir: bot_dir.to_string_lossy().to_string(),
        files_copied,
        installed_version,
        bundled_version,
        needs_npm_install,
        node_modules_present,
    })
}

/// Copy vendored bot files from the .app bundle to the app-data dir.
/// Only writes when the bundled VERSION differs from the installed
/// VERSION (so we don't re-copy on every launch). Does NOT clobber
/// node_modules — that's the user's npm-install output.
pub fn ensure_bot_files_copied<R: Runtime>(handle: &AppHandle<R>) -> Result<(), CryptoError> {
    let dst = effective_bot_dir(handle)?;

    // If the user set a manual override, do NOT touch their directory.
    let app_data = handle
        .path()
        .app_data_dir()
        .map_err(|e| CryptoError::Internal(format!("app_data_dir: {e}")))?;
    let settings = atw_settings::load(&app_data);
    if settings.bot_dir.is_some() {
        return Ok(());
    }

    let src = bundled_bot_source(handle)?;
    if !src.exists() {
        return Err(CryptoError::Internal(format!(
            "bundled bot resources missing at {}",
            src.display()
        )));
    }

    let installed = read_marker_version(&dst);
    let bundled = read_marker_version(&src);
    if installed.is_some() && installed == bundled && dst.join("repost.js").is_file() {
        // Up to date — no copy needed.
        return Ok(());
    }

    fs::create_dir_all(&dst)?;
    for fname in &["repost.js", "package.json", "VERSION"] {
        let s = src.join(fname);
        let d = dst.join(fname);
        if s.is_file() {
            fs::copy(&s, &d)?;
        }
    }
    Ok(())
}

/// Run `npm install` in the bot dir. Streams stdout + stderr into a
/// 200-line ring buffer for the install-progress UI. Times out at 5 min
/// (Playwright + stealth + deps install in well under that on any
/// reasonable network).
pub async fn run_npm_install<R: Runtime>(
    handle: &AppHandle<R>,
) -> Result<InstallResult, CryptoError> {
    let started = std::time::Instant::now();
    let bot_dir = effective_bot_dir(handle)?;
    if !bot_dir.join("package.json").is_file() {
        return Err(CryptoError::Internal(format!(
            "package.json missing at {}; copy bot files first",
            bot_dir.display()
        )));
    }
    let npm = discover_npm()
        .ok_or_else(|| CryptoError::Internal("npm not found on PATH (install Node 18+ from nodejs.org)".into()))?;

    // Augment PATH with the dirs we found npm in + the standard fallbacks
    // so npm can find its own `node` shebang target. Finder-launched Tauri
    // apps inherit a stripped PATH; this is the surgical fix.
    let augmented_path = augment_path_for_node(&npm);

    let mut cmd = Command::new(&npm);
    cmd.arg("install")
        .arg("--silent")
        .arg("--no-audit")
        .arg("--no-fund")
        .current_dir(&bot_dir)
        .env("PATH", &augmented_path)
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped());

    let mut child = cmd
        .spawn()
        .map_err(|e| CryptoError::Internal(format!("spawn npm: {e}")))?;
    let stdout = child
        .stdout
        .take()
        .ok_or_else(|| CryptoError::Internal("npm stdout missing".into()))?;
    let stderr = child
        .stderr
        .take()
        .ok_or_else(|| CryptoError::Internal("npm stderr missing".into()))?;

    let log = std::sync::Arc::new(tokio::sync::Mutex::new(Vec::<String>::with_capacity(256)));
    let log_out = std::sync::Arc::clone(&log);
    let so = tokio::spawn(async move {
        let mut lines = BufReader::new(stdout).lines();
        while let Ok(Some(line)) = lines.next_line().await {
            let mut buf = log_out.lock().await;
            if buf.len() >= 200 {
                buf.remove(0);
            }
            buf.push(line);
        }
    });
    let log_err = std::sync::Arc::clone(&log);
    let se = tokio::spawn(async move {
        let mut lines = BufReader::new(stderr).lines();
        while let Ok(Some(line)) = lines.next_line().await {
            let mut buf = log_err.lock().await;
            if buf.len() >= 200 {
                buf.remove(0);
            }
            buf.push(format!("[stderr] {line}"));
        }
    });

    let timeout = Duration::from_secs(5 * 60);
    let status = tokio::time::timeout(timeout, child.wait()).await;
    let _ = so.await;
    let _ = se.await;
    let buf = log.lock().await;
    let log_excerpt = buf.join("\n");
    let elapsed_seconds = started.elapsed().as_secs();

    let (status_str, summary) = match status {
        Ok(Ok(es)) if es.success() => (
            "success",
            format!("npm install completed in {elapsed_seconds}s"),
        ),
        Ok(Ok(es)) => (
            "failed",
            format!("npm install exited {es} after {elapsed_seconds}s"),
        ),
        Ok(Err(e)) => (
            "failed",
            format!("npm install spawn error: {e}"),
        ),
        Err(_) => {
            let _ = child.kill().await;
            (
                "failed",
                format!("npm install timed out after {elapsed_seconds}s"),
            )
        }
    };

    Ok(InstallResult {
        status: status_str.to_string(),
        summary,
        log_excerpt,
        elapsed_seconds,
    })
}

/// Find `npm`. Tauri apps launched from Finder/Dock get a stripped PATH
/// that omits Homebrew (`/opt/homebrew/bin`, `/usr/local/bin`), nvm,
/// volta, etc. So we scan PATH first and then fall back to a handful of
/// standard install locations before giving up.
fn discover_npm() -> Option<PathBuf> {
    let exe = if cfg!(target_os = "windows") { "npm.cmd" } else { "npm" };
    if let Some(path_var) = std::env::var_os("PATH") {
        for dir in std::env::split_paths(&path_var) {
            let candidate = dir.join(exe);
            if candidate.is_file() {
                return Some(candidate);
            }
        }
    }
    for fallback in npm_fallback_dirs() {
        let candidate = fallback.join(exe);
        if candidate.is_file() {
            return Some(candidate);
        }
    }
    None
}

/// Build a PATH string that includes the parent's PATH, the dir we
/// found `npm` in (so `node` likely sits beside it), and all the
/// standard fallbacks. Used as the env for `npm install` subprocesses.
pub(crate) fn augment_path_for_node(npm_path: &Path) -> std::ffi::OsString {
    use std::ffi::OsString;
    let sep = if cfg!(target_os = "windows") { ";" } else { ":" };
    let mut parts: Vec<String> = Vec::new();
    if let Some(npm_dir) = npm_path.parent() {
        parts.push(npm_dir.to_string_lossy().to_string());
    }
    for dir in npm_fallback_dirs() {
        parts.push(dir.to_string_lossy().to_string());
    }
    if let Some(existing) = std::env::var_os("PATH") {
        parts.push(existing.to_string_lossy().to_string());
    }
    let mut seen = std::collections::HashSet::new();
    let mut deduped: Vec<String> = Vec::new();
    for p in parts {
        if !p.is_empty() && seen.insert(p.clone()) {
            deduped.push(p);
        }
    }
    OsString::from(deduped.join(sep))
}

fn npm_fallback_dirs() -> Vec<PathBuf> {
    let mut dirs: Vec<PathBuf> = Vec::new();
    if cfg!(target_os = "macos") {
        dirs.push(PathBuf::from("/opt/homebrew/bin"));
        dirs.push(PathBuf::from("/usr/local/bin"));
        dirs.push(PathBuf::from("/usr/local/opt/node/bin"));
    }
    if cfg!(target_os = "linux") {
        dirs.push(PathBuf::from("/usr/local/bin"));
        dirs.push(PathBuf::from("/usr/bin"));
    }
    if let Some(home) = std::env::var_os("HOME") {
        let home = PathBuf::from(home);
        if let Ok(entries) = std::fs::read_dir(home.join(".nvm/versions/node")) {
            for entry in entries.flatten() {
                dirs.push(entry.path().join("bin"));
            }
        }
        dirs.push(home.join(".volta/bin"));
        dirs.push(home.join(".fnm/aliases/default/bin"));
        dirs.push(home.join(".asdf/shims"));
    }
    dirs
}

// ----- Tauri commands --------------------------------------------------------

#[tauri::command]
pub fn inspect_atw_setup<R: Runtime>(handle: AppHandle<R>) -> Result<SetupState, CryptoError> {
    inspect(&handle)
}

#[tauri::command]
pub fn ensure_atw_bot_files<R: Runtime>(handle: AppHandle<R>) -> Result<SetupState, CryptoError> {
    ensure_bot_files_copied(&handle)?;
    inspect(&handle)
}

#[tauri::command]
pub async fn install_atw_bot_deps<R: Runtime>(
    handle: AppHandle<R>,
) -> Result<InstallResult, CryptoError> {
    // Make sure files are present before npm-install. Cheap if up to date.
    ensure_bot_files_copied(&handle)?;
    run_npm_install(&handle).await
}

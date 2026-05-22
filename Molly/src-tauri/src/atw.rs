// ATW Repost bot integration.
//
// v1 design: Molly orchestrates the EXISTING Node + Playwright bot at
// the user's `bot_dir` path (defaults shown in Settings → ATW). We
// spawn `node repost.js` with credentials + cadence params via env
// vars (decrypted from PR1's keystore at run time, never written to
// disk in plaintext beyond the subprocess env which lives in kernel
// memory only for the run's duration).
//
// We capture stdout + stderr, persist a tail of ~100 lines into
// `background_job_runs.log_excerpt`, and parse a few status markers
// from the existing log format to produce a human-readable summary
// ("Submitted 47 of 50 listings", "Login verification failed", etc.).
//
// This is deliberately a SHELL — no chromiumoxide, no browser
// automation in Rust. The Node bot already works against the live
// site with stealth evasions; reimplementing it in Rust would carry
// real regression risk.

use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::sync::Arc;
use std::time::{Duration, Instant};

use serde::Serialize;
use tauri::{AppHandle, Manager, Runtime, State};
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command;

use crate::atw_settings::{self, AtwSettings};
use crate::atw_setup;
use crate::crypto::keystore::KeystoreState;
use crate::crypto::CryptoError;

/// Standard install paths for Google Chrome. Returned on a best-effort
/// basis; None means we couldn't find it and the user must set
/// `browserExecutablePath` in Settings → ATW manually.
pub fn discover_chrome() -> Option<String> {
    let candidates: &[&str] = &[
        // macOS
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        "/Applications/Google Chrome Canary.app/Contents/MacOS/Google Chrome Canary",
        "/Applications/Chromium.app/Contents/MacOS/Chromium",
        // Linux
        "/usr/bin/google-chrome",
        "/usr/bin/google-chrome-stable",
        "/usr/bin/chromium",
        // Windows
        r"C:\Program Files\Google\Chrome\Application\chrome.exe",
        r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    ];
    for c in candidates {
        if std::path::Path::new(c).exists() {
            return Some((*c).to_string());
        }
    }
    None
}

/// Locate `node`. Scans PATH first, then falls back to a handful of
/// standard install locations (Homebrew, nvm, volta, fnm, asdf) — Tauri
/// apps launched from Finder/Dock get a stripped PATH that often omits
/// the directories where a developer's Node actually lives.
pub fn discover_node() -> Option<PathBuf> {
    let exe = if cfg!(target_os = "windows") { "node.exe" } else { "node" };
    if let Some(path_var) = std::env::var_os("PATH") {
        for dir in std::env::split_paths(&path_var) {
            let candidate = dir.join(exe);
            if candidate.is_file() {
                return Some(candidate);
            }
        }
    }
    for fallback in node_fallback_dirs() {
        let candidate = fallback.join(exe);
        if candidate.is_file() {
            return Some(candidate);
        }
    }
    None
}

/// Common Node install locations. Kept in sync with `atw_setup::npm_fallback_dirs`.
fn node_fallback_dirs() -> Vec<PathBuf> {
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

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AtwHealthCheck {
    pub node_found: bool,
    pub node_path: Option<String>,
    pub chrome_found: bool,
    pub chrome_path: Option<String>,
    pub bot_dir_set: bool,
    pub bot_dir_exists: bool,
    pub bot_dir_has_repost_js: bool,
    pub bot_dir_has_node_modules: bool,
}

/// `health_check_with_dir` accepts the effective bot dir so the caller
/// (`atw_health_check` Tauri command) can resolve it via `atw_setup::
/// effective_bot_dir` — which auto-resolves to `app_data/atw-bot/` for
/// the zero-config flow but respects a manual override in settings.
pub(crate) fn health_check_with_dir(settings: &AtwSettings, bot_dir: &Path) -> AtwHealthCheck {
    let node = discover_node();
    let chrome = settings
        .browser_executable_path
        .clone()
        .or_else(discover_chrome);
    let bot_dir_exists = bot_dir.is_dir();
    let bot_dir_has_repost_js = bot_dir.join("repost.js").is_file();
    let bot_dir_has_node_modules = bot_dir.join("node_modules").is_dir();

    AtwHealthCheck {
        node_found: node.is_some(),
        node_path: node.map(|p| p.to_string_lossy().to_string()),
        chrome_found: chrome.is_some(),
        chrome_path: chrome,
        bot_dir_set: true, // always set under the auto-managed model
        bot_dir_exists,
        bot_dir_has_repost_js,
        bot_dir_has_node_modules,
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RunOutcome {
    pub status: String,         // "success" | "failed"
    pub summary: String,
    pub log_excerpt: String,    // last ~100 lines
    pub elapsed_seconds: u64,
}

/// Run the ATW bot once. Spawns `node repost.js` with all the config
/// passed via env vars (overriding the user's .env so Molly's settings
/// win). Captures stdout + stderr line-by-line, keeps the last 200
/// lines in a ring buffer for the run history.
///
/// `extra_env` is wired in so callers can override RUN_INTERVAL_HOURS
/// to a very large value — we drive scheduling from Molly's runner,
/// not the bot's internal loop. The bot loops forever by default; we
/// want it to exit after ONE cycle. The bot doesn't have a built-in
/// "one shot" flag, so we work around this by setting RUN_INTERVAL
/// huge and killing the subprocess after the first cycle completes.
/// (Detect "Run #N ended" in stdout → terminate.)
pub async fn run_once<R: Runtime>(
    handle: &AppHandle<R>,
    state: &State<'_, Arc<KeystoreState>>,
) -> Result<RunOutcome, CryptoError> {
    let started = Instant::now();
    let app_data = handle
        .path()
        .app_data_dir()
        .map_err(|e| CryptoError::Internal(format!("app_data_dir: {e}")))?;
    let settings = atw_settings::load(&app_data);

    // Auto-managed bot dir: ensure vendored files are copied to app
    // data before the run (cheap if already done; refreshes after
    // Molly updates that bump VERSION).
    atw_setup::ensure_bot_files_copied(handle)?;
    let bot_path = atw_setup::effective_bot_dir(handle)?;
    if !bot_path.join("repost.js").is_file() {
        return Err(CryptoError::Internal(format!(
            "repost.js not found at {}",
            bot_path.display()
        )));
    }
    if !bot_path.join("node_modules").is_dir() {
        return Err(CryptoError::Internal(
            "Bot dependencies not installed yet — open Settings → 🌀 ATW Repost and click \"Install bot dependencies\".".into(),
        ));
    }

    let node_path = discover_node()
        .ok_or_else(|| CryptoError::Internal("Node not found on PATH (install Node 18+ from nodejs.org)".into()))?;

    // Decrypt the ATW password from the keystore. This is the only
    // place plaintext briefly exists in our memory; it goes straight
    // into the subprocess env and we don't hold a copy.
    let password = {
        let guard = state.0.lock().expect("keystore lock poisoned");
        let session = guard.as_ref().ok_or(CryptoError::Locked)?;
        if session.is_idle() {
            return Err(CryptoError::Locked);
        }
        atw_settings::decrypt_password(session, &settings)?
            .ok_or_else(|| CryptoError::Internal("ATW password not set".into()))?
    };

    // Chrome path: settings override OR discovery.
    let chrome = settings
        .browser_executable_path
        .clone()
        .or_else(discover_chrome);

    let augmented_path = crate::atw_setup::augment_path_for_node(&node_path);

    let mut cmd = Command::new(&node_path);
    cmd.arg("repost.js")
        .current_dir(&bot_path)
        .env("PATH", &augmented_path)
        .env("ATW_EMAIL", &settings.email)
        .env("ATW_PASSWORD", &password)
        .env("REPOST_DAYS", settings.repost_days.to_string())
        .env("UTC_OFFSET", settings.utc_offset.to_string())
        .env("SCHEDULE_START_HOUR", settings.schedule_start_hour.to_string())
        .env("SCHEDULE_END_HOUR", settings.schedule_end_hour.to_string())
        .env("DELAY_MS", settings.delay_ms.to_string())
        // Tell the bot to wait 24h between its internal loops — we
        // kill the subprocess after run #1 completes anyway.
        .env("RUN_INTERVAL_HOURS", "24")
        .env("HEADLESS", if settings.headless { "true" } else { "false" })
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    if let Some(path) = &chrome {
        cmd.env("BROWSER_EXECUTABLE_PATH", path);
    }

    let mut child = cmd
        .spawn()
        .map_err(|e| CryptoError::Internal(format!("spawn node: {e}")))?;

    let stdout = child
        .stdout
        .take()
        .ok_or_else(|| CryptoError::Internal("subprocess stdout missing".into()))?;
    let stderr = child
        .stderr
        .take()
        .ok_or_else(|| CryptoError::Internal("subprocess stderr missing".into()))?;

    // Tail buffer (capacity ~200 lines).
    let log = Arc::new(tokio::sync::Mutex::new(Vec::<String>::with_capacity(256)));

    // Spawn reader tasks for both streams.
    let log_out = Arc::clone(&log);
    let stdout_task = tokio::spawn(async move {
        let mut lines = BufReader::new(stdout).lines();
        let mut saw_run_end = false;
        while let Ok(Some(line)) = lines.next_line().await {
            {
                let mut buf = log_out.lock().await;
                if buf.len() >= 200 {
                    buf.remove(0);
                }
                buf.push(line.clone());
            }
            // Detect "Run #N ended" — the bot's own one-cycle marker.
            // After this, the bot enters its countdown sleep for the
            // next cycle; we kill the subprocess to exit cleanly.
            if line.contains("ended (") && line.contains("s elapsed)") {
                saw_run_end = true;
                break;
            }
        }
        saw_run_end
    });
    let log_err = Arc::clone(&log);
    let stderr_task = tokio::spawn(async move {
        let mut lines = BufReader::new(stderr).lines();
        while let Ok(Some(line)) = lines.next_line().await {
            let mut buf = log_err.lock().await;
            if buf.len() >= 200 {
                buf.remove(0);
            }
            buf.push(format!("[stderr] {line}"));
        }
    });

    // Wait for the run-end marker (with a hard timeout cap so a hung
    // bot doesn't keep node alive forever).
    let hard_timeout = Duration::from_secs(45 * 60); // 45 minutes
    let stdout_done = tokio::time::timeout(hard_timeout, stdout_task).await;
    // Terminate the subprocess (the bot would otherwise enter its
    // countdown sleep for the next cycle).
    let _ = child.kill().await;
    let _ = child.wait().await;
    let _ = stderr_task.await;

    let buf = log.lock().await;
    let log_excerpt = buf.join("\n");
    let elapsed_seconds = started.elapsed().as_secs();

    let saw_run_end = matches!(stdout_done, Ok(Ok(true)));
    let (status, summary) = summarize(&buf, saw_run_end, elapsed_seconds);

    Ok(RunOutcome {
        status: status.to_string(),
        summary,
        log_excerpt,
        elapsed_seconds,
    })
}

/// Parse the bot's stdout tail into a human-readable summary.
///
/// Looks for known markers from repost.js:
///   - "Login verification got HTTP ..." → failed (login refused)
///   - "Login failed — landed on ..." → failed (auth error)
///   - "Logged-in page content looks unexpected" → failed
///   - "Nothing to repost" → success (no-op run)
///   - "Run complete — submitted N of M slot(s)." → success
fn summarize(log_lines: &[String], saw_run_end: bool, elapsed_seconds: u64) -> (&'static str, String) {
    // Scan for failure markers FIRST (the bot prints both error lines
    // and the "Run #N ended" marker — we want the failure to win).
    for line in log_lines {
        if line.contains("Login verification got HTTP") {
            return ("failed", "Login verification failed — site is likely blocking the browser as a bot.".into());
        }
        if line.contains("Login failed") {
            return ("failed", "Login rejected — check credentials.".into());
        }
        if line.contains("looks unexpected") {
            return ("failed", "Logged-in page content unexpected (selectors may have drifted).".into());
        }
        if line.contains("Redirected to /login mid-run") {
            return ("failed", "Session expired mid-run.".into());
        }
        if line.starts_with("Config error") {
            return ("failed", format!("Config error: {}", line.trim_start_matches("Config error: ")));
        }
    }
    for line in log_lines.iter().rev() {
        if let Some(idx) = line.find("Run complete — submitted ") {
            let rest = &line[idx + "Run complete — submitted ".len()..];
            return ("success", format!("ATW repost complete ({rest}, {elapsed_seconds}s elapsed)"));
        }
        if line.contains("Nothing to repost") {
            return ("success", format!("ATW already up to date — no listings needed reposting ({elapsed_seconds}s elapsed)"));
        }
    }
    if saw_run_end {
        return ("success", format!("ATW run completed in {elapsed_seconds}s"));
    }
    ("failed", format!("ATW run did not complete cleanly within {elapsed_seconds}s (see log_excerpt for details)"))
}

// ----- Tauri commands --------------------------------------------------------

#[tauri::command]
pub fn atw_health_check<R: Runtime>(handle: AppHandle<R>) -> Result<AtwHealthCheck, CryptoError> {
    let app_data = handle
        .path()
        .app_data_dir()
        .map_err(|e| CryptoError::Internal(format!("app_data_dir: {e}")))?;
    let s = atw_settings::load(&app_data);
    // Probe the auto-managed bot dir (or the user's override if set).
    let bot_dir = atw_setup::effective_bot_dir(&handle)?;
    Ok(health_check_with_dir(&s, &bot_dir))
}

/// On-demand "Run now" from the React UI. Returns the same outcome the
/// scheduled runner would. Caller (the JS layer) is expected to also
/// write a row to `background_job_runs` so the run shows up in history.
#[tauri::command]
pub async fn atw_run_now<R: Runtime>(
    handle: AppHandle<R>,
    state: State<'_, Arc<KeystoreState>>,
) -> Result<RunOutcome, CryptoError> {
    run_once(&handle, &state).await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn summarize_login_failure_wins_over_run_end() {
        let log = vec![
            "Logging in (step 1: email)...".to_string(),
            "Login verification got HTTP 403".to_string(),
            "Run #1 ended (12.5s elapsed).".to_string(),
        ];
        let (status, summary) = summarize(&log, true, 12);
        assert_eq!(status, "failed");
        assert!(summary.contains("Login verification failed"));
    }

    #[test]
    fn summarize_run_complete_is_success() {
        let log = vec![
            "Logging in (step 1: email)...".to_string(),
            "Login OK".to_string(),
            "Run complete — submitted 47 of 47 slot(s).".to_string(),
            "Run #1 ended (305.0s elapsed).".to_string(),
        ];
        let (status, summary) = summarize(&log, true, 305);
        assert_eq!(status, "success");
        assert!(summary.contains("47 of 47"));
        assert!(summary.contains("305s"));
    }

    #[test]
    fn summarize_nothing_to_repost() {
        let log = vec![
            "Login OK".to_string(),
            "Nothing to repost — all listings already scheduled.".to_string(),
            "Run #1 ended (18.0s elapsed).".to_string(),
        ];
        let (status, summary) = summarize(&log, true, 18);
        assert_eq!(status, "success");
        assert!(summary.contains("already up to date"));
    }

    #[test]
    fn summarize_config_error_fails() {
        let log = vec![
            "Config error: REPOST_DAYS must be a positive integer (got -1)".to_string(),
        ];
        let (status, summary) = summarize(&log, false, 1);
        assert_eq!(status, "failed");
        assert!(summary.contains("REPOST_DAYS"));
    }

    #[test]
    fn summarize_hung_subprocess_fails() {
        let log = vec!["Logging in (step 1: email)...".to_string()];
        let (status, summary) = summarize(&log, false, 2700);
        assert_eq!(status, "failed");
        assert!(summary.contains("did not complete cleanly"));
    }

    #[test]
    fn discover_node_returns_node_if_installed() {
        // Just verify the function doesn't panic. On dev machines node
        // is usually present; in CI it might not be.
        let _ = discover_node();
    }

    #[test]
    fn discover_chrome_returns_known_or_none() {
        // Same — best-effort, varies by environment.
        let _ = discover_chrome();
    }

    #[test]
    fn health_check_with_empty_dir_reports_unset() {
        // The auto-managed model passes the bot dir in directly (the
        // Tauri command resolves it via atw_setup); test that with a
        // path we know doesn't exist.
        let s = AtwSettings::defaults();
        let tmp = tempfile::tempdir().unwrap();
        let nonexistent = tmp.path().join("never-created");
        let h = health_check_with_dir(&s, &nonexistent);
        assert!(!h.bot_dir_exists);
        assert!(!h.bot_dir_has_repost_js);
        assert!(!h.bot_dir_has_node_modules);
    }
}

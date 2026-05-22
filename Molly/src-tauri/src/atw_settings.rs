// ATW settings — config for the `atw_repost` background job.
//
// Stored as a single JSON blob in app_data_dir/atw-settings.json
// (parallel to backup-settings.json, bundler-settings.json). The
// password field is the AES-GCM-wrapped blob from PR1's keystore;
// we never write or read plaintext through this layer.
//
// The encryption / decryption is delegated to `crypto::wrap` against
// the in-session DEK; `set_atw_settings` requires the keystore to be
// unlocked (it encrypts on save), and `decrypt_password()` is called
// at run time inside `atw::run_once` (which also requires unlock).

use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Arc;

use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Manager, Runtime, State};

use crate::crypto::keystore::{KeystoreState, SessionState};
use crate::crypto::wrap;
use crate::crypto::CryptoError;

const SETTINGS_FILENAME: &str = "atw-settings.json";

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct AtwSettings {
    /// User's ATW login email. Plaintext (not a secret).
    pub email: String,
    /// AES-GCM-encrypted password blob (base64, versioned). None when
    /// the user hasn't set a password yet.
    pub password_ciphertext: Option<String>,
    pub password_dek_version: Option<i32>,
    /// Absolute path to the user's `atw-repost-bot` directory (the
    /// folder containing `repost.js` + `package.json` + `node_modules`).
    /// v1 ships as a "point at your existing install" model; v2 will
    /// vendor the bot inside Molly's bundle.
    pub bot_dir: Option<String>,
    /// Override Chrome path; None = use the standard install location.
    pub browser_executable_path: Option<String>,
    /// Run frequency in seconds. Default 4h = 14400.
    pub cadence_seconds: u32,
    /// How many days to spread reposts across (matches REPOST_DAYS).
    pub repost_days: u32,
    /// Earliest local hour to schedule a repost at (0-23).
    pub schedule_start_hour: u32,
    /// Latest local hour, exclusive (1-24).
    pub schedule_end_hour: u32,
    /// Local UTC offset (matches UTC_OFFSET).
    pub utc_offset: i32,
    /// Milliseconds between form submissions (rate limiter).
    pub delay_ms: u32,
    /// Run headless (false to see the browser pop up for debugging).
    pub headless: bool,
}

impl AtwSettings {
    /// Sensible defaults matching the existing repost.js .env.example.
    pub fn defaults() -> Self {
        Self {
            email: String::new(),
            password_ciphertext: None,
            password_dek_version: None,
            bot_dir: None,
            browser_executable_path: None,
            cadence_seconds: 4 * 60 * 60, // 4h
            repost_days: 3,
            schedule_start_hour: 8,
            schedule_end_hour: 22,
            utc_offset: 4, // EDT — Sallie's timezone per the existing config
            delay_ms: 4000,
            headless: true,
        }
    }

    pub fn has_password(&self) -> bool {
        self.password_ciphertext.is_some()
    }
}

fn settings_path(app_data_dir: &Path) -> PathBuf {
    app_data_dir.join(SETTINGS_FILENAME)
}

pub(crate) fn load(app_data_dir: &Path) -> AtwSettings {
    let p = settings_path(app_data_dir);
    fs::read(&p)
        .ok()
        .and_then(|bytes| serde_json::from_slice::<AtwSettings>(&bytes).ok())
        .unwrap_or_else(AtwSettings::defaults)
}

pub(crate) fn save(app_data_dir: &Path, s: &AtwSettings) -> Result<(), CryptoError> {
    fs::create_dir_all(app_data_dir)?;
    let p = settings_path(app_data_dir);
    let bytes = serde_json::to_vec_pretty(s)
        .map_err(|e| CryptoError::Internal(format!("serialize atw settings: {e}")))?;
    let tmp = p.with_extension("json.tmp");
    fs::write(&tmp, &bytes)?;
    fs::rename(&tmp, &p)?;
    Ok(())
}

fn app_data_dir<R: Runtime>(handle: &AppHandle<R>) -> Result<PathBuf, CryptoError> {
    handle
        .path()
        .app_data_dir()
        .map_err(|e| CryptoError::Internal(format!("app_data_dir: {e}")))
}

/// Decrypt the stored ATW password into plaintext. Requires the
/// keystore to be unlocked. Returns `None` if no password is stored.
/// Called from `atw::run_once` to populate the subprocess env var.
pub(crate) fn decrypt_password(
    session: &SessionState,
    s: &AtwSettings,
) -> Result<Option<String>, CryptoError> {
    let Some(ct) = &s.password_ciphertext else {
        return Ok(None);
    };
    let version = s.password_dek_version.unwrap_or(session.version);
    if version != session.version {
        return Err(CryptoError::DecryptionFailed);
    }
    Ok(Some(wrap::decrypt_field(&session.dek, ct)?))
}

// ----- Tauri commands --------------------------------------------------------

/// Public DTO returned to the frontend — same shape as `AtwSettings`
/// EXCEPT password_ciphertext is suppressed and replaced with a bool
/// `hasPassword`. The plaintext never leaves Rust via this command.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AtwSettingsDto {
    pub email: String,
    pub has_password: bool,
    pub password_dek_version: Option<i32>,
    pub bot_dir: Option<String>,
    pub browser_executable_path: Option<String>,
    pub cadence_seconds: u32,
    pub repost_days: u32,
    pub schedule_start_hour: u32,
    pub schedule_end_hour: u32,
    pub utc_offset: i32,
    pub delay_ms: u32,
    pub headless: bool,
}

impl From<&AtwSettings> for AtwSettingsDto {
    fn from(s: &AtwSettings) -> Self {
        Self {
            email: s.email.clone(),
            has_password: s.has_password(),
            password_dek_version: s.password_dek_version,
            bot_dir: s.bot_dir.clone(),
            browser_executable_path: s.browser_executable_path.clone(),
            cadence_seconds: s.cadence_seconds,
            repost_days: s.repost_days,
            schedule_start_hour: s.schedule_start_hour,
            schedule_end_hour: s.schedule_end_hour,
            utc_offset: s.utc_offset,
            delay_ms: s.delay_ms,
            headless: s.headless,
        }
    }
}

#[tauri::command]
pub fn get_atw_settings<R: Runtime>(
    handle: AppHandle<R>,
) -> Result<AtwSettingsDto, CryptoError> {
    let dir = app_data_dir(&handle)?;
    Ok(AtwSettingsDto::from(&load(&dir)))
}

/// Payload sent from the React form. `password` is the plaintext (or
/// None to leave existing ciphertext alone, or Some("") to clear).
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SetAtwSettingsPayload {
    pub email: String,
    pub password: Option<String>,
    pub bot_dir: Option<String>,
    pub browser_executable_path: Option<String>,
    pub cadence_seconds: u32,
    pub repost_days: u32,
    pub schedule_start_hour: u32,
    pub schedule_end_hour: u32,
    pub utc_offset: i32,
    pub delay_ms: u32,
    pub headless: bool,
}

#[tauri::command]
pub fn set_atw_settings<R: Runtime>(
    handle: AppHandle<R>,
    state: State<Arc<KeystoreState>>,
    payload: SetAtwSettingsPayload,
) -> Result<AtwSettingsDto, CryptoError> {
    let dir = app_data_dir(&handle)?;
    let mut current = load(&dir);

    current.email = payload.email;
    current.bot_dir = payload.bot_dir;
    current.browser_executable_path = payload.browser_executable_path;
    current.cadence_seconds = payload.cadence_seconds.max(60);
    current.repost_days = payload.repost_days.clamp(1, 14);
    current.schedule_start_hour = payload.schedule_start_hour.min(23);
    current.schedule_end_hour = payload.schedule_end_hour.clamp(1, 24);
    current.utc_offset = payload.utc_offset;
    current.delay_ms = payload.delay_ms.clamp(1000, 60_000);
    current.headless = payload.headless;

    if let Some(pw) = payload.password {
        if pw.is_empty() {
            // Empty string explicitly clears.
            current.password_ciphertext = None;
            current.password_dek_version = None;
        } else {
            let guard = state.0.lock().expect("keystore lock poisoned");
            let session = guard.as_ref().ok_or(CryptoError::Locked)?;
            if session.is_idle() {
                return Err(CryptoError::Locked);
            }
            current.password_ciphertext = Some(wrap::encrypt_field(&session.dek, &pw)?);
            current.password_dek_version = Some(session.version);
        }
    }
    // If password is None, leave current ciphertext alone.

    save(&dir, &current)?;
    Ok(AtwSettingsDto::from(&current))
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn defaults_match_env_example() {
        let d = AtwSettings::defaults();
        assert_eq!(d.cadence_seconds, 14400);
        assert_eq!(d.repost_days, 3);
        assert_eq!(d.schedule_start_hour, 8);
        assert_eq!(d.schedule_end_hour, 22);
        assert_eq!(d.delay_ms, 4000);
        assert!(d.headless);
        assert!(!d.has_password());
    }

    #[test]
    fn round_trip_via_disk() {
        let tmp = TempDir::new().unwrap();
        let mut s = AtwSettings::defaults();
        s.email = "sallie@example.com".into();
        s.bot_dir = Some("/path/to/bot".into());
        save(tmp.path(), &s).unwrap();
        let loaded = load(tmp.path());
        assert_eq!(loaded.email, "sallie@example.com");
        assert_eq!(loaded.bot_dir.as_deref(), Some("/path/to/bot"));
    }

    #[test]
    fn missing_file_yields_defaults() {
        let tmp = TempDir::new().unwrap();
        let loaded = load(tmp.path());
        assert_eq!(loaded.cadence_seconds, 14400);
    }
}

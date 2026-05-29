// Phase 9: Content Bundler — Tauri commands + settings + the publish flow.
//
// File-handling layered so unit tests can exercise the SQL + validation +
// composition without an `AppHandle`:
//
//   - `pure_*` / pure validators / `next_uid_in_conn` take a `&Connection`
//     and any other plain args; tested under `mod tests`.
//   - The `#[tauri::command]` wrappers open the DB, resolve paths via
//     `AppHandle`, and otherwise delegate to those helpers.
//
// The composition itself lives in `bundle_zip::compose_bundle` — the
// publish flow here reads the bundle row + line-items, builds a
// `BundleSnapshot`, calls compose_bundle, then stamps the row inside
// a transaction. Clip auto-upsert (Content only) is part of the same
// transaction so no orphan clip can appear if compose_bundle fails.

use std::fs;
use std::path::{Path, PathBuf};
use std::time::Duration;

use chrono::{DateTime, Datelike, Local, NaiveDate, Utc};
use rusqlite::{params, types::Value as SqlValue, Connection};
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Manager, Runtime};

use crate::bundle_zip::{
    self, BundleArtifact, BundleError as ZipError, BundleSnapshot, BundleType, FanDay,
    FileEntry, FileKind,
};
use crate::fsutil;

#[allow(dead_code)]
const APP_NAME: &str = "Molly";
const BUNDLE_FOLDER: &str = "Molly bundles";
const SETTINGS_FILENAME: &str = "bundler-settings.json";
const PURGE_DEBOUNCE_HOURS: i64 = 23;

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

#[derive(Debug, thiserror::Error)]
pub enum BundleError {
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    #[error("db: {0}")]
    Db(String),
    #[error("settings: {0}")]
    Settings(String),
    #[error("not found: {0}")]
    NotFound(String),
    #[error("invalid: {0}")]
    Invalid(String),
    #[error("cannot publish: {count} issue(s)")]
    ValidationFailed { count: usize, issues: Vec<ValidationIssue> },
    #[error("zip: {0}")]
    Zip(String),
    #[error("attachment changed since upload (relpath: {0})")]
    AttachmentChanged(String),
}

impl From<rusqlite::Error> for BundleError {
    fn from(e: rusqlite::Error) -> Self {
        BundleError::Db(e.to_string())
    }
}

impl From<ZipError> for BundleError {
    fn from(e: ZipError) -> Self {
        match e {
            ZipError::AttachmentChanged { relpath } => BundleError::AttachmentChanged(relpath),
            other => BundleError::Zip(other.to_string()),
        }
    }
}

impl serde::Serialize for BundleError {
    fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        use serde::ser::SerializeStruct;
        // Surface validation issues as structured JSON so the frontend
        // can render the checklist; everything else as a plain message.
        if let BundleError::ValidationFailed { count, issues } = self {
            let mut st = s.serialize_struct("BundleError", 3)?;
            st.serialize_field("kind", "validationFailed")?;
            st.serialize_field("count", count)?;
            st.serialize_field("issues", issues)?;
            st.end()
        } else {
            let mut st = s.serialize_struct("BundleError", 2)?;
            st.serialize_field("kind", "error")?;
            st.serialize_field("message", &self.to_string())?;
            st.end()
        }
    }
}

// ---------------------------------------------------------------------------
// Boundary types — every struct that crosses serialize/deserialize MUST
// be camelCase (asserted in lib.rs::camel_case_contract).
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum Severity {
    Error,
    Warn,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ValidationIssue {
    pub field_path: String,
    pub message: String,
    pub severity: Severity,
    /// DOM id the form rendered for this field; the frontend's
    /// ValidationChecklist scrolls/focuses to it.
    pub jump_to_field_id: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BundleSummary {
    pub uid: String,
    pub bundle_type: String,
    pub persona_code: Option<String>,
    pub state: String,
    pub title: String,
    pub content_date: String,
    pub go_live_date: Option<String>,
    pub published_at: Option<String>,
    pub bundle_path: Option<String>,
    pub bundle_size_bytes: Option<i64>,
    pub created_at: String,
    pub updated_at: String,
    /// Calculated from `created_at` vs `BundlerSettings.warn_threshold_days`.
    pub aging_flag: String, // "fresh" | "aging" | "overdue"
    pub file_count: i64,
    pub tag_ids: Vec<i64>,
    /// Set by return_file::import_return_file. Non-NULL means Sallie has
    /// imported the post-bundle for this row.
    pub completed_at: Option<String>,
    /// Scheduled cleanup timestamp — set on return-file import to 3 days
    /// out. The auto-purge pass picks up rows whose delete_after has passed.
    pub delete_after: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BundleFileInfo {
    pub id: i64,
    pub bundle_uid: String,
    pub fansite_day_id: Option<i64>,
    pub position: i64,
    pub relpath: String,
    /// Resolved against app_data_dir at read time so the frontend can
    /// pass it to `convertFileSrc` without round-tripping through Rust.
    /// Empty on save returns until reread (callers using save_bundle_file's
    /// returned shape should rely on relpath + a follow-up get_bundle).
    pub absolute_path: String,
    pub original_name: String,
    pub kind: String,
    pub size_bytes: i64,
    pub sha256: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BundleCategory {
    pub name: String,
    pub position: i64,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BundleFanDay {
    pub id: i64,
    pub day_of_month: i64,
    pub message: String,
    pub file_count: i64,
    pub tag_ids: Vec<i64>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Bundle {
    pub summary: BundleSummary,
    pub special_instructions: String,
    pub description_mode: Option<String>,
    pub description_text: String,
    pub description_audio_relpath: Option<String>,
    /// Resolved against app_data_dir for `convertFileSrc` consumption.
    pub description_audio_absolute_path: Option<String>,
    pub description_audio_original_name: Option<String>,
    pub delivery_kind: Option<String>,
    pub delivery_site_id: Option<i64>,
    pub delivery_url: Option<String>,
    pub delivery_recipient: String,
    pub price_cents: Option<i64>,
    pub handled_in_platform: bool,
    pub fansite_year: Option<i64>,
    pub fansite_month: Option<i64>,
    pub outer_sha256: Option<String>,
    pub inner_sha256: Option<String>,
    pub files: Vec<BundleFileInfo>,
    pub categories: Vec<BundleCategory>,
    pub fan_days: Vec<BundleFanDay>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BundleFieldPatch {
    pub title: Option<String>,
    pub go_live_date: Option<Option<String>>,
    pub special_instructions: Option<String>,
    pub description_mode: Option<Option<String>>,
    pub description_text: Option<String>,
    pub delivery_kind: Option<Option<String>>,
    pub delivery_site_id: Option<Option<i64>>,
    pub delivery_url: Option<Option<String>>,
    pub delivery_recipient: Option<String>,
    pub price_cents: Option<Option<i64>>,
    pub handled_in_platform: Option<bool>,
    pub fansite_year: Option<Option<i64>>,
    pub fansite_month: Option<Option<i64>>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BundlePublishResult {
    pub uid: String,
    pub path: String,
    pub size_bytes: u64,
    pub inner_sha256: String,
    pub outer_sha256: String,
    pub file_count: usize,
    pub clip_created: bool,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PurgeResult {
    pub considered: u32,
    pub purged: u32,
    pub skipped_missing: u32,
    pub last_run_at: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BundleArchiveRow {
    pub uid: Option<String>,
    pub path: String,
    pub filename: String,
    pub modified_at: String,
    pub size_bytes: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BundlerSettings {
    pub bundle_path: Option<String>,
    pub warn_threshold_days: u32,
    pub purge_threshold_days: u32,
    pub auto_purge_enabled: bool,
    pub last_purge_at: Option<String>,
}

impl Default for BundlerSettings {
    fn default() -> Self {
        Self {
            bundle_path: None,
            warn_threshold_days: 30,
            purge_threshold_days: 60,
            auto_purge_enabled: true,
            last_purge_at: None,
        }
    }
}

impl BundlerSettings {
    fn resolved_output_dir(&self) -> PathBuf {
        match &self.bundle_path {
            Some(p) if !p.is_empty() => PathBuf::from(p),
            _ => fsutil::downloads_subdir(BUNDLE_FOLDER),
        }
    }
}

// ---------------------------------------------------------------------------
// Settings load/save (mirrors backup.rs::Settings file pattern)
// ---------------------------------------------------------------------------

fn settings_path(app_data_dir: &Path) -> PathBuf {
    app_data_dir.join(SETTINGS_FILENAME)
}

pub(crate) fn load_settings(app_data_dir: &Path) -> BundlerSettings {
    let path = settings_path(app_data_dir);
    fs::read(&path)
        .ok()
        .and_then(|bytes| serde_json::from_slice::<BundlerSettings>(&bytes).ok())
        .unwrap_or_default()
}

pub(crate) fn save_settings(
    app_data_dir: &Path,
    settings: &BundlerSettings,
) -> Result<(), BundleError> {
    fs::create_dir_all(app_data_dir)?;
    let path = settings_path(app_data_dir);
    let bytes = serde_json::to_vec_pretty(settings)
        .map_err(|e| BundleError::Settings(e.to_string()))?;
    let tmp = path.with_extension("json.tmp");
    fs::write(&tmp, &bytes)?;
    fs::rename(&tmp, &path)?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Connection plumbing (rusqlite handle to molly.db, same approach as c4s.rs)
// ---------------------------------------------------------------------------

fn app_data_dir<R: Runtime>(handle: &AppHandle<R>) -> Result<PathBuf, BundleError> {
    handle
        .path()
        .app_data_dir()
        .map_err(|e| BundleError::Settings(e.to_string()))
}

fn open_conn(app_data_dir: &Path) -> Result<Connection, BundleError> {
    let db_path = app_data_dir.join("molly.db");
    let conn = Connection::open(&db_path)
        .map_err(|e| BundleError::Db(format!("open {}: {e}", db_path.display())))?;
    conn.busy_timeout(Duration::from_secs(5))?;
    conn.execute_batch("PRAGMA foreign_keys = ON;")?;
    Ok(conn)
}

// ---------------------------------------------------------------------------
// UID generation — `YYYY-MM-DD-####` (4-digit counter, shared per day)
// ---------------------------------------------------------------------------

fn iso_today() -> String {
    Local::now().format("%Y-%m-%d").to_string()
}

fn iso_now() -> String {
    Utc::now().to_rfc3339()
}

/// True iff `s` matches the bundle UID shape `YYYY-MM-DD-NNNN`. Used when
/// scanning the bundle directory to tell our archives apart from any
/// unrelated zips a user has dropped in there.
fn is_bundle_uid(s: &str) -> bool {
    if s.len() != 15 {
        return false;
    }
    s.chars().enumerate().all(|(i, c)| match i {
        4 | 7 | 10 => c == '-',
        _ => c.is_ascii_digit(),
    })
}

/// Return the next bundle UID for `today`. `today` is the date prefix
/// (YYYY-MM-DD); we scan `bundles` for the max counter already used
/// today, add 1, zero-pad to 4 digits. Pulls the value with one
/// SELECT against a regular index — no SEQUENCE table.
pub(crate) fn next_uid_in_conn(conn: &Connection, today: &str) -> Result<String, BundleError> {
    let like = format!("{}-%", today);
    let max: Option<String> = conn
        .query_row(
            "SELECT uid FROM bundles WHERE uid LIKE ?1 ORDER BY uid DESC LIMIT 1",
            params![like],
            |row| row.get(0),
        )
        .ok();
    let next: u32 = match max {
        Some(uid) => uid
            .rsplit('-')
            .next()
            .and_then(|n| n.parse::<u32>().ok())
            .map(|n| n + 1)
            .unwrap_or(1),
        None => 1,
    };
    if next > 9999 {
        return Err(BundleError::Invalid(
            "exhausted 9999 bundle UIDs for today".into(),
        ));
    }
    Ok(format!("{today}-{:04}", next))
}

// ---------------------------------------------------------------------------
// Validation helpers — server-side mirror of src/lib/bundleValidation.ts.
// Each fn appends to `issues`; no short-circuit so callers can show the
// full checklist.
// ---------------------------------------------------------------------------

const PLACEHOLDER_TITLES: &[&str] = &["none", "blank", "custom"];

pub(crate) fn validate_title(title: &str, issues: &mut Vec<ValidationIssue>) {
    let trimmed = title.trim();
    if trimmed.is_empty() {
        issues.push(ValidationIssue {
            field_path: "title".into(),
            message: "Title can't be blank.".into(),
            severity: Severity::Error,
            jump_to_field_id: "bundle-title".into(),
        });
        return;
    }
    let lower = trimmed.to_lowercase();
    if PLACEHOLDER_TITLES.contains(&lower.as_str()) {
        issues.push(ValidationIssue {
            field_path: "title".into(),
            message: format!("Title can't be a placeholder ({}).", trimmed),
            severity: Severity::Error,
            jump_to_field_id: "bundle-title".into(),
        });
    }
    let words = trimmed.split_whitespace().filter(|s| !s.is_empty()).count();
    if words < 2 {
        issues.push(ValidationIssue {
            field_path: "title".into(),
            message: "Title needs at least two words.".into(),
            severity: Severity::Error,
            jump_to_field_id: "bundle-title".into(),
        });
    }
}

pub(crate) fn validate_persona(persona: Option<&str>, issues: &mut Vec<ValidationIssue>) {
    if persona.is_none() || persona.map(|p| p.is_empty()).unwrap_or(true) {
        issues.push(ValidationIssue {
            field_path: "persona".into(),
            message: "Persona is required.".into(),
            severity: Severity::Error,
            jump_to_field_id: "bundle-persona".into(),
        });
    }
}

pub(crate) fn validate_go_live(
    go_live: Option<&str>,
    today: NaiveDate,
    issues: &mut Vec<ValidationIssue>,
) {
    let Some(s) = go_live else {
        issues.push(ValidationIssue {
            field_path: "goLiveDate".into(),
            message: "Go-live date is required.".into(),
            severity: Severity::Error,
            jump_to_field_id: "bundle-go-live".into(),
        });
        return;
    };
    let Ok(date) = NaiveDate::parse_from_str(s, "%Y-%m-%d") else {
        issues.push(ValidationIssue {
            field_path: "goLiveDate".into(),
            message: "Go-live date isn't a valid YYYY-MM-DD.".into(),
            severity: Severity::Error,
            jump_to_field_id: "bundle-go-live".into(),
        });
        return;
    };
    if date < today {
        issues.push(ValidationIssue {
            field_path: "goLiveDate".into(),
            message: "Go-live date can't be in the past.".into(),
            severity: Severity::Error,
            jump_to_field_id: "bundle-go-live".into(),
        });
    } else if date <= today + chrono::Duration::days(5) {
        issues.push(ValidationIssue {
            field_path: "goLiveDate".into(),
            message: "Are you allowing enough time for editing?".into(),
            severity: Severity::Warn,
            jump_to_field_id: "bundle-go-live".into(),
        });
    }
}

pub(crate) fn validate_content_description(
    text: &str,
    audio_relpath: Option<&str>,
    prohibited_words: &[String],
    issues: &mut Vec<ValidationIssue>,
) {
    let has_text = !text.trim().is_empty();
    let has_audio = audio_relpath.is_some();
    if !has_text && !has_audio {
        issues.push(ValidationIssue {
            field_path: "description".into(),
            message: "Add a text description or upload an audio file.".into(),
            severity: Severity::Error,
            jump_to_field_id: "bundle-description".into(),
        });
    }
    if has_text && has_audio {
        issues.push(ValidationIssue {
            field_path: "description".into(),
            message: "Pick one — text or audio, not both.".into(),
            severity: Severity::Error,
            jump_to_field_id: "bundle-description".into(),
        });
    }
    if has_text {
        let lower = text.to_lowercase();
        for w in prohibited_words {
            if !w.is_empty() && lower.contains(&w.to_lowercase()) {
                issues.push(ValidationIssue {
                    field_path: "description.text".into(),
                    message: format!("Description contains prohibited word: '{w}'."),
                    severity: Severity::Error,
                    jump_to_field_id: "bundle-description-text".into(),
                });
            }
        }
    }
}

pub(crate) fn validate_categories(
    categories: &[BundleCategory],
    issues: &mut Vec<ValidationIssue>,
) {
    if categories.len() < 3 {
        issues.push(ValidationIssue {
            field_path: "categories".into(),
            message: format!(
                "Pick at least 3 categories (you have {}).",
                categories.len()
            ),
            severity: Severity::Error,
            jump_to_field_id: "bundle-categories".into(),
        });
    }
}

pub(crate) fn validate_content_files(
    files: &[BundleFileInfo],
    issues: &mut Vec<ValidationIssue>,
) {
    let media: Vec<&BundleFileInfo> = files
        .iter()
        .filter(|f| f.kind == "video" || f.kind == "image")
        .collect();
    if media.is_empty() {
        issues.push(ValidationIssue {
            field_path: "files".into(),
            message: "Upload at least one video or image.".into(),
            severity: Severity::Error,
            jump_to_field_id: "bundle-files".into(),
        });
    }
}

/// Top-level validator for the Content bundle type.
pub(crate) fn validate_content_bundle(
    bundle: &Bundle,
    today: NaiveDate,
    prohibited_words: &[String],
) -> Vec<ValidationIssue> {
    let mut issues = Vec::new();
    validate_title(&bundle.summary.title, &mut issues);
    validate_persona(bundle.summary.persona_code.as_deref(), &mut issues);
    validate_go_live(bundle.summary.go_live_date.as_deref(), today, &mut issues);
    validate_content_description(
        &bundle.description_text,
        bundle.description_audio_relpath.as_deref(),
        prohibited_words,
        &mut issues,
    );
    validate_categories(&bundle.categories, &mut issues);
    validate_content_files(&bundle.files, &mut issues);
    issues
}

/// Custom-bundle delivery rule: `delivery_kind` must be set; if 'site' a
/// site id is required; if 'url' nothing else is required here (Robert
/// fills in the URL later via the SideMolly return-file flow). Recipient
/// is always required; price required unless handled-in-platform.
pub(crate) fn validate_custom_delivery(
    bundle: &Bundle,
    issues: &mut Vec<ValidationIssue>,
) {
    match bundle.delivery_kind.as_deref() {
        None => {
            issues.push(ValidationIssue {
                field_path: "delivery".into(),
                message: "Pick a delivery method (Site or URL link).".into(),
                severity: Severity::Error,
                jump_to_field_id: "bundle-delivery".into(),
            });
        }
        Some("site") if bundle.delivery_site_id.is_none() => {
            issues.push(ValidationIssue {
                field_path: "delivery".into(),
                message: "Pick a site for this persona.".into(),
                severity: Severity::Error,
                jump_to_field_id: "bundle-delivery-site".into(),
            });
        }
        _ => {}
    }
    if bundle.delivery_recipient.trim().is_empty() {
        issues.push(ValidationIssue {
            field_path: "delivery.recipient".into(),
            message: "Who is this for? Add a recipient name / username.".into(),
            severity: Severity::Error,
            jump_to_field_id: "bundle-delivery-recipient".into(),
        });
    }
    if !bundle.handled_in_platform {
        match bundle.price_cents {
            None => {
                issues.push(ValidationIssue {
                    field_path: "price".into(),
                    message: "Set a price (or tick \"handled in delivery platform\").".into(),
                    severity: Severity::Error,
                    jump_to_field_id: "bundle-price".into(),
                });
            }
            Some(c) if c < 0 => {
                issues.push(ValidationIssue {
                    field_path: "price".into(),
                    message: "Price can't be negative.".into(),
                    severity: Severity::Error,
                    jump_to_field_id: "bundle-price".into(),
                });
            }
            _ => {}
        }
    }
}

/// Top-level validator for the Custom bundle type.
pub(crate) fn validate_custom_bundle(bundle: &Bundle, today: NaiveDate) -> Vec<ValidationIssue> {
    let mut issues = Vec::new();
    validate_title(&bundle.summary.title, &mut issues);
    validate_persona(bundle.summary.persona_code.as_deref(), &mut issues);
    validate_go_live(bundle.summary.go_live_date.as_deref(), today, &mut issues);
    validate_content_files(&bundle.files, &mut issues);
    validate_custom_delivery(bundle, &mut issues);
    issues
}

/// FanSite completion check — given a (year, month), every day in that
/// month must have a `bundle_fan_days` row with a non-empty message AND
/// at least one file. Days are 1..N where N is days-in-month (28/29/30/31).
pub(crate) fn validate_fansite_completion(bundle: &Bundle, issues: &mut Vec<ValidationIssue>) {
    let (Some(y), Some(m)) = (bundle.fansite_year, bundle.fansite_month) else {
        issues.push(ValidationIssue {
            field_path: "fansiteMonth".into(),
            message: "Pick a month and year to plan posts for.".into(),
            severity: Severity::Error,
            jump_to_field_id: "bundle-fansite-month".into(),
        });
        return;
    };
    let days_in_month = days_in_month(y as i32, m as u32);
    if days_in_month == 0 {
        issues.push(ValidationIssue {
            field_path: "fansiteMonth".into(),
            message: format!("Month {m} doesn't look right (need 1-12)."),
            severity: Severity::Error,
            jump_to_field_id: "bundle-fansite-month".into(),
        });
        return;
    }
    // Index fan_days by day_of_month for fast lookup.
    let mut day_map: std::collections::HashMap<i64, &BundleFanDay> =
        std::collections::HashMap::new();
    for d in &bundle.fan_days {
        day_map.insert(d.day_of_month, d);
    }
    for day in 1..=days_in_month {
        let entry = day_map.get(&(day as i64));
        let has_message = entry.map(|d| !d.message.trim().is_empty()).unwrap_or(false);
        let file_count = entry.map(|d| d.file_count).unwrap_or(0);
        if !has_message || file_count < 1 {
            let missing = match (has_message, file_count >= 1) {
                (false, false) => "needs a message and a file",
                (false, true) => "needs a message",
                (true, false) => "needs a file",
                _ => "ok",
            };
            issues.push(ValidationIssue {
                field_path: format!("fanDay.{:02}", day),
                message: format!("Day {:02} {}.", day, missing),
                severity: Severity::Error,
                jump_to_field_id: format!("bundle-fan-day-{:02}", day),
            });
        }
    }
}

/// Top-level validator for the FanSite bundle type.
pub(crate) fn validate_fansite_bundle(bundle: &Bundle) -> Vec<ValidationIssue> {
    let mut issues = Vec::new();
    validate_title(&bundle.summary.title, &mut issues);
    validate_persona(bundle.summary.persona_code.as_deref(), &mut issues);
    validate_fansite_completion(bundle, &mut issues);
    issues
}

/// Calendar days in (year, month). Returns 0 if month is out of 1..=12.
pub(crate) fn days_in_month(year: i32, month: u32) -> u32 {
    if month < 1 || month > 12 {
        return 0;
    }
    // First day of next month minus one day = last day of this month.
    let (ny, nm) = if month == 12 { (year + 1, 1) } else { (year, month + 1) };
    let first_of_next = match chrono::NaiveDate::from_ymd_opt(ny, nm, 1) {
        Some(d) => d,
        None => return 0,
    };
    let last = first_of_next - chrono::Duration::days(1);
    last.day()
}

// ---------------------------------------------------------------------------
// SQL: load/save core CRUD ops. All take `&Connection` so they're testable
// against an in-memory DB.
// ---------------------------------------------------------------------------

fn aging_flag(created_at: &str, threshold_days: u32) -> String {
    if threshold_days == 0 {
        return "fresh".into();
    }
    // Try RFC3339 first (RFC3339-shaped strings stored by Tauri commands),
    // then SQLite's `datetime('now')` format (`YYYY-MM-DD HH:MM:SS` UTC).
    let created: DateTime<Utc> = if let Ok(dt) = DateTime::parse_from_rfc3339(created_at) {
        dt.with_timezone(&Utc)
    } else if let Ok(naive) =
        chrono::NaiveDateTime::parse_from_str(created_at, "%Y-%m-%d %H:%M:%S")
    {
        Utc.from_utc_datetime(&naive)
    } else {
        return "fresh".into();
    };
    let age_days = (Utc::now() - created).num_days();
    if age_days >= threshold_days as i64 * 2 {
        "overdue".into()
    } else if age_days >= threshold_days as i64 {
        "aging".into()
    } else {
        "fresh".into()
    }
}

use chrono::TimeZone;

fn row_to_summary(
    row: &rusqlite::Row,
    warn_threshold_days: u32,
    file_count: i64,
    tag_ids: Vec<i64>,
) -> rusqlite::Result<BundleSummary> {
    let created_at: String = row.get("created_at")?;
    Ok(BundleSummary {
        uid: row.get("uid")?,
        bundle_type: row.get("bundle_type")?,
        persona_code: row.get("persona_code")?,
        state: row.get("state")?,
        title: row.get("title")?,
        content_date: row.get("content_date")?,
        go_live_date: row.get("go_live_date")?,
        published_at: row.get("published_at")?,
        bundle_path: row.get("bundle_path")?,
        bundle_size_bytes: row.get("bundle_size_bytes")?,
        aging_flag: aging_flag(&created_at, warn_threshold_days),
        created_at,
        updated_at: row.get("updated_at")?,
        file_count,
        tag_ids,
        completed_at: row.get("completed_at")?,
        delete_after: row.get("delete_after")?,
    })
}

/// Helper: read the tag-id list for a bundle. Used by row_to_summary
/// callers + the public Bundle composer. Returns empty if the bundle
/// has no tags yet (table doesn't even need a row).
fn load_tag_ids(conn: &Connection, uid: &str) -> rusqlite::Result<Vec<i64>> {
    let mut stmt = conn.prepare(
        "SELECT tag_id FROM bundle_tag_links WHERE bundle_uid = ?1 ORDER BY tag_id",
    )?;
    let rows = stmt
        .query_map(params![uid], |r| r.get::<_, i64>(0))?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(rows)
}

pub(crate) fn pure_create_bundle(
    conn: &Connection,
    today: &str,
    bundle_type: &str,
    persona_code: Option<&str>,
) -> Result<String, BundleError> {
    match bundle_type {
        "content" | "custom" | "fansite" => {}
        other => return Err(BundleError::Invalid(format!("unknown bundle type {other}"))),
    }
    let uid = next_uid_in_conn(conn, today)?;
    conn.execute(
        "INSERT INTO bundles (uid, bundle_type, persona_code, content_date)
         VALUES (?1, ?2, ?3, ?4)",
        params![uid, bundle_type, persona_code, today],
    )?;
    Ok(uid)
}

fn load_files_for(
    conn: &Connection,
    uid: &str,
    support_dir: &Path,
) -> Result<Vec<BundleFileInfo>, BundleError> {
    let mut stmt = conn.prepare(
        "SELECT id, bundle_uid, fansite_day_id, position, relpath, original_name, kind,
                size_bytes, sha256
         FROM bundle_files
         WHERE bundle_uid = ?1
         ORDER BY COALESCE(fansite_day_id, 0), position, id",
    )?;
    let rows = stmt
        .query_map(params![uid], |r| {
            let relpath: String = r.get(4)?;
            let absolute_path = absolute_for(support_dir, &relpath);
            Ok(BundleFileInfo {
                id: r.get(0)?,
                bundle_uid: r.get(1)?,
                fansite_day_id: r.get(2)?,
                position: r.get(3)?,
                relpath,
                absolute_path,
                original_name: r.get(5)?,
                kind: r.get(6)?,
                size_bytes: r.get(7)?,
                sha256: r.get(8)?,
            })
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(rows)
}

/// Resolve a relative attachment path to a string the frontend can pass to
/// `convertFileSrc`. Empty `support_dir` (used in tests where there's no
/// app_data) just returns the relpath unchanged.
fn absolute_for(support_dir: &Path, relpath: &str) -> String {
    if support_dir.as_os_str().is_empty() {
        relpath.to_string()
    } else {
        support_dir
            .join(relpath)
            .to_string_lossy()
            .into_owned()
    }
}

fn load_categories_for(conn: &Connection, uid: &str) -> Result<Vec<BundleCategory>, BundleError> {
    let mut stmt = conn.prepare(
        "SELECT name, position FROM bundle_categories WHERE bundle_uid = ?1 ORDER BY position",
    )?;
    let rows = stmt
        .query_map(params![uid], |r| {
            Ok(BundleCategory {
                name: r.get(0)?,
                position: r.get(1)?,
            })
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(rows)
}

fn load_fan_days_for(conn: &Connection, uid: &str) -> Result<Vec<BundleFanDay>, BundleError> {
    let mut stmt = conn.prepare(
        "SELECT bundle_fan_days.id, bundle_fan_days.day_of_month, bundle_fan_days.message,
                COUNT(bundle_files.id) AS file_count
         FROM bundle_fan_days
         LEFT JOIN bundle_files ON bundle_files.fansite_day_id = bundle_fan_days.id
         WHERE bundle_fan_days.bundle_uid = ?1
         GROUP BY bundle_fan_days.id, bundle_fan_days.day_of_month, bundle_fan_days.message
         ORDER BY bundle_fan_days.day_of_month",
    )?;
    let mut rows: Vec<BundleFanDay> = stmt
        .query_map(params![uid], |r| {
            Ok(BundleFanDay {
                id: r.get(0)?,
                day_of_month: r.get(1)?,
                message: r.get(2)?,
                file_count: r.get(3)?,
                tag_ids: Vec::new(),
            })
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    drop(stmt);
    // Second pass for tag_ids per day — keeps the GROUP BY shape clean.
    for d in rows.iter_mut() {
        let mut tag_stmt = conn.prepare(
            "SELECT tag_id FROM bundle_tag_links WHERE fan_day_id = ?1 ORDER BY tag_id",
        )?;
        d.tag_ids = tag_stmt
            .query_map(params![d.id], |r| r.get::<_, i64>(0))?
            .collect::<rusqlite::Result<Vec<_>>>()?;
    }
    Ok(rows)
}

pub(crate) fn pure_get_bundle(
    conn: &Connection,
    uid: &str,
    warn_threshold_days: u32,
    support_dir: &Path,
) -> Result<Bundle, BundleError> {
    let files = load_files_for(conn, uid, support_dir)?;
    let categories = load_categories_for(conn, uid)?;
    let fan_days = load_fan_days_for(conn, uid)?;
    let file_count = files.len() as i64;
    let mut stmt = conn.prepare(
        "SELECT uid, bundle_type, persona_code, state, title, content_date, go_live_date,
                special_instructions, description_mode, description_text,
                description_audio_relpath,
                delivery_kind, delivery_site_id, delivery_url, delivery_recipient,
                price_cents, handled_in_platform,
                fansite_year, fansite_month,
                published_at, bundle_path, bundle_size_bytes,
                outer_sha256, inner_sha256,
                created_at, updated_at,
                completed_at, delete_after
         FROM bundles WHERE uid = ?1",
    )?;
    let mut rows = stmt.query(params![uid])?;
    let Some(row) = rows.next()? else {
        return Err(BundleError::NotFound(uid.to_string()));
    };

    let tag_ids = load_tag_ids(conn, uid)?;
    let summary = row_to_summary(row, warn_threshold_days, file_count, tag_ids)?;
    let description_audio_relpath: Option<String> = row.get("description_audio_relpath")?;
    let description_audio_original_name = description_audio_relpath
        .as_deref()
        .and_then(|p| {
            // attachments/.../<uuid>_<orig>
            let last = p.rsplit('/').next()?;
            let after_uuid = last.splitn(2, '_').nth(1)?;
            Some(after_uuid.to_string())
        });

    let description_audio_absolute_path = description_audio_relpath
        .as_deref()
        .map(|rel| absolute_for(support_dir, rel));

    Ok(Bundle {
        summary,
        special_instructions: row.get("special_instructions")?,
        description_mode: row.get("description_mode")?,
        description_text: row.get("description_text")?,
        description_audio_relpath,
        description_audio_absolute_path,
        description_audio_original_name,
        delivery_kind: row.get("delivery_kind")?,
        delivery_site_id: row.get("delivery_site_id")?,
        delivery_url: row.get("delivery_url")?,
        delivery_recipient: row.get("delivery_recipient")?,
        price_cents: row.get("price_cents")?,
        handled_in_platform: row.get::<_, i64>("handled_in_platform")? != 0,
        fansite_year: row.get("fansite_year")?,
        fansite_month: row.get("fansite_month")?,
        outer_sha256: row.get("outer_sha256")?,
        inner_sha256: row.get("inner_sha256")?,
        files,
        categories,
        fan_days,
    })
}

pub(crate) fn pure_list_bundles(
    conn: &Connection,
    state: Option<&str>,
    warn_threshold_days: u32,
) -> Result<Vec<BundleSummary>, BundleError> {
    // Pull summaries + per-bundle file counts in one round trip.
    let (sql, p): (&str, Vec<SqlValue>) = match state {
        Some(s) => (
            "SELECT b.uid, b.bundle_type, b.persona_code, b.state, b.title, b.content_date,
                    b.go_live_date, b.published_at, b.bundle_path, b.bundle_size_bytes,
                    b.created_at, b.updated_at, b.completed_at, b.delete_after,
                    (SELECT COUNT(*) FROM bundle_files WHERE bundle_uid = b.uid) AS file_count
             FROM bundles b
             WHERE b.state = ?1
             ORDER BY b.created_at DESC",
            vec![SqlValue::Text(s.to_string())],
        ),
        None => (
            "SELECT b.uid, b.bundle_type, b.persona_code, b.state, b.title, b.content_date,
                    b.go_live_date, b.published_at, b.bundle_path, b.bundle_size_bytes,
                    b.created_at, b.updated_at, b.completed_at, b.delete_after,
                    (SELECT COUNT(*) FROM bundle_files WHERE bundle_uid = b.uid) AS file_count
             FROM bundles b
             ORDER BY b.created_at DESC",
            vec![],
        ),
    };
    let mut stmt = conn.prepare(sql)?;
    let mut summaries: Vec<BundleSummary> = stmt
        .query_map(rusqlite::params_from_iter(p.iter()), |row| {
            let file_count: i64 = row.get("file_count")?;
            // Tags are loaded in a second pass below so we don't fight the
            // borrow checker against `conn` while the prepared statement
            // is live.
            row_to_summary(row, warn_threshold_days, file_count, Vec::new())
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    drop(stmt);
    for s in summaries.iter_mut() {
        s.tag_ids = load_tag_ids(conn, &s.uid)?;
    }
    Ok(summaries)
}

/// Set categories for a bundle. Uppercases, dedups (case-insensitively),
/// strips empties, and renumbers `position` to 1..N. Mirrors
/// MasterClipper's `setCategories` two-step (delete all + reinsert).
pub(crate) fn pure_set_categories(
    conn: &Connection,
    uid: &str,
    names_in_order: &[String],
) -> Result<(), BundleError> {
    let mut seen = std::collections::HashSet::new();
    let cleaned: Vec<String> = names_in_order
        .iter()
        .map(|s| s.trim().to_uppercase())
        .filter(|s| !s.is_empty())
        .filter(|s| seen.insert(s.clone()))
        .collect();

    conn.execute(
        "DELETE FROM bundle_categories WHERE bundle_uid = ?1",
        params![uid],
    )?;
    for (i, name) in cleaned.iter().enumerate() {
        conn.execute(
            "INSERT INTO bundle_categories (bundle_uid, name, position) VALUES (?1, ?2, ?3)",
            params![uid, name, (i as i64) + 1],
        )?;
    }
    conn.execute(
        "UPDATE bundles SET updated_at = datetime('now') WHERE uid = ?1",
        params![uid],
    )?;
    Ok(())
}

pub(crate) fn pure_reorder_files(
    conn: &Connection,
    uid: &str,
    ordered_ids: &[i64],
) -> Result<(), BundleError> {
    for (i, id) in ordered_ids.iter().enumerate() {
        conn.execute(
            "UPDATE bundle_files SET position = ?1 WHERE id = ?2 AND bundle_uid = ?3",
            params![(i as i64) + 1, id, uid],
        )?;
    }
    conn.execute(
        "UPDATE bundles SET updated_at = datetime('now') WHERE uid = ?1",
        params![uid],
    )?;
    Ok(())
}

pub(crate) fn pure_delete_bundle_draft(
    conn: &Connection,
    uid: &str,
) -> Result<Vec<String>, BundleError> {
    // Caller is responsible for deleting attachment files on disk; we
    // return the relpaths so they can do that AFTER the SQL commits.
    let mut stmt = conn.prepare(
        "SELECT relpath FROM bundle_files WHERE bundle_uid = ?1
         UNION
         SELECT description_audio_relpath FROM bundles WHERE uid = ?1 AND description_audio_relpath IS NOT NULL",
    )?;
    let relpaths = stmt
        .query_map(params![uid], |r| r.get::<_, String>(0))?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    conn.execute("DELETE FROM bundles WHERE uid = ?1", params![uid])?;
    Ok(relpaths)
}

pub(crate) fn pure_list_prohibited(conn: &Connection) -> Result<Vec<String>, BundleError> {
    let mut stmt = conn.prepare("SELECT word FROM bundle_prohibited_words ORDER BY word")?;
    let rows = stmt
        .query_map([], |r| r.get::<_, String>(0))?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(rows)
}

pub(crate) fn pure_add_prohibited(conn: &Connection, word: &str) -> Result<(), BundleError> {
    let cleaned = word.trim();
    if cleaned.is_empty() {
        return Err(BundleError::Invalid("word can't be empty".into()));
    }
    conn.execute(
        "INSERT INTO bundle_prohibited_words (word) VALUES (?1)
         ON CONFLICT(word) DO NOTHING",
        params![cleaned],
    )?;
    Ok(())
}

pub(crate) fn pure_remove_prohibited(conn: &Connection, word: &str) -> Result<(), BundleError> {
    conn.execute(
        "DELETE FROM bundle_prohibited_words WHERE word = ?1 COLLATE NOCASE",
        params![word],
    )?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Publish flow — build snapshot, compose, stamp DB inside transaction,
// upsert clip for Content type.
// ---------------------------------------------------------------------------

fn build_snapshot(
    conn: &Connection,
    bundle: &Bundle,
    support_dir: &Path,
    published_at: String,
) -> Result<BundleSnapshot, BundleError> {
    let bundle_type = match bundle.summary.bundle_type.as_str() {
        "content" => BundleType::Content,
        "custom" => BundleType::Custom,
        "fansite" => BundleType::FanSite,
        other => return Err(BundleError::Invalid(format!("unknown type {other}"))),
    };

    // Resolve the audio file (Content type).
    let description_audio = if let Some(rel) = &bundle.description_audio_relpath {
        let abs = resolve_relative(support_dir, rel)?;
        // Hash from disk if we don't have a stored hash (rare — uploaded via UI always stores it).
        let stored: Option<String> = conn
            .query_row(
                "SELECT description_audio_sha256 FROM bundles WHERE uid = ?1",
                params![bundle.summary.uid],
                |r| r.get(0),
            )
            .ok()
            .flatten();
        let sha = stored.unwrap_or_default();
        let original = bundle
            .description_audio_original_name
            .clone()
            .unwrap_or_else(|| "audio".to_string());
        Some(FileEntry {
            original_name: original,
            abs_path: abs,
            relpath_for_error: rel.clone(),
            kind: FileKind::Audio,
            position: 0,
            sha256_db: sha,
            fansite_day_of_month: None,
        })
    } else {
        None
    };

    // Resolve all bundle_files rows to FileEntry. For FanSite we look up
    // each row's day_of_month via the fan_days table.
    let mut day_by_id = std::collections::HashMap::new();
    for d in &bundle.fan_days {
        day_by_id.insert(d.id, d.day_of_month);
    }
    let mut files: Vec<FileEntry> = Vec::with_capacity(bundle.files.len());
    for f in &bundle.files {
        let abs = resolve_relative(support_dir, &f.relpath)?;
        let kind = match f.kind.as_str() {
            "video" => FileKind::Video,
            "image" => FileKind::Image,
            "audio" => FileKind::Audio,
            other => return Err(BundleError::Invalid(format!("unknown kind {other}"))),
        };
        let fansite_day_of_month = f.fansite_day_id.and_then(|id| day_by_id.get(&id).copied());
        files.push(FileEntry {
            original_name: f.original_name.clone(),
            abs_path: abs,
            relpath_for_error: f.relpath.clone(),
            kind,
            position: f.position,
            sha256_db: f.sha256.clone(),
            fansite_day_of_month,
        });
    }

    // Delivery site label (if site picked).
    let delivery_site_name = if let Some(id) = bundle.delivery_site_id {
        conn.query_row(
            "SELECT name FROM sites WHERE id = ?1",
            params![id],
            |r| r.get::<_, String>(0),
        )
        .ok()
    } else {
        None
    };

    // Bundle-level content tags (sorted by tag sort_order / name to match
    // the picker display). For FanSite bundles these are usually empty
    // because tagging happens per-day, but the read is harmless.
    let bundle_tag_names: Vec<String> = {
        let mut stmt = conn.prepare(
            "SELECT t.name
             FROM bundle_tag_links l
             JOIN content_tags_def t ON t.id = l.tag_id
             WHERE l.bundle_uid = ?1 AND l.fan_day_id IS NULL
             ORDER BY t.sort_order, t.name COLLATE NOCASE",
        )?;
        let names = stmt
            .query_map(params![bundle.summary.uid], |r| r.get::<_, String>(0))?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        names
    };

    // Per-day tag names for FanSite. Built into a HashMap keyed by
    // fan_day_id so the FanDay loop below can stitch them in without
    // another query per day.
    let mut tags_by_fan_day: std::collections::HashMap<i64, Vec<String>> =
        std::collections::HashMap::new();
    if matches!(bundle_type, BundleType::FanSite) {
        let mut stmt = conn.prepare(
            "SELECT l.fan_day_id, t.name
             FROM bundle_tag_links l
             JOIN content_tags_def t ON t.id = l.tag_id
             JOIN bundle_fan_days d ON d.id = l.fan_day_id
             WHERE d.bundle_uid = ?1 AND l.fan_day_id IS NOT NULL
             ORDER BY t.sort_order, t.name COLLATE NOCASE",
        )?;
        let rows: Vec<(i64, String)> = stmt
            .query_map(params![bundle.summary.uid], |r| {
                Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?))
            })?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        for (day_id, name) in rows {
            tags_by_fan_day.entry(day_id).or_default().push(name);
        }
    }

    Ok(BundleSnapshot {
        uid: bundle.summary.uid.clone(),
        bundle_type,
        persona_code: bundle.summary.persona_code.clone(),
        title: bundle.summary.title.clone(),
        content_date: bundle.summary.content_date.clone(),
        go_live_date: bundle.summary.go_live_date.clone(),
        special_instructions: bundle.special_instructions.clone(),
        description_text: bundle.description_text.clone(),
        description_audio,
        categories: bundle.categories.iter().map(|c| c.name.clone()).collect(),
        tags: bundle_tag_names,
        delivery_kind: bundle.delivery_kind.clone(),
        delivery_site_name,
        delivery_url: bundle.delivery_url.clone(),
        delivery_recipient: bundle.delivery_recipient.clone(),
        price_cents: bundle.price_cents,
        handled_in_platform: bundle.handled_in_platform,
        fansite_year: bundle.fansite_year,
        fansite_month: bundle.fansite_month,
        fan_days: bundle
            .fan_days
            .iter()
            .map(|d| FanDay {
                day_of_month: d.day_of_month,
                message: d.message.clone(),
                tag_names: tags_by_fan_day.remove(&d.id).unwrap_or_default(),
            })
            .collect(),
        files,
        published_at,
    })
}

fn resolve_relative(support_dir: &Path, relpath: &str) -> Result<PathBuf, BundleError> {
    if relpath.starts_with('/') || relpath.contains("..") {
        return Err(BundleError::Invalid(format!("bad relpath {relpath}")));
    }
    Ok(support_dir.join(relpath))
}

// load_recent_log_lines deleted in v1.9.0 — the bundle's Molly.log no
// longer includes the personal-journal mollys_log table (the in-zip
// log is strictly a technical build log of THIS bundle's composition).
// See bundle_zip::render_molly_log for the new content layout.

/// Upsert a clip row from a published Content bundle. Caller is the
/// publish transaction; this runs inside it. Preserves any existing
/// `molly_notes_html` (Sallie's editable Molly-side notes).
fn pure_upsert_clip_from_bundle(conn: &Connection, bundle: &Bundle) -> Result<(), BundleError> {
    let categories_csv = bundle
        .categories
        .iter()
        .map(|c| c.name.as_str())
        .collect::<Vec<_>>()
        .join(", ");
    conn.execute(
        "INSERT INTO clips (id, persona_code, title, status, content_date, go_live_date,
                            categories, notes, imported_at)
         VALUES (?1, ?2, ?3, 'Bundled', ?4, ?5, ?6, ?7, datetime('now'))
         ON CONFLICT(id) DO UPDATE SET
            persona_code = excluded.persona_code,
            title        = excluded.title,
            status       = excluded.status,
            content_date = excluded.content_date,
            go_live_date = excluded.go_live_date,
            categories   = excluded.categories,
            notes        = excluded.notes",
        params![
            bundle.summary.uid,
            bundle.summary.persona_code,
            bundle.summary.title,
            bundle.summary.content_date,
            bundle.summary.go_live_date,
            categories_csv,
            bundle.special_instructions,
        ],
    )?;
    Ok(())
}

fn pure_stamp_publish(
    conn: &mut Connection,
    uid: &str,
    bundle_type: &str,
    artifact: &BundleArtifact,
    published_at: &str,
    bundle: &Bundle,
) -> Result<bool, BundleError> {
    let tx = conn.transaction()?;
    tx.execute(
        "UPDATE bundles SET
            state            = 'published',
            published_at     = ?1,
            bundle_path      = ?2,
            bundle_size_bytes = ?3,
            outer_sha256     = ?4,
            inner_sha256     = ?5,
            updated_at       = datetime('now')
         WHERE uid = ?6",
        params![
            published_at,
            artifact.path.to_string_lossy().to_string(),
            artifact.size_bytes as i64,
            artifact.outer_sha256,
            artifact.inner_sha256,
            uid,
        ],
    )?;
    let mut clip_created = false;
    if bundle_type == "content" {
        pure_upsert_clip_from_bundle(&tx, bundle)?;
        // Mirror the bundle's bundle-level content tags onto the clip
        // row. Idempotent — re-publish re-syncs. FanSite per-day tags
        // are NOT mirrored (they belong to days, not clips).
        crate::content_tags::pure_mirror_bundle_tags_to_clip(&tx, &bundle.summary.uid, &bundle.summary.uid)
            .map_err(|e| BundleError::Invalid(format!("mirror tags: {e}")))?;
        clip_created = true;
    }
    tx.commit()?;
    Ok(clip_created)
}

// ---------------------------------------------------------------------------
// Auto-purge
// ---------------------------------------------------------------------------

pub(crate) fn pure_auto_purge(
    conn: &Connection,
    settings: &BundlerSettings,
    now: DateTime<Utc>,
) -> Result<PurgeResult, BundleError> {
    let now_str = now.to_rfc3339();
    if !settings.auto_purge_enabled {
        return Ok(PurgeResult {
            considered: 0,
            purged: 0,
            skipped_missing: 0,
            last_run_at: now_str,
        });
    }
    // Two cleanup rules, UNIONed:
    //   1. The generic "this bundle has been sitting around for N days"
    //      rule (skipped when purge_threshold_days == 0).
    //   2. The per-bundle delete_after rule — set on return-file import to
    //      now()+3d. Always honored when auto_purge_enabled is on so the
    //      "kept forever" toggle (purge_threshold_days=0) still cleans up
    //      bundles Sallie explicitly closed out.
    let age_cutoff_str = if settings.purge_threshold_days > 0 {
        (now - chrono::Duration::days(settings.purge_threshold_days as i64)).to_rfc3339()
    } else {
        // Sentinel that won't match any RFC3339 timestamp.
        "0001-01-01T00:00:00Z".to_string()
    };
    let mut stmt = conn.prepare(
        "SELECT uid, bundle_path FROM bundles
         WHERE state <> 'purged'
           AND (
                (state = 'published' AND published_at IS NOT NULL AND published_at < ?1)
             OR (delete_after IS NOT NULL AND delete_after < ?2)
           )",
    )?;
    let candidates = stmt
        .query_map(params![age_cutoff_str, now_str], |r| {
            Ok((r.get::<_, String>(0)?, r.get::<_, Option<String>>(1)?))
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    let mut purged = 0u32;
    let mut skipped_missing = 0u32;
    for (uid, path) in &candidates {
        if let Some(p) = path {
            let pp = PathBuf::from(p);
            if pp.exists() {
                let _ = fs::remove_file(&pp);
            } else {
                skipped_missing += 1;
            }
        } else {
            skipped_missing += 1;
        }
        conn.execute(
            "UPDATE bundles
             SET state = 'purged', bundle_path = NULL, updated_at = datetime('now')
             WHERE uid = ?1",
            params![uid],
        )?;
        purged += 1;
    }
    Ok(PurgeResult {
        considered: candidates.len() as u32,
        purged,
        skipped_missing,
        last_run_at: now_str,
    })
}

pub async fn auto_purge_on_launch<R: Runtime>(handle: &AppHandle<R>) -> Result<(), BundleError> {
    let app_data = app_data_dir(handle)?;
    let settings = load_settings(&app_data);
    // Debounce: don't run if a successful purge happened in the past
    // 23h. (Once per day max — same spirit as backup debounce.)
    if let Some(last) = &settings.last_purge_at {
        if let Ok(last) = DateTime::parse_from_rfc3339(last).map(|d| d.with_timezone(&Utc)) {
            if Utc::now() - last < chrono::Duration::hours(PURGE_DEBOUNCE_HOURS) {
                return Ok(());
            }
        }
    }
    let conn = open_conn(&app_data)?;
    let result = pure_auto_purge(&conn, &settings, Utc::now())?;
    let mut updated = settings.clone();
    updated.last_purge_at = Some(result.last_run_at.clone());
    save_settings(&app_data, &updated)?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Tauri commands
// ---------------------------------------------------------------------------

#[tauri::command]
pub fn create_bundle<R: Runtime>(
    handle: AppHandle<R>,
    bundle_type: String,
    persona_code: Option<String>,
) -> Result<String, BundleError> {
    let app_data = app_data_dir(&handle)?;
    let conn = open_conn(&app_data)?;
    pure_create_bundle(&conn, &iso_today(), &bundle_type, persona_code.as_deref())
}

#[tauri::command]
pub fn update_bundle_fields<R: Runtime>(
    handle: AppHandle<R>,
    uid: String,
    patch: BundleFieldPatch,
) -> Result<(), BundleError> {
    let app_data = app_data_dir(&handle)?;
    let conn = open_conn(&app_data)?;
    apply_patch(&conn, &uid, &patch)
}

fn apply_patch(conn: &Connection, uid: &str, patch: &BundleFieldPatch) -> Result<(), BundleError> {
    macro_rules! upd_simple {
        ($col:literal, $val:expr) => {
            if let Some(v) = &$val {
                conn.execute(
                    concat!("UPDATE bundles SET ", $col, " = ?1, updated_at = datetime('now') WHERE uid = ?2"),
                    params![v, uid],
                )?;
            }
        };
    }
    macro_rules! upd_nullable {
        ($col:literal, $val:expr) => {
            if let Some(opt) = &$val {
                conn.execute(
                    concat!("UPDATE bundles SET ", $col, " = ?1, updated_at = datetime('now') WHERE uid = ?2"),
                    params![opt.clone(), uid],
                )?;
            }
        };
    }
    upd_simple!("title", patch.title);
    upd_nullable!("go_live_date", patch.go_live_date);
    upd_simple!("special_instructions", patch.special_instructions);
    upd_nullable!("description_mode", patch.description_mode);
    upd_simple!("description_text", patch.description_text);
    upd_nullable!("delivery_kind", patch.delivery_kind);
    upd_nullable!("delivery_site_id", patch.delivery_site_id);
    upd_nullable!("delivery_url", patch.delivery_url);
    upd_simple!("delivery_recipient", patch.delivery_recipient);
    upd_nullable!("price_cents", patch.price_cents);
    if let Some(v) = patch.handled_in_platform {
        conn.execute(
            "UPDATE bundles SET handled_in_platform = ?1, updated_at = datetime('now') WHERE uid = ?2",
            params![if v { 1 } else { 0 }, uid],
        )?;
    }
    upd_nullable!("fansite_year", patch.fansite_year);
    upd_nullable!("fansite_month", patch.fansite_month);
    Ok(())
}

#[tauri::command]
pub fn save_bundle_file<R: Runtime>(
    handle: AppHandle<R>,
    bundle_uid: String,
    src_path: String,
    kind: String,
    fansite_day_id: Option<i64>,
) -> Result<BundleFileInfo, BundleError> {
    let app_data = app_data_dir(&handle)?;
    let src = Path::new(&src_path);
    if !src.exists() || !src.is_file() {
        return Err(BundleError::Invalid(format!(
            "source file missing: {src_path}"
        )));
    }
    match kind.as_str() {
        "video" | "image" | "audio" => {}
        other => return Err(BundleError::Invalid(format!("unknown kind {other}"))),
    }
    let basename = src
        .file_name()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_else(|| "file".to_string());
    let cat = format!("bundles/{bundle_uid}/files");
    let safe_base = sanitize_component(&basename);
    let target_dir = app_data.join("attachments").join(&cat);
    fs::create_dir_all(&target_dir)?;
    let uuid = uuid::Uuid::new_v4().simple().to_string();
    let target_name = format!("{uuid}_{safe_base}");
    let target_path = target_dir.join(&target_name);
    fs::copy(src, &target_path)?;
    let size_bytes = fs::metadata(&target_path)?.len() as i64;
    let sha = bundle_zip::sha256_file(&target_path)?;
    let relpath = format!("attachments/{cat}/{target_name}");

    let conn = open_conn(&app_data)?;
    // Position = max existing for (bundle_uid, fansite_day_id) + 1.
    let max_pos: i64 = match fansite_day_id {
        Some(day_id) => conn
            .query_row(
                "SELECT COALESCE(MAX(position), 0) FROM bundle_files
                 WHERE bundle_uid = ?1 AND fansite_day_id = ?2",
                params![bundle_uid, day_id],
                |r| r.get(0),
            )
            .unwrap_or(0),
        None => conn
            .query_row(
                "SELECT COALESCE(MAX(position), 0) FROM bundle_files
                 WHERE bundle_uid = ?1 AND fansite_day_id IS NULL",
                params![bundle_uid],
                |r| r.get(0),
            )
            .unwrap_or(0),
    };
    let next_pos = max_pos + 1;
    conn.execute(
        "INSERT INTO bundle_files (bundle_uid, fansite_day_id, position, relpath,
                                   original_name, kind, size_bytes, sha256)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
        params![
            bundle_uid, fansite_day_id, next_pos, relpath, basename, kind, size_bytes, sha,
        ],
    )?;
    let id = conn.last_insert_rowid();
    conn.execute(
        "UPDATE bundles SET updated_at = datetime('now') WHERE uid = ?1",
        params![bundle_uid],
    )?;
    let absolute_path = absolute_for(&app_data, &relpath);
    Ok(BundleFileInfo {
        id,
        bundle_uid,
        fansite_day_id,
        position: next_pos,
        relpath,
        absolute_path,
        original_name: basename,
        kind,
        size_bytes,
        sha256: sha,
    })
}

#[tauri::command]
pub fn delete_bundle_file<R: Runtime>(
    handle: AppHandle<R>,
    file_id: i64,
) -> Result<(), BundleError> {
    let app_data = app_data_dir(&handle)?;
    let conn = open_conn(&app_data)?;
    let (uid, relpath, fansite_day_id): (String, String, Option<i64>) = conn
        .query_row(
            "SELECT bundle_uid, relpath, fansite_day_id FROM bundle_files WHERE id = ?1",
            params![file_id],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
        )
        .map_err(|_| BundleError::NotFound(format!("file {file_id}")))?;
    conn.execute("DELETE FROM bundle_files WHERE id = ?1", params![file_id])?;
    let abs = app_data.join(&relpath);
    if abs.exists() {
        let _ = fs::remove_file(&abs);
    }
    renumber_positions(&conn, &uid, fansite_day_id)?;
    Ok(())
}

fn renumber_positions(
    conn: &Connection,
    uid: &str,
    fansite_day_id: Option<i64>,
) -> Result<(), BundleError> {
    let ids: Vec<i64> = match fansite_day_id {
        Some(day) => conn
            .prepare(
                "SELECT id FROM bundle_files WHERE bundle_uid = ?1 AND fansite_day_id = ?2
                 ORDER BY position, id",
            )?
            .query_map(params![uid, day], |r| r.get(0))?
            .collect::<rusqlite::Result<Vec<_>>>()?,
        None => conn
            .prepare(
                "SELECT id FROM bundle_files WHERE bundle_uid = ?1 AND fansite_day_id IS NULL
                 ORDER BY position, id",
            )?
            .query_map(params![uid], |r| r.get(0))?
            .collect::<rusqlite::Result<Vec<_>>>()?,
    };
    for (i, id) in ids.iter().enumerate() {
        conn.execute(
            "UPDATE bundle_files SET position = ?1 WHERE id = ?2",
            params![(i as i64) + 1, id],
        )?;
    }
    Ok(())
}

#[tauri::command]
pub fn reorder_bundle_files<R: Runtime>(
    handle: AppHandle<R>,
    bundle_uid: String,
    ordered_ids: Vec<i64>,
) -> Result<(), BundleError> {
    let app_data = app_data_dir(&handle)?;
    let conn = open_conn(&app_data)?;
    pure_reorder_files(&conn, &bundle_uid, &ordered_ids)
}

#[tauri::command]
pub fn set_bundle_categories<R: Runtime>(
    handle: AppHandle<R>,
    bundle_uid: String,
    names_in_order: Vec<String>,
) -> Result<(), BundleError> {
    let app_data = app_data_dir(&handle)?;
    let conn = open_conn(&app_data)?;
    pure_set_categories(&conn, &bundle_uid, &names_in_order)
}

#[tauri::command]
pub fn list_bundles<R: Runtime>(
    handle: AppHandle<R>,
    state: Option<String>,
) -> Result<Vec<BundleSummary>, BundleError> {
    let app_data = app_data_dir(&handle)?;
    let settings = load_settings(&app_data);
    let conn = open_conn(&app_data)?;
    pure_list_bundles(&conn, state.as_deref(), settings.warn_threshold_days)
}

#[tauri::command]
pub fn get_bundle<R: Runtime>(
    handle: AppHandle<R>,
    uid: String,
) -> Result<Bundle, BundleError> {
    let app_data = app_data_dir(&handle)?;
    let settings = load_settings(&app_data);
    let conn = open_conn(&app_data)?;
    pure_get_bundle(&conn, &uid, settings.warn_threshold_days, &app_data)
}

#[tauri::command]
pub fn delete_bundle_draft<R: Runtime>(
    handle: AppHandle<R>,
    uid: String,
) -> Result<(), BundleError> {
    let app_data = app_data_dir(&handle)?;
    let conn = open_conn(&app_data)?;
    let relpaths = pure_delete_bundle_draft(&conn, &uid)?;
    for rel in relpaths {
        let abs = app_data.join(&rel);
        if abs.exists() {
            let _ = fs::remove_file(&abs);
        }
    }
    Ok(())
}

#[tauri::command]
pub fn publish_bundle<R: Runtime>(
    handle: AppHandle<R>,
    uid: String,
) -> Result<BundlePublishResult, BundleError> {
    let app_data = app_data_dir(&handle)?;
    let settings = load_settings(&app_data);
    let mut conn = open_conn(&app_data)?;
    let bundle = pure_get_bundle(&conn, &uid, settings.warn_threshold_days, &app_data)?;

    let prohibited = pure_list_prohibited(&conn)?;
    let today = Local::now().date_naive();
    let issues = match bundle.summary.bundle_type.as_str() {
        "content" => validate_content_bundle(&bundle, today, &prohibited),
        "custom" => validate_custom_bundle(&bundle, today),
        "fansite" => validate_fansite_bundle(&bundle),
        other => {
            return Err(BundleError::Invalid(format!(
                "Unknown bundle type `{other}`."
            )));
        }
    };
    let blocking: Vec<ValidationIssue> = issues
        .iter()
        .filter(|i| i.severity == Severity::Error)
        .cloned()
        .collect();
    if !blocking.is_empty() {
        return Err(BundleError::ValidationFailed {
            count: blocking.len(),
            issues: blocking,
        });
    }

    let published_at = iso_now();
    let snapshot = build_snapshot(&conn, &bundle, &app_data, published_at.clone())?;
    let out_dir = settings.resolved_output_dir();
    let artifact = bundle_zip::compose_bundle(&snapshot, &out_dir)?;
    let clip_created = pure_stamp_publish(
        &mut conn,
        &uid,
        &bundle.summary.bundle_type,
        &artifact,
        &published_at,
        &bundle,
    )?;

    Ok(BundlePublishResult {
        uid,
        path: artifact.path.to_string_lossy().to_string(),
        size_bytes: artifact.size_bytes,
        inner_sha256: artifact.inner_sha256,
        outer_sha256: artifact.outer_sha256,
        file_count: artifact.file_count,
        clip_created,
    })
}

#[tauri::command]
pub fn delete_published_bundle<R: Runtime>(
    handle: AppHandle<R>,
    uid: String,
) -> Result<(), BundleError> {
    let app_data = app_data_dir(&handle)?;
    let conn = open_conn(&app_data)?;
    let path: Option<String> = conn
        .query_row(
            "SELECT bundle_path FROM bundles WHERE uid = ?1",
            params![uid],
            |r| r.get(0),
        )
        .map_err(|_| BundleError::NotFound(uid.clone()))?;
    if let Some(p) = path {
        let pp = PathBuf::from(&p);
        if pp.exists() {
            let _ = fs::remove_file(&pp);
        }
    }
    conn.execute(
        "UPDATE bundles
         SET state = 'draft', bundle_path = NULL, bundle_size_bytes = NULL,
             outer_sha256 = NULL, inner_sha256 = NULL, published_at = NULL,
             updated_at = datetime('now')
         WHERE uid = ?1",
        params![uid],
    )?;
    Ok(())
}

#[tauri::command]
pub fn list_bundle_archives<R: Runtime>(
    handle: AppHandle<R>,
) -> Result<Vec<BundleArchiveRow>, BundleError> {
    let app_data = app_data_dir(&handle)?;
    let settings = load_settings(&app_data);
    let dir = settings.resolved_output_dir();
    let mut rows = Vec::new();
    let Ok(entries) = fs::read_dir(&dir) else {
        return Ok(rows);
    };
    for entry in entries.flatten() {
        let name = entry.file_name().to_string_lossy().to_string();
        if !name.ends_with(".zip") {
            continue;
        }
        let Ok(meta) = entry.metadata() else { continue };
        let modified_str = meta
            .modified()
            .ok()
            .map(|m| DateTime::<Utc>::from(m).to_rfc3339())
            .unwrap_or_default();
        // Filename is `<UID>.zip` (pre-v1.18.2) or `<UID> <title>.zip`
        // (v1.18.2+). Take everything up to the first space and validate it
        // looks like a UID; anything else is somebody else's zip.
        let stem = name.strip_suffix(".zip").unwrap_or(&name);
        let candidate = stem.split(' ').next().unwrap_or(stem);
        let uid = if is_bundle_uid(candidate) {
            Some(candidate.to_string())
        } else {
            None
        };
        rows.push(BundleArchiveRow {
            uid,
            path: entry.path().to_string_lossy().to_string(),
            filename: name,
            modified_at: modified_str,
            size_bytes: meta.len(),
        });
    }
    rows.sort_by(|a, b| b.modified_at.cmp(&a.modified_at));
    Ok(rows)
}

#[tauri::command]
pub fn reveal_bundles_dir<R: Runtime>(handle: AppHandle<R>) -> Result<(), BundleError> {
    let app_data = app_data_dir(&handle)?;
    let settings = load_settings(&app_data);
    let dir = settings.resolved_output_dir();
    fs::create_dir_all(&dir)?;
    fsutil::reveal_in_file_browser(&dir)
        .map_err(|e| BundleError::Settings(e.to_string()))?;
    Ok(())
}

#[tauri::command]
pub fn open_bundle_archive(path: String) -> Result<(), BundleError> {
    #[cfg(target_os = "macos")]
    {
        std::process::Command::new("open").arg(&path).status()?;
    }
    #[cfg(target_os = "windows")]
    {
        std::process::Command::new("cmd")
            .args(["/C", "start", "", &path])
            .status()?;
    }
    #[cfg(all(not(target_os = "macos"), not(target_os = "windows")))]
    {
        std::process::Command::new("xdg-open").arg(&path).status()?;
    }
    Ok(())
}

#[tauri::command]
pub fn auto_purge_old_bundles<R: Runtime>(handle: AppHandle<R>) -> Result<PurgeResult, BundleError> {
    let app_data = app_data_dir(&handle)?;
    let settings = load_settings(&app_data);
    let conn = open_conn(&app_data)?;
    let result = pure_auto_purge(&conn, &settings, Utc::now())?;
    let mut updated = settings.clone();
    updated.last_purge_at = Some(result.last_run_at.clone());
    save_settings(&app_data, &updated)?;
    Ok(result)
}

#[tauri::command]
pub fn get_bundler_settings<R: Runtime>(handle: AppHandle<R>) -> Result<BundlerSettings, BundleError> {
    let app_data = app_data_dir(&handle)?;
    Ok(load_settings(&app_data))
}

#[tauri::command]
pub fn set_bundler_settings<R: Runtime>(
    handle: AppHandle<R>,
    settings: BundlerSettings,
) -> Result<(), BundleError> {
    let app_data = app_data_dir(&handle)?;
    save_settings(&app_data, &settings)
}

// ---- FanSite day CRUD --------------------------------------------------

pub(crate) fn pure_create_fan_day(
    conn: &Connection,
    bundle_uid: &str,
    day_of_month: i64,
) -> Result<BundleFanDay, BundleError> {
    if !(1..=31).contains(&day_of_month) {
        return Err(BundleError::Invalid(format!(
            "day_of_month {day_of_month} not in 1..=31"
        )));
    }
    // INSERT OR IGNORE so the UI can call create-on-demand without
    // worrying about duplicates; existing rows are returned as-is.
    conn.execute(
        "INSERT OR IGNORE INTO bundle_fan_days (bundle_uid, day_of_month) VALUES (?1, ?2)",
        params![bundle_uid, day_of_month],
    )?;
    let (id, message): (i64, String) = conn.query_row(
        "SELECT id, message FROM bundle_fan_days WHERE bundle_uid = ?1 AND day_of_month = ?2",
        params![bundle_uid, day_of_month],
        |r| Ok((r.get(0)?, r.get(1)?)),
    )?;
    let file_count: i64 = conn.query_row(
        "SELECT COUNT(*) FROM bundle_files WHERE fansite_day_id = ?1",
        params![id],
        |r| r.get(0),
    )?;
    conn.execute(
        "UPDATE bundles SET updated_at = datetime('now') WHERE uid = ?1",
        params![bundle_uid],
    )?;
    Ok(BundleFanDay {
        id,
        day_of_month,
        message,
        file_count,
        tag_ids: Vec::new(),
    })
}

pub(crate) fn pure_update_fan_day_message(
    conn: &Connection,
    fan_day_id: i64,
    message: &str,
) -> Result<(), BundleError> {
    let n = conn.execute(
        "UPDATE bundle_fan_days SET message = ?1, updated_at = datetime('now') WHERE id = ?2",
        params![message, fan_day_id],
    )?;
    if n == 0 {
        return Err(BundleError::NotFound(format!("fan_day {fan_day_id}")));
    }
    // Bubble the touch up to bundles.updated_at so list-view aging
    // calc + aging-flag refresh notice the activity.
    conn.execute(
        "UPDATE bundles SET updated_at = datetime('now')
         WHERE uid = (SELECT bundle_uid FROM bundle_fan_days WHERE id = ?1)",
        params![fan_day_id],
    )?;
    Ok(())
}

pub(crate) fn pure_delete_fan_day(
    conn: &Connection,
    fan_day_id: i64,
) -> Result<Vec<String>, BundleError> {
    // ON DELETE CASCADE removes bundle_files rows, but we need the
    // relpaths back so the Tauri layer can unlink the actual files.
    let relpaths: Vec<String> = conn
        .prepare("SELECT relpath FROM bundle_files WHERE fansite_day_id = ?1")?
        .query_map(params![fan_day_id], |r| r.get(0))?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    let n = conn.execute(
        "DELETE FROM bundle_fan_days WHERE id = ?1",
        params![fan_day_id],
    )?;
    if n == 0 {
        return Err(BundleError::NotFound(format!("fan_day {fan_day_id}")));
    }
    Ok(relpaths)
}

#[tauri::command]
pub fn create_fan_day<R: Runtime>(
    handle: AppHandle<R>,
    bundle_uid: String,
    day_of_month: i64,
) -> Result<BundleFanDay, BundleError> {
    let app_data = app_data_dir(&handle)?;
    let conn = open_conn(&app_data)?;
    pure_create_fan_day(&conn, &bundle_uid, day_of_month)
}

#[tauri::command]
pub fn update_fan_day_message<R: Runtime>(
    handle: AppHandle<R>,
    fan_day_id: i64,
    message: String,
) -> Result<(), BundleError> {
    let app_data = app_data_dir(&handle)?;
    let conn = open_conn(&app_data)?;
    pure_update_fan_day_message(&conn, fan_day_id, &message)
}

#[tauri::command]
pub fn delete_fan_day<R: Runtime>(
    handle: AppHandle<R>,
    fan_day_id: i64,
) -> Result<(), BundleError> {
    let app_data = app_data_dir(&handle)?;
    let conn = open_conn(&app_data)?;
    let relpaths = pure_delete_fan_day(&conn, fan_day_id)?;
    for rel in relpaths {
        let abs = app_data.join(&rel);
        if abs.exists() {
            let _ = fs::remove_file(&abs);
        }
    }
    Ok(())
}

#[tauri::command]
pub fn list_prohibited_words<R: Runtime>(handle: AppHandle<R>) -> Result<Vec<String>, BundleError> {
    let app_data = app_data_dir(&handle)?;
    let conn = open_conn(&app_data)?;
    pure_list_prohibited(&conn)
}

#[tauri::command]
pub fn add_prohibited_word<R: Runtime>(handle: AppHandle<R>, word: String) -> Result<(), BundleError> {
    let app_data = app_data_dir(&handle)?;
    let conn = open_conn(&app_data)?;
    pure_add_prohibited(&conn, &word)
}

#[tauri::command]
pub fn remove_prohibited_word<R: Runtime>(handle: AppHandle<R>, word: String) -> Result<(), BundleError> {
    let app_data = app_data_dir(&handle)?;
    let conn = open_conn(&app_data)?;
    pure_remove_prohibited(&conn, &word)
}

fn sanitize_component(s: &str) -> String {
    s.chars()
        .map(|c| match c {
            '/' | '\\' | ':' | '\0' | '?' | '*' | '"' | '<' | '>' | '|' => '_',
            _ => c,
        })
        .collect()
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use rusqlite::Connection;

    #[test]
    fn is_bundle_uid_accepts_valid_shape() {
        assert!(is_bundle_uid("2026-05-26-0001"));
        assert!(is_bundle_uid("2026-12-31-9999"));
    }

    #[test]
    fn is_bundle_uid_rejects_other_shapes() {
        assert!(!is_bundle_uid(""));
        assert!(!is_bundle_uid("2026-05-26"));               // missing counter
        assert!(!is_bundle_uid("2026-05-26-0001-extra"));    // too long
        assert!(!is_bundle_uid("2026/05/26-0001"));          // wrong separators
        assert!(!is_bundle_uid("Somebody-Elses-Random.zip")); // not ours
        assert!(!is_bundle_uid("2026-05-26-001a"));          // non-digit counter
    }

    fn fresh_db() -> Connection {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch("PRAGMA foreign_keys = ON;").unwrap();
        for sql in [
            include_str!("../migrations/001_init.sql"),
            include_str!("../migrations/002_sites.sql"),
            include_str!("../migrations/003_taxonomy.sql"),
            include_str!("../migrations/004_customers.sql"),
            include_str!("../migrations/005_clips.sql"),
            include_str!("../migrations/006_schedules.sql"),
            include_str!("../migrations/007_income.sql"),
            include_str!("../migrations/008_expenses.sql"),
            include_str!("../migrations/009_social.sql"),
            include_str!("../migrations/010_kinks.sql"),
            include_str!("../migrations/011_kinks_preload.sql"),
            include_str!("../migrations/012_products_and_customer_fields.sql"),
            include_str!("../migrations/013_customer_history.sql"),
            include_str!("../migrations/014_customer_sales.sql"),
            include_str!("../migrations/015_mollys_log.sql"),
            include_str!("../migrations/016_c4s_clips.sql"),
            include_str!("../migrations/017_bundles.sql"),
            include_str!("../migrations/026_content_tags.sql"),
            include_str!("../migrations/027_fanday_tags.sql"),
            include_str!("../migrations/028_clip_tags.sql"),
            include_str!("../migrations/034_return_file_import.sql"),
        ] {
            conn.execute_batch(sql).unwrap();
        }
        conn
    }

    #[test]
    fn uid_counter_monotonic_per_day() {
        let conn = fresh_db();
        let u1 = pure_create_bundle(&conn, "2026-05-22", "content", Some("CoC")).unwrap();
        let u2 = pure_create_bundle(&conn, "2026-05-22", "content", Some("CoC")).unwrap();
        let u3 = pure_create_bundle(&conn, "2026-05-22", "custom", Some("PoA")).unwrap();
        assert_eq!(u1, "2026-05-22-0001");
        assert_eq!(u2, "2026-05-22-0002");
        assert_eq!(u3, "2026-05-22-0003");
        // Next day resets the counter.
        let u4 = pure_create_bundle(&conn, "2026-05-23", "content", Some("CoC")).unwrap();
        assert_eq!(u4, "2026-05-23-0001");
    }

    #[test]
    fn prohibited_words_seeded() {
        let conn = fresh_db();
        let words = pure_list_prohibited(&conn).unwrap();
        let lower: Vec<String> = words.iter().map(|w| w.to_lowercase()).collect();
        assert!(lower.contains(&"blackmail".to_string()));
        assert!(lower.contains(&"mommy".to_string()));
        assert!(lower.contains(&"addiction".to_string()));
        assert!(lower.contains(&"addicted".to_string()));
        assert_eq!(words.len(), 4);
    }

    #[test]
    fn prohibited_words_add_and_remove() {
        let conn = fresh_db();
        pure_add_prohibited(&conn, "naughty").unwrap();
        pure_add_prohibited(&conn, "NAUGHTY").unwrap(); // case-insensitive dedup via UNIQUE COLLATE NOCASE
        let words = pure_list_prohibited(&conn).unwrap();
        assert_eq!(words.iter().filter(|w| w.eq_ignore_ascii_case("naughty")).count(), 1);
        pure_remove_prohibited(&conn, "Naughty").unwrap();
        let words = pure_list_prohibited(&conn).unwrap();
        assert!(!words.iter().any(|w| w.eq_ignore_ascii_case("naughty")));
    }

    #[test]
    fn title_rules() {
        for bad in ["", "  ", "none", "Blank", "CUSTOM", "hello", "x"] {
            let mut issues = Vec::new();
            validate_title(bad, &mut issues);
            assert!(!issues.is_empty(), "expected fail for {bad:?}");
        }
        for good in ["hello world", "Sallie Saturday Special", "two words"] {
            let mut issues = Vec::new();
            validate_title(good, &mut issues);
            assert!(issues.is_empty(), "expected pass for {good:?}");
        }
    }

    #[test]
    fn go_live_rules() {
        let today = NaiveDate::from_ymd_opt(2026, 5, 22).unwrap();
        // missing → error
        let mut i = Vec::new();
        validate_go_live(None, today, &mut i);
        assert_eq!(i.len(), 1);
        assert_eq!(i[0].severity, Severity::Error);
        // past → error
        let mut i = Vec::new();
        validate_go_live(Some("2026-05-21"), today, &mut i);
        assert_eq!(i[0].severity, Severity::Error);
        // today → warn
        let mut i = Vec::new();
        validate_go_live(Some("2026-05-22"), today, &mut i);
        assert_eq!(i[0].severity, Severity::Warn);
        // +3 → warn
        let mut i = Vec::new();
        validate_go_live(Some("2026-05-25"), today, &mut i);
        assert_eq!(i[0].severity, Severity::Warn);
        // +10 → no issue
        let mut i = Vec::new();
        validate_go_live(Some("2026-06-01"), today, &mut i);
        assert!(i.is_empty());
        // malformed
        let mut i = Vec::new();
        validate_go_live(Some("nope"), today, &mut i);
        assert_eq!(i[0].severity, Severity::Error);
    }

    #[test]
    fn description_mutex_and_prohibited_words() {
        // Neither set → error.
        let mut i = Vec::new();
        validate_content_description("", None, &[], &mut i);
        assert_eq!(i.iter().filter(|x| x.severity == Severity::Error).count(), 1);
        // Both set → error.
        let mut i = Vec::new();
        validate_content_description("hi", Some("rel"), &[], &mut i);
        assert_eq!(i.iter().filter(|x| x.severity == Severity::Error).count(), 1);
        // Prohibited substring (case-insensitive, partial-word fine).
        let mut i = Vec::new();
        let words = vec!["mommy".to_string(), "addiction".to_string()];
        validate_content_description("I love my Mommy and the addictions", None, &words, &mut i);
        let messages: Vec<_> = i.iter().map(|x| x.message.clone()).collect();
        assert!(messages.iter().any(|m| m.contains("mommy")));
        assert!(messages.iter().any(|m| m.contains("addiction")));
    }

    #[test]
    fn categories_need_three() {
        let mk = |n: usize| -> Vec<BundleCategory> {
            (0..n)
                .map(|i| BundleCategory {
                    name: format!("CAT{i}"),
                    position: i as i64 + 1,
                })
                .collect()
        };
        for n in 0..3 {
            let mut i = Vec::new();
            validate_categories(&mk(n), &mut i);
            assert_eq!(i.len(), 1, "n={n} should fail");
        }
        let mut i = Vec::new();
        validate_categories(&mk(3), &mut i);
        assert!(i.is_empty());
    }

    #[test]
    fn set_categories_uppercases_dedups_and_renumbers() {
        let conn = fresh_db();
        let uid = pure_create_bundle(&conn, "2026-05-22", "content", Some("CoC")).unwrap();
        pure_set_categories(
            &conn,
            &uid,
            &["bbw".into(), "  bbw ".into(), "stuffing".into(), "".into(), "solo".into()],
        )
        .unwrap();
        let cats = load_categories_for(&conn, &uid).unwrap();
        let names: Vec<_> = cats.iter().map(|c| c.name.clone()).collect();
        assert_eq!(names, vec!["BBW".to_string(), "STUFFING".into(), "SOLO".into()]);
        let positions: Vec<_> = cats.iter().map(|c| c.position).collect();
        assert_eq!(positions, vec![1, 2, 3]);
    }

    #[test]
    fn upsert_clip_for_content_only_preserves_molly_notes() {
        let conn = fresh_db();
        // Bootstrap persona to satisfy the FK.
        conn.execute(
            "INSERT INTO personas (code, display_name) VALUES ('CoC', 'CoC')",
            [],
        )
        .ok();
        let uid = pure_create_bundle(&conn, "2026-05-22", "content", Some("CoC")).unwrap();
        // Pre-populate a clips row with molly_notes_html set, simulating
        // a manual edit Sallie made before re-publishing.
        conn.execute(
            "INSERT INTO clips (id, molly_notes_html, title) VALUES (?1, 'preserve me', '')",
            params![uid],
        )
        .unwrap();
        let bundle = pure_get_bundle(&conn, &uid, 30, Path::new("")).unwrap();
        pure_upsert_clip_from_bundle(&conn, &bundle).unwrap();
        // molly_notes_html must survive.
        let notes: String = conn
            .query_row(
                "SELECT molly_notes_html FROM clips WHERE id = ?1",
                params![uid],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(notes, "preserve me");
        let status: String = conn
            .query_row(
                "SELECT status FROM clips WHERE id = ?1",
                params![uid],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(status, "Bundled");
    }

    #[test]
    fn auto_purge_respects_threshold_zero_and_disabled() {
        let conn = fresh_db();
        let uid = pure_create_bundle(&conn, "2026-05-22", "content", None).unwrap();
        conn.execute(
            "UPDATE bundles SET state='published', published_at='1990-01-01T00:00:00Z' WHERE uid = ?1",
            params![uid],
        )
        .unwrap();
        // Threshold 0 → no purge.
        let mut s = BundlerSettings::default();
        s.purge_threshold_days = 0;
        let r = pure_auto_purge(&conn, &s, Utc::now()).unwrap();
        assert_eq!(r.purged, 0);
        // Disabled → no purge.
        let mut s = BundlerSettings::default();
        s.auto_purge_enabled = false;
        let r = pure_auto_purge(&conn, &s, Utc::now()).unwrap();
        assert_eq!(r.purged, 0);
    }

    #[test]
    fn auto_purge_only_touches_published_state() {
        let conn = fresh_db();
        // Two bundles: one published-old, one draft (also "old" but
        // shouldn't be touched because state='draft').
        let pub_uid = pure_create_bundle(&conn, "2026-05-22", "content", None).unwrap();
        let draft_uid = pure_create_bundle(&conn, "2026-05-22", "custom", None).unwrap();
        conn.execute(
            "UPDATE bundles SET state='published', published_at='1990-01-01T00:00:00Z' WHERE uid = ?1",
            params![pub_uid],
        )
        .unwrap();
        let r = pure_auto_purge(&conn, &BundlerSettings::default(), Utc::now()).unwrap();
        assert_eq!(r.purged, 1);
        let state_after: String = conn
            .query_row("SELECT state FROM bundles WHERE uid = ?1", params![pub_uid], |r| r.get(0))
            .unwrap();
        assert_eq!(state_after, "purged");
        let draft_state: String = conn
            .query_row("SELECT state FROM bundles WHERE uid = ?1", params![draft_uid], |r| r.get(0))
            .unwrap();
        assert_eq!(draft_state, "draft");
    }

    #[test]
    fn delete_bundle_draft_returns_relpaths() {
        let conn = fresh_db();
        let uid = pure_create_bundle(&conn, "2026-05-22", "content", None).unwrap();
        conn.execute(
            "INSERT INTO bundle_files (bundle_uid, position, relpath, original_name, kind, size_bytes, sha256)
             VALUES (?1, 1, 'attachments/bundles/x/files/a.jpg', 'a.jpg', 'image', 100, 'abc')",
            params![uid],
        )
        .unwrap();
        conn.execute(
            "UPDATE bundles SET description_audio_relpath='attachments/bundles/x/files/b.mp3' WHERE uid = ?1",
            params![uid],
        )
        .unwrap();
        let rels = pure_delete_bundle_draft(&conn, &uid).unwrap();
        assert_eq!(rels.len(), 2);
        // Bundle row should be gone (cascades deleted file rows).
        let n: i64 = conn
            .query_row("SELECT COUNT(*) FROM bundles WHERE uid = ?1", params![uid], |r| r.get(0))
            .unwrap();
        assert_eq!(n, 0);
        let n: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM bundle_files WHERE bundle_uid = ?1",
                params![uid],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(n, 0);
    }

    #[test]
    fn aging_flag_buckets() {
        // 0 threshold → always fresh.
        assert_eq!(aging_flag("2020-01-01T00:00:00Z", 0), "fresh");
        // Date in the very recent past → fresh.
        let recent = (Utc::now() - chrono::Duration::days(1)).to_rfc3339();
        assert_eq!(aging_flag(&recent, 30), "fresh");
        // Just past threshold → aging.
        let mid = (Utc::now() - chrono::Duration::days(35)).to_rfc3339();
        assert_eq!(aging_flag(&mid, 30), "aging");
        // 2× threshold → overdue.
        let old = (Utc::now() - chrono::Duration::days(70)).to_rfc3339();
        assert_eq!(aging_flag(&old, 30), "overdue");
    }

    // ---- PR2: Custom + FanSite validators + fan_day CRUD ---------------

    fn mk_bundle(uid: &str, bundle_type: &str) -> Bundle {
        Bundle {
            summary: BundleSummary {
                uid: uid.into(),
                bundle_type: bundle_type.into(),
                persona_code: Some("CoC".into()),
                state: "draft".into(),
                title: "Hello World Bundle".into(),
                content_date: "2026-05-22".into(),
                go_live_date: Some("2026-06-15".into()),
                published_at: None,
                bundle_path: None,
                bundle_size_bytes: None,
                created_at: "2026-05-22T00:00:00Z".into(),
                updated_at: "2026-05-22T00:00:00Z".into(),
                aging_flag: "fresh".into(),
                file_count: 0,
                tag_ids: vec![],
                completed_at: None,
                delete_after: None,
            },
            special_instructions: String::new(),
            description_mode: None,
            description_text: String::new(),
            description_audio_relpath: None,
            description_audio_absolute_path: None,
            description_audio_original_name: None,
            delivery_kind: None,
            delivery_site_id: None,
            delivery_url: None,
            delivery_recipient: String::new(),
            price_cents: None,
            handled_in_platform: false,
            fansite_year: None,
            fansite_month: None,
            outer_sha256: None,
            inner_sha256: None,
            files: vec![],
            categories: vec![],
            fan_days: vec![],
        }
    }

    fn mk_video_file() -> BundleFileInfo {
        BundleFileInfo {
            id: 1,
            bundle_uid: "x".into(),
            fansite_day_id: None,
            position: 1,
            relpath: "r".into(),
            absolute_path: "r".into(),
            original_name: "v.mp4".into(),
            kind: "video".into(),
            size_bytes: 1,
            sha256: String::new(),
        }
    }

    #[test]
    fn days_in_month_handles_28_29_30_31() {
        assert_eq!(days_in_month(2026, 1), 31);
        assert_eq!(days_in_month(2026, 2), 28); // not a leap year
        assert_eq!(days_in_month(2024, 2), 29); // leap
        assert_eq!(days_in_month(2026, 4), 30);
        assert_eq!(days_in_month(2026, 12), 31);
        assert_eq!(days_in_month(2026, 0), 0); // invalid
        assert_eq!(days_in_month(2026, 13), 0); // invalid
    }

    #[test]
    fn custom_delivery_requires_kind() {
        let mut b = mk_bundle("x", "custom");
        b.files.push(mk_video_file());
        b.delivery_recipient = "alice".into();
        b.handled_in_platform = true; // skip price requirement

        // delivery_kind unset → error.
        let mut i = Vec::new();
        validate_custom_delivery(&b, &mut i);
        assert!(i.iter().any(|x| x.field_path == "delivery"));

        // 'site' kind without site_id → error.
        let mut b2 = b.clone();
        b2.delivery_kind = Some("site".into());
        let mut i2 = Vec::new();
        validate_custom_delivery(&b2, &mut i2);
        assert!(i2.iter().any(|x| x.field_path == "delivery"));

        // 'site' kind with site_id → no delivery error.
        let mut b3 = b.clone();
        b3.delivery_kind = Some("site".into());
        b3.delivery_site_id = Some(1);
        let mut i3 = Vec::new();
        validate_custom_delivery(&b3, &mut i3);
        assert!(!i3.iter().any(|x| x.field_path == "delivery"));
    }

    #[test]
    fn custom_url_kind_needs_no_url_string() {
        // 1.20.1: URL link is just a delivery method choice; Robert fills
        // in the URL via the SideMolly return-file flow once delivered.
        let mut b = mk_bundle("x", "custom");
        b.files.push(mk_video_file());
        b.delivery_recipient = "alice".into();
        b.handled_in_platform = true;
        b.delivery_kind = Some("url".into());
        // delivery_url stays None.

        let mut i = Vec::new();
        validate_custom_delivery(&b, &mut i);
        assert!(
            i.is_empty(),
            "expected no issues for URL-kind without URL, got: {:?}",
            i
        );
    }

    #[test]
    fn custom_price_required_unless_handled_in_platform() {
        let mut b = mk_bundle("x", "custom");
        b.delivery_recipient = "alice".into();
        b.delivery_site_id = Some(1);
        b.delivery_kind = Some("site".into());

        // handled_in_platform=false + price=None → error
        let mut i = Vec::new();
        validate_custom_delivery(&b, &mut i);
        assert!(i.iter().any(|x| x.field_path == "price"));

        // handled_in_platform=true → price not required
        b.handled_in_platform = true;
        let mut i2 = Vec::new();
        validate_custom_delivery(&b, &mut i2);
        assert!(!i2.iter().any(|x| x.field_path == "price"));

        // handled_in_platform=false + negative price → error
        b.handled_in_platform = false;
        b.price_cents = Some(-100);
        let mut i3 = Vec::new();
        validate_custom_delivery(&b, &mut i3);
        assert!(i3.iter().any(|x| x.field_path == "price"));

        // valid price → no price error
        b.price_cents = Some(2500);
        let mut i4 = Vec::new();
        validate_custom_delivery(&b, &mut i4);
        assert!(!i4.iter().any(|x| x.field_path == "price"));
    }

    #[test]
    fn fansite_completion_lists_missing_days() {
        let mut b = mk_bundle("x", "fansite");
        b.fansite_year = Some(2026);
        b.fansite_month = Some(2); // 28 days
        // Fill 25 days; expect 3 missing.
        for day in 1..=25 {
            b.fan_days.push(BundleFanDay {
                id: day,
                day_of_month: day,
                message: "post".into(),
                file_count: 1,
                tag_ids: vec![],
            });
        }
        let mut issues = Vec::new();
        validate_fansite_completion(&b, &mut issues);
        let missing: Vec<&ValidationIssue> = issues
            .iter()
            .filter(|i| i.field_path.starts_with("fanDay."))
            .collect();
        assert_eq!(missing.len(), 3, "expected days 26-28 missing");
        assert!(missing.iter().all(|i| i.severity == Severity::Error));
    }

    #[test]
    fn fansite_completion_differentiates_missing_message_vs_file() {
        let mut b = mk_bundle("x", "fansite");
        b.fansite_year = Some(2026);
        b.fansite_month = Some(1); // 31 days
        // Day 5: has file but no message
        b.fan_days.push(BundleFanDay { id: 5, day_of_month: 5, message: "".into(), file_count: 1, tag_ids: vec![] });
        // Day 6: has message but no file
        b.fan_days.push(BundleFanDay { id: 6, day_of_month: 6, message: "post".into(), file_count: 0, tag_ids: vec![] });
        // Fill the rest so we can target our assertions
        for day in (1..=31).filter(|d| *d != 5 && *d != 6) {
            b.fan_days.push(BundleFanDay { id: day + 100, day_of_month: day, message: "p".into(), file_count: 1, tag_ids: vec![] });
        }
        let mut issues = Vec::new();
        validate_fansite_completion(&b, &mut issues);
        let d5 = issues.iter().find(|i| i.field_path == "fanDay.05").unwrap();
        let d6 = issues.iter().find(|i| i.field_path == "fanDay.06").unwrap();
        assert!(d5.message.contains("message"));
        assert!(d6.message.contains("file"));
    }

    #[test]
    fn fansite_completion_needs_year_month_first() {
        let b = mk_bundle("x", "fansite");
        // fansite_year + fansite_month are None
        let mut issues = Vec::new();
        validate_fansite_completion(&b, &mut issues);
        assert!(issues.iter().any(|i| i.field_path == "fansiteMonth"));
    }

    #[test]
    fn fan_day_crud_round_trip() {
        let conn = fresh_db();
        let uid = pure_create_bundle(&conn, "2026-05-22", "fansite", Some("CoC")).unwrap();

        let day1 = pure_create_fan_day(&conn, &uid, 5).unwrap();
        assert_eq!(day1.day_of_month, 5);
        assert_eq!(day1.message, "");
        assert_eq!(day1.file_count, 0);

        // Idempotent — second call returns the same row, not a duplicate.
        let day1_again = pure_create_fan_day(&conn, &uid, 5).unwrap();
        assert_eq!(day1_again.id, day1.id);

        // Update message.
        pure_update_fan_day_message(&conn, day1.id, "hello there").unwrap();
        let after = load_fan_days_for(&conn, &uid).unwrap();
        assert_eq!(after[0].message, "hello there");

        // Reject out-of-range day.
        assert!(pure_create_fan_day(&conn, &uid, 0).is_err());
        assert!(pure_create_fan_day(&conn, &uid, 32).is_err());

        // Delete returns relpaths (empty here since no files attached).
        let relpaths = pure_delete_fan_day(&conn, day1.id).unwrap();
        assert!(relpaths.is_empty());
        assert!(load_fan_days_for(&conn, &uid).unwrap().is_empty());

        // Deleting non-existent fan_day → NotFound.
        assert!(matches!(
            pure_delete_fan_day(&conn, 9999),
            Err(BundleError::NotFound(_))
        ));
    }

    #[test]
    fn fan_day_delete_cascades_files_and_returns_relpaths() {
        let conn = fresh_db();
        let uid = pure_create_bundle(&conn, "2026-05-22", "fansite", Some("Sa")).unwrap();
        let day = pure_create_fan_day(&conn, &uid, 1).unwrap();
        conn.execute(
            "INSERT INTO bundle_files (bundle_uid, fansite_day_id, position, relpath, original_name, kind, size_bytes, sha256)
             VALUES (?1, ?2, 1, 'attachments/bundles/x/files/img.jpg', 'img.jpg', 'image', 100, 'abc')",
            params![uid, day.id],
        ).unwrap();
        let rels = pure_delete_fan_day(&conn, day.id).unwrap();
        assert_eq!(rels.len(), 1);
        assert_eq!(rels[0], "attachments/bundles/x/files/img.jpg");
        // Cascade deleted the file row.
        let count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM bundle_files WHERE bundle_uid = ?1",
                params![uid],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(count, 0);
    }
}

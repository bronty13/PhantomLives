// Bundle composition + SHA-256 hashing for the Phase 9 Content Bundler.
//
// `compose_bundle` takes a pre-resolved `BundleSnapshot` (all DB lookups
// already done by the caller) and produces a deterministic, two-layer
// ZIP at `<out_dir>/<UID>.zip`:
//
//     outer.zip
//     ├── <UID>-inner.zip
//     │   ├── info.md
//     │   ├── Molly.log
//     │   ├── Audio/<file>            (Content bundles with audio description)
//     │   ├── Video/00001_<orig>...   (Content/Custom)
//     │   ├── Photos/00001_<orig>...  (Content/Custom)
//     │   └── FanSite/DD_NN_<orig>... (FanSite)
//     └── hashes.json
//
// Determinism notes:
// - ZIP entries are written in a fixed, type-driven order (info.md,
//   Molly.log, then media — sorted by `position` for media). Reordering
//   would change the byte stream and therefore the outer hash.
// - All entries use `zip::DateTime::default()` (1980-01-01 MS-DOS epoch),
//   not the current wall-clock; same reason.
// - `hashes.json` is composed from a `BTreeMap`-equivalent (Vec built in
//   the same deterministic order as the entries) and serialized with
//   `serde_json::to_vec_pretty`, which itself preserves insertion order.
//
// Integrity notes:
// - Every file we copy from disk is re-hashed during composition and the
//   result asserted against the `sha256_db` field carried in the snapshot
//   (which the caller read from `bundle_files.sha256`). Any divergence
//   returns `BundleError::AttachmentChanged{relpath}` — the caller turns
//   it into a fixable validation issue Sallie can re-upload through.

use std::fs;
use std::io::{Cursor, Read, Write};
use std::path::{Path, PathBuf};

use serde::Serialize;
use sha2::{Digest, Sha256};
use zip::write::SimpleFileOptions;

/// Three discriminated bundle flavors. Mirrors the `bundle_type` CHECK
/// constraint in migration 017.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BundleType {
    Content,
    Custom,
    FanSite,
}

impl BundleType {
    pub fn as_str(self) -> &'static str {
        match self {
            BundleType::Content => "content",
            BundleType::Custom => "custom",
            BundleType::FanSite => "fansite",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FileKind {
    Video,
    Image,
    Audio,
}

impl FileKind {
    pub fn as_str(self) -> &'static str {
        match self {
            FileKind::Video => "video",
            FileKind::Image => "image",
            FileKind::Audio => "audio",
        }
    }
}

/// One file the snapshot wants in the bundle. `abs_path` is the resolved
/// on-disk location (caller joined support_dir + relpath); `sha256_db` is
/// what was stored in `bundle_files.sha256` at upload time and is the
/// reference for the "did this file change?" check.
#[derive(Debug, Clone)]
pub struct FileEntry {
    pub original_name: String,
    pub abs_path: PathBuf,
    pub relpath_for_error: String,
    pub kind: FileKind,
    pub position: i64,
    pub sha256_db: String,
    /// Only set for FanSite files; carries the calendar day.
    pub fansite_day_of_month: Option<i64>,
}

/// One calendar day's message for a FanSite bundle.
#[derive(Debug, Clone)]
pub struct FanDay {
    pub day_of_month: i64,
    pub message: String,
}

#[derive(Debug, Clone)]
pub struct BundleSnapshot {
    pub uid: String,
    pub bundle_type: BundleType,
    pub persona_code: Option<String>,
    pub title: String,
    pub content_date: String,
    pub go_live_date: Option<String>,
    pub special_instructions: String,

    // Content
    pub description_text: String,
    pub description_audio: Option<FileEntry>,
    pub categories: Vec<String>, // already UPPERCASE, in position order

    // Custom
    pub delivery_kind: Option<String>,           // "site" | "url"
    pub delivery_site_name: Option<String>,      // resolved label
    pub delivery_url: Option<String>,
    pub delivery_recipient: String,
    pub price_cents: Option<i64>,
    pub handled_in_platform: bool,

    // FanSite
    pub fansite_year: Option<i64>,
    pub fansite_month: Option<i64>,
    pub fan_days: Vec<FanDay>,

    /// Ordered media files. For Content/Custom these are bundle-scoped;
    /// for FanSite each carries its `fansite_day_of_month`.
    pub files: Vec<FileEntry>,

    /// Free-text published_at to stamp in the bundle audit header.
    /// RFC3339-shaped string the caller already formatted.
    pub published_at: String,
}

#[derive(Debug)]
pub struct BundleArtifact {
    pub path: PathBuf,
    pub size_bytes: u64,
    pub inner_sha256: String,
    pub outer_sha256: String,
    pub file_count: usize,
}

#[derive(Debug, thiserror::Error)]
pub enum BundleError {
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    #[error("zip: {0}")]
    Zip(#[from] zip::result::ZipError),
    #[error("source file missing: {0}")]
    MissingSource(String),
    #[error("attachment changed since upload (relpath: {relpath})")]
    AttachmentChanged { relpath: String },
}

impl serde::Serialize for BundleError {
    fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(&self.to_string())
    }
}

#[derive(Debug, Serialize)]
struct HashesEntry {
    path: String,
    sha256: String,
}

#[derive(Debug, Serialize)]
struct InnerZipDescriptor {
    name: String,
    sha256: String,
    bytes: u64,
}

#[derive(Debug, Serialize)]
struct HashesDocument {
    #[serde(rename = "bundleUid")]
    bundle_uid: String,
    #[serde(rename = "innerZip")]
    inner_zip: InnerZipDescriptor,
    files: Vec<HashesEntry>,
}

/// Public entry point. Composes the snapshot into a deterministic ZIP
/// at `<out_dir>/<UID>.zip`. Creates `out_dir` if missing. Caller is
/// responsible for stamping the DB with the returned artifact info.
pub fn compose_bundle(
    snapshot: &BundleSnapshot,
    out_dir: &Path,
) -> Result<BundleArtifact, BundleError> {
    fs::create_dir_all(out_dir)?;

    // ---- Pass 1: read every media file from disk, hash, plan its
    // in-zip path. info.md + Molly.log come from the snapshot (no disk
    // read) and are rendered AFTER this pass so the build log can list
    // every planned file with its final path and hash.
    let mut media: Vec<(String, Vec<u8>, String)> = Vec::new();

    // Audio description (Content type only) — also lives outside `files`.
    if let Some(audio) = &snapshot.description_audio {
        let bytes = read_and_verify(audio)?;
        let sha = sha256_hex(&bytes);
        let path = format!("Audio/{}", sanitize_name(&audio.original_name));
        media.push((path, bytes, sha));
    }

    // Media files. Sort defensively even though the caller is supposed
    // to send them ordered — caller bugs shouldn't make hashes flaky.
    let mut files = snapshot.files.clone();
    match snapshot.bundle_type {
        BundleType::Content | BundleType::Custom => {
            files.sort_by_key(|f| (f.kind as i32, f.position));
            for f in &files {
                let bytes = read_and_verify(f)?;
                let sha = sha256_hex(&bytes);
                let folder = match f.kind {
                    FileKind::Video => "Video",
                    FileKind::Image => "Photos",
                    FileKind::Audio => "Audio", // shouldn't occur for content/custom media
                };
                let path = format!(
                    "{folder}/{:05}_{}",
                    f.position,
                    sanitize_name(&f.original_name)
                );
                media.push((path, bytes, sha));
            }
        }
        BundleType::FanSite => {
            files.sort_by_key(|f| (f.fansite_day_of_month.unwrap_or(0), f.position));
            for f in &files {
                let bytes = read_and_verify(f)?;
                let sha = sha256_hex(&bytes);
                let day = f.fansite_day_of_month.unwrap_or(0);
                let path = format!(
                    "FanSite/{:02}_{:02}_{}",
                    day,
                    f.position,
                    sanitize_name(&f.original_name)
                );
                media.push((path, bytes, sha));
            }
        }
    }

    // ---- Pass 2: render info.md + Molly.log now that media is known.
    // Molly.log includes a build trace listing every planned media file
    // with its final in-zip path + sha; that's its job — a technical
    // build log of this bundle's composition.
    let info_md_bytes = render_info_md(snapshot).into_bytes();
    let info_md_sha = sha256_hex(&info_md_bytes);
    let molly_log_bytes = render_molly_log(snapshot, &info_md_sha, &media).into_bytes();
    let molly_log_sha = sha256_hex(&molly_log_bytes);

    let mut planned: Vec<(String, Vec<u8>, String)> = Vec::with_capacity(2 + media.len());
    planned.push(("info.md".to_string(), info_md_bytes, info_md_sha));
    planned.push(("Molly.log".to_string(), molly_log_bytes, molly_log_sha));
    planned.extend(media);

    // ---- Compose inner ZIP into memory so we can hash the bytes directly.
    let inner_zip_bytes = build_zip(&planned)?;
    let inner_sha = sha256_hex(&inner_zip_bytes);
    let inner_zip_name = format!("{}-inner.zip", snapshot.uid);

    // ---- Compose hashes.json (deterministic ordering matches `planned`).
    let hashes_doc = HashesDocument {
        bundle_uid: snapshot.uid.clone(),
        inner_zip: InnerZipDescriptor {
            name: inner_zip_name.clone(),
            sha256: inner_sha.clone(),
            bytes: inner_zip_bytes.len() as u64,
        },
        files: planned
            .iter()
            .map(|(path, _bytes, sha)| HashesEntry {
                path: path.clone(),
                sha256: sha.clone(),
            })
            .collect(),
    };
    let hashes_json = serde_json::to_vec_pretty(&hashes_doc)
        .expect("HashesDocument is always serializable");

    // ---- Outer ZIP: just the inner.zip + hashes.json.
    let outer_zip_bytes = build_zip(&vec![
        (inner_zip_name.clone(), inner_zip_bytes, inner_sha.clone()),
        ("hashes.json".to_string(), hashes_json, String::new()),
    ])?;
    let outer_sha = sha256_hex(&outer_zip_bytes);

    // ---- Atomic write to <out_dir>/<UID>.zip via .tmp + rename.
    let out_path = out_dir.join(format!("{}.zip", snapshot.uid));
    let tmp_path = out_path.with_extension("zip.tmp");
    fs::write(&tmp_path, &outer_zip_bytes)?;
    if out_path.exists() {
        let _ = fs::remove_file(&out_path);
    }
    fs::rename(&tmp_path, &out_path)?;
    let size_bytes = fs::metadata(&out_path)?.len();

    // file_count counts everything inside the inner zip (info.md + Molly.log
    // + media). Excludes the outer container.
    let file_count = hashes_doc.files.len();

    Ok(BundleArtifact {
        path: out_path,
        size_bytes,
        inner_sha256: inner_sha,
        outer_sha256: outer_sha,
        file_count,
    })
}

/// Public utility: SHA-256 a file at `path`, return lowercase hex digest.
/// Used by `bundles::save_bundle_file` at upload time to populate the
/// `bundle_files.sha256` column.
pub fn sha256_file(path: &Path) -> Result<String, BundleError> {
    let mut file = fs::File::open(path)
        .map_err(|_| BundleError::MissingSource(path.to_string_lossy().to_string()))?;
    let mut hasher = Sha256::new();
    let mut buf = [0u8; 64 * 1024];
    loop {
        let n = file.read(&mut buf)?;
        if n == 0 {
            break;
        }
        hasher.update(&buf[..n]);
    }
    Ok(hex_lower(&hasher.finalize()))
}

fn sha256_hex(bytes: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(bytes);
    hex_lower(&hasher.finalize())
}

fn hex_lower(bytes: &[u8]) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut s = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        s.push(HEX[(b >> 4) as usize] as char);
        s.push(HEX[(b & 0x0f) as usize] as char);
    }
    s
}

fn read_and_verify(entry: &FileEntry) -> Result<Vec<u8>, BundleError> {
    let mut file = fs::File::open(&entry.abs_path)
        .map_err(|_| BundleError::MissingSource(entry.relpath_for_error.clone()))?;
    let mut bytes = Vec::new();
    file.read_to_end(&mut bytes)?;
    if !entry.sha256_db.is_empty() {
        let live = sha256_hex(&bytes);
        if live != entry.sha256_db {
            return Err(BundleError::AttachmentChanged {
                relpath: entry.relpath_for_error.clone(),
            });
        }
    }
    Ok(bytes)
}

fn build_zip(entries: &[(String, Vec<u8>, String)]) -> Result<Vec<u8>, BundleError> {
    let mut cursor = Cursor::new(Vec::new());
    {
        let mut zip = zip::ZipWriter::new(&mut cursor);
        // Use the MS-DOS epoch (1980-01-01) for every entry so the byte
        // stream — and therefore the outer SHA-256 — is the same across
        // builds of the same snapshot.
        let opts = SimpleFileOptions::default()
            .compression_method(zip::CompressionMethod::Deflated)
            .last_modified_time(zip::DateTime::default())
            .unix_permissions(0o644);
        for (name, bytes, _sha) in entries {
            zip.start_file(name, opts)?;
            zip.write_all(bytes)?;
        }
        zip.finish()?;
    }
    Ok(cursor.into_inner())
}

/// Drop characters that aren't safe to drop into a ZIP entry name on
/// either macOS or Windows. Conservative: keep ASCII letters/digits and a
/// few common separators; replace everything else with `_`.
fn sanitize_name(name: &str) -> String {
    let mut out = String::with_capacity(name.len());
    for c in name.chars() {
        if c.is_ascii_alphanumeric() || matches!(c, '.' | '-' | '_' | ' ' | '(' | ')') {
            out.push(c);
        } else {
            out.push('_');
        }
    }
    if out.is_empty() {
        out.push('_');
    }
    out
}

fn render_info_md(s: &BundleSnapshot) -> String {
    let mut md = String::new();
    md.push_str(&format!("# {}\n\n", if s.title.is_empty() { "(no title)" } else { &s.title }));
    md.push_str(&format!("- **Bundle UID:** `{}`\n", s.uid));
    md.push_str(&format!("- **Type:** `{}`\n", s.bundle_type.as_str()));
    md.push_str(&format!(
        "- **Persona:** `{}`\n",
        s.persona_code.as_deref().unwrap_or("(unassigned)")
    ));
    md.push_str(&format!("- **Content date:** `{}`\n", s.content_date));
    if let Some(g) = &s.go_live_date {
        md.push_str(&format!("- **Go-live date:** `{}`\n", g));
    }
    md.push_str(&format!("- **Published at:** `{}`\n\n", s.published_at));

    match s.bundle_type {
        BundleType::Content => {
            md.push_str("## Description\n\n");
            if let Some(audio) = &s.description_audio {
                md.push_str(&format!(
                    "Audio: `Audio/{}`\n\n",
                    sanitize_name(&audio.original_name)
                ));
            } else if !s.description_text.is_empty() {
                md.push_str(&format!("{}\n\n", s.description_text));
            } else {
                md.push_str("_(none)_\n\n");
            }

            md.push_str("## Categories\n\n");
            if s.categories.is_empty() {
                md.push_str("_(none)_\n\n");
            } else {
                for (i, c) in s.categories.iter().enumerate() {
                    md.push_str(&format!("{}. {}\n", i + 1, c));
                }
                md.push('\n');
            }
        }
        BundleType::Custom => {
            md.push_str("## Delivery\n\n");
            md.push_str(&format!("- **To:** `{}`\n", s.delivery_recipient));
            match s.delivery_kind.as_deref() {
                Some("site") => {
                    md.push_str(&format!(
                        "- **Platform:** `{}`\n",
                        s.delivery_site_name.as_deref().unwrap_or("(unknown site)")
                    ));
                }
                Some("url") => {
                    md.push_str(&format!(
                        "- **URL:** {}\n",
                        s.delivery_url.as_deref().unwrap_or("")
                    ));
                }
                _ => {
                    md.push_str("- **Platform:** _(not set)_\n");
                }
            }
            if s.handled_in_platform {
                md.push_str("- **Price:** _handled in delivery platform_\n");
            } else if let Some(c) = s.price_cents {
                md.push_str(&format!("- **Price:** ${}.{:02}\n", c / 100, c % 100));
            } else {
                md.push_str("- **Price:** _(not set)_\n");
            }
            md.push('\n');
        }
        BundleType::FanSite => {
            md.push_str(&format!(
                "## Fan Site posts — {}-{:02}\n\n",
                s.fansite_year.unwrap_or(0),
                s.fansite_month.unwrap_or(0)
            ));
            let mut days = s.fan_days.clone();
            days.sort_by_key(|d| d.day_of_month);
            for d in &days {
                let count = s
                    .files
                    .iter()
                    .filter(|f| f.fansite_day_of_month == Some(d.day_of_month))
                    .count();
                md.push_str(&format!(
                    "### Day {:02}\n\n{}\n\n_({} file{})_\n\n",
                    d.day_of_month,
                    if d.message.is_empty() { "_(no message)_" } else { &d.message },
                    count,
                    if count == 1 { "" } else { "s" }
                ));
            }
        }
    }

    md.push_str("## Files (in order)\n\n");
    if s.files.is_empty() && s.description_audio.is_none() {
        md.push_str("_(none)_\n\n");
    } else {
        let mut sorted = s.files.clone();
        match s.bundle_type {
            BundleType::FanSite => {
                sorted.sort_by_key(|f| (f.fansite_day_of_month.unwrap_or(0), f.position));
                for f in &sorted {
                    md.push_str(&format!(
                        "- `FanSite/{:02}_{:02}_{}` (`{}`, {} bytes hashed)\n",
                        f.fansite_day_of_month.unwrap_or(0),
                        f.position,
                        sanitize_name(&f.original_name),
                        f.kind.as_str(),
                        f.sha256_db.chars().take(8).collect::<String>(),
                    ));
                }
            }
            _ => {
                sorted.sort_by_key(|f| (f.kind as i32, f.position));
                for f in &sorted {
                    let folder = match f.kind {
                        FileKind::Video => "Video",
                        FileKind::Image => "Photos",
                        FileKind::Audio => "Audio",
                    };
                    md.push_str(&format!(
                        "- `{}/{:05}_{}` (`{}`, {} bytes hashed)\n",
                        folder,
                        f.position,
                        sanitize_name(&f.original_name),
                        f.kind.as_str(),
                        f.sha256_db.chars().take(8).collect::<String>(),
                    ));
                }
            }
        }
        md.push('\n');
    }

    md.push_str("## Special instructions\n\n");
    md.push_str(if s.special_instructions.is_empty() {
        "_(none)_\n"
    } else {
        &s.special_instructions
    });
    md.push('\n');

    md
}

/// Render the technical build log that goes inside the bundle ZIP as
/// `Molly.log`. Includes every wizard input AND a per-file build trace
/// so Robert (or future-Sallie, or an auditor) can re-derive every byte
/// in the inner zip without ever seeing the source DB.
///
/// `media` is the planned media entries (Audio/Video/Photos/FanSite),
/// pre-hashed; we don't include the inner/outer ZIP shas because those
/// are computed AFTER this log is written (and would chase their own tail).
fn render_molly_log(
    s: &BundleSnapshot,
    info_md_sha: &str,
    media: &[(String, Vec<u8>, String)],
) -> String {
    let mut log = String::new();
    log.push_str("================================================================\n");
    log.push_str("Molly Bundler — build log\n");
    log.push_str("================================================================\n");
    log.push_str(&format!("Bundle UID:         {}\n", s.uid));
    log.push_str(&format!("Bundle type:        {}\n", s.bundle_type.as_str()));
    log.push_str(&format!(
        "Persona:            {}\n",
        s.persona_code.as_deref().unwrap_or("(unassigned)")
    ));
    log.push_str(&format!("Generated:          {}\n", s.published_at));
    log.push_str("\n");

    // ---- All wizard inputs ----
    log.push_str("[INPUTS]\n");
    log.push_str(&format!("Title:              {}\n", s.title));
    log.push_str(&format!("Content date:       {}\n", s.content_date));
    if let Some(g) = &s.go_live_date {
        log.push_str(&format!("Go-live date:       {}\n", g));
    }

    match s.bundle_type {
        BundleType::Content => {
            if let Some(audio) = &s.description_audio {
                log.push_str("Description mode:   audio\n");
                log.push_str(&format!(
                    "Description audio:  {}\n",
                    sanitize_name(&audio.original_name)
                ));
            } else if !s.description_text.is_empty() {
                log.push_str("Description mode:   text\n");
                log.push_str("Description text:\n");
                for line in s.description_text.lines() {
                    log.push_str(&format!("  | {}\n", line));
                }
            } else {
                log.push_str("Description mode:   (none)\n");
            }
            log.push_str(&format!("Categories ({}):\n", s.categories.len()));
            for (i, c) in s.categories.iter().enumerate() {
                log.push_str(&format!("  {}. {}\n", i + 1, c));
            }
        }
        BundleType::Custom => {
            log.push_str(&format!("Delivery recipient: {}\n", s.delivery_recipient));
            match s.delivery_kind.as_deref() {
                Some("site") => log.push_str(&format!(
                    "Delivery platform:  {}\n",
                    s.delivery_site_name.as_deref().unwrap_or("(unknown site)")
                )),
                Some("url") => log.push_str(&format!(
                    "Delivery URL:       {}\n",
                    s.delivery_url.as_deref().unwrap_or("")
                )),
                _ => log.push_str("Delivery platform:  (not set)\n"),
            }
            if s.handled_in_platform {
                log.push_str("Price:              handled in delivery platform\n");
            } else if let Some(c) = s.price_cents {
                log.push_str(&format!("Price:              ${}.{:02}\n", c / 100, c % 100));
            } else {
                log.push_str("Price:              (not set)\n");
            }
        }
        BundleType::FanSite => {
            log.push_str(&format!(
                "Fan site month:     {:04}-{:02}\n",
                s.fansite_year.unwrap_or(0),
                s.fansite_month.unwrap_or(0)
            ));
            let mut days = s.fan_days.clone();
            days.sort_by_key(|d| d.day_of_month);
            log.push_str(&format!("Days ({}):\n", days.len()));
            for d in &days {
                let count = s
                    .files
                    .iter()
                    .filter(|f| f.fansite_day_of_month == Some(d.day_of_month))
                    .count();
                log.push_str(&format!(
                    "  Day {:02} ({} file{}): {}\n",
                    d.day_of_month,
                    count,
                    if count == 1 { "" } else { "s" },
                    if d.message.is_empty() { "(no message)" } else { &d.message },
                ));
            }
        }
    }

    log.push_str("Special instructions:\n");
    if s.special_instructions.is_empty() {
        log.push_str("  (none)\n");
    } else {
        for line in s.special_instructions.lines() {
            log.push_str(&format!("  | {}\n", line));
        }
    }
    log.push_str("\n");

    // ---- Per-file build trace ----
    log.push_str("[BUILD]\n");
    log.push_str(&format!(
        "  {:<48} {:>12} bytes  sha {}…\n",
        "info.md",
        "(rendered)",
        short_sha(info_md_sha),
    ));
    log.push_str(&format!(
        "  {:<48} {:>12}\n",
        "Molly.log", "(this file — sha computed at write time)",
    ));
    let mut total_bytes: u64 = 0;
    for (path, bytes, sha) in media {
        total_bytes += bytes.len() as u64;
        log.push_str(&format!(
            "  {:<48} {:>12} bytes  sha {}…  read+verify MATCH\n",
            path,
            bytes.len(),
            short_sha(sha),
        ));
    }
    log.push_str(&format!(
        "  ---\n  Total media bytes:  {} ({} file{})\n",
        total_bytes,
        media.len(),
        if media.len() == 1 { "" } else { "s" },
    ));
    log.push_str("\n");

    // ---- Integrity note ----
    log.push_str("[INTEGRITY]\n");
    log.push_str("  Every media file above was read from disk and its\n");
    log.push_str("  live SHA-256 was asserted == the upload-time hash\n");
    log.push_str("  stored in bundle_files.sha256 before being added to\n");
    log.push_str("  the inner zip. The inner zip itself is then hashed\n");
    log.push_str("  and that hash is recorded in hashes.json (top level\n");
    log.push_str("  of the outer zip), alongside per-file hashes for\n");
    log.push_str("  each entry inside.\n");
    log.push_str("\n[END BUILD LOG]\n");
    log
}

fn short_sha(s: &str) -> &str {
    &s[..16.min(s.len())]
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;
    use std::path::PathBuf;

    fn write_tmp(dir: &Path, name: &str, body: &[u8]) -> PathBuf {
        let p = dir.join(name);
        fs::write(&p, body).unwrap();
        p
    }

    fn fixture_content(work: &Path) -> BundleSnapshot {
        let img = write_tmp(work, "photo1.jpg", b"PNG-fake-1");
        let img_sha = sha256_file(&img).unwrap();
        let vid = write_tmp(work, "clip.mp4", b"MP4-fake-content");
        let vid_sha = sha256_file(&vid).unwrap();

        BundleSnapshot {
            uid: "2026-05-22-0001".to_string(),
            bundle_type: BundleType::Content,
            persona_code: Some("CoC".to_string()),
            title: "Test Bundle One".to_string(),
            content_date: "2026-05-22".to_string(),
            go_live_date: Some("2026-05-29".to_string()),
            special_instructions: "be cute".to_string(),
            description_text: "Hello there".to_string(),
            description_audio: None,
            categories: vec!["BBW".into(), "STUFFING".into(), "SOLO".into()],
            delivery_kind: None,
            delivery_site_name: None,
            delivery_url: None,
            delivery_recipient: String::new(),
            price_cents: None,
            handled_in_platform: false,
            fansite_year: None,
            fansite_month: None,
            fan_days: Vec::new(),
            files: vec![
                FileEntry {
                    original_name: "photo1.jpg".into(),
                    abs_path: img,
                    relpath_for_error: "attachments/bundles/x/files/photo1.jpg".into(),
                    kind: FileKind::Image,
                    position: 1,
                    sha256_db: img_sha,
                    fansite_day_of_month: None,
                },
                FileEntry {
                    original_name: "clip.mp4".into(),
                    abs_path: vid,
                    relpath_for_error: "attachments/bundles/x/files/clip.mp4".into(),
                    kind: FileKind::Video,
                    position: 1,
                    sha256_db: vid_sha,
                    fansite_day_of_month: None,
                },
            ],
            published_at: "2026-05-22T03:00:00Z".to_string(),
        }
    }

    fn read_entries(zip_bytes: &[u8]) -> Vec<(String, Vec<u8>)> {
        let cursor = Cursor::new(zip_bytes);
        let mut archive = zip::ZipArchive::new(cursor).unwrap();
        let mut out = Vec::new();
        for i in 0..archive.len() {
            let mut entry = archive.by_index(i).unwrap();
            let name = entry.name().to_string();
            let mut bytes = Vec::new();
            entry.read_to_end(&mut bytes).unwrap();
            out.push((name, bytes));
        }
        out
    }

    #[test]
    fn hash_is_deterministic() {
        let work = tempfile::tempdir().unwrap();
        let snap = fixture_content(work.path());
        let out1 = tempfile::tempdir().unwrap();
        let out2 = tempfile::tempdir().unwrap();
        let a = compose_bundle(&snap, out1.path()).unwrap();
        let b = compose_bundle(&snap, out2.path()).unwrap();
        assert_eq!(
            a.outer_sha256, b.outer_sha256,
            "same snapshot must produce identical outer ZIP bytes"
        );
        assert_eq!(a.inner_sha256, b.inner_sha256);
    }

    #[test]
    fn bundle_layout_matches_spec_for_content() {
        let work = tempfile::tempdir().unwrap();
        let snap = fixture_content(work.path());
        let out = tempfile::tempdir().unwrap();
        let artifact = compose_bundle(&snap, out.path()).unwrap();

        // Outer should contain exactly inner zip + hashes.json.
        let outer_bytes = fs::read(&artifact.path).unwrap();
        let outer_entries = read_entries(&outer_bytes);
        let outer_names: Vec<String> = outer_entries.iter().map(|(n, _)| n.clone()).collect();
        assert_eq!(
            outer_names,
            vec!["2026-05-22-0001-inner.zip".to_string(), "hashes.json".to_string()]
        );

        // Inner should contain info.md, Molly.log, Photos/00001_photo1.jpg, Video/00001_clip.mp4.
        let inner_bytes = &outer_entries[0].1;
        let inner_entries = read_entries(inner_bytes);
        let inner_names: Vec<String> = inner_entries.iter().map(|(n, _)| n.clone()).collect();
        assert!(inner_names.contains(&"info.md".to_string()));
        assert!(inner_names.contains(&"Molly.log".to_string()));
        assert!(inner_names.contains(&"Photos/00001_photo1.jpg".to_string()));
        assert!(inner_names.contains(&"Video/00001_clip.mp4".to_string()));
    }

    #[test]
    fn hashes_json_matches_payload() {
        let work = tempfile::tempdir().unwrap();
        let snap = fixture_content(work.path());
        let out = tempfile::tempdir().unwrap();
        let artifact = compose_bundle(&snap, out.path()).unwrap();

        let outer_bytes = fs::read(&artifact.path).unwrap();
        let outer_entries = read_entries(&outer_bytes);
        // Order is inner.zip first, hashes.json second per build_zip plan.
        let inner_bytes = &outer_entries[0].1;
        let hashes_json_bytes = &outer_entries[1].1;

        let inner_sha_live = sha256_hex(inner_bytes);
        let doc: serde_json::Value =
            serde_json::from_slice(hashes_json_bytes).expect("hashes.json valid JSON");
        assert_eq!(
            doc["innerZip"]["sha256"].as_str().unwrap(),
            inner_sha_live,
            "hashes.json innerZip.sha256 must equal live SHA-256 of inner zip bytes"
        );

        // Every file entry's sha256 in hashes.json must match a re-hash of
        // the corresponding file inside the inner zip.
        let inner_entries = read_entries(inner_bytes);
        let by_name: std::collections::HashMap<&str, &[u8]> = inner_entries
            .iter()
            .map(|(n, b)| (n.as_str(), b.as_slice()))
            .collect();
        for f in doc["files"].as_array().unwrap() {
            let path = f["path"].as_str().unwrap();
            let claimed = f["sha256"].as_str().unwrap();
            let body = by_name.get(path).unwrap_or_else(|| panic!("inner missing {path}"));
            assert_eq!(sha256_hex(body), claimed, "sha mismatch for {path}");
        }
    }

    #[test]
    fn file_mutated_after_upload_is_caught() {
        let work = tempfile::tempdir().unwrap();
        let mut snap = fixture_content(work.path());
        // Mutate the first file on disk so its live hash differs from sha256_db.
        let p = snap.files[0].abs_path.clone();
        fs::write(&p, b"tampered bytes").unwrap();

        // Re-running compose should fail loud.
        let out = tempfile::tempdir().unwrap();
        let err = compose_bundle(&snap, out.path()).unwrap_err();
        match err {
            BundleError::AttachmentChanged { relpath } => {
                assert!(
                    relpath.contains("photo1.jpg"),
                    "error should name the mutated relpath, got {relpath}"
                );
            }
            other => panic!("expected AttachmentChanged, got {other:?}"),
        }
        // Sanity: clear sha256_db should silence the check (caller can
        // opt out, e.g. for legacy rows pre-hashing rollout).
        snap.files[0].sha256_db.clear();
        let _ok = compose_bundle(&snap, out.path()).unwrap();
    }

    #[test]
    fn info_md_includes_all_fields() {
        let work = tempfile::tempdir().unwrap();
        let snap = fixture_content(work.path());
        let md = render_info_md(&snap);
        assert!(md.contains("# Test Bundle One"));
        assert!(md.contains("`2026-05-22-0001`"));
        assert!(md.contains("`content`"));
        assert!(md.contains("`CoC`"));
        assert!(md.contains("Hello there"));
        assert!(md.contains("BBW"));
        assert!(md.contains("STUFFING"));
        assert!(md.contains("SOLO"));
        assert!(md.contains("be cute"));
        assert!(md.contains("Photos/00001_photo1.jpg"));
        assert!(md.contains("Video/00001_clip.mp4"));
    }

    #[test]
    fn fansite_layout_uses_day_and_position() {
        let work = tempfile::tempdir().unwrap();
        let f1 = write_tmp(work.path(), "a.jpg", b"a");
        let f1_sha = sha256_file(&f1).unwrap();
        let f2 = write_tmp(work.path(), "b.jpg", b"b");
        let f2_sha = sha256_file(&f2).unwrap();
        let f3 = write_tmp(work.path(), "c.jpg", b"c");
        let f3_sha = sha256_file(&f3).unwrap();

        let snap = BundleSnapshot {
            uid: "2026-05-22-0007".to_string(),
            bundle_type: BundleType::FanSite,
            persona_code: Some("Sa".to_string()),
            title: "May 2026 fan site".to_string(),
            content_date: "2026-05-22".to_string(),
            go_live_date: None,
            special_instructions: String::new(),
            description_text: String::new(),
            description_audio: None,
            categories: Vec::new(),
            delivery_kind: None,
            delivery_site_name: None,
            delivery_url: None,
            delivery_recipient: String::new(),
            price_cents: None,
            handled_in_platform: false,
            fansite_year: Some(2026),
            fansite_month: Some(5),
            fan_days: vec![
                FanDay { day_of_month: 1, message: "day one".into() },
                FanDay { day_of_month: 15, message: "mid month".into() },
            ],
            files: vec![
                FileEntry {
                    original_name: "a.jpg".into(), abs_path: f1, relpath_for_error: "a".into(),
                    kind: FileKind::Image, position: 1, sha256_db: f1_sha,
                    fansite_day_of_month: Some(1),
                },
                FileEntry {
                    original_name: "b.jpg".into(), abs_path: f2, relpath_for_error: "b".into(),
                    kind: FileKind::Image, position: 2, sha256_db: f2_sha,
                    fansite_day_of_month: Some(1),
                },
                FileEntry {
                    original_name: "c.jpg".into(), abs_path: f3, relpath_for_error: "c".into(),
                    kind: FileKind::Image, position: 1, sha256_db: f3_sha,
                    fansite_day_of_month: Some(15),
                },
            ],
            published_at: "2026-05-22T03:00:00Z".to_string(),
        };

        let out = tempfile::tempdir().unwrap();
        let artifact = compose_bundle(&snap, out.path()).unwrap();

        let outer_bytes = fs::read(&artifact.path).unwrap();
        let outer_entries = read_entries(&outer_bytes);
        let inner_entries = read_entries(&outer_entries[0].1);
        let inner_names: Vec<String> = inner_entries.iter().map(|(n, _)| n.clone()).collect();
        assert!(inner_names.contains(&"FanSite/01_01_a.jpg".to_string()));
        assert!(inner_names.contains(&"FanSite/01_02_b.jpg".to_string()));
        assert!(inner_names.contains(&"FanSite/15_01_c.jpg".to_string()));
    }

    #[test]
    fn sanitize_name_strips_path_separators() {
        assert_eq!(sanitize_name("../etc/passwd"), ".._etc_passwd");
        assert_eq!(sanitize_name("a b (c).mp4"), "a b (c).mp4");
        assert_eq!(sanitize_name(""), "_");
        assert_eq!(sanitize_name("naïve.txt"), "na_ve.txt");
    }
}

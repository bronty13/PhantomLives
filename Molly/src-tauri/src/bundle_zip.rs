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

/// Discriminated bundle flavors. Content/Custom/FanSite mirror the
/// `bundle_type` CHECK constraint in migration 017; YouTube is the 4th
/// flavor added in v1.23.0, discriminated by `bundle_kind` (migration 036).
/// YouTube shares Content's ZIP layout (Video/ + Audio/), minus categories.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BundleType {
    Content,
    Custom,
    FanSite,
    YouTube,
}

impl BundleType {
    pub fn as_str(self) -> &'static str {
        match self {
            BundleType::Content => "content",
            BundleType::Custom => "custom",
            BundleType::FanSite => "fansite",
            BundleType::YouTube => "youtube",
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
    /// Per-day content-tag names, in sort order. Empty when no tags
    /// attached to this day. FanSite-only — bundle-level tags for
    /// Content/Custom live on `BundleSnapshot.tags`.
    pub tag_names: Vec<String>,
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
    /// Optional preview assets (Content type): a static cover thumbnail and
    /// an animated teaser GIF. Composed under `Preview/` in the inner ZIP.
    pub thumbnail: Option<FileEntry>,
    pub teaser_gif: Option<FileEntry>,
    pub categories: Vec<String>, // already UPPERCASE, in position order

    /// Bundle-level content-tag names, in sort order. Populated for
    /// Content + Custom bundles; FanSite uses per-day tags on `fan_days`
    /// instead (and leaves this empty).
    pub tags: Vec<String>,

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

// ---------------------------------------------------------------------------
// Phase 2 (SideMolly contract) — manifest.json schema. Mirrors the spec in
// SideMolly/PLAN.md §5. Sibling to hashes.json in the outer ZIP; SideMolly
// prefers it over parsing Molly.log when present (parse_manifest_json in
// SideMolly/src-tauri/src/manifest.rs). Snake-case Rust fields, camelCase
// over the wire via #[serde(rename_all = "camelCase")].
// ---------------------------------------------------------------------------

const MANIFEST_VERSION: u32 = 1;

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct ManifestDoc {
    manifest_version: u32,
    bundle_uid: String,
    bundle_type: &'static str,
    persona_code: Option<String>,
    title: String,
    content_date: String,
    go_live_date: Option<String>,
    special_instructions: String,
    description: ManifestDescription,
    /// Optional preview assets (Content bundles). Paths are relative to the
    /// inner ZIP root, matching the `Preview/...` entries. Additive in
    /// manifest v1 — older consumers ignore unknown keys.
    preview: ManifestPreview,
    categories: Vec<String>,
    /// Bundle-level content tags (Content + Custom). FanSite uses
    /// per-day tags on `fanSite.days[i].tags` and leaves this empty.
    tags: Vec<String>,
    delivery: ManifestDelivery,
    fan_site: ManifestFanSite,
    files: Vec<ManifestFile>,
    published_at: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct ManifestDescription {
    /// "text" | "audio" | "none"
    mode: &'static str,
    text: String,
    audio_path: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct ManifestPreview {
    /// In-zip path of the cover thumbnail, or null when none.
    thumbnail_path: Option<String>,
    /// In-zip path of the teaser GIF, or null when none.
    teaser_gif_path: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct ManifestDelivery {
    /// "site" | "url" | null
    kind: Option<String>,
    site_name: Option<String>,
    url: Option<String>,
    recipient: String,
    price_cents: Option<i64>,
    handled_in_platform: bool,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct ManifestFanSite {
    year: Option<i64>,
    month: Option<i64>,
    days: Vec<ManifestFanDay>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct ManifestFanDay {
    day: i64,
    message: String,
    /// Per-day content-tag names, in sort order. FanSite-only.
    tags: Vec<String>,
    files: Vec<ManifestFanDayFile>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct ManifestFanDayFile {
    path: String,
    position: i64,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct ManifestFile {
    /// "video" | "image" | "audio"
    kind: &'static str,
    original_name: String,
    in_zip_path: String,
    position: i64,
    fansite_day_of_month: Option<i64>,
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

    // Preview assets (Content type only) — thumbnail + teaser GIF. Like the
    // audio description these live outside `files`; each gets a stable,
    // prefixed path under Preview/ so the in-zip layout (and therefore the
    // outer SHA-256) is deterministic.
    if let Some(thumb) = &snapshot.thumbnail {
        let bytes = read_and_verify(thumb)?;
        let sha = sha256_hex(&bytes);
        let path = format!("Preview/thumbnail_{}", sanitize_name(&thumb.original_name));
        media.push((path, bytes, sha));
    }
    if let Some(teaser) = &snapshot.teaser_gif {
        let bytes = read_and_verify(teaser)?;
        let sha = sha256_hex(&bytes);
        let path = format!("Preview/teaser_{}", sanitize_name(&teaser.original_name));
        media.push((path, bytes, sha));
    }

    // Media files. Sort defensively even though the caller is supposed
    // to send them ordered — caller bugs shouldn't make hashes flaky.
    let mut files = snapshot.files.clone();
    match snapshot.bundle_type {
        BundleType::Content | BundleType::Custom | BundleType::YouTube => {
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

    // ---- Phase 2 manifest.json (SideMolly contract — see PLAN.md §5).
    // Derived from the immutable BundleSnapshot, so this is byte-for-byte
    // deterministic across composes of the same snapshot.
    let manifest_json = render_manifest_json(snapshot);

    // ---- Outer ZIP: inner.zip + manifest.json + hashes.json.
    // Order matters for determinism (entries are zipped in this order
    // and the outer SHA-256 is sensitive to order). manifest.json sits
    // between inner.zip and hashes.json — adding it shifts hashes.json
    // by one entry from where it was in v1.17.1 bundles, which is fine
    // because consumers find it by name, not index.
    let outer_zip_bytes = build_zip(&vec![
        (inner_zip_name.clone(), inner_zip_bytes, inner_sha.clone()),
        ("manifest.json".to_string(), manifest_json, String::new()),
        ("hashes.json".to_string(), hashes_json, String::new()),
    ])?;
    let outer_sha = sha256_hex(&outer_zip_bytes);

    // ---- Atomic write to <out_dir>/<UID> <title>.zip via .tmp + rename.
    // Title is appended so Sallie can recognize bundles by name in Finder
    // instead of memorizing UIDs; falls back to `<UID>.zip` if title is empty.
    let out_path = out_dir.join(bundle_archive_filename(&snapshot.uid, &snapshot.title));
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

/// Build the on-disk filename for a published bundle ZIP. Returns
/// `<UID> <sanitized-title>.zip`, or just `<UID>.zip` when the title is
/// empty/whitespace-only or sanitizes down to nothing. Title is capped at
/// 100 chars to keep total filenames well under APFS's 255-byte limit and
/// readable in Finder.
pub fn bundle_archive_filename(uid: &str, title: &str) -> String {
    let trimmed = title.trim();
    if trimmed.is_empty() {
        return format!("{uid}.zip");
    }
    let mut safe = String::with_capacity(trimmed.len());
    for c in trimmed.chars() {
        match c {
            // Filesystem-forbidden on macOS or Windows.
            '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|' | '\0' => safe.push(' '),
            // Other control chars.
            c if (c as u32) < 0x20 => safe.push(' '),
            _ => safe.push(c),
        }
    }
    // Collapse whitespace runs and strip leading/trailing dots+spaces.
    let collapsed: String = safe.split_whitespace().collect::<Vec<_>>().join(" ");
    let cleaned = collapsed.trim_matches(|c: char| c == '.' || c.is_whitespace());
    if cleaned.is_empty() {
        return format!("{uid}.zip");
    }
    const MAX_TITLE_LEN: usize = 100;
    let title_part: String = if cleaned.chars().count() > MAX_TITLE_LEN {
        cleaned
            .chars()
            .take(MAX_TITLE_LEN)
            .collect::<String>()
            .trim_end()
            .to_string()
    } else {
        cleaned.to_string()
    };
    format!("{uid} {title_part}.zip")
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
        // YouTube shares Content's layout (description + content tags) but
        // has no Categories section.
        BundleType::Content | BundleType::YouTube => {
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

            if s.thumbnail.is_some() || s.teaser_gif.is_some() {
                md.push_str("## Preview assets\n\n");
                if let Some(thumb) = &s.thumbnail {
                    md.push_str(&format!(
                        "- **Thumbnail:** `Preview/thumbnail_{}`\n",
                        sanitize_name(&thumb.original_name)
                    ));
                }
                if let Some(teaser) = &s.teaser_gif {
                    md.push_str(&format!(
                        "- **Teaser GIF:** `Preview/teaser_{}`\n",
                        sanitize_name(&teaser.original_name)
                    ));
                }
                md.push('\n');
            }

            if s.bundle_type != BundleType::YouTube {
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

            md.push_str("## Content tags\n\n");
            if s.tags.is_empty() {
                md.push_str("_(none)_\n\n");
            } else {
                md.push_str(&format!("{}\n\n", s.tags.join(", ")));
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

            md.push_str("## Content tags\n\n");
            if s.tags.is_empty() {
                md.push_str("_(none)_\n\n");
            } else {
                md.push_str(&format!("{}\n\n", s.tags.join(", ")));
            }
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
                    "### Day {:02}\n\n{}\n\n_({} file{})_\n",
                    d.day_of_month,
                    if d.message.is_empty() { "_(no message)_" } else { &d.message },
                    count,
                    if count == 1 { "" } else { "s" }
                ));
                if !d.tag_names.is_empty() {
                    md.push_str(&format!("\n**Tags:** {}\n", d.tag_names.join(", ")));
                }
                md.push('\n');
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
        BundleType::Content | BundleType::YouTube => {
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
            if let Some(thumb) = &s.thumbnail {
                log.push_str(&format!(
                    "Thumbnail:          Preview/thumbnail_{}\n",
                    sanitize_name(&thumb.original_name)
                ));
            }
            if let Some(teaser) = &s.teaser_gif {
                log.push_str(&format!(
                    "Teaser GIF:         Preview/teaser_{}\n",
                    sanitize_name(&teaser.original_name)
                ));
            }
            if s.bundle_type != BundleType::YouTube {
                log.push_str(&format!("Categories ({}):\n", s.categories.len()));
                for (i, c) in s.categories.iter().enumerate() {
                    log.push_str(&format!("  {}. {}\n", i + 1, c));
                }
            }
            log.push_str(&format!("Content tags ({}):\n", s.tags.len()));
            if s.tags.is_empty() {
                log.push_str("  (none)\n");
            } else {
                for (i, t) in s.tags.iter().enumerate() {
                    log.push_str(&format!("  {}. {}\n", i + 1, t));
                }
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
            log.push_str(&format!("Content tags ({}):\n", s.tags.len()));
            if s.tags.is_empty() {
                log.push_str("  (none)\n");
            } else {
                for (i, t) in s.tags.iter().enumerate() {
                    log.push_str(&format!("  {}. {}\n", i + 1, t));
                }
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
                if !d.tag_names.is_empty() {
                    log.push_str(&format!(
                        "    tags: {}\n",
                        d.tag_names.join(", "),
                    ));
                }
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

// ---------------------------------------------------------------------------
// Phase 2 (SideMolly contract): manifest.json composition.
// Sits at the top of the outer ZIP, between <UID>-inner.zip and
// hashes.json. SideMolly's parse_manifest_json prefers this over its
// Molly.log fallback. Everything below is derived from the immutable
// BundleSnapshot — no DB, no FS reads — so it's byte-for-byte
// deterministic across composes of the same snapshot.
// ---------------------------------------------------------------------------

/// Compute the inner-zip path a given FileEntry will land at. Mirrors
/// the path-construction logic in compose_bundle's media loop so the
/// manifest references match the actual zip layout. NOT factored back
/// into compose_bundle to avoid changing the existing byte stream — the
/// outer SHA-256 already changes (new entry added) but inner ZIP bytes
/// must stay identical so v1.18.0 bundles can still be re-ingested by
/// older SideMolly versions via the Molly.log fallback path.
fn in_zip_path_for(snapshot: &BundleSnapshot, file: &FileEntry) -> String {
    match snapshot.bundle_type {
        BundleType::Content | BundleType::Custom | BundleType::YouTube => {
            let folder = match file.kind {
                FileKind::Video => "Video",
                FileKind::Image => "Photos",
                FileKind::Audio => "Audio",
            };
            format!("{folder}/{:05}_{}", file.position, sanitize_name(&file.original_name))
        }
        BundleType::FanSite => {
            let day = file.fansite_day_of_month.unwrap_or(0);
            format!("FanSite/{:02}_{:02}_{}", day, file.position, sanitize_name(&file.original_name))
        }
    }
}

pub fn render_manifest_json(snapshot: &BundleSnapshot) -> Vec<u8> {
    // ---- Description (Content bundles) ----
    let description = if let Some(audio) = &snapshot.description_audio {
        ManifestDescription {
            mode: "audio",
            text: String::new(),
            audio_path: Some(format!("Audio/{}", sanitize_name(&audio.original_name))),
        }
    } else if !snapshot.description_text.is_empty() {
        ManifestDescription {
            mode: "text",
            text: snapshot.description_text.clone(),
            audio_path: None,
        }
    } else {
        ManifestDescription {
            mode: "none",
            text: String::new(),
            audio_path: None,
        }
    };

    // ---- Preview assets (Content bundles) ----
    let preview = ManifestPreview {
        thumbnail_path: snapshot
            .thumbnail
            .as_ref()
            .map(|t| format!("Preview/thumbnail_{}", sanitize_name(&t.original_name))),
        teaser_gif_path: snapshot
            .teaser_gif
            .as_ref()
            .map(|t| format!("Preview/teaser_{}", sanitize_name(&t.original_name))),
    };

    // ---- Delivery (Custom bundles) ----
    let delivery = ManifestDelivery {
        kind: snapshot.delivery_kind.clone(),
        site_name: snapshot.delivery_site_name.clone(),
        url: snapshot.delivery_url.clone(),
        recipient: snapshot.delivery_recipient.clone(),
        price_cents: snapshot.price_cents,
        handled_in_platform: snapshot.handled_in_platform,
    };

    // ---- FanSite (FanSite bundles) ----
    // Days are ordered by day_of_month; per-day files are filtered
    // from the snapshot's flat file list (sorted by position for
    // stability).
    let mut fan_days_sorted = snapshot.fan_days.clone();
    fan_days_sorted.sort_by_key(|d| d.day_of_month);
    let fan_days: Vec<ManifestFanDay> = fan_days_sorted
        .iter()
        .map(|d| {
            let mut files: Vec<&FileEntry> = snapshot
                .files
                .iter()
                .filter(|f| f.fansite_day_of_month == Some(d.day_of_month))
                .collect();
            files.sort_by_key(|f| f.position);
            ManifestFanDay {
                day: d.day_of_month,
                message: d.message.clone(),
                tags: d.tag_names.clone(),
                files: files
                    .iter()
                    .map(|f| ManifestFanDayFile {
                        path: in_zip_path_for(snapshot, f),
                        position: f.position,
                    })
                    .collect(),
            }
        })
        .collect();

    // ---- Flat files list ----
    // Mirror the same ordering as compose_bundle's media iteration so
    // the order is meaningful + deterministic.
    let mut files_sorted = snapshot.files.clone();
    match snapshot.bundle_type {
        BundleType::Content | BundleType::Custom | BundleType::YouTube => {
            files_sorted.sort_by_key(|f| (f.kind as i32, f.position));
        }
        BundleType::FanSite => {
            files_sorted.sort_by_key(|f| (f.fansite_day_of_month.unwrap_or(0), f.position));
        }
    }
    let files: Vec<ManifestFile> = files_sorted
        .iter()
        .map(|f| ManifestFile {
            kind: f.kind.as_str(),
            original_name: f.original_name.clone(),
            in_zip_path: in_zip_path_for(snapshot, f),
            position: f.position,
            fansite_day_of_month: f.fansite_day_of_month,
            sha256: f.sha256_db.clone(),
        })
        .collect();

    let doc = ManifestDoc {
        manifest_version: MANIFEST_VERSION,
        bundle_uid: snapshot.uid.clone(),
        bundle_type: snapshot.bundle_type.as_str(),
        persona_code: snapshot.persona_code.clone(),
        title: snapshot.title.clone(),
        content_date: snapshot.content_date.clone(),
        go_live_date: snapshot.go_live_date.clone(),
        special_instructions: snapshot.special_instructions.clone(),
        description,
        preview,
        categories: snapshot.categories.clone(),
        tags: snapshot.tags.clone(),
        delivery,
        fan_site: ManifestFanSite {
            year: snapshot.fansite_year,
            month: snapshot.fansite_month,
            days: fan_days,
        },
        files,
        published_at: snapshot.published_at.clone(),
    };
    serde_json::to_vec_pretty(&doc).expect("ManifestDoc is always serializable")
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;
    use std::path::PathBuf;

    #[test]
    fn archive_filename_appends_title() {
        assert_eq!(
            bundle_archive_filename("2026-05-26-0001", "My Title Goes Here"),
            "2026-05-26-0001 My Title Goes Here.zip",
        );
    }

    #[test]
    fn archive_filename_falls_back_when_title_empty() {
        assert_eq!(
            bundle_archive_filename("2026-05-26-0001", ""),
            "2026-05-26-0001.zip",
        );
        assert_eq!(
            bundle_archive_filename("2026-05-26-0001", "   "),
            "2026-05-26-0001.zip",
        );
    }

    #[test]
    fn archive_filename_sanitizes_forbidden_chars() {
        // /, \, :, *, ?, ", <, >, | are all illegal somewhere — replace
        // with spaces and collapse runs.
        let got = bundle_archive_filename("2026-05-26-0001", "May 2026 / Custom: \"foo\"");
        assert_eq!(got, "2026-05-26-0001 May 2026 Custom foo.zip");
    }

    #[test]
    fn archive_filename_truncates_long_titles() {
        let long_title = "a".repeat(500);
        let got = bundle_archive_filename("2026-05-26-0001", &long_title);
        // 15 (uid) + 1 (space) + 100 (capped title) + 4 (".zip") = 120
        assert_eq!(got.len(), 120);
        assert!(got.starts_with("2026-05-26-0001 "));
        assert!(got.ends_with(".zip"));
    }

    #[test]
    fn archive_filename_strips_leading_trailing_dots() {
        // Windows reserves trailing dots, and leading dots make Finder hide
        // the file on macOS. Strip both.
        assert_eq!(
            bundle_archive_filename("2026-05-26-0001", "...edge case..."),
            "2026-05-26-0001 edge case.zip",
        );
    }

    #[test]
    fn archive_filename_falls_back_when_only_forbidden_chars() {
        // Sanitization can empty the title; fall back to UID-only.
        assert_eq!(
            bundle_archive_filename("2026-05-26-0001", "///:::"),
            "2026-05-26-0001.zip",
        );
    }

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
            thumbnail: None,
            teaser_gif: None,
            categories: vec!["BBW".into(), "STUFFING".into(), "SOLO".into()],
            tags: vec!["tits".into(), "panties".into()],
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

        // Outer should contain inner zip + manifest.json + hashes.json
        // (v1.18.0+ Phase 2 contract; v1.17.x bundles had no manifest).
        let outer_bytes = fs::read(&artifact.path).unwrap();
        let outer_entries = read_entries(&outer_bytes);
        let outer_names: Vec<String> = outer_entries.iter().map(|(n, _)| n.clone()).collect();
        assert_eq!(
            outer_names,
            vec![
                "2026-05-22-0001-inner.zip".to_string(),
                "manifest.json".to_string(),
                "hashes.json".to_string(),
            ],
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
        // Order per build_zip plan: inner.zip, manifest.json, hashes.json.
        let inner_bytes = &outer_entries[0].1;
        let hashes_json_bytes = &outer_entries[2].1;

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
        // Phase 14 PR5 — content tags must appear under their own heading.
        assert!(md.contains("## Content tags"));
        assert!(md.contains("tits, panties"));
    }

    #[test]
    fn molly_log_includes_bundle_level_tags() {
        let work = tempfile::tempdir().unwrap();
        let snap = fixture_content(work.path());
        let log = render_molly_log(&snap, "deadbeef", &[]);
        assert!(log.contains("Content tags (2):"));
        assert!(log.contains("1. tits"));
        assert!(log.contains("2. panties"));
    }

    #[test]
    fn info_md_renders_per_day_tags_for_fansite() {
        // Build a minimal FanSite snapshot without composing — render only.
        let snap = BundleSnapshot {
            uid: "X".into(), bundle_type: BundleType::FanSite,
            persona_code: None, title: "T".into(), content_date: "2026-06-01".into(),
            go_live_date: None, special_instructions: String::new(),
            description_text: String::new(), description_audio: None,
            thumbnail: None, teaser_gif: None,
            categories: Vec::new(), tags: Vec::new(),
            delivery_kind: None, delivery_site_name: None, delivery_url: None,
            delivery_recipient: String::new(), price_cents: None, handled_in_platform: false,
            fansite_year: Some(2026), fansite_month: Some(6),
            fan_days: vec![
                FanDay { day_of_month: 4,  message: "spring".into(),  tag_names: vec!["heels".into(), "tits".into()] },
                FanDay { day_of_month: 11, message: "monday".into(),  tag_names: vec![] },
                FanDay { day_of_month: 18, message: "midweek".into(), tag_names: vec!["flats".into()] },
            ],
            files: Vec::new(), published_at: "2026-06-01T00:00:00Z".into(),
        };
        let md = render_info_md(&snap);
        // Day 4 → both tags present, comma-joined, under a Tags line.
        assert!(md.contains("### Day 04"));
        assert!(md.contains("**Tags:** heels, tits"));
        // Day 11 → no tag line at all (must not say "Tags: ").
        assert!(md.contains("### Day 11"));
        // Day 18 → single tag.
        assert!(md.contains("### Day 18"));
        assert!(md.contains("**Tags:** flats"));
        // Negative — render must not emit "Tags:" for the empty day. Since
        // "Tags:" appears in other day blocks we count occurrences.
        let tag_line_count = md.matches("**Tags:**").count();
        assert_eq!(tag_line_count, 2, "only days with tags should print a Tags line");
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
            thumbnail: None,
            teaser_gif: None,
            categories: Vec::new(),
            tags: Vec::new(),
            delivery_kind: None,
            delivery_site_name: None,
            delivery_url: None,
            delivery_recipient: String::new(),
            price_cents: None,
            handled_in_platform: false,
            fansite_year: Some(2026),
            fansite_month: Some(5),
            fan_days: vec![
                FanDay {
                    day_of_month: 1,
                    message: "day one".into(),
                    tag_names: vec!["heels".into(), "tits".into()],
                },
                FanDay {
                    day_of_month: 15,
                    message: "mid month".into(),
                    tag_names: vec!["flats".into()],
                },
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

    // ---------------------------------------------------------------------------
    // Phase 2 — manifest.json contract.
    // ---------------------------------------------------------------------------

    fn read_outer_manifest_bytes(artifact_path: &Path) -> Vec<u8> {
        let outer_bytes = fs::read(artifact_path).unwrap();
        let outer_entries = read_entries(&outer_bytes);
        // [0] inner.zip, [1] manifest.json, [2] hashes.json — per the
        // compose_bundle planned order.
        outer_entries[1].1.clone()
    }

    #[test]
    fn manifest_json_is_deterministic() {
        // Same snapshot composed twice must produce byte-identical
        // manifest.json. The whole outer-ZIP SHA depends on this.
        let work = tempfile::tempdir().unwrap();
        let snap = fixture_content(work.path());
        let out1 = tempfile::tempdir().unwrap();
        let out2 = tempfile::tempdir().unwrap();
        let a = compose_bundle(&snap, out1.path()).unwrap();
        let b = compose_bundle(&snap, out2.path()).unwrap();
        let manifest_a = read_outer_manifest_bytes(&a.path);
        let manifest_b = read_outer_manifest_bytes(&b.path);
        assert_eq!(manifest_a, manifest_b);
        // Sanity: also valid JSON.
        let _: serde_json::Value = serde_json::from_slice(&manifest_a)
            .expect("manifest.json must be valid JSON");
    }

    #[test]
    fn manifest_json_round_trips_content_bundle() {
        let work = tempfile::tempdir().unwrap();
        let snap = fixture_content(work.path());
        let out = tempfile::tempdir().unwrap();
        let artifact = compose_bundle(&snap, out.path()).unwrap();
        let manifest_bytes = read_outer_manifest_bytes(&artifact.path);
        let doc: serde_json::Value = serde_json::from_slice(&manifest_bytes).unwrap();

        assert_eq!(doc["manifestVersion"], 1);
        assert_eq!(doc["bundleUid"], "2026-05-22-0001");
        assert_eq!(doc["bundleType"], "content");
        assert_eq!(doc["personaCode"], "CoC");
        assert_eq!(doc["title"], "Test Bundle One");
        assert_eq!(doc["contentDate"], "2026-05-22");
        assert_eq!(doc["goLiveDate"], "2026-05-29");
        assert_eq!(doc["specialInstructions"], "be cute");
        assert_eq!(doc["description"]["mode"], "text");
        assert_eq!(doc["description"]["text"], "Hello there");
        assert!(doc["description"]["audioPath"].is_null());
        assert_eq!(doc["categories"][0], "BBW");
        assert_eq!(doc["categories"][1], "STUFFING");
        assert_eq!(doc["categories"][2], "SOLO");
        assert_eq!(doc["tags"][0], "tits");
        assert_eq!(doc["tags"][1], "panties");
        assert_eq!(doc["publishedAt"], "2026-05-22T03:00:00Z");

        // Files list mirrors inner-zip layout (kind, position, in-zip path, sha).
        let files = doc["files"].as_array().unwrap();
        assert_eq!(files.len(), 2);
        let by_path: std::collections::HashMap<&str, &serde_json::Value> =
            files.iter().map(|f| (f["inZipPath"].as_str().unwrap(), f)).collect();
        let img = by_path.get("Photos/00001_photo1.jpg").unwrap();
        assert_eq!(img["kind"], "image");
        assert_eq!(img["originalName"], "photo1.jpg");
        assert_eq!(img["position"], 1);
        assert!(img["fansiteDayOfMonth"].is_null());
        assert!(img["sha256"].as_str().unwrap().len() == 64);
        let vid = by_path.get("Video/00001_clip.mp4").unwrap();
        assert_eq!(vid["kind"], "video");

        // Empty Custom/FanSite fields stay structurally present but null/empty.
        assert!(doc["delivery"]["kind"].is_null());
        assert_eq!(doc["delivery"]["handledInPlatform"], false);
        assert!(doc["fanSite"]["year"].is_null());
        assert_eq!(doc["fanSite"]["days"].as_array().unwrap().len(), 0);

        // No preview assets in the base fixture — the object is present but null.
        assert!(doc["preview"]["thumbnailPath"].is_null());
        assert!(doc["preview"]["teaserGifPath"].is_null());
    }

    #[test]
    fn compose_includes_preview_assets() {
        let work = tempfile::tempdir().unwrap();
        let mut snap = fixture_content(work.path());
        let thumb = write_tmp(work.path(), "cover.png", b"PNG-thumb-bytes");
        let teaser = write_tmp(work.path(), "loop.gif", b"GIF89a-teaser-bytes");
        snap.thumbnail = Some(FileEntry {
            original_name: "cover.png".into(),
            abs_path: thumb.clone(),
            relpath_for_error: "attachments/bundles/x/files/cover.png".into(),
            kind: FileKind::Image,
            position: 0,
            sha256_db: sha256_file(&thumb).unwrap(),
            fansite_day_of_month: None,
        });
        snap.teaser_gif = Some(FileEntry {
            original_name: "loop.gif".into(),
            abs_path: teaser.clone(),
            relpath_for_error: "attachments/bundles/x/files/loop.gif".into(),
            kind: FileKind::Image,
            position: 0,
            sha256_db: sha256_file(&teaser).unwrap(),
            fansite_day_of_month: None,
        });

        let out = tempfile::tempdir().unwrap();
        let artifact = compose_bundle(&snap, out.path()).unwrap();

        // (a) Both assets land under Preview/ in the inner zip.
        let outer_bytes = fs::read(&artifact.path).unwrap();
        let outer_entries = read_entries(&outer_bytes);
        let inner_entries = read_entries(&outer_entries[0].1);
        let inner_names: Vec<String> = inner_entries.iter().map(|(n, _)| n.clone()).collect();
        assert!(inner_names.contains(&"Preview/thumbnail_cover.png".to_string()));
        assert!(inner_names.contains(&"Preview/teaser_loop.gif".to_string()));

        // (b) hashes.json carries both Preview/ entries.
        let manifest_bytes = read_outer_manifest_bytes(&artifact.path);
        let doc: serde_json::Value = serde_json::from_slice(&manifest_bytes).unwrap();
        assert_eq!(doc["preview"]["thumbnailPath"], "Preview/thumbnail_cover.png");
        assert_eq!(doc["preview"]["teaserGifPath"], "Preview/teaser_loop.gif");

        // (c) Determinism: composing the same snapshot again is byte-identical.
        let out2 = tempfile::tempdir().unwrap();
        let artifact2 = compose_bundle(&snap, out2.path()).unwrap();
        assert_eq!(artifact.outer_sha256, artifact2.outer_sha256);
    }

    #[test]
    fn compose_without_preview_assets_is_backward_compatible() {
        // A Content bundle with no preview assets produces a manifest whose
        // preview object is null/null and an unchanged outer SHA across runs.
        let work = tempfile::tempdir().unwrap();
        let snap = fixture_content(work.path());
        let out1 = tempfile::tempdir().unwrap();
        let out2 = tempfile::tempdir().unwrap();
        let a = compose_bundle(&snap, out1.path()).unwrap();
        let b = compose_bundle(&snap, out2.path()).unwrap();
        assert_eq!(a.outer_sha256, b.outer_sha256);
        let manifest = read_outer_manifest_bytes(&a.path);
        let doc: serde_json::Value = serde_json::from_slice(&manifest).unwrap();
        assert!(doc["preview"]["thumbnailPath"].is_null());
        assert!(doc["preview"]["teaserGifPath"].is_null());
    }

    #[test]
    fn manifest_json_round_trips_custom_bundle() {
        let work = tempfile::tempdir().unwrap();
        let img = write_tmp(work.path(), "preview.jpg", b"PNG-fake");
        let img_sha = sha256_file(&img).unwrap();

        let snap = BundleSnapshot {
            uid: "2026-05-22-0014".to_string(),
            bundle_type: BundleType::Custom,
            persona_code: Some("PoA".to_string()),
            title: "@username 5min custom".to_string(),
            content_date: "2026-05-22".to_string(),
            go_live_date: None,
            special_instructions: String::new(),
            description_text: String::new(),
            description_audio: None,
            thumbnail: None,
            teaser_gif: None,
            categories: Vec::new(),
            tags: Vec::new(),
            delivery_kind: Some("site".to_string()),
            delivery_site_name: Some("C4S Studio messages".to_string()),
            delivery_url: None,
            delivery_recipient: "@username".to_string(),
            price_cents: Some(4900),
            handled_in_platform: false,
            fansite_year: None,
            fansite_month: None,
            fan_days: Vec::new(),
            files: vec![FileEntry {
                original_name: "preview.jpg".into(),
                abs_path: img,
                relpath_for_error: "preview.jpg".into(),
                kind: FileKind::Image,
                position: 1,
                sha256_db: img_sha,
                fansite_day_of_month: None,
            }],
            published_at: "2026-05-22T03:00:00Z".to_string(),
        };
        let out = tempfile::tempdir().unwrap();
        let artifact = compose_bundle(&snap, out.path()).unwrap();
        let manifest_bytes = read_outer_manifest_bytes(&artifact.path);
        let doc: serde_json::Value = serde_json::from_slice(&manifest_bytes).unwrap();

        assert_eq!(doc["bundleType"], "custom");
        assert_eq!(doc["delivery"]["kind"], "site");
        assert_eq!(doc["delivery"]["siteName"], "C4S Studio messages");
        assert!(doc["delivery"]["url"].is_null());
        assert_eq!(doc["delivery"]["recipient"], "@username");
        assert_eq!(doc["delivery"]["priceCents"], 4900);
        assert_eq!(doc["delivery"]["handledInPlatform"], false);
    }

    #[test]
    fn manifest_json_round_trips_fansite_bundle() {
        // Reuse the existing fansite_layout fixture inline.
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
            thumbnail: None,
            teaser_gif: None,
            categories: Vec::new(),
            tags: Vec::new(),
            delivery_kind: None,
            delivery_site_name: None,
            delivery_url: None,
            delivery_recipient: String::new(),
            price_cents: None,
            handled_in_platform: false,
            fansite_year: Some(2026),
            fansite_month: Some(5),
            fan_days: vec![
                FanDay {
                    day_of_month: 1,
                    message: "day one".into(),
                    tag_names: vec!["heels".into(), "tits".into()],
                },
                FanDay {
                    day_of_month: 15,
                    message: "mid month".into(),
                    tag_names: vec!["flats".into()],
                },
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
        let manifest_bytes = read_outer_manifest_bytes(&artifact.path);
        let doc: serde_json::Value = serde_json::from_slice(&manifest_bytes).unwrap();

        assert_eq!(doc["bundleType"], "fansite");
        assert_eq!(doc["fanSite"]["year"], 2026);
        assert_eq!(doc["fanSite"]["month"], 5);
        let days = doc["fanSite"]["days"].as_array().unwrap();
        assert_eq!(days.len(), 2);
        assert_eq!(days[0]["day"], 1);
        assert_eq!(days[0]["message"], "day one");
        assert_eq!(days[0]["tags"][0], "heels");
        assert_eq!(days[0]["files"].as_array().unwrap().len(), 2);
        assert_eq!(days[0]["files"][0]["path"], "FanSite/01_01_a.jpg");
        assert_eq!(days[0]["files"][0]["position"], 1);
        assert_eq!(days[1]["day"], 15);
        assert_eq!(days[1]["files"][0]["path"], "FanSite/15_01_c.jpg");

        // Flat files list keyed by inZipPath; fansiteDayOfMonth populated.
        let files = doc["files"].as_array().unwrap();
        assert_eq!(files.len(), 3);
        let a_row = files.iter().find(|f| f["inZipPath"] == "FanSite/01_01_a.jpg").unwrap();
        assert_eq!(a_row["fansiteDayOfMonth"], 1);
        assert_eq!(a_row["kind"], "image");
    }

    #[test]
    fn manifest_json_audio_description_mode() {
        let work = tempfile::tempdir().unwrap();
        let audio = write_tmp(work.path(), "say.m4a", b"AAC");
        let audio_sha = sha256_file(&audio).unwrap();

        let snap = BundleSnapshot {
            uid: "2026-05-22-0099".to_string(),
            bundle_type: BundleType::Content,
            persona_code: Some("Sa".to_string()),
            title: "audio-described".to_string(),
            content_date: "2026-05-22".to_string(),
            go_live_date: None,
            special_instructions: String::new(),
            description_text: String::new(),
            description_audio: Some(FileEntry {
                original_name: "say.m4a".into(),
                abs_path: audio,
                relpath_for_error: "say.m4a".into(),
                kind: FileKind::Audio,
                position: 1,
                sha256_db: audio_sha,
                fansite_day_of_month: None,
            }),
            thumbnail: None,
            teaser_gif: None,
            categories: vec!["BBW".into()],
            tags: Vec::new(),
            delivery_kind: None,
            delivery_site_name: None,
            delivery_url: None,
            delivery_recipient: String::new(),
            price_cents: None,
            handled_in_platform: false,
            fansite_year: None,
            fansite_month: None,
            fan_days: Vec::new(),
            files: Vec::new(),
            published_at: "2026-05-22T03:00:00Z".to_string(),
        };
        let out = tempfile::tempdir().unwrap();
        let artifact = compose_bundle(&snap, out.path()).unwrap();
        let manifest_bytes = read_outer_manifest_bytes(&artifact.path);
        let doc: serde_json::Value = serde_json::from_slice(&manifest_bytes).unwrap();

        assert_eq!(doc["description"]["mode"], "audio");
        assert_eq!(doc["description"]["audioPath"], "Audio/say.m4a");
        assert_eq!(doc["description"]["text"], "");
    }
}

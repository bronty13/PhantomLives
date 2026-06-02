//! SideMolly Summary — a one-document PDF per bundle.
//!
//! Gathers, in order: applicable metadata (varying by bundle type), a grid of
//! medium thumbnails (the configured export-thumb selection), a cleaned-up
//! concatenation of every video transcript, and the full processing log.
//!
//! Written to `work/<uid>/auto/<MasterBasename> — Summary.pdf` and copied to
//! Dropbox alongside the assembled master cut. Rendered with `genpdf`
//! (automatic text wrapping + pagination + JPEG embedding); the body font is
//! bundled Liberation Sans (OFL), embedded at compile time.

use std::fs;
use std::path::{Path, PathBuf};

use rusqlite::{params, Connection, OptionalExtension};
use serde::Serialize;
use tauri::{AppHandle, Manager, Runtime};

use genpdf::{elements, fonts, style, Element as _};

use crate::bundles::{self, BundleError};
use crate::manifest::BundleManifest;

const FONT_REGULAR: &[u8] = include_bytes!("../resources/fonts/LiberationSans-Regular.ttf");
const FONT_BOLD: &[u8] = include_bytes!("../resources/fonts/LiberationSans-Bold.ttf");
const FONT_ITALIC: &[u8] = include_bytes!("../resources/fonts/LiberationSans-Italic.ttf");
const FONT_BOLD_ITALIC: &[u8] = include_bytes!("../resources/fonts/LiberationSans-BoldItalic.ttf");

/// Columns in the thumbnail grid.
const GRID_COLS: usize = 3;
/// DPI used when embedding a 256px thumbnail so it lands at ~medium width
/// (≈59 mm) inside a ~62 mm column on an A4 page with 12 mm margins.
const THUMB_DPI: f64 = 110.0;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SummaryResult {
    pub output_path: String,
}

fn open_conn<R: Runtime>(handle: &AppHandle<R>) -> Result<Connection, BundleError> {
    let dir = handle
        .path()
        .resolve("", tauri::path::BaseDirectory::AppLocalData)
        .map_err(|e| BundleError::Io(std::io::Error::other(format!("appdata path: {e}"))))?;
    let conn = Connection::open(dir.join("sidemolly.db"))?;
    conn.execute_batch("PRAGMA foreign_keys = ON;")?;
    Ok(conn)
}

fn pdf_err(context: &str, e: genpdf::error::Error) -> BundleError {
    BundleError::Io(std::io::Error::other(format!("pdf {context}: {e}")))
}

// ---------------------------------------------------------------------------
// Pure helpers (unit-tested)
// ---------------------------------------------------------------------------

/// Normalize a concatenation of raw whisper `.txt` transcripts into flowing
/// prose: drop blank lines, collapse internal whitespace, split into sentences
/// on `.?!`, capitalize each sentence's first letter, and guarantee each ends
/// with terminal punctuation followed by two spaces. Best-effort when the
/// source lacks punctuation (capitalizes the start, appends a period).
pub(crate) fn clean_transcript(raw: &str) -> String {
    // Collapse every run of whitespace (incl. the per-segment newlines) to a
    // single space. This alone removes blank lines and stray indentation.
    let flat: String = raw.split_whitespace().collect::<Vec<_>>().join(" ");
    if flat.is_empty() {
        return String::new();
    }

    // Split into sentences, keeping the terminal punctuation on each.
    let mut sentences: Vec<String> = Vec::new();
    let mut cur = String::new();
    for ch in flat.chars() {
        cur.push(ch);
        if matches!(ch, '.' | '!' | '?') {
            let s = cur.trim();
            if !s.is_empty() {
                sentences.push(s.to_string());
            }
            cur.clear();
        }
    }
    let tail = cur.trim();
    if !tail.is_empty() {
        sentences.push(tail.to_string());
    }

    let cleaned: Vec<String> = sentences
        .iter()
        .map(|s| {
            let mut s = s.trim().to_string();
            // Capitalize the first alphabetic character.
            if let Some(idx) = s.find(|c: char| c.is_alphabetic()) {
                let first = s[idx..].chars().next().unwrap();
                let upper: String = first.to_uppercase().collect();
                s.replace_range(idx..idx + first.len_utf8(), &upper);
            }
            // Guarantee terminal punctuation.
            if !s.ends_with(['.', '!', '?']) {
                s.push('.');
            }
            s
        })
        .collect();

    // Two spaces between sentences.
    cleaned.join("  ")
}

/// Format a price in cents as `$X.XX`, or the platform note when handled there.
fn format_price(price_cents: Option<i64>, handled_in_platform: bool) -> String {
    if handled_in_platform {
        "Handled in platform".to_string()
    } else if let Some(c) = price_cents {
        format!("${:.2}", c as f64 / 100.0)
    } else {
        "—".to_string()
    }
}

fn nonempty(s: &Option<String>) -> Option<String> {
    s.as_ref().map(|v| v.trim().to_string()).filter(|v| !v.is_empty())
}

/// Seconds → `MM:SS` (minutes uncapped, so a 75-minute video reads `75:00`).
fn format_duration_mmss(secs: f64) -> String {
    let total = secs.max(0.0) as u64; // floor
    format!("{:02}:{:02}", total / 60, total % 60)
}

/// Bytes → `"12.4 MB"`.
fn format_size_mb(bytes: u64) -> String {
    format!("{:.1} MB", bytes as f64 / (1024.0 * 1024.0))
}

/// Streaming SHA-256 of a file (the master cut can be hundreds of MB).
fn sha256_file(path: &Path) -> Option<String> {
    use sha2::{Digest, Sha256};
    use std::io::Read;
    let mut file = std::fs::File::open(path).ok()?;
    let mut hasher = Sha256::new();
    let mut buf = [0u8; 65536];
    loop {
        let n = file.read(&mut buf).ok()?;
        if n == 0 {
            break;
        }
        hasher.update(&buf[..n]);
    }
    Some(format!("{:x}", hasher.finalize()))
}

/// Gather the assembled master cut's size / length / hash, or `None` when the
/// bundle hasn't been assembled yet.
fn gather_assembled(workspace: &Path, title: &str) -> Option<AssembledInfo> {
    let master = bundles::resolve_master_cut_path(workspace, title);
    if !master.exists() {
        return None;
    }
    let size = std::fs::metadata(&master).map(|m| m.len()).unwrap_or(0);
    Some(AssembledInfo {
        filename: master.file_name().map(|s| s.to_string_lossy().to_string()).unwrap_or_default(),
        size_mb: format_size_mb(size),
        length: crate::thumbnails::probe_video_duration(&master)
            .map(format_duration_mmss)
            .unwrap_or_else(|| "—".into()),
        sha256: sha256_file(&master).unwrap_or_else(|| "—".into()),
    })
}

/// Verification + size details of the assembled master cut, gathered (with
/// file I/O) by the caller and rendered after "Date Processed".
pub(crate) struct AssembledInfo {
    pub filename: String,
    pub size_mb: String,
    pub length: String,
    pub sha256: String,
}

/// Build the label/value metadata rows for a bundle, varying by type. Adding a
/// new bundle type means extending the single `match` below — that's the
/// "expandable for new bundle types" contract. The `description` value is
/// resolved by the caller (typed text or audio transcript) and passed in;
/// `assembled` carries the master-cut details rendered after Date Processed.
pub(crate) fn summary_fields(
    m: &BundleManifest,
    title_override: &str,
    description: &str,
    processed_at: Option<&str>,
    assembled: Option<&AssembledInfo>,
) -> Vec<(String, String)> {
    let mut f: Vec<(String, String)> = Vec::new();

    f.push(("Title".into(), if m.title.trim().is_empty() { "(untitled)".into() } else { m.title.trim().into() }));

    let ov = title_override.trim();
    if !ov.is_empty() && ov != m.title.trim() {
        f.push(("Working title".into(), ov.to_string()));
    }

    if !description.trim().is_empty() {
        f.push(("Description".into(), description.trim().to_string()));
    }
    if !m.categories.is_empty() {
        f.push(("Categories".into(), m.categories.join(", ")));
    }
    if let Some(g) = nonempty(&m.go_live_date) {
        f.push(("Go-Live Date".into(), g));
    }
    f.push((
        "Date Processed".into(),
        processed_at.map(|s| s.to_string()).unwrap_or_else(|| "— (not yet assembled)".into()),
    ));

    // Assembled master-cut details (size / length / verification hash).
    if let Some(a) = assembled {
        f.push(("Assembled file".into(), a.filename.clone()));
        f.push(("File size".into(), a.size_mb.clone()));
        f.push(("Length".into(), a.length.clone()));
        f.push(("SHA-256".into(), a.sha256.clone()));
    }

    match m.bundle_type.as_str() {
        "custom" => {
            match m.delivery_kind.as_deref() {
                Some("url") => {
                    if let Some(u) = nonempty(&m.delivery_url) {
                        f.push(("Delivery URL".into(), u));
                    }
                }
                _ => {
                    if let Some(s) = nonempty(&m.delivery_site_name) {
                        f.push(("Site".into(), s));
                    }
                }
            }
            if !m.delivery_recipient.trim().is_empty() {
                f.push(("Deliver to".into(), m.delivery_recipient.trim().to_string()));
            }
            f.push(("Price".into(), format_price(m.price_cents, m.handled_in_platform)));
        }
        "fansite" => {
            if let (Some(y), Some(mo)) = (m.fansite_year, m.fansite_month) {
                f.push(("FanSite Month".into(), format!("{y}-{mo:02}")));
            }
            f.push(("Scheduled Days".into(), m.fan_days.len().to_string()));
        }
        _ => {}
    }

    f
}

// ---------------------------------------------------------------------------
// Data gathering
// ---------------------------------------------------------------------------

/// `updated_at` of the most recent finished `assemble_master` job — our
/// "Date Processed". None when the bundle hasn't been assembled.
fn assembly_date(conn: &Connection, uid: &str) -> Option<String> {
    conn.query_row(
        "SELECT updated_at FROM jobs
          WHERE bundle_uid = ?1 AND kind = 'assemble_master' AND status = 'done'
          ORDER BY updated_at DESC LIMIT 1",
        params![uid],
        |r| r.get::<_, String>(0),
    )
    .optional()
    .ok()
    .flatten()
}

/// Working path of a specific in-zip file, if extracted.
fn working_path_for(conn: &Connection, uid: &str, in_zip_path: &str) -> Option<String> {
    conn.query_row(
        "SELECT working_path FROM bundle_files WHERE bundle_uid = ?1 AND in_zip_path = ?2",
        params![uid, in_zip_path],
        |r| r.get::<_, Option<String>>(0),
    )
    .optional()
    .ok()
    .flatten()
    .flatten()
    .filter(|p| !p.is_empty())
}

/// Resolve the Description value: typed text verbatim, or — for an audio
/// description — the transcribed + cleaned audio. Degrades to an honest note
/// when transcription isn't possible.
fn resolve_description(conn: &Connection, m: &BundleManifest) -> String {
    match m.description_mode.as_deref() {
        Some("text") => m.description_text.trim().to_string(),
        Some("audio") => {
            let Some(rel) = nonempty(&m.description_audio_path) else {
                return "(audio description — file not recorded)".into();
            };
            match working_path_for(conn, &m.uid, &rel) {
                Some(wp) => match crate::transcribe::transcribe_audio_to_text(Path::new(&wp)) {
                    Ok(text) => {
                        let cleaned = clean_transcript(&text);
                        if cleaned.is_empty() {
                            "(audio description — transcript was empty)".into()
                        } else {
                            cleaned
                        }
                    }
                    Err(_) => "(audio description — transcript unavailable; transcribe engine not installed)".into(),
                },
                None => "(audio description — audio file not found in workspace)".into(),
            }
        }
        _ => m.description_text.trim().to_string(),
    }
}

/// Concatenate every video's `.txt` transcript (in bundle order), cleaned.
fn concat_video_transcripts(conn: &Connection, uid: &str, workspace: &Path) -> String {
    let tx_dir = workspace.join("transcripts");
    let mut raw = String::new();
    let mut stmt = match conn.prepare(
        "SELECT in_zip_path FROM bundle_files
          WHERE bundle_uid = ?1 AND kind = 'video'
          ORDER BY CASE WHEN fansite_day_of_month IS NULL THEN 0 ELSE fansite_day_of_month END,
                   position, in_zip_path",
    ) {
        Ok(s) => s,
        Err(_) => return String::new(),
    };
    let rows = stmt.query_map(params![uid], |r| r.get::<_, String>(0));
    if let Ok(rows) = rows {
        for in_zip in rows.flatten() {
            let stem = Path::new(&in_zip)
                .file_stem()
                .map(|s| s.to_string_lossy().to_string())
                .unwrap_or_default();
            let txt = tx_dir.join(format!("{stem}.txt"));
            if let Ok(content) = fs::read_to_string(&txt) {
                raw.push_str(&content);
                raw.push('\n');
            }
        }
    }
    clean_transcript(&raw)
}

/// Full processing log, oldest-first: (timestamp, level, kind, message).
fn read_full_log(conn: &Connection, uid: &str) -> Vec<(String, String, String, String)> {
    let mut out = Vec::new();
    let Ok(mut stmt) = conn.prepare(
        "SELECT timestamp, level, COALESCE(kind, ''), message
           FROM processing_log WHERE bundle_uid = ?1 ORDER BY id ASC",
    ) else {
        return out;
    };
    if let Ok(rows) = stmt.query_map(params![uid], |r| {
        Ok((
            r.get::<_, String>(0)?,
            r.get::<_, String>(1)?,
            r.get::<_, String>(2)?,
            r.get::<_, String>(3)?,
        ))
    }) {
        for row in rows.flatten() {
            out.push(row);
        }
    }
    out
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

fn heading(text: &str, size: u8) -> impl genpdf::Element {
    elements::Paragraph::new(text).styled(style::Style::new().bold().with_font_size(size))
}

fn kv_line(label: &str, value: &str) -> elements::Paragraph {
    let mut p = elements::Paragraph::default();
    p.push_styled(format!("{label}:  "), style::Style::new().bold());
    p.push(value.to_string());
    p
}

/// Per-file image thumbnails for the no-video fallback, with each file's
/// rotation so the grid can right them.
fn export_thumbs_with_rotation(conn: &Connection, uid: &str) -> Result<Vec<(String, i64)>, BundleError> {
    let mut stmt = conn.prepare(
        "SELECT t.thumbnail_path, f.rotation_degrees
           FROM bundle_export_thumbs t
           JOIN bundle_files f ON f.id = t.bundle_file_id
          WHERE t.bundle_uid = ?1 ORDER BY t.position",
    )?;
    let rows = stmt.query_map(params![uid], |r| Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)?)))?;
    let mut v = Vec::new();
    for r in rows {
        v.push(r?);
    }
    Ok(v)
}

/// Build the grid's embeddable images: prefer N rotation-corrected frames
/// sampled across the bundle's videos; when the bundle has no video, fall back
/// to rotation-corrected per-file image thumbnails.
fn build_grid_images(conn: &Connection, uid: &str, workspace: &Path, count: i64) -> Vec<elements::Image> {
    let frames_dir = workspace.join(".frames");
    let frames = crate::frames::sample_bundle_frames(conn, uid, count, &frames_dir).unwrap_or_default();
    if !frames.is_empty() {
        // ffmpeg already righted these, so embed straight from disk.
        return frames
            .iter()
            .filter_map(|p| elements::Image::from_path(p).ok())
            .map(|i| i.with_dpi(THUMB_DPI).with_alignment(genpdf::Alignment::Center))
            .collect();
    }

    let Ok(thumbs) = export_thumbs_with_rotation(conn, uid) else {
        return Vec::new();
    };
    thumbs
        .iter()
        .filter(|(p, _)| {
            let l = p.to_lowercase();
            l.ends_with(".jpg") || l.ends_with(".jpeg")
        })
        .filter_map(|(p, rot)| {
            let bytes = crate::thumbnails::rotated_jpeg_bytes(Path::new(p), *rot)?;
            elements::Image::from_reader(std::io::Cursor::new(bytes)).ok()
        })
        .map(|i| i.with_dpi(THUMB_DPI).with_alignment(genpdf::Alignment::Center))
        .collect()
}

/// Core builder, separated from the Tauri command so it's exercisable from a
/// thin wrapper. Returns the output path.
fn build_summary<R: Runtime>(handle: &AppHandle<R>, uid: &str) -> Result<PathBuf, BundleError> {
    let conn = open_conn(handle)?;

    // Refresh the export-thumb selection to the configured count so the grid
    // (and the post-bundle that shares it) reflect the current setting.
    let count = bundles::thumb_count(&conn);
    bundles::reselect_export_thumbs(&conn, uid, count)?;

    // Load manifest + working-title override (effective title comes from
    // fetch_bundle_title below).
    let (manifest_json, title_override): (String, String) = conn
        .query_row(
            "SELECT manifest_json, title_override FROM bundles WHERE uid = ?1",
            params![uid],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .optional()?
        .ok_or_else(|| BundleError::NotFound(format!("bundle {uid}")))?;
    let manifest: BundleManifest = serde_json::from_str(&manifest_json).unwrap_or_default();

    let effective_title = bundles::fetch_bundle_title(&conn, uid)?;
    let workspace = crate::extract::bundle_workspace_dir(&bundles::work_root(handle)?, uid);

    let processed_at = assembly_date(&conn, uid);
    let description = resolve_description(&conn, &manifest);
    let assembled = gather_assembled(&workspace, &effective_title);
    let fields = summary_fields(&manifest, &title_override, &description, processed_at.as_deref(), assembled.as_ref());
    let transcript = concat_video_transcripts(&conn, uid, &workspace);
    let log = read_full_log(&conn, uid);

    // ---- Build the document ----
    let font_family = fonts::FontFamily {
        regular: fonts::FontData::new(FONT_REGULAR.to_vec(), None).map_err(|e| pdf_err("font", e))?,
        bold: fonts::FontData::new(FONT_BOLD.to_vec(), None).map_err(|e| pdf_err("font", e))?,
        italic: fonts::FontData::new(FONT_ITALIC.to_vec(), None).map_err(|e| pdf_err("font", e))?,
        bold_italic: fonts::FontData::new(FONT_BOLD_ITALIC.to_vec(), None).map_err(|e| pdf_err("font", e))?,
    };
    let mut doc = genpdf::Document::new(font_family);
    doc.set_title(format!("SideMolly Summary — {effective_title}"));
    doc.set_minimal_conformance();
    doc.set_font_size(11);
    let mut deco = genpdf::SimplePageDecorator::new();
    deco.set_margins(genpdf::Margins::all(12));
    doc.set_page_decorator(deco);

    // Header.
    let persona = manifest.persona_code.clone().unwrap_or_else(|| "—".into());
    doc.push(heading("SideMolly Summary", 20));
    doc.push(
        elements::Paragraph::new(format!("{persona} · {} · {effective_title}", manifest.bundle_type))
            .styled(style::Style::new().italic().with_font_size(11)),
    );
    doc.push(elements::Break::new(1.0));

    // Metadata.
    doc.push(heading("Metadata", 14));
    for (label, value) in &fields {
        doc.push(kv_line(label, value));
    }
    doc.push(elements::Break::new(1.0));

    // Image grid: N rotation-corrected frames sampled across the bundle's
    // videos (falls back to per-file image thumbnails when there are none).
    // Laid out in fixed-width rows, padding the trailing row to GRID_COLS.
    let images = build_grid_images(&conn, uid, &workspace, count);
    if !images.is_empty() {
        doc.push(heading(&format!("Thumbnails ({})", images.len()), 14));
        let mut table = elements::TableLayout::new(vec![1; GRID_COLS]);
        let mut iter = images.into_iter().peekable();
        while iter.peek().is_some() {
            let mut row = table.row();
            for _ in 0..GRID_COLS {
                match iter.next() {
                    Some(img) => row.push_element(img.padded(genpdf::Margins::all(2))),
                    None => row.push_element(elements::Paragraph::new("")),
                }
            }
            row.push().map_err(|e| pdf_err("table row", e))?;
        }
        doc.push(table);
        doc.push(elements::Break::new(1.0));
    }

    // Transcript.
    doc.push(heading("Transcript", 14));
    if transcript.is_empty() {
        doc.push(
            elements::Paragraph::new("(No video transcripts yet — run Transcribe on the Edit tab.)")
                .styled(style::Style::new().italic()),
        );
    } else {
        doc.push(elements::Paragraph::new(transcript));
    }
    doc.push(elements::Break::new(1.0));

    // Processing log.
    doc.push(heading(&format!("Processing log ({})", log.len()), 14));
    if log.is_empty() {
        doc.push(elements::Paragraph::new("(empty)").styled(style::Style::new().italic()));
    } else {
        let small = style::Style::new().with_font_size(8);
        for (ts, level, kind, message) in &log {
            let prefix = if kind.is_empty() {
                format!("{ts}  [{level}]  ")
            } else {
                format!("{ts}  [{level}]  {kind}: ")
            };
            let mut p = elements::Paragraph::default();
            p.push_styled(prefix, small.clone());
            p.push_styled(message.clone(), small.clone());
            doc.push(p);
        }
    }

    // ---- Render ----
    let auto = workspace.join("auto");
    fs::create_dir_all(&auto)?;
    let out_path = auto.join(format!("{} — Summary.pdf", bundles::master_cut_basename(&effective_title)));
    doc.render_to_file(&out_path).map_err(|e| pdf_err("render", e))?;

    crate::processing_log::write(
        &conn,
        Some(uid),
        None,
        Some("summary"),
        crate::processing_log::Level::Info,
        "SideMolly Summary PDF generated",
        None,
        out_path.file_name().and_then(|s| s.to_str()),
    );

    Ok(out_path)
}

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------

#[tauri::command]
pub fn generate_bundle_summary<R: Runtime>(
    handle: AppHandle<R>,
    uid: String,
) -> Result<SummaryResult, BundleError> {
    let path = build_summary(&handle, &uid)?;
    Ok(SummaryResult { output_path: path.to_string_lossy().to_string() })
}

#[tauri::command]
pub fn reveal_bundle_summary<R: Runtime>(
    handle: AppHandle<R>,
    uid: String,
) -> Result<(), BundleError> {
    let conn = open_conn(&handle)?;
    let title = bundles::fetch_bundle_title(&conn, &uid)?;
    let workspace = crate::extract::bundle_workspace_dir(&bundles::work_root(&handle)?, &uid);
    let path = workspace
        .join("auto")
        .join(format!("{} — Summary.pdf", bundles::master_cut_basename(&title)));
    if !path.exists() {
        return Err(BundleError::NotFound(format!("summary PDF for {uid} (generate it first)")));
    }
    crate::fsutil::reveal_in_file_browser(&path)?;
    Ok(())
}

/// Best-effort generation used by the Dropbox copy path: never propagates a
/// failure (a missing transcript or font glitch must not block the master-cut
/// copy). Returns the path on success.
pub fn try_generate_for_dropbox<R: Runtime>(handle: &AppHandle<R>, uid: &str) -> Option<PathBuf> {
    match build_summary(handle, uid) {
        Ok(p) => Some(p),
        Err(e) => {
            eprintln!("[sidemolly] summary generation for {uid} failed (continuing): {e}");
            None
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::manifest::BundleManifest;

    #[test]
    fn clean_transcript_removes_blank_lines_and_double_spaces_sentences() {
        let raw = "hello there.\n\n  \nhow are you?\n";
        assert_eq!(clean_transcript(raw), "Hello there.  How are you?");
    }

    #[test]
    fn clean_transcript_capitalizes_and_adds_terminal_period() {
        assert_eq!(clean_transcript("just some words"), "Just some words.");
        assert_eq!(clean_transcript("a   b.\tc"), "A b.  C.");
    }

    #[test]
    fn clean_transcript_is_idempotent() {
        let once = clean_transcript("hi there. how ARE you?  fine.");
        assert_eq!(clean_transcript(&once), once);
    }

    #[test]
    fn clean_transcript_empty_input() {
        assert_eq!(clean_transcript("   \n\n  "), "");
    }

    #[test]
    fn embedded_fonts_load_and_render_a_pdf() {
        // De-risks the bundled Liberation Sans TTFs + the genpdf render path
        // without needing an AppHandle: build a tiny document and confirm it
        // writes a non-empty `%PDF` file.
        let font_family = fonts::FontFamily {
            regular: fonts::FontData::new(FONT_REGULAR.to_vec(), None).unwrap(),
            bold: fonts::FontData::new(FONT_BOLD.to_vec(), None).unwrap(),
            italic: fonts::FontData::new(FONT_ITALIC.to_vec(), None).unwrap(),
            bold_italic: fonts::FontData::new(FONT_BOLD_ITALIC.to_vec(), None).unwrap(),
        };
        let mut doc = genpdf::Document::new(font_family);
        doc.set_minimal_conformance();
        doc.push(heading("SideMolly Summary smoke", 16));
        doc.push(elements::Paragraph::new("Hello — rendered with the bundled font."));

        let dir = tempfile::TempDir::new().unwrap();
        let out = dir.path().join("smoke.pdf");
        doc.render_to_file(&out).expect("genpdf should render with the embedded fonts");

        let bytes = std::fs::read(&out).unwrap();
        assert!(bytes.len() > 200, "rendered PDF should be non-trivial");
        assert_eq!(&bytes[..4], b"%PDF", "output should be a PDF");
    }

    #[test]
    fn format_price_variants() {
        assert_eq!(format_price(Some(4900), false), "$49.00");
        assert_eq!(format_price(Some(500), false), "$5.00");
        assert_eq!(format_price(None, true), "Handled in platform");
        assert_eq!(format_price(Some(4900), true), "Handled in platform");
        assert_eq!(format_price(None, false), "—");
    }

    fn content_manifest() -> BundleManifest {
        BundleManifest {
            uid: "u".into(),
            bundle_type: "content".into(),
            title: "My Clip".into(),
            categories: vec!["Solo".into(), "Toys".into()],
            go_live_date: Some("2026-06-10".into()),
            ..Default::default()
        }
    }

    #[test]
    fn summary_fields_content_shows_base_fields() {
        let m = content_manifest();
        let f = summary_fields(&m, "", "A short blurb", Some("2026-06-02T10:00:00"), None);
        let map: std::collections::HashMap<_, _> = f.iter().cloned().collect();
        assert_eq!(map.get("Title").unwrap(), "My Clip");
        assert_eq!(map.get("Description").unwrap(), "A short blurb");
        assert_eq!(map.get("Categories").unwrap(), "Solo, Toys");
        assert_eq!(map.get("Go-Live Date").unwrap(), "2026-06-10");
        assert_eq!(map.get("Date Processed").unwrap(), "2026-06-02T10:00:00");
        assert!(!map.contains_key("Working title"), "no override → no working-title row");
        assert!(!map.contains_key("Price"), "content bundle has no price row");
    }

    #[test]
    fn summary_fields_working_title_only_when_overridden() {
        let m = content_manifest();
        // Override equal to original → not shown.
        let same = summary_fields(&m, "My Clip", "", None, None);
        assert!(!same.iter().any(|(k, _)| k == "Working title"));
        // Distinct override → shown.
        let diff = summary_fields(&m, "Better Name", "", None, None);
        let row = diff.iter().find(|(k, _)| k == "Working title").unwrap();
        assert_eq!(row.1, "Better Name");
    }

    #[test]
    fn summary_fields_custom_shows_delivery_and_price() {
        let m = BundleManifest {
            uid: "c".into(),
            bundle_type: "custom".into(),
            title: "Order #42".into(),
            delivery_kind: Some("site".into()),
            delivery_site_name: Some("C4S messages".into()),
            delivery_recipient: "@buyer".into(),
            price_cents: Some(4900),
            ..Default::default()
        };
        let f = summary_fields(&m, "", "", None, None);
        let map: std::collections::HashMap<_, _> = f.iter().cloned().collect();
        assert_eq!(map.get("Site").unwrap(), "C4S messages");
        assert_eq!(map.get("Deliver to").unwrap(), "@buyer");
        assert_eq!(map.get("Price").unwrap(), "$49.00");
    }

    #[test]
    fn summary_fields_custom_handled_in_platform() {
        let m = BundleManifest {
            bundle_type: "custom".into(),
            title: "Order".into(),
            handled_in_platform: true,
            ..Default::default()
        };
        let f = summary_fields(&m, "", "", None, None);
        let map: std::collections::HashMap<_, _> = f.iter().cloned().collect();
        assert_eq!(map.get("Price").unwrap(), "Handled in platform");
    }

    #[test]
    fn format_duration_mmss_floors_and_pads() {
        assert_eq!(format_duration_mmss(0.0), "00:00");
        assert_eq!(format_duration_mmss(49.7), "00:49");
        assert_eq!(format_duration_mmss(130.0), "02:10");
        assert_eq!(format_duration_mmss(3725.0), "62:05"); // minutes uncapped
    }

    #[test]
    fn format_size_mb_rounds() {
        assert_eq!(format_size_mb(12_582_912), "12.0 MB"); // 12 MiB
        assert_eq!(format_size_mb(0), "0.0 MB");
    }

    #[test]
    fn summary_fields_includes_assembled_details_after_date_processed() {
        let m = content_manifest();
        let info = AssembledInfo {
            filename: "My Clip.mp4".into(),
            size_mb: "12.4 MB".into(),
            length: "01:23".into(),
            sha256: "abc123".into(),
        };
        let f = summary_fields(&m, "", "", Some("2026-06-02T10:00:00"), Some(&info));
        let labels: Vec<&str> = f.iter().map(|(k, _)| k.as_str()).collect();
        let dp = labels.iter().position(|&l| l == "Date Processed").unwrap();
        // Assembled rows land immediately after Date Processed, in order.
        assert_eq!(&labels[dp + 1..dp + 5], &["Assembled file", "File size", "Length", "SHA-256"]);
        let map: std::collections::HashMap<_, _> = f.iter().cloned().collect();
        assert_eq!(map.get("File size").unwrap(), "12.4 MB");
        assert_eq!(map.get("Length").unwrap(), "01:23");
        assert_eq!(map.get("SHA-256").unwrap(), "abc123");
    }

    #[test]
    fn summary_fields_omits_assembled_when_absent() {
        let m = content_manifest();
        let f = summary_fields(&m, "", "", None, None);
        assert!(!f.iter().any(|(k, _)| k == "Assembled file"));
    }
}

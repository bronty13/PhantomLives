// Phase 13: Notes. Folders + notes + tags + attachments. CRUD is in
// pure helpers (take `&Connection`) so they're cheap to unit-test;
// the `#[tauri::command]` wrappers open the DB, resolve app_data, and
// delegate. Mirrors the pattern in bundles.rs / site_credentials.rs.

use std::fs;
use std::path::{Path, PathBuf};
use std::time::Duration;

use rusqlite::{params, Connection};
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Manager, Runtime};
use uuid::Uuid;

use crate::crypto::CryptoError;

// ----- DB connection helper --------------------------------------------------

fn open_conn(app_data: &Path) -> Result<Connection, CryptoError> {
    let db_path = app_data.join("molly.db");
    let conn = Connection::open(&db_path)
        .map_err(|e| CryptoError::Db(format!("open {}: {e}", db_path.display())))?;
    conn.busy_timeout(Duration::from_secs(5))?;
    conn.execute_batch("PRAGMA foreign_keys = ON;")?;
    Ok(conn)
}

fn app_data_dir<R: Runtime>(handle: &AppHandle<R>) -> Result<PathBuf, CryptoError> {
    handle
        .path()
        .app_data_dir()
        .map_err(|e| CryptoError::Internal(format!("app_data_dir: {e}")))
}

// ----- Public types ----------------------------------------------------------

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NoteFolder {
    pub id: i64,
    pub parent_id: Option<i64>,
    pub name: String,
    pub sort_order: i64,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NoteSummary {
    pub id: i64,
    pub folder_id: Option<i64>,
    pub title: String,
    pub paper_color: Option<String>,
    pub font_family: Option<String>,
    pub updated_at: String,
    pub last_edited_at: String,
    pub tag_ids: Vec<i64>,
    pub attachment_count: i64,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Note {
    pub id: i64,
    pub folder_id: Option<i64>,
    pub title: String,
    pub content_html: String,
    pub content_text: String,
    pub paper_color: Option<String>,
    pub font_family: Option<String>,
    pub created_at: String,
    pub updated_at: String,
    pub last_edited_at: String,
    pub tag_ids: Vec<i64>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NoteTag {
    pub id: i64,
    pub name: String,
    pub color: String,
    pub sort_order: i64,
    pub is_builtin: bool,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NoteAttachment {
    pub id: i64,
    pub note_id: i64,
    pub filename: String,
    pub original_name: String,
    pub mime: String,
    pub size_bytes: i64,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FindHit {
    pub note_id: i64,
    pub note_title: String,
    pub folder_id: Option<i64>,
    pub line_no: i64,
    pub snippet: String, // ~80 chars of context around the match
}

// ----- Pure folder CRUD ------------------------------------------------------

pub(crate) fn pure_list_folders(conn: &Connection) -> Result<Vec<NoteFolder>, CryptoError> {
    let mut stmt = conn.prepare(
        "SELECT id, parent_id, name, sort_order, created_at, updated_at
         FROM note_folders
         ORDER BY parent_id IS NULL DESC, parent_id, sort_order, name COLLATE NOCASE",
    )?;
    let rows = stmt
        .query_map([], |r| {
            Ok(NoteFolder {
                id: r.get(0)?,
                parent_id: r.get(1)?,
                name: r.get(2)?,
                sort_order: r.get(3)?,
                created_at: r.get(4)?,
                updated_at: r.get(5)?,
            })
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(rows)
}

pub(crate) fn pure_create_folder(
    conn: &Connection,
    parent_id: Option<i64>,
    name: &str,
) -> Result<i64, CryptoError> {
    if name.trim().is_empty() {
        return Err(CryptoError::Internal("folder name required".into()));
    }
    if let Some(pid) = parent_id {
        // Validate parent exists to avoid silent dangling rows when the
        // FK enforcement happens to be relaxed (in-memory test DBs).
        let exists: i64 = conn
            .query_row("SELECT COUNT(*) FROM note_folders WHERE id = ?1", params![pid], |r| r.get(0))?;
        if exists == 0 {
            return Err(CryptoError::Internal(format!("parent folder {pid} not found")));
        }
    }
    let next_order: i64 = conn
        .query_row(
            "SELECT COALESCE(MAX(sort_order), 0) + 1 FROM note_folders
             WHERE parent_id IS ?1",
            params![parent_id],
            |r| r.get(0),
        )
        .unwrap_or(1);
    conn.execute(
        "INSERT INTO note_folders (parent_id, name, sort_order) VALUES (?1, ?2, ?3)",
        params![parent_id, name.trim(), next_order],
    )?;
    Ok(conn.last_insert_rowid())
}

pub(crate) fn pure_rename_folder(
    conn: &Connection,
    folder_id: i64,
    name: &str,
) -> Result<(), CryptoError> {
    if name.trim().is_empty() {
        return Err(CryptoError::Internal("folder name required".into()));
    }
    conn.execute(
        "UPDATE note_folders SET name = ?1, updated_at = datetime('now') WHERE id = ?2",
        params![name.trim(), folder_id],
    )?;
    Ok(())
}

pub(crate) fn pure_move_folder(
    conn: &Connection,
    folder_id: i64,
    new_parent_id: Option<i64>,
) -> Result<(), CryptoError> {
    // Cycle prevention: the new parent must not be folder_id itself or
    // any of its descendants. Walk up from new_parent_id; if we hit
    // folder_id, reject.
    if let Some(mut anc) = new_parent_id {
        loop {
            if anc == folder_id {
                return Err(CryptoError::Internal(
                    "can't move a folder into itself or one of its children".into(),
                ));
            }
            let parent: Option<i64> = conn
                .query_row(
                    "SELECT parent_id FROM note_folders WHERE id = ?1",
                    params![anc],
                    |r| r.get(0),
                )
                .ok()
                .flatten();
            match parent {
                Some(p) => anc = p,
                None => break,
            }
        }
    }
    conn.execute(
        "UPDATE note_folders SET parent_id = ?1, updated_at = datetime('now') WHERE id = ?2",
        params![new_parent_id, folder_id],
    )?;
    Ok(())
}

pub(crate) fn pure_delete_folder(conn: &Connection, folder_id: i64) -> Result<(), CryptoError> {
    // FK cascade handles notes + sub-folders + tag links + attachment rows.
    // Callers responsible for cleaning attachment FILES on disk separately
    // (they need the app_data path, which this pure helper doesn't have).
    conn.execute("DELETE FROM note_folders WHERE id = ?1", params![folder_id])?;
    Ok(())
}

// ----- Pure note CRUD --------------------------------------------------------

pub(crate) fn pure_list_notes(
    conn: &Connection,
    folder_id: Option<i64>,
) -> Result<Vec<NoteSummary>, CryptoError> {
    let mut stmt = conn.prepare(
        "SELECT id, folder_id, title, paper_color, font_family, updated_at, last_edited_at
         FROM notes
         WHERE folder_id IS ?1
         ORDER BY last_edited_at DESC, id DESC",
    )?;
    let raw: Vec<(i64, Option<i64>, String, Option<String>, Option<String>, String, String)> =
        stmt.query_map(params![folder_id], |r| {
            Ok((
                r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?, r.get(5)?, r.get(6)?,
            ))
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;

    // Fetch tag_ids + attachment_count per note in two cheap follow-up
    // queries. For Sallie's volume the N+1 cost is fine; switch to a
    // single GROUP_CONCAT if it ever becomes hot.
    let mut out = Vec::with_capacity(raw.len());
    for (id, folder_id, title, paper_color, font_family, updated_at, last_edited_at) in raw {
        let tag_ids = pure_note_tag_ids(conn, id)?;
        let attachment_count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM note_attachments WHERE note_id = ?1",
                params![id],
                |r| r.get(0),
            )
            .unwrap_or(0);
        out.push(NoteSummary {
            id, folder_id, title, paper_color, font_family,
            updated_at, last_edited_at, tag_ids, attachment_count,
        });
    }
    Ok(out)
}

pub(crate) fn pure_get_note(conn: &Connection, note_id: i64) -> Result<Note, CryptoError> {
    let row: (i64, Option<i64>, String, String, String, Option<String>, Option<String>, String, String, String) =
        conn.query_row(
            "SELECT id, folder_id, title, content_html, content_text, paper_color, font_family,
                    created_at, updated_at, last_edited_at
             FROM notes WHERE id = ?1",
            params![note_id],
            |r| Ok((
                r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?,
                r.get(5)?, r.get(6)?, r.get(7)?, r.get(8)?, r.get(9)?,
            )),
        )?;
    let tag_ids = pure_note_tag_ids(conn, note_id)?;
    Ok(Note {
        id: row.0, folder_id: row.1, title: row.2, content_html: row.3, content_text: row.4,
        paper_color: row.5, font_family: row.6,
        created_at: row.7, updated_at: row.8, last_edited_at: row.9, tag_ids,
    })
}

pub(crate) fn pure_create_note(
    conn: &Connection,
    folder_id: Option<i64>,
    title: &str,
) -> Result<i64, CryptoError> {
    let safe_title = if title.trim().is_empty() { "Untitled" } else { title.trim() };
    conn.execute(
        "INSERT INTO notes (folder_id, title) VALUES (?1, ?2)",
        params![folder_id, safe_title],
    )?;
    Ok(conn.last_insert_rowid())
}

pub(crate) fn pure_update_note(
    conn: &Connection,
    note_id: i64,
    title: &str,
    content_html: &str,
    content_text: &str,
) -> Result<(), CryptoError> {
    conn.execute(
        "UPDATE notes
         SET title = ?1, content_html = ?2, content_text = ?3,
             updated_at = datetime('now'), last_edited_at = datetime('now')
         WHERE id = ?4",
        params![title, content_html, content_text, note_id],
    )?;
    Ok(())
}

pub(crate) fn pure_set_note_style(
    conn: &Connection,
    note_id: i64,
    font_family: Option<&str>,
    paper_color: Option<&str>,
) -> Result<(), CryptoError> {
    conn.execute(
        "UPDATE notes SET font_family = ?1, paper_color = ?2, updated_at = datetime('now')
         WHERE id = ?3",
        params![font_family, paper_color, note_id],
    )?;
    Ok(())
}

pub(crate) fn pure_move_note(
    conn: &Connection,
    note_id: i64,
    new_folder_id: Option<i64>,
) -> Result<(), CryptoError> {
    conn.execute(
        "UPDATE notes SET folder_id = ?1, updated_at = datetime('now') WHERE id = ?2",
        params![new_folder_id, note_id],
    )?;
    Ok(())
}

pub(crate) fn pure_delete_note(conn: &Connection, note_id: i64) -> Result<(), CryptoError> {
    conn.execute("DELETE FROM notes WHERE id = ?1", params![note_id])?;
    Ok(())
}

pub(crate) fn pure_copy_note(conn: &Connection, note_id: i64) -> Result<i64, CryptoError> {
    let src = pure_get_note(conn, note_id)?;
    conn.execute(
        "INSERT INTO notes (folder_id, title, content_html, content_text, paper_color, font_family)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
        params![
            src.folder_id,
            format!("{} (copy)", src.title),
            src.content_html,
            src.content_text,
            src.paper_color,
            src.font_family,
        ],
    )?;
    let new_id = conn.last_insert_rowid();
    // Carry the tag set forward.
    for tid in src.tag_ids {
        conn.execute(
            "INSERT OR IGNORE INTO note_tag_links (note_id, tag_id) VALUES (?1, ?2)",
            params![new_id, tid],
        )?;
    }
    Ok(new_id)
}

// ----- Pure tag CRUD ---------------------------------------------------------

pub(crate) fn pure_list_tags(conn: &Connection) -> Result<Vec<NoteTag>, CryptoError> {
    let mut stmt = conn.prepare(
        "SELECT id, name, color, sort_order, is_builtin
         FROM note_tags_def ORDER BY sort_order, name COLLATE NOCASE",
    )?;
    let rows = stmt
        .query_map([], |r| {
            Ok(NoteTag {
                id: r.get(0)?,
                name: r.get(1)?,
                color: r.get(2)?,
                sort_order: r.get(3)?,
                is_builtin: r.get::<_, i64>(4)? != 0,
            })
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(rows)
}

pub(crate) fn pure_create_tag(
    conn: &Connection,
    name: &str,
    color: &str,
) -> Result<i64, CryptoError> {
    if name.trim().is_empty() {
        return Err(CryptoError::Internal("tag name required".into()));
    }
    let next_order: i64 = conn
        .query_row("SELECT COALESCE(MAX(sort_order), 0) + 1 FROM note_tags_def", [], |r| r.get(0))
        .unwrap_or(1);
    conn.execute(
        "INSERT INTO note_tags_def (name, color, sort_order, is_builtin) VALUES (?1, ?2, ?3, 0)",
        params![name.trim(), color, next_order],
    )?;
    Ok(conn.last_insert_rowid())
}

pub(crate) fn pure_update_tag(
    conn: &Connection,
    tag_id: i64,
    name: &str,
    color: &str,
) -> Result<(), CryptoError> {
    if name.trim().is_empty() {
        return Err(CryptoError::Internal("tag name required".into()));
    }
    conn.execute(
        "UPDATE note_tags_def SET name = ?1, color = ?2, updated_at = datetime('now')
         WHERE id = ?3",
        params![name.trim(), color, tag_id],
    )?;
    Ok(())
}

pub(crate) fn pure_delete_tag(conn: &Connection, tag_id: i64) -> Result<(), CryptoError> {
    let is_builtin: i64 = conn
        .query_row(
            "SELECT is_builtin FROM note_tags_def WHERE id = ?1",
            params![tag_id],
            |r| r.get(0),
        )
        .unwrap_or(0);
    if is_builtin != 0 {
        return Err(CryptoError::Internal(
            "built-in tags can be renamed and recoloured but not deleted".into(),
        ));
    }
    conn.execute("DELETE FROM note_tags_def WHERE id = ?1", params![tag_id])?;
    Ok(())
}

pub(crate) fn pure_note_tag_ids(conn: &Connection, note_id: i64) -> Result<Vec<i64>, CryptoError> {
    let mut stmt = conn.prepare(
        "SELECT tag_id FROM note_tag_links WHERE note_id = ?1 ORDER BY tag_id",
    )?;
    let rows = stmt
        .query_map(params![note_id], |r| r.get::<_, i64>(0))?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(rows)
}

pub(crate) fn pure_set_note_tags(
    conn: &Connection,
    note_id: i64,
    tag_ids: &[i64],
) -> Result<(), CryptoError> {
    conn.execute("DELETE FROM note_tag_links WHERE note_id = ?1", params![note_id])?;
    for tid in tag_ids {
        conn.execute(
            "INSERT OR IGNORE INTO note_tag_links (note_id, tag_id) VALUES (?1, ?2)",
            params![note_id, tid],
        )?;
    }
    conn.execute(
        "UPDATE notes SET updated_at = datetime('now') WHERE id = ?1",
        params![note_id],
    )?;
    Ok(())
}

// ----- Search (titles + folder names) + Find (note bodies) -------------------

/// Title-and-folder-name search. Plain substring (case-insensitive)
/// when `regex` is false; full regex when true.
pub(crate) fn pure_search_titles(
    conn: &Connection,
    query: &str,
    regex: bool,
) -> Result<Vec<NoteSummary>, CryptoError> {
    if query.trim().is_empty() {
        return Ok(Vec::new());
    }
    if regex {
        let re = regex::RegexBuilder::new(query)
            .case_insensitive(true)
            .build()
            .map_err(|e| CryptoError::Internal(format!("regex: {e}")))?;
        // Naive: fetch all titles, filter in Rust. Sallie's volume makes
        // this fine; if it ever isn't, switch to SQLite's REGEXP scalar
        // function registration.
        let mut stmt = conn.prepare(
            "SELECT id FROM notes ORDER BY last_edited_at DESC, id DESC",
        )?;
        let ids: Vec<i64> = stmt
            .query_map([], |r| r.get::<_, i64>(0))?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        let mut out = Vec::new();
        for id in ids {
            let n = pure_get_note(conn, id)?;
            if re.is_match(&n.title) {
                out.push(NoteSummary {
                    id: n.id, folder_id: n.folder_id, title: n.title,
                    paper_color: n.paper_color, font_family: n.font_family,
                    updated_at: n.updated_at.clone(),
                    last_edited_at: n.last_edited_at,
                    tag_ids: n.tag_ids,
                    attachment_count: conn
                        .query_row(
                            "SELECT COUNT(*) FROM note_attachments WHERE note_id = ?1",
                            params![n.id], |r| r.get(0),
                        )
                        .unwrap_or(0),
                });
            }
        }
        Ok(out)
    } else {
        let pat = format!("%{}%", query.trim().replace('%', "\\%").replace('_', "\\_"));
        let mut stmt = conn.prepare(
            "SELECT id FROM notes WHERE title LIKE ?1 ESCAPE '\\'
             ORDER BY last_edited_at DESC, id DESC",
        )?;
        let ids: Vec<i64> = stmt
            .query_map(params![pat], |r| r.get::<_, i64>(0))?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        let mut out = Vec::new();
        for id in ids {
            let n = pure_get_note(conn, id)?;
            out.push(NoteSummary {
                id: n.id, folder_id: n.folder_id, title: n.title,
                paper_color: n.paper_color, font_family: n.font_family,
                updated_at: n.updated_at.clone(), last_edited_at: n.last_edited_at,
                tag_ids: n.tag_ids,
                attachment_count: conn
                    .query_row(
                        "SELECT COUNT(*) FROM note_attachments WHERE note_id = ?1",
                        params![n.id], |r| r.get(0),
                    )
                    .unwrap_or(0),
            });
        }
        Ok(out)
    }
}

/// Find phrase in note bodies. Returns up to 5 hits per note with line
/// number + ~80-char snippet. `regex` toggles literal-substring vs
/// regex matching (case-insensitive in both modes).
pub(crate) fn pure_find_in_bodies(
    conn: &Connection,
    query: &str,
    regex: bool,
) -> Result<Vec<FindHit>, CryptoError> {
    if query.trim().is_empty() {
        return Ok(Vec::new());
    }
    let re = if regex {
        Some(
            regex::RegexBuilder::new(query)
                .case_insensitive(true)
                .build()
                .map_err(|e| CryptoError::Internal(format!("regex: {e}")))?,
        )
    } else {
        None
    };
    let lowered = query.trim().to_lowercase();

    let mut stmt = conn.prepare(
        "SELECT id, folder_id, title, content_text FROM notes
         WHERE content_text != ''",
    )?;
    let rows = stmt
        .query_map([], |r| {
            Ok((
                r.get::<_, i64>(0)?,
                r.get::<_, Option<i64>>(1)?,
                r.get::<_, String>(2)?,
                r.get::<_, String>(3)?,
            ))
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;

    let mut hits = Vec::new();
    for (note_id, folder_id, title, body) in rows {
        let mut per_note = 0;
        for (line_idx, line) in body.lines().enumerate() {
            if per_note >= 5 {
                break;
            }
            let matched = match &re {
                Some(re) => re.is_match(line),
                None => line.to_lowercase().contains(&lowered),
            };
            if matched {
                hits.push(FindHit {
                    note_id,
                    note_title: title.clone(),
                    folder_id,
                    line_no: (line_idx + 1) as i64,
                    snippet: snippet_around(line, &lowered, &re),
                });
                per_note += 1;
            }
        }
    }
    Ok(hits)
}

fn snippet_around(line: &str, lowered_needle: &str, re: &Option<regex::Regex>) -> String {
    const PAD: usize = 40;
    let lower = line.to_lowercase();
    let match_start = match re {
        Some(re) => re.find(line).map(|m| m.start()),
        None => lower.find(lowered_needle),
    };
    let center = match_start.unwrap_or(0);
    let chars: Vec<char> = line.chars().collect();
    // Convert byte index to char index approximately.
    let center_char = line[..center.min(line.len())].chars().count();
    let start = center_char.saturating_sub(PAD);
    let end = (center_char + PAD).min(chars.len());
    let mut out: String = chars[start..end].iter().collect();
    if start > 0 { out.insert_str(0, "…"); }
    if end < chars.len() { out.push('…'); }
    out
}

// ----- App-wide note defaults (font + paper colour) --------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NoteDefaults {
    pub default_font: String,
    pub default_paper_color: String,
}

pub(crate) fn pure_load_defaults(conn: &Connection) -> Result<NoteDefaults, CryptoError> {
    let load = |k: &str, fallback: &str| -> String {
        conn.query_row(
            "SELECT value FROM app_settings WHERE key = ?1",
            params![k],
            |r| r.get::<_, String>(0),
        )
        .unwrap_or_else(|_| fallback.to_string())
    };
    Ok(NoteDefaults {
        default_font: load("notes.defaultFont", "Paper Daisy"),
        default_paper_color: load("notes.defaultPaperColor", "#fdfcf8"),
    })
}

pub(crate) fn pure_save_defaults(
    conn: &Connection,
    defaults: &NoteDefaults,
) -> Result<(), CryptoError> {
    conn.execute(
        "INSERT INTO app_settings (key, value) VALUES ('notes.defaultFont', ?1)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        params![defaults.default_font],
    )?;
    conn.execute(
        "INSERT INTO app_settings (key, value) VALUES ('notes.defaultPaperColor', ?1)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        params![defaults.default_paper_color],
    )?;
    Ok(())
}

// ----- Tauri commands --------------------------------------------------------

#[tauri::command]
pub fn list_note_folders<R: Runtime>(handle: AppHandle<R>) -> Result<Vec<NoteFolder>, CryptoError> {
    pure_list_folders(&open_conn(&app_data_dir(&handle)?)?)
}

#[tauri::command]
pub fn create_note_folder<R: Runtime>(
    handle: AppHandle<R>,
    parent_id: Option<i64>,
    name: String,
) -> Result<i64, CryptoError> {
    pure_create_folder(&open_conn(&app_data_dir(&handle)?)?, parent_id, &name)
}

#[tauri::command]
pub fn rename_note_folder<R: Runtime>(
    handle: AppHandle<R>,
    folder_id: i64,
    name: String,
) -> Result<(), CryptoError> {
    pure_rename_folder(&open_conn(&app_data_dir(&handle)?)?, folder_id, &name)
}

#[tauri::command]
pub fn move_note_folder<R: Runtime>(
    handle: AppHandle<R>,
    folder_id: i64,
    new_parent_id: Option<i64>,
) -> Result<(), CryptoError> {
    pure_move_folder(&open_conn(&app_data_dir(&handle)?)?, folder_id, new_parent_id)
}

#[tauri::command]
pub fn delete_note_folder<R: Runtime>(
    handle: AppHandle<R>,
    folder_id: i64,
) -> Result<(), CryptoError> {
    pure_delete_folder(&open_conn(&app_data_dir(&handle)?)?, folder_id)
}

#[tauri::command]
pub fn list_notes<R: Runtime>(
    handle: AppHandle<R>,
    folder_id: Option<i64>,
) -> Result<Vec<NoteSummary>, CryptoError> {
    pure_list_notes(&open_conn(&app_data_dir(&handle)?)?, folder_id)
}

#[tauri::command]
pub fn get_note<R: Runtime>(handle: AppHandle<R>, note_id: i64) -> Result<Note, CryptoError> {
    pure_get_note(&open_conn(&app_data_dir(&handle)?)?, note_id)
}

#[tauri::command]
pub fn create_note<R: Runtime>(
    handle: AppHandle<R>,
    folder_id: Option<i64>,
    title: String,
) -> Result<i64, CryptoError> {
    pure_create_note(&open_conn(&app_data_dir(&handle)?)?, folder_id, &title)
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdateNotePayload {
    pub note_id: i64,
    pub title: String,
    pub content_html: String,
    pub content_text: String,
}

#[tauri::command]
pub fn update_note<R: Runtime>(
    handle: AppHandle<R>,
    payload: UpdateNotePayload,
) -> Result<(), CryptoError> {
    pure_update_note(
        &open_conn(&app_data_dir(&handle)?)?,
        payload.note_id, &payload.title, &payload.content_html, &payload.content_text,
    )
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NoteStylePayload {
    pub note_id: i64,
    pub font_family: Option<String>,
    pub paper_color: Option<String>,
}

#[tauri::command]
pub fn set_note_style<R: Runtime>(
    handle: AppHandle<R>,
    payload: NoteStylePayload,
) -> Result<(), CryptoError> {
    pure_set_note_style(
        &open_conn(&app_data_dir(&handle)?)?,
        payload.note_id,
        payload.font_family.as_deref(),
        payload.paper_color.as_deref(),
    )
}

#[tauri::command]
pub fn move_note<R: Runtime>(
    handle: AppHandle<R>,
    note_id: i64,
    new_folder_id: Option<i64>,
) -> Result<(), CryptoError> {
    pure_move_note(&open_conn(&app_data_dir(&handle)?)?, note_id, new_folder_id)
}

#[tauri::command]
pub fn delete_note<R: Runtime>(handle: AppHandle<R>, note_id: i64) -> Result<(), CryptoError> {
    pure_delete_note(&open_conn(&app_data_dir(&handle)?)?, note_id)
}

#[tauri::command]
pub fn copy_note<R: Runtime>(handle: AppHandle<R>, note_id: i64) -> Result<i64, CryptoError> {
    pure_copy_note(&open_conn(&app_data_dir(&handle)?)?, note_id)
}

#[tauri::command]
pub fn set_note_tags<R: Runtime>(
    handle: AppHandle<R>,
    note_id: i64,
    tag_ids: Vec<i64>,
) -> Result<(), CryptoError> {
    pure_set_note_tags(&open_conn(&app_data_dir(&handle)?)?, note_id, &tag_ids)
}

#[tauri::command]
pub fn list_note_tags<R: Runtime>(handle: AppHandle<R>) -> Result<Vec<NoteTag>, CryptoError> {
    pure_list_tags(&open_conn(&app_data_dir(&handle)?)?)
}

#[tauri::command]
pub fn create_note_tag<R: Runtime>(
    handle: AppHandle<R>,
    name: String,
    color: String,
) -> Result<i64, CryptoError> {
    pure_create_tag(&open_conn(&app_data_dir(&handle)?)?, &name, &color)
}

#[tauri::command]
pub fn update_note_tag<R: Runtime>(
    handle: AppHandle<R>,
    tag_id: i64,
    name: String,
    color: String,
) -> Result<(), CryptoError> {
    pure_update_tag(&open_conn(&app_data_dir(&handle)?)?, tag_id, &name, &color)
}

#[tauri::command]
pub fn delete_note_tag<R: Runtime>(
    handle: AppHandle<R>,
    tag_id: i64,
) -> Result<(), CryptoError> {
    pure_delete_tag(&open_conn(&app_data_dir(&handle)?)?, tag_id)
}

#[tauri::command]
pub fn search_note_titles<R: Runtime>(
    handle: AppHandle<R>,
    query: String,
    regex: bool,
) -> Result<Vec<NoteSummary>, CryptoError> {
    pure_search_titles(&open_conn(&app_data_dir(&handle)?)?, &query, regex)
}

#[tauri::command]
pub fn find_in_notes<R: Runtime>(
    handle: AppHandle<R>,
    query: String,
    regex: bool,
) -> Result<Vec<FindHit>, CryptoError> {
    pure_find_in_bodies(&open_conn(&app_data_dir(&handle)?)?, &query, regex)
}

#[tauri::command]
pub fn get_note_defaults<R: Runtime>(handle: AppHandle<R>) -> Result<NoteDefaults, CryptoError> {
    pure_load_defaults(&open_conn(&app_data_dir(&handle)?)?)
}

#[tauri::command]
pub fn set_note_defaults<R: Runtime>(
    handle: AppHandle<R>,
    defaults: NoteDefaults,
) -> Result<(), CryptoError> {
    pure_save_defaults(&open_conn(&app_data_dir(&handle)?)?, &defaults)
}

// ----- Attachments -----------------------------------------------------------

fn note_attachments_dir(app_data: &Path, note_id: i64) -> PathBuf {
    app_data.join("note_attachments").join(note_id.to_string())
}

fn sanitize_basename(s: &str) -> String {
    s.chars()
        .map(|c| match c {
            '/' | '\\' | ':' | '\0' | '?' | '*' | '"' | '<' | '>' | '|' => '_',
            _ => c,
        })
        .collect()
}

#[tauri::command]
pub fn save_note_attachment<R: Runtime>(
    handle: AppHandle<R>,
    note_id: i64,
    src_path: String,
) -> Result<NoteAttachment, CryptoError> {
    let app_data = app_data_dir(&handle)?;
    let src = Path::new(&src_path);
    if !src.is_file() {
        return Err(CryptoError::Internal(format!("not a file: {src_path}")));
    }
    let original = src
        .file_name()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_else(|| "attachment".into());
    let safe = sanitize_basename(&original);
    let uuid = Uuid::new_v4().simple().to_string();
    let stored = format!("{uuid}_{safe}");
    let target_dir = note_attachments_dir(&app_data, note_id);
    fs::create_dir_all(&target_dir).map_err(|e| CryptoError::Internal(format!("mkdir: {e}")))?;
    let target = target_dir.join(&stored);
    fs::copy(src, &target).map_err(|e| CryptoError::Internal(format!("copy: {e}")))?;
    let meta = fs::metadata(&target).map_err(|e| CryptoError::Internal(format!("stat: {e}")))?;
    let mime = guess_mime(&original);

    let conn = open_conn(&app_data)?;
    conn.execute(
        "INSERT INTO note_attachments (note_id, filename, original_name, mime, size_bytes)
         VALUES (?1, ?2, ?3, ?4, ?5)",
        params![note_id, stored, original, mime, meta.len() as i64],
    )?;
    let new_id = conn.last_insert_rowid();
    let row: NoteAttachment = conn.query_row(
        "SELECT id, note_id, filename, original_name, mime, size_bytes, created_at
         FROM note_attachments WHERE id = ?1",
        params![new_id],
        |r| Ok(NoteAttachment {
            id: r.get(0)?, note_id: r.get(1)?, filename: r.get(2)?, original_name: r.get(3)?,
            mime: r.get(4)?, size_bytes: r.get(5)?, created_at: r.get(6)?,
        }),
    )?;
    // Touch the parent note so the middle pane shows the updated paper-clip count.
    conn.execute("UPDATE notes SET updated_at = datetime('now') WHERE id = ?1", params![note_id])?;
    Ok(row)
}

#[tauri::command]
pub fn list_note_attachments<R: Runtime>(
    handle: AppHandle<R>,
    note_id: i64,
) -> Result<Vec<NoteAttachment>, CryptoError> {
    let conn = open_conn(&app_data_dir(&handle)?)?;
    let mut stmt = conn.prepare(
        "SELECT id, note_id, filename, original_name, mime, size_bytes, created_at
         FROM note_attachments WHERE note_id = ?1 ORDER BY id ASC",
    )?;
    let rows = stmt
        .query_map(params![note_id], |r| Ok(NoteAttachment {
            id: r.get(0)?, note_id: r.get(1)?, filename: r.get(2)?, original_name: r.get(3)?,
            mime: r.get(4)?, size_bytes: r.get(5)?, created_at: r.get(6)?,
        }))?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(rows)
}

#[tauri::command]
pub fn delete_note_attachment<R: Runtime>(
    handle: AppHandle<R>,
    attachment_id: i64,
) -> Result<(), CryptoError> {
    let app_data = app_data_dir(&handle)?;
    let conn = open_conn(&app_data)?;
    let row: Option<(i64, String)> = conn
        .query_row(
            "SELECT note_id, filename FROM note_attachments WHERE id = ?1",
            params![attachment_id],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .ok();
    if let Some((note_id, filename)) = row {
        let p = note_attachments_dir(&app_data, note_id).join(&filename);
        let _ = fs::remove_file(&p);
        conn.execute(
            "DELETE FROM note_attachments WHERE id = ?1",
            params![attachment_id],
        )?;
        conn.execute("UPDATE notes SET updated_at = datetime('now') WHERE id = ?1", params![note_id])?;
    }
    Ok(())
}

#[tauri::command]
pub fn open_note_attachment<R: Runtime>(
    handle: AppHandle<R>,
    attachment_id: i64,
) -> Result<(), CryptoError> {
    let path = resolve_attachment_path(&handle, attachment_id)?;
    #[cfg(target_os = "macos")]
    { std::process::Command::new("open").arg(&path).spawn()
        .map_err(|e| CryptoError::Internal(format!("open: {e}")))?; }
    #[cfg(target_os = "windows")]
    { std::process::Command::new("cmd").args(["/C", "start", "", &path.to_string_lossy()]).spawn()
        .map_err(|e| CryptoError::Internal(format!("start: {e}")))?; }
    #[cfg(all(not(target_os = "macos"), not(target_os = "windows")))]
    { std::process::Command::new("xdg-open").arg(&path).spawn()
        .map_err(|e| CryptoError::Internal(format!("xdg-open: {e}")))?; }
    Ok(())
}

#[tauri::command]
pub fn download_note_attachment<R: Runtime>(
    handle: AppHandle<R>,
    attachment_id: i64,
    dest_path: String,
) -> Result<(), CryptoError> {
    let src = resolve_attachment_path(&handle, attachment_id)?;
    let dst = Path::new(&dest_path);
    if let Some(parent) = dst.parent() {
        let _ = fs::create_dir_all(parent);
    }
    fs::copy(&src, dst).map_err(|e| CryptoError::Internal(format!("copy: {e}")))?;
    Ok(())
}

fn resolve_attachment_path<R: Runtime>(
    handle: &AppHandle<R>,
    attachment_id: i64,
) -> Result<PathBuf, CryptoError> {
    let app_data = app_data_dir(handle)?;
    let conn = open_conn(&app_data)?;
    let (note_id, filename): (i64, String) = conn.query_row(
        "SELECT note_id, filename FROM note_attachments WHERE id = ?1",
        params![attachment_id],
        |r| Ok((r.get(0)?, r.get(1)?)),
    )?;
    let p = note_attachments_dir(&app_data, note_id).join(filename);
    if !p.is_file() {
        return Err(CryptoError::Internal(format!(
            "attachment file missing at {}",
            p.display()
        )));
    }
    Ok(p)
}

fn guess_mime(name: &str) -> String {
    let ext = Path::new(name)
        .extension()
        .and_then(|s| s.to_str())
        .unwrap_or("")
        .to_lowercase();
    match ext.as_str() {
        "png" => "image/png",
        "jpg" | "jpeg" => "image/jpeg",
        "gif" => "image/gif",
        "webp" => "image/webp",
        "heic" => "image/heic",
        "pdf" => "application/pdf",
        "txt" | "md" => "text/plain",
        "html" | "htm" => "text/html",
        "json" => "application/json",
        "csv" => "text/csv",
        "zip" => "application/zip",
        "mp4" | "m4v" => "video/mp4",
        "mov" => "video/quicktime",
        "mp3" => "audio/mpeg",
        "wav" => "audio/wav",
        _ => "application/octet-stream",
    }.into()
}

// ----- Tests -----------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use rusqlite::Connection;

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
            include_str!("../migrations/018_crypto_keystore.sql"),
            include_str!("../migrations/019_site_credentials.sql"),
            include_str!("../migrations/020_background_jobs.sql"),
            include_str!("../migrations/021_keystore_stay_unlocked.sql"),
            include_str!("../migrations/022_job_run_log_path.sql"),
            include_str!("../migrations/023_notes.sql"),
        ] {
            conn.execute_batch(sql).unwrap();
        }
        conn
    }

    #[test]
    fn defaults_seeded_from_migration() {
        let conn = fresh_db();
        let d = pure_load_defaults(&conn).unwrap();
        assert_eq!(d.default_font, "Paper Daisy");
        assert_eq!(d.default_paper_color, "#fdfcf8");
    }

    #[test]
    fn seven_default_tags_seeded() {
        let conn = fresh_db();
        let tags = pure_list_tags(&conn).unwrap();
        assert_eq!(tags.len(), 6, "expected 6 built-in tags");
        let names: Vec<&str> = tags.iter().map(|t| t.name.as_str()).collect();
        assert!(names.contains(&"ideas"));
        assert!(names.contains(&"bettereveryday"));
        for t in &tags { assert!(t.is_builtin); }
    }

    #[test]
    fn folder_create_then_list_then_rename() {
        let conn = fresh_db();
        let id = pure_create_folder(&conn, None, "Marketing").unwrap();
        let folders = pure_list_folders(&conn).unwrap();
        assert_eq!(folders.len(), 1);
        assert_eq!(folders[0].name, "Marketing");
        pure_rename_folder(&conn, id, "Promos").unwrap();
        let folders = pure_list_folders(&conn).unwrap();
        assert_eq!(folders[0].name, "Promos");
    }

    #[test]
    fn folder_move_into_self_rejected() {
        let conn = fresh_db();
        let root = pure_create_folder(&conn, None, "Root").unwrap();
        let child = pure_create_folder(&conn, Some(root), "Child").unwrap();
        // Moving root under itself or under its descendant must fail.
        assert!(pure_move_folder(&conn, root, Some(root)).is_err());
        assert!(pure_move_folder(&conn, root, Some(child)).is_err());
        // Moving child under root is fine.
        pure_move_folder(&conn, child, Some(root)).unwrap();
    }

    #[test]
    fn delete_folder_cascades_notes() {
        let conn = fresh_db();
        let f = pure_create_folder(&conn, None, "X").unwrap();
        let _n = pure_create_note(&conn, Some(f), "hi").unwrap();
        let notes = pure_list_notes(&conn, Some(f)).unwrap();
        assert_eq!(notes.len(), 1);
        pure_delete_folder(&conn, f).unwrap();
        let notes = pure_list_notes(&conn, Some(f)).unwrap();
        assert_eq!(notes.len(), 0);
    }

    #[test]
    fn note_create_update_then_get_roundtrip() {
        let conn = fresh_db();
        let id = pure_create_note(&conn, None, "Hello").unwrap();
        pure_update_note(&conn, id, "Hello updated", "<p>body</p>", "body").unwrap();
        let n = pure_get_note(&conn, id).unwrap();
        assert_eq!(n.title, "Hello updated");
        assert_eq!(n.content_text, "body");
    }

    #[test]
    fn note_copy_carries_tags() {
        let conn = fresh_db();
        let n = pure_create_note(&conn, None, "A").unwrap();
        let tags = pure_list_tags(&conn).unwrap();
        let chosen = vec![tags[0].id, tags[1].id];
        pure_set_note_tags(&conn, n, &chosen).unwrap();
        let copy = pure_copy_note(&conn, n).unwrap();
        let copy_note = pure_get_note(&conn, copy).unwrap();
        assert_eq!(copy_note.title, "A (copy)");
        let mut got = copy_note.tag_ids;
        got.sort();
        let mut want = chosen;
        want.sort();
        assert_eq!(got, want);
    }

    #[test]
    fn cannot_delete_builtin_tag() {
        let conn = fresh_db();
        let tags = pure_list_tags(&conn).unwrap();
        let builtin = tags.iter().find(|t| t.is_builtin).unwrap();
        assert!(pure_delete_tag(&conn, builtin.id).is_err());
    }

    #[test]
    fn user_tag_can_be_deleted() {
        let conn = fresh_db();
        let id = pure_create_tag(&conn, "custom-tag", "#abcdef").unwrap();
        pure_delete_tag(&conn, id).unwrap();
    }

    #[test]
    fn search_titles_plain_substring() {
        let conn = fresh_db();
        let _ = pure_create_note(&conn, None, "Buy milk").unwrap();
        let _ = pure_create_note(&conn, None, "Promo ideas").unwrap();
        let _ = pure_create_note(&conn, None, "Roadmap").unwrap();
        let hits = pure_search_titles(&conn, "promo", false).unwrap();
        assert_eq!(hits.len(), 1);
        assert_eq!(hits[0].title, "Promo ideas");
    }

    #[test]
    fn search_titles_regex() {
        let conn = fresh_db();
        let _ = pure_create_note(&conn, None, "Buy milk").unwrap();
        let _ = pure_create_note(&conn, None, "Buy eggs").unwrap();
        let _ = pure_create_note(&conn, None, "Sell bonds").unwrap();
        let hits = pure_search_titles(&conn, "^Buy", true).unwrap();
        assert_eq!(hits.len(), 2);
    }

    #[test]
    fn find_in_bodies_returns_line_numbers() {
        let conn = fresh_db();
        let id = pure_create_note(&conn, None, "Plans").unwrap();
        pure_update_note(
            &conn, id, "Plans", "<p>line 1</p><p>second-line</p><p>third</p>",
            "line 1\nsecond-line\nthird",
        ).unwrap();
        let hits = pure_find_in_bodies(&conn, "second", false).unwrap();
        assert_eq!(hits.len(), 1);
        assert_eq!(hits[0].line_no, 2);
        assert!(hits[0].snippet.contains("second-line"));
    }

    #[test]
    fn find_in_bodies_caps_at_5_per_note() {
        let conn = fresh_db();
        let id = pure_create_note(&conn, None, "Repeats").unwrap();
        let body: String = (0..20).map(|_| "hello\n").collect();
        pure_update_note(&conn, id, "Repeats", "<p>...</p>", &body).unwrap();
        let hits = pure_find_in_bodies(&conn, "hello", false).unwrap();
        assert_eq!(hits.len(), 5);
    }

    #[test]
    fn defaults_save_then_load() {
        let conn = fresh_db();
        pure_save_defaults(&conn, &NoteDefaults {
            default_font: "Caveat".into(),
            default_paper_color: "#ffe4ec".into(),
        }).unwrap();
        let d = pure_load_defaults(&conn).unwrap();
        assert_eq!(d.default_font, "Caveat");
        assert_eq!(d.default_paper_color, "#ffe4ec");
    }

    #[test]
    fn per_note_style_overrides_persist() {
        let conn = fresh_db();
        let id = pure_create_note(&conn, None, "Pink note").unwrap();
        pure_set_note_style(&conn, id, Some("Indie Flower"), Some("#ffe4ec")).unwrap();
        let n = pure_get_note(&conn, id).unwrap();
        assert_eq!(n.font_family.as_deref(), Some("Indie Flower"));
        assert_eq!(n.paper_color.as_deref(), Some("#ffe4ec"));
        // Setting back to NULL is "use defaults."
        pure_set_note_style(&conn, id, None, None).unwrap();
        let n = pure_get_note(&conn, id).unwrap();
        assert!(n.font_family.is_none());
        assert!(n.paper_color.is_none());
    }
}

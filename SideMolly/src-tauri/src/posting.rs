// Phase 7 — posting primitives.
//
// The user's own platform list (posting_targets) + the per-bundle
// checklist state (bundle_postings). Phases 8-10 layer flavor-specific
// runners (Content / Custom / FanSite) on top of these primitives —
// the underlying CRUD + URL-template resolution lives here.
//
// `target.kind` filters which bundles see which target:
//   content / custom / fansite — match the corresponding
//     bundle.bundle_type exactly
//   any                        — show on every bundle
//
// URL template resolution mirrors the Dropbox folder template
// (decision #21 / Phase 6 follow-up): {uid}, {title}, {persona},
// {date}. Variables not present in the template are simply left as
// literal text in the URL string (so a non-template URL like
// "https://example.com/login" passes through unchanged).

use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Manager, Runtime};

use crate::bundles::BundleError;

// ---------------------------------------------------------------------------
// posting_targets
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PostingTarget {
    pub id: i64,
    pub name: String,
    pub url_template: String,
    pub persona_code: Option<String>,
    pub color: String,
    pub icon: String,
    pub position: i64,
    pub kind: String,           // 'content'|'custom'|'fansite'|'any'
    pub enabled: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct PostingTargetInput {
    pub name: String,
    #[serde(default)] pub url_template: String,
    #[serde(default)] pub persona_code: Option<String>,
    #[serde(default = "default_color")] pub color: String,
    #[serde(default = "default_icon")]  pub icon: String,
    #[serde(default = "default_position")] pub position: i64,
    #[serde(default = "default_kind")]  pub kind: String,
    #[serde(default = "default_true")]  pub enabled: bool,
}

fn default_color()    -> String { "#888888".into() }
fn default_icon()     -> String { "🎯".into() }
fn default_position() -> i64    { 100 }
fn default_kind()     -> String { "any".into() }
fn default_true()     -> bool   { true }

#[tauri::command]
pub fn list_posting_targets<R: Runtime>(
    handle: AppHandle<R>,
) -> Result<Vec<PostingTarget>, BundleError> {
    let conn = open_conn(&handle)?;
    let mut stmt = conn.prepare(
        "SELECT id, name, url_template, persona_code, color, icon,
                position, kind, enabled
           FROM posting_targets
          ORDER BY position, name",
    )?;
    let rows = stmt
        .query_map([], |r| Ok(PostingTarget {
            id: r.get(0)?,
            name: r.get(1)?,
            url_template: r.get(2)?,
            persona_code: r.get(3)?,
            color: r.get(4)?,
            icon: r.get(5)?,
            position: r.get(6)?,
            kind: r.get(7)?,
            enabled: r.get::<_, i64>(8)? != 0,
        }))?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(rows)
}

#[tauri::command]
pub fn create_posting_target<R: Runtime>(
    handle: AppHandle<R>,
    target: PostingTargetInput,
) -> Result<i64, BundleError> {
    validate_kind(&target.kind)?;
    let conn = open_conn(&handle)?;
    conn.execute(
        "INSERT INTO posting_targets
            (name, url_template, persona_code, color, icon, position, kind, enabled)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
        params![
            target.name, target.url_template, target.persona_code,
            target.color, target.icon, target.position, target.kind,
            if target.enabled { 1 } else { 0 },
        ],
    )?;
    Ok(conn.last_insert_rowid())
}

#[tauri::command]
pub fn update_posting_target<R: Runtime>(
    handle: AppHandle<R>,
    id: i64,
    target: PostingTargetInput,
) -> Result<(), BundleError> {
    validate_kind(&target.kind)?;
    let conn = open_conn(&handle)?;
    let n = conn.execute(
        "UPDATE posting_targets
            SET name = ?1, url_template = ?2, persona_code = ?3,
                color = ?4, icon = ?5, position = ?6, kind = ?7,
                enabled = ?8, updated_at = datetime('now')
          WHERE id = ?9",
        params![
            target.name, target.url_template, target.persona_code,
            target.color, target.icon, target.position, target.kind,
            if target.enabled { 1 } else { 0 }, id,
        ],
    )?;
    if n == 0 {
        return Err(BundleError::NotFound(format!("target {id}")));
    }
    Ok(())
}

#[tauri::command]
pub fn delete_posting_target<R: Runtime>(
    handle: AppHandle<R>,
    id: i64,
) -> Result<(), BundleError> {
    let conn = open_conn(&handle)?;
    conn.execute("DELETE FROM posting_targets WHERE id = ?1", params![id])?;
    Ok(())
}

fn validate_kind(k: &str) -> Result<(), BundleError> {
    match k {
        "content" | "custom" | "fansite" | "any" => Ok(()),
        other => Err(BundleError::Io(std::io::Error::other(
            format!("invalid kind '{other}'; must be content|custom|fansite|any"),
        ))),
    }
}

// ---------------------------------------------------------------------------
// bundle_postings
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BundlePosting {
    pub id: i64,
    pub bundle_uid: String,
    pub target_id: i64,
    pub state: String,                  // pending|scheduled|posted|skipped
    pub posted_at: Option<String>,
    pub posted_url: Option<String>,
    pub body_override: Option<String>,
    pub notes: Option<String>,
    pub updated_at: String,
}

/// A target + its current posting row for a bundle. The frontend
/// renders one card per target, with state from the posting row (or
/// default 'pending' when no row exists yet). Resolved URL string is
/// computed server-side so the user just clicks Open.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PostingCard {
    pub target: PostingTarget,
    pub posting: Option<BundlePosting>,
    pub resolved_url: String,
}

#[tauri::command]
pub fn list_bundle_postings<R: Runtime>(
    handle: AppHandle<R>,
    uid: String,
) -> Result<Vec<PostingCard>, BundleError> {
    let conn = open_conn(&handle)?;

    // Bundle lookup for URL template resolution.
    let bundle: Option<(String, String, Option<String>, String)> = conn.query_row(
        "SELECT bundle_type, COALESCE(title, ''), persona_code, ingested_at
           FROM bundles WHERE uid = ?1",
        params![uid],
        |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)),
    ).optional()?;
    let (bundle_type, title, persona_code, ingested_at) = bundle
        .ok_or_else(|| BundleError::NotFound(format!("bundle {uid}")))?;
    let date = ingested_at.split(' ').next().unwrap_or("").to_string();

    // Pull all enabled targets whose `kind` matches the bundle type
    // (or is 'any'). Persona-filter: a target with persona_code set
    // only shows for bundles of that persona. Persona_code NULL on
    // the target = shows for everyone.
    let mut stmt = conn.prepare(
        "SELECT id, name, url_template, persona_code, color, icon,
                position, kind, enabled
           FROM posting_targets
          WHERE enabled = 1
            AND (kind = 'any' OR kind = ?1)
            AND (persona_code IS NULL OR persona_code = ?2)
          ORDER BY position, name",
    )?;
    let targets: Vec<PostingTarget> = stmt
        .query_map(params![bundle_type, persona_code.clone().unwrap_or_default()], |r| Ok(PostingTarget {
            id: r.get(0)?,
            name: r.get(1)?,
            url_template: r.get(2)?,
            persona_code: r.get(3)?,
            color: r.get(4)?,
            icon: r.get(5)?,
            position: r.get(6)?,
            kind: r.get(7)?,
            enabled: r.get::<_, i64>(8)? != 0,
        }))?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    drop(stmt);

    // For each, look up the bundle_postings row (if any) and resolve
    // the URL template.
    let mut out: Vec<PostingCard> = Vec::with_capacity(targets.len());
    for t in targets {
        let posting: Option<BundlePosting> = conn.query_row(
            "SELECT id, bundle_uid, target_id, state, posted_at, posted_url,
                    body_override, notes, updated_at
               FROM bundle_postings
              WHERE bundle_uid = ?1 AND target_id = ?2",
            params![uid, t.id],
            |r| Ok(BundlePosting {
                id: r.get(0)?,
                bundle_uid: r.get(1)?,
                target_id: r.get(2)?,
                state: r.get(3)?,
                posted_at: r.get(4)?,
                posted_url: r.get(5)?,
                body_override: r.get(6)?,
                notes: r.get(7)?,
                updated_at: r.get(8)?,
            }),
        ).optional()?;

        let resolved_url = resolve_url_template(
            &t.url_template,
            &uid, &title, persona_code.as_deref(), &date,
        );
        out.push(PostingCard { target: t, posting, resolved_url });
    }
    Ok(out)
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct UpsertBundlePostingInput {
    pub bundle_uid: String,
    pub target_id: i64,
    pub state: String,
    #[serde(default)] pub posted_at: Option<String>,
    #[serde(default)] pub posted_url: Option<String>,
    #[serde(default)] pub body_override: Option<String>,
    #[serde(default)] pub notes: Option<String>,
}

#[tauri::command]
pub fn upsert_bundle_posting<R: Runtime>(
    handle: AppHandle<R>,
    input: UpsertBundlePostingInput,
) -> Result<(), BundleError> {
    if !["pending","scheduled","posted","skipped"].contains(&input.state.as_str()) {
        return Err(BundleError::Io(std::io::Error::other(
            format!("invalid state '{}'", input.state),
        )));
    }
    let conn = open_conn(&handle)?;
    conn.execute(
        "INSERT INTO bundle_postings
            (bundle_uid, target_id, state, posted_at, posted_url,
             body_override, notes, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, datetime('now'))
         ON CONFLICT(bundle_uid, target_id) DO UPDATE SET
            state         = excluded.state,
            posted_at     = excluded.posted_at,
            posted_url    = excluded.posted_url,
            body_override = excluded.body_override,
            notes         = excluded.notes,
            updated_at    = datetime('now')",
        params![
            input.bundle_uid, input.target_id, input.state,
            input.posted_at, input.posted_url, input.body_override, input.notes,
        ],
    )?;
    Ok(())
}

#[tauri::command]
pub fn mark_posted<R: Runtime>(
    handle: AppHandle<R>,
    bundle_uid: String,
    target_id: i64,
    posted_url: Option<String>,
) -> Result<(), BundleError> {
    let conn = open_conn(&handle)?;
    conn.execute(
        "INSERT INTO bundle_postings
            (bundle_uid, target_id, state, posted_at, posted_url, updated_at)
         VALUES (?1, ?2, 'posted', datetime('now'), ?3, datetime('now'))
         ON CONFLICT(bundle_uid, target_id) DO UPDATE SET
            state      = 'posted',
            posted_at  = COALESCE(bundle_postings.posted_at, datetime('now')),
            posted_url = COALESCE(?3, bundle_postings.posted_url),
            updated_at = datetime('now')",
        params![bundle_uid, target_id, posted_url],
    )?;
    Ok(())
}

// ---------------------------------------------------------------------------
// URL template resolution
// ---------------------------------------------------------------------------

/// Replace template variables in a URL string. Variables not present
/// in the template pass through unchanged. URL-encode the bundle's
/// title since it may contain spaces / punctuation that need escaping
/// for a query string.
pub fn resolve_url_template(
    template: &str,
    uid: &str,
    title: &str,
    persona: Option<&str>,
    date: &str,
) -> String {
    let persona_str = persona.unwrap_or("");
    let mut out = template.to_string();
    out = out.replace("{uid}", &url_encode(uid));
    out = out.replace("{title}", &url_encode(title));
    out = out.replace("{persona}", &url_encode(persona_str));
    out = out.replace("{date}", &url_encode(date));
    out
}

/// Minimal URL-encoder for the subset of chars that show up in
/// PhantomLives titles. Avoids pulling in the `urlencoding` crate
/// for what amounts to a token-replacement on user-set URLs.
fn url_encode(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for b in s.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9'
            | b'-' | b'_' | b'.' | b'~' => out.push(b as char),
            b' ' => out.push_str("%20"),
            _ => out.push_str(&format!("%{:02X}", b)),
        }
    }
    out
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn open_conn<R: Runtime>(handle: &AppHandle<R>) -> Result<Connection, BundleError> {
    let dir = handle.path()
        .resolve("", tauri::path::BaseDirectory::AppLocalData)
        .map_err(|e| BundleError::Io(std::io::Error::other(format!("appdata path: {e}"))))?;
    Ok(Connection::open(dir.join("sidemolly.db"))?)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn url_template_resolves_every_variable() {
        let out = resolve_url_template(
            "https://example.com/{persona}/{date}/{uid}?title={title}",
            "2026-05-22-0002",
            "Mary Poppins",
            Some("CoC"),
            "2026-05-22",
        );
        assert_eq!(
            out,
            "https://example.com/CoC/2026-05-22/2026-05-22-0002?title=Mary%20Poppins",
        );
    }

    #[test]
    fn url_template_without_vars_passes_through() {
        let out = resolve_url_template(
            "https://example.com/login",
            "u", "t", Some("p"), "2026-05-22",
        );
        assert_eq!(out, "https://example.com/login");
    }

    #[test]
    fn url_encode_handles_special_chars() {
        assert_eq!(url_encode("hello world"), "hello%20world");
        assert_eq!(url_encode("a&b=c"), "a%26b%3Dc");
        assert_eq!(url_encode("Mary Poppins"), "Mary%20Poppins");
        assert_eq!(url_encode("Robert's clip"), "Robert%27s%20clip");
    }

    #[test]
    fn validate_kind_accepts_known_values() {
        assert!(validate_kind("any").is_ok());
        assert!(validate_kind("content").is_ok());
        assert!(validate_kind("custom").is_ok());
        assert!(validate_kind("fansite").is_ok());
        assert!(validate_kind("nonsense").is_err());
    }
}

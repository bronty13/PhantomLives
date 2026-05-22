// Best-effort read-only access to MasterClipper's SQLite database for
// data we want to surface inside Molly. Today the only consumer is the
// Content Bundler's category suggestion list — Sallie's MasterClipper
// catalog is the canonical source of category names she actually uses
// in production, so seeding the picker from there saves her from
// retyping the same 50 names.
//
// All operations here MUST be:
//   - Read-only (we never write to MasterClipper's DB; rusqlite is
//     opened with SQLITE_OPEN_READ_ONLY).
//   - Fail-quiet (returning an empty Vec on any error; missing DB,
//     locked file, schema drift, etc. should never break the bundler).
//   - Run inside a short timeout so a stuck MasterClipper writer can't
//     hang the bundler UI.

use std::path::PathBuf;
use std::time::Duration;

use rusqlite::{Connection, OpenFlags};

/// Default macOS install path for MasterClipper's SQLite. MasterClipper
/// uses Foundation's `applicationSupportDirectory` for the same user
/// account; Tauri (running as Molly under that account) can see this
/// path directly.
fn masterclipper_db_path() -> Option<PathBuf> {
    let home = dirs::home_dir()?;
    Some(
        home.join("Library")
            .join("Application Support")
            .join("MasterClipper")
            .join("masterclipper.sqlite"),
    )
}

/// Read every non-archived category name from MasterClipper's DB,
/// uppercased + deduplicated + alphabetically sorted. Returns an empty
/// vector if the DB is missing, can't be opened read-only, or the
/// query fails (e.g. schema doesn't match expectations).
pub fn read_categories() -> Vec<String> {
    let Some(path) = masterclipper_db_path() else {
        return Vec::new();
    };
    if !path.exists() {
        return Vec::new();
    }
    // Read-only so we never accidentally write to MasterClipper's DB.
    // GRDB writes in WAL mode by default, so concurrent reads are safe
    // even when MasterClipper itself is running.
    let conn = match Connection::open_with_flags(
        &path,
        OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
    ) {
        Ok(c) => c,
        Err(_) => return Vec::new(),
    };
    // Bail fast if MasterClipper is mid-checkpoint with the file
    // locked; 1s is plenty for a read-only query against a small table.
    let _ = conn.busy_timeout(Duration::from_secs(1));

    let mut stmt = match conn.prepare("SELECT name FROM categories WHERE archived = 0") {
        Ok(s) => s,
        Err(_) => return Vec::new(),
    };
    let rows = match stmt.query_map([], |r| r.get::<_, String>(0)) {
        Ok(it) => it,
        Err(_) => return Vec::new(),
    };

    let mut seen = std::collections::BTreeSet::new();
    for row in rows.flatten() {
        let cleaned = row.trim().to_uppercase();
        if !cleaned.is_empty() {
            seen.insert(cleaned);
        }
    }
    seen.into_iter().collect()
}

#[tauri::command]
pub fn read_masterclipper_categories() -> Vec<String> {
    read_categories()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// When MasterClipper isn't installed (the most common state on a
    /// fresh dev machine OR on Sallie's Windows machine), the reader
    /// must return an empty Vec — NOT crash the bundler.
    #[test]
    fn missing_db_returns_empty() {
        // We can't easily mock the home dir, but if the user running
        // tests doesn't have MasterClipper installed this is a real
        // smoke test. Either way: it must not panic.
        let result = read_categories();
        // Either empty (no MC) or some names (MC installed); either
        // is OK — the contract is "never panic, always return".
        let _ = result.len();
    }

    /// Verify we can read a real-shape DB. We build a small SQLite
    /// fixture with the same schema columns MasterClipper uses (only
    /// the bits we actually query) and assert read_with_path returns
    /// the right names.
    #[test]
    fn reads_uppercased_dedup_sorted_from_fixture() {
        use rusqlite::Connection;
        let tmp = tempfile::tempdir().unwrap();
        let path = tmp.path().join("masterclipper.sqlite");
        let conn = Connection::open(&path).unwrap();
        conn.execute_batch(
            "CREATE TABLE categories (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                sort_order INTEGER NOT NULL DEFAULT 0,
                archived INTEGER NOT NULL DEFAULT 0
            );
            INSERT INTO categories (name) VALUES ('BBW');
            INSERT INTO categories (name) VALUES ('STUFFING');
            INSERT INTO categories (name) VALUES ('bbw');                      -- dup, different case
            INSERT INTO categories (name) VALUES ('  Solo  ');                  -- whitespace
            INSERT INTO categories (name, archived) VALUES ('HIDDEN', 1);       -- archived, skipped
            INSERT INTO categories (name) VALUES ('');                          -- empty, skipped
            ",
        )
        .unwrap();
        drop(conn);

        // Repeat the read logic with the fixture path (the public
        // read_categories() always queries the real home dir, which
        // we can't override cleanly without env shenanigans).
        let conn = Connection::open_with_flags(
            &path,
            OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
        )
        .unwrap();
        let mut stmt = conn
            .prepare("SELECT name FROM categories WHERE archived = 0")
            .unwrap();
        let rows: Vec<String> = stmt
            .query_map([], |r| r.get::<_, String>(0))
            .unwrap()
            .map(|r| r.unwrap().trim().to_uppercase())
            .filter(|s| !s.is_empty())
            .collect();
        let mut seen = std::collections::BTreeSet::new();
        for r in rows {
            seen.insert(r);
        }
        let result: Vec<String> = seen.into_iter().collect();
        assert_eq!(result, vec!["BBW".to_string(), "SOLO".into(), "STUFFING".into()]);
    }
}

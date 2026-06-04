mod backup;
mod export;
mod fsutil;

use tauri_plugin_sql::{Migration, MigrationKind};

pub fn run() {
    let migrations = vec![Migration {
        version: 1,
        description: "init",
        sql: include_str!("../migrations/001_init.sql"),
        kind: MigrationKind::Up,
    }];

    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_process::init())
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_updater::Builder::new().build())
        .plugin(
            tauri_plugin_sql::Builder::default()
                .add_migrations("sqlite:purplemind.db", migrations)
                .build(),
        )
        .setup(|app| {
            let handle = app.handle().clone();
            // Auto-backup-on-launch (CLAUDE.md standard). Never throw; log on failure.
            tauri::async_runtime::spawn(async move {
                if let Err(err) = backup::run_on_launch_if_due(&handle).await {
                    eprintln!("[purplemind] launch backup failed: {err}");
                }
            });
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            backup::run_backup_now,
            backup::list_backups,
            backup::test_backup,
            backup::restore_backup,
            backup::reveal_backup_dir,
            backup::reveal_path,
            backup::get_backup_settings,
            backup::set_backup_settings,
            export::export_dir,
            export::save_export,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

// ---------------------------------------------------------------------------
// camelCase boundary contract — every Tauri-IPC struct serialises camelCase.
// Add a test for every new boundary type introduced.
// ---------------------------------------------------------------------------
#[cfg(test)]
mod camel_case_contract {
    use crate::backup::{BackupRow, Settings, VerifyResult};
    use crate::export::ExportResult;
    use serde_json::Value;

    fn assert_camel(value: &Value, type_name: &'static str) {
        let object = value
            .as_object()
            .unwrap_or_else(|| panic!("{type_name} should serialize to a JSON object"));
        for key in object.keys() {
            assert!(
                !key.contains('_'),
                "{type_name}: serialized field `{key}` is snake_case — add #[serde(rename_all = \"camelCase\")] to the struct",
            );
        }
    }

    #[test]
    fn settings_is_camel_case() {
        assert_camel(&serde_json::to_value(Settings::default()).unwrap(), "Settings");
    }

    #[test]
    fn backup_row_is_camel_case() {
        assert_camel(
            &serde_json::to_value(BackupRow {
                path: String::new(),
                filename: String::new(),
                modified_at: String::new(),
                size_bytes: 0,
            })
            .unwrap(),
            "BackupRow",
        );
    }

    #[test]
    fn verify_result_is_camel_case() {
        assert_camel(
            &serde_json::to_value(VerifyResult {
                archive_path: String::new(),
                archive_size: 0,
                file_count: 0,
                total_bytes: 0,
                has_database: false,
                entries: vec![],
            })
            .unwrap(),
            "VerifyResult",
        );
    }

    #[test]
    fn export_result_is_camel_case() {
        assert_camel(
            &serde_json::to_value(ExportResult {
                output_path: String::new(),
                directory: String::new(),
            })
            .unwrap(),
            "ExportResult",
        );
    }
}

// ---------------------------------------------------------------------------
// Migration smoke test: applies every shipped migration to a fresh in-memory
// SQLite database in source order and verifies the expected tables exist and
// the foreign-key cascade is wired.
// ---------------------------------------------------------------------------
#[cfg(test)]
mod migration_smoke {
    use rusqlite::Connection;

    #[test]
    fn all_migrations_apply_cleanly() {
        let conn = Connection::open_in_memory().expect("open :memory:");
        conn.execute_batch("PRAGMA foreign_keys = ON;").unwrap();

        let migrations: &[(u32, &str, &str)] =
            &[(1, "init", include_str!("../migrations/001_init.sql"))];
        for (v, name, sql) in migrations {
            conn.execute_batch(sql)
                .unwrap_or_else(|e| panic!("migration {v} ({name}) failed: {e}"));
        }

        let expected_tables: &[&str] = &["app_settings", "maps", "nodes", "edges"];
        for t in expected_tables {
            let count: i64 = conn
                .query_row(
                    "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name = ?1",
                    rusqlite::params![t],
                    |row| row.get(0),
                )
                .unwrap();
            assert_eq!(count, 1, "table `{t}` should exist after all migrations");
        }

        // Seed row from 001 is present.
        let export_dir: String = conn
            .query_row(
                "SELECT value FROM app_settings WHERE key = 'export_dir'",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(export_dir, "", "export_dir seeds empty (use runtime default)");

        // Deleting a map cascades to its nodes and edges.
        conn.execute(
            "INSERT INTO maps (id, title, created_at, updated_at) VALUES ('m1','M','t','t')",
            [],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO nodes (id, map_id, label, x, y, created_at, updated_at)
             VALUES ('n1','m1','A',0,0,'t','t'), ('n2','m1','B',10,10,'t','t')",
            [],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO edges (id, map_id, source_id, target_id) VALUES ('e1','m1','n1','n2')",
            [],
        )
        .unwrap();
        conn.execute("DELETE FROM maps WHERE id = 'm1'", []).unwrap();
        let nodes_left: i64 = conn
            .query_row("SELECT COUNT(*) FROM nodes", [], |r| r.get(0))
            .unwrap();
        let edges_left: i64 = conn
            .query_row("SELECT COUNT(*) FROM edges", [], |r| r.get(0))
            .unwrap();
        assert_eq!(nodes_left, 0, "deleting a map cascades to nodes");
        assert_eq!(edges_left, 0, "deleting a map cascades to edges");
    }
}

// ---------------------------------------------------------------------------
// Migration immutability guard.
//
// `tauri-plugin-sql` stores a SHA256 of each migration's bytes alongside its
// version row in `_sqlx_migrations`. On every app launch it re-hashes the
// shipped migration files and refuses to start if any hash doesn't match the
// stored value — that's the "migration N was previously applied but has been
// modified" error. This test catches the same case at `cargo test` time so we
// never ship a build that crashes someone's app at launch.
//
// Workflow:
//   - Adding a new migration: this test fails with the new file's hash;
//     paste the suggested line into `EXPECTED_MIGRATION_HASHES`.
//   - Editing an existing migration: this test fails. Don't fix the hash —
//     revert the migration and add a new one to apply your change.
// ---------------------------------------------------------------------------
#[cfg(test)]
mod migration_immutability {
    use sha2::{Digest, Sha256};

    /// Frozen hashes of every shipped migration. Editing a migration after
    /// it's been added to this list is a build break — by design. Append a
    /// new line ONLY when ADDING a new migration file.
    const EXPECTED_MIGRATION_HASHES: &[(u32, &str)] = &[(
        1,
        "6deea4e7d12ce95b8a79b78be1cd1eabc736da83fc07d4798a5612af52686061",
    )];

    /// Source-of-truth for "which migrations ship at compile time". Must stay
    /// aligned with the `migrations` vec in `run()` above + the `migrations`
    /// array in `migration_smoke::all_migrations_apply_cleanly`.
    const MIGRATION_FILES: &[(u32, &str, &str)] =
        &[(1, "001_init.sql", include_str!("../migrations/001_init.sql"))];

    fn sha256_hex(s: &str) -> String {
        let mut h = Sha256::new();
        h.update(s.as_bytes());
        format!("{:x}", h.finalize())
    }

    #[test]
    fn migrations_have_not_been_edited_post_ship() {
        let expected: std::collections::HashMap<u32, &str> =
            EXPECTED_MIGRATION_HASHES.iter().copied().collect();

        let mut problems: Vec<String> = Vec::new();
        for (version, name, sql) in MIGRATION_FILES {
            let hash = sha256_hex(sql);
            match expected.get(version) {
                Some(e) if *e == hash.as_str() => {}
                Some(e) => problems.push(format!(
                    "❌ migration {version} ({name}) HAS BEEN MODIFIED post-ship.\n\
                     \n\
                     Expected hash: {e}\n\
                     Current hash:  {hash}\n\
                     \n\
                     Migrations are immutable once shipped. Revert this file\n\
                     to its previous bytes and add a NEW migration to apply\n\
                     your intended change.",
                )),
                None => problems.push(format!(
                    "❌ migration {version} ({name}) has no expected hash entry.\n\
                     \n\
                     If you just added this migration, append the following\n\
                     line to EXPECTED_MIGRATION_HASHES:\n\
                     \n\
                     \t({version}, \"{hash}\"),",
                )),
            }
        }

        // Detect a hash entry whose file disappeared (rename / deletion).
        for (version, _) in EXPECTED_MIGRATION_HASHES {
            if !MIGRATION_FILES.iter().any(|(v, _, _)| v == version) {
                problems.push(format!(
                    "❌ EXPECTED_MIGRATION_HASHES lists version {version} but no\n\
                     corresponding entry exists in MIGRATION_FILES (was the\n\
                     file deleted or renamed?).",
                ));
            }
        }

        assert!(
            problems.is_empty(),
            "\n\n{}\n\n",
            problems.join("\n\n────────────────────────────────────────\n\n"),
        );
    }
}

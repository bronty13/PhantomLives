mod backup;
mod fsutil;

use tauri_plugin_sql::{Migration, MigrationKind};

pub fn run() {
    let migrations = vec![
        Migration {
            version: 1,
            description: "init",
            sql: include_str!("../migrations/001_init.sql"),
            kind: MigrationKind::Up,
        },
    ];

    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_process::init())
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_updater::Builder::new().build())
        .plugin(
            tauri_plugin_sql::Builder::default()
                .add_migrations("sqlite:sidemolly.db", migrations)
                .build(),
        )
        .setup(|app| {
            let handle = app.handle().clone();
            // Auto-backup-on-launch (CLAUDE.md standard). Never throw; log on failure.
            tauri::async_runtime::spawn(async move {
                if let Err(err) = backup::run_on_launch_if_due(&handle).await {
                    eprintln!("[sidemolly] launch backup failed: {err}");
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
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

// ---------------------------------------------------------------------------
// camelCase boundary contract.
//
// Every struct that crosses the Tauri IPC boundary serializes camelCase via
// `#[serde(rename_all = "camelCase")]`. This test catches a missing rename
// at `cargo test` time instead of silently breaking the frontend.
//
// Add a new test here for every new boundary struct introduced from
// Phase 1 onward.
// ---------------------------------------------------------------------------
#[cfg(test)]
mod camel_case_contract {
    use crate::backup::{BackupRow, Settings, VerifyResult};
    use serde_json::Value;

    fn assert_camel(value: &Value, type_name: &'static str) {
        let object = value.as_object().unwrap_or_else(|| panic!("{type_name} should serialize to a JSON object"));
        for key in object.keys() {
            assert!(
                !key.contains('_'),
                "{type_name}: serialized field `{key}` is snake_case — add #[serde(rename_all = \"camelCase\")] to the struct",
            );
        }
    }

    #[test]
    fn settings_is_camel_case() {
        let v = serde_json::to_value(Settings::default()).unwrap();
        assert_camel(&v, "Settings");
    }

    #[test]
    fn backup_row_is_camel_case() {
        let v = serde_json::to_value(BackupRow {
            path: String::new(),
            filename: String::new(),
            modified_at: String::new(),
            size_bytes: 0,
        }).unwrap();
        assert_camel(&v, "BackupRow");
    }

    #[test]
    fn verify_result_is_camel_case() {
        let v = serde_json::to_value(VerifyResult {
            archive_path: String::new(),
            archive_size: 0,
            file_count: 0,
            total_bytes: 0,
            has_database: false,
            entries: vec![],
        }).unwrap();
        assert_camel(&v, "VerifyResult");
    }
}

// ---------------------------------------------------------------------------
// Migration smoke test: applies every shipped migration to a fresh in-memory
// SQLite database in source order and verifies the expected tables exist.
// ---------------------------------------------------------------------------
#[cfg(test)]
mod migration_smoke {
    use rusqlite::Connection;

    #[test]
    fn all_migrations_apply_cleanly() {
        let conn = Connection::open_in_memory().expect("open :memory:");
        conn.execute_batch("PRAGMA foreign_keys = ON;").unwrap();

        let migrations: &[(u32, &str, &str)] = &[
            (1, "init", include_str!("../migrations/001_init.sql")),
        ];

        for (v, name, sql) in migrations {
            conn.execute_batch(sql)
                .unwrap_or_else(|e| panic!("migration {v} ({name}) failed: {e}"));
        }

        let expected_tables: &[&str] = &["app_settings"];
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
    }
}

mod backup;
mod bundle_io;
mod bundles;
mod extract;
mod fsutil;
mod manifest;
mod thumbnails;
mod watch;

use tauri_plugin_sql::{Migration, MigrationKind};

pub fn run() {
    let migrations = vec![
        Migration {
            version: 1,
            description: "init",
            sql: include_str!("../migrations/001_init.sql"),
            kind: MigrationKind::Up,
        },
        Migration {
            version: 2,
            description: "bundles",
            sql: include_str!("../migrations/002_bundles.sql"),
            kind: MigrationKind::Up,
        },
        Migration {
            version: 3,
            description: "bundle-files",
            sql: include_str!("../migrations/003_bundle_files.sql"),
            kind: MigrationKind::Up,
        },
        Migration {
            version: 4,
            description: "export-thumbs",
            sql: include_str!("../migrations/004_export_thumbs.sql"),
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
            // Phase 1b watched-folder ingest. Runs an initial scan +
            // notify watcher in its own thread; emits `bundle-ingested`
            // events the frontend listens to.
            watch::spawn_watcher(app.handle().clone());
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
            bundles::ingest_bundle,
            bundles::list_bundles,
            bundles::get_bundle,
            bundles::reveal_working_dir,
            bundles::reveal_working_file,
            bundles::read_doc_text,
            bundles::get_export_thumbnails,
            bundles::get_bundle_thumbnails,
            watch::get_watch_settings,
            watch::set_watch_dir,
            watch::scan_watch_dir_now,
            watch::reveal_watch_dir,
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
    use crate::bundle_io::{HashesDoc, HashesFile, HashesInnerZip};
    use crate::bundles::{BundleDetail, BundleFileRow, BundleSummary, ExportThumb, IngestResult};
    use crate::manifest::{BundleManifest, FanDay};
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

    #[test] fn settings_is_camel_case() {
        assert_camel(&serde_json::to_value(Settings::default()).unwrap(), "Settings");
    }

    #[test] fn backup_row_is_camel_case() {
        assert_camel(&serde_json::to_value(BackupRow {
            path: String::new(), filename: String::new(),
            modified_at: String::new(), size_bytes: 0,
        }).unwrap(), "BackupRow");
    }

    #[test] fn verify_result_is_camel_case() {
        assert_camel(&serde_json::to_value(VerifyResult {
            archive_path: String::new(), archive_size: 0,
            file_count: 0, total_bytes: 0, has_database: false,
            entries: vec![],
        }).unwrap(), "VerifyResult");
    }

    #[test] fn ingest_result_is_camel_case() {
        assert_camel(&serde_json::to_value(IngestResult {
            uid: String::new(), bundle_type: String::new(),
            persona_code: None, title: String::new(),
            verify_status: String::new(), file_count: 0,
            manifest_source: String::new(),
            workspace_path: String::new(), extracted_count: 0,
            thumbnail_count: 0, export_thumb_count: 0,
        }).unwrap(), "IngestResult");
    }

    #[test] fn export_thumb_is_camel_case() {
        assert_camel(&serde_json::to_value(ExportThumb {
            position: 1,
            source_in_zip_path: String::new(),
            thumbnail_path: String::new(),
        }).unwrap(), "ExportThumb");
    }

    #[test] fn bundle_summary_is_camel_case() {
        assert_camel(&serde_json::to_value(BundleSummary {
            uid: String::new(), bundle_type: String::new(),
            persona_code: None, title: String::new(),
            ingested_at: String::new(), verify_status: String::new(),
            bundle_state: String::new(), file_count: 0,
            source_zip_path: String::new(),
        }).unwrap(), "BundleSummary");
    }

    #[test] fn bundle_file_row_is_camel_case() {
        assert_camel(&serde_json::to_value(BundleFileRow {
            in_zip_path: String::new(), original_name: String::new(),
            kind: String::new(), position: 0,
            fansite_day_of_month: None, sha256: String::new(),
            size_bytes: 0,
            working_path: None, thumbnail_path: None,
        }).unwrap(), "BundleFileRow");
    }

    #[test] fn bundle_detail_is_camel_case() {
        assert_camel(&serde_json::to_value(BundleDetail {
            summary: BundleSummary {
                uid: String::new(), bundle_type: String::new(),
                persona_code: None, title: String::new(),
                ingested_at: String::new(), verify_status: String::new(),
                bundle_state: String::new(), file_count: 0,
                source_zip_path: String::new(),
            },
            manifest: BundleManifest::default(),
            files: vec![],
        }).unwrap(), "BundleDetail");
    }

    #[test] fn bundle_manifest_is_camel_case() {
        assert_camel(&serde_json::to_value(BundleManifest::default()).unwrap(), "BundleManifest");
    }

    #[test] fn fan_day_is_camel_case() {
        assert_camel(&serde_json::to_value(FanDay::default()).unwrap(), "FanDay");
    }

    #[test] fn hashes_doc_is_camel_case() {
        assert_camel(&serde_json::to_value(HashesDoc {
            bundle_uid: String::new(),
            inner_zip: HashesInnerZip { name: String::new(), sha256: String::new(), bytes: 0 },
            files: vec![],
        }).unwrap(), "HashesDoc");
    }

    #[test] fn hashes_inner_zip_is_camel_case() {
        assert_camel(&serde_json::to_value(HashesInnerZip {
            name: String::new(), sha256: String::new(), bytes: 0,
        }).unwrap(), "HashesInnerZip");
    }

    #[test] fn hashes_file_is_camel_case() {
        assert_camel(&serde_json::to_value(HashesFile {
            path: String::new(), sha256: String::new(),
        }).unwrap(), "HashesFile");
    }

    use crate::watch::{ScanResult, WatchSettings};

    #[test] fn watch_settings_is_camel_case() {
        assert_camel(&serde_json::to_value(WatchSettings {
            configured_path: String::new(),
            resolved_path: String::new(),
            using_default: true,
        }).unwrap(), "WatchSettings");
    }

    #[test] fn scan_result_is_camel_case() {
        assert_camel(&serde_json::to_value(ScanResult {
            scanned_path: String::new(),
            considered: 0, ingested: 0, skipped: 0, failed: 0,
            errors: vec![],
        }).unwrap(), "ScanResult");
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
            (1, "init",           include_str!("../migrations/001_init.sql")),
            (2, "bundles",        include_str!("../migrations/002_bundles.sql")),
            (3, "bundle-files",   include_str!("../migrations/003_bundle_files.sql")),
            (4, "export-thumbs",  include_str!("../migrations/004_export_thumbs.sql")),
        ];

        for (v, name, sql) in migrations {
            conn.execute_batch(sql)
                .unwrap_or_else(|e| panic!("migration {v} ({name}) failed: {e}"));
        }

        let expected_tables: &[&str] = &[
            "app_settings", "bundles", "bundle_files", "bundle_export_thumbs",
        ];
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

        // bundles CHECK constraints are real (reject 'nonsense' for bundle_type).
        let bad = conn.execute(
            "INSERT INTO bundles (uid, bundle_type, source_zip_path, manifest_json)
             VALUES ('x', 'nonsense', '/x', '{}')",
            [],
        );
        assert!(bad.is_err(), "CHECK on bundle_type should reject 'nonsense'");

        // bundle_files CHECK constraints likewise.
        conn.execute(
            "INSERT INTO bundles (uid, bundle_type, source_zip_path, manifest_json)
             VALUES ('ok', 'content', '/ok', '{}')",
            [],
        ).unwrap();
        let bad_kind = conn.execute(
            "INSERT INTO bundle_files (bundle_uid, in_zip_path, original_name,
                                       kind, sha256)
             VALUES ('ok', 'x', 'x', 'nonsense', 'sha')",
            [],
        );
        assert!(bad_kind.is_err(), "CHECK on bundle_files.kind should reject 'nonsense'");
    }
}

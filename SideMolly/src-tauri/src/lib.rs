mod auto_assemble;
mod backup;
mod bundle_io;
mod bundles;
mod extract;
mod fsutil;
mod images;
mod jobs;
mod manifest;
mod thumbnails;
mod video;
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
        Migration {
            version: 5,
            description: "image-ops",
            sql: include_str!("../migrations/005_image_ops.sql"),
            kind: MigrationKind::Up,
        },
        Migration {
            version: 6,
            description: "jobs",
            sql: include_str!("../migrations/006_jobs.sql"),
            kind: MigrationKind::Up,
        },
        Migration {
            version: 7,
            description: "video-processed-files",
            sql: include_str!("../migrations/007_video_processed_files.sql"),
            kind: MigrationKind::Up,
        },
        Migration {
            version: 8,
            description: "watermark-per-media",
            sql: include_str!("../migrations/008_watermark_per_media.sql"),
            kind: MigrationKind::Up,
        },
        Migration {
            version: 9,
            description: "bundle-file-rotation",
            sql: include_str!("../migrations/009_bundle_file_rotation.sql"),
            kind: MigrationKind::Up,
        },
        Migration {
            version: 10,
            description: "jobs-kind-widen",
            sql: include_str!("../migrations/010_jobs_kind_widen.sql"),
            kind: MigrationKind::Up,
        },
        Migration {
            version: 11,
            description: "auto-assembly-settings",
            sql: include_str!("../migrations/011_auto_assembly_settings.sql"),
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
            // Phase 4 background job worker. Polls the `jobs` table
            // every 2s; dispatches by kind (process_video for v0.6.0,
            // transcribe/dropbox/etc. in later phases).
            jobs::spawn_worker(app.handle().clone());
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
            bundles::get_watermark_profiles,
            bundles::set_watermark_profile,
            bundles::process_bundle_images,
            bundles::list_processed_files,
            bundles::get_processed_previews,
            bundles::enqueue_bundle_video_ops,
            bundles::list_jobs,
            bundles::list_job_runs,
            bundles::reveal_job_output,
            bundles::reveal_processed_file,
            bundles::set_bundle_file_rotation,
            auto_assemble::enqueue_auto_assemble,
            auto_assemble::get_auto_assembly_settings,
            auto_assemble::set_auto_assembly_settings,
            auto_assemble::get_deepfilternet_status,
            bundles::get_master_cut_status,
            bundles::reveal_master_cut,
            bundles::open_master_cut,
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
    use crate::auto_assemble::{
        AssembleMasterParams, AutoAssemblySettings, DeepFilterNetStatus,
        EnqueueAutoAssembleResult, NormalizeVideoParams, RenderTitleParams,
    };
    use crate::bundles::{BundleDetail, BundleFileRow, BundleSummary, ExportThumb,
        ImageProgressEvent, IngestResult};
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

    #[test] fn auto_assembly_settings_is_camel_case() {
        assert_camel(&serde_json::to_value(AutoAssemblySettings {
            target_width: 1920, target_height: 1080, target_fps: 30,
            xfade_duration_secs: 1.0, title_duration_secs: 10.0,
            audio_enhance_enabled: true, deepfilternet_enabled: false,
        }).unwrap(), "AutoAssemblySettings");
    }

    #[test] fn render_title_params_is_camel_case() {
        assert_camel(&serde_json::to_value(RenderTitleParams {
            bundle_uid: String::new(), output_path: String::new(),
            title: String::new(), persona_watermark: String::new(),
            duration_secs: 10.0, fps: 30, width: 1920, height: 1080,
        }).unwrap(), "RenderTitleParams");
    }

    #[test] fn normalize_video_params_is_camel_case() {
        assert_camel(&serde_json::to_value(NormalizeVideoParams {
            bundle_uid: String::new(), bundle_file_id: 0,
            working_path: String::new(), output_path: String::new(),
            width: 1920, height: 1080, fps: 30,
            rotation_degrees: 0, watermark_png_path: None,
            watermark_position: String::new(), watermark_margin_pct: 0.0,
            audio_enhance: false,
            deepfilternet_enabled: false,
        }).unwrap(), "NormalizeVideoParams");
    }

    #[test] fn deepfilternet_status_is_camel_case() {
        assert_camel(&serde_json::to_value(DeepFilterNetStatus {
            installed: false, bin_path: None, version: None,
        }).unwrap(), "DeepFilterNetStatus");
    }

    #[test] fn assemble_master_params_is_camel_case() {
        assert_camel(&serde_json::to_value(AssembleMasterParams {
            bundle_uid: String::new(), output_path: String::new(),
            input_paths: vec![], xfade_duration_secs: 1.0, fps: 30,
        }).unwrap(), "AssembleMasterParams");
    }

    #[test] fn enqueue_auto_assemble_result_is_camel_case() {
        assert_camel(&serde_json::to_value(EnqueueAutoAssembleResult {
            bundle_uid: String::new(), master_path: String::new(),
            job_ids: vec![], video_count: 0, errors: vec![],
        }).unwrap(), "EnqueueAutoAssembleResult");
    }

    #[test] fn image_progress_event_is_camel_case() {
        assert_camel(&serde_json::to_value(ImageProgressEvent {
            bundle_uid: String::new(), done: 0, total: 0,
            current_in_zip_path: String::new(),
        }).unwrap(), "ImageProgressEvent");
    }

    #[test] fn bundle_file_row_is_camel_case() {
        assert_camel(&serde_json::to_value(BundleFileRow {
            in_zip_path: String::new(), original_name: String::new(),
            kind: String::new(), position: 0,
            fansite_day_of_month: None, sha256: String::new(),
            size_bytes: 0,
            working_path: None, thumbnail_path: None,
            rotation_degrees: 0,
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
    use crate::bundles::{
        EnqueueVideoOpsResult, ImageOpsInput, ProcessImagesResult,
        ProcessedFileRow, VideoOpsInput, WatermarkProfileRow,
    };
    use crate::jobs::{JobRow, JobRunRow};

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

    #[test] fn watermark_profile_row_is_camel_case() {
        assert_camel(&serde_json::to_value(WatermarkProfileRow {
            persona_code: String::new(), text: String::new(),
            opacity_percent: 20, position: "bottom-right".into(),
            font_size_pct: 4.0, margin_pct: 2.5,
            image_enabled: false, video_enabled: true,
        }).unwrap(), "WatermarkProfileRow");
    }

    #[test] fn image_ops_input_is_camel_case() {
        assert_camel(&serde_json::to_value(ImageOpsInput::default()).unwrap(), "ImageOpsInput");
    }

    #[test] fn processed_file_row_is_camel_case() {
        assert_camel(&serde_json::to_value(ProcessedFileRow {
            bundle_file_id: 0, in_zip_path: String::new(),
            op_kind: String::new(), output_path: String::new(),
            created_at: String::new(),
        }).unwrap(), "ProcessedFileRow");
    }

    #[test] fn process_images_result_is_camel_case() {
        assert_camel(&serde_json::to_value(ProcessImagesResult {
            bundle_uid: String::new(), op_kind: String::new(),
            processed: vec![], skipped: 0, errors: vec![],
        }).unwrap(), "ProcessImagesResult");
    }

    #[test] fn video_ops_input_is_camel_case() {
        assert_camel(&serde_json::to_value(VideoOpsInput::default()).unwrap(), "VideoOpsInput");
    }

    #[test] fn enqueue_video_ops_result_is_camel_case() {
        assert_camel(&serde_json::to_value(EnqueueVideoOpsResult {
            bundle_uid: String::new(), op_kind: String::new(),
            enqueued_count: 0, skipped: 0, job_ids: vec![], errors: vec![],
        }).unwrap(), "EnqueueVideoOpsResult");
    }

    #[test] fn job_row_is_camel_case() {
        assert_camel(&serde_json::to_value(JobRow {
            id: 0, kind: String::new(), params_json: String::new(),
            bundle_uid: None, source_in_zip_path: None,
            status: String::new(), attempts: 0, last_error: None,
            created_at: String::new(), updated_at: String::new(),
        }).unwrap(), "JobRow");
    }

    #[test] fn job_run_row_is_camel_case() {
        assert_camel(&serde_json::to_value(JobRunRow {
            id: 0, job_id: 0, started_at: String::new(),
            finished_at: None, exit_code: None, log_path: None,
        }).unwrap(), "JobRunRow");
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
            (5, "image-ops",      include_str!("../migrations/005_image_ops.sql")),
            (6, "jobs",           include_str!("../migrations/006_jobs.sql")),
            (7, "video-processed", include_str!("../migrations/007_video_processed_files.sql")),
            (8, "wm-per-media",   include_str!("../migrations/008_watermark_per_media.sql")),
            (9, "bf-rotation",    include_str!("../migrations/009_bundle_file_rotation.sql")),
            (10, "jobs-kind-widen", include_str!("../migrations/010_jobs_kind_widen.sql")),
            (11, "aa-settings",   include_str!("../migrations/011_auto_assembly_settings.sql")),
        ];
        for (v, name, sql) in migrations {
            conn.execute_batch(sql)
                .unwrap_or_else(|e| panic!("migration {v} ({name}) failed: {e}"));
        }

        let expected_tables: &[&str] = &[
            "app_settings", "bundles", "bundle_files", "bundle_export_thumbs",
            "watermark_profiles", "processed_files",
            "jobs", "job_runs",
            "auto_assembly_settings",
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

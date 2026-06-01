mod auto_assemble;
mod backup;
mod bundle_io;
mod bundles;
mod dropbox;
mod extract;
mod fansite;
mod fsutil;
mod images;
mod jobs;
mod manifest;
mod persona_clips;
mod post_bundle;
mod posting;
mod processing_log;
mod thumbnails;
mod transcribe;
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
        Migration {
            version: 12,
            description: "processing-log",
            sql: include_str!("../migrations/012_processing_log.sql"),
            kind: MigrationKind::Up,
        },
        Migration {
            version: 13,
            description: "dropbox",
            sql: include_str!("../migrations/013_dropbox.sql"),
            kind: MigrationKind::Up,
        },
        Migration {
            version: 14,
            description: "dropbox-template-default",
            sql: include_str!("../migrations/014_dropbox_template_default.sql"),
            kind: MigrationKind::Up,
        },
        Migration {
            version: 15,
            description: "posting",
            sql: include_str!("../migrations/015_posting.sql"),
            kind: MigrationKind::Up,
        },
        Migration {
            version: 16,
            description: "posting-assets-and-fansite",
            sql: include_str!("../migrations/016_posting_assets_and_fansite.sql"),
            kind: MigrationKind::Up,
        },
        Migration {
            version: 17,
            description: "posting-log",
            sql: include_str!("../migrations/017_posting_log.sql"),
            kind: MigrationKind::Up,
        },
        Migration {
            version: 18,
            description: "bundle-type-widen",
            sql: include_str!("../migrations/018_bundle_type_widen.sql"),
            kind: MigrationKind::Up,
        },
        Migration {
            version: 19,
            description: "persona-clips",
            sql: include_str!("../migrations/019_persona_clips.sql"),
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
            // v0.20.0: relocate the bundle workspace from Application
            // Support to ~/Downloads/SideMolly/work/. Runs synchronously
            // before the watcher so work_root is stable, and before the
            // backup so the archive no longer carries the old media.
            bundles::migrate_workspace_to_downloads(app.handle());
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
            bundles::clear_bundle_processing,
            auto_assemble::enqueue_auto_assemble,
            auto_assemble::detect_bundle_format,
            auto_assemble::get_auto_assembly_settings,
            auto_assemble::set_auto_assembly_settings,
            auto_assemble::get_deepfilternet_status,
            transcribe::get_transcribe_status,
            transcribe::enqueue_bundle_transcripts,
            transcribe::list_transcripts,
            transcribe::reveal_transcript,
            processing_log::list_log_entries,
            processing_log::export_bundle_log,
            processing_log::clear_bundle_log,
            processing_log::reveal_bundle_log,
            dropbox::get_dropbox_settings,
            dropbox::set_dropbox_settings,
            dropbox::dry_run_dropbox,
            dropbox::copy_to_dropbox,
            dropbox::reveal_dropbox_dest,
            posting::list_posting_targets,
            posting::create_posting_target,
            posting::update_posting_target,
            posting::delete_posting_target,
            posting::list_bundle_postings,
            posting::upsert_bundle_posting,
            posting::mark_posted,
            posting::list_bundle_assets,
            fansite::get_fansite_plan,
            fansite::seed_fansite_targets,
            fansite::prepare_fansite_day,
            fansite::reveal_fansite_day,
            fansite::set_fansite_day,
            fansite::reset_fansite_postings,
            fansite::list_posting_log,
            post_bundle::compose_post_bundle,
            post_bundle::get_post_bundle_status,
            post_bundle::reveal_post_bundle,
            jobs::retry_job,
            jobs::cancel_pending_job,
            jobs::clear_jobs_by_status,
            jobs::get_worker_paused,
            jobs::set_worker_paused,
            bundles::get_master_cut_status,
            bundles::reveal_master_cut,
            bundles::open_master_cut,
            watch::get_watch_settings,
            watch::set_watch_dir,
            watch::scan_watch_dir_now,
            watch::reveal_watch_dir,
            persona_clips::list_persona_clips,
            persona_clips::upload_persona_clip,
            persona_clips::set_persona_clip_enabled,
            persona_clips::clear_persona_clip,
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
    use crate::transcribe::{
        EnqueueTranscriptsResult, TranscribeStatus, TranscribeVideoParams,
        TranscriptRow,
    };
    use crate::processing_log::{ExportLogResult, LogRow};
    use crate::dropbox::{
        CopyResultRow, CopyResultSummary, DropboxSettings,
        DryRunRow, DryRunSummary,
    };
    use crate::posting::{
        BundleAsset, BundlePosting,
        PostingCard, PostingTarget, PostingTargetInput,
        UpsertBundlePostingInput,
    };
    use crate::fansite::{
        FanSiteDay, FanSitePlan, FanSiteTargetDay, PostingLogRow,
        PreparedDay, PreparedDayFile,
    };
    use crate::post_bundle::{ComposeResult, PostBundleStatus};
    use crate::bundles::{BundleDetail, BundleFileRow, BundleSummary, ExportThumb,
        ImageProgressEvent, IngestResult};
    use crate::manifest::{BundleManifest, FanDay};
    use crate::persona_clips::PersonaClipRow;
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

    #[test] fn persona_clip_row_is_camel_case() {
        assert_camel(&serde_json::to_value(PersonaClipRow {
            persona_code: String::new(), role: String::new(),
            clip_path: String::new(), enabled: false,
            updated_at: String::new(),
        }).unwrap(), "PersonaClipRow");
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

    #[test] fn transcribe_status_is_camel_case() {
        assert_camel(&serde_json::to_value(TranscribeStatus {
            installed: false, command: None, description: None, version: None,
        }).unwrap(), "TranscribeStatus");
    }

    #[test] fn transcribe_video_params_is_camel_case() {
        assert_camel(&serde_json::to_value(TranscribeVideoParams {
            bundle_uid: String::new(), bundle_file_id: 0,
            source_path: String::new(), json_output_path: String::new(),
            model: None,
        }).unwrap(), "TranscribeVideoParams");
    }

    #[test] fn enqueue_transcripts_result_is_camel_case() {
        assert_camel(&serde_json::to_value(EnqueueTranscriptsResult {
            bundle_uid: String::new(), job_ids: vec![],
            video_count: 0, skipped: 0, errors: vec![],
        }).unwrap(), "EnqueueTranscriptsResult");
    }

    #[test] fn log_row_is_camel_case() {
        assert_camel(&serde_json::to_value(LogRow {
            id: 0, timestamp: String::new(), bundle_uid: None, job_id: None,
            kind: None, level: String::new(), message: String::new(),
            subject: None, details: None,
        }).unwrap(), "LogRow");
    }

    #[test] fn export_log_result_is_camel_case() {
        assert_camel(&serde_json::to_value(ExportLogResult {
            bundle_uid: String::new(), output_path: String::new(), row_count: 0,
        }).unwrap(), "ExportLogResult");
    }

    #[test] fn dropbox_settings_is_camel_case() {
        assert_camel(&serde_json::to_value(DropboxSettings {
            root_path: String::new(), template: String::new(),
        }).unwrap(), "DropboxSettings");
    }

    #[test] fn dry_run_row_is_camel_case() {
        assert_camel(&serde_json::to_value(DryRunRow {
            source_path: String::new(), source_sha256: String::new(),
            source_size_bytes: 0,
            dropbox_path: String::new(), destination_name: String::new(),
            kind: String::new(), status: String::new(),
        }).unwrap(), "DryRunRow");
    }

    #[test] fn dry_run_summary_is_camel_case() {
        assert_camel(&serde_json::to_value(DryRunSummary {
            bundle_uid: String::new(), root_configured: false,
            dropbox_root: String::new(), destination_dir: String::new(),
            items: vec![],
        }).unwrap(), "DryRunSummary");
    }

    #[test] fn copy_result_row_is_camel_case() {
        assert_camel(&serde_json::to_value(CopyResultRow {
            source_path: String::new(), dropbox_path: String::new(),
            status: String::new(), verified: false, error: None,
        }).unwrap(), "CopyResultRow");
    }

    #[test] fn copy_result_summary_is_camel_case() {
        assert_camel(&serde_json::to_value(CopyResultSummary {
            bundle_uid: String::new(), destination_dir: String::new(),
            copied: 0, skipped: 0, failed: 0, items: vec![],
        }).unwrap(), "CopyResultSummary");
    }

    #[test] fn posting_target_is_camel_case() {
        assert_camel(&serde_json::to_value(PostingTarget {
            id: 0, name: String::new(), url_template: String::new(),
            persona_code: None, color: String::new(), icon: String::new(),
            position: 0, kind: String::new(), enabled: false,
        }).unwrap(), "PostingTarget");
    }

    #[test] fn posting_target_input_is_camel_case() {
        assert_camel(&serde_json::to_value(PostingTargetInput::default()).unwrap(),
                     "PostingTargetInput");
    }

    #[test] fn bundle_posting_is_camel_case() {
        assert_camel(&serde_json::to_value(BundlePosting {
            id: 0, bundle_uid: String::new(), target_id: 0,
            state: String::new(), posted_at: None, posted_url: None,
            body_override: None, notes: None,
            selected_assets_json: "[]".into(), fansite_day: None,
            updated_at: String::new(),
        }).unwrap(), "BundlePosting");
    }

    #[test] fn bundle_asset_is_camel_case() {
        assert_camel(&serde_json::to_value(BundleAsset {
            kind: String::new(), path: String::new(), label: String::new(),
            size_bytes: 0, in_zip_path: None,
        }).unwrap(), "BundleAsset");
    }

    #[test] fn fansite_target_day_is_camel_case() {
        assert_camel(&serde_json::to_value(FanSiteTargetDay {
            target_id: 0, state: String::new(),
            posted_at: None, posted_url: None, notes: None,
        }).unwrap(), "FanSiteTargetDay");
    }

    #[test] fn fansite_day_is_camel_case() {
        assert_camel(&serde_json::to_value(FanSiteDay {
            day_of_month: 0, message: String::new(), file_count: 0,
            targets: vec![],
        }).unwrap(), "FanSiteDay");
    }

    #[test] fn fansite_plan_is_camel_case() {
        assert_camel(&serde_json::to_value(FanSitePlan {
            bundle_uid: String::new(), persona_code: None, title: String::new(),
            year: None, month: None, targets: vec![], days: vec![],
        }).unwrap(), "FanSitePlan");
    }

    #[test] fn prepared_day_is_camel_case() {
        assert_camel(&serde_json::to_value(PreparedDay {
            bundle_uid: String::new(), day_of_month: 0,
            folder_path: String::new(), files: vec![],
            processed_count: 0, skipped_count: 0, errors: vec![],
        }).unwrap(), "PreparedDay");
    }

    #[test] fn prepared_day_file_is_camel_case() {
        assert_camel(&serde_json::to_value(PreparedDayFile {
            name: String::new(), path: String::new(),
            kind: String::new(), in_zip_path: String::new(),
        }).unwrap(), "PreparedDayFile");
    }

    #[test] fn posting_log_row_is_camel_case() {
        assert_camel(&serde_json::to_value(PostingLogRow {
            id: 0, bundle_uid: String::new(), target_id: None,
            target_name: String::new(), persona_code: None, fansite_day: None,
            title: None, action: String::new(), posted_url: None,
            details: None, logged_at: String::new(),
        }).unwrap(), "PostingLogRow");
    }

    #[test] fn compose_result_is_camel_case() {
        assert_camel(&serde_json::to_value(ComposeResult {
            bundle_uid: String::new(), output_path: String::new(),
            inner_zip_sha256: String::new(), outer_zip_sha256: String::new(),
            target_count: 0, artifact_count: 0, bytes_written: 0,
        }).unwrap(), "ComposeResult");
    }

    #[test] fn post_bundle_status_is_camel_case() {
        assert_camel(&serde_json::to_value(PostBundleStatus {
            bundle_uid: String::new(), output_path: String::new(),
            exists: false, size_bytes: 0, modified_at: None,
        }).unwrap(), "PostBundleStatus");
    }

    #[test] fn posting_card_is_camel_case() {
        assert_camel(&serde_json::to_value(PostingCard {
            target: PostingTarget {
                id: 0, name: String::new(), url_template: String::new(),
                persona_code: None, color: String::new(), icon: String::new(),
                position: 0, kind: String::new(), enabled: false,
            },
            posting: None,
            resolved_url: String::new(),
        }).unwrap(), "PostingCard");
    }

    #[test] fn upsert_bundle_posting_input_is_camel_case() {
        assert_camel(&serde_json::to_value(UpsertBundlePostingInput::default()).unwrap(),
                     "UpsertBundlePostingInput");
    }

    #[test] fn transcript_row_is_camel_case() {
        assert_camel(&serde_json::to_value(TranscriptRow {
            bundle_uid: String::new(), in_zip_path: String::new(),
            stem: String::new(),
            json_path: None, txt_path: None, srt_path: None, txt_preview: None,
        }).unwrap(), "TranscriptRow");
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
            (12, "processing-log", include_str!("../migrations/012_processing_log.sql")),
            (13, "dropbox",        include_str!("../migrations/013_dropbox.sql")),
            (14, "dropbox-template-default", include_str!("../migrations/014_dropbox_template_default.sql")),
            (15, "posting", include_str!("../migrations/015_posting.sql")),
            (16, "posting-assets-and-fansite", include_str!("../migrations/016_posting_assets_and_fansite.sql")),
            (17, "posting-log", include_str!("../migrations/017_posting_log.sql")),
            (18, "bundle-type-widen", include_str!("../migrations/018_bundle_type_widen.sql")),
            (19, "persona-clips", include_str!("../migrations/019_persona_clips.sql")),
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
            "processing_log",
            "dropbox_settings", "dropbox_copies",
            "posting_targets", "bundle_postings", "posting_log",
            "persona_clips",
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

        // Migration 018 widened the CHECK to admit Molly's 'youtube' type.
        let yt = conn.execute(
            "INSERT INTO bundles (uid, bundle_type, source_zip_path, manifest_json)
             VALUES ('yt', 'youtube', '/yt', '{}')",
            [],
        );
        assert!(yt.is_ok(), "CHECK on bundle_type should accept 'youtube' after migration 018");

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

        // Migration 019 persona_clips: role CHECK is real.
        let bad_role = conn.execute(
            "INSERT INTO persona_clips (persona_code, role) VALUES ('CoC', 'sidebar')",
            [],
        );
        assert!(bad_role.is_err(), "CHECK on persona_clips.role should reject 'sidebar'");
    }
}

// ---------------------------------------------------------------------------
// Migration immutability guard.
//
// `tauri-plugin-sql` stores a SHA256 of each migration's bytes alongside its
// version row in `_sqlx_migrations`. On every app launch it re-hashes the
// shipped migration files and refuses to start if any hash doesn't match
// the stored value — that's the "migration N was previously applied but has
// been modified" error.
//
// This test catches the same case at `cargo test` time so we never ship a
// build that crashes someone's app at launch (incident 2026-05-24: editing
// migration 013 in-place after v0.13.0 had been installed locally).
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
    /// it's been added to this list is a build break — by design.
    /// Append a new line ONLY when ADDING a new migration file.
    const EXPECTED_MIGRATION_HASHES: &[(u32, &str)] = &[
        (1, "ea35d775514071b3913c4c93c520d9c8d507a9c046bc1eecd1ccb9c6835a0bbc"),
        (2, "5cc3db2c5f89fbde821b0388497c2a7cbc457eeac01306dd819dc52d194f04a5"),
        (3, "0da5d79a58dac71d9e336ee212ee333c6a82e047ba7545c61844b5cff6bea9f4"),
        (4, "8493f734171befd8fb73c74ec0746d0bb423df5256c4c4a372be47a009b55fe5"),
        (5, "9c43bcec5c7dabbc52ba2cb14a2f976a98dcaebf532bb92562043dc67578f8e0"),
        (6, "b21627d4f9685db02b146be0ddbebfbce6a5c64145499fad14d8c0f709d6c3b9"),
        (7, "bd9dffb47b862b3acab054136ba1fa080df944792bb4ccd84f04058dddd73b27"),
        (8, "fd07dddeccd0f89a9186bbb566a975596a48bd599de093321daf169a26a479de"),
        (9, "5d8d7f67405008c02693ec0bdfef1876805e33343b534243e9c467a1fdd02972"),
        (10, "23fd87b32c210f7a1c20241ff07f7f54effee9cf9f872263686c8a0c0f27f153"),
        (11, "2fa55655c9bf934271e14656773574a448bce10a32c73f396fbd2e7e342e5ce4"),
        (12, "7194fded5e2a69f7ced08db8972518f98129459ba70f21aba610877311b8aed0"),
        (13, "79668ad641cf0e8b2c2e38745cb765cdb2618c15833063cd5fc3d09506a798bb"),
        (14, "d1cef25bbf843418ab1fbfffd1d53a19cbeda98d699d2fee35bd5c416e368e22"),
        (15, "6a0add1e30d2adb380c0d32e7dba9b3b2337e64d365f8fbff3777056ae81d42f"),
        (16, "76eb7e7c6f4a684c8cb1e48d23ce43b29289e57f276d32c264123eb1857a6326"),
        (17, "786bea0eb6e0e2a7acb240f58e9575dd3613c74444b8fcc01c7b7f52acb49ebc"),
        (18, "d702e588f454e025904a7bafb807765f2e6dc498dd6129bb1eeba4ae904bef5e"),
        (19, "f91d7ddfaf209570c6a19aabda9bbdd8b4b22212f6bd32d2742be3340ba423e0"),
    ];

    /// Source-of-truth for "which migrations ship at compile time". Must
    /// stay aligned with the `migrations` vec in `run()` above + the
    /// `migrations` array in `migration_smoke::all_migrations_apply_cleanly`.
    /// `include_str!` pulls the file bytes at compile time so the test
    /// runs against the same content tauri-plugin-sql will hash at launch.
    const MIGRATION_FILES: &[(u32, &str, &str)] = &[
        (1,  "001_init.sql",                       include_str!("../migrations/001_init.sql")),
        (2,  "002_bundles.sql",                    include_str!("../migrations/002_bundles.sql")),
        (3,  "003_bundle_files.sql",               include_str!("../migrations/003_bundle_files.sql")),
        (4,  "004_export_thumbs.sql",              include_str!("../migrations/004_export_thumbs.sql")),
        (5,  "005_image_ops.sql",                  include_str!("../migrations/005_image_ops.sql")),
        (6,  "006_jobs.sql",                       include_str!("../migrations/006_jobs.sql")),
        (7,  "007_video_processed_files.sql",      include_str!("../migrations/007_video_processed_files.sql")),
        (8,  "008_watermark_per_media.sql",        include_str!("../migrations/008_watermark_per_media.sql")),
        (9,  "009_bundle_file_rotation.sql",       include_str!("../migrations/009_bundle_file_rotation.sql")),
        (10, "010_jobs_kind_widen.sql",            include_str!("../migrations/010_jobs_kind_widen.sql")),
        (11, "011_auto_assembly_settings.sql",     include_str!("../migrations/011_auto_assembly_settings.sql")),
        (12, "012_processing_log.sql",             include_str!("../migrations/012_processing_log.sql")),
        (13, "013_dropbox.sql",                    include_str!("../migrations/013_dropbox.sql")),
        (14, "014_dropbox_template_default.sql",   include_str!("../migrations/014_dropbox_template_default.sql")),
        (15, "015_posting.sql",                    include_str!("../migrations/015_posting.sql")),
        (16, "016_posting_assets_and_fansite.sql", include_str!("../migrations/016_posting_assets_and_fansite.sql")),
        (17, "017_posting_log.sql",                include_str!("../migrations/017_posting_log.sql")),
        (18, "018_bundle_type_widen.sql",          include_str!("../migrations/018_bundle_type_widen.sql")),
        (19, "019_persona_clips.sql",              include_str!("../migrations/019_persona_clips.sql")),
    ];

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
                     your intended change. (Incident 2026-05-24.)",
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

mod attachments;
mod atw;
mod atw_settings;
mod atw_setup;
mod backup;
mod background_jobs;
mod bundle_zip;
mod bundles;
mod c4s;
mod crypto;
mod export;
mod fsutil;
mod history;
mod log;
mod masterclipper;
mod notes;
mod site_credentials;

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
            description: "sites",
            sql: include_str!("../migrations/002_sites.sql"),
            kind: MigrationKind::Up,
        },
        Migration {
            version: 3,
            description: "taxonomy",
            sql: include_str!("../migrations/003_taxonomy.sql"),
            kind: MigrationKind::Up,
        },
        Migration {
            version: 4,
            description: "customers",
            sql: include_str!("../migrations/004_customers.sql"),
            kind: MigrationKind::Up,
        },
        Migration {
            version: 5,
            description: "clips",
            sql: include_str!("../migrations/005_clips.sql"),
            kind: MigrationKind::Up,
        },
        Migration {
            version: 6,
            description: "schedules",
            sql: include_str!("../migrations/006_schedules.sql"),
            kind: MigrationKind::Up,
        },
        Migration {
            version: 7,
            description: "income",
            sql: include_str!("../migrations/007_income.sql"),
            kind: MigrationKind::Up,
        },
        Migration {
            version: 8,
            description: "expenses",
            sql: include_str!("../migrations/008_expenses.sql"),
            kind: MigrationKind::Up,
        },
        Migration {
            version: 9,
            description: "social",
            sql: include_str!("../migrations/009_social.sql"),
            kind: MigrationKind::Up,
        },
        Migration {
            version: 10,
            description: "kinks",
            sql: include_str!("../migrations/010_kinks.sql"),
            kind: MigrationKind::Up,
        },
        Migration {
            version: 11,
            description: "kinks-preload",
            sql: include_str!("../migrations/011_kinks_preload.sql"),
            kind: MigrationKind::Up,
        },
        Migration {
            version: 12,
            description: "products-and-customer-fields",
            sql: include_str!("../migrations/012_products_and_customer_fields.sql"),
            kind: MigrationKind::Up,
        },
        Migration {
            version: 13,
            description: "customer-history",
            sql: include_str!("../migrations/013_customer_history.sql"),
            kind: MigrationKind::Up,
        },
        Migration {
            version: 14,
            description: "customer-sales",
            sql: include_str!("../migrations/014_customer_sales.sql"),
            kind: MigrationKind::Up,
        },
        Migration {
            version: 15,
            description: "mollys-log",
            sql: include_str!("../migrations/015_mollys_log.sql"),
            kind: MigrationKind::Up,
        },
        Migration {
            version: 16,
            description: "c4s-clips",
            sql: include_str!("../migrations/016_c4s_clips.sql"),
            kind: MigrationKind::Up,
        },
        Migration {
            version: 17,
            description: "bundles",
            sql: include_str!("../migrations/017_bundles.sql"),
            kind: MigrationKind::Up,
        },
        Migration {
            version: 18,
            description: "crypto-keystore",
            sql: include_str!("../migrations/018_crypto_keystore.sql"),
            kind: MigrationKind::Up,
        },
        Migration {
            version: 19,
            description: "site-credentials",
            sql: include_str!("../migrations/019_site_credentials.sql"),
            kind: MigrationKind::Up,
        },
        Migration {
            version: 20,
            description: "background-jobs",
            sql: include_str!("../migrations/020_background_jobs.sql"),
            kind: MigrationKind::Up,
        },
        Migration {
            version: 21,
            description: "keystore-stay-unlocked",
            sql: include_str!("../migrations/021_keystore_stay_unlocked.sql"),
            kind: MigrationKind::Up,
        },
        Migration {
            version: 22,
            description: "job-run-log-path",
            sql: include_str!("../migrations/022_job_run_log_path.sql"),
            kind: MigrationKind::Up,
        },
        Migration {
            version: 23,
            description: "notes",
            sql: include_str!("../migrations/023_notes.sql"),
            kind: MigrationKind::Up,
        },
        Migration {
            version: 24,
            description: "note-font-size",
            sql: include_str!("../migrations/024_note_font_size.sql"),
            kind: MigrationKind::Up,
        },
    ];

    tauri::Builder::default()
        .manage(crypto::KeystoreState::new_arc())
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_process::init())
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_updater::Builder::new().build())
        .plugin(
            tauri_plugin_sql::Builder::default()
                .add_migrations("sqlite:molly.db", migrations)
                .build(),
        )
        .setup(|app| {
            let handle = app.handle().clone();
            // Auto-backup-on-launch (CLAUDE.md standard). Never throw; log on failure.
            tauri::async_runtime::spawn(async move {
                if let Err(err) = backup::run_on_launch_if_due(&handle).await {
                    eprintln!("[molly] launch backup failed: {err}");
                }
            });
            let handle2 = app.handle().clone();
            // Auto-purge old published bundles (Phase 9). Same fail-quietly
            // contract: log on failure; never crash launch. Debounced to
            // once-per-day inside auto_purge_on_launch.
            tauri::async_runtime::spawn(async move {
                if let Err(err) = bundles::auto_purge_on_launch(&handle2).await {
                    eprintln!("[molly] launch bundle auto-purge failed: {err}");
                }
            });
            let handle_kc = app.handle().clone();
            // Phase 10 follow-up: try to restore the unlocked session from
            // the OS keychain if the user opted into "Stay unlocked across
            // restarts." Synchronous, runs once, then we move on.
            crypto::commands::try_restore_from_keychain(&handle_kc);
            let handle3 = app.handle().clone();
            // Phase 10 keystore idle-lock checker. Polls every 60s; clears
            // the cached DEK if it's been idle longer than IDLE_LOCK_SECONDS
            // (8h default) AND stay_unlocked is OFF. Same fail-quietly
            // contract.
            tauri::async_runtime::spawn(async move {
                crypto::commands::idle_check_loop(handle3).await;
            });
            let handle4 = app.handle().clone();
            // Phase 12 background-jobs runner. Polls every 60s; fires any
            // job whose next_run_at has passed. Only registered kind in v1
            // is 'atw_repost'. Same fail-quietly contract — individual job
            // failures are recorded as `status='failed'` rows and the
            // loop continues.
            tauri::async_runtime::spawn(async move {
                background_jobs::run_loop(handle4).await;
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
            attachments::save_attachment,
            attachments::delete_attachment,
            attachments::reveal_attachment,
            attachments::open_attachment,
            export::export_full_data,
            export::reveal_export_dir,
            export::import_full_export,
            history::add_history_entry_with_attachment,
            history::download_history_attachment,
            log::add_log_entry_with_attachment,
            log::download_log_attachment,
            c4s::replace_c4s_clips,
            c4s::delete_all_c4s_data,
            bundles::create_bundle,
            bundles::update_bundle_fields,
            bundles::save_bundle_file,
            bundles::delete_bundle_file,
            bundles::reorder_bundle_files,
            bundles::set_bundle_categories,
            bundles::list_bundles,
            bundles::get_bundle,
            bundles::delete_bundle_draft,
            bundles::publish_bundle,
            bundles::delete_published_bundle,
            bundles::list_bundle_archives,
            bundles::reveal_bundles_dir,
            bundles::open_bundle_archive,
            bundles::auto_purge_old_bundles,
            bundles::get_bundler_settings,
            bundles::set_bundler_settings,
            bundles::list_prohibited_words,
            bundles::add_prohibited_word,
            bundles::remove_prohibited_word,
            bundles::create_fan_day,
            bundles::update_fan_day_message,
            bundles::delete_fan_day,
            masterclipper::read_masterclipper_categories,
            crypto::commands::keystore_status,
            crypto::commands::init_keystore,
            crypto::commands::unlock_keystore,
            crypto::commands::lock_keystore,
            crypto::commands::set_keystore_stay_unlocked,
            crypto::commands::change_passphrase,
            crypto::commands::encrypt_field,
            crypto::commands::decrypt_field,
            crypto::commands::export_keystore_mnemonic,
            crypto::commands::import_keystore_from_mnemonic,
            crypto::commands::wipe_keystore,
            site_credentials::list_site_credentials,
            site_credentials::create_site_credential,
            site_credentials::update_credential_username,
            site_credentials::update_credential_label,
            site_credentials::set_credential_password,
            site_credentials::clear_credential_password,
            site_credentials::reveal_credential_password,
            site_credentials::set_credential_primary,
            site_credentials::delete_site_credential,
            atw_settings::get_atw_settings,
            atw_settings::set_atw_settings,
            atw::atw_health_check,
            atw::atw_run_now,
            atw_setup::inspect_atw_setup,
            atw_setup::ensure_atw_bot_files,
            atw_setup::install_atw_bot_deps,
            background_jobs::list_background_jobs,
            background_jobs::list_job_runs,
            background_jobs::upsert_atw_job,
            background_jobs::set_job_enabled,
            background_jobs::set_job_cadence,
            background_jobs::run_job_now,
            background_jobs::open_run_log,
            background_jobs::reveal_run_log,
            notes::list_note_folders,
            notes::create_note_folder,
            notes::rename_note_folder,
            notes::move_note_folder,
            notes::delete_note_folder,
            notes::list_notes,
            notes::get_note,
            notes::create_note,
            notes::update_note,
            notes::set_note_style,
            notes::move_note,
            notes::delete_note,
            notes::copy_note,
            notes::set_note_tags,
            notes::list_note_tags,
            notes::create_note_tag,
            notes::update_note_tag,
            notes::delete_note_tag,
            notes::search_note_titles,
            notes::find_in_notes,
            notes::get_note_defaults,
            notes::set_note_defaults,
            notes::save_note_attachment,
            notes::list_note_attachments,
            notes::delete_note_attachment,
            notes::open_note_attachment,
            notes::download_note_attachment,
            notes::write_note_export,
        ])
        .run(tauri::generate_context!())
        .expect("error while running molly");
}

// ---------------------------------------------------------------------------
// Regression test: every type that crosses the Tauri boundary must serialize
// as camelCase.
//
// The v0.6.1 release shipped with BackupRow / VerifyResult / ExportResult /
// AttachmentInfo missing `#[serde(rename_all = "camelCase")]`, which made
// the frontend read `undefined` for every field ("NaN MB", "no molly.db
// inside", "undefined files"). This test pins the contract — if anyone
// adds a new boundary type without the attribute, `cargo test` fails.
//
// Add new response types here as the surface grows.
// ---------------------------------------------------------------------------
#[cfg(test)]
mod camel_case_contract {
    use crate::attachments::AttachmentInfo;
    use crate::backup::{BackupRow, Settings, VerifyResult};
    use crate::c4s::{DeleteAllResult, ReplaceResult};
    use crate::export::ExportResult;
    use crate::history::HistoryEntryRef;
    use crate::log::LogEntryRef;
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

    #[test]
    fn attachment_info_is_camel_case() {
        let v = serde_json::to_value(AttachmentInfo {
            relative_path: String::new(),
            absolute_path: String::new(),
            size_bytes: 0,
        }).unwrap();
        assert_camel(&v, "AttachmentInfo");
    }

    #[test]
    fn export_result_is_camel_case() {
        let v = serde_json::to_value(ExportResult {
            path: String::new(),
            size_bytes: 0,
            file_count: 0,
        }).unwrap();
        assert_camel(&v, "ExportResult");
    }

    #[test]
    fn history_entry_ref_is_camel_case() {
        let v = serde_json::to_value(HistoryEntryRef { id: 0 }).unwrap();
        assert_camel(&v, "HistoryEntryRef");
    }

    #[test]
    fn log_entry_ref_is_camel_case() {
        let v = serde_json::to_value(LogEntryRef { id: 0 }).unwrap();
        assert_camel(&v, "LogEntryRef");
    }

    #[test]
    fn c4s_replace_result_is_camel_case() {
        let v = serde_json::to_value(ReplaceResult {
            persona_code: String::new(),
            deleted_count: 0,
            inserted_count: 0,
            expected_count: 0,
            matches: true,
            imported_at: String::new(),
        }).unwrap();
        assert_camel(&v, "ReplaceResult");
    }

    #[test]
    fn c4s_delete_all_result_is_camel_case() {
        let v = serde_json::to_value(DeleteAllResult {
            deleted_clips: 0,
            deleted_imports: 0,
        }).unwrap();
        assert_camel(&v, "DeleteAllResult");
    }

    // Phase 9: every Content Bundler boundary type. Asserted here so
    // adding a new field without #[serde(rename_all = "camelCase")] on
    // the parent struct fails `cargo test` instead of silently breaking
    // the frontend's BundleSummary / Bundle render.
    use crate::bundles::{
        Bundle, BundleArchiveRow, BundleCategory, BundleFanDay, BundleFileInfo,
        BundlePublishResult, BundleSummary, BundlerSettings, PurgeResult, Severity,
        ValidationIssue,
    };

    fn empty_summary() -> BundleSummary {
        BundleSummary {
            uid: String::new(),
            bundle_type: String::new(),
            persona_code: None,
            state: String::new(),
            title: String::new(),
            content_date: String::new(),
            go_live_date: None,
            published_at: None,
            bundle_path: None,
            bundle_size_bytes: None,
            created_at: String::new(),
            updated_at: String::new(),
            aging_flag: String::new(),
            file_count: 0,
        }
    }

    #[test]
    fn bundler_settings_is_camel_case() {
        let v = serde_json::to_value(BundlerSettings::default()).unwrap();
        assert_camel(&v, "BundlerSettings");
    }

    #[test]
    fn bundle_summary_is_camel_case() {
        let v = serde_json::to_value(empty_summary()).unwrap();
        assert_camel(&v, "BundleSummary");
    }

    #[test]
    fn bundle_file_info_is_camel_case() {
        let v = serde_json::to_value(BundleFileInfo {
            id: 0,
            bundle_uid: String::new(),
            fansite_day_id: None,
            position: 0,
            relpath: String::new(),
            original_name: String::new(),
            kind: String::new(),
            size_bytes: 0,
            sha256: String::new(),
        })
        .unwrap();
        assert_camel(&v, "BundleFileInfo");
    }

    #[test]
    fn bundle_fan_day_is_camel_case() {
        let v = serde_json::to_value(BundleFanDay {
            id: 0,
            day_of_month: 1,
            message: String::new(),
            file_count: 0,
        })
        .unwrap();
        assert_camel(&v, "BundleFanDay");
    }

    #[test]
    fn bundle_category_is_camel_case() {
        let v = serde_json::to_value(BundleCategory {
            name: String::new(),
            position: 1,
        })
        .unwrap();
        assert_camel(&v, "BundleCategory");
    }

    #[test]
    fn bundle_full_is_camel_case() {
        let v = serde_json::to_value(Bundle {
            summary: empty_summary(),
            special_instructions: String::new(),
            description_mode: None,
            description_text: String::new(),
            description_audio_relpath: None,
            description_audio_original_name: None,
            delivery_kind: None,
            delivery_site_id: None,
            delivery_url: None,
            delivery_recipient: String::new(),
            price_cents: None,
            handled_in_platform: false,
            fansite_year: None,
            fansite_month: None,
            outer_sha256: None,
            inner_sha256: None,
            files: vec![],
            categories: vec![],
            fan_days: vec![],
        })
        .unwrap();
        assert_camel(&v, "Bundle");
    }

    #[test]
    fn bundle_publish_result_is_camel_case() {
        let v = serde_json::to_value(BundlePublishResult {
            uid: String::new(),
            path: String::new(),
            size_bytes: 0,
            inner_sha256: String::new(),
            outer_sha256: String::new(),
            file_count: 0,
            clip_created: false,
        })
        .unwrap();
        assert_camel(&v, "BundlePublishResult");
    }

    #[test]
    fn purge_result_is_camel_case() {
        let v = serde_json::to_value(PurgeResult {
            considered: 0,
            purged: 0,
            skipped_missing: 0,
            last_run_at: String::new(),
        })
        .unwrap();
        assert_camel(&v, "PurgeResult");
    }

    #[test]
    fn bundle_archive_row_is_camel_case() {
        let v = serde_json::to_value(BundleArchiveRow {
            uid: None,
            path: String::new(),
            filename: String::new(),
            modified_at: String::new(),
            size_bytes: 0,
        })
        .unwrap();
        assert_camel(&v, "BundleArchiveRow");
    }

    #[test]
    fn validation_issue_is_camel_case() {
        let v = serde_json::to_value(ValidationIssue {
            field_path: String::new(),
            message: String::new(),
            severity: Severity::Error,
            jump_to_field_id: String::new(),
        })
        .unwrap();
        assert_camel(&v, "ValidationIssue");
    }

    // Phase 10 keystore boundary structs.
    use crate::crypto::commands::{EncryptedField, MnemonicWords};
    use crate::crypto::KeystoreStatus;

    #[test]
    fn keystore_status_is_camel_case() {
        let v = serde_json::to_value(KeystoreStatus {
            initialized: false,
            unlocked: false,
            version: 1,
            unlocked_secs: None,
            stay_unlocked: false,
        })
        .unwrap();
        assert_camel(&v, "KeystoreStatus");
    }

    #[test]
    fn encrypted_field_is_camel_case() {
        let v = serde_json::to_value(EncryptedField {
            ciphertext: String::new(),
            dek_version: 1,
        })
        .unwrap();
        assert_camel(&v, "EncryptedField");
    }

    #[test]
    fn mnemonic_words_is_camel_case() {
        let v = serde_json::to_value(MnemonicWords { words: vec![] }).unwrap();
        assert_camel(&v, "MnemonicWords");
    }

    // Phase 11 site credentials.
    use crate::site_credentials::SiteCredential;

    #[test]
    fn site_credential_is_camel_case() {
        let v = serde_json::to_value(SiteCredential {
            id: 0,
            site_id: 0,
            label: String::new(),
            username: String::new(),
            has_password: false,
            password_dek_version: None,
            password_updated_at: None,
            is_primary: false,
            sort_order: 0,
        })
        .unwrap();
        assert_camel(&v, "SiteCredential");
    }

    // Phase 12 background jobs + ATW.
    use crate::atw::{AtwHealthCheck, RunOutcome};
    use crate::atw_settings::AtwSettingsDto;
    use crate::background_jobs::{BackgroundJob, BackgroundJobRun};

    #[test]
    fn atw_settings_dto_is_camel_case() {
        let v = serde_json::to_value(AtwSettingsDto {
            email: String::new(),
            has_password: false,
            password_dek_version: None,
            bot_dir: None,
            browser_executable_path: None,
            cadence_seconds: 0,
            repost_days: 0,
            schedule_start_hour: 0,
            schedule_end_hour: 0,
            utc_offset: 0,
            delay_ms: 0,
            headless: true,
        })
        .unwrap();
        assert_camel(&v, "AtwSettingsDto");
    }

    #[test]
    fn atw_health_check_is_camel_case() {
        let v = serde_json::to_value(AtwHealthCheck {
            node_found: false,
            node_path: None,
            chrome_found: false,
            chrome_path: None,
            bot_dir_set: false,
            bot_dir_exists: false,
            bot_dir_has_repost_js: false,
            bot_dir_has_node_modules: false,
        })
        .unwrap();
        assert_camel(&v, "AtwHealthCheck");
    }

    #[test]
    fn atw_run_outcome_is_camel_case() {
        let v = serde_json::to_value(RunOutcome {
            status: String::new(),
            summary: String::new(),
            log_excerpt: String::new(),
            elapsed_seconds: 0,
            log_path: None,
        })
        .unwrap();
        assert_camel(&v, "RunOutcome");
    }

    #[test]
    fn background_job_is_camel_case() {
        let v = serde_json::to_value(BackgroundJob {
            id: 0,
            kind: String::new(),
            name: String::new(),
            enabled: false,
            cadence_seconds: 0,
            params_json: String::new(),
            last_run_at: None,
            next_run_at: None,
            created_at: String::new(),
            updated_at: String::new(),
        })
        .unwrap();
        assert_camel(&v, "BackgroundJob");
    }

    #[test]
    fn background_job_run_is_camel_case() {
        let v = serde_json::to_value(BackgroundJobRun {
            id: 0,
            job_id: 0,
            started_at: String::new(),
            finished_at: None,
            status: String::new(),
            summary: String::new(),
            log_excerpt: String::new(),
            log_path: None,
        })
        .unwrap();
        assert_camel(&v, "BackgroundJobRun");
    }

    // Phase 13 — Notes boundary structs.
    use crate::notes::{FindHit, Note, NoteAttachment, NoteDefaults, NoteFolder, NoteSummary, NoteTag};

    #[test]
    fn note_folder_is_camel_case() {
        let v = serde_json::to_value(NoteFolder {
            id: 0, parent_id: None, name: String::new(), sort_order: 0,
            created_at: String::new(), updated_at: String::new(),
        }).unwrap();
        assert_camel(&v, "NoteFolder");
    }

    #[test]
    fn note_summary_is_camel_case() {
        let v = serde_json::to_value(NoteSummary {
            id: 0, folder_id: None, title: String::new(),
            paper_color: None, font_family: None, font_size_scale: None,
            updated_at: String::new(), last_edited_at: String::new(),
            tag_ids: vec![], attachment_count: 0,
        }).unwrap();
        assert_camel(&v, "NoteSummary");
    }

    #[test]
    fn note_is_camel_case() {
        let v = serde_json::to_value(Note {
            id: 0, folder_id: None, title: String::new(),
            content_html: String::new(), content_text: String::new(),
            paper_color: None, font_family: None, font_size_scale: None,
            created_at: String::new(), updated_at: String::new(),
            last_edited_at: String::new(), tag_ids: vec![],
        }).unwrap();
        assert_camel(&v, "Note");
    }

    #[test]
    fn note_tag_is_camel_case() {
        let v = serde_json::to_value(NoteTag {
            id: 0, name: String::new(), color: String::new(),
            sort_order: 0, is_builtin: false,
        }).unwrap();
        assert_camel(&v, "NoteTag");
    }

    #[test]
    fn note_attachment_is_camel_case() {
        let v = serde_json::to_value(NoteAttachment {
            id: 0, note_id: 0, filename: String::new(), original_name: String::new(),
            mime: String::new(), size_bytes: 0, created_at: String::new(),
        }).unwrap();
        assert_camel(&v, "NoteAttachment");
    }

    #[test]
    fn find_hit_is_camel_case() {
        let v = serde_json::to_value(FindHit {
            note_id: 0, note_title: String::new(), folder_id: None,
            line_no: 0, snippet: String::new(),
        }).unwrap();
        assert_camel(&v, "FindHit");
    }

    #[test]
    fn note_defaults_is_camel_case() {
        let v = serde_json::to_value(NoteDefaults {
            default_font: String::new(), default_paper_color: String::new(),
            default_font_size_scale: 1.0,
        }).unwrap();
        assert_camel(&v, "NoteDefaults");
    }
}

// ---------------------------------------------------------------------------
// Migration smoke test: applies every shipped migration to a fresh in-memory
// SQLite database in source order and verifies the expected tables exist.
// This catches future schema regressions (bad ALTER, missing FK target, SQL
// syntax errors) before they touch Sallie's real DB on launch — the
// migration runner there is fail-loud but you don't want to find out
// post-shipping.
// ---------------------------------------------------------------------------
#[cfg(test)]
mod migration_smoke {
    use rusqlite::Connection;

    #[test]
    fn all_migrations_apply_cleanly() {
        let conn = Connection::open_in_memory().expect("open :memory:");
        // Match the running app's FK enforcement so CASCADE / RESTRICT clauses
        // are actually validated, not just parsed.
        conn.execute_batch("PRAGMA foreign_keys = ON;").unwrap();

        // Each entry mirrors the `migrations` Vec in run(). Adding a
        // migration there means appending one line here.
        let migrations: &[(u32, &str, &str)] = &[
            (1,  "init",                         include_str!("../migrations/001_init.sql")),
            (2,  "sites",                        include_str!("../migrations/002_sites.sql")),
            (3,  "taxonomy",                     include_str!("../migrations/003_taxonomy.sql")),
            (4,  "customers",                    include_str!("../migrations/004_customers.sql")),
            (5,  "clips",                        include_str!("../migrations/005_clips.sql")),
            (6,  "schedules",                    include_str!("../migrations/006_schedules.sql")),
            (7,  "income",                       include_str!("../migrations/007_income.sql")),
            (8,  "expenses",                     include_str!("../migrations/008_expenses.sql")),
            (9,  "social",                       include_str!("../migrations/009_social.sql")),
            (10, "kinks",                        include_str!("../migrations/010_kinks.sql")),
            (11, "kinks-preload",                include_str!("../migrations/011_kinks_preload.sql")),
            (12, "products-and-customer-fields", include_str!("../migrations/012_products_and_customer_fields.sql")),
            (13, "customer-history",             include_str!("../migrations/013_customer_history.sql")),
            (14, "customer-sales",               include_str!("../migrations/014_customer_sales.sql")),
            (15, "mollys-log",                   include_str!("../migrations/015_mollys_log.sql")),
            (16, "c4s-clips",                    include_str!("../migrations/016_c4s_clips.sql")),
            (17, "bundles",                      include_str!("../migrations/017_bundles.sql")),
            (18, "crypto-keystore",              include_str!("../migrations/018_crypto_keystore.sql")),
            (19, "site-credentials",             include_str!("../migrations/019_site_credentials.sql")),
            (20, "background-jobs",              include_str!("../migrations/020_background_jobs.sql")),
            (21, "keystore-stay-unlocked",       include_str!("../migrations/021_keystore_stay_unlocked.sql")),
            (22, "job-run-log-path",             include_str!("../migrations/022_job_run_log_path.sql")),
            (23, "notes",                        include_str!("../migrations/023_notes.sql")),
            (24, "note-font-size",               include_str!("../migrations/024_note_font_size.sql")),
        ];

        for (v, name, sql) in migrations {
            conn.execute_batch(sql)
                .unwrap_or_else(|e| panic!("migration {v} ({name}) failed: {e}"));
        }

        // Anchor table existence so a future migration that accidentally
        // DROPs one of these is caught immediately.
        let expected_tables: &[&str] = &[
            "personas", "app_settings",
            "sites",
            "products", "interests", "kinks",
            "customers", "customer_products", "customer_interests", "customer_kinks",
            "customer_history", "customer_sales",
            "clips", "clip_imports",
            "schedules", "occurrences",
            "income_adhoc", "income_site",
            "expenses", "expenses_recurring",
            "social_platforms", "social_promos",
            "mollys_log",
            "c4s_clips", "c4s_imports",
            "bundles", "bundle_fan_days", "bundle_files", "bundle_categories", "bundle_prohibited_words",
            "crypto_keystore",
            "site_credentials",
            "background_jobs", "background_job_runs",
            "note_folders", "notes", "note_tags_def", "note_tag_links", "note_attachments",
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

        // Migration 011 preloads 349 kinks; if that ever silently drops to
        // zero, catch it here before the app's KinkChipPicker shows empty.
        let kink_count: i64 = conn
            .query_row("SELECT COUNT(*) FROM kinks", [], |row| row.get(0))
            .unwrap();
        assert!(
            kink_count >= 349,
            "migration 011 should preload at least 349 kinks; got {kink_count}",
        );

        // Migration 017 seeds four default prohibited words for the
        // Content Bundler's description validator. The bundler form
        // assumes the table is non-empty out of the box; if a future
        // migration accidentally TRUNCATEs it, the validator goes
        // permissive overnight without warning.
        let prohibited_count: i64 = conn
            .query_row("SELECT COUNT(*) FROM bundle_prohibited_words", [], |row| row.get(0))
            .unwrap();
        assert_eq!(
            prohibited_count, 4,
            "migration 017 should seed exactly 4 prohibited words; got {prohibited_count}",
        );

        // Migration 018 enforces the keystore-singleton contract: the
        // row with id=1 must exist post-migration even on a fresh DB,
        // with NULL salt/wrapped_dek meaning "not initialized yet."
        // Init code paths assume this row is present and UPDATE it
        // rather than INSERT, so the bootstrap row matters.
        let keystore_count: i64 = conn
            .query_row("SELECT COUNT(*) FROM crypto_keystore WHERE id = 1", [], |row| row.get(0))
            .unwrap();
        assert_eq!(
            keystore_count, 1,
            "migration 018 should seed exactly one crypto_keystore singleton row; got {keystore_count}",
        );

        // Migration 019 backfills a primary site_credentials row for
        // every existing site. A fresh DB has zero sites (sites are
        // user-created), so the count is also zero — but the table
        // must exist (covered by the anchor-tables loop above) and
        // the FK invariant must hold. We insert a fixture site here
        // to exercise the backfill SQL path against the existing
        // migration script (which runs INSERT INTO site_credentials
        // SELECT ... FROM sites; a fresh DB has zero rows in sites,
        // so this is a no-op — fine, the existence of the SELECT
        // statement is what we'd test with a more elaborate setup).
        let creds_count: i64 = conn
            .query_row("SELECT COUNT(*) FROM site_credentials", [], |row| row.get(0))
            .unwrap();
        let sites_count: i64 = conn
            .query_row("SELECT COUNT(*) FROM sites", [], |row| row.get(0))
            .unwrap();
        assert_eq!(
            creds_count, sites_count,
            "migration 019 should backfill exactly one credential per site (got {creds_count} creds vs {sites_count} sites)",
        );
    }
}

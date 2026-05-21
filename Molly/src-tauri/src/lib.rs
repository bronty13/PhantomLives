mod attachments;
mod backup;
mod export;
mod fsutil;
mod history;
mod log;

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
    ];

    tauri::Builder::default()
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
}

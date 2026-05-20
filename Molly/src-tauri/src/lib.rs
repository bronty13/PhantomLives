mod attachments;
mod backup;
mod export;
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
        ])
        .run(tauri::generate_context!())
        .expect("error while running molly");
}

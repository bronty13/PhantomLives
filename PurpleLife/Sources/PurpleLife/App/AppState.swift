import Foundation
import SwiftUI

/// Top-level observable state. Phase 1 keeps it deliberately thin: it owns
/// the SettingsStore, fires the launch-time backup before any UI reads the
/// DB, and exposes the singleton `DatabaseService` to views.
@MainActor
final class AppState: ObservableObject {
    @Published var settingsStore = SettingsStore()
    @Published var schema = SchemaRegistry()
    let database = DatabaseService.shared

    @Published var objectCount: Int = 0
    @Published var selectedTypeId: String?

    /// Set by the Quick Switcher to ask the main window to open a
    /// specific record. The `RecordsScreen` watches this and routes it
    /// into its detail sheet, then clears it.
    @Published var openRecordRequest: String?

    /// Pass-through to the underlying SettingsStore — saves on every set.
    /// Lets views write `appState.settings.foo = …` without thinking about
    /// the store. Mirrors the Timeliner pattern.
    var settings: AppSettings {
        get { settingsStore.settings }
        set {
            settingsStore.settings = newValue
            settingsStore.save()
        }
    }

    init() {
        // Backup-on-launch must run BEFORE any code touches the DB pool, so
        // the archive captures a clean copy of the on-disk state from the
        // last session. BackupService swallows its own errors.
        BackupService.runOnLaunchIfDue(settingsStore: settingsStore)

        // Wire ObjectEngine → SchemaRegistry so search-index updates have
        // the type definitions they need.
        ObjectEngine.currentSchema = schema

        // Rebuild the FTS5 index on every launch — cheap for our row
        // counts and immune to a missed write or a restored backup.
        SearchService.reindexAll(schema: schema)

        // Default sidebar selection — first visible built-in.
        selectedTypeId = schema.visibleTypes.first?.id

        reloadAll()
    }

    /// Refresh derived UI state from the database. Called on launch and
    /// after restore. Phase 1 only has the object count; Phase 2 expands
    /// this to load the schema registry, sidebar lists, etc.
    func reloadAll() {
        do {
            objectCount = try database.objectCount()
        } catch {
            NSLog("PurpleLife: objectCount failed — \(error.localizedDescription)")
            objectCount = 0
        }
    }
}

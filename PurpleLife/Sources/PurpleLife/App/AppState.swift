import Foundation
import SwiftUI

/// Top-level observable state. Phase 1 keeps it deliberately thin: it owns
/// the SettingsStore, fires the launch-time backup before any UI reads the
/// DB, and exposes the singleton `DatabaseService` to views.
@MainActor
final class AppState: ObservableObject {

    /// Notification posted when the user invokes the ⌘N "New record"
    /// menu command. `RecordsScreen` observes and creates a new record
    /// of its currently-displayed type.
    static let newRecordRequestedNotification = Notification.Name("PurpleLife.newRecordRequested")

    /// Notification posted when the user invokes a ⌘1…⌘9 "Jump to
    /// type" command. `userInfo["index"]` carries the 1-based position
    /// in `SchemaRegistry.visibleTypes`.
    static let jumpToTypeIndexNotification = Notification.Name("PurpleLife.jumpToTypeIndex")
    @Published var settingsStore = SettingsStore()
    @Published var schema = SchemaRegistry()
    @Published var sync = CloudKitSyncService()
    let database = DatabaseService.shared

    @Published var objectCount: Int = 0

    /// Sidebar selection. The special value `nil` means "Today" (the
    /// home panel that doesn't belong to any type). Real type ids
    /// select that type's records pane.
    @Published var selectedTypeId: String?
    @Published var showTodayInDetail: Bool = true

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
        ObjectEngine.sync = sync
        // Wire SchemaRegistry → sync so user schema mutations
        // (add/rename/delete types and fields) push to CloudKit and
        // peers learn about them. Same mirror pattern as ObjectEngine.
        schema.sync = sync

        // Rebuild the FTS5 index on every launch — cheap for our row
        // counts and immune to a missed write or a restored backup.
        SearchService.reindexAll(schema: schema)

        // Phase 4: kick off CloudKit sync. Runs async; the rest of the
        // app launches normally regardless of sync state. If iCloud
        // / entitlement / container isn't available, sync transitions to
        // `.disabled` and the app stays fully usable locally.
        // Skipped under XCTest — CloudKit's account check stalls the
        // test runner connection (we hit the XCTest timeout because the
        // host app's startup tasks block on iCloud auth).
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            sync.start(schema: schema)
        }

        // Default detail pane is Today; type selection is left nil so the
        // sidebar's Today row reads as selected.
        selectedTypeId = nil
        showTodayInDetail = true

        reloadAll()

        // ⌘1…⌘9 menu commands post a notification with a 1-based
        // index; resolve here against `schema.visibleTypes` and route
        // to the existing `selectedTypeId` binding so the sidebar
        // reflects the change naturally.
        NotificationCenter.default.addObserver(
            forName: AppState.jumpToTypeIndexNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self,
                  let index = note.userInfo?["index"] as? Int else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                let visible = self.schema.visibleTypes
                guard index >= 1, index <= visible.count else { return }
                self.selectedTypeId = visible[index - 1].id
                self.showTodayInDetail = false
            }
        }
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

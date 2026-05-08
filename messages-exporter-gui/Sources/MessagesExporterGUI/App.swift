import SwiftUI

@main
struct MessagesExporterGUIApp: App {
    @StateObject private var runner: ExportRunner
    @StateObject private var presets = PresetStore()

    init() {
        // Launch-time auto-backup per PhantomLives/CLAUDE.md. Runs
        // synchronously before any UI is built; failures are NSLogged
        // and never propagated, so the app launches even if backup
        // fails (volume unmounted, disk full, etc.). The 5-minute
        // debounce inside BackupService prevents repeated relaunches
        // during a debugging session from filling the backup folder.
        BackupService.runOnLaunchIfDue()
        // The runner needs a history store; we instantiate one here
        // and inject so the runner and any future consumers share the
        // same in-memory copy.
        _runner = StateObject(wrappedValue: ExportRunner(history: RunHistoryStore()))
    }

    var body: some Scene {
        WindowGroup("Messages Exporter") {
            RootView()
                .environmentObject(runner)
                .environmentObject(presets)
                // Min size keeps the four-tile row + form card on screen
                // without horizontal scrolling. Ideal matches the design's
                // 1100×780 artboard so a fresh launch hits the intended
                // proportions.
                .frame(minWidth: 920, idealWidth: 1100,
                       minHeight: 640, idealHeight: 780)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        Settings {
            SettingsView()
                .environmentObject(runner)
                .environmentObject(presets)
        }
    }
}

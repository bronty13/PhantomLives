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
                // Window IS resizable; the floor just has to give a
                // small-laptop screen enough headroom to actually drag.
                // 920×640 (the original target) left no practical
                // resize range on a 1280×800 laptop and looked like
                // "won't resize". 910×632 keeps the four stat tiles +
                // form card legible while still giving meaningful
                // shrink room. Resize range opens up freely on bigger
                // displays.
                .frame(minWidth: 910, minHeight: 632)
        }
        // NOTE: dropped `.windowStyle(.hiddenTitleBar)`. That style
        // strips resize in combination with our HStack-sidebar layout
        // on this macOS build (we tried `.windowResizability` with
        // `.contentMinSize`, an explicit `maxWidth: .infinity` frame,
        // and an AppKit bridge that re-inserts `.resizable` into the
        // NSWindow styleMask — none restored edge-drag). The regular
        // title bar costs ~28pt at the top but the window resizes
        // freely and the traffic lights no longer overlap content.
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

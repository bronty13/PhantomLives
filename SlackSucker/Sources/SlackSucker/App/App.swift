import SwiftUI

@main
struct SlackSuckerApp: App {
    @StateObject private var settings = SettingsStore()
    @StateObject private var runner: ArchiveRunner
    @StateObject private var workspaces = WorkspaceService()
    @StateObject private var channels = ChannelService()
    @StateObject private var presets = PresetStore()

    @AppStorage("themePreference") private var themePref: String = ThemePreference.system.rawValue

    init() {
        // Launch-time auto-backup per PhantomLives/CLAUDE.md. Runs
        // synchronously before any UI is built; failures are NSLogged
        // and never propagated so the app launches even if backup fails.
        // The 5-minute debounce inside BackupService prevents repeated
        // relaunches during a debugging session from filling the folder.
        BackupService.runOnLaunchIfDue()
        _runner = StateObject(wrappedValue: ArchiveRunner(history: RunHistoryStore()))
    }

    var body: some Scene {
        WindowGroup("SlackSucker") {
            RootView()
                .environmentObject(settings)
                .environmentObject(runner)
                .environmentObject(workspaces)
                .environmentObject(channels)
                .environmentObject(presets)
                .preferredColorScheme(ThemePreference(rawValue: themePref)?.colorScheme)
                .frame(minWidth: 920, minHeight: 640)
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(runner)
                .preferredColorScheme(ThemePreference(rawValue: themePref)?.colorScheme)
        }
    }
}

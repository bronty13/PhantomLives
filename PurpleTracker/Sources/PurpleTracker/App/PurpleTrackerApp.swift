import SwiftUI
import AppKit

@main
struct PurpleTrackerApp: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(appState.settingsStore)
                .frame(minWidth: 1100, minHeight: 700)
                // Sheet hosting the ⌘K command palette. Bound to AppState
                // so menu items elsewhere can toggle it open.
                .sheet(isPresented: $appState.commandPaletteVisible) {
                    CommandPaletteView()
                        .environmentObject(appState)
                        .frame(width: 620, height: 420)
                }
                .onAppear {
                    appDelegate.appState = appState
                    appDelegate.installMenuBarItem()
                    appState.purgeExpiredTrash()
                }
        }
        .defaultSize(width: 1400, height: 900)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Matter") {
                    if let firstType = appState.types.first {
                        _ = try? appState.createMatter(typeId: firstType.id)
                    }
                }
                .keyboardShortcut("n")
            }
            CommandGroup(after: .toolbar) {
                Button("Quick Open / Command Palette…") {
                    appState.commandPaletteVisible.toggle()
                }
                .keyboardShortcut("k", modifiers: [.command])
                Button("Today") { appState.sidebarSection = .today }
                    .keyboardShortcut("1", modifiers: [.command, .shift])
                Button("All Matters") { appState.sidebarSection = .all }
                    .keyboardShortcut("2", modifiers: [.command, .shift])
                Button("Time Dashboard") { appState.sidebarSection = .timeDashboard }
                    .keyboardShortcut("3", modifiers: [.command, .shift])
                Button("Analytics") { appState.sidebarSection = .analytics }
                    .keyboardShortcut("4", modifiers: [.command, .shift])
                Divider()
                Button("Toggle Active Timer") {
                    if appState.timer.activeMatterId != nil {
                        _ = appState.timer.stop()
                    } else if let id = appState.selectedMatterId {
                        appState.timer.start(matterId: id)
                    }
                }
                .keyboardShortcut(" ", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(appState.settingsStore)
                .frame(minWidth: 760, minHeight: 540)
        }
    }
}

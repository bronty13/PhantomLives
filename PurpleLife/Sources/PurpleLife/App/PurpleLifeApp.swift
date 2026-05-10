import SwiftUI

@main
struct PurpleLifeApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1200, height: 800)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(after: .toolbar) {
                SchemaEditorMenuItem()
                QuickSwitcherMenuItem()
            }
        }

        // The schema editor lives in its own window so it can be left open
        // alongside a record list. Accessible from the Window menu and via
        // ⇧⌘S (wired by `SchemaEditorMenuItem`).
        Window("Schema editor", id: "schema-editor") {
            SchemaEditorScreen()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1100, height: 700)

        // ⌘K Quick Switcher — small floating window for global search.
        Window("Quick switcher", id: "quick-switcher") {
            QuickSwitcher()
                .environmentObject(appState)
        }
        .defaultSize(width: 640, height: 440)
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

private struct SchemaEditorMenuItem: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Schema editor…") {
            openWindow(id: "schema-editor")
        }
        .keyboardShortcut("s", modifiers: [.command, .shift])
    }
}

private struct QuickSwitcherMenuItem: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Quick switcher…") {
            openWindow(id: "quick-switcher")
        }
        .keyboardShortcut("k", modifiers: [.command])
    }
}

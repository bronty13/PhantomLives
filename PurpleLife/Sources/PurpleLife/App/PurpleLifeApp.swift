import SwiftUI

@main
struct PurpleLifeApp: App {
    // The adaptor must come BEFORE @StateObject so SwiftUI installs the
    // delegate before `AppState`'s init kicks off CloudKit work — the
    // delegate registers for remote notifications on
    // `applicationDidFinishLaunching`, which the sync service depends on
    // for its silent-push wakeups.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
            CommandGroup(replacing: .newItem) {
                NewRecordMenuItem()
            }
            CommandGroup(after: .toolbar) {
                SchemaEditorMenuItem()
                QuickSwitcherMenuItem()
                Divider()
                JumpToTypeMenuItems()
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

        // Menu-bar quick-capture. A small SF Symbol in the system menu
        // bar opens a popover with type picker + title field; ⌘↩ saves
        // and the popover stays open for repeat capture, Esc closes.
        // The icon is always present in this build — no toggle yet.
        MenuBarExtra("PurpleLife quick capture", systemImage: "wand.and.sparkles") {
            QuickCaptureMenu()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)
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

/// ⌘N — File → New Record. Replaces the default "New Window"
/// command that SwiftUI inserts (we already use a single
/// `WindowGroup`; users don't need a second window). Posts the
/// notification that `RecordsScreen` listens for; the screen owns
/// the actual record creation so the new row participates in its
/// reload + selection flow.
private struct NewRecordMenuItem: View {
    var body: some View {
        Button("New record") {
            NotificationCenter.default.post(
                name: AppState.newRecordRequestedNotification, object: nil
            )
        }
        .keyboardShortcut("n", modifiers: [.command])
    }
}

/// ⌘1…⌘9 — Window menu group. Each posts the index notification;
/// `AppState` resolves the index against `schema.visibleTypes` and
/// flips `selectedTypeId`. Labels are intentionally generic ("Type
/// 1", "Type 2"…) — making them reactive to `schema.visibleTypes`
/// requires plumbing AppState into the App-scope Commands block,
/// which is a bigger refactor than the shortcuts are worth. The
/// shortcut itself is the affordance; the label is a fallback for
/// users browsing the menu.
private struct JumpToTypeMenuItems: View {
    var body: some View {
        ForEach(1...9, id: \.self) { index in
            Button("Jump to type \(index)") {
                NotificationCenter.default.post(
                    name: AppState.jumpToTypeIndexNotification,
                    object: nil,
                    userInfo: ["index": index]
                )
            }
            .keyboardShortcut(KeyEquivalent(Character("\(index)")), modifiers: [.command])
        }
    }
}

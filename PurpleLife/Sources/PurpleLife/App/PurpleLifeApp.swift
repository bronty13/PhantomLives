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
                .preferredColorScheme(appState.settings.appearance.colorScheme)
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
                SearchMenuItem()
                Divider()
                JumpToTypeMenuItems()
            }
            CommandGroup(after: .sidebar) {
                Divider()
                VaultMenuItem()
                    .environmentObject(appState)
            }
        }

        // The schema editor lives in its own window so it can be left open
        // alongside a record list. Accessible from the Window menu and via
        // ⇧⌘S (wired by `SchemaEditorMenuItem`).
        Window("Schema editor", id: "schema-editor") {
            SchemaEditorScreen()
                .environmentObject(appState)
                .preferredColorScheme(appState.settings.appearance.colorScheme)
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1100, height: 700)

        // ⌘K Quick Switcher — small floating window for global search.
        Window("Quick switcher", id: "quick-switcher") {
            QuickSwitcher()
                .environmentObject(appState)
                .preferredColorScheme(appState.settings.appearance.colorScheme)
        }
        .defaultSize(width: 640, height: 440)
        .windowResizability(.contentSize)

        // Tags Increment 3b — Advanced Search window. ⌘⇧F. Distinct
        // from Quick Switcher (which stays minimal); this surface
        // carries the structured filters (types, tags, date, Vault
        // gating). Quick Switcher's footer (Phase 3d) hands off
        // here via `appState.searchHandoffQuery`.
        Window("Search", id: "search") {
            SearchScreen()
                .environmentObject(appState)
                .preferredColorScheme(appState.settings.appearance.colorScheme)
        }
        .defaultSize(width: 880, height: 640)

        Settings {
            SettingsView()
                .environmentObject(appState)
                .preferredColorScheme(appState.settings.appearance.colorScheme)
        }

        // Menu-bar quick-capture. A small SF Symbol in the system menu
        // bar opens a popover with type picker + title field; ⌘↩ saves
        // and the popover stays open for repeat capture, Esc closes.
        // The icon is always present in this build — no toggle yet.
        MenuBarExtra("PurpleLife quick capture", systemImage: "wand.and.sparkles") {
            QuickCaptureMenu()
                .environmentObject(appState)
                .preferredColorScheme(appState.settings.appearance.colorScheme)
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

/// ⌘⇧F — Edit / Window menu entry for the advanced Search window
/// (tags Increment 3b). Distinct from ⌘K Quick Switcher: Quick
/// Switcher is the always-quick path; this is for structured
/// filtering across types / tags / dates with Vault gating.
private struct SearchMenuItem: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Search…") {
            openWindow(id: "search")
        }
        .keyboardShortcut("f", modifiers: [.command, .shift])
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

/// View → Show Vault / Lock Vault. The same item flips its label
/// based on the current `vaultRevealed` state. ⇧⌘V triggers the
/// reveal flow (Touch ID / device password via `VaultAuthService`)
/// or instantly locks if already revealed. Re-locks on every quit
/// since `vaultRevealed` is runtime-only.
private struct VaultMenuItem: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        if appState.vaultRevealed {
            Button("Lock Vault") {
                appState.lockVault()
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])
        } else {
            Button("Show Vault…") {
                Task { @MainActor in
                    await appState.revealVault()
                }
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])
        }
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

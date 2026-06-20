import SwiftUI

@main
struct IrcleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settingsStore = SettingsStore()
    @StateObject private var model: IrcleModel
    @StateObject private var facesStore: FacesStore

    init() {
        let store = SettingsStore()
        _settingsStore = StateObject(wrappedValue: store)
        _model = StateObject(wrappedValue: IrcleModel(settingsStore: store))
        _facesStore = StateObject(wrappedValue: FacesStore(baseDir: SettingsStore.supportDirectory))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(settingsStore)
                .environmentObject(facesStore)
        }
        .defaultSize(width: 940, height: 620)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { UpdaterController.shared.checkForUpdates() }
                    .disabled(!UpdaterController.shared.canCheckForUpdates)
                Divider()
                ConnectMenuItem(model: model, settingsStore: settingsStore)
                Button("Disconnect") { model.disconnectSelected() }
                    .keyboardShortcut("k", modifiers: [.command, .option])
            }
            CommandGroup(after: .toolbar) {
                ConnectionsMenuItem()
                UserlistMenuItem()
                FacesMenuItem()
                LogsMenuItem()
                DCCMenuItem()
            }
            CommandMenu("Servers") {
                ForEach(settingsStore.settings.servers) { profile in
                    Button("Connect to \(profile.name)") { model.connect(to: profile) }
                }
                Divider()
                Button("Disconnect Current") { model.disconnectSelected() }
            }
            CommandGroup(after: .windowList) {
                BufferWindowsMenu(model: model)
            }
            CommandGroup(replacing: .help) {
                ManualMenuItem()
            }
        }

        // The Faces window — a separate window like classic Ircle. Single
        // instance, opened via `openWindow(id: "faces")`.
        Window("Faces", id: "faces") {
            FacesView()
                .environmentObject(model)
                .environmentObject(settingsStore)
                .environmentObject(facesStore)
        }
        .defaultSize(width: 420, height: 480)

        // The Log viewer — read-only browser of saved transcripts.
        Window("Chat Logs", id: "logs") {
            LogViewerView()
                .environmentObject(settingsStore)
        }
        .defaultSize(width: 640, height: 460)

        // The in-app manual (history + research + feature reference).
        Window("Ircle Manual", id: "manual") {
            ManualView()
                .environmentObject(settingsStore)
        }
        .defaultSize(width: 720, height: 640)

        // The Connections window — every saved server with live status +
        // Connect/Disconnect/Edit/Nick. The intuitive multi-server hub; opens in
        // every interface style (⌘⇧K).
        Window("Connections", id: "connections") {
            ConnectionsView()
                .environmentObject(model)
                .environmentObject(settingsStore)
        }
        .defaultSize(width: 460, height: 300)

        // ── Floating ("Workspace") interface style: classic Ircle 3.5 windows ──
        // One window per channel/query, addressed by buffer UUID.
        WindowGroup("Channel", id: "buffer", for: UUID.self) { $id in
            if let id {
                BufferWindowView(bufferID: id)
                    .environmentObject(model)
                    .environmentObject(settingsStore)
                    .environmentObject(facesStore)
            }
        }
        .defaultSize(width: 560, height: 420)

        // The detached nick-list window (follows the selected channel).
        Window("Userlist", id: "userlist") {
            UserlistWindowView()
                .environmentObject(model)
                .environmentObject(settingsStore)
                .environmentObject(facesStore)
        }
        .defaultSize(width: 340, height: 420)

        // The floating Inputline window (routes to the selected buffer).
        Window("Inputline", id: "inputline") {
            InputlineWindowView()
                .environmentObject(model)
                .environmentObject(settingsStore)
                .environmentObject(facesStore)
        }
        .defaultSize(width: 560, height: 120)

        // DCC Transfers — accept/decline inbound file + chat offers.
        Window("DCC Transfers", id: "dcc") {
            DCCTransfersView()
                .environmentObject(model.dcc)
                .environmentObject(settingsStore)
        }
        .defaultSize(width: 520, height: 360)

        // One window per accepted DCC chat, addressed by session UUID.
        WindowGroup("DCC Chat", id: "dccchat", for: UUID.self) { $sessionID in
            if let sessionID {
                DCCChatView(sessionID: sessionID)
                    .environmentObject(model.dcc)
                    .environmentObject(settingsStore)
            }
        }
        .defaultSize(width: 480, height: 420)

        Settings {
            SettingsView()
                .environmentObject(model)
                .environmentObject(settingsStore)
        }
    }
}

/// Smart Connect (⌘K): with a single configured server, connect it directly;
/// with none or several, open the Connections window so the user chooses (fixes
/// the old behavior of silently grabbing only the first server).
private struct ConnectMenuItem: View {
    let model: IrcleModel
    let settingsStore: SettingsStore
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Connect") {
            if model.canQuickConnect { model.connectDefault() }
            else { openWindow(id: "connections") }
        }
        .keyboardShortcut("k", modifiers: [.command])
    }
}

/// Window-menu entries for every open buffer: a channel/query opens (or focuses)
/// its own window; a server console selects it in the shared Console window. This
/// is how you (re)open a channel window you've closed in the Floating style.
private struct BufferWindowsMenu: View {
    @ObservedObject var model: IrcleModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        if !model.allBuffers.isEmpty {
            Divider()
            ForEach(model.allBuffers) { buffer in
                Button(buffer.name) {
                    if buffer.kind == .server { model.select(buffer) }
                    else { openWindow(id: "buffer", value: buffer.id) }
                }
            }
        }
    }
}

/// Menu item that opens the Connections window (the multi-server hub).
private struct ConnectionsMenuItem: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Connections") { openWindow(id: "connections") }
            .keyboardShortcut("k", modifiers: [.command, .shift])
    }
}

/// Menu item that floats the Userlist (nick list) window — the current channel's
/// users with the action grid + mode row. Available in every interface style
/// (⌘⇧U), so you can pop the user list out even in Clean/Classic.
private struct UserlistMenuItem: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Userlist") { openWindow(id: "userlist") }
            .keyboardShortcut("u", modifiers: [.command, .shift])
    }
}

/// Menu item that opens the Faces window. Lives in a View so it can read the
/// `openWindow` environment action (not available directly in `App`).
private struct FacesMenuItem: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Faces") { openWindow(id: "faces") }
            .keyboardShortcut("f", modifiers: [.command, .shift])
    }
}

/// Menu item that opens the Chat Logs window.
private struct LogsMenuItem: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Chat Logs") { openWindow(id: "logs") }
            .keyboardShortcut("l", modifiers: [.command, .shift])
    }
}

/// Menu item that opens the DCC Transfers window.
private struct DCCMenuItem: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("DCC Transfers") { openWindow(id: "dcc") }
            .keyboardShortcut("d", modifiers: [.command, .shift])
    }
}

/// Help-menu item that opens the in-app manual.
private struct ManualMenuItem: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Ircle Manual") { openWindow(id: "manual") }
            .keyboardShortcut("?", modifiers: [.command])
    }
}

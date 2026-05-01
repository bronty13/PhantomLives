import SwiftUI

@main
struct PurpleIRCApp: App {
    @StateObject private var model = ChatModel()

    var body: some Scene {
        WindowGroup("PurpleIRC") {
            // Wrap ContentView in a lock gate so an encrypted envelope
            // can't be bypassed. When the keystore is locked, the gate
            // shows an unlock sheet and blocks everything else.
            RootView()
                .environmentObject(model)
                .frame(minWidth: 900, minHeight: 560)
                .onAppear {
                    // Install the spell-check field-editor injector once
                    // the first window exists. Idempotent — covers the
                    // Watch Monitor secondary window too via the global
                    // didBecomeKeyNotification observer set up inside.
                    SpellCheckBootstrap.installOnAllWindows()
                    // macOS state-restoration auto-reopens the Watch Monitor
                    // window when it was open at last quit. The Watch Monitor
                    // is a "summon as needed" panel, not a primary window —
                    // close any auto-restored copy so the user only sees it
                    // when they explicitly open it via toolbar or ⇧⌘M.
                    closeWatchMonitorIfAutoRestored()
                }
        }
        .windowToolbarStyle(.unified)
        .commands {
            // Replace File → New Window with our own File menu items.
            CommandGroup(replacing: .newItem) {
                FileMenu().environmentObject(model)
            }
            // App menu additions: Lock Keystore + dangerous Reset Everything.
            CommandGroup(after: .appSettings) {
                AppMenuExtras().environmentObject(model)
            }
            // Edit menu — append find / line operations after the system
            // pasteboard items.
            CommandGroup(after: .pasteboard) {
                EditMenuExtras().environmentObject(model)
            }
            // Top-level custom menus.
            CommandMenu("View")         { ViewMenu().environmentObject(model) }
            CommandMenu("Buffer")       { BufferMenu().environmentObject(model) }
            CommandMenu("Network")      { NetworkMenu().environmentObject(model) }
            CommandMenu("Conversation") { ConversationMenu().environmentObject(model) }
            // Help menu — append below the system Help search field.
            CommandGroup(after: .help) {
                HelpMenuExtras().environmentObject(model)
            }
        }

        // Persistent secondary window — Watch Monitor — that shows
        // join / part / quit / nick across every connected network.
        // Identified by a stable string so .openWindow(id:) can find it.
        Window("Watch Monitor", id: "watch-monitor") {
            WatchMonitorView()
                .environmentObject(model)
        }
    }
}

// MARK: - Menu groups
//
// Each top-level menu is its own small View so the App.body's `.commands`
// block stays scannable. Buttons reach into ChatModel via the shared
// EnvironmentObject; menu state (enabled/disabled, toggles) is derived
// from `model.connectionState`, `model.connections`, etc. so the menu
// reflects the live app state without manual refreshes.

/// File menu — "New Network…" replaces the standard "New Window" because
/// PurpleIRC opens its real new things via the Networks panel and the
/// Setup sheet. Standard Close Window stays via the system File menu.
private struct FileMenu: View {
    @EnvironmentObject var model: ChatModel
    var body: some View {
        Button("New Network…") {
            model.pendingSetupTab = .servers
            model.showSetup = true
        }
        .keyboardShortcut("n", modifiers: [.command])

        Divider()

        Button("Close Buffer") { model.closeCurrentBuffer() }
            .keyboardShortcut("w", modifiers: [.command])
            .disabled(model.activeConnection?.selectedBufferID == nil)

        Divider()

        Button("Export Current Buffer…") { model.sendInput("/export buffer") }
        Button("Export All Buffers…")    { model.sendInput("/export all") }
    }
}

/// PurpleIRC menu extras — Lock Keystore + the dangerous reset.
/// Inserted after the system "Settings…" item so they sit with the
/// other app-level actions.
private struct AppMenuExtras: View {
    @EnvironmentObject var model: ChatModel
    var body: some View {
        Divider()
        Button("Lock Keystore") {
            model.keyStore.lock()
        }
        .keyboardShortcut("l", modifiers: [.command, .shift])
        .disabled(!model.keyStore.isUnlocked)

        Button(role: .destructive) {
            model.requestNuke()
        } label: {
            Text("Reset Everything (NUKE)…")
        }
    }
}

/// Edit menu extras — Find in Buffer (⌘F) routes through the slash
/// dispatcher's findRequest bridge so the menu and `/find` share one
/// path into BufferView.
private struct EditMenuExtras: View {
    @EnvironmentObject var model: ChatModel
    var body: some View {
        Divider()
        Button("Find in Buffer…") {
            model.findRequest = ""
        }
        .keyboardShortcut("f", modifiers: [.command])
    }
}

/// View menu — visual tuning shortcuts. Theme and density submenus pull
/// directly from the static `Theme.all` / `ChatDensity.allCases` lists so
/// adding a theme picks up automatically.
private struct ViewMenu: View {
    @EnvironmentObject var model: ChatModel
    var body: some View {
        Toggle("Show Raw Log", isOn: $model.showRawLog)

        Divider()

        Button("Increase Font Size") { model.incrementFontSize() }
            .keyboardShortcut("=", modifiers: [.command])
        Button("Decrease Font Size") { model.decrementFontSize() }
            .keyboardShortcut("-", modifiers: [.command])
        Button("Reset Font Size")    { model.resetFontSize() }
            .keyboardShortcut("0", modifiers: [.command])

        Divider()

        Menu("Density") {
            ForEach(ChatDensity.allCases) { d in
                Button {
                    model.setDensity(d)
                } label: {
                    HStack {
                        Text(d.displayName)
                        if model.settings.settings.chatDensity == d {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }

        Menu("Theme") {
            ForEach(Theme.all) { theme in
                Button {
                    model.setTheme(byID: theme.id)
                } label: {
                    HStack {
                        Text(theme.id)
                        if model.settings.settings.themeID == theme.id {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
    }
}

/// Buffer menu — buffer + network navigation, plus mark-read / clear.
private struct BufferMenu: View {
    @EnvironmentObject var model: ChatModel
    var body: some View {
        Button("Next Buffer") { model.cycleBuffer(forward: true) }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            .disabled(model.activeConnection?.buffers.count ?? 0 < 2)
        Button("Previous Buffer") { model.cycleBuffer(forward: false) }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            .disabled(model.activeConnection?.buffers.count ?? 0 < 2)

        Divider()

        Button("Next Network") { model.cycleNetwork(forward: true) }
            .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            .disabled(model.connections.count < 2)
        Button("Previous Network") { model.cycleNetwork(forward: false) }
            .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            .disabled(model.connections.count < 2)

        Divider()

        Button("Mark All as Read") { model.markAllReadEverywhere() }
            .keyboardShortcut("m", modifiers: [.command, .control])
        Button("Clear Buffer") { model.clearCurrentBuffer() }
            .disabled(model.activeConnection?.selectedBufferID == nil)
    }
}

/// Network menu — connection-state + accessory windows. Most of these
/// were on the old single "IRC" menu; they're regrouped here under a
/// clearer name and joined by Reconnect / Channel List shortcuts.
private struct NetworkMenu: View {
    @EnvironmentObject var model: ChatModel
    var body: some View {
        Button("Connect") { model.connect() }
            .keyboardShortcut("k", modifiers: [.command])
            .disabled(model.connectionState == .connected || model.connectionState == .connecting)
        Button("Disconnect") { model.disconnect() }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .disabled(model.connectionState != .connected)
        Button("Reconnect") { model.reconnect() }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(model.activeConnection == nil)

        Divider()

        Button("Channel List…") { model.showChannelList = true }
            .keyboardShortcut("l", modifiers: [.command, .shift])
        Button("Watchlist…") { model.showWatchlist = true }
            .keyboardShortcut("a", modifiers: [.command, .shift])
        WatchMonitorMenuItem()
        Button("DCC Transfers…") { model.showDCC = true }
            .keyboardShortcut("t", modifiers: [.command, .shift])
        Button("Seen Log…") { model.showSeenList = true }
    }
}

/// Conversation menu — actions scoped to the active channel / query.
/// Each prompt-driven item routes through the generic InputPrompt sheet
/// so we don't have a forest of one-off modal dialogs.
private struct ConversationMenu: View {
    @EnvironmentObject var model: ChatModel

    var body: some View {
        Button("Join Channel…") {
            model.requestInput(
                title: "Join channel",
                message: "Enter a channel name. The leading # is added automatically if you forget it.",
                placeholder: "#channel",
                confirmLabel: "Join"
            ) { name in
                model.sendInput("/join \(name)")
            }
        }
        .keyboardShortcut("j", modifiers: [.command, .shift])
        .disabled(model.connectionState != .connected)

        Button("Open Query…") {
            model.requestInput(
                title: "Open query",
                message: "Open a private message buffer with this nick.",
                placeholder: "nick",
                confirmLabel: "Open"
            ) { nick in
                model.sendInput("/query \(nick)")
            }
        }
        .keyboardShortcut("q", modifiers: [.command, .shift])
        .disabled(model.connectionState != .connected)

        Divider()

        Button("Set Topic…") {
            let current = model.activeConnection?.buffers
                .first(where: { $0.id == model.activeConnection?.selectedBufferID })?.topic ?? ""
            model.requestInput(
                title: "Set channel topic",
                message: "The new topic for this channel.",
                placeholder: "topic",
                defaultText: current,
                confirmLabel: "Set"
            ) { topic in
                model.sendInput("/topic \(topic)")
            }
        }
        .disabled(!isInChannel)

        Button("Invite User…") {
            model.requestInput(
                title: "Invite user",
                message: "Send an INVITE for the current channel.",
                placeholder: "nick",
                confirmLabel: "Invite"
            ) { nick in
                model.sendInput("/invite \(nick)")
            }
        }
        .disabled(!isInChannel)

        Divider()

        Button("WHOIS…") {
            model.requestInput(
                title: "WHOIS",
                message: "Look up information for a nick on this network.",
                placeholder: "nick",
                confirmLabel: "Look up"
            ) { nick in
                model.sendInput("/whois \(nick)")
            }
        }
        Button("WHOWAS…") {
            model.requestInput(
                title: "WHOWAS",
                message: "Look up the most recent record for a nick that has since quit.",
                placeholder: "nick",
                confirmLabel: "Look up"
            ) { nick in
                model.sendInput("/whowas \(nick)")
            }
        }
    }

    private var isInChannel: Bool {
        guard let conn = model.activeConnection,
              let id = conn.selectedBufferID,
              let buf = conn.buffers.first(where: { $0.id == id }) else { return false }
        return buf.kind == .channel
    }
}

/// Help menu extras — appended after the system Help search field.
private struct HelpMenuExtras: View {
    @EnvironmentObject var model: ChatModel
    var body: some View {
        Button("Slash Command Reference…") {
            model.helpPrefillQuery = ""
            model.showHelp = true
        }
        .keyboardShortcut("?", modifiers: [.command, .shift])

        Button("App Diagnostic Log…") { model.showAppLog = true }
        Button("Chat Logs…")          { model.showChatLogs = true }
    }
}

/// Close any Watch Monitor window AppKit auto-restored at launch. SwiftUI
/// scene IDs surface as the underlying NSWindow's `identifier` with a
/// "SwiftUI.Window-<id>" prefix; we match on the `watch-monitor` suffix so
/// future SwiftUI version bumps don't silently break the heuristic. Title
/// match is a belt-and-suspenders fallback. Runs after a tiny delay so
/// SwiftUI has time to finish window creation before we close it — closing
/// mid-creation can leave the menu bar's "Window" submenu in a stale state.
@MainActor
fileprivate func closeWatchMonitorIfAutoRestored() {
    Task { @MainActor in
        try? await Task.sleep(nanoseconds: 250_000_000)
        for window in NSApp.windows {
            let id = window.identifier?.rawValue ?? ""
            let title = window.title
            if id.contains("watch-monitor") || title == "Watch Monitor" {
                window.close()
            }
        }
    }
}

/// IRC menu item that opens the Watch Monitor window. `.openWindow(id:)`
/// lives in `Environment(\.openWindow)`, which is only available inside
/// a View — wrapping in this tiny helper keeps the App.body clean.
struct WatchMonitorMenuItem: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Watch Monitor…") {
            openWindow(id: "watch-monitor")
        }
        .keyboardShortcut("m", modifiers: [.command, .shift])
    }
}

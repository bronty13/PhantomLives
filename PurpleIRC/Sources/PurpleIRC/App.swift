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
                }
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("IRC") {
                Button("Connect") { model.connect() }
                    .keyboardShortcut("k", modifiers: [.command])
                    .disabled(model.connectionState == .connected || model.connectionState == .connecting)
                Button("Disconnect") { model.disconnect() }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                    .disabled(model.connectionState != .connected)
                Divider()
                Button("Watchlist…") { model.showWatchlist = true }
                    .keyboardShortcut("w", modifiers: [.command, .shift])
                WatchMonitorMenuItem()
                Button("DCC Transfers…") { model.showDCC = true }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                Button("Setup…") { model.showSetup = true }
                    .keyboardShortcut(",", modifiers: [.command])
                Toggle("Show Raw Log", isOn: $model.showRawLog)
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

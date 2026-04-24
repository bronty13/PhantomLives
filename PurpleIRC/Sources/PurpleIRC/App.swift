import SwiftUI

@main
struct PurpleIRCApp: App {
    @StateObject private var model = ChatModel()

    var body: some Scene {
        WindowGroup("PurpleIRC") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 900, minHeight: 560)
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
                Button("DCC Transfers…") { model.showDCC = true }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                Button("Setup…") { model.showSetup = true }
                    .keyboardShortcut(",", modifiers: [.command])
                Toggle("Show Raw Log", isOn: $model.showRawLog)
            }
        }
    }
}

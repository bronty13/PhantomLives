import SwiftUI
import AppKit
import UniformTypeIdentifiers

@main
struct PurpleSpeakApp: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("PurpleSpeak") {
            ContentView()
                .environmentObject(appState)
                .environmentObject(appState.settingsStore)
                .environmentObject(appState.documentStore)
                .environmentObject(appState.tts)
                .environmentObject(appState.modelManager)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1180, height: 800)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(after: .newItem) {
                Button("Import Documents…") { appState.presentImportPanel() }
                    .keyboardShortcut("o")
                Button("New from Pasted Text") { appState.startPasteFlow() }
                    .keyboardShortcut("n")
                Button("Read Web Article…") { appState.startWebFlow() }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                Divider()
                Button("Transcribe Audio / Video…") { appState.presentTranscribePanel() }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
            }
            CommandMenu("Playback") {
                Button("Play / Pause") { appState.togglePlayPause() }
                    .keyboardShortcut(.space, modifiers: [])
                Button("Stop") { appState.tts.stop() }
                    .keyboardShortcut(".", modifiers: [.command])
                Divider()
                Button("Next Paragraph") { appState.skip(byParagraphs: 1) }
                    .keyboardShortcut(.rightArrow, modifiers: [.command])
                Button("Previous Paragraph") { appState.skip(byParagraphs: -1) }
                    .keyboardShortcut(.leftArrow, modifiers: [.command])
                Divider()
                Button("Export Audio…") { appState.exportCurrentAudio() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(appState.currentText.isEmpty)
            }
            CommandGroup(after: .windowArrangement) {
                Divider()
                Button("Reset Window State…") {
                    let alert = NSAlert()
                    alert.messageText = "Reset Window State?"
                    alert.informativeText = "Sidebar and window size return to defaults. Restart PurpleSpeak after confirming."
                    alert.addButton(withTitle: "Reset")
                    alert.addButton(withTitle: "Cancel")
                    if alert.runModal() == .alertFirstButtonReturn {
                        WindowStateGuard.forceReset(appName: "PurpleSpeak",
                                                    resetVersion: AppDelegate.windowResetVersion)
                    }
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(appState.settingsStore)
                .environmentObject(appState.modelManager)
                .frame(minWidth: 620, minHeight: 460)
        }
    }
}

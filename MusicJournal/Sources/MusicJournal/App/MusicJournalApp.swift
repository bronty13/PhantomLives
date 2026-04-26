// MusicJournalApp.swift
// Entry point for the Music Journal macOS application.
// Wires the AppState environment object into the window hierarchy and
// registers global menu commands for sync and export operations.

import SwiftUI

@main
struct MusicJournalApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                // Forward the Spotify OAuth callback URL scheme to the auth service.
                .onOpenURL { url in
                    appState.spotifyAuth.handleCallback(url: url)
                }
        }
        .commands {
            // ⌘⇧R — sync shortcut mirrors the toolbar button.
            CommandGroup(after: .newItem) {
                Button("Sync Now") {
                    Task { await appState.sync() }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
            ExportMenuCommands(appState: appState)
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

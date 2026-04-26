// SettingsView.swift
// macOS Settings window (⌘,) containing two tabs:
//  - Spotify: account status, last sync time, sync-now button, disconnect.
//  - Data: full JSON export and import for backup/restore.

import SwiftUI

/// Settings window root — tabbed between Spotify and Data panels.
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showImportPicker = false
    @State private var importError: String?

    var body: some View {
        TabView {
            SpotifySettingsView()
                .tabItem { Label("Spotify", systemImage: "music.note") }
                .tag(0)

            DataSettingsView(
                showImportPicker: $showImportPicker,
                importError: $importError
            )
            .tabItem { Label("Data", systemImage: "cylinder") }
            .tag(1)
        }
        .padding(20)
        .frame(width: 480, height: 280)
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: [.json]
        ) { result in
            switch result {
            case .success(let url):
                do {
                    guard url.startAccessingSecurityScopedResource() else { return }
                    defer { url.stopAccessingSecurityScopedResource() }
                    let data = try Data(contentsOf: url)
                    try ExportService.shared.importDatabaseFromJSON(data)
                    Task { await appState.loadFromDatabase() }
                } catch {
                    importError = error.localizedDescription
                }
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
    }
}

// MARK: - SpotifySettingsView

/// Spotify tab: shows connected account name, last sync date, and controls.
struct SpotifySettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section {
                if appState.isAuthenticated {
                    LabeledContent("Account") {
                        HStack {
                            Text(appState.spotifyAuth.displayName ?? "Connected")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Disconnect", role: .destructive) {
                                appState.spotifyAuth.logout()
                            }
                        }
                    }
                    LabeledContent("Last Sync") {
                        Text(appState.lastSyncDate.map {
                            $0.formatted(date: .abbreviated, time: .shortened)
                        } ?? "Never")
                        .foregroundStyle(.secondary)
                    }
                    Button("Sync Now") {
                        Task { await appState.sync() }
                    }
                    .disabled(appState.isSyncing)
                } else {
                    Button("Connect Spotify") {
                        appState.spotifyAuth.startLogin()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - DataSettingsView

/// Data tab: JSON backup export and full-replace import.
struct DataSettingsView: View {
    @EnvironmentObject var appState: AppState
    @Binding var showImportPicker: Bool
    @Binding var importError: String?

    var body: some View {
        Form {
            Section {
                Button("Export Full Database (JSON)") {
                    do {
                        let data = try ExportService.shared.exportDatabaseAsJSON()
                        let panel = NSSavePanel()
                        panel.nameFieldStringValue = "MusicJournal-\(Date().formatted(.iso8601)).json"
                        panel.allowedContentTypes = [.json]
                        if panel.runModal() == .OK, let url = panel.url {
                            try data.write(to: url)
                        }
                    } catch {}
                }

                Button("Import Database from JSON...") {
                    showImportPicker = true
                }

                if let error = importError {
                    Text(error).foregroundStyle(.red).font(.caption)
                }

                Text("Import replaces all local data. Export a backup first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

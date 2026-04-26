// SettingsView.swift
// macOS Settings window (⌘,) containing two tabs:
//  - Spotify: account status, last sync time, sync-now button, disconnect.
//  - Data: full JSON export and import for backup/restore.

import SwiftUI

/// Settings window root — tabbed between Spotify, LLM, and Data panels.
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showImportPicker = false
    @State private var importError: String?

    var body: some View {
        TabView {
            SpotifySettingsView()
                .tabItem { Label("Spotify", systemImage: "music.note") }
                .tag(0)

            LLMSettingsView()
                .tabItem { Label("LLM Prompt", systemImage: "text.bubble") }
                .tag(1)

            DataSettingsView(
                showImportPicker: $showImportPicker,
                importError: $importError
            )
            .tabItem { Label("Data", systemImage: "cylinder") }
            .tag(2)
        }
        .padding(20)
        .frame(width: 620, height: 540)
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

// MARK: - LLMSettingsView

/// LLM tab: two editable prompt templates (Track and Playlist) used by the
/// Copy LLM Prompt actions. Both auto-save to UserDefaults on edit.
struct LLMSettingsView: View {
    enum Kind: String, CaseIterable, Identifiable {
        case track = "Track"
        case playlist = "Playlist"
        var id: String { rawValue }
    }

    @State private var selection: Kind = .track
    @State private var trackTemplate: String = LLMPromptService.template
    @State private var playlistTemplate: String = LLMPromptService.playlistTemplate
    @State private var batchSizeText: String = String(LLMPromptService.batchSize)

    private static let trackPlaceholders = """
    Placeholders: \
    {{TRACK_NAME}}, {{ARTIST}}, {{ALBUM}}, {{YEAR}}, {{DURATION}}, {{SPOTIFY_URL}}
    """
    private static let playlistPlaceholders = """
    Placeholders: \
    {{PLAYLIST_NAME}}, {{OWNER}}, {{DESCRIPTION}}, {{TRACK_COUNT}}, {{TRACK_LIST}}
    """

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Prompt", selection: $selection) {
                ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)

            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: binding)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 240)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                .onChange(of: trackTemplate) { LLMPromptService.setTemplate(trackTemplate) }
                .onChange(of: playlistTemplate) { LLMPromptService.setPlaylistTemplate(playlistTemplate) }

            Text(placeholders)
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack {
                Button("Reset to Default") { resetSelected() }
                Spacer()
            }

            if selection == .playlist {
                Divider().padding(.vertical, 4)
                HStack(spacing: 8) {
                    Text("Tracks per batch:").font(.caption)
                    TextField("", text: $batchSizeText)
                        .frame(width: 60)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { commitBatchSize() }
                    Stepper("", value: Binding(
                        get: { Int(batchSizeText) ?? LLMPromptService.batchSize },
                        set: { batchSizeText = String($0); commitBatchSize() }
                    ), in: 5...500, step: 5)
                    .labelsHidden()
                    Text("Each Copy Prompt picks up to this many of the still-unannotated tracks.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func commitBatchSize() {
        if let n = Int(batchSizeText) {
            LLMPromptService.setBatchSize(n)
            batchSizeText = String(LLMPromptService.batchSize)
        } else {
            batchSizeText = String(LLMPromptService.batchSize)
        }
    }

    private var binding: Binding<String> {
        selection == .track ? $trackTemplate : $playlistTemplate
    }

    private var description: String {
        switch selection {
        case .track:
            return "Used by Copy LLM Prompt on the track detail panel. The LLM should reply with a JSON object containing songYear, lyricSummary, lyrics, and notes."
        case .playlist:
            return "Used by the LLM menu on the playlist detail panel. The response can update playlistNotes / playlistTitle and a batch of tracks (matched back by spotifyId)."
        }
    }

    private var placeholders: String {
        selection == .track ? Self.trackPlaceholders : Self.playlistPlaceholders
    }

    private func resetSelected() {
        switch selection {
        case .track:
            LLMPromptService.setTemplate("")
            trackTemplate = LLMPromptService.defaultTemplate
        case .playlist:
            LLMPromptService.setPlaylistTemplate("")
            playlistTemplate = LLMPromptService.defaultPlaylistTemplate
        }
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

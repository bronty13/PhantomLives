// PlaylistDetailView.swift
// Detail column shown when a playlist is selected in the sidebar.
// Layout: PlaylistHeaderView (cover + metadata) above a TrackListView (Table),
// with an optional TrackDetailView panel on the right when a track is selected.
// Reloads tracks on playlist change and after every sync.

import SwiftUI

/// Full-detail view for a selected playlist: header, track table, and
/// an optional side panel for the selected track.
///
/// Takes only the playlist's `spotifyId` and resolves the live `Playlist`
/// value from `AppState` on every render. This means `saveNotes` triggers
/// a re-render with fresh DB data automatically — earlier the view held a
/// snapshot taken at construction, so edits only appeared after restart.
struct PlaylistDetailView: View {
    let playlistId: String
    @EnvironmentObject var appState: AppState
    @State private var tracks: [Track] = []
    @State private var selectedTrackId: String?
    /// Derived from selectedTrackId so selection survives track list reloads.
    private var selectedTrack: Track? { tracks.first { $0.spotifyId == selectedTrackId } }
    @State private var editingNotes = false
    @State private var notes: String = ""
    @State private var customTitle: String = ""
    @State private var showExport = false

    // LLM playlist round-trip state.
    @State private var llmError: String?
    @State private var llmStatus: String?

    /// Live lookup against the AppState array — re-runs on every render.
    private var playlist: Playlist? {
        appState.playlists.first { $0.spotifyId == playlistId }
    }

    /// True when a track is selected; toggling closes the inspector and
    /// clears the selection so the inspector close button works as expected.
    private var inspectorBinding: Binding<Bool> {
        Binding(
            get: { selectedTrackId != nil },
            set: { newValue in if !newValue { selectedTrackId = nil } }
        )
    }

    var body: some View {
        Group {
            if let playlist {
                content(for: playlist)
            } else {
                // Playlist removed from AppState (e.g. user disconnected
                // mid-view). Showing nothing is preferable to crashing.
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func content(for playlist: Playlist) -> some View {
        VStack(spacing: 0) {
            // Header shows the actual track count from the DB, not Spotify's
            // potentially-stale estimate.
            PlaylistHeaderView(playlist: playlist, trackCount: tracks.count)

            Divider()

            TrackListView(tracks: tracks, selectedTrackId: $selectedTrackId)
        }
        // `.inspector` is the macOS 14+ native trailing-panel API. Unlike
        // HSplitView, it doesn't force the parent NavigationSplitView to
        // renegotiate column widths when it appears/disappears — which was
        // the source of the sidebar leading-edge clip on track selection.
        .inspector(isPresented: inspectorBinding) {
            Group {
                if let track = selectedTrack {
                    TrackDetailView(track: track, onSave: { _ in
                        Task { await loadTracks() }
                    })
                } else {
                    EmptyView()
                }
            }
            .inspectorColumnWidth(min: 280, ideal: 320, max: 400)
        }
        .navigationTitle(playlist.userTitle.isEmpty ? playlist.name : playlist.userTitle)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Edit Notes") {
                    notes = playlist.userNotes
                    customTitle = playlist.userTitle
                    editingNotes = true
                }
                Button("Export") { showExport = true }
                Menu {
                    Button(copyPromptLabel) { copyPlaylistPrompt(playlist) }
                        .disabled(unannotatedCount == 0)
                    Button("Apply Response") { applyPlaylistResponse(playlist) }
                } label: {
                    Label(llmMenuLabel, systemImage: "text.bubble")
                }
                .help("Playlist-level LLM round-trip. Each Copy Prompt picks the next \(LLMPromptService.batchSize) tracks that don't yet have notes/summary — paste into your LLM, copy the JSON reply, click Apply.")
            }
        }
        // Reload when the selected playlist changes or after a sync completes.
        .task(id: playlistId) { await loadTracks() }
        .onChange(of: appState.lastSyncDate) { Task { await loadTracks() } }
        .alert("LLM", isPresented: .constant(llmError != nil)) {
            Button("OK") { llmError = nil }
        } message: {
            Text(llmError ?? "")
        }
        .alert("LLM Apply Result", isPresented: .constant(llmStatus != nil)) {
            Button("OK") { llmStatus = nil }
        } message: {
            Text(llmStatus ?? "")
        }
        .sheet(isPresented: $editingNotes) {
            PlaylistNotesSheet(
                playlistName: playlist.name,
                notes: $notes,
                customTitle: $customTitle,
                onSave: saveNotes
            )
        }
        .sheet(isPresented: $showExport) {
            ExportSheet(playlist: playlist)
        }
    }

    private func loadTracks() async {
        do {
            tracks = try DatabaseService.shared.fetchTracks(forPlaylist: playlistId)
        } catch {}
    }

    private func saveNotes() {
        try? DatabaseService.shared.updatePlaylistNotes(
            spotifyId: playlistId,
            notes: notes,
            title: customTitle
        )
        Task { await appState.loadFromDatabase() }
    }

    // MARK: - LLM playlist round-trip

    /// Number of tracks in this playlist that haven't been LLM-annotated yet.
    private var unannotatedCount: Int {
        LLMPromptService.tracksNeedingAnnotation(tracks).count
    }

    /// Number of tracks the next batch will include (capped by `batchSize`).
    private var nextBatchCount: Int {
        min(unannotatedCount, LLMPromptService.batchSize)
    }

    private var llmMenuLabel: String {
        if unannotatedCount == 0 {
            return "LLM (all \(tracks.count) annotated)"
        }
        return "LLM (\(unannotatedCount) unannotated)"
    }

    private var copyPromptLabel: String {
        if unannotatedCount == 0 { return "All Tracks Annotated" }
        return "Copy Prompt — Next \(nextBatchCount) of \(unannotatedCount)"
    }

    private func copyPlaylistPrompt(_ playlist: Playlist) {
        let pending = LLMPromptService.tracksNeedingAnnotation(tracks)
        guard !pending.isEmpty else {
            llmStatus = "Every track in this playlist already has LLM annotation. Nothing to copy."
            return
        }
        let batch = Array(pending.prefix(LLMPromptService.batchSize))
        let prompt = LLMPromptService.renderPlaylist(
            playlist,
            batchTracks: batch,
            totalCount: tracks.count
        )
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(prompt, forType: .string)
        llmStatus = """
        Prompt copied for \(batch.count) tracks (of \(pending.count) remaining unannotated).

        Paste into your LLM, copy the JSON response, then click Apply Response.
        """
    }

    private func applyPlaylistResponse(_ playlist: Playlist) {
        let pb = NSPasteboard.general
        guard let raw = pb.string(forType: .string), !raw.isEmpty else {
            llmError = LLMPromptService.ParseError.empty.localizedDescription
            return
        }
        do {
            let resp = try LLMPromptService.parsePlaylistResponse(raw)

            // Playlist-level updates — only if the LLM provided non-empty
            // values AND the existing playlist field is empty. This prevents
            // batch-N's playlist summary from clobbering batch-1's.
            let newNotes = resp.playlistNotes ?? ""
            let newTitle = resp.playlistTitle ?? ""
            let writeNotes = !newNotes.isEmpty && playlist.userNotes.isEmpty
            let writeTitle = !newTitle.isEmpty && playlist.userTitle.isEmpty
            if writeNotes || writeTitle {
                try? DatabaseService.shared.updatePlaylistNotes(
                    spotifyId: playlistId,
                    notes: writeNotes ? newNotes : playlist.userNotes,
                    title: writeTitle ? newTitle : playlist.userTitle
                )
            }

            // Per-track updates (matched by spotifyId).
            let updates: [DatabaseService.TrackUpdate] = (resp.tracks ?? []).map { t in
                DatabaseService.TrackUpdate(
                    spotifyId: t.spotifyId,
                    songYear: t.songYear,
                    lyrics: t.lyrics?.isEmpty == false ? t.lyrics : nil,
                    lyricSummary: t.lyricSummary?.isEmpty == false ? t.lyricSummary : nil,
                    notes: t.notes?.isEmpty == false ? t.notes : nil,
                    rating: nil
                )
            }
            let appliedIds = (try? DatabaseService.shared.applyTrackUpdates(updates)) ?? []
            let skipped = updates.count - appliedIds.count

            // Refresh views.
            Task {
                await appState.loadFromDatabase()
                await loadTracks()
            }

            llmStatus = formatApplyReport(
                appliedTracks: appliedIds.count,
                skippedTracks: skipped,
                wrotePlaylistNotes: writeNotes,
                wrotePlaylistTitle: writeTitle,
                hadPlaylistNotesInResponse: !newNotes.isEmpty,
                hadPlaylistTitleInResponse: !newTitle.isEmpty
            )
        } catch {
            llmError = error.localizedDescription
        }
    }

    private func formatApplyReport(
        appliedTracks: Int,
        skippedTracks: Int,
        wrotePlaylistNotes: Bool,
        wrotePlaylistTitle: Bool,
        hadPlaylistNotesInResponse: Bool,
        hadPlaylistTitleInResponse: Bool
    ) -> String {
        var lines: [String] = []
        if appliedTracks == 0 && !wrotePlaylistNotes && !wrotePlaylistTitle {
            lines.append("Nothing was applied.")
        } else {
            lines.append("Applied:")
            if appliedTracks > 0 {
                lines.append("• \(appliedTracks) track\(appliedTracks == 1 ? "" : "s")")
            }
            if wrotePlaylistNotes { lines.append("• Playlist notes") }
            if wrotePlaylistTitle { lines.append("• Playlist title") }
        }
        if skippedTracks > 0 {
            lines.append("")
            lines.append("Skipped \(skippedTracks) track update\(skippedTracks == 1 ? "" : "s") — spotifyId not found in this playlist.")
        }
        if hadPlaylistNotesInResponse && !wrotePlaylistNotes {
            lines.append("")
            lines.append("Playlist notes in response were ignored (this playlist already had notes — first batch wins).")
        }
        if hadPlaylistTitleInResponse && !wrotePlaylistTitle {
            lines.append("Playlist title in response was ignored (custom title already set).")
        }
        let remaining = unannotatedCount - appliedTracks
        if remaining > 0 {
            lines.append("")
            lines.append("\(remaining) tracks still need annotation. Click Copy Prompt again to continue.")
        } else {
            lines.append("")
            lines.append("🎉 All tracks in this playlist are now annotated.")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - PlaylistHeaderView

/// Large header above the track table showing cover art, description,
/// owner info, and any user notes.
struct PlaylistHeaderView: View {
    let playlist: Playlist
    /// Actual track count from the DB, passed in from PlaylistDetailView.
    let trackCount: Int

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            AsyncImage(url: URL(string: playlist.imageURL ?? "")) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    ZStack {
                        Color.secondary.opacity(0.15)
                        Image(systemName: "music.note.list")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 110, height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)

            VStack(alignment: .leading, spacing: 5) {
                // Show the Spotify name as a subtitle when a custom title is set
                if !playlist.userTitle.isEmpty {
                    Text(playlist.name)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                if !playlist.description.isEmpty {
                    Text(playlist.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 12) {
                    Label("\(trackCount) tracks", systemImage: "music.note")
                    Label(playlist.ownerName, systemImage: "person")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !playlist.userNotes.isEmpty {
                    Text(playlist.userNotes)
                        .font(.footnote)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .padding(8)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

// MARK: - TrackListView

/// Sortable table of tracks. Columns: position, title, artist, album,
/// star rating, and duration.
struct TrackListView: View {
    let tracks: [Track]
    @Binding var selectedTrackId: String?

    var body: some View {
        Table(tracks, selection: $selectedTrackId) {
            TableColumn("#") { track in
                Text("\(tracks.firstIndex(where: { $0.spotifyId == track.spotifyId }).map { $0 + 1 } ?? 0)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .width(40)

            TableColumn("Title") { track in
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.name).lineLimit(1)
                    // Note indicator shown when the user has written notes for this track
                    if !track.userNotes.isEmpty {
                        Image(systemName: "note.text")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }
            }

            TableColumn("Artist") { Text($0.artistNames).lineLimit(1) }
            TableColumn("Album") { Text($0.albumName).lineLimit(1) }

            TableColumn("★") { track in
                if let r = track.userRating {
                    Text(String(repeating: "★", count: r))
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }
            }
            .width(50)

            TableColumn("Time") { track in
                Text(track.durationFormatted)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(50)
        }
    }
}

// MARK: - PlaylistNotesSheet

/// Modal sheet for editing a playlist's custom title and free-form notes.
struct PlaylistNotesSheet: View {
    let playlistName: String
    @Binding var notes: String
    @Binding var customTitle: String
    let onSave: () -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Playlist Notes")
                .font(.title2.bold())

            Text("Custom Title")
                .font(.headline)
            TextField("Leave blank to use Spotify title", text: $customTitle)
                .textFieldStyle(.roundedBorder)

            Text("My Notes")
                .font(.headline)
            MarkdownEditor(text: $notes, minHeight: 200)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { onSave(); dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}

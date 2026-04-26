// PlaylistDetailView.swift
// Detail column shown when a playlist is selected in the sidebar.
// Layout: PlaylistHeaderView (cover + metadata) above a TrackListView (Table),
// with an optional TrackDetailView panel on the right when a track is selected.
// Reloads tracks on playlist change and after every sync.

import SwiftUI

/// Full-detail view for a selected playlist: header, track table, and
/// an optional side panel for the selected track.
struct PlaylistDetailView: View {
    let playlist: Playlist
    @EnvironmentObject var appState: AppState
    @State private var tracks: [Track] = []
    @State private var selectedTrackId: String?
    /// Derived from selectedTrackId so selection survives track list reloads.
    private var selectedTrack: Track? { tracks.first { $0.spotifyId == selectedTrackId } }
    @State private var editingNotes = false
    @State private var notes: String = ""
    @State private var customTitle: String = ""
    @State private var showExport = false

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                // Header shows the actual track count from the DB, not Spotify's
                // potentially-stale estimate.
                PlaylistHeaderView(playlist: playlist, trackCount: tracks.count)

                Divider()

                TrackListView(tracks: tracks, selectedTrackId: $selectedTrackId)
            }
            .frame(minWidth: 360)

            if let track = selectedTrack {
                TrackDetailView(track: track, onSave: { _ in
                    Task { await loadTracks() }
                })
                .frame(minWidth: 280, maxWidth: 380)
            }
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
            }
        }
        // Reload when the selected playlist changes or after a sync completes.
        .task(id: playlist.spotifyId) { await loadTracks() }
        .onChange(of: appState.lastSyncDate) { Task { await loadTracks() } }
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
            tracks = try DatabaseService.shared.fetchTracks(forPlaylist: playlist.spotifyId)
        } catch {}
    }

    private func saveNotes() {
        try? DatabaseService.shared.updatePlaylistNotes(
            spotifyId: playlist.spotifyId,
            notes: notes,
            title: customTitle
        )
        Task { await appState.loadFromDatabase() }
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
            TextEditor(text: $notes)
                .font(.body)
                .frame(minHeight: 200)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))

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

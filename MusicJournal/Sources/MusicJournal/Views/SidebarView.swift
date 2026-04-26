// SidebarView.swift
// Left sidebar — searchable list of all synced playlists.
// Each row shows a 44×44 thumbnail, the playlist name (or custom title),
// and the track count. Rows use listRowInsets to ensure the thumbnail
// is not clipped against the window edge.

import SwiftUI

/// Sidebar column listing all playlists with live search filtering.
struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @Binding var selectedPlaylist: Playlist?
    @State private var searchText = ""

    /// Playlists filtered by the search text; shows all when the field is empty.
    var filtered: [Playlist] {
        guard !searchText.isEmpty else { return appState.playlists }
        return appState.playlists.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.userTitle.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List(filtered, selection: $selectedPlaylist) { playlist in
            PlaylistRowView(playlist: playlist)
                .tag(playlist)
                // Explicit insets prevent the thumbnail from touching the
                // left edge of the window when no playlist is selected.
                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 8))
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search playlists")
        .navigationTitle("Music Journal")
        .navigationSubtitle("\(appState.playlists.count) playlists")
        .toolbar {
            ToolbarItem {
                if let date = appState.lastSyncDate {
                    Text("Synced \(date.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - PlaylistRowView

/// Single row in the sidebar playlist list.
/// Shows a cover thumbnail, the display name (custom title or Spotify name),
/// and the track count with a music note icon.
struct PlaylistRowView: View {
    let playlist: Playlist

    var body: some View {
        HStack(spacing: 10) {
            // Cover art with fallback placeholder
            AsyncImage(url: URL(string: playlist.imageURL ?? "")) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    ZStack {
                        Color.secondary.opacity(0.15)
                        Image(systemName: "music.note.list")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 16))
                    }
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 3) {
                // Prefer custom title if the user has set one
                Text(playlist.userTitle.isEmpty ? playlist.name : playlist.userTitle)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 4) {
                    Image(systemName: "music.note")
                        .font(.caption2)
                    Text("\(playlist.trackCount) tracks")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 2)
    }
}

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

    /// Only the playlists owned by the signed-in Spotify user.
    /// Spotify's development mode returns zero tracks for playlists the user
    /// does not own, so showing them in the sidebar is just noise. If the
    /// user ID is unknown (legacy installs), fall back to showing everything.
    private var ownedByUser: [Playlist] {
        guard let userId = appState.userSpotifyId else {
            return appState.playlists
        }
        return appState.playlists.filter { $0.ownerSpotifyId == userId }
    }

    /// User-owned playlists filtered by the search text.
    var filtered: [Playlist] {
        guard !searchText.isEmpty else { return ownedByUser }
        return ownedByUser.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.userTitle.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        // Inline search + list. Avoids `.searchable(.sidebar)` and
        // `.navigationTitle` / `.navigationSubtitle` — the implicit chrome
        // they install in the sidebar column was the source of the
        // leading-edge content shift on macOS Tahoe NavigationSplitView.
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search playlists", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            List(filtered, selection: $selectedPlaylist) { playlist in
                PlaylistRowView(playlist: playlist)
                    .tag(playlist)
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 8))
            }
            .scrollContentBackground(.hidden)

            HStack {
                Text("\(ownedByUser.count) playlists")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
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

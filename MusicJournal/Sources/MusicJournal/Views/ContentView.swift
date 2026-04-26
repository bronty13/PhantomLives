// ContentView.swift
// Root view of the application.
// Shows WelcomeView when unauthenticated, or a manual HStack-based
// sidebar-detail layout once the user has connected Spotify. A frosted-glass
// status banner slides in at the bottom of the window during an active sync.

import SwiftUI

/// Root container. Uses a plain `HStack` instead of `NavigationSplitView`
/// because three successive attempts at fixing macOS Tahoe's sidebar
/// chrome-positioning bug all failed under one repro path or another. With
/// a manual layout we own every pixel of the sidebar's frame and there is
/// no implicit chrome to mis-position.
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedPlaylist: Playlist?

    var body: some View {
        Group {
            if !appState.isAuthenticated {
                WelcomeView()
            } else {
                HStack(spacing: 0) {
                    SidebarView(selectedPlaylist: $selectedPlaylist)
                        .frame(width: 300)
                        .background(.ultraThinMaterial)
                    Divider()
                    Group {
                        if let playlist = selectedPlaylist {
                            // Pass only the ID — PlaylistDetailView resolves the
                            // live value from AppState so saves reflect immediately.
                            PlaylistDetailView(playlistId: playlist.spotifyId)
                        } else {
                            EmptyStateView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: 1000, idealWidth: 1200, minHeight: 650)
        // Sync progress banner — shown only while a sync is running and
        // status text is available (first status is set after the initial
        // playlist fetch completes).
        .overlay(alignment: .bottom) {
            if appState.isSyncing, let status = appState.syncStatus {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text(status)
                        .font(.callout)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial)
                .overlay(alignment: .top) { Divider() }
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if let last = appState.lastSyncDate {
                    Text("Synced \(last.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ToolbarItem(placement: .automatic) {
                if appState.isSyncing {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Button {
                        Task { await appState.sync() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Sync with Spotify")
                }
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    appState.spotifyAuth.logout()
                } label: {
                    Image(systemName: "person.crop.circle.badge.xmark")
                }
                .help("Disconnect Spotify — reconnect to refresh permissions")
            }
        }
        .alert("Sync Error", isPresented: .constant(appState.syncError != nil)) {
            Button("OK") { appState.syncError = nil }
        } message: {
            Text(appState.syncError ?? "")
        }
    }
}

// MARK: - EmptyStateView

/// Placeholder shown in the detail column when no playlist is selected.
struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("Select a playlist")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }
}

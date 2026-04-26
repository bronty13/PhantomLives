// ContentView.swift
// Root view of the application.
// Shows WelcomeView when unauthenticated, or the NavigationSplitView layout
// once the user has connected Spotify. A frosted-glass status banner slides
// in at the bottom of the window during an active sync.

import SwiftUI

/// Root container that gates on authentication state and hosts the main
/// sidebar-detail navigation split view.
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedPlaylist: Playlist?

    var body: some View {
        Group {
            if !appState.isAuthenticated {
                WelcomeView()
            } else {
                NavigationSplitView {
                    SidebarView(selectedPlaylist: $selectedPlaylist)
                        .navigationSplitViewColumnWidth(min: 240, ideal: 280)
                } detail: {
                    if let playlist = selectedPlaylist {
                        PlaylistDetailView(playlist: playlist)
                    } else {
                        EmptyStateView()
                    }
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

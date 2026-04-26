// AppState.swift
// Central observable store for the application.
// All views receive this object via @EnvironmentObject and react to
// published changes driven by Spotify sync and database operations.

import SwiftUI
import Combine

/// Top-level application state. Owns Spotify auth, the local database
/// reference, and all sync lifecycle flags consumed by the UI.
@MainActor
final class AppState: ObservableObject {

    // MARK: - Published state

    /// All playlists currently stored in the local database, sorted by name.
    @Published var playlists: [Playlist] = []

    /// True while a Spotify sync is running; drives the toolbar spinner and
    /// disables the sync button to prevent concurrent syncs.
    @Published var isSyncing = false

    /// Non-nil when a sync fails; consumed by the error alert in ContentView.
    @Published var syncError: String?

    /// Per-playlist progress message shown in the frosted-glass status banner.
    @Published var syncStatus: String?

    /// Mirrors SpotifyAuthService.isAuthenticated so views can gate on a
    /// single source rather than drilling into the auth service directly.
    @Published var isAuthenticated = false

    /// Mirrors SpotifyAuthService.userSpotifyId so views observing AppState
    /// re-render when the ID is captured/cleared (SwiftUI does not observe
    /// nested ObservableObjects automatically).
    @Published var userSpotifyId: String?

    /// Last successful full-sync timestamp; persisted across launches via
    /// UserDefaults so the toolbar "Synced X ago" label survives restarts.
    @Published var lastSyncDate: Date? = UserDefaults.standard.object(forKey: "lastSyncDate") as? Date {
        didSet { UserDefaults.standard.set(lastSyncDate, forKey: "lastSyncDate") }
    }

    // MARK: - Services

    let spotifyAuth = SpotifyAuthService()
    let db = DatabaseService.shared

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init() {
        // Keep isAuthenticated and userSpotifyId in sync with the auth
        // service automatically.
        spotifyAuth.$isAuthenticated
            .receive(on: RunLoop.main)
            .assign(to: &$isAuthenticated)
        spotifyAuth.$userSpotifyId
            .receive(on: RunLoop.main)
            .assign(to: &$userSpotifyId)

        Task { await loadFromDatabase() }
    }

    // MARK: - Database

    /// Fetches all playlists from SQLite and updates the published array.
    func loadFromDatabase() async {
        do {
            playlists = try db.fetchAllPlaylists()
        } catch {
            syncError = error.localizedDescription
        }
    }

    // MARK: - Sync

    /// Performs a full incremental sync with the Spotify Web API.
    ///
    /// Flow:
    ///  1. Fetch the user's playlist list (paginated).
    ///  2. Upsert playlists into the local DB, preserving user notes/titles.
    ///  3. For each playlist, fetch tracks with a 1 s inter-request delay to
    ///     respect Spotify's rate limits.
    ///  4. Upsert tracks and update the playlist track count.
    ///  5. Reload the local DB and stamp lastSyncDate.
    ///
    /// Playlists owned by other users return no `items` from the API when
    /// the app is in Spotify development mode — those are silently skipped.
    func sync() async {
        guard spotifyAuth.isAuthenticated, !isSyncing else { return }
        isSyncing = true
        syncError = nil
        syncStatus = nil
        defer { isSyncing = false; syncStatus = nil }
        do {
            let api = SpotifyAPIService(auth: spotifyAuth)
            let allFetched = try await api.fetchAllPlaylists()
            // Skip playlists not owned by the signed-in user — Spotify
            // development-mode quotas return zero tracks for them, so they
            // would just clutter the sidebar and waste sync time. Keep the
            // pre-filter behaviour (sync everything) when the user ID is
            // not yet known, so the next launch's profile fetch can settle.
            let fetched: [Playlist]
            if let userId = userSpotifyId {
                fetched = allFetched.filter { $0.ownerSpotifyId == userId }
            } else {
                fetched = allFetched
            }
            try db.upsertPlaylists(fetched)

            let toSync = fetched

            for (index, playlist) in toSync.enumerated() {
                syncStatus = "Syncing \(index + 1) of \(toSync.count): \(playlist.name)"
                // 1 s pause between playlists — stays well within Spotify's
                // 429 threshold for development-mode apps.
                try await Task.sleep(nanoseconds: 1_000_000_000)
                do {
                    let tracks = try await api.fetchTracks(forPlaylist: playlist.spotifyId)
                    try db.upsertTracks(tracks, forPlaylist: playlist.spotifyId)
                    try db.updatePlaylistTrackCount(spotifyId: playlist.spotifyId, count: tracks.count)
                    print("✅ \(playlist.name): \(tracks.count) tracks saved")
                } catch SpotifyError.rateLimited(let wait) {
                    print("⏳ Rate limited on \(playlist.name) (Retry-After: \(wait)s) — skipping")
                    continue
                } catch SpotifyError.httpError(403), SpotifyError.httpError(404) {
                    print("⚠️ \(playlist.name): skipped (403/404)")
                    continue
                }
            }
            lastSyncDate = Date()
            await loadFromDatabase()
        } catch SpotifyError.notAuthenticated, SpotifyError.httpError(401) {
            // Token expired or revoked — force re-login.
            spotifyAuth.logout()
        } catch SpotifyError.rateLimited(let wait) {
            syncError = "Rate limited (Retry-After: \(wait)s) — please wait and try again."
        } catch {
            syncError = error.localizedDescription
        }
    }
}

// SpotifyAPIService.swift
// Wraps the Spotify Web API endpoints used by Music Journal.
//
// Key design notes:
//  - Uses .convertFromSnakeCase globally, but any struct that defines its own
//    CodingKeys enum must map every key explicitly — the strategy is bypassed.
//  - fetchTracks pauses 500 ms between paginated track pages and the caller
//    (AppState.sync) pauses 1 s between playlists to avoid 429s.
//  - Playlists owned by other users return no `items` field in development mode;
//    fetchTracks returns [] silently in that case.

import Foundation

// MARK: - SpotifyAPIService

/// Stateless Spotify REST client. Requires a valid `SpotifyAuthService` for
/// token injection; does not manage auth state itself.
final class SpotifyAPIService {
    private let auth: SpotifyAuthService

    /// Shared decoder. convertFromSnakeCase handles most field names; structs
    /// with custom CodingKeys must map snake_case keys manually.
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    init(auth: SpotifyAuthService) {
        self.auth = auth
    }

    // MARK: - Public API

    /// Fetches all of the current user's playlists (owned + followed), paginated.
    func fetchAllPlaylists() async throws -> [Playlist] {
        var playlists: [Playlist] = []
        var url: String? = "https://api.spotify.com/v1/me/playlists?limit=50"
        while let next = url {
            let page: SpotifyPage<SpotifyPlaylistItem> = try await get(url: next)
            playlists += page.items.map { Playlist(from: $0) }
            url = page.next
        }
        return playlists
    }

    /// Fetches all tracks for a playlist, handling pagination.
    ///
    /// Returns (Track, PlaylistTrack) pairs ready for DB upsert.
    /// Local files and podcast episodes are filtered out.
    func fetchTracks(forPlaylist playlistId: String) async throws -> [(Track, PlaylistTrack)] {
        let full: SpotifyFullPlaylist = try await get(
            url: "https://api.spotify.com/v1/playlists/\(playlistId)?limit=100"
        )
        // `items` is absent for playlists owned by other users in dev mode.
        guard let tracksPage = full.items else {
            print("⚠️ \(playlistId): items nil in response")
            return []
        }
        print("🎵 \(playlistId): \(tracksPage.items.count) items, next=\(tracksPage.next ?? "nil")")
        var results = extractTracks(from: tracksPage.items, playlistId: playlistId, startPosition: 0)
        var nextURL = tracksPage.next
        var position = results.count
        while let next = nextURL {
            // 500 ms between pagination requests — conservative but safe for dev apps.
            try await Task.sleep(nanoseconds: 500_000_000)
            let page: SpotifyPage<SpotifyTrackItem> = try await get(url: next)
            results += extractTracks(from: page.items, playlistId: playlistId, startPosition: position)
            position = results.count
            nextURL = page.next
        }
        return results
    }

    // MARK: - Private helpers

    /// Converts raw SpotifyTrackItem array into (Track, PlaylistTrack) pairs,
    /// skipping local files, episodes, and items with nil track objects.
    private func extractTracks(from items: [SpotifyTrackItem], playlistId: String, startPosition: Int) -> [(Track, PlaylistTrack)] {
        var results: [(Track, PlaylistTrack)] = []
        for (offset, item) in items.enumerated() {
            guard let spotifyTrack = item.track,
                  spotifyTrack.isLocal != true,
                  spotifyTrack.type != "episode"
            else { continue }
            let track = Track(from: spotifyTrack)
            let pt = PlaylistTrack(
                playlistSpotifyId: playlistId,
                trackSpotifyId: spotifyTrack.id,
                position: startPosition + offset,
                addedAt: item.addedAt.flatMap { ISO8601DateFormatter().date(from: $0) },
                addedBySpotifyId: item.addedBy?.id
            )
            results.append((track, pt))
        }
        return results
    }

    /// Generic authenticated GET — decodes the response body into `T`.
    private func get<T: Decodable>(url urlString: String) async throws -> T {
        guard let token = await auth.validAccessToken else {
            throw SpotifyError.notAuthenticated
        }
        guard let url = URL(string: urlString) else {
            throw SpotifyError.decodingError("Invalid URL: \(urlString)")
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse {
            print("🌐 HTTP \(http.statusCode) — \(urlString.suffix(60))")
            if http.statusCode == 429 {
                let wait = http.value(forHTTPHeaderField: "Retry-After") ?? "unknown"
                print("⏳ 429 — Retry-After: \(wait)s — URL: \(urlString)")
                throw SpotifyError.rateLimited(retryAfter: wait)
            }
            if http.statusCode == 401 { throw SpotifyError.notAuthenticated }
            if http.statusCode != 200 {
                let body = String(data: data, encoding: .utf8) ?? ""
                print("❌ Error body: \(body.prefix(200))")
                throw SpotifyError.httpError(http.statusCode)
            }
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch let error as DecodingError {
            // Surface the exact key/path so API mismatches are easy to diagnose.
            switch error {
            case .keyNotFound(let key, let ctx):
                let path = ctx.codingPath.map(\.stringValue).joined(separator: ".")
                throw SpotifyError.decodingError("Missing key '\(key.stringValue)' at path: \(path)")
            case .typeMismatch(_, let ctx):
                let path = ctx.codingPath.map(\.stringValue).joined(separator: ".")
                throw SpotifyError.decodingError("Type mismatch at path: \(path) — \(ctx.debugDescription)")
            default:
                throw SpotifyError.decodingError(String(describing: error))
            }
        } catch {
            throw SpotifyError.decodingError(error.localizedDescription)
        }
    }
}

// MARK: - SpotifyError

enum SpotifyError: LocalizedError {
    case notAuthenticated
    case httpError(Int)
    case decodingError(String)
    case rateLimited(retryAfter: String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Not authenticated with Spotify"
        case .httpError(let code): return "Spotify API error: HTTP \(code)"
        case .decodingError(let msg): return "Spotify response error: \(msg)"
        case .rateLimited(let wait): return "Spotify rate limited (Retry-After: \(wait)s) — your client ID may be flagged. See console."
        }
    }
}

// MARK: - Spotify API Response Types

/// Top-level playlist response; the track page lives under the "items" JSON key.
struct SpotifyFullPlaylist: Decodable {
    let items: SpotifyPage<SpotifyTrackItem>?
}

/// Generic pagination envelope returned by all Spotify list endpoints.
struct SpotifyPage<T: Decodable>: Decodable {
    let items: [T]
    /// Absolute URL for the next page, or nil on the last page.
    let next: String?
}

/// One item from GET /me/playlists.
///
/// Note: the track-count object is keyed "items" in the API response (not "tracks").
/// Custom CodingKeys are required here because the global .convertFromSnakeCase
/// strategy is bypassed whenever a CodingKeys enum is present.
struct SpotifyPlaylistItem: Decodable {
    let id: String
    let name: String
    let description: String?
    let owner: SpotifyOwner
    let images: [SpotifyImage]?
    let tracks: SpotifyTrackCount?
    let `public`: Bool?
    let collaborative: Bool
    let snapshotId: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description, owner, images
        case tracks = "items"           // Spotify nests the count object under "items"
        case `public` = "public"        // Reserved keyword — must be quoted
        case collaborative
        case snapshotId = "snapshot_id" // Not handled by convertFromSnakeCase here
    }
}

struct SpotifyOwner: Decodable { let id: String; let displayName: String? }
struct SpotifyImage: Decodable { let url: String }
struct SpotifyTrackCount: Decodable { let total: Int }

/// One item from the tracks page of GET /playlists/{id}.
///
/// The track object is keyed "item" (singular) in this response — different
/// from the playlist list endpoint. Custom init handles nil gracefully so a
/// single bad item doesn't abort the whole page decode.
struct SpotifyTrackItem: Decodable {
    let track: SpotifyTrackObject?
    let addedAt: String?
    let addedBy: SpotifyAddedBy?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        track = try? c.decode(SpotifyTrackObject.self, forKey: .track)
        addedAt = try? c.decode(String.self, forKey: .addedAt)
        addedBy = try? c.decode(SpotifyAddedBy.self, forKey: .addedBy)
    }

    enum CodingKeys: String, CodingKey {
        case track = "item"   // Singular "item" — not "track"
        case addedAt, addedBy
    }
}

struct SpotifyAddedBy: Decodable { let id: String }

/// Full track metadata returned inside a playlist tracks page.
struct SpotifyTrackObject: Decodable {
    let id: String
    let name: String
    let artists: [SpotifyArtist]
    let album: SpotifyAlbum?
    let durationMs: Int
    let trackNumber: Int?
    let discNumber: Int?
    let explicit: Bool?
    /// True for files added from local storage; these are skipped during import.
    let isLocal: Bool?
    let popularity: Int?
    let previewUrl: String?
    let externalUrls: SpotifyExternalURLs?
    /// "track" for songs, "episode" for podcasts. Episodes are skipped.
    let type: String?
}

struct SpotifyArtist: Decodable { let name: String }
struct SpotifyAlbum: Decodable {
    let id: String
    let name: String
    let images: [SpotifyImage]?
    /// `YYYY` or `YYYY-MM-DD` depending on `release_date_precision`. We
    /// only need the year, so we tolerate either form.
    let releaseDate: String?

    enum CodingKeys: String, CodingKey {
        case id, name, images
        case releaseDate = "release_date"
    }
}
struct SpotifyExternalURLs: Decodable { let spotify: String }

// MARK: - Model mapping

extension Playlist {
    /// Constructs a new Playlist from a Spotify API response item.
    /// `userNotes` and `userTitle` start empty; they are preserved by
    /// `DatabaseService.upsertPlaylists` on subsequent syncs.
    init(from item: SpotifyPlaylistItem) {
        self.rowId = nil
        self.spotifyId = item.id
        self.name = item.name
        self.description = item.description ?? ""
        self.ownerName = item.owner.displayName ?? item.owner.id
        self.ownerSpotifyId = item.owner.id
        self.imageURL = item.images?.first?.url
        self.trackCount = item.tracks?.total ?? 0
        self.isPublic = item.public ?? false
        self.isCollaborative = item.collaborative
        self.snapshotId = item.snapshotId ?? ""
        self.userNotes = ""
        self.userTitle = ""
        self.syncedAt = Date()
    }
}

extension Track {
    /// Constructs a new Track from a Spotify track object.
    /// `userNotes` and `userRating` start empty/nil; they are preserved by
    /// `DatabaseService.upsertTracks` on subsequent syncs.
    init(from item: SpotifyTrackObject) {
        self.rowId = nil
        self.spotifyId = item.id
        self.name = item.name
        self.artistNames = item.artists.map { $0.name }.joined(separator: ", ")
        self.albumName = item.album?.name ?? ""
        self.albumSpotifyId = item.album?.id ?? ""
        self.albumImageURL = item.album?.images?.first?.url
        self.durationMs = item.durationMs
        self.trackNumber = item.trackNumber ?? 0
        self.discNumber = item.discNumber ?? 1
        self.isExplicit = item.explicit ?? false
        self.isLocal = item.isLocal ?? false
        self.popularity = item.popularity
        self.previewURL = item.previewUrl
        self.spotifyURL = item.externalUrls?.spotify ?? ""
        self.userNotes = ""
        self.personalNotes = ""
        self.userRating = nil
        // First-sync seed for songYear from album.release_date — preserved
        // by upsertTracks if the user hasn't overridden it.
        self.songYear = Track.parseYear(from: item.album?.releaseDate)
        self.lyrics = ""
        self.lyricSummary = ""
        self.syncedAt = Date()
    }

    /// Extracts the leading 4-digit year from a Spotify release_date string
    /// (`YYYY`, `YYYY-MM`, or `YYYY-MM-DD`). Returns nil if no year is found.
    static func parseYear(from releaseDate: String?) -> Int? {
        guard let s = releaseDate, s.count >= 4 else { return nil }
        return Int(s.prefix(4))
    }
}

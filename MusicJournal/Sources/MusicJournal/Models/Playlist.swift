// Playlist.swift
// Core model representing a Spotify playlist stored in the local SQLite database.
// Conforms to GRDB persistence protocols for automatic read/write mapping.

import Foundation
import GRDB

/// A Spotify playlist record stored locally.
///
/// Spotify-sourced fields are refreshed on every sync; `userNotes` and
/// `userTitle` are user-owned and are never overwritten during sync.
struct Playlist: Codable, FetchableRecord, MutablePersistableRecord {
    /// SQLite auto-increment row ID; nil before first insert.
    var rowId: Int64?

    // MARK: - Spotify fields (updated on every sync)

    var spotifyId: String
    var name: String
    var description: String
    var ownerName: String
    var ownerSpotifyId: String
    /// URL of the playlist cover image; nil if Spotify returns no image.
    var imageURL: String?
    /// Track count as last reported by Spotify or the post-sync actual count.
    var trackCount: Int
    var isPublic: Bool
    var isCollaborative: Bool
    /// Opaque snapshot identifier — changes whenever the playlist content changes.
    var snapshotId: String

    // MARK: - User-owned fields (never overwritten by sync)

    /// Free-form notes the user has written about this playlist.
    var userNotes: String
    /// Custom display title; if empty, the Spotify name is shown instead.
    var userTitle: String

    /// Timestamp of the most recent sync for this playlist.
    var syncedAt: Date

    static let databaseTableName = "playlists"

    // CodingKeys maps the Swift property names to the SQLite column names.
    // `rowId` → "id" matches the autoIncrementedPrimaryKey column name.
    enum CodingKeys: String, CodingKey {
        case rowId = "id"
        case spotifyId, name, description, ownerName, ownerSpotifyId
        case imageURL, trackCount, isPublic, isCollaborative
        case snapshotId, userNotes, userTitle, syncedAt
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        rowId = inserted.rowID
    }
}

// MARK: - Identifiable

extension Playlist: Identifiable {
    /// SwiftUI identity uses spotifyId so List selection survives re-fetches.
    var id: String { spotifyId }
}

// MARK: - Hashable
//
// Custom == compares only `spotifyId` so that sidebar List selection
// (`selection: $selectedPlaylist` keyed on Playlist values) survives sync —
// every sync bumps `syncedAt`, which would otherwise make the new value
// `!=` the binding's old value and visually clear the selection.
//
// Track gets *synthesised* Equatable instead because its inspector view
// needs SwiftUI to detect content changes; see Track.swift.
extension Playlist: Hashable {
    static func == (lhs: Playlist, rhs: Playlist) -> Bool { lhs.spotifyId == rhs.spotifyId }
    func hash(into hasher: inout Hasher) { hasher.combine(spotifyId) }
}

// MARK: - GRDB Associations

extension Playlist {
    static let playlistTracks = hasMany(PlaylistTrack.self,
        using: ForeignKey(["playlistSpotifyId"], to: ["spotifyId"]))
    static let tracks = hasMany(Track.self, through: playlistTracks, using: PlaylistTrack.track)
}

// Track.swift
// Core model representing a Spotify track stored in the local SQLite database.
// Conforms to GRDB persistence protocols for automatic read/write mapping.

import Foundation
import GRDB

/// A Spotify track record stored locally.
///
/// Spotify-sourced fields are refreshed on every sync; `userNotes` and
/// `userRating` are user-owned and are never overwritten during sync.
struct Track: Codable, FetchableRecord, MutablePersistableRecord {
    /// SQLite auto-increment row ID; nil before first insert.
    var rowId: Int64?

    // MARK: - Spotify fields (updated on every sync)

    var spotifyId: String
    var name: String
    /// Comma-separated list of artist names (e.g. "Artist A, Artist B").
    var artistNames: String
    var albumName: String
    var albumSpotifyId: String
    /// URL of the album art; nil if Spotify returns no image.
    var albumImageURL: String?
    var durationMs: Int
    var trackNumber: Int
    var discNumber: Int
    var isExplicit: Bool
    /// True for locally-stored files; these are skipped during sync since
    /// they have no valid Spotify ID or metadata.
    var isLocal: Bool
    /// Spotify popularity score 0–100; nil if not returned by the API.
    var popularity: Int?
    /// 30-second preview clip URL; nil for most tracks.
    var previewURL: String?
    var spotifyURL: String

    // MARK: - User-owned fields (never overwritten by sync)

    var userNotes: String
    /// Star rating 1–5; nil means unrated.
    var userRating: Int?

    var syncedAt: Date

    static let databaseTableName = "tracks"

    enum CodingKeys: String, CodingKey {
        case rowId = "id"
        case spotifyId, name, artistNames, albumName, albumSpotifyId
        case albumImageURL, durationMs, trackNumber, discNumber
        case isExplicit, isLocal, popularity, previewURL, spotifyURL
        case userNotes, userRating, syncedAt
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        rowId = inserted.rowID
    }

    // MARK: - Computed helpers

    /// Duration as "M:SS" string suitable for display in the track table.
    var durationFormatted: String {
        let total = durationMs / 1000
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    /// Artist names split into individual strings for display or filtering.
    var artistList: [String] {
        artistNames.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

// MARK: - Identifiable

extension Track: Identifiable {
    var id: String { spotifyId }
}

// MARK: - Hashable

extension Track: Hashable {
    static func == (lhs: Track, rhs: Track) -> Bool { lhs.spotifyId == rhs.spotifyId }
    func hash(into hasher: inout Hasher) { hasher.combine(spotifyId) }
}

// PlaylistTrack.swift
// Join-table model that maps a playlist to its tracks with positional ordering.
// The composite primary key (playlistSpotifyId, trackSpotifyId) is defined
// in the database migration; GRDB handles insert/fetch automatically.

import Foundation
import GRDB

/// Join record connecting a playlist to a track at a specific position.
///
/// The entire playlist_tracks table for a given playlist is deleted and
/// re-inserted on every sync so that track order always matches Spotify.
struct PlaylistTrack: Codable, FetchableRecord, PersistableRecord {
    var playlistSpotifyId: String
    var trackSpotifyId: String
    /// 0-based position within the playlist as returned by the Spotify API.
    var position: Int
    /// ISO-8601 date the track was added to the playlist; nil if unknown.
    var addedAt: Date?
    /// Spotify user ID of whoever added the track; nil for legacy entries.
    var addedBySpotifyId: String?

    static let databaseTableName = "playlist_tracks"

    // MARK: - GRDB Associations

    static let playlist = belongsTo(Playlist.self,
        using: ForeignKey(["playlistSpotifyId"], to: ["spotifyId"]))
    static let track = belongsTo(Track.self,
        using: ForeignKey(["trackSpotifyId"], to: ["spotifyId"]))
}

/// Convenience record for fetching a PlaylistTrack together with its Track
/// in a single joined SQL query.
struct PlaylistTrackWithTrack: FetchableRecord, Decodable {
    var playlistTrack: PlaylistTrack
    var track: Track
}

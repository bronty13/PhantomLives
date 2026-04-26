// DatabaseService.swift
// SQLite persistence layer using GRDB.swift.
// The database file lives at:
//   ~/Library/Application Support/MusicJournal/journal.sqlite
// Schema migrations are append-only: register new migrations, never edit old ones.

import Foundation
import GRDB

/// Singleton service that owns the SQLite database queue and exposes
/// typed read/write operations for playlists and tracks.
final class DatabaseService {
    static let shared = DatabaseService()
    private let dbQueue: DatabaseQueue

    private init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MusicJournal", isDirectory: true)
        try! FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        let dbPath = appSupport.appendingPathComponent("journal.sqlite").path
        dbQueue = try! DatabaseQueue(path: dbPath)
        try! migrate()
    }

    // MARK: - Migrations

    /// Registers and runs all schema migrations in order.
    /// Add new `migrator.registerMigration("vN_...")` blocks here — never edit
    /// existing registrations, as GRDB skips already-applied migrations by name.
    private func migrate() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial") { db in
            try db.create(table: "playlists") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("spotifyId", .text).notNull().unique()
                t.column("name", .text).notNull()
                t.column("description", .text).notNull().defaults(to: "")
                t.column("ownerName", .text).notNull()
                t.column("ownerSpotifyId", .text).notNull()
                t.column("imageURL", .text)
                t.column("trackCount", .integer).notNull().defaults(to: 0)
                t.column("isPublic", .boolean).notNull().defaults(to: false)
                t.column("isCollaborative", .boolean).notNull().defaults(to: false)
                t.column("snapshotId", .text).notNull().defaults(to: "")
                t.column("userNotes", .text).notNull().defaults(to: "")
                t.column("userTitle", .text).notNull().defaults(to: "")
                t.column("syncedAt", .datetime).notNull()
            }

            try db.create(table: "tracks") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("spotifyId", .text).notNull().unique()
                t.column("name", .text).notNull()
                t.column("artistNames", .text).notNull()
                t.column("albumName", .text).notNull()
                t.column("albumSpotifyId", .text).notNull()
                t.column("albumImageURL", .text)
                t.column("durationMs", .integer).notNull()
                t.column("trackNumber", .integer).notNull()
                t.column("discNumber", .integer).notNull()
                t.column("isExplicit", .boolean).notNull().defaults(to: false)
                t.column("isLocal", .boolean).notNull().defaults(to: false)
                t.column("popularity", .integer)
                t.column("previewURL", .text)
                t.column("spotifyURL", .text).notNull()
                t.column("userNotes", .text).notNull().defaults(to: "")
                t.column("userRating", .integer)
                t.column("syncedAt", .datetime).notNull()
            }

            // Composite PK ensures a track appears at most once per playlist.
            // ON DELETE CASCADE cleans up join rows when a playlist/track is removed.
            try db.create(table: "playlist_tracks") { t in
                t.column("playlistSpotifyId", .text).notNull()
                    .references("playlists", column: "spotifyId", onDelete: .cascade)
                t.column("trackSpotifyId", .text).notNull()
                    .references("tracks", column: "spotifyId", onDelete: .cascade)
                t.column("position", .integer).notNull()
                t.column("addedAt", .datetime)
                t.column("addedBySpotifyId", .text)
                t.primaryKey(["playlistSpotifyId", "trackSpotifyId"])
            }
        }

        migrator.registerMigration("v2_track_extra_fields") { db in
            // User-owned, never overwritten by sync. Defaults make existing
            // rows valid without data backfill.
            try db.alter(table: "tracks") { t in
                t.add(column: "songYear", .integer)
                t.add(column: "lyrics", .text).notNull().defaults(to: "")
                t.add(column: "lyricSummary", .text).notNull().defaults(to: "")
            }
        }

        migrator.registerMigration("v3_personal_notes") { db in
            // "Personal Notes" — user-only, never touched by the LLM.
            try db.alter(table: "tracks") { t in
                t.add(column: "personalNotes", .text).notNull().defaults(to: "")
            }
        }

        try migrator.migrate(dbQueue)
    }

    // MARK: - Playlists

    /// Returns all playlists sorted alphabetically by name.
    func fetchAllPlaylists() throws -> [Playlist] {
        try dbQueue.read { db in
            try Playlist.order(Column("name")).fetchAll(db)
        }
    }

    /// Upserts each playlist, preserving `userNotes` and `userTitle` on update.
    func upsertPlaylists(_ playlists: [Playlist]) throws {
        try dbQueue.write { db in
            for var playlist in playlists {
                if var existing = try Playlist
                    .filter(Column("spotifyId") == playlist.spotifyId)
                    .fetchOne(db) {
                    // Sync only Spotify-controlled fields; never clobber user data.
                    existing.name          = playlist.name
                    existing.description   = playlist.description
                    existing.ownerName     = playlist.ownerName
                    existing.imageURL      = playlist.imageURL
                    existing.trackCount    = playlist.trackCount
                    existing.isPublic      = playlist.isPublic
                    existing.isCollaborative = playlist.isCollaborative
                    existing.snapshotId    = playlist.snapshotId
                    existing.syncedAt      = playlist.syncedAt
                    try existing.update(db)
                } else {
                    try playlist.insert(db)
                }
            }
        }
    }

    /// Saves user notes and custom title for a playlist.
    func updatePlaylistNotes(spotifyId: String, notes: String, title: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE playlists SET userNotes = ?, userTitle = ? WHERE spotifyId = ?",
                arguments: [notes, title, spotifyId]
            )
        }
    }

    // MARK: - Tracks

    /// Returns all tracks for a playlist in their Spotify-defined order.
    func fetchTracks(forPlaylist playlistId: String) throws -> [Track] {
        try dbQueue.read { db in
            try Track.fetchAll(db, sql: """
                SELECT tracks.* FROM tracks
                JOIN playlist_tracks ON playlist_tracks.trackSpotifyId = tracks.spotifyId
                WHERE playlist_tracks.playlistSpotifyId = ?
                ORDER BY playlist_tracks.position
                """, arguments: [playlistId])
        }
    }

    /// Replaces all tracks for a playlist with the newly synced set.
    ///
    /// Deletes existing join rows first so that removed or reordered tracks
    /// are handled correctly without leaving orphan rows.
    func upsertTracks(_ pairs: [(Track, PlaylistTrack)], forPlaylist playlistId: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM playlist_tracks WHERE playlistSpotifyId = ?",
                arguments: [playlistId]
            )
            for (var track, pt) in pairs {
                if var existing = try Track
                    .filter(Column("spotifyId") == track.spotifyId)
                    .fetchOne(db) {
                    // Update mutable Spotify fields; leave userNotes/userRating intact.
                    existing.name = track.name
                    existing.artistNames = track.artistNames
                    existing.albumName = track.albumName
                    existing.albumImageURL = track.albumImageURL
                    existing.durationMs = track.durationMs
                    existing.popularity = track.popularity
                    existing.previewURL = track.previewURL
                    existing.syncedAt = track.syncedAt
                    // Backfill songYear from the album's release_date when
                    // the user hasn't entered one yet. Preserves manual
                    // overrides on subsequent syncs.
                    if existing.songYear == nil, let synced = track.songYear {
                        existing.songYear = synced
                    }
                    try existing.update(db)
                } else {
                    try track.insert(db)
                }
                try pt.insert(db)
            }
        }
    }

    /// Stores the actual synced track count in the playlists table.
    ///
    /// Spotify's playlist-list endpoint returns an estimated count that is
    /// often 0 for development-mode apps; this overwrites it after a real fetch.
    func updatePlaylistTrackCount(spotifyId: String, count: Int) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE playlists SET trackCount = ? WHERE spotifyId = ?",
                arguments: [count, spotifyId]
            )
        }
    }

    /// One track's worth of partial user-field updates for a bulk apply.
    /// `nil` fields leave the existing column value unchanged.
    struct TrackUpdate {
        let spotifyId: String
        let songYear: Int?
        let lyrics: String?
        let lyricSummary: String?
        let notes: String?
        let rating: Int?
    }

    /// Applies a batch of partial track updates in a single transaction.
    /// Returns the spotifyIds that matched an existing row.
    @discardableResult
    func applyTrackUpdates(_ updates: [TrackUpdate]) throws -> [String] {
        try dbQueue.write { db in
            var applied: [String] = []
            for u in updates {
                guard var existing = try Track
                    .filter(Column("spotifyId") == u.spotifyId)
                    .fetchOne(db)
                else { continue }
                if let y = u.songYear { existing.songYear = y }
                if let l = u.lyrics { existing.lyrics = l }
                if let s = u.lyricSummary { existing.lyricSummary = s }
                if let n = u.notes { existing.userNotes = n }
                if let r = u.rating { existing.userRating = r }
                try existing.update(db)
                applied.append(u.spotifyId)
            }
            return applied
        }
    }

    /// Saves all user-owned fields for a track in one write.
    func updateTrackUserFields(
        spotifyId: String,
        notes: String,
        personalNotes: String,
        rating: Int?,
        songYear: Int?,
        lyrics: String,
        lyricSummary: String
    ) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    UPDATE tracks
                    SET userNotes = ?,
                        personalNotes = ?,
                        userRating = ?,
                        songYear = ?,
                        lyrics = ?,
                        lyricSummary = ?
                    WHERE spotifyId = ?
                    """,
                arguments: [notes, personalNotes, rating, songYear, lyrics, lyricSummary, spotifyId]
            )
        }
    }

    // MARK: - Export / Import

    /// Serialises the entire database into a `DatabaseExport` value for JSON export.
    func exportDatabase() throws -> DatabaseExport {
        try dbQueue.read { db in
            let playlists = try Playlist.fetchAll(db)
            let tracks = try Track.fetchAll(db)
            let links = try PlaylistTrack.fetchAll(db)
            return DatabaseExport(playlists: playlists, tracks: tracks, playlistTracks: links)
        }
    }

    /// Replaces all local data with the contents of a `DatabaseExport`.
    /// The caller should export a backup before calling this.
    func importDatabase(_ export: DatabaseExport) throws {
        try dbQueue.write { db in
            try PlaylistTrack.deleteAll(db)
            try Track.deleteAll(db)
            try Playlist.deleteAll(db)
            for var p in export.playlists { try p.insert(db) }
            for var t in export.tracks { try t.insert(db) }
            for pt in export.playlistTracks { try pt.insert(db) }
        }
    }
}

// MARK: - DatabaseExport

/// Serialisable snapshot of the full database used for JSON backup/restore.
struct DatabaseExport: Codable {
    var version: Int
    var exportedAt: Date
    let playlists: [Playlist]
    let tracks: [Track]
    let playlistTracks: [PlaylistTrack]

    init(playlists: [Playlist], tracks: [Track], playlistTracks: [PlaylistTrack]) {
        self.version = 1
        self.exportedAt = Date()
        self.playlists = playlists
        self.tracks = tracks
        self.playlistTracks = playlistTracks
    }
}

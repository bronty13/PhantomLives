import Foundation
import GRDB

final class DatabaseService {
    private let dbQueue: DatabaseQueue

    init() throws {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("PurpleReel", isDirectory: true)
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        let dbURL = appSupport.appendingPathComponent("purplereel.sqlite")

        var config = Configuration()
        config.label = "PurpleReel"
        self.dbQueue = try DatabaseQueue(path: dbURL.path, configuration: config)

        try migrator.migrate(dbQueue)
    }

    private var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()

        m.registerMigration("v1_schema") { db in
            try db.create(table: "asset") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("path", .text).notNull().unique().indexed()
                t.column("filename", .text).notNull()
                t.column("sizeBytes", .integer).notNull()
                t.column("modifiedAt", .datetime).notNull()
                t.column("codec", .text)
                t.column("widthPx", .integer)
                t.column("heightPx", .integer)
                t.column("durationSeconds", .double)
                t.column("frameRate", .double)
                t.column("sha1", .text)
                t.column("addedAt", .datetime).notNull()
            }

            try db.create(table: "tag") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().unique()
            }

            try db.create(table: "asset_tag") { t in
                t.column("assetId", .integer).notNull()
                    .references("asset", onDelete: .cascade)
                t.column("tagId", .integer).notNull()
                    .references("tag", onDelete: .cascade)
                t.primaryKey(["assetId", "tagId"])
            }

            try db.create(table: "marker") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("assetId", .integer).notNull()
                    .references("asset", onDelete: .cascade)
                t.column("timecodeIn", .double).notNull()
                t.column("timecodeOut", .double)
                t.column("note", .text)
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "subclip") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("parentAssetId", .integer).notNull()
                    .references("asset", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("timecodeIn", .double).notNull()
                t.column("timecodeOut", .double).notNull()
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "rating") { t in
                t.column("assetId", .integer).primaryKey()
                    .references("asset", onDelete: .cascade)
                t.column("stars", .integer).notNull()
                t.column("colorLabel", .text)
                t.column("description", .text)
            }

            try db.create(table: "transcript") { t in
                t.column("assetId", .integer).primaryKey()
                    .references("asset", onDelete: .cascade)
                t.column("json", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }

            // FTS5 search over filenames, descriptions, marker notes,
            // transcript text. Populated via triggers in a later migration
            // once we have content beyond filename to index.
            try db.create(virtualTable: "asset_fts", using: FTS5()) { t in
                t.column("filename")
                t.column("description")
            }
        }

        // Kyno-parity log fields. Separate table (1:1 with asset) so the
        // sidebar Metadata pane can read/write a single row and the
        // technical `asset` columns stay tightly scoped to scanner output.
        m.registerMigration("v2_clip_metadata") { db in
            try db.create(table: "clip_metadata") { t in
                t.column("assetId", .integer).primaryKey()
                    .references("asset", onDelete: .cascade)
                t.column("title", .text)
                t.column("description", .text)
                t.column("reel", .text)
                t.column("scene", .text)
                t.column("shot", .text)
                t.column("take", .text)
                t.column("angle", .text)
                t.column("camera", .text)
            }
        }

        // Filter-dropdown extensions: audio codec + camera-set
        // creation date. Both populated by MediaScanner.scan(...) via
        // AVURLAsset. Nullable — older / unsupported containers and
        // non-AV assets simply have NULL columns. Existing rows are
        // backfilled on the next rescan because upsertAssets() always
        // writes every column.
        m.registerMigration("v3_asset_audio_recorded") { db in
            try db.alter(table: "asset") { t in
                t.add(column: "audioCodec", .text)
                t.add(column: "recordedAt", .datetime)
            }
        }

        // v4 — Date Created column on asset (filesystem birth time)
        // and audioChannelNames on clip_metadata. Both backfill to
        // NULL for existing rows; rescan repopulates createdAt from
        // the FS, and the channel-names field is user-edited.
        m.registerMigration("v4_asset_created_channels") { db in
            try db.alter(table: "asset") { t in
                t.add(column: "createdAt", .datetime)
            }
            try db.alter(table: "clip_metadata") { t in
                t.add(column: "audioChannelNames", .text)
            }
        }

        // v5 — variable-frame-rate flag on asset. NULL = unknown;
        // populated by MediaScanner via the
        // `nominalFrameRate` vs `minFrameDuration` heuristic.
        // Drives the new VFR/CFR Filter criterion.
        m.registerMigration("v5_asset_is_vfr") { db in
            try db.alter(table: "asset") { t in
                t.add(column: "isVFR", .boolean)
            }
        }

        // v6 — user-set poster-frame override (seconds into the
        // clip). NULL = auto-pick mid-clip frame. Kyno-parity for
        // the P keyboard shortcut. Lives on `asset` so the grid /
        // list cells can read it from the same value type they
        // already render; no extra DB join per cell.
        m.registerMigration("v6_asset_poster_frame") { db in
            try db.alter(table: "asset") { t in
                t.add(column: "posterFrameSeconds", .double)
            }
        }

        // v7 — volume identity for offline / cross-volume search
        // (Kyno-parity row 57). `volumeUUID` lets us reconnect
        // catalogue rows after a `/Volumes/<name>` mount-point
        // shift; `volumeLabel` is a human-readable display field
        // for the optional list column. NULL on assets scanned
        // before this migration — rescan repopulates from
        // URLResourceKey.volumeIdentifierKey.
        m.registerMigration("v7_asset_volume_id") { db in
            try db.alter(table: "asset") { t in
                t.add(column: "volumeUUID", .text)
                t.add(column: "volumeLabel", .text)
            }
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS asset_volumeUUID
                ON asset(volumeUUID)
                """)
        }

        return m
    }

    /// Repath every asset on the given volume after a remount.
    /// `oldRoot` and `newRoot` are mount-point paths like
    /// `/Volumes/CardA`. Rewrites the `path` column for assets
    /// whose path starts with `oldRoot/`. Returns the number of
    /// rows touched.
    func updateAssetPathPrefix(volumeUUID: String,
                                oldRoot: String,
                                newRoot: String) throws -> Int {
        let oldPrefix = oldRoot.hasSuffix("/") ? oldRoot : oldRoot + "/"
        let newPrefix = newRoot.hasSuffix("/") ? newRoot : newRoot + "/"
        return try dbQueue.write { db in
            try db.execute(sql: """
                UPDATE asset
                   SET path = ? || substr(path, ?)
                 WHERE volumeUUID = ?
                   AND substr(path, 1, ?) = ?
                """, arguments: [
                    newPrefix,
                    oldPrefix.count + 1,
                    volumeUUID,
                    oldPrefix.count,
                    oldPrefix
                ])
            return db.changesCount
        }
    }

    /// Distinct volumes catalogued so far. Used by the Offline
    /// filter UI to show "you have clips on N volumes" copy.
    func catalogedVolumes() throws -> [(uuid: String, label: String?)] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT volumeUUID, volumeLabel
                  FROM asset
                 WHERE volumeUUID IS NOT NULL
                 GROUP BY volumeUUID
                """).map {
                    (uuid: $0["volumeUUID"] ?? "",
                     label: $0["volumeLabel"])
                }
        }
    }

    // MARK: - Poster frame

    /// Update just the poster-frame column without touching the rest
    /// of the asset row. Cheaper than re-upserting, and keeps the
    /// scanner-owned columns untouched.
    func setPosterFrame(assetId: Int64, seconds: Double?) throws {
        try dbQueue.write { db in
            try db.execute(sql: """
                UPDATE asset SET posterFrameSeconds = ? WHERE id = ?
                """, arguments: [seconds, assetId])
        }
    }

    // MARK: - Clip metadata (Kyno log fields)

    func clipMetadata(assetId: Int64) throws -> ClipMetadata {
        try dbQueue.read { db in
            try ClipMetadata.fetchOne(db, key: assetId)
                ?? ClipMetadata(assetId: assetId,
                                title: nil, description: nil,
                                reel: nil, scene: nil, shot: nil,
                                take: nil, angle: nil, camera: nil)
        }
    }

    func setClipMetadata(_ meta: ClipMetadata) throws {
        try dbQueue.write { db in
            try meta.save(db)
        }
    }

    // MARK: - Asset CRUD

    func upsertAssets(_ assets: [Asset]) throws {
        try dbQueue.write { db in
            for var a in assets {
                if let existing = try Asset
                    .filter(Column("path") == a.path)
                    .fetchOne(db) {
                    a.rowId = existing.rowId
                    try a.update(db)
                } else {
                    try a.insert(db)
                }
            }
        }
    }

    func allAssets() throws -> [Asset] {
        try dbQueue.read { db in
            try Asset.order(Column("filename").asc).fetchAll(db)
        }
    }

    func clearAssets() throws {
        try dbQueue.write { db in
            _ = try Asset.deleteAll(db)
        }
    }

    func asset(forPath path: String) throws -> Asset? {
        try dbQueue.read { db in
            try Asset.filter(Column("path") == path).fetchOne(db)
        }
    }

    func updateAssetPath(oldPath: String, newPath: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: """
                UPDATE asset SET path = ?, filename = ? WHERE path = ?
                """, arguments: [newPath, (newPath as NSString).lastPathComponent, oldPath])
        }
    }

    // MARK: - Markers

    func markers(assetId: Int64) throws -> [Marker] {
        try dbQueue.read { db in
            try Marker.filter(Column("assetId") == assetId)
                .order(Column("timecodeIn").asc)
                .fetchAll(db)
        }
    }

    func addMarker(assetId: Int64, timecodeIn: Double, timecodeOut: Double? = nil,
                   note: String? = nil) throws -> Marker {
        let m = Marker(id: nil, assetId: assetId, timecodeIn: timecodeIn,
                       timecodeOut: timecodeOut, note: note, createdAt: Date())
        try dbQueue.write { db in
            try m.insert(db)
        }
        return m
    }

    func updateMarker(_ marker: Marker) throws {
        try dbQueue.write { db in
            try marker.update(db)
        }
    }

    func deleteMarker(id: Int64) throws {
        _ = try dbQueue.write { db in
            try Marker.filter(Column("id") == id).deleteAll(db)
        }
    }

    // MARK: - Subclips

    func subclips(parentAssetId: Int64) throws -> [Subclip] {
        try dbQueue.read { db in
            try Subclip.filter(Column("parentAssetId") == parentAssetId)
                .order(Column("timecodeIn").asc)
                .fetchAll(db)
        }
    }

    func addSubclip(parentAssetId: Int64, name: String,
                    timecodeIn: Double, timecodeOut: Double) throws -> Subclip {
        let s = Subclip(id: nil, parentAssetId: parentAssetId, name: name,
                        timecodeIn: timecodeIn, timecodeOut: timecodeOut,
                        createdAt: Date())
        try dbQueue.write { db in
            try s.insert(db)
        }
        return s
    }

    func deleteSubclip(id: Int64) throws {
        _ = try dbQueue.write { db in
            try Subclip.filter(Column("id") == id).deleteAll(db)
        }
    }

    // MARK: - Tags

    func tags(assetId: Int64) throws -> [Tag] {
        try dbQueue.read { db in
            try Tag.fetchAll(db, sql: """
                SELECT t.* FROM tag t
                JOIN asset_tag at ON at.tagId = t.id
                WHERE at.assetId = ?
                ORDER BY t.name ASC
                """, arguments: [assetId])
        }
    }

    /// Idempotent. Creates the tag if needed, links it to the asset.
    /// Returns the tag (with its id populated).
    ///
    /// GRDB's `PersistableRecord.insert(db)` is non-mutating and
    /// does NOT update the source record's id after the insert,
    /// so we use raw SQL + `lastInsertedRowID` to fetch the new
    /// tag's id. Re-fetching via filter() also works but costs an
    /// extra round trip. (The earlier `var t = Tag(...); try
    /// t.insert(db); tag = t` pattern was silently broken on new
    /// tags — `t.id` stayed nil and the guard below threw.)
    func addTag(name: String, assetId: Int64) throws -> Tag {
        try dbQueue.write { db in
            if let existing = try Tag.filter(Column("name") == name).fetchOne(db),
               let tagId = existing.id {
                try db.execute(sql: """
                    INSERT OR IGNORE INTO asset_tag (assetId, tagId) VALUES (?, ?)
                    """, arguments: [assetId, tagId])
                return existing
            }
            try db.execute(sql: "INSERT INTO tag (name) VALUES (?)",
                            arguments: [name])
            let tagId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT OR IGNORE INTO asset_tag (assetId, tagId) VALUES (?, ?)
                """, arguments: [assetId, tagId])
            return Tag(id: tagId, name: name)
        }
    }

    func removeTag(name: String, assetId: Int64) throws {
        _ = try dbQueue.write { db in
            try db.execute(sql: """
                DELETE FROM asset_tag
                WHERE assetId = ?
                  AND tagId = (SELECT id FROM tag WHERE name = ?)
                """, arguments: [assetId, name])
        }
    }

    // MARK: - Transcripts

    func transcript(assetId: Int64) throws -> TranscriptDocument? {
        try dbQueue.read { db in
            let row = try Row.fetchOne(db, sql: """
                SELECT json FROM transcript WHERE assetId = ?
                """, arguments: [assetId])
            guard let jsonString: String = row?["json"] else { return nil }
            guard let data = jsonString.data(using: .utf8) else { return nil }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try? decoder.decode(TranscriptDocument.self, from: data)
        }
    }

    func saveTranscript(_ doc: TranscriptDocument, assetId: Int64) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(doc)
        let jsonString = String(data: data, encoding: .utf8) ?? "{}"
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO transcript (assetId, json, createdAt) VALUES (?, ?, ?)
                ON CONFLICT(assetId) DO UPDATE SET json = excluded.json, createdAt = excluded.createdAt
                """, arguments: [assetId, jsonString, Date()])
        }
    }

    // MARK: - Ratings

    func rating(assetId: Int64) throws -> Rating? {
        try dbQueue.read { db in
            try Rating.filter(Column("assetId") == assetId).fetchOne(db)
        }
    }

    /// Upsert. `stars == 0` removes the row to keep the table tidy.
    func setRating(assetId: Int64, stars: Int,
                   colorLabel: String? = nil, description: String? = nil) throws {
        try dbQueue.write { db in
            if stars <= 0 && (description ?? "").isEmpty && (colorLabel ?? "").isEmpty {
                try Rating.filter(Column("assetId") == assetId).deleteAll(db)
                return
            }
            let r = Rating(assetId: assetId, stars: stars,
                            colorLabel: colorLabel, description: description)
            try r.save(db)
        }
    }
}

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

        return m
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
        var m = Marker(id: nil, assetId: assetId, timecodeIn: timecodeIn,
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
        var s = Subclip(id: nil, parentAssetId: parentAssetId, name: name,
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
    func addTag(name: String, assetId: Int64) throws -> Tag {
        try dbQueue.write { db in
            var tag = try Tag.filter(Column("name") == name).fetchOne(db)
            if tag == nil {
                var t = Tag(id: nil, name: name)
                try t.insert(db)
                tag = t
            }
            guard let tagId = tag?.id else {
                throw NSError(domain: "PurpleReel.DB", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "tag insert produced no id"])
            }
            try db.execute(sql: """
                INSERT OR IGNORE INTO asset_tag (assetId, tagId) VALUES (?, ?)
                """, arguments: [assetId, tagId])
            return tag!
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
            var r = Rating(assetId: assetId, stars: stars,
                            colorLabel: colorLabel, description: description)
            try r.save(db)
        }
    }
}

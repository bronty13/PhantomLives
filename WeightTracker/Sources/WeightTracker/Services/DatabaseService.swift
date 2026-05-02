import Foundation
import GRDB

@MainActor
final class DatabaseService {
    static let shared = DatabaseService()

    private var dbPool: DatabasePool

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("WeightTracker", isDirectory: true)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbURL = dir.appendingPathComponent("weighttracker.sqlite")
        dbPool = try! DatabasePool(path: dbURL.path)
        try! migrate()
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial") { db in
            try db.create(table: "weight_entries") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("date", .text).notNull().unique()
                t.column("weightLbs", .double).notNull()
                t.column("notesMd", .text).notNull().defaults(to: "")
                t.column("createdAt", .text).notNull()
                t.column("updatedAt", .text).notNull()
            }
        }

        migrator.registerMigration("v2_photos") { db in
            try db.alter(table: "weight_entries") { t in
                t.add(column: "photoBlob", .blob)
                t.add(column: "photoFilename", .text)
                t.add(column: "photoExt", .text)
            }
        }

        try migrator.migrate(dbPool)
    }

    func fetchAll() throws -> [WeightEntry] {
        try dbPool.read { db in
            try WeightEntry.order(Column("date").asc).fetchAll(db)
        }
    }

    func fetchRange(start: String, end: String) throws -> [WeightEntry] {
        try dbPool.read { db in
            try WeightEntry
                .filter(Column("date") >= start && Column("date") <= end)
                .order(Column("date").asc)
                .fetchAll(db)
        }
    }

    func insert(_ entry: inout WeightEntry) throws {
        try dbPool.write { db in
            try entry.insert(db)
        }
    }

    func update(_ entry: WeightEntry) throws {
        try dbPool.write { db in
            try entry.update(db)
        }
    }

    func delete(id: Int64) throws {
        try dbPool.write { db in
            _ = try WeightEntry.deleteOne(db, key: id)
        }
    }

    func deleteAll(ids: [Int64]) throws {
        try dbPool.write { db in
            _ = try WeightEntry.deleteAll(db, keys: ids)
        }
    }

    func earliestEntry() throws -> WeightEntry? {
        try dbPool.read { db in
            try WeightEntry.order(Column("date").asc).fetchOne(db)
        }
    }

    func latestEntry() throws -> WeightEntry? {
        try dbPool.read { db in
            try WeightEntry.order(Column("date").desc).fetchOne(db)
        }
    }

    func entryCount() throws -> Int {
        try dbPool.read { db in
            try WeightEntry.fetchCount(db)
        }
    }

    var databaseURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("WeightTracker/weighttracker.sqlite")
    }
}

import Foundation
import GRDB

/// CRUD for generic WYSIWYG notes. Body is stored as RTF (`Data`) plus a
/// plain-text mirror for search. Soft-delete via `deleted_at`.
@MainActor
enum GenericNoteService {
    private static var pool: DatabasePool { DatabaseService.shared.dbPool }

    /// Notes for one type, live only, ordered newest note-date first then
    /// most-recently-edited.
    static func fetchLive(typeId: String) throws -> [GenericNote] {
        try pool.read { db in
            try GenericNote
                .filter(Column("type_id") == typeId)
                .filter(Column("deleted_at") == nil)
                .order(Column("note_date").desc, Column("updated_at").desc)
                .fetchAll(db)
        }
    }

    static func fetch(id: String) throws -> GenericNote? {
        try pool.read { db in try GenericNote.fetchOne(db, key: id) }
    }

    static func insert(_ n: GenericNote) throws {
        try pool.write { db in var x = n; try x.insert(db) }
    }

    static func update(_ n: GenericNote) throws {
        var x = n
        x.updatedAt = Date()
        try pool.write { db in try x.update(db) }
    }

    static func softDelete(id: String) throws {
        try pool.write { db in
            try db.execute(
                sql: "UPDATE generic_note SET deleted_at = ? WHERE id = ?",
                arguments: [Date(), id]
            )
        }
    }

    static func restore(id: String) throws {
        try pool.write { db in
            try db.execute(
                sql: "UPDATE generic_note SET deleted_at = NULL WHERE id = ?",
                arguments: [id]
            )
        }
    }

    static func purge(id: String) throws {
        try pool.write { db in _ = try GenericNote.deleteOne(db, key: id) }
    }
}

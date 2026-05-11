import Foundation
import GRDB

/// CRUD for the user-configurable Note Types (Staff, SCRUM, …). Type names
/// are unique (DB-enforced). `delete` is blocked if any non-deleted notes
/// reference the type; the caller should either re-home those notes first or
/// call `forceDelete` (which the UI currently doesn't expose).
@MainActor
enum NoteTypeService {
    private static var pool: DatabasePool { DatabaseService.shared.dbPool }

    static func fetchAll() throws -> [NoteType] {
        try pool.read { db in
            try NoteType.order(Column("sort_order").asc, Column("name").asc).fetchAll(db)
        }
    }

    static func insert(_ t: NoteType) throws {
        try pool.write { db in var x = t; try x.insert(db) }
    }

    static func update(_ t: NoteType) throws {
        try pool.write { db in try t.update(db) }
    }

    /// Refuses to delete a type that still has live notes — that would either
    /// cascade-delete user content (bad) or orphan rows (worse, per FK RESTRICT
    /// in the v8 migration). UI should re-home or trash the notes first.
    static func delete(id: String) throws {
        try pool.write { db in
            let live = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM generic_note WHERE type_id = ? AND deleted_at IS NULL",
                arguments: [id]
            ) ?? 0
            guard live == 0 else { throw NoteTypeError.hasLiveNotes(count: live) }
            _ = try NoteType.deleteOne(db, key: id)
        }
    }

    /// Persist a fresh ordering by writing `sort_order` from the array index.
    static func reorder(_ ordered: [NoteType]) throws {
        try pool.write { db in
            for (i, var t) in ordered.enumerated() {
                t.sortOrder = i
                try t.update(db)
            }
        }
    }
}

enum NoteTypeError: LocalizedError {
    case hasLiveNotes(count: Int)
    var errorDescription: String? {
        switch self {
        case .hasLiveNotes(let n):
            return "Can't delete a Note Type that still has \(n) note\(n == 1 ? "" : "s"). Re-home or trash those notes first."
        }
    }
}

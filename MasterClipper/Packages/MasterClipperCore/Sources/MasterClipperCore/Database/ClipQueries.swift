import Foundation
import GRDB

/// Read-only queries used by both the macOS app (against its live DatabasePool)
/// and the iOS app (against a read-only DatabaseQueue opened on the iCloud
/// snapshot). Every function takes a `DatabaseReader` so the same code path
/// works on either side.
public enum ClipQueries {

    public static func fetchAllClips(includeArchived: Bool = false, in reader: any DatabaseReader) throws -> [Clip] {
        try reader.read { db in
            var q = Clip.order(Column("created_at").desc)
            if !includeArchived { q = q.filter(Column("archived") == false) }
            return try q.fetchAll(db)
        }
    }

    public static func fetchClip(id: String, in reader: any DatabaseReader) throws -> Clip? {
        try reader.read { db in try Clip.fetchOne(db, key: id) }
    }

    public static func fetchPersonas(includeArchived: Bool = false, in reader: any DatabaseReader) throws -> [Persona] {
        try reader.read { db in
            var q = Persona.order(Column("sort_order").asc, Column("code").asc)
            if !includeArchived { q = q.filter(Column("archived") == false) }
            return try q.fetchAll(db)
        }
    }

    public static func fetchSites(includeArchived: Bool = false, in reader: any DatabaseReader) throws -> [Site] {
        try reader.read { db in
            var q = Site.order(Column("sort_order").asc, Column("code").asc)
            if !includeArchived { q = q.filter(Column("archived") == false) }
            return try q.fetchAll(db)
        }
    }

    public static func fetchCategories(includeArchived: Bool = false, in reader: any DatabaseReader) throws -> [ClipCategory] {
        try reader.read { db in
            var q = ClipCategory.order(Column("sort_order").asc, Column("name").asc)
            if !includeArchived { q = q.filter(Column("archived") == false) }
            return try q.fetchAll(db)
        }
    }

    public static func fetchClipNotes(clipId: String, in reader: any DatabaseReader) throws -> [ClipNote] {
        try reader.read { db in
            try ClipNote
                .filter(Column("clip_id") == clipId)
                .order(Column("created_at").asc, Column("id").asc)
                .fetchAll(db)
        }
    }

    public static func fetchPostings(forClip clipId: String, in reader: any DatabaseReader) throws -> [ClipPosting] {
        try reader.read { db in
            try ClipPosting
                .filter(Column("clip_id") == clipId)
                .fetchAll(db)
        }
    }

    /// Categories attached to a clip, joined through `clip_categories`. Ordered
    /// by the position column the writer maintains on the join table.
    public static func fetchCategoriesForClip(clipId: String, in reader: any DatabaseReader) throws -> [ClipCategory] {
        try reader.read { db in
            try ClipCategory.fetchAll(db, sql: """
                SELECT c.* FROM categories c
                JOIN clip_categories cc ON cc.category_id = c.id
                WHERE cc.clip_id = ?
                ORDER BY cc.position ASC
                """, arguments: [clipId])
        }
    }
}

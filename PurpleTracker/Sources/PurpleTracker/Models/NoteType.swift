import Foundation
import GRDB

/// A user-configurable Notes "folder" — e.g. Staff, Architecture, SCRUM. Each
/// `GenericNote` belongs to exactly one type. Seeded defaults live in the v8
/// migration; users can add / rename / reorder / delete via Settings.
struct NoteType: Codable, Hashable, Identifiable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "note_type"

    var id: String
    var name: String
    var sortOrder: Int
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name
        case sortOrder = "sort_order"
        case createdAt = "created_at"
    }

    static func newDraft(name: String, sortOrder: Int) -> NoteType {
        NoteType(id: UUID().uuidString, name: name,
                 sortOrder: sortOrder, createdAt: Date())
    }
}

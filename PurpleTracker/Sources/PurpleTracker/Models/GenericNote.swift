import Foundation
import GRDB

/// A free-form WYSIWYG note belonging to a `NoteType` (Staff / Architecture /
/// SCRUM / etc.). Lives in `generic_note`. The rich body is persisted as RTF
/// data (`body_rtf`); a plain-text mirror (`body_plain`) is stored alongside
/// so we can search and grep without round-tripping `NSAttributedString`.
struct GenericNote: Codable, Hashable, Identifiable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "generic_note"

    var id: String
    var typeId: String
    var noteDate: Date          // user-controlled day the note is "for"
    var title: String
    var bodyRtf: Data?          // NSAttributedString → RTF; nil = empty
    var bodyPlain: String       // plain-text mirror for search
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, title
        case typeId = "type_id"
        case noteDate = "note_date"
        case bodyRtf = "body_rtf"
        case bodyPlain = "body_plain"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    static func newDraft(typeId: String, date: Date = Date()) -> GenericNote {
        let now = Date()
        return GenericNote(
            id: UUID().uuidString,
            typeId: typeId,
            noteDate: date,
            title: "",
            bodyRtf: nil,
            bodyPlain: "",
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        )
    }
}

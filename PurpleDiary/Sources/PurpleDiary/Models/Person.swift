import Foundation
import GRDB

/// A person you mention in entries. Unlike Timeliner (where people belong to a
/// case), diary people are global — they recur across the whole journal — and
/// are linked to individual entries via the `entry_people` join table.
struct Person: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Hashable {
    var id: String                  // UUID string
    var name: String
    var notes: String

    static let databaseTableName = "people"

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case notes
    }
}

extension Person {
    static func newDraft(name: String = "") -> Person {
        Person(id: UUID().uuidString, name: name, notes: "")
    }
}

/// Join row: entry ↔ person.
struct EntryPerson: Codable, FetchableRecord, PersistableRecord, Hashable {
    var entryId: String
    var personId: String

    static let databaseTableName = "entry_people"

    enum CodingKeys: String, CodingKey {
        case entryId = "entry_id"
        case personId = "person_id"
    }
}

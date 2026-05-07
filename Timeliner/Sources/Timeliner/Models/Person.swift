import Foundation
import GRDB

struct Person: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Hashable {
    var id: String                  // UUID string
    var caseId: String              // FK → cases.id
    var name: String
    var role: String                // PersonRole.rawValue
    var notes: String

    static let databaseTableName = "people"

    enum CodingKeys: String, CodingKey {
        case id
        case caseId = "case_id"
        case name
        case role
        case notes
    }

    var roleEnum: PersonRole {
        get { PersonRole(rawValue: role) ?? .other }
        set { role = newValue.rawValue }
    }
}

extension Person {
    static func newDraft(caseId: String, role: PersonRole = .other) -> Person {
        Person(
            id: UUID().uuidString,
            caseId: caseId,
            name: "",
            role: role.rawValue,
            notes: ""
        )
    }
}

struct EventPerson: Codable, FetchableRecord, PersistableRecord, Hashable {
    var eventId: String
    var personId: String
    var roleInEvent: String?        // optional override at the event-level

    static let databaseTableName = "event_people"

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case personId = "person_id"
        case roleInEvent = "role_in_event"
    }

    static let event  = belongsTo(Event.self,  using: ForeignKey(["event_id"],  to: ["id"]))
    static let person = belongsTo(Person.self, using: ForeignKey(["person_id"], to: ["id"]))
}

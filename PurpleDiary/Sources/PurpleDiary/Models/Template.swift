import Foundation
import GRDB

/// A reusable entry scaffold. When you start a new entry from a template, its
/// `body` is rendered (date/time tokens substituted — see `TemplateService`)
/// and dropped into the new entry. Templates are user data, stored in the
/// encrypted database like everything else.
struct Template: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Hashable {
    var id: String                  // UUID
    var name: String
    var body: String                // Markdown scaffold, may contain {{tokens}}
    var sortOrder: Int
    var createdAt: String

    static let databaseTableName = "templates"

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case body
        case sortOrder = "sort_order"
        case createdAt = "created_at"
    }
}

extension Template {
    static func newDraft(name: String, body: String, sortOrder: Int = 0) -> Template {
        Template(id: UUID().uuidString, name: name, body: body,
                 sortOrder: sortOrder,
                 createdAt: ISO8601DateFormatter().string(from: Date()))
    }
}

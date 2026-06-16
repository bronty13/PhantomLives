import Foundation
import GRDB

/// A keyword in PurplePeek's local keyword store. PhotoKit cannot read keywords, so the
/// vocabulary lives here; `source` distinguishes keywords the user created (`local`) from
/// ones seeded out of Photos via the optional `osxphotos` import (`photos`).
struct Keyword: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable {
    var id: String
    var name: String
    var source: String        // "local" | "photos"
    var createdAt: String

    static let databaseTableName = "keywords"

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case source
        case createdAt = "created_at"
    }

    enum Source: String {
        case local
        case photos
    }
}

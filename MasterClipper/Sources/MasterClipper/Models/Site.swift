import Foundation
import GRDB

struct Site: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Hashable {
    var id: Int64?
    var code: String
    var displayName: String
    var personaScope: String   // CSV of persona codes, e.g. "CoC,PoA"
    var sortOrder: Int
    var archived: Bool

    static let databaseTableName = "sites"

    enum CodingKeys: String, CodingKey {
        case id
        case code
        case displayName = "display_name"
        case personaScope = "persona_scope"
        case sortOrder = "sort_order"
        case archived
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    var personaScopeList: [String] {
        personaScope.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    func appliesTo(personaCode: String) -> Bool {
        personaScopeList.contains { $0.caseInsensitiveCompare(personaCode) == .orderedSame }
    }
}

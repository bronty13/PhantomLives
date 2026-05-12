import Foundation
import GRDB

public struct Site: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Hashable {
    public var id: Int64?
    public var code: String
    public var displayName: String
    public var personaScope: String   // CSV of persona codes, e.g. "CoC,PoA"
    public var sortOrder: Int
    public var archived: Bool

    public static let databaseTableName = "sites"

    enum CodingKeys: String, CodingKey {
        case id
        case code
        case displayName = "display_name"
        case personaScope = "persona_scope"
        case sortOrder = "sort_order"
        case archived
    }

    public init(
        id: Int64? = nil,
        code: String,
        displayName: String,
        personaScope: String,
        sortOrder: Int,
        archived: Bool
    ) {
        self.id = id
        self.code = code
        self.displayName = displayName
        self.personaScope = personaScope
        self.sortOrder = sortOrder
        self.archived = archived
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public var personaScopeList: [String] {
        personaScope.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    public func appliesTo(personaCode: String) -> Bool {
        personaScopeList.contains { $0.caseInsensitiveCompare(personaCode) == .orderedSame }
    }
}

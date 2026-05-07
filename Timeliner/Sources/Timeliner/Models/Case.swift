import Foundation
import GRDB

struct Case: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Hashable {
    var id: String                  // UUID string, stable across exports
    var title: String
    var caseDescription: String     // free-form intro / synopsis (markdown OK)
    var status: String              // CaseStatus.rawValue
    var pinned: Bool
    var createdAt: String           // ISO-8601
    var updatedAt: String

    static let databaseTableName = "cases"

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case caseDescription = "description"
        case status
        case pinned
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var statusEnum: CaseStatus {
        get { CaseStatus(rawValue: status) ?? .active }
        set { status = newValue.rawValue }
    }
}

extension Case {
    static func newDraft(title: String = "") -> Case {
        let now = ISO8601DateFormatter().string(from: Date())
        return Case(
            id: UUID().uuidString,
            title: title,
            caseDescription: "",
            status: CaseStatus.active.rawValue,
            pinned: false,
            createdAt: now,
            updatedAt: now
        )
    }
}

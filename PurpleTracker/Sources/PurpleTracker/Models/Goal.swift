import Foundation
import GRDB

/// A team/business goal a Matter can be tagged against. Many-to-many with
/// Matter via the `matter_goal` join table. User-configurable in
/// Settings → Goals.
struct Goal: Codable, Hashable, Identifiable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "goal"

    var id: String          // UUID
    var name: String
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, name
        case sortOrder = "sort_order"
    }
}

extension Goal {
    /// Default seed list — the team's current quarter goals.
    static let seedNames: [String] = [
        "Checkmarx Onboarding",
        "Disaster Recovery Business Continuity Risk Goal",
        "Information Security Team Goal",
        "Mimecast Expansion",
        "Optimize Assurance",
        "Optimize SentinelOne",
        "Support All defi Initiatives"
    ]
}

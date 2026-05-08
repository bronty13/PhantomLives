import Foundation
import GRDB

/// A strategic initiative a Matter can be tagged against. Many-to-many with
/// Matter via the `matter_initiative` join table. User-configurable in
/// Settings → Initiatives.
struct Initiative: Codable, Hashable, Identifiable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "initiative"

    var id: String          // UUID
    var name: String
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, name
        case sortOrder = "sort_order"
    }
}

extension Initiative {
    /// Default seed list per user spec. Order preserved as `sort_order`.
    static let seedNames: [String] = [
        "Meet all client commitments",
        "Grow Originations ARR",
        "Optimize operations",
        "Develop plans for new sources of revenue",
        "Grow client base opportunistically",
        "Increase revenue per client",
        "Market expansion",
        "Acquisitions"
    ]
}

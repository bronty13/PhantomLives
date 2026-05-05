import Foundation
import GRDB

/// Configurable dropdown entry for the per-clip "exclude from posting"
/// flag. Managed in **Settings → Posting**; seeded with three default
/// reasons (Custom, Not Posted - Sent Individually, Other - Please
/// specify) and the user can add / archive their own.
struct ExclusionReason: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable {
    var id: Int64?
    var label: String
    var sortOrder: Int
    var archived: Bool

    static let databaseTableName = "exclusion_reasons"

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case sortOrder = "sort_order"
        case archived
    }
}

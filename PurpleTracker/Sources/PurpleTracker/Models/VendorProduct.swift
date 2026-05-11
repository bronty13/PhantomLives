import Foundation
import GRDB

/// A product line provided by a Third Party. Repeatable list; `sortOrder`
/// is hand-curated so the UI can drag-to-reorder later.
struct VendorProduct: Codable, Hashable, Identifiable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "vendor_product"

    var id: String          // UUID
    var vendorId: String
    var sortOrder: Int
    var name: String
    var notes: String

    enum CodingKeys: String, CodingKey {
        case id, name, notes
        case vendorId = "vendor_id"
        case sortOrder = "sort_order"
    }
}

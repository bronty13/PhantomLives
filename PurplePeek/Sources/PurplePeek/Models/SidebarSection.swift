import Foundation
import GRDB

/// A user-defined sidebar group that scan roots can be filed under. Roots with a matching
/// `section_id` appear beneath this section's header; roots with a NULL `section_id` live in
/// the implicit default ("Folders") group. `sortOrder` orders the sections themselves.
struct SidebarSection: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable {
    var id: String
    var name: String
    var sortOrder: Int
    var createdAt: String

    static let databaseTableName = "sidebar_sections"

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case sortOrder = "sort_order"
        case createdAt = "created_at"
    }
}

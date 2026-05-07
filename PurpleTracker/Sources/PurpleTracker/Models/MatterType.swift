import Foundation
import GRDB

/// Configurable Matter type — drives both classification and the color shown
/// on the Matter list-row leading bar / detail header. `isCadenced == true`
/// marks the special "Cadenced Activities" type whose Matters carry a
/// `Cadence` and auto-spawn a follow-up on close.
struct MatterType: Codable, Hashable, Identifiable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "matter_type"

    var id: String                  // UUID
    var name: String
    var colorHex: String
    var sortOrder: Int
    var isCadenced: Bool

    enum CodingKeys: String, CodingKey {
        case id, name
        case colorHex = "color_hex"
        case sortOrder = "sort_order"
        case isCadenced = "is_cadenced"
    }
}

extension MatterType {
    /// Default seed list. Colors chosen for visual distinction. Index order
    /// is preserved as `sort_order` and matches the spec.
    static let seedTypes: [(name: String, color: String, cadenced: Bool)] = [
        ("Client Request",         "#3B82F6", false),  // blue
        ("SSAE/SOC Audit",         "#7C3AED", false),  // purple
        ("Client Audit",           "#A855F7", false),  // violet
        ("External Audit",         "#EC4899", false),  // pink
        ("DR/BCP",                 "#EF4444", false),  // red
        ("Assurance",              "#F97316", false),  // orange
        ("Policies and Standards", "#F59E0B", false),  // amber
        ("Investigation",          "#EAB308", false),  // yellow
        ("Legal",                  "#84CC16", false),  // lime
        ("Human Resources",        "#22C55E", false),  // green
        ("Finance",                "#14B8A6", false),  // teal
        ("AI Enablement",          "#06B6D4", false),  // cyan
        ("Staff",                  "#0EA5E9", false),  // sky
        ("Cadenced Activities",    "#6366F1", true ),  // indigo
    ]
}

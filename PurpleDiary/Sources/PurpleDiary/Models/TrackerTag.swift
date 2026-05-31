import Foundation
import GRDB

/// What kind of value a tracker holds. Determines the editor control and how a
/// logged value is formatted/graphed.
enum TrackerKind: String, Codable, CaseIterable, Hashable {
    case number     // a plain quantity (cups of water, pages read, km run) — paired with `unit`
    case duration   // minutes, shown as "1h 20m" / "45m"
    case boolean    // yes/no, stored as 0/1

    var label: String {
        switch self {
        case .number:   return "Number"
        case .duration: return "Duration"
        case .boolean:  return "Yes / No"
        }
    }

    var systemImage: String {
        switch self {
        case .number:   return "number"
        case .duration: return "clock"
        case .boolean:  return "checkmark.square"
        }
    }

    /// Format a stored value for display, given the tracker's free-text `unit`
    /// (used only by `.number`).
    func format(_ value: Double, unit: String) -> String {
        switch self {
        case .boolean:
            return value >= 0.5 ? "Yes" : "No"
        case .duration:
            let total = Int(value.rounded())
            let h = total / 60, m = total % 60
            if h > 0 && m > 0 { return "\(h)h \(m)m" }
            if h > 0          { return "\(h)h" }
            return "\(m)m"
        case .number:
            // Trim a trailing ".0" so whole numbers read cleanly.
            let n = value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
            return unit.isEmpty ? n : "\(n) \(unit)"
        }
    }
}

/// A user-defined quantified metric you can log per entry and graph over time
/// (water intake, sleep hours, mood-adjacent self-ratings, "did I exercise?").
/// `rowId` is the autoincrement PK; `id` (Identifiable) is the unique name —
/// mirrors `Tag`'s shape so the management UI patterns port directly.
struct TrackerTag: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Hashable {
    var rowId: Int64?
    var name: String
    var unit: String            // free text for `.number` (e.g. "cups"); ignored for duration/bool
    var kind: TrackerKind
    var colorHex: String

    var id: String { name }

    static let databaseTableName = "tracker_tags"

    enum CodingKeys: String, CodingKey {
        case rowId = "id"
        case name
        case unit
        case kind
        case colorHex = "color_hex"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        rowId = inserted.rowID
    }
}

/// Join row: a value logged for `trackerTagId` on `entryId`. One value per
/// (entry, tracker). For `.boolean` trackers the value is 0 or 1; for
/// `.duration` it's minutes; for `.number` it's the raw quantity.
struct TrackerValue: Codable, FetchableRecord, PersistableRecord, Hashable {
    var entryId: String
    var trackerTagId: Int64
    var value: Double

    static let databaseTableName = "tracker_values"

    enum CodingKeys: String, CodingKey {
        case entryId = "entry_id"
        case trackerTagId = "tracker_tag_id"
        case value
    }
}

import Foundation
import GRDB

struct ClipHistoryEntry: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Hashable {
    var id: Int64?
    var clipId: String
    var field: String           // "title" | "status" | "go_live_date" | …
    var oldValue: String?
    var newValue: String?
    var changedAt: String       // ISO timestamp

    static let databaseTableName = "clip_history"

    enum CodingKeys: String, CodingKey {
        case id
        case clipId = "clip_id"
        case field
        case oldValue = "old_value"
        case newValue = "new_value"
        case changedAt = "changed_at"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    /// Human-readable label for the field name. Falls back to the raw key.
    var fieldLabel: String {
        switch field {
        case "title":               return "Title"
        case "external_clip_id":    return "External Clip ID"
        case "tracking_tag":        return "Tracking Tag"
        case "persona_code":        return "Persona"
        case "description_raw":     return "Description (raw)"
        case "description_refined": return "Description (refined)"
        case "keywords":            return "Keywords"
        case "performers":          return "Performers"
        case "clip_filename":       return "Clip Filename"
        case "thumbnail_filename":  return "Thumbnail Filename"
        case "preview_filename":    return "Preview Filename"
        case "length_seconds":      return "Length"
        case "price_cents":         return "Price"
        case "sales_count":         return "Sales count"
        case "income_cents":        return "Income"
        case "content_date":        return "Content date"
        case "go_live_date":        return "Go-Live date"
        case "status":               return "Status"
        case "archived":            return "Archived"
        case "notes":               return "Notes"
        case "categories":          return "Categories"
        default:                    return field
        }
    }
}

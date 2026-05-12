import Foundation
import GRDB

public struct ClipHistoryEntry: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Hashable {
    public var id: Int64?
    public var clipId: String
    public var field: String
    public var oldValue: String?
    public var newValue: String?
    public var changedAt: String

    public static let databaseTableName = "clip_history"

    enum CodingKeys: String, CodingKey {
        case id
        case clipId = "clip_id"
        case field
        case oldValue = "old_value"
        case newValue = "new_value"
        case changedAt = "changed_at"
    }

    public init(
        id: Int64? = nil,
        clipId: String,
        field: String,
        oldValue: String? = nil,
        newValue: String? = nil,
        changedAt: String
    ) {
        self.id = id
        self.clipId = clipId
        self.field = field
        self.oldValue = oldValue
        self.newValue = newValue
        self.changedAt = changedAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public var fieldLabel: String {
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
        case "status":              return "Status"
        case "archived":            return "Archived"
        case "notes":               return "Notes"
        case "categories":          return "Categories"
        default:                    return field
        }
    }
}

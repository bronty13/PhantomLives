import Foundation
import GRDB

/// A timestamped vendor note. Parallel to `note` on Matter, but on its own
/// table so cascades and queries stay tidy. Attachments per note live in
/// `vendor_attachment` with `kind = 'note'` and `parent_id = note.id`.
struct VendorNote: Codable, Hashable, Identifiable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "vendor_note"

    var id: String          // UUID
    var vendorId: String
    var bodyMd: String
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case vendorId = "vendor_id"
        case bodyMd = "body_md"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

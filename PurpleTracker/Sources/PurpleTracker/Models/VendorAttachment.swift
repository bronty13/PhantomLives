import Foundation
import GRDB

/// A file attached to a Third Party. Mirrors `attachment` (BLOB + hashes)
/// but lives on its own table so vendors stay self-contained. The same row
/// shape covers contracts, invoices, vendor notes, and "other" files —
/// distinguished by `kind` and (for invoices / notes) the optional
/// `parentId` linking back to the relevant child row.
///
///   kind = 'contract'  → parent_id NULL
///   kind = 'invoice'   → parent_id = vendor_invoice.id (deleted with invoice)
///   kind = 'note'      → parent_id = vendor_note.id    (deleted with note)
///   kind = 'other'     → parent_id NULL
///
/// SHA1 is the integrity-check algorithm (same as Matter attachments).
struct VendorAttachment: Codable, Hashable, Identifiable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "vendor_attachment"

    var id: String                  // UUID
    var vendorId: String
    var kind: String                // VendorAttachmentKind.rawValue
    var parentId: String?           // optional FK into vendor_invoice / vendor_note
    var filename: String
    var sizeBytes: Int64
    var mimeType: String
    var data: Data
    var md5: String
    var sha1: String
    var sha256: String
    var addedAt: Date
    var lastVerifiedAt: Date?
    var lastVerifyOk: Bool

    enum CodingKeys: String, CodingKey {
        case id, kind, filename, data, md5, sha1, sha256
        case vendorId = "vendor_id"
        case parentId = "parent_id"
        case sizeBytes = "size_bytes"
        case mimeType = "mime_type"
        case addedAt = "added_at"
        case lastVerifiedAt = "last_verified_at"
        case lastVerifyOk = "last_verify_ok"
    }
}

enum VendorAttachmentKind: String, CaseIterable, Identifiable {
    case contract, invoice, note, other
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .contract: return "Contract"
        case .invoice:  return "Invoice"
        case .note:     return "Note"
        case .other:    return "Other"
        }
    }
}

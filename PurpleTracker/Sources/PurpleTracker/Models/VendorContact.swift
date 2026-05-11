import Foundation
import GRDB

/// A point of contact at a Third Party. Three fixed kinds per the user
/// spec: sales / escalation / technical. Stored as separate rows (rather than
/// fixed columns on `vendor`) so phone/mobile/email per role share a schema
/// and we can extend with more kinds later without another migration.
struct VendorContact: Codable, Hashable, Identifiable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "vendor_contact"

    var id: String                  // UUID
    var vendorId: String            // FK vendor.id
    var kind: String                // ContactKind.rawValue
    var name: String
    var title: String
    var phone: String
    var mobile: String
    var email: String

    enum CodingKeys: String, CodingKey {
        case id, kind, name, title, phone, mobile, email
        case vendorId = "vendor_id"
    }
}

enum VendorContactKind: String, CaseIterable, Identifiable {
    case sales      = "sales"
    case escalation = "escalation"
    case technical  = "technical"
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .sales:      return "Sales"
        case .escalation: return "Escalation"
        case .technical:  return "Technical"
        }
    }
}

extension VendorContact {
    static func empty(vendorId: String, kind: VendorContactKind) -> VendorContact {
        VendorContact(id: UUID().uuidString, vendorId: vendorId,
                      kind: kind.rawValue, name: "", title: "",
                      phone: "", mobile: "", email: "")
    }
}

import Foundation
import GRDB

/// A Third Party (vendor) — the v1.4.0 master entity. Demographics + free-form
/// fields. Child rows live in `vendor_contact`, `vendor_product`,
/// `vendor_year_amount`, `vendor_invoice`, `vendor_note`, `vendor_attachment`.
/// Soft-delete via `deletedAt` (the same pattern Matter uses).
struct Vendor: Codable, Hashable, Identifiable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "vendor"

    var id: String                          // UUID
    var name: String
    var address: String
    var website: String
    var phone: String
    var reseller: String                    // "Cyber One" | "CDW" | "Other"
    var resellerOther: String               // populated when reseller == "Other"
    var rating: Int?                        // 1..5, nullable
    var ratingNote: String
    var descriptionMd: String
    var dataCenter: String
    var exitStrategyMd: String
    var contractSummaryMd: String
    var costingSummaryMd: String
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, address, website, phone, reseller, rating
        case resellerOther = "reseller_other"
        case ratingNote = "rating_note"
        case descriptionMd = "description_md"
        case dataCenter = "data_center"
        case exitStrategyMd = "exit_strategy_md"
        case contractSummaryMd = "contract_summary_md"
        case costingSummaryMd = "costing_summary_md"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    static func newDraft(name: String = "") -> Vendor {
        let now = Date()
        return Vendor(
            id: UUID().uuidString,
            name: name,
            address: "",
            website: "",
            phone: "",
            reseller: Reseller.cyberOne.rawValue,
            resellerOther: "",
            rating: nil,
            ratingNote: "",
            descriptionMd: "",
            dataCenter: "",
            exitStrategyMd: "",
            contractSummaryMd: "",
            costingSummaryMd: "",
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        )
    }

    /// User-facing reseller label (free text when "Other").
    var resellerDisplay: String {
        if reseller == Reseller.other.rawValue && !resellerOther.isEmpty {
            return resellerOther
        }
        return reseller
    }
}

/// Pick-list of reseller values. "Other" stores its specific value in
/// `Vendor.resellerOther`.
enum Reseller: String, CaseIterable, Identifiable {
    case cyberOne = "Cyber One"
    case cdw = "CDW"
    case other = "Other"
    var id: String { rawValue }
}

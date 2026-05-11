import Foundation
import GRDB

/// Per-vendor, per-year **budget** and optional **actual override**. The
/// effective actual for a year is computed as:
///
///   `actualOverrideCents ?? SUM(vendor_invoice.amount_cents WHERE year = Y)`
///
/// — manual override beats the invoice rollup if it is present.
/// Year is stored as an integer (e.g. 2026).
struct VendorYearAmount: Codable, Hashable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "vendor_year_amount"

    var vendorId: String
    var year: Int
    var budgetCents: Int64
    var actualOverrideCents: Int64?     // NULL → fall back to invoice rollup

    enum CodingKeys: String, CodingKey {
        case year
        case vendorId = "vendor_id"
        case budgetCents = "budget_cents"
        case actualOverrideCents = "actual_override_cents"
    }
}

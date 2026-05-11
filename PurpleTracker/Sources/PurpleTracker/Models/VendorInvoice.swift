import Foundation
import GRDB

/// A vendor invoice. First-class row so multiple invoices in a year can be
/// summed for the "effective actual". The `year` column is derived from
/// `invoiceDate` at insert time and indexed for fast SUM-by-year queries.
/// Backdating is allowed (no min-date guard) so historical loads work.
struct VendorInvoice: Codable, Hashable, Identifiable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "vendor_invoice"

    var id: String                  // UUID
    var vendorId: String            // FK vendor.id
    var invoiceDate: Date
    var year: Int                   // mirror of Calendar.component(.year, …) for indexed SUMs
    var amountCents: Int64
    var vendorInvoiceNumber: String
    var memo: String
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, year, memo
        case vendorId = "vendor_id"
        case invoiceDate = "invoice_date"
        case amountCents = "amount_cents"
        case vendorInvoiceNumber = "vendor_invoice_number"
        case createdAt = "created_at"
    }

    /// Returns the calendar year of `date` in the user's current calendar.
    /// Centralised here so insertions and migrations stay consistent.
    static func yearOf(_ date: Date) -> Int {
        Calendar.current.component(.year, from: date)
    }
}

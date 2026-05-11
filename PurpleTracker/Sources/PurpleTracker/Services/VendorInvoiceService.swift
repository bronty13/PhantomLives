import Foundation
import GRDB

/// Invoice CRUD + the "effective actual" rollup that drives the Budget &
/// Actuals matrix on the vendor detail. Invariants:
///
///   - `year` is always derived from `invoice_date` at insert time (consistent
///      with `VendorInvoice.yearOf`); the column is indexed.
///   - The **effective actual** for `(vendor, year)` is
///         `override ?? SUM(amount_cents)`.
///     `override = nil` (NULL) → invoice sum wins; any non-NULL override —
///     even `0` — replaces the rollup. This is intentional so a user can pin
///     the actuals to a known value if invoices are mid-load.
@MainActor
enum VendorInvoiceService {

    private static var pool: DatabasePool { DatabaseService.shared.dbPool }

    static func fetchInvoices(vendorId: String) throws -> [VendorInvoice] {
        try pool.read { db in
            try VendorInvoice
                .filter(Column("vendor_id") == vendorId)
                .order(Column("invoice_date").desc)
                .fetchAll(db)
        }
    }

    /// Insert an invoice. Year is recomputed from `invoiceDate`, ignoring any
    /// caller-supplied value so backdating produces correct rollup buckets.
    @discardableResult
    static func insert(vendorId: String, date: Date, amountCents: Int64,
                       vendorInvoiceNumber: String = "", memo: String = "") throws -> VendorInvoice {
        let inv = VendorInvoice(
            id: UUID().uuidString,
            vendorId: vendorId,
            invoiceDate: date,
            year: VendorInvoice.yearOf(date),
            amountCents: amountCents,
            vendorInvoiceNumber: vendorInvoiceNumber,
            memo: memo,
            createdAt: Date()
        )
        try pool.write { db in var x = inv; try x.insert(db) }
        return inv
    }

    /// Update — recomputes `year` from `invoiceDate` so callers can move an
    /// invoice between years without touching `year` themselves.
    static func update(_ invoice: VendorInvoice) throws {
        var x = invoice
        x.year = VendorInvoice.yearOf(x.invoiceDate)
        try pool.write { db in try x.update(db) }
    }

    static func delete(id: String) throws {
        try pool.write { db in _ = try VendorInvoice.deleteOne(db, key: id) }
    }

    /// SUM of invoice amounts per year for one vendor, keyed by year.
    /// Years with no invoices are absent (not 0).
    static func invoiceTotalsByYear(vendorId: String) throws -> [Int: Int64] {
        try pool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT year, COALESCE(SUM(amount_cents), 0) AS total
                FROM vendor_invoice
                WHERE vendor_id = ?
                GROUP BY year
                """, arguments: [vendorId])
            var out: [Int: Int64] = [:]
            for r in rows { out[r["year"]] = r["total"] }
            return out
        }
    }

    /// Effective actuals for `(vendor, year ∈ years)`: override ?? invoice sum.
    /// Always returns an entry for every requested year (0 if neither is set).
    static func effectiveActuals(vendorId: String, years: [Int]) throws -> [Int: Int64] {
        let sums = try invoiceTotalsByYear(vendorId: vendorId)
        let overrides: [Int: Int64?] = try pool.read { db in
            var out: [Int: Int64?] = [:]
            let rows = try Row.fetchAll(db, sql: """
                SELECT year, actual_override_cents
                FROM vendor_year_amount
                WHERE vendor_id = ?
                """, arguments: [vendorId])
            for r in rows { out[r["year"]] = r["actual_override_cents"] as Int64? }
            return out
        }
        var result: [Int: Int64] = [:]
        for y in years {
            if let override = overrides[y], let v = override {
                result[y] = v
            } else {
                result[y] = sums[y] ?? 0
            }
        }
        return result
    }
}

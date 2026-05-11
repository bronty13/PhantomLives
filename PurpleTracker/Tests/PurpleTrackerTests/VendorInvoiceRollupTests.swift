import XCTest
import GRDB
@testable import PurpleTracker

/// Effective-actual rollup:
///   override ?? SUM(invoices in year)
/// — any non-NULL override (including 0) replaces the rollup.
@MainActor
final class VendorInvoiceRollupTests: XCTestCase {

    private func seed(vendorId: String, invoices: [(year: Int, cents: Int64)]) throws {
        let pool = DatabaseService.shared.dbPool
        try pool.write { db in
            try db.execute(
                sql: """
                INSERT INTO vendor (id, name, reseller, created_at, updated_at)
                VALUES (?, 'Acme', 'CDW', ?, ?)
                """,
                arguments: [vendorId, Date(), Date()]
            )
            for (i, inv) in invoices.enumerated() {
                let comp = DateComponents(year: inv.year, month: 6, day: 15)
                let date = Calendar.current.date(from: comp)!
                try db.execute(
                    sql: """
                    INSERT INTO vendor_invoice
                        (id, vendor_id, invoice_date, year, amount_cents,
                         vendor_invoice_number, memo, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: ["inv-\(i)", vendorId, date, inv.year, inv.cents,
                                "", "", Date()]
                )
            }
        }
    }

    private func wipe() throws {
        let pool = DatabaseService.shared.dbPool
        try pool.write { db in
            try db.execute(sql: "DELETE FROM vendor_invoice")
            try db.execute(sql: "DELETE FROM vendor_year_amount")
            try db.execute(sql: "DELETE FROM vendor")
        }
    }

    func testSumOnlyPathWhenNoOverride() async throws {
        try wipe()
        try seed(vendorId: "v-sum",
                 invoices: [(2026, 10_000), (2026, 25_000), (2027, 99_999)])
        let actuals = try VendorInvoiceService.effectiveActuals(
            vendorId: "v-sum", years: [2026, 2027, 2028]
        )
        XCTAssertEqual(actuals[2026], 35_000)
        XCTAssertEqual(actuals[2027], 99_999)
        XCTAssertEqual(actuals[2028], 0)
    }

    func testManualOverrideBeatsSum() async throws {
        try wipe()
        try seed(vendorId: "v-ovr",
                 invoices: [(2026, 100_000), (2026, 100_000)])
        // Pin 2026 actual to a different value.
        try VendorService.upsertYearAmount(VendorYearAmount(
            vendorId: "v-ovr", year: 2026,
            budgetCents: 0, actualOverrideCents: 50_000
        ))
        let actuals = try VendorInvoiceService.effectiveActuals(
            vendorId: "v-ovr", years: [2026]
        )
        XCTAssertEqual(actuals[2026], 50_000)
    }

    func testZeroOverrideStillBeatsSum() async throws {
        try wipe()
        try seed(vendorId: "v-zero",
                 invoices: [(2026, 100_000)])
        try VendorService.upsertYearAmount(VendorYearAmount(
            vendorId: "v-zero", year: 2026,
            budgetCents: 0, actualOverrideCents: 0
        ))
        let actuals = try VendorInvoiceService.effectiveActuals(
            vendorId: "v-zero", years: [2026]
        )
        XCTAssertEqual(actuals[2026], 0,
                       "Explicit override of 0 must beat the invoice rollup")
    }

    func testClearingOverrideReturnsToSum() async throws {
        try wipe()
        try seed(vendorId: "v-clr", invoices: [(2026, 42_000)])
        try VendorService.upsertYearAmount(VendorYearAmount(
            vendorId: "v-clr", year: 2026,
            budgetCents: 0, actualOverrideCents: 12_345
        ))
        try VendorService.upsertYearAmount(VendorYearAmount(
            vendorId: "v-clr", year: 2026,
            budgetCents: 0, actualOverrideCents: nil
        ))
        let actuals = try VendorInvoiceService.effectiveActuals(
            vendorId: "v-clr", years: [2026]
        )
        XCTAssertEqual(actuals[2026], 42_000)
    }

    func testBackdatedInvoiceLandsInCorrectYear() async throws {
        try wipe()
        // Insert via the service path (which sets `year` from the date)
        // — proves backdating to 2020 buckets under 2020, not the current
        // calendar year.
        let pool = DatabaseService.shared.dbPool
        try await pool.write { db in
            try db.execute(
                sql: """
                INSERT INTO vendor (id, name, reseller, created_at, updated_at)
                VALUES ('v-bd', 'X', 'CDW', ?, ?)
                """, arguments: [Date(), Date()]
            )
        }
        let backdated = Calendar.current.date(from: DateComponents(year: 2020, month: 1, day: 1))!
        _ = try VendorInvoiceService.insert(
            vendorId: "v-bd", date: backdated, amountCents: 7_500
        )
        let actuals = try VendorInvoiceService.effectiveActuals(
            vendorId: "v-bd", years: [2020, 2021]
        )
        XCTAssertEqual(actuals[2020], 7_500)
        XCTAssertEqual(actuals[2021], 0)
    }
}

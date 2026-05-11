import XCTest
@testable import PurpleTracker

@MainActor
final class VendorReportTests: XCTestCase {

    private func wipe() throws {
        let pool = DatabaseService.shared.dbPool
        try pool.write { db in
            try db.execute(sql: "DELETE FROM vendor_invoice")
            try db.execute(sql: "DELETE FROM vendor_year_amount")
            try db.execute(sql: "DELETE FROM vendor_product")
            try db.execute(sql: "DELETE FROM vendor_contact")
            try db.execute(sql: "DELETE FROM vendor")
        }
    }

    func testSingleVendorBasicHasHeaderAndMatrix() async throws {
        try wipe()
        var v = Vendor.newDraft(name: "Acme")
        v.reseller = "CDW"
        v.rating = 4
        try VendorService.insert(v)
        try VendorService.upsertYearAmount(VendorYearAmount(
            vendorId: v.id, year: 2026, budgetCents: 100_000, actualOverrideCents: nil
        ))
        let md = VendorReportService.renderMarkdown(
            vendor: v, detailed: false, yearRange: [2026, 2027]
        )
        XCTAssertTrue(md.contains("# Acme"))
        XCTAssertTrue(md.contains("**Reseller:** CDW"))
        XCTAssertTrue(md.contains("## Budget & Actuals"))
        XCTAssertTrue(md.contains("| 2026 |"))
        XCTAssertTrue(md.contains("| 2027 |"))
    }

    func testSingleVendorDetailedIncludesAllSectionsWhenPopulated() async throws {
        try wipe()
        var v = Vendor.newDraft(name: "Big Vendor")
        v.contractSummaryMd = "We pay them money."
        v.costingSummaryMd  = "It is a lot."
        v.exitStrategyMd    = "Run."
        try VendorService.insert(v)
        try VendorService.upsertContact(VendorContact(
            id: "c1", vendorId: v.id, kind: "sales",
            name: "Pat Buyer", phone: "555", mobile: "", email: "pat@example.com"
        ))
        let md = VendorReportService.renderMarkdown(
            vendor: v, detailed: true, yearRange: [2026]
        )
        XCTAssertTrue(md.contains("## Contract Summary"))
        XCTAssertTrue(md.contains("## Costing Summary"))
        XCTAssertTrue(md.contains("## Exit Strategy"))
        XCTAssertTrue(md.contains("## Contacts"))
        XCTAssertTrue(md.contains("Pat Buyer"))
    }

    func testAllVendorsBasicIsATable() async throws {
        try wipe()
        try VendorService.insert(Vendor.newDraft(name: "Alpha"))
        try VendorService.insert(Vendor.newDraft(name: "Bravo"))
        let vendors = try VendorService.fetchAllLive()
        let md = VendorReportService.renderAllVendorsBasic(vendors, yearRange: [2026])
        XCTAssertTrue(md.contains("| Vendor |"))
        XCTAssertTrue(md.contains("| Alpha |"))
        XCTAssertTrue(md.contains("| Bravo |"))
    }
}

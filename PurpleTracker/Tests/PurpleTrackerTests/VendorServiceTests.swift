import XCTest
@testable import PurpleTracker

@MainActor
final class VendorServiceTests: XCTestCase {

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

    func testInsertFetchUpdateSoftDelete() async throws {
        try wipe()
        var v = Vendor.newDraft(name: "Test Vendor")
        try VendorService.insert(v)
        let live = try VendorService.fetchAllLive()
        XCTAssertTrue(live.contains(where: { $0.id == v.id }))

        v.name = "Renamed"
        try VendorService.update(v)
        let fetched = try VendorService.fetch(id: v.id)
        XCTAssertEqual(fetched?.name, "Renamed")

        try VendorService.softDelete(id: v.id)
        XCTAssertFalse(try VendorService.fetchAllLive().contains(where: { $0.id == v.id }))
        XCTAssertTrue(try VendorService.fetchTrashed().contains(where: { $0.id == v.id }))

        try VendorService.restore(id: v.id)
        XCTAssertTrue(try VendorService.fetchAllLive().contains(where: { $0.id == v.id }))
    }

    func testResellerOtherRoundTrip() async throws {
        try wipe()
        var v = Vendor.newDraft(name: "Other Vendor")
        v.reseller = Reseller.other.rawValue
        v.resellerOther = "Bob's Resale"
        try VendorService.insert(v)
        let fetched = try XCTUnwrap(try VendorService.fetch(id: v.id))
        XCTAssertEqual(fetched.resellerDisplay, "Bob's Resale")
    }

    func testMoneyParseAndFormatRoundTrip() {
        XCTAssertEqual(Money.parse("$1,234.56"), 123_456)
        XCTAssertEqual(Money.parse(""), nil)
        XCTAssertEqual(Money.parse("12.50"), 1_250)
        XCTAssertTrue(Money.format(cents: 1_234_500).contains("12,345"))
    }
}

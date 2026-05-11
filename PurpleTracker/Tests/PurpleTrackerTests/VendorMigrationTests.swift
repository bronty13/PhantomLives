import XCTest
import GRDB
@testable import PurpleTracker

@MainActor
final class VendorMigrationTests: XCTestCase {

    func testV6CreatesAllThirdPartyTables() throws {
        let q = try DatabaseQueue()
        try DatabaseService.applyMigrations(to: q)
        try q.read { db in
            for table in ["vendor","vendor_contact","vendor_product",
                          "vendor_year_amount","vendor_invoice","vendor_note",
                          "vendor_attachment"] {
                XCTAssertTrue(try db.tableExists(table), "Missing table: \(table)")
            }
            let cols = try db.columns(in: "matter").map(\.name)
            XCTAssertTrue(cols.contains("vendor_id"))
        }
    }

    func testV6IsIdempotent() throws {
        let q = try DatabaseQueue()
        try DatabaseService.applyMigrations(to: q)
        try DatabaseService.applyMigrations(to: q)
        try q.read { db in
            XCTAssertTrue(try db.tableExists("vendor"))
        }
    }

    /// Vendor hard-delete must null Matter.vendor_id (ON DELETE SET NULL),
    /// not delete the Matter.
    func testHardDeletingVendorSetsMatterVendorIdNull() throws {
        let q = try DatabaseQueue()
        try DatabaseService.applyMigrations(to: q)
        try q.write { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
            // Seed a Matter type + matter referencing a vendor.
            try db.execute(sql:
                "INSERT INTO matter_type (id, name) VALUES ('t1', 'Test')")
            try db.execute(sql:
                """
                INSERT INTO vendor (id, name, reseller, created_at, updated_at)
                VALUES ('v1', 'Acme', 'CDW', ?, ?)
                """,
                arguments: [Date(), Date()]
            )
            try db.execute(sql:
                """
                INSERT INTO matter (id, title, type_id, status, created_at, accessed_at, modified_at, vendor_id)
                VALUES ('2026-01-01-00001', 'm', 't1', 'New', ?, ?, ?, 'v1')
                """,
                arguments: [Date(), Date(), Date()]
            )
            try db.execute(sql: "DELETE FROM vendor WHERE id = 'v1'")
            let vid = try String.fetchOne(db, sql:
                "SELECT vendor_id FROM matter WHERE id = '2026-01-01-00001'")
            // ON DELETE SET NULL → row remains, fk goes nil
            XCTAssertNil(vid)
        }
    }
}

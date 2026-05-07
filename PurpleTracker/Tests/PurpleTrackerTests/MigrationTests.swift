import XCTest
import GRDB
@testable import PurpleTracker

@MainActor
final class MigrationTests: XCTestCase {
    func testV1AppliesCleanlyAndCreatesAllTables() throws {
        let q = try DatabaseQueue()
        try DatabaseService.applyMigrations(to: q)

        try q.read { db in
            for table in ["matter_type","status_value","cadence","matter_id_counter",
                          "matter","time_entry","note","attachment","person"] {
                XCTAssertTrue(try db.tableExists(table), "Missing table: \(table)")
            }
        }
    }

    /// v2 added the People roster + `requestor_associate_id` on matter.
    /// v3 added 5 internal IP FKs and 5 external IP free-text columns.
    func testV2AndV3MatterColumnsExist() throws {
        let q = try DatabaseQueue()
        try DatabaseService.applyMigrations(to: q)
        try q.read { db in
            let cols = try db.columns(in: "matter").map(\.name)
            XCTAssertTrue(cols.contains("requestor_associate_id"))
            for i in 1...5 {
                XCTAssertTrue(cols.contains("interested_party\(i)_associate_id"),
                              "Missing interested_party\(i)_associate_id")
                XCTAssertTrue(cols.contains("external_interested_party\(i)"),
                              "Missing external_interested_party\(i)")
            }
        }
    }

    func testMigrationIsIdempotent() throws {
        let q = try DatabaseQueue()
        try DatabaseService.applyMigrations(to: q)
        try DatabaseService.applyMigrations(to: q)  // second call must be a no-op
        try q.read { db in
            XCTAssertTrue(try db.tableExists("matter"))
        }
    }
}

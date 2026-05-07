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
                          "matter","time_entry","note","attachment"] {
                XCTAssertTrue(try db.tableExists(table), "Missing table: \(table)")
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

import XCTest
import GRDB
@testable import PurpleTracker

@MainActor
final class MatterIDServiceTests: XCTestCase {

    private func newQueue() throws -> DatabaseQueue {
        let q = try DatabaseQueue()
        try DatabaseService.applyMigrations(to: q)
        // Seed a single type so the FK on `matter` is satisfiable.
        try q.write { db in
            try db.execute(sql: """
                INSERT INTO matter_type (id, name, color_hex, sort_order, is_cadenced)
                VALUES ('t', 'Test', '#000000', 0, 0)
                """)
        }
        return q
    }

    func testFormatPadsToFiveDigits() {
        let id = MatterIDService.format(date: Date(timeIntervalSince1970: 0), sequence: 7)
        XCTAssertTrue(id.hasSuffix("-00007"), "Expected 5-digit zero-padded suffix, got \(id)")
    }

    func testSequentialAllocationsIncrement() throws {
        let q = try newQueue()
        let date = isoDate("2026-05-07")
        var ids: [String] = []
        for i in 0..<5 {
            let id = try MatterIDService.allocateAndInsert(on: date, in: q) { db, mid in
                try db.execute(sql: """
                    INSERT INTO matter (id, title, type_id, status, description_md,
                        created_at, accessed_at, modified_at,
                        external1_number, external1_url, external2_number, external2_url,
                        external3_number, external3_url, time_tracking_code,
                        resolution_md, lessons_md, notes_md,
                        file_store_primary, file_store_secondary)
                    VALUES (?, ?, 't', 'New', '', ?, ?, ?, '', '', '', '', '', '', '', '', '', '', '', '')
                    """, arguments: [mid, "M\(i)", Date(), Date(), Date()])
            }
            ids.append(id)
        }
        XCTAssertEqual(ids, [
            "2026-05-07-00001",
            "2026-05-07-00002",
            "2026-05-07-00003",
            "2026-05-07-00004",
            "2026-05-07-00005",
        ])
    }

    func testCounterResetsPerDay() throws {
        let q = try newQueue()
        let day1 = isoDate("2026-05-07")
        let day2 = isoDate("2026-05-08")
        let id1 = try MatterIDService.allocateAndInsert(on: day1, in: q) { db, mid in
            try insertEmptyMatter(db: db, id: mid)
        }
        let id2 = try MatterIDService.allocateAndInsert(on: day2, in: q) { db, mid in
            try insertEmptyMatter(db: db, id: mid)
        }
        XCTAssertEqual(id1, "2026-05-07-00001")
        XCTAssertEqual(id2, "2026-05-08-00001")
    }

    func testRollbackReleasesSequence() throws {
        let q = try newQueue()
        let date = isoDate("2026-05-07")

        struct Boom: Error {}
        do {
            _ = try MatterIDService.allocateAndInsert(on: date, in: q) { _, _ in
                throw Boom()
            }
            XCTFail("should have thrown")
        } catch is Boom { /* expected */ }

        // Next allocation should still be -00001 because the failed one's
        // counter increment was rolled back.
        let id = try MatterIDService.allocateAndInsert(on: date, in: q) { db, mid in
            try insertEmptyMatter(db: db, id: mid)
        }
        XCTAssertEqual(id, "2026-05-07-00001")
    }

    private func insertEmptyMatter(db: Database, id: String) throws {
        try db.execute(sql: """
            INSERT INTO matter (id, title, type_id, status, description_md,
                created_at, accessed_at, modified_at,
                external1_number, external1_url, external2_number, external2_url,
                external3_number, external3_url, time_tracking_code,
                resolution_md, lessons_md, notes_md,
                file_store_primary, file_store_secondary)
            VALUES (?, '', 't', 'New', '', ?, ?, ?, '', '', '', '', '', '', '', '', '', '', '', '')
            """, arguments: [id, Date(), Date(), Date()])
    }

    private func isoDate(_ s: String) -> Date {
        MatterIDService.dateFormatter.date(from: s)!
    }
}

import XCTest
@testable import PurpleLife

/// Phase 5 — WeightTracker CSV import. Exercises the row parser, the
/// kg→lb conversion, and a few resilience cases (quoted fields with
/// commas, missing notes, unparseable rows).
final class WeightCSVImporterTests: XCTestCase {

    @MainActor
    private func wipeWeight() throws {
        try DatabaseService.shared.dbPool.write { db in
            try db.execute(sql: "DELETE FROM objects_fts WHERE type_id = 'Weight'")
            try db.execute(sql: "DELETE FROM objects WHERE type_id = 'Weight'")
        }
        ObjectEngine.currentSchema = SchemaRegistry(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("schema-csv-\(UUID().uuidString).json")
        )
    }

    private func writeTempCSV(_ text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wt-\(UUID().uuidString).csv")
        try text.data(using: .utf8)!.write(to: url, options: .atomic)
        return url
    }

    @MainActor
    func testImportsPoundsAsIs() throws {
        try wipeWeight()
        let csv = """
        Date,Weight (lb),Notes
        "2026-05-01 12:00:00 +0000",180.5,"baseline"
        "2026-05-02 12:00:00 +0000",179.8,"day 2"
        """
        let url = try writeTempCSV(csv)
        let report = try WeightCSVImporter.importCSV(from: url)
        XCTAssertEqual(report.imported, 2)
        XCTAssertEqual(report.skipped, 0)

        let weights = try ObjectEngine.fetch(typeId: "Weight")
        XCTAssertEqual(weights.count, 2)
        let pounds = weights.compactMap { $0.fields()["pounds"] as? Double }.sorted()
        XCTAssertEqual(pounds, [179.8, 180.5])
    }

    @MainActor
    func testConvertsKilogramsToPounds() throws {
        try wipeWeight()
        let csv = """
        Date,Weight (kg),Notes
        "2026-05-01",80.0,"baseline"
        """
        let url = try writeTempCSV(csv)
        let report = try WeightCSVImporter.importCSV(from: url)
        XCTAssertEqual(report.imported, 1)

        let weights = try ObjectEngine.fetch(typeId: "Weight")
        XCTAssertEqual(weights.count, 1)
        let pounds = (weights[0].fields()["pounds"] as? Double) ?? 0
        // 80 kg × 2.2046 ≈ 176.37 lb
        XCTAssertEqual(pounds, 80.0 * 2.2046226218, accuracy: 0.0001)
    }

    @MainActor
    func testRowParserHandlesEmbeddedCommasAndQuotes() {
        // Notes contains both a comma and a doubled-quote escape.
        let row = #""2026-05-01",180.0,"hello, ""world"""#
        let cells = WeightCSVImporter.parseCSVRow(row)
        XCTAssertEqual(cells.count, 3)
        XCTAssertEqual(cells[0], "2026-05-01")
        XCTAssertEqual(cells[1], "180.0")
        XCTAssertEqual(cells[2], "hello, \"world\"")
    }

    @MainActor
    func testSkipsUnparseableRowsButContinues() throws {
        try wipeWeight()
        let csv = """
        Date,Weight (lb),Notes
        bad-date,180,"nope"
        "2026-05-01",notanumber,"also nope"
        "2026-05-02",181.0,"good"
        """
        let url = try writeTempCSV(csv)
        let report = try WeightCSVImporter.importCSV(from: url)
        XCTAssertEqual(report.imported, 1)
        XCTAssertEqual(report.skipped, 2)
        XCTAssertEqual(report.errors.count, 2)
    }

    @MainActor
    func testMissingNotesColumnIsOk() throws {
        try wipeWeight()
        let csv = """
        Date,Weight (lb)
        "2026-05-01",180.0
        """
        let url = try writeTempCSV(csv)
        let report = try WeightCSVImporter.importCSV(from: url)
        XCTAssertEqual(report.imported, 1)
    }
}

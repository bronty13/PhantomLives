import XCTest
@testable import PurpleLife

/// `RecordsChartBody.extractPoints` is the pure-data half of the
/// charts view kind. Tests cover the same-day dedup (last-write-wins
/// per calendar day) and the field-extraction defensive paths.
///
/// SwiftUI rendering of the chart isn't unit-testable without a UI
/// host; covered visually during the slice 2 build verification.
final class RecordsChartBodyTests: XCTestCase {

    private func record(
        id: String,
        date: String,
        pounds: Double,
        updatedAt: String
    ) -> ObjectRecord {
        ObjectRecord(
            id: id,
            typeId: "Weight",
            parentId: nil,
            fieldsJSON: "{\"date\":\"\(date)\",\"pounds\":\(pounds)}",
            createdAt: updatedAt,
            updatedAt: updatedAt
        )
    }

    func testEmptyInputProducesEmptyPoints() {
        let out = RecordsChartBody.extractPoints(rows: [], dateKey: "date", valueKey: "pounds")
        XCTAssertTrue(out.isEmpty)
    }

    func testSortsByDateAscending() {
        let rows = [
            record(id: "a", date: "2026-05-03", pounds: 180, updatedAt: "2026-05-03T08:00:00Z"),
            record(id: "b", date: "2026-05-01", pounds: 182, updatedAt: "2026-05-01T08:00:00Z"),
            record(id: "c", date: "2026-05-02", pounds: 181, updatedAt: "2026-05-02T08:00:00Z"),
        ]
        let out = RecordsChartBody.extractPoints(rows: rows, dateKey: "date", valueKey: "pounds")
        XCTAssertEqual(out.count, 3)
        XCTAssertTrue(out[0].date < out[1].date)
        XCTAssertTrue(out[1].date < out[2].date)
        XCTAssertEqual(out[0].value, 182)
        XCTAssertEqual(out[1].value, 181)
        XCTAssertEqual(out[2].value, 180)
    }

    func testDedupesSameDayKeepingMostRecentUpdatedAt() {
        // Two records on 2026-05-01 — second update should win.
        let rows = [
            record(id: "morning", date: "2026-05-01", pounds: 182,
                   updatedAt: "2026-05-01T07:00:00Z"),
            record(id: "evening", date: "2026-05-01", pounds: 181,
                   updatedAt: "2026-05-01T19:00:00Z"),
        ]
        let out = RecordsChartBody.extractPoints(rows: rows, dateKey: "date", valueKey: "pounds")
        XCTAssertEqual(out.count, 1, "same-day records should dedupe to one point")
        XCTAssertEqual(out.first?.value, 181, "most-recently-updated record wins")
    }

    func testRecordsMissingDateOrValueAreSkipped() {
        let valid = record(id: "v", date: "2026-05-01", pounds: 180,
                           updatedAt: "2026-05-01T08:00:00Z")
        let noDate = ObjectRecord(
            id: "no-date", typeId: "Weight", parentId: nil,
            fieldsJSON: "{\"pounds\":175}",
            createdAt: "2026-05-01T08:00:00Z", updatedAt: "2026-05-01T08:00:00Z"
        )
        let noValue = ObjectRecord(
            id: "no-value", typeId: "Weight", parentId: nil,
            fieldsJSON: "{\"date\":\"2026-05-02\"}",
            createdAt: "2026-05-02T08:00:00Z", updatedAt: "2026-05-02T08:00:00Z"
        )
        let out = RecordsChartBody.extractPoints(
            rows: [valid, noDate, noValue],
            dateKey: "date", valueKey: "pounds"
        )
        XCTAssertEqual(out.count, 1, "rows missing either field should be silently dropped")
        XCTAssertEqual(out.first?.value, 180)
    }

    func testEmptyKeysProduceEmptyPoints() {
        let rows = [record(id: "a", date: "2026-05-01", pounds: 180,
                           updatedAt: "2026-05-01T08:00:00Z")]
        XCTAssertTrue(RecordsChartBody.extractPoints(rows: rows, dateKey: "", valueKey: "pounds").isEmpty)
        XCTAssertTrue(RecordsChartBody.extractPoints(rows: rows, dateKey: "date", valueKey: "").isEmpty)
    }
}

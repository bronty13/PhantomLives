import XCTest
@testable import PurpleAtticCore

/// Tests for the typed run metrics: restic-detail parsing, byte-size parsing, and the
/// `RunSummary → RunRecord` builder.
final class RunMetricsTests: XCTestCase {

    func testApplyCloudDetailParsesRealResticString() {
        var m = RunMetrics()
        m.applyCloudDetail("8 new, 2 changed, 364584 unmodified; +906.389 MiB (139.773 MiB stored); snapshot b1fd0247; check OK")
        XCTAssertEqual(m.cloudNew, 8)
        XCTAssertEqual(m.cloudChanged, 2)
        XCTAssertEqual(m.cloudUnmodified, 364584)
        XCTAssertEqual(m.cloudSnapshot, "b1fd0247")
        XCTAssertEqual(m.cloudCheckOK, true)
        // Prefers the deduped "stored" size (139.773 MiB), not the logical 906.389 MiB.
        let expected = Int64(139.773 * 1024 * 1024)
        XCTAssertEqual(m.cloudBytesAdded, expected)
    }

    func testApplyCloudDetailWithoutCheck() {
        var m = RunMetrics()
        m.applyCloudDetail("0 new, 0 changed, 100 unmodified; snapshot abc123")
        XCTAssertEqual(m.cloudNew, 0)
        XCTAssertEqual(m.cloudUnmodified, 100)
        XCTAssertEqual(m.cloudSnapshot, "abc123")
        XCTAssertNil(m.cloudCheckOK)
    }

    func testParseByteSizeUnits() {
        XCTAssertEqual(RunMetrics.parseByteSize(in: "+2.0 GiB added", preferringStored: false),
                       Int64(2.0 * 1024 * 1024 * 1024))
        XCTAssertEqual(RunMetrics.parseByteSize(in: "1.5 MB total", preferringStored: false),
                       Int64(1.5 * 1_000_000))
        XCTAssertNil(RunMetrics.parseByteSize(in: "no size here", preferringStored: false))
    }

    func testParseByteSizePrefersStoredParenthetical() {
        let n = RunMetrics.parseByteSize(in: "+906.389 MiB (139.773 MiB stored)", preferringStored: true)
        XCTAssertEqual(n, Int64(139.773 * 1024 * 1024))
    }

    func testMakeRunRecordFromSummary() {
        var metrics = RunMetrics()
        metrics.primaryFileCount = 1234
        metrics.verifyDiscrepancies = 0
        metrics.cloudSnapshot = "deadbeef"
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let summary = ExportEngine.RunSummary(
            profileName: "Main", startedAt: start, finishedAt: start.addingTimeInterval(120),
            steps: [.init(name: "Export HEIC originals", success: true, detail: "exit 0", duration: 100)],
            logFile: "/tmp/x.log", metadataEmbedSkips: ["a.heic"], reviewStagedCount: 7,
            reviewPath: "/tmp/review", metrics: metrics)
        let rec = summary.makeRunRecord(trigger: "scheduled")
        // id is the start time as yyyyMMdd-HHmmss (local-zone, so assert the shape, not the value).
        XCTAssertNotNil(rec.id.range(of: #"^\d{8}-\d{6}$"#, options: .regularExpression))
        XCTAssertEqual(rec.profileName, "Main")
        XCTAssertEqual(rec.trigger, "scheduled")
        XCTAssertEqual(rec.allSucceeded, true)
        XCTAssertEqual(rec.newItemsArchived, 7)
        XCTAssertEqual(rec.metadataEmbedSkips, 1)
        XCTAssertEqual(rec.metrics.primaryFileCount, 1234)
        XCTAssertEqual(rec.steps.count, 1)
        XCTAssertEqual(rec.steps.first?.name, "Export HEIC originals")
        XCTAssertEqual(rec.durationSec, 120, accuracy: 0.001)
    }
}

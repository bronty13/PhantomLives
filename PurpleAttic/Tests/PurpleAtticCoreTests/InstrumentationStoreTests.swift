import XCTest
@testable import PurpleAtticCore

/// Tests for the structured run-history + purge-audit stores (the new dashboard instrumentation):
/// JSONL append/load round-trips, malformed-line resilience, and sort order.
final class InstrumentationStoreTests: XCTestCase {

    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("attic-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    // MARK: AtticJSON

    func testAppendAndLoadLinesRoundTrip() {
        struct Row: Codable, Equatable { var n: Int; var name: String; var when: Date }
        let url = tmpDir.appendingPathComponent("rows.jsonl")
        let a = Row(n: 1, name: "one", when: Date(timeIntervalSince1970: 1_700_000_000))
        let b = Row(n: 2, name: "two/slash", when: Date(timeIntervalSince1970: 1_700_086_400))
        XCTAssertTrue(AtticJSON.appendLine(a, to: url))
        XCTAssertTrue(AtticJSON.appendLine(b, to: url))
        let loaded = AtticJSON.loadLines(Row.self, from: url)
        XCTAssertEqual(loaded, [a, b])
    }

    func testLoadLinesSkipsMalformedTail() throws {
        struct Row: Codable, Equatable { var n: Int }
        let url = tmpDir.appendingPathComponent("rows.jsonl")
        AtticJSON.appendLine(Row(n: 1), to: url)
        AtticJSON.appendLine(Row(n: 2), to: url)
        // Simulate a crash that left a half-written final line.
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{ this is not json".utf8))
        try handle.close()
        let loaded = AtticJSON.loadLines(Row.self, from: url)
        XCTAssertEqual(loaded.map { $0.n }, [1, 2])  // good lines survive; bad tail dropped
    }

    func testLoadLinesMissingFileReturnsEmpty() {
        struct Row: Codable { var n: Int }
        let url = tmpDir.appendingPathComponent("does-not-exist.jsonl")
        XCTAssertTrue(AtticJSON.loadLines(Row.self, from: url).isEmpty)
    }

    // MARK: RunHistoryStore

    func testRunHistoryAppendLoadSorted() {
        let url = tmpDir.appendingPathComponent("run-history.jsonl")
        let older = makeRun(id: "a", start: Date(timeIntervalSince1970: 1_000), ok: true)
        let newer = makeRun(id: "b", start: Date(timeIntervalSince1970: 2_000), ok: false)
        // Append out of order; load must return oldest-first.
        RunHistoryStore.append(newer, to: url)
        RunHistoryStore.append(older, to: url)
        let loaded = RunHistoryStore.load(from: url)
        XCTAssertEqual(loaded.map { $0.id }, ["a", "b"])
        XCTAssertEqual(loaded.last?.allSucceeded, false)
    }

    // MARK: PurgeAuditStore

    func testPurgeAuditAppendLoadSorted() {
        let url = tmpDir.appendingPathComponent("purge-audit.jsonl")
        let r1 = PurgeAuditRecord(timestamp: Date(timeIntervalSince1970: 5_000), trigger: .manual,
                                  action: .stage, requested: 10, resolved: 10, succeeded: 10,
                                  failed: 0, bytes: 1024, album: "X")
        let r2 = PurgeAuditRecord(timestamp: Date(timeIntervalSince1970: 9_000), trigger: .auto,
                                  action: .delete, requested: 5, resolved: 5, succeeded: 4, failed: 1, bytes: 2048)
        PurgeAuditStore.append(r2, to: url)
        PurgeAuditStore.append(r1, to: url)
        let loaded = PurgeAuditStore.load(from: url)
        XCTAssertEqual(loaded.map { $0.timestamp.timeIntervalSince1970 }, [5_000, 9_000])
        XCTAssertEqual(loaded.first?.action, .stage)
        XCTAssertEqual(loaded.last?.trigger, .auto)
    }

    func testPurgeAuditIdEncodesActionAndStamp() {
        let r = PurgeAuditRecord(timestamp: Date(timeIntervalSince1970: 1_700_000_000), trigger: .auto,
                                 action: .delete, requested: 1, resolved: 1, succeeded: 1, failed: 0, bytes: 0)
        XCTAssertTrue(r.id.hasSuffix("-delete"))
    }

    // MARK: Helpers

    private func makeRun(id: String, start: Date, ok: Bool) -> RunRecord {
        RunRecord(id: id, profileName: "Test", startedAt: start, finishedAt: start.addingTimeInterval(60),
                  durationSec: 60, allSucceeded: ok, trigger: "manual", steps: [],
                  metrics: RunMetrics(), newItemsArchived: 0, metadataEmbedSkips: 0, logFile: nil)
    }
}

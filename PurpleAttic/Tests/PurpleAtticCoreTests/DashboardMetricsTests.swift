import XCTest
@testable import PurpleAtticCore

/// Tests for the pure dashboard roll-ups: the summary numbers and the chart time-series.
final class DashboardMetricsTests: XCTestCase {

    private func run(id: String, dayOffset: Int, ok: Bool, files: Int = 0, newItems: Int = 0,
                     discrepancies: Int = 0, snapshot: String? = nil, checkOK: Bool? = nil,
                     cloudBytes: Int64 = 0, mirrorsVerified: Int = 1) -> RunRecord {
        var m = RunMetrics()
        m.primaryFileCount = files
        m.verifyDiscrepancies = discrepancies
        m.cloudSnapshot = snapshot
        m.cloudCheckOK = checkOK
        m.cloudBytesAdded = cloudBytes
        m.mirrorsVerified = mirrorsVerified
        let start = Date(timeIntervalSince1970: 1_700_000_000 + Double(dayOffset) * 86_400)
        return RunRecord(id: id, profileName: "Main", startedAt: start, finishedAt: start.addingTimeInterval(60),
                         durationSec: 60, allSucceeded: ok, trigger: "scheduled", steps: [],
                         metrics: m, newItemsArchived: newItems, metadataEmbedSkips: 0, logFile: nil)
    }

    private func audit(dayOffset: Int, action: PurgeAuditRecord.Action, succeeded: Int,
                       bytes: Int64 = 0) -> PurgeAuditRecord {
        PurgeAuditRecord(timestamp: Date(timeIntervalSince1970: 1_700_000_000 + Double(dayOffset) * 86_400),
                         trigger: .auto, action: action, requested: succeeded, resolved: succeeded,
                         succeeded: succeeded, failed: 0, bytes: bytes)
    }

    func testSummaryRollsUpRunsAuditsManifest() {
        let runs = [
            run(id: "r1", dayOffset: 0, ok: true, files: 1000, newItems: 5, snapshot: "s1", checkOK: true, cloudBytes: 1_000),
            run(id: "r2", dayOffset: 1, ok: false, files: 1010, newItems: 3, discrepancies: 2, cloudBytes: 500),
            run(id: "r3", dayOffset: 2, ok: true, files: 1020, newItems: 4, snapshot: "s3", checkOK: true, cloudBytes: 2_000),
        ]
        let audits = [
            audit(dayOffset: 0, action: .stage, succeeded: 10),
            audit(dayOffset: 2, action: .delete, succeeded: 8, bytes: 4096),
        ]
        let plan = PurgePlan(cutoff: Date(), recordsConsidered: 50, candidates: [])
        var manifest = PurgeManifest(from: plan, profileName: "Main", keepWindowDays: 365, computedAt: Date())
        manifest.verifiedCount = 12
        manifest.verifiedBytes = 9999
        manifest.unverifiedCount = 3

        let s = DashboardMetrics.summarize(runs: runs, audits: audits, manifest: manifest)
        XCTAssertEqual(s.runsTotal, 3)
        XCTAssertEqual(s.runsOK, 2)
        XCTAssertEqual(s.lastRunOK, true)            // r3 is newest and OK
        XCTAssertEqual(s.lastVerifiedFileCount, 1020)
        XCTAssertEqual(s.lastDiscrepancies, 0)       // r3 had none
        XCTAssertEqual(s.totalNewArchived, 12)       // 5+3+4
        XCTAssertEqual(s.totalStaged, 10)
        XCTAssertEqual(s.totalDeleted, 8)
        XCTAssertEqual(s.bytesReclaimed, 4096)       // only delete actions count
        XCTAssertEqual(s.lastSnapshot, "s3")         // newest run with a snapshot
        XCTAssertEqual(s.lastCloudCheckOK, true)
        XCTAssertEqual(s.totalCloudBytesAdded, 3_500)
        XCTAssertEqual(s.readyToPurge, 12)
        XCTAssertEqual(s.readyBytes, 9999)
        XCTAssertEqual(s.readyUnverified, 3)
    }

    func testLastCleanVerifyIgnoresRunsWithDiscrepancies() {
        let runs = [
            run(id: "r1", dayOffset: 0, ok: true, discrepancies: 0),
            run(id: "r2", dayOffset: 1, ok: false, discrepancies: 5),  // newest but dirty
        ]
        let s = DashboardMetrics.summarize(runs: runs, audits: [], manifest: nil)
        XCTAssertEqual(s.lastCleanVerifyAt, runs[0].startedAt)  // the clean one, not the newer dirty one
    }

    func testCumulativePurgedSeriesAccumulates() {
        let audits = [
            audit(dayOffset: 0, action: .stage, succeeded: 3),
            audit(dayOffset: 1, action: .stage, succeeded: 2),
            audit(dayOffset: 2, action: .delete, succeeded: 5),
        ]
        let series = DashboardMetrics.cumulativePurgedSeries(audits)
        XCTAssertEqual(series.map { $0.value }, [3, 5, 10])
    }

    func testNewItemsSeriesOrderedOldestFirst() {
        let runs = [
            run(id: "b", dayOffset: 2, ok: true, newItems: 9),
            run(id: "a", dayOffset: 0, ok: true, newItems: 1),
        ]
        let series = DashboardMetrics.newItemsSeries(runs)
        XCTAssertEqual(series.map { $0.value }, [1, 9])  // sorted by date ascending
    }

    func testEmptyInputsProduceZeroSummary() {
        let s = DashboardMetrics.summarize(runs: [], audits: [], manifest: nil)
        XCTAssertEqual(s.runsTotal, 0)
        XCTAssertNil(s.lastRunAt)
        XCTAssertEqual(s.readyToPurge, 0)
        XCTAssertNil(s.lastSnapshot)
    }
}

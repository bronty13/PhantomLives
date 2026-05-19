import XCTest
@testable import PurpleReel

/// Coverage for the C34 (E3) workflow-chain run resumption
/// persistence. The service writes/reads `Snapshot` JSON to a
/// per-user dir; tests use a temp `directoryOverride` so the host
/// machine's real Application Support stays untouched.
@MainActor
final class ActiveRunPersistenceTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("purplereel-active-runs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true
        )
        ActiveRunPersistence.directoryOverride = tempDir
    }

    override func tearDownWithError() throws {
        ActiveRunPersistence.directoryOverride = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func sampleSnapshot(
        completed: [Int] = []
    ) -> ActiveRunPersistence.Snapshot {
        let chain = WorkflowChain(
            name: "Test chain",
            steps: [.transcode(.defaults), .exportReport(.defaults)],
            continueOnFailure: false
        )
        return ActiveRunPersistence.Snapshot(
            id: UUID(),
            chain: chain,
            sourcePath: "/tmp/source",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastUpdatedAt: Date(timeIntervalSince1970: 1_700_000_500),
            completedStepIndices: completed
        )
    }

    // MARK: - Save / load round-trip

    func testSaveAndLoadAllReturnsTheSnapshot() {
        let snap = sampleSnapshot(completed: [0])
        ActiveRunPersistence.save(snap)
        let all = ActiveRunPersistence.loadAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.id, snap.id)
        XCTAssertEqual(all.first?.chain.name, "Test chain")
        XCTAssertEqual(all.first?.completedStepIndices, [0])
        XCTAssertEqual(all.first?.sourcePath, "/tmp/source")
    }

    func testEmptyDirectoryReturnsNoSnapshots() {
        XCTAssertTrue(ActiveRunPersistence.loadAll().isEmpty)
    }

    func testSaveSameIDOverwritesRatherThanDuplicates() {
        var snap = sampleSnapshot(completed: [])
        ActiveRunPersistence.save(snap)
        snap.completedStepIndices = [0, 1]
        ActiveRunPersistence.save(snap)
        let all = ActiveRunPersistence.loadAll()
        XCTAssertEqual(all.count, 1, "Same id should overwrite, not duplicate")
        XCTAssertEqual(all.first?.completedStepIndices, [0, 1])
    }

    // MARK: - Delete

    func testDeleteRemovesTheSnapshotFile() {
        let snap = sampleSnapshot()
        ActiveRunPersistence.save(snap)
        XCTAssertEqual(ActiveRunPersistence.loadAll().count, 1)
        ActiveRunPersistence.delete(snap.id)
        XCTAssertTrue(ActiveRunPersistence.loadAll().isEmpty)
    }

    func testDeleteUnknownIDIsNoOp() {
        // Should not throw / log; the runner calls delete() on
        // every clean exit, sometimes when no snapshot was ever
        // saved (e.g. a chain that finished its first step before
        // the initial save() landed — unlikely but possible).
        ActiveRunPersistence.delete(UUID())
        XCTAssertTrue(ActiveRunPersistence.loadAll().isEmpty)
    }

    // MARK: - clearAll

    func testClearAllWipesEveryFile() {
        ActiveRunPersistence.save(sampleSnapshot())
        ActiveRunPersistence.save(sampleSnapshot())
        ActiveRunPersistence.save(sampleSnapshot())
        XCTAssertEqual(ActiveRunPersistence.loadAll().count, 3)
        ActiveRunPersistence.clearAll()
        XCTAssertTrue(ActiveRunPersistence.loadAll().isEmpty)
    }

    // MARK: - Sort order

    /// `loadAll` returns newest-first so the launch prompt
    /// surfaces the most-recently-active run as the first
    /// resume candidate.
    func testLoadAllSortsByLastUpdatedNewestFirst() {
        let older = ActiveRunPersistence.Snapshot(
            id: UUID(), chain: sampleSnapshot().chain,
            sourcePath: "/tmp/older",
            startedAt: Date(timeIntervalSince1970: 1_000),
            lastUpdatedAt: Date(timeIntervalSince1970: 1_000),
            completedStepIndices: []
        )
        let newer = ActiveRunPersistence.Snapshot(
            id: UUID(), chain: sampleSnapshot().chain,
            sourcePath: "/tmp/newer",
            startedAt: Date(timeIntervalSince1970: 2_000),
            lastUpdatedAt: Date(timeIntervalSince1970: 2_000),
            completedStepIndices: []
        )
        ActiveRunPersistence.save(older)
        ActiveRunPersistence.save(newer)
        let all = ActiveRunPersistence.loadAll()
        XCTAssertEqual(all.first?.sourcePath, "/tmp/newer",
            "loadAll should return newest first")
    }

    // MARK: - Resume reconstruction

    /// Round-trip through `WorkflowChainRun(resumingFrom:)` —
    /// pre-completed indices land as `.finished` step states with
    /// the resumed-from-prior-session detail message.
    func testResumeMarksCompletedStepsAsFinished() {
        var snap = sampleSnapshot()
        snap.completedStepIndices = [0]
        let run = WorkflowChainRun(resumingFrom: snap)
        XCTAssertTrue(run.isResumed)
        if case .finished = run.steps[0].status {
            // expected
        } else {
            XCTFail("Step 0 should be pre-marked as finished from snapshot")
        }
        XCTAssertEqual(run.steps[0].progress, 1)
        if case .queued = run.steps[1].status {
            // expected — step 1 wasn't in completedStepIndices.
        } else {
            XCTFail("Step 1 should remain queued (not in completedStepIndices)")
        }
    }
}

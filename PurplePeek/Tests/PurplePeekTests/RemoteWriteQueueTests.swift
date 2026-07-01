import XCTest
@testable import PurplePeek

/// The offline write queue: coalescing, ordering, persistence, and retryable-vs-permanent
/// failure handling. `autoRetry: false` disables the path monitor + backoff so tests drive
/// `drainNow()` deterministically.
@MainActor
final class RemoteWriteQueueTests: XCTestCase {
    private var storeURL: URL!

    override func setUp() {
        super.setUp()
        storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pp-queue-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("queue.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: storeURL.deletingLastPathComponent())
        super.tearDown()
    }

    private func retryableError() -> Error { URLError(.cannotConnectToHost) }

    // MARK: Coalescing & ordering

    func testCoalescingKeepsNewestValuePerFileAndField() async {
        // Sender always "offline" so entries accumulate for inspection.
        let q = RemoteWriteQueue(storeURL: storeURL, autoRetry: false) { _ in throw self.retryableError() }
        q.submit(.keep(fileId: "a", fileName: "a.jpg", value: 1))
        q.submit(.keep(fileId: "a", fileName: "a.jpg", value: 0))     // supersedes keep=1
        q.submit(.title(fileId: "a", fileName: "a.jpg", value: "T"))  // different field: kept
        q.submit(.keep(fileId: "b", fileName: "b.jpg", value: 1))     // different file: kept
        await q.drainNow()
        XCTAssertEqual(q.pending.count, 3)
        let keepA = q.pending.first { $0.fileId == "a" && $0.kind == .keep }
        XCTAssertEqual(keepA?.intValue, 0)                            // newest value won
    }

    func testDrainSendsInSubmissionOrderAndEmpties() async {
        var sent: [PendingWrite] = []
        let q = RemoteWriteQueue(storeURL: storeURL, autoRetry: false) { sent.append($0) }
        q.submit(.keep(fileId: "a", fileName: "a.jpg", value: 1))
        q.submit(.favorite(fileId: "a", fileName: "a.jpg", value: true))
        q.submit(.keep(fileId: "b", fileName: "b.jpg", value: 0))
        await q.drainNow()
        XCTAssertEqual(sent.map(\.kind), [.keep, .favorite, .keep])
        XCTAssertEqual(sent.map(\.fileId), ["a", "a", "b"])
        XCTAssertTrue(q.pending.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path))  // empty queue → store removed
    }

    // MARK: Failure handling

    func testRetryableFailureKeepsWriteQueued() async {
        var counts = [Int]()
        let q = RemoteWriteQueue(storeURL: storeURL, autoRetry: false) { _ in throw self.retryableError() }
        q.onCountChange = { counts.append($0) }
        q.submit(.keep(fileId: "a", fileName: "a.jpg", value: 1))
        await q.drainNow()
        XCTAssertEqual(q.pending.count, 1)                            // still queued, not dropped
    }

    func testPermanentFailureDropsWriteAndSurfacesIt() async {
        var failed: [PendingWrite] = []
        let q = RemoteWriteQueue(storeURL: storeURL, autoRetry: false) { _ in throw PeekServerError.notFound }
        q.onPermanentFailure = { write, _ in failed.append(write) }
        q.submit(.keep(fileId: "gone", fileName: "gone.jpg", value: 1))
        q.submit(.keep(fileId: "also-gone", fileName: "g2.jpg", value: 0))
        await q.drainNow()
        XCTAssertTrue(q.pending.isEmpty)                              // queue never wedges behind unsendables
        XCTAssertEqual(failed.map(\.fileId), ["gone", "also-gone"])
    }

    func testRecoveryAfterOutage() async {
        // First drain fails (offline); flipping the flag simulates connectivity returning.
        var online = false
        var sent: [PendingWrite] = []
        let q = RemoteWriteQueue(storeURL: storeURL, autoRetry: false) { write in
            guard online else { throw self.retryableError() }
            sent.append(write)
        }
        q.submit(.caption(fileId: "a", fileName: "a.jpg", value: "hello"))
        await q.drainNow()
        XCTAssertEqual(q.pending.count, 1)
        online = true
        await q.drainNow()
        XCTAssertTrue(q.pending.isEmpty)
        XCTAssertEqual(sent.first?.stringValue, "hello")
    }

    // MARK: Persistence

    func testPendingWritesSurviveRelaunch() async {
        let q1 = RemoteWriteQueue(storeURL: storeURL, autoRetry: false) { _ in throw self.retryableError() }
        q1.submit(.keep(fileId: "a", fileName: "a.jpg", value: 1))
        q1.submit(.keywords(fileId: "a", fileName: "a.jpg", names: ["x", "y"]))
        await q1.drainNow()

        // "Relaunch": a fresh queue over the same store, now with a working sender.
        var sent: [PendingWrite] = []
        let q2 = RemoteWriteQueue(storeURL: storeURL, autoRetry: false) { sent.append($0) }
        XCTAssertEqual(q2.pending.count, 2)                           // restored from disk
        await q2.drainNow()
        XCTAssertTrue(q2.pending.isEmpty)
        XCTAssertEqual(sent.map(\.kind), [.keep, .keywords])
        XCTAssertEqual(sent.last?.listValue, ["x", "y"])
    }

    func testNilValuesRoundTrip() async {
        // keep=nil (undecide) and title=nil (clear) are legitimate values — persistence must
        // not confuse them with "absent".
        let q1 = RemoteWriteQueue(storeURL: storeURL, autoRetry: false) { _ in throw self.retryableError() }
        q1.submit(.keep(fileId: "a", fileName: "a.jpg", value: nil))
        q1.submit(.title(fileId: "a", fileName: "a.jpg", value: nil))
        await q1.drainNow()
        let q2 = RemoteWriteQueue(storeURL: storeURL, autoRetry: false) { _ in }
        XCTAssertEqual(q2.pending.count, 2)
        XCTAssertEqual(q2.pending[0].kind, .keep)
        XCTAssertNil(q2.pending[0].intValue)
        XCTAssertEqual(q2.pending[1].kind, .title)
        XCTAssertNil(q2.pending[1].stringValue)
    }

    // MARK: Error classification

    func testRetryableClassification() {
        XCTAssertTrue(RemoteWriteQueue.isRetryable(URLError(.notConnectedToInternet)))
        XCTAssertTrue(RemoteWriteQueue.isRetryable(URLError(.timedOut)))
        XCTAssertTrue(RemoteWriteQueue.isRetryable(URLError(.cannotConnectToHost)))
        XCTAssertTrue(RemoteWriteQueue.isRetryable(PeekServerError.badResponse(503)))
        XCTAssertFalse(RemoteWriteQueue.isRetryable(URLError(.cancelled)))
        XCTAssertFalse(RemoteWriteQueue.isRetryable(PeekServerError.badResponse(400)))
        XCTAssertFalse(RemoteWriteQueue.isRetryable(PeekServerError.notFound))
        XCTAssertFalse(RemoteWriteQueue.isRetryable(PeekServerError.decoding("x")))
    }

    func testStoreURLIsPerAccount() {
        let a = RemoteWriteQueue.storeURL(account: "peek@10.0.0.59:8788")
        let b = RemoteWriteQueue.storeURL(account: "peek@other-host:8788")
        XCTAssertNotEqual(a, b)
        XCTAssertTrue(a.lastPathComponent.hasPrefix("pending-writes-"))
    }
}

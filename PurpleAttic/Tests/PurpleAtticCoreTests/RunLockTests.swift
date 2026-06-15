import XCTest
@testable import PurpleAtticCore

/// The single-writer lock is what keeps a manual run, the hourly run, and the drive-connect-
/// triggered run from overlapping — the collision that wedged the old Cryptomator vault. These
/// assert mutual exclusion and that releasing frees the lock for the next run.
final class RunLockTests: XCTestCase {

    private func tempLockURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("attic-runlock-\(UUID().uuidString).lock")
    }

    func testSecondAcquireFailsWhileHeld() throws {
        let url = tempLockURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let first = try XCTUnwrap(RunLock.tryAcquire(at: url), "first acquire should succeed")
        XCTAssertNil(RunLock.tryAcquire(at: url), "a second run must NOT be able to take the held lock")
        first.release()
    }

    func testLockIsReusableAfterRelease() throws {
        let url = tempLockURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let first = try XCTUnwrap(RunLock.tryAcquire(at: url))
        first.release()
        // After release, the next run must be able to acquire it (no stale-lock wedge).
        let second = try XCTUnwrap(RunLock.tryAcquire(at: url), "lock must be reacquirable after release")
        second.release()
    }

    func testWritesPidForDiagnostics() throws {
        let url = tempLockURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let lock = try XCTUnwrap(RunLock.tryAcquire(at: url))
        let contents = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        XCTAssertEqual(contents.trimmingCharacters(in: .whitespacesAndNewlines), "\(getpid())")
        lock.release()
    }
}

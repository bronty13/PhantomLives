import XCTest
@testable import PurpleReel

/// Coverage for the C37 `BackupJob.cancel()` API. The full
/// `VerifiedBackupService.run(...)` integration is an integration
/// test (filesystem + hashing); these unit tests pin the cancel
/// flag's state model. The service-loop's "stop processing on
/// cancel" branch is exercised by manual QA.
@MainActor
final class BackupJobCancelTests: XCTestCase {

    private func makeJob() -> BackupJob {
        BackupJob(
            source: URL(fileURLWithPath: "/tmp/source"),
            destinations: [URL(fileURLWithPath: "/tmp/dst")],
            algorithm: .sha1,
            mhlFormat: .legacy
        )
    }

    func testDefaultIsNotCancelled() {
        let job = makeJob()
        XCTAssertFalse(job.isCancelled,
            "Fresh BackupJob must not be in a cancelled state")
    }

    func testCancelFlipsTheFlag() {
        let job = makeJob()
        job.cancel()
        XCTAssertTrue(job.isCancelled,
            "cancel() must set isCancelled to true")
    }

    /// Calling cancel twice is a no-op — the flag stays true.
    /// VerifiedBackupService checks isCancelled between every
    /// file, so re-cancelling is idempotent; pin that here.
    func testCancelIsIdempotent() {
        let job = makeJob()
        job.cancel()
        job.cancel()
        XCTAssertTrue(job.isCancelled)
    }

    /// `.cancelled` is a distinct BackupFileState case so the run
    /// summary can count cancelled-but-not-attempted files
    /// separately from `.failed` (failed=verified-broken,
    /// cancelled=never-attempted). Pin the case exists + is
    /// distinct from .failed.
    func testCancelledStateIsDistinctFromFailed() {
        let cancelled = BackupFileState.cancelled
        let failed = BackupFileState.failed("x")
        XCTAssertNotEqual(cancelled, failed,
            ".cancelled and .failed must be distinct cases")
    }
}

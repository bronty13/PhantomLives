import XCTest
@testable import PurpleAtticCore

/// The resilience guard: a scheduled (e.g. hourly) run must do NOTHING — cleanly, no
/// throw, no boot-disk write — when the primary archive drive isn't a mounted volume.
final class PrimaryDriveGuardTests: XCTestCase {

    private func makeEngine() -> ExportEngine {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pa-guard-\(UUID().uuidString)")
        let logger = AtticLogger(runName: "guard-test", logDirectory: tmp, echo: false)
        return ExportEngine(logger: logger)
    }

    func testRunSkipsCleanlyWhenPrimaryDriveNotMounted() throws {
        // A /Volumes path that is not a mounted volume → the run must return a clean,
        // successful "skipped" summary rather than throwing or touching the boot disk.
        let profile = ArchiveProfile(
            name: "Test", primaryDestination: "/Volumes/__PA_NotMounted_Guard_Test__")
        let summary = try makeEngine().run(profile: profile, dryRun: false)

        XCTAssertTrue(summary.allSucceeded, "a no-op skip is a success, not a failure")
        XCTAssertEqual(summary.steps.count, 1)
        XCTAssertTrue(summary.steps[0].detail.contains("skipped"),
                      "the single step should record the skip, got: \(summary.steps[0].detail)")
        // It must NOT have created the unmounted path on the boot disk.
        XCTAssertFalse(FileManager.default.fileExists(atPath: "/Volumes/__PA_NotMounted_Guard_Test__"))
    }
}

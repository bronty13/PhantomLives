import XCTest
@testable import PurpleReel

/// Coverage for `PermissionsCheck` — specifically the
/// consent-on-first-use trigger helpers added for the macOS 15+
/// (Sequoia / Tahoe) Privacy & Security wizard rewrite.
///
/// We can't drive `NSOpenPanel` from XCTest, so the trigger flow is
/// tested via the underlying `attemptRead(at:)` helper that both
/// public triggers call once the user has picked a URL. That's
/// where the real TCC-bearing work happens; the panel is just a
/// URL picker.
final class PermissionsCheckTests: XCTestCase {

    func testCanReadReturnsTrueForReadableTempDir() {
        let tmp = FileManager.default.temporaryDirectory
        XCTAssertTrue(PermissionsCheck.canRead(path: tmp.path),
                       "Temp dir should always be readable from the test process")
    }

    func testCanReadReturnsFalseForMissingPath() {
        let bogus = "/var/empty/PurpleReel-test-\(UUID().uuidString)"
        XCTAssertFalse(PermissionsCheck.canRead(path: bogus),
                        "Nonexistent path must report unreadable")
    }

    func testAttemptReadGrantedForExistingDir() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("PurpleReel-PermTest-\(UUID().uuidString)",
                                     isDirectory: true)
        try FileManager.default.createDirectory(at: tmp,
                                                  withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        XCTAssertEqual(PermissionsCheck.attemptRead(at: tmp), .granted)
    }

    func testAttemptReadDeniedForMissingDir() {
        let bogus = URL(fileURLWithPath:
            "/var/empty/PurpleReel-test-\(UUID().uuidString)",
                         isDirectory: true)
        let outcome = PermissionsCheck.attemptRead(at: bogus)
        if case .denied = outcome {
            // Expected.
        } else {
            XCTFail("Missing path must return .denied, got \(outcome)")
        }
    }

    func testRunReturnsAResultStruct() {
        // Spot-check that `run()` doesn't crash and returns a Result.
        // We can't assert on the boolean values — those depend on
        // what TCC has authorised for the test runner — but the call
        // path must not throw and must return a stable struct shape.
        let result = PermissionsCheck.run()
        _ = result.hasMinimumViable
        _ = result.movies
        _ = result.downloads
        _ = result.documents
        _ = result.fullDiskAccess
    }

    func testHasMinimumViableTrumpedByFullDiskAccess() {
        let fda = PermissionsCheck.Result(movies: false, downloads: false,
                                            documents: false, fullDiskAccess: true)
        XCTAssertTrue(fda.hasMinimumViable,
                       "Full Disk Access alone must satisfy hasMinimumViable")

        let allThree = PermissionsCheck.Result(movies: true, downloads: true,
                                                 documents: true, fullDiskAccess: false)
        XCTAssertTrue(allThree.hasMinimumViable,
                       "All three folder grants must satisfy hasMinimumViable")

        let partial = PermissionsCheck.Result(movies: true, downloads: true,
                                                documents: false, fullDiskAccess: false)
        XCTAssertFalse(partial.hasMinimumViable,
                        "Missing Documents must fail hasMinimumViable")
    }

    func testPaneURLsAreParseable() {
        for pane in PermissionsCheck.Pane.allCases {
            XCTAssertNotNil(URL(string: pane.rawValue),
                             "Pane \(pane.label) must produce a parseable URL")
        }
    }
}

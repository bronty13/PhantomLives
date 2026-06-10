import XCTest
@testable import PurpleAtticCore

final class ReviewStagingTests: XCTestCase {

    func testNewPathsIsSetDifference() {
        let before: Set<String> = ["2020/a.heic", "2020/a.heic.xmp"]
        let after: Set<String> = ["2020/a.heic", "2020/a.heic.xmp", "2021/b.heic", "2021/b.heic.xmp"]
        XCTAssertEqual(ReviewStaging.newPaths(before: before, after: after),
                       ["2021/b.heic", "2021/b.heic.xmp"])
    }

    func testNoNewPathsWhenUnchanged() {
        let s: Set<String> = ["x", "y"]
        XCTAssertTrue(ReviewStaging.newPaths(before: s, after: s).isEmpty)
    }

    func testSnapshotAndCopyNewRoundTrip() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("pa-review-\(UUID().uuidString)")
        let src = root.appendingPathComponent("originals")
        let batch = root.appendingPathComponent("REVIEW/20260610-120000")
        try fm.createDirectory(at: src.appendingPathComponent("2020/2020-01"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        // Baseline file.
        try "old".write(to: src.appendingPathComponent("2020/2020-01/old.heic"), atomically: true, encoding: .utf8)
        let before = ReviewStaging.snapshot(src.path)
        XCTAssertEqual(before, ["2020/2020-01/old.heic"])

        // Add a new photo + sidecar.
        try fm.createDirectory(at: src.appendingPathComponent("2021/2021-05"), withIntermediateDirectories: true)
        try "new".write(to: src.appendingPathComponent("2021/2021-05/new.heic"), atomically: true, encoding: .utf8)
        try "<xmp/>".write(to: src.appendingPathComponent("2021/2021-05/new.heic.xmp"), atomically: true, encoding: .utf8)

        let added = ReviewStaging.newPaths(before: before, after: ReviewStaging.snapshot(src.path))
        XCTAssertEqual(added, ["2021/2021-05/new.heic", "2021/2021-05/new.heic.xmp"])

        let r = ReviewStaging.copyNew(relPaths: added, sourceDir: src.path, batchDir: batch.path, subfolder: "originals")
        XCTAssertEqual(r.copied, 2)
        XCTAssertEqual(r.failed, 0)
        // The new files landed under <batch>/originals/<dated path>, structure preserved.
        XCTAssertTrue(fm.fileExists(atPath: batch.appendingPathComponent("originals/2021/2021-05/new.heic").path))
        XCTAssertTrue(fm.fileExists(atPath: batch.appendingPathComponent("originals/2021/2021-05/new.heic.xmp").path))
        // The pre-existing file was NOT re-staged.
        XCTAssertFalse(fm.fileExists(atPath: batch.appendingPathComponent("originals/2020/2020-01/old.heic").path))
    }

    func testSnapshotEmptyForMissingDir() {
        XCTAssertTrue(ReviewStaging.snapshot("/no/such/dir-\(UUID().uuidString)").isEmpty)
    }
}

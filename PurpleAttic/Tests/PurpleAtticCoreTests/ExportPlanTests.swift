import XCTest
@testable import PurpleAtticCore

final class ExportPlanTests: XCTestCase {

    private func profile(jpeg: Bool = true) -> ArchiveProfile {
        ArchiveProfile(
            name: "Test",
            photosLibraryPath: nil,
            primaryDestination: "/Volumes/SSD/PhotoArchive",
            mirrorDestinations: ["/Volumes/Mirror/PhotoArchive"],
            keepHEIC: true,
            keepJPEG: jpeg
        )
    }

    func testOriginalsArgsHaveSafetyFlags() {
        let args = ExportPlan.arguments(profile: profile(), pass: .originals, dryRun: false)
        XCTAssertEqual(args.first, "export")
        XCTAssertEqual(args[1], "/Volumes/SSD/PhotoArchive/originals")
        XCTAssertTrue(args.contains("--update"), "incremental flag must always be present")
        XCTAssertTrue(args.contains("--sidecar"))
        XCTAssertTrue(args.contains("XMP"))
        XCTAssertTrue(args.contains("--exiftool"))
        XCTAssertFalse(args.contains("--convert-to-jpeg"), "originals pass must not convert")
        XCTAssertFalse(args.contains("--dry-run"))
    }

    func testJpegPassConverts() {
        let args = ExportPlan.arguments(profile: profile(), pass: .jpeg, dryRun: false)
        XCTAssertEqual(args[1], "/Volumes/SSD/PhotoArchive/jpeg")
        XCTAssertTrue(args.contains("--convert-to-jpeg"))
    }

    func testDryRunFlag() {
        let args = ExportPlan.arguments(profile: profile(), pass: .originals, dryRun: true)
        XCTAssertTrue(args.contains("--dry-run"))
    }

    func testLibraryPathIncludedWhenSet() {
        var p = profile()
        p.photosLibraryPath = "/Users/me/Pictures/Photos Library.photoslibrary"
        let args = ExportPlan.arguments(profile: p, pass: .originals, dryRun: false)
        XCTAssertTrue(args.contains("--library"))
        XCTAssertTrue(args.contains("/Users/me/Pictures/Photos Library.photoslibrary"))
    }

    func testDownloadMissingOptIn() {
        var p = profile()
        p.downloadMissingFromICloud = true
        let args = ExportPlan.arguments(profile: p, pass: .originals, dryRun: false)
        XCTAssertTrue(args.contains("--download-missing"))
    }

    func testEnabledPassesRespectFormatToggles() {
        XCTAssertEqual(profile(jpeg: true).enabledPasses, [.originals, .jpeg])
        XCTAssertEqual(profile(jpeg: false).enabledPasses, [.originals])
    }

    func testShellQuotingOfSpacedPaths() {
        let cmd = ExportPlan.shellCommand(osxphotos: "/opt/homebrew/bin/osxphotos",
                                          profile: profile(), pass: .originals, dryRun: false)
        XCTAssertTrue(cmd.contains("'{created.year}/{created.year}-{created.mm}'")
                      || cmd.contains("{created.year}/{created.year}-{created.mm}"))
        XCTAssertTrue(cmd.hasPrefix("/opt/homebrew/bin/osxphotos export"))
    }
}

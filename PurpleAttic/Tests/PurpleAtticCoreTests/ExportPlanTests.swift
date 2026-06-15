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

    func testIncludeHiddenFollowsProfile() {
        // osxphotos includes hidden BY DEFAULT, so "include hidden" = no hidden flag at all.
        let defaultArgs = ExportPlan.arguments(profile: profile(), pass: .originals, dryRun: false)
        XCTAssertFalse(defaultArgs.contains("--not-hidden"), "default archives the Hidden album")
        XCTAssertFalse(defaultArgs.contains("--include-hidden"), "no such osxphotos flag")
        // Opt out → --not-hidden excludes the Hidden album.
        var p = profile(); p.includeHidden = false
        XCTAssertTrue(ExportPlan.arguments(profile: p, pass: .originals, dryRun: false)
                        .contains("--not-hidden"))
    }

    func testOriginalsArgsHaveSafetyFlags() {
        let args = ExportPlan.arguments(profile: profile(), pass: .originals, dryRun: false)
        XCTAssertEqual(args.first, "export")
        // Default archiveSubfolder ("Photos Archive") is nested under the chosen base.
        XCTAssertEqual(args[1], "/Volumes/SSD/PhotoArchive/Photos Archive/originals")
        XCTAssertTrue(args.contains("--update"), "incremental flag must always be present")
        XCTAssertTrue(args.contains("--sidecar"))
        XCTAssertTrue(args.contains("XMP"))
        XCTAssertTrue(args.contains("--exiftool"))
        // When exiftool is resolvable, its ABSOLUTE path must be passed so a launchd/
        // scheduled run (minimal PATH) doesn't fail with "Could not find exiftool".
        if let exiftool = Tooling.exiftool {
            let i = args.firstIndex(of: "--exiftool-path")
            XCTAssertNotNil(i, "--exiftool-path must accompany --exiftool")
            if let i { XCTAssertEqual(args[i + 1], exiftool) }
        }
        XCTAssertFalse(args.contains("--convert-to-jpeg"), "originals pass must not convert")
        XCTAssertFalse(args.contains("--dry-run"))
    }

    func testJpegPassConverts() {
        let args = ExportPlan.arguments(profile: profile(), pass: .jpeg, dryRun: false)
        XCTAssertEqual(args[1], "/Volumes/SSD/PhotoArchive/Photos Archive/jpeg")
        XCTAssertTrue(args.contains("--convert-to-jpeg"))
    }

    // MARK: Archive subfolder composition

    func testArchiveRootNestsSubfolderForPhysicalBases() {
        var p = profile()
        p.primaryDestination = "/Volumes/PRO-G40"
        p.mirrorDestinations = ["/Volumes/MirrorA", "/Volumes/MirrorB"]
        p.archiveSubfolder = "Photos Archive"
        XCTAssertEqual(p.primaryArchiveRoot, "/Volumes/PRO-G40/Photos Archive")
        XCTAssertEqual(p.mirrorArchiveRoots,
                       ["/Volumes/MirrorA/Photos Archive", "/Volumes/MirrorB/Photos Archive"])
        // The export destination is the archive root + the pass subdir.
        let args = ExportPlan.arguments(profile: p, pass: .originals, dryRun: false)
        XCTAssertEqual(args[1], "/Volumes/PRO-G40/Photos Archive/originals")
    }

    func testEmptyArchiveSubfolderIsOptOut() {
        var p = profile()
        p.primaryDestination = "/Volumes/PRO-G40"
        p.archiveSubfolder = ""
        XCTAssertEqual(p.primaryArchiveRoot, "/Volumes/PRO-G40")
        let args = ExportPlan.arguments(profile: p, pass: .originals, dryRun: false)
        XCTAssertEqual(args[1], "/Volumes/PRO-G40/originals")
    }

    func testCustomArchiveSubfolderName() {
        var p = profile()
        p.primaryDestination = "/Volumes/PRO-G40"
        p.archiveSubfolder = "Backups/PhotoArchive"
        XCTAssertEqual(p.primaryArchiveRoot, "/Volumes/PRO-G40/Backups/PhotoArchive")
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

    func testDownloadMissingUsesPhotoKitByDefault() {
        var p = profile()
        p.downloadMissingFromICloud = true
        // usePhotoKitForDownload defaults to true.
        let args = ExportPlan.arguments(profile: p, pass: .originals, dryRun: false)
        XCTAssertTrue(args.contains("--download-missing"))
        XCTAssertTrue(args.contains("--use-photokit"),
                      "PhotoKit is the reliable download path and is the default")
    }

    func testPhotoKitCanBeDisabledForAppleScriptPath() {
        var p = profile()
        p.downloadMissingFromICloud = true
        p.usePhotoKitForDownload = false
        let args = ExportPlan.arguments(profile: p, pass: .originals, dryRun: false)
        XCTAssertTrue(args.contains("--download-missing"))
        XCTAssertFalse(args.contains("--use-photokit"))
    }

    func testPhotoKitFlagAbsentWithoutDownloadMissing() {
        var p = profile()
        p.downloadMissingFromICloud = false
        p.usePhotoKitForDownload = true   // meaningless without download-missing
        let args = ExportPlan.arguments(profile: p, pass: .originals, dryRun: false)
        XCTAssertFalse(args.contains("--use-photokit"),
                       "--use-photokit must not appear unless --download-missing is active")
        XCTAssertFalse(args.contains("--download-missing"))
    }

    func testSharedAndSyndicatedExcludedByDefault() {
        // excludeSharedAndSyndicated defaults to true.
        let args = ExportPlan.arguments(profile: profile(), pass: .originals, dryRun: false)
        XCTAssertTrue(args.contains("--not-syndicated"),
                      "Shared-with-You items must be skipped so they don't show as missing")
        XCTAssertTrue(args.contains("--not-shared"),
                      "shared-album items must be skipped (not your originals)")
    }

    func testSharedExclusionCanBeDisabled() {
        var p = profile()
        p.excludeSharedAndSyndicated = false
        let args = ExportPlan.arguments(profile: p, pass: .originals, dryRun: false)
        XCTAssertFalse(args.contains("--not-syndicated"))
        XCTAssertFalse(args.contains("--not-shared"))
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

import XCTest
@testable import PurpleAtticCore

/// Regression guard for the mirror/cloud rsync flags. macOS's default rsync is openrsync,
/// which rejects `--info=progress2` and aborts instantly — which silently broke mirror,
/// verify, and cloud on the first real run. The engine must pick flags the available rsync
/// actually supports.
final class RsyncArgsTests: XCTestCase {

    private let junkExcludes = ["--exclude=.DS_Store", "--exclude=.osxphotos_export.db*"]

    func testOpenrsyncBannerAvoidsProgress2() {
        // The exact banner from macOS's /usr/bin/rsync.
        let banner = "openrsync: protocol version 29\nrsync version 2.6.9 compatible\n"
        let args = ExportEngine.rsyncCopyArgs(versionBanner: banner)
        XCTAssertFalse(args.contains("--info=progress2"), "openrsync rejects --info=progress2")
        XCTAssertFalse(args.contains(where: { $0.hasPrefix("--progress") || $0 == "-P" }))
        XCTAssertEqual(args, ["-ahv"] + junkExcludes)
    }

    func testModernRsync3UsesProgress2() {
        let banner = "rsync  version 3.2.7  protocol version 31\nCopyright (C) 1996-2022\n"
        let args = ExportEngine.rsyncCopyArgs(versionBanner: banner)
        XCTAssertEqual(args, ["-ah", "--info=progress2"] + junkExcludes)
    }

    func testRsync2xClassicAvoidsProgress2() {
        // A genuine old samba rsync 2.6.9 (not openrsync) also lacks --info=progress2.
        let args = ExportEngine.rsyncCopyArgs(versionBanner: "rsync  version 2.6.9  protocol version 29")
        XCTAssertEqual(args, ["-ahv"] + junkExcludes)
    }

    func testEmptyBannerFallsBackSafely() {
        // Couldn't read --version → assume the lowest common denominator (no progress2).
        XCTAssertEqual(ExportEngine.rsyncCopyArgs(versionBanner: ""), ["-ahv"] + junkExcludes)
    }

    func testAlwaysExcludesJunkRegardlessOfRsync() {
        // .DS_Store on a Cryptomator/macFUSE vault aborts the whole openrsync transfer;
        // the export DB is per-destination state, not archive content. Both must be excluded
        // from every copy (mirror + cloud), on any rsync.
        for banner in ["openrsync: protocol version 29", "rsync version 3.2.7", ""] {
            let args = ExportEngine.rsyncCopyArgs(versionBanner: banner)
            XCTAssertTrue(args.contains("--exclude=.DS_Store"))
            XCTAssertTrue(args.contains("--exclude=.osxphotos_export.db*"))
        }
    }

    func testMirrorKeepsOwnerGroupPerms() {
        // The on-disk (APFS) mirror preserves attributes — no --no-* flags.
        let args = ExportEngine.rsyncCopyArgs(versionBanner: "openrsync: protocol version 29")
        XCTAssertFalse(args.contains("--no-owner"))
        XCTAssertFalse(args.contains("--no-group"))
        XCTAssertFalse(args.contains("--no-perms"))
    }

    func testVaultDropsOwnerGroupPerms() {
        // The Cryptomator/macFUSE vault can't chown/chmod (fchownat → "Function not
        // implemented"), so owner/group/perms preservation must be disabled or the cloud
        // copy aborts.
        for banner in ["openrsync: protocol version 29", "rsync version 3.2.7", ""] {
            let args = ExportEngine.rsyncCopyArgs(versionBanner: banner, forVault: true)
            XCTAssertTrue(args.contains("--no-owner"))
            XCTAssertTrue(args.contains("--no-group"))
            XCTAssertTrue(args.contains("--no-perms"))
            // still excludes the junk
            XCTAssertTrue(args.contains("--exclude=.DS_Store"))
        }
    }
}

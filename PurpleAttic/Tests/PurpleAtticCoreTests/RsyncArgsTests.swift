import XCTest
@testable import PurpleAtticCore

/// Regression guard for the mirror/cloud rsync flags. macOS's default rsync is openrsync,
/// which rejects `--info=progress2` and aborts instantly — which silently broke mirror,
/// verify, and cloud on the first real run. The engine must pick flags the available rsync
/// actually supports.
final class RsyncArgsTests: XCTestCase {

    func testOpenrsyncBannerAvoidsProgress2() {
        // The exact banner from macOS's /usr/bin/rsync.
        let banner = "openrsync: protocol version 29\nrsync version 2.6.9 compatible\n"
        let args = ExportEngine.rsyncCopyArgs(versionBanner: banner)
        XCTAssertFalse(args.contains("--info=progress2"), "openrsync rejects --info=progress2")
        XCTAssertFalse(args.contains(where: { $0.hasPrefix("--progress") || $0 == "-P" }))
        XCTAssertEqual(args, ["-ahv"])
    }

    func testModernRsync3UsesProgress2() {
        let banner = "rsync  version 3.2.7  protocol version 31\nCopyright (C) 1996-2022\n"
        let args = ExportEngine.rsyncCopyArgs(versionBanner: banner)
        XCTAssertEqual(args, ["-ah", "--info=progress2"])
    }

    func testRsync2xClassicAvoidsProgress2() {
        // A genuine old samba rsync 2.6.9 (not openrsync) also lacks --info=progress2.
        let args = ExportEngine.rsyncCopyArgs(versionBanner: "rsync  version 2.6.9  protocol version 29")
        XCTAssertEqual(args, ["-ahv"])
    }

    func testEmptyBannerFallsBackSafely() {
        // Couldn't read --version → assume the lowest common denominator (no progress2).
        XCTAssertEqual(ExportEngine.rsyncCopyArgs(versionBanner: ""), ["-ahv"])
    }
}

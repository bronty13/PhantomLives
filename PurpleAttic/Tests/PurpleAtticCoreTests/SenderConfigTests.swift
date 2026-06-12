import XCTest
@testable import PurpleAtticCore

/// Sender mode must (a) reuse the export engine without ever enabling mirror/cloud/**purge** or
/// local review copies, and (b) build a correct rsync-over-SSH command. These tests pin both.
final class SenderConfigTests: XCTestCase {

    private func baseConfig() -> SenderConfig {
        SenderConfig(
            name: "Sallie-MacBook",
            stagingRoot: "/Volumes/SenderSSD",
            archiveSubfolder: "Photos Archive - Sallie",
            keepHEIC: true, keepJPEG: true,
            downloadMissingFromICloud: false,
            remote: .init(enabled: true, host: "vortex.local", user: "bronty13",
                          port: 2222, identityFile: "/Users/x/.ssh/vortex", remotePath: "/Volumes/ROG_WHITE/Sallie")
        )
    }

    // MARK: - export-only / never-purge

    func testExportProfileIsExportOnlyAndNeverPurges() {
        let p = baseConfig().exportProfile()
        XCTAssertEqual(p.primaryDestination, "/Volumes/SenderSSD")
        XCTAssertTrue(p.mirrorDestinations.isEmpty, "sender must not mirror locally")
        XCTAssertNil(p.cloudVaultPath, "sender must not touch a vault")
        XCTAssertFalse(p.purgeEnabled, "a sender can NEVER purge")
        XCTAssertFalse(p.reviewNewItems, "no local review copies on a small-disk source")
        XCTAssertEqual(p.archiveSubfolder, "Photos Archive - Sallie")
        XCTAssertEqual(p.enabledPasses, [.originals, .jpeg])
    }

    func testExportProfileCarriesDownloadFlags() {
        var c = baseConfig(); c.downloadMissingFromICloud = true; c.usePhotoKitForDownload = true
        let p = c.exportProfile()
        XCTAssertTrue(p.downloadMissingFromICloud)
        XCTAssertTrue(p.usePhotoKitForDownload)
        // And that flows through to the osxphotos argv.
        let args = ExportPlan.arguments(profile: p, pass: .originals, dryRun: false)
        XCTAssertTrue(args.contains("--download-missing"))
        XCTAssertTrue(args.contains("--use-photokit"))
    }

    func testStagingArchiveRootNesting() {
        XCTAssertEqual(baseConfig().stagingArchiveRoot, "/Volumes/SenderSSD/Photos Archive - Sallie")
        var c = baseConfig(); c.archiveSubfolder = ""
        XCTAssertEqual(c.stagingArchiveRoot, "/Volumes/SenderSSD", "empty subfolder → archive at SSD root")
    }

    // MARK: - validation

    func testValidationFlagsMissingStagingAndRemoteFields() {
        var c = SenderConfig()  // empty staging, remote disabled
        XCTAssertTrue(c.validationIssues().contains { $0.contains("Staging SSD path is not set") })

        c.stagingRoot = "/Volumes/SenderSSD"   // not mounted in test env
        XCTAssertTrue(c.validationIssues().contains { $0.contains("isn’t mounted/available") })

        c.remote = .init(enabled: true, host: "", user: "", port: 22, remotePath: "")
        let issues = c.validationIssues()
        XCTAssertTrue(issues.contains { $0.contains("Remote host") })
        XCTAssertTrue(issues.contains { $0.contains("Remote user") })
        XCTAssertTrue(issues.contains { $0.contains("Remote path") })
    }

    func testNoFormatSelectedIsAnIssue() {
        var c = baseConfig(); c.keepHEIC = false; c.keepJPEG = false
        XCTAssertTrue(c.validationIssues().contains { $0.contains("No export format") })
    }

    // MARK: - rsync-over-SSH argv

    func testRsyncArgumentsShape() {
        let args = SenderAgent.rsyncArguments(config: baseConfig(), rsyncVersionBanner: "openrsync")
        // Excludes + resume + verbose copy (openrsync banner → -ahv, not progress2).
        XCTAssertTrue(args.contains("-ahv"))
        XCTAssertTrue(args.contains("--partial"))
        XCTAssertTrue(args.contains("--exclude=.DS_Store"))
        XCTAssertTrue(args.contains("--exclude=.osxphotos_export.db*"))
        // The SSH transport string carries port, identity, and unattended-safe options.
        guard let eIdx = args.firstIndex(of: "-e") else { return XCTFail("missing -e") }
        let ssh = args[eIdx + 1]
        XCTAssertTrue(ssh.contains("ssh -p 2222"))
        XCTAssertTrue(ssh.contains("-i /Users/x/.ssh/vortex"))
        XCTAssertTrue(ssh.contains("BatchMode=yes"))
        XCTAssertTrue(ssh.contains("StrictHostKeyChecking=accept-new"))
        // Source is the staging archive root WITH a trailing slash (copy contents, not the dir).
        XCTAssertEqual(args[args.count - 2], "/Volumes/SenderSSD/Photos Archive - Sallie/")
        // Target: user@host:'remotePath/' (remote path single-quoted so spaces survive the remote shell).
        XCTAssertEqual(args.last, "bronty13@vortex.local:'/Volumes/ROG_WHITE/Sallie/'")
    }

    func testRsyncIdentityFileOmittedWhenNil() {
        var c = baseConfig(); c.remote.identityFile = nil
        let args = SenderAgent.rsyncArguments(config: c, rsyncVersionBanner: "openrsync")
        let ssh = args[args.firstIndex(of: "-e")! + 1]
        XCTAssertFalse(ssh.contains("-i "), "no -i when no identity file configured")
    }

    // MARK: - round-trip persistence

    func testCodableRoundTrip() throws {
        let c = baseConfig()
        let data = try JSONEncoder().encode(c)
        let back = try JSONDecoder().decode(SenderConfig.self, from: data)
        XCTAssertEqual(c, back)
    }

    func testDecodingToleratesMissingKeys() throws {
        // An older/minimal sender.json with only a couple of keys must decode with defaults.
        let json = #"{"name":"X","stagingRoot":"/Volumes/S"}"#.data(using: .utf8)!
        let c = try JSONDecoder().decode(SenderConfig.self, from: json)
        XCTAssertEqual(c.name, "X")
        XCTAssertEqual(c.stagingRoot, "/Volumes/S")
        XCTAssertTrue(c.keepHEIC)                 // default
        XCTAssertFalse(c.remote.enabled)          // default
        XCTAssertEqual(c.archiveSubfolder, "Photos Archive")
    }
}

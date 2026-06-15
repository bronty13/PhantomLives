import XCTest
@testable import PurpleAtticCore

/// Covers the off-site (restic) layer's *pure* building blocks — the environment + arguments restic
/// is driven with — plus the skip-not-fail contract. These run without a network, a B2 bucket, or
/// the Keychain, which is the whole point: the acceptance gate is "assert the exact env/args a
/// destination produces" so a regression can't silently corrupt how secrets are passed.
final class ResticServiceTests: XCTestCase {

    private func b2Dest() -> CloudDestination {
        CloudDestination(name: "Backblaze B2", kind: .resticB2,
                         repo: "b2:my-bucket:photos", keychainService: "PurpleAttic Restic B2")
    }

    private func rcloneDest() -> CloudDestination {
        CloudDestination(name: "Proton", kind: .resticRclone,
                         repo: "rclone:proton:photos", rcloneRemote: "proton",
                         keychainService: "PurpleAttic Restic Proton")
    }

    // MARK: - Password command

    func testPasswordCommandTargetsKeychainItem() {
        let cmd = ResticService.passwordCommand(service: "PurpleAttic Restic B2")
        XCTAssertTrue(cmd.hasPrefix("/usr/bin/security find-generic-password"))
        XCTAssertTrue(cmd.contains("-s 'PurpleAttic Restic B2'"), "service must be present + shell-quoted")
        XCTAssertTrue(cmd.contains("-a \(ResticService.KeychainAccount.resticPassword)"))
        XCTAssertTrue(cmd.hasSuffix("-w"), "-w prints the password for RESTIC_PASSWORD_COMMAND")
    }

    func testPasswordCommandEscapesQuotesInService() {
        // A service name containing a single quote must not break out of the shell quoting.
        let cmd = ResticService.passwordCommand(service: "weird'name")
        XCTAssertTrue(cmd.contains("'weird'\\''name'"))
    }

    // MARK: - Environment building (B2)

    func testB2EnvironmentHasRepoCredsAndPasswordCommand() {
        let secrets = ResticService.ResolvedSecrets(b2AccountId: "ID123", b2AccountKey: "KEY456")
        let env = ResticService.makeEnvironment(for: b2Dest(), secrets: secrets,
                                                inheritedPATH: "/usr/bin:/bin", home: "/Users/test")
        XCTAssertEqual(env["RESTIC_REPOSITORY"], "b2:my-bucket:photos")
        XCTAssertEqual(env["B2_ACCOUNT_ID"], "ID123")
        XCTAssertEqual(env["B2_ACCOUNT_KEY"], "KEY456")
        XCTAssertEqual(env["HOME"], "/Users/test")
        XCTAssertNotNil(env["RESTIC_PASSWORD_COMMAND"])
        // The passphrase itself must NEVER be in the env — only the command that fetches it.
        XCTAssertNil(env["RESTIC_PASSWORD"])
        // A B2 destination must not leak rclone vars.
        XCTAssertNil(env["RCLONE_CONFIG"])
        XCTAssertNil(env["RCLONE_CONFIG_PASS"])
    }

    func testB2EnvironmentOmitsMissingCreds() {
        // No secrets resolved → no B2 keys in the env (backup() will skip cleanly upstream).
        let env = ResticService.makeEnvironment(for: b2Dest(), secrets: .init(),
                                                inheritedPATH: "/usr/bin", home: "/Users/test")
        XCTAssertNil(env["B2_ACCOUNT_ID"])
        XCTAssertNil(env["B2_ACCOUNT_KEY"])
    }

    // MARK: - Environment building (rclone)

    func testRcloneEnvironmentHasConfigNotB2() {
        let secrets = ResticService.ResolvedSecrets(rcloneConfigPath: "/Users/test/.config/rclone/rclone.conf",
                                                    rcloneConfigPass: "cfgpass")
        let env = ResticService.makeEnvironment(for: rcloneDest(), secrets: secrets,
                                                inheritedPATH: "/usr/bin", home: "/Users/test")
        XCTAssertEqual(env["RESTIC_REPOSITORY"], "rclone:proton:photos")
        XCTAssertEqual(env["RCLONE_CONFIG"], "/Users/test/.config/rclone/rclone.conf")
        XCTAssertEqual(env["RCLONE_CONFIG_PASS"], "cfgpass")
        XCTAssertNil(env["B2_ACCOUNT_ID"], "an rclone destination must not set B2 vars")
        XCTAssertNil(env["B2_ACCOUNT_KEY"])
    }

    // MARK: - PATH augmentation (the launchd-bare-PATH lesson)

    func testEnsureToolDirsPrependsHomebrewWhenMissing() {
        let p = ResticService.ensureToolDirs(inPATH: "/usr/bin:/bin")
        XCTAssertTrue(p.hasPrefix("/opt/homebrew/bin:/usr/local/bin:"),
                      "homebrew tool dirs must be prepended so restic can find rclone under launchd")
        XCTAssertTrue(p.hasSuffix("/usr/bin:/bin"))
    }

    func testEnsureToolDirsNoDuplicatesWhenPresent() {
        let input = "/opt/homebrew/bin:/usr/bin"
        let p = ResticService.ensureToolDirs(inPATH: input)
        XCTAssertEqual(p.components(separatedBy: "/opt/homebrew/bin").count - 1, 1, "must not duplicate an existing dir")
    }

    // MARK: - Argument building

    func testBackupArgumentsPinHostAndTag() {
        let args = ResticService.backupArguments(sourcePath: "/Volumes/ROG_WHITE/Photos Archive")
        XCTAssertEqual(args.first, "backup")
        XCTAssertTrue(args.contains("/Volumes/ROG_WHITE/Photos Archive"))
        XCTAssertTrue(args.contains("--tag"))
        XCTAssertTrue(args.contains(ResticService.snapshotTag))
        XCTAssertTrue(args.contains("--host"))
        XCTAssertTrue(args.contains(ResticService.snapshotHost))
    }

    func testCheckArgumentsStructureAndSubset() {
        XCTAssertEqual(ResticService.checkArguments(), ["check"])
        XCTAssertEqual(ResticService.checkArguments(readDataSubset: "1/20"),
                       ["check", "--read-data-subset", "1/20"])
    }

    // MARK: - Outcome semantics (skip is NOT a failure)

    func testOutcomeFailureClassification() {
        XCTAssertFalse(ResticService.Outcome.skipped(reason: "offline").isFailure)
        XCTAssertFalse(ResticService.Outcome.backedUp(detail: "ok").isFailure)
        XCTAssertFalse(ResticService.Outcome.checked(detail: "ok").isFailure)
        XCTAssertTrue(ResticService.Outcome.failed("boom").isFailure)
        XCTAssertEqual(ResticService.Outcome.skipped(reason: "offline").detail, "skipped — offline")
    }

    // MARK: - Skip-when-unconfigured / missing creds (no network touched)

    func testBackupSkipsMissingB2Creds() throws {
        // With restic installed, a configured B2 destination whose Keychain has no creds must
        // SKIP (not fail, not prompt, not hit the network). Guards the laptop "offline = no-op".
        try XCTSkipIf(Tooling.restic == nil, "restic not installed in this environment")
        let dest = CloudDestination(name: "B2", kind: .resticB2,
                                    repo: "b2:nonexistent-bucket-xyz:photos",
                                    keychainService: "PurpleAttic Test No Such Service \(UUID().uuidString)")
        let outcome = ResticService.backup(destination: dest, sourcePath: "/tmp") { _ in }
        guard case .skipped = outcome else {
            return XCTFail("expected .skipped for a B2 destination with no Keychain creds, got \(outcome)")
        }
    }
}

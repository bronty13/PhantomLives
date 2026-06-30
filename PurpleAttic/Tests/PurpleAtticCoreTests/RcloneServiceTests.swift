import XCTest
@testable import PurpleAtticCore

/// Covers the ad-hoc B2 (rclone crypt) layer's *pure* building blocks — the env-defined remotes and
/// the argv rclone is driven with — plus the skip-not-fail outcome semantics. These run without a
/// network, a B2 bucket, or the Keychain: the acceptance gate is "assert the exact remote/args a
/// config produces" so a regression can't silently corrupt how the two B2 remotes (and their
/// secrets) are defined. Mirrors `ResticServiceTests`.
final class RcloneServiceTests: XCTestCase {

    private func cfg(prefix: String = "files", hardDelete: Bool = true) -> AdhocBackupConfig {
        AdhocBackupConfig(name: "Ad-hoc B2", bucket: "my-bucket", prefix: prefix,
                          keychainService: "PurpleAttic B2 Ad-hoc", sources: [], hardDelete: hardDelete)
    }

    private func secrets() -> RcloneService.ResolvedSecrets {
        .init(b2AccountId: "KID", b2AccountKey: "AKEY",
              cryptPasswordObscured: "OBSCURED1", cryptPassword2Obscured: "OBSCURED2")
    }

    // MARK: - Env var key composition

    func testConfigEnvKeyUppercasesRemoteAndKey() {
        XCTAssertEqual(RcloneService.configEnvKey("padhocb2", "account"), "RCLONE_CONFIG_PADHOCB2_ACCOUNT")
        XCTAssertEqual(RcloneService.configEnvKey("padhoc", "filename_encryption"),
                       "RCLONE_CONFIG_PADHOC_FILENAME_ENCRYPTION")
    }

    // MARK: - Remote path composition

    func testBaseRemotePathWithAndWithoutPrefix() {
        XCTAssertEqual(RcloneService.baseRemotePath(config: cfg(prefix: "files")), "padhocb2:my-bucket/files")
        XCTAssertEqual(RcloneService.baseRemotePath(config: cfg(prefix: "")), "padhocb2:my-bucket")
        // Stray slashes around the prefix must not double up.
        XCTAssertEqual(RcloneService.baseRemotePath(config: cfg(prefix: "/files/")), "padhocb2:my-bucket/files")
    }

    func testCryptPath() {
        XCTAssertEqual(RcloneService.cryptPath(), "padhoc:")
        XCTAssertEqual(RcloneService.cryptPath("Invoices/x.pdf"), "padhoc:Invoices/x.pdf")
    }

    // MARK: - Environment building

    func testEnvironmentDefinesBothRemotesWithSecrets() {
        let env = RcloneService.makeEnvironment(for: cfg(), secrets: secrets(),
                                                inheritedPATH: "/usr/bin:/bin", home: "/Users/test")
        // Isolation + basics.
        XCTAssertEqual(env["RCLONE_CONFIG"], "/dev/null", "must ignore the user's personal rclone.conf")
        XCTAssertEqual(env["HOME"], "/Users/test")
        XCTAssertTrue(env["PATH"]?.contains("/opt/homebrew/bin") == true, "homebrew dirs prepended so rclone is found")
        // Base B2 remote.
        XCTAssertEqual(env["RCLONE_CONFIG_PADHOCB2_TYPE"], "b2")
        XCTAssertEqual(env["RCLONE_CONFIG_PADHOCB2_ACCOUNT"], "KID")
        XCTAssertEqual(env["RCLONE_CONFIG_PADHOCB2_KEY"], "AKEY")
        XCTAssertEqual(env["RCLONE_CONFIG_PADHOCB2_HARD_DELETE"], "true")
        // Crypt remote wrapping the base.
        XCTAssertEqual(env["RCLONE_CONFIG_PADHOC_TYPE"], "crypt")
        XCTAssertEqual(env["RCLONE_CONFIG_PADHOC_REMOTE"], "padhocb2:my-bucket/files")
        XCTAssertEqual(env["RCLONE_CONFIG_PADHOC_PASSWORD"], "OBSCURED1")
        XCTAssertEqual(env["RCLONE_CONFIG_PADHOC_PASSWORD2"], "OBSCURED2")
        XCTAssertEqual(env["RCLONE_CONFIG_PADHOC_FILENAME_ENCRYPTION"], "standard")
        XCTAssertEqual(env["RCLONE_CONFIG_PADHOC_DIRECTORY_NAME_ENCRYPTION"], "true")
    }

    func testEnvironmentOmitsMissingSecretsButKeepsStructure() {
        let env = RcloneService.makeEnvironment(for: cfg(), secrets: .init(),
                                                inheritedPATH: "/usr/bin", home: "/Users/test")
        // No secrets → no credential vars (ops skip cleanly upstream)…
        XCTAssertNil(env["RCLONE_CONFIG_PADHOCB2_ACCOUNT"])
        XCTAssertNil(env["RCLONE_CONFIG_PADHOCB2_KEY"])
        XCTAssertNil(env["RCLONE_CONFIG_PADHOC_PASSWORD"])
        XCTAssertNil(env["RCLONE_CONFIG_PADHOC_PASSWORD2"])
        // …but the remote *structure* is still defined.
        XCTAssertEqual(env["RCLONE_CONFIG_PADHOCB2_TYPE"], "b2")
        XCTAssertEqual(env["RCLONE_CONFIG_PADHOC_TYPE"], "crypt")
        XCTAssertEqual(env["RCLONE_CONFIG_PADHOC_REMOTE"], "padhocb2:my-bucket/files")
    }

    func testHardDeleteFalseIsHonored() {
        let env = RcloneService.makeEnvironment(for: cfg(hardDelete: false), secrets: secrets(),
                                                inheritedPATH: "/usr/bin", home: "/h")
        XCTAssertEqual(env["RCLONE_CONFIG_PADHOCB2_HARD_DELETE"], "false")
    }

    // MARK: - Argument builders

    func testCopyAndCopytoArguments() {
        // `--size-only` is REQUIRED: through a crypt remote rclone can't hash-match against B2, and
        // modtime is fragile (re-staging a source rewrites mtimes), so without it every file is
        // re-uploaded as "replaced existing" — re-sending the whole archive each run instead of the
        // delta. The store is additive/immutable, so size comparison is correct here.
        XCTAssertEqual(RcloneService.copyArguments(source: "/x/Foo", destRemotePath: "Foo"),
                       ["copy", "/x/Foo", "padhoc:Foo", "--size-only"])
        XCTAssertEqual(RcloneService.copytoArguments(source: "/x/a.pdf", destRemotePath: "a.pdf"),
                       ["copyto", "/x/a.pdf", "padhoc:a.pdf", "--size-only"])
    }

    func testLsjsonArguments() {
        let ls = RcloneService.lsjsonArguments()
        XCTAssertEqual(ls.first, "lsjson")
        XCTAssertTrue(ls.contains("padhoc:"))
        XCTAssertTrue(ls.contains("--recursive"))
        XCTAssertTrue(ls.contains("--files-only"))
        XCTAssertFalse(ls.contains("--hash"))
        XCTAssertTrue(RcloneService.lsjsonArguments(hash: true).contains("--hash"))
    }

    func testMoveArguments() {
        XCTAssertEqual(RcloneService.moveArguments(fromRemotePath: "a.pdf", toRemotePath: "b.pdf"),
                       ["moveto", "padhoc:a.pdf", "padhoc:b.pdf"])
    }

    func testDeleteArgumentsAreHardDelete() {
        let del = RcloneService.deleteArguments(remotePath: "a.pdf")
        XCTAssertEqual(del.first, "deletefile")
        XCTAssertTrue(del.contains("padhoc:a.pdf"))
        XCTAssertTrue(del.contains("--b2-hard-delete"), "a permanent delete must never silently degrade to a hide")
    }

    func testCheckArgumentsAreOneWayCombined() {
        let chk = RcloneService.checkArguments(localSource: "/x/Foo", remotePath: "Foo")
        XCTAssertEqual(chk.first, "check")
        XCTAssertTrue(chk.contains("/x/Foo"))
        XCTAssertTrue(chk.contains("padhoc:Foo"))
        XCTAssertTrue(chk.contains("--one-way"))
        XCTAssertTrue(chk.contains("--combined"))
        XCTAssertTrue(chk.contains("-"))
    }

    // MARK: - Outcome semantics (skip is NOT a failure)

    func testOutcomeFailureClassification() {
        XCTAssertFalse(RcloneService.Outcome.ok(detail: "x").isFailure)
        XCTAssertFalse(RcloneService.Outcome.skipped(reason: "offline").isFailure)
        XCTAssertTrue(RcloneService.Outcome.failed("boom").isFailure)
        XCTAssertEqual(RcloneService.Outcome.skipped(reason: "offline").detail, "skipped — offline")
    }

    // MARK: - Friendly error mapping (rclone stderr → actionable message)

    func testFriendlyErrorMapsAuthFailureToCredentialsHint() {
        let s = "2026/06/28 22:30:14 CRITICAL: Failed to create file system for \"padhocb2:adhoc-archive\": failed to authorize account: failed to authenticate: Unknown 401  (401 bad_auth_token)"
        let msg = RcloneService.friendlyError(s)
        XCTAssertTrue(msg.lowercased().contains("credential"),
                      "401 / bad_auth_token must map to a credentials hint, got: \(msg)")
    }

    func testFriendlyErrorMapsBucketNotFound() {
        XCTAssertTrue(RcloneService.friendlyError("ERROR: bucket not found").lowercased().contains("bucket"))
    }

    func testFriendlyErrorFallbackStripsTimestampAndLevel() {
        let s = "2026/01/01 00:00:00 NOTICE: loading\n2026/01/01 00:00:01 CRITICAL: directory not reachable somehow"
        let msg = RcloneService.friendlyError(s)
        XCTAssertFalse(msg.contains("CRITICAL"))
        XCTAssertFalse(msg.contains("2026/01/01"))
        XCTAssertFalse(msg.isEmpty)
    }

    // MARK: - Config validity + skip-when-unconfigured (no network touched)

    func testUnconfiguredConfigIsNotConfigured() {
        XCTAssertFalse(AdhocBackupConfig(bucket: "", keychainService: "").isConfigured)
        XCTAssertFalse(AdhocBackupConfig(bucket: "b", keychainService: "").isConfigured)
        XCTAssertTrue(AdhocBackupConfig(bucket: "b", keychainService: "s").isConfigured)
    }

    func testListSkipsWhenUnconfigured() {
        // An unconfigured store must SKIP (no network, no Keychain, no crash) regardless of whether
        // rclone is installed.
        let (files, outcome) = RcloneService.list(config: AdhocBackupConfig(bucket: "", keychainService: ""))
        XCTAssertTrue(files.isEmpty)
        if case .failed = outcome {
            // rclone-missing failure is acceptable here; the point is it never succeeds/hangs.
        } else if case .skipped = outcome {
            // expected when rclone is present but the store is unconfigured
        } else {
            XCTFail("expected .skipped or .failed for an unconfigured store, got \(outcome)")
        }
    }
}

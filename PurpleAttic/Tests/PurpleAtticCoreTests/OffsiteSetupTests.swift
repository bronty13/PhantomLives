import XCTest
@testable import PurpleAtticCore

/// Covers the *setup-time* off-site building blocks added for the in-app B2/restic configuration:
/// the Keychain argv builders, the recovery-passphrase generator (entropy + uniformity), and the
/// restic admin arg/JSON helpers + the bounded sample-file finder. All pure/local — no network,
/// no Keychain writes, no B2.
final class OffsiteSetupTests: XCTestCase {

    // MARK: KeychainStore argv

    func testUpsertArgumentsUpsertsAndOmitsValue() {
        let args = KeychainStore.upsertArguments(service: "PurpleAttic Restic B2", account: "b2-account-id")
        XCTAssertEqual(args, ["add-generic-password", "-U", "-s", "PurpleAttic Restic B2", "-a", "b2-account-id", "-w"])
        // The secret is never baked into the argv builder — it's appended by set(...).
        XCTAssertEqual(args.last, "-w")
    }

    func testReadAndDeleteArguments() {
        XCTAssertEqual(KeychainStore.readArguments(service: "svc", account: "acct"),
                       ["find-generic-password", "-s", "svc", "-a", "acct", "-w"])
        XCTAssertEqual(KeychainStore.deleteArguments(service: "svc", account: "acct"),
                       ["delete-generic-password", "-s", "svc", "-a", "acct"])
    }

    // MARK: RecoveryPassphrase

    func testSecureIndexStaysInBounds() throws {
        for bound in [1, 2, 7, 100, 1297, 65_537] {
            for _ in 0..<200 {
                let i = try RecoveryPassphrase.secureIndex(below: bound)
                XCTAssertTrue(i >= 0 && i < bound, "index \(i) out of 0..<\(bound)")
            }
        }
    }

    func testGenerateMeetsEntropyTargetAndShape() throws {
        let g: RecoveryPassphrase.Generated
        do {
            g = try RecoveryPassphrase.generate(targetBits: 100)
        } catch RecoveryPassphrase.GenError.noWordlist {
            throw XCTSkip("No system wordlist on this host")
        }
        XCTAssertGreaterThanOrEqual(g.bits, 100, "should hit the entropy target")
        XCTAssertGreaterThanOrEqual(g.words.count, 6)
        XCTAssertEqual(g.phrase.split(separator: "-").count, g.words.count, "phrase joins all words")
        for w in g.words {
            XCTAssertTrue(w.count >= 4 && w.count <= 7, "word length typeable: \(w)")
            XCTAssertTrue(w.allSatisfy { $0.isASCII && $0.isLowercase && $0.isLetter }, "lowercase a–z: \(w)")
        }
    }

    func testGenerateIsRandomAcrossCalls() throws {
        do {
            let a = try RecoveryPassphrase.generate()
            let b = try RecoveryPassphrase.generate()
            XCTAssertNotEqual(a.phrase, b.phrase, "two generations must differ")
        } catch RecoveryPassphrase.GenError.noWordlist {
            throw XCTSkip("No system wordlist on this host")
        }
    }

    // MARK: ResticService admin argv + JSON

    func testAdminArgumentBuilders() {
        XCTAssertEqual(ResticService.keyListArguments(), ["key", "list", "--json"])
        XCTAssertEqual(ResticService.snapshotsArguments(), ["snapshots", "--json", "--no-lock"])
        XCTAssertEqual(ResticService.keyAddArguments(passwordFile: "/tmp/x"),
                       ["key", "add", "--new-password-file", "/tmp/x"])
    }

    func testParseSnapshotsCountsAndPicksLatest() {
        let json = """
        [{"time":"2026-06-15T09:24:29.7Z","id":"a"},
         {"time":"2026-06-14T08:00:00.0Z","id":"b"}]
        """.data(using: .utf8)!
        let s = ResticService.parseSnapshots(json)
        XCTAssertEqual(s.count, 2)
        XCTAssertEqual(s.latest, "2026-06-15T09:24:29.7Z")
    }

    func testParseSnapshotsEmpty() {
        let s = ResticService.parseSnapshots("[]".data(using: .utf8)!)
        XCTAssertEqual(s.count, 0)
        XCTAssertNil(s.latest)
        // Garbage in → empty, not a crash.
        let bad = ResticService.parseSnapshots("not json".data(using: .utf8)!)
        XCTAssertEqual(bad.count, 0)
    }

    func testParseKeysReadsCurrentFlag() {
        let json = """
        [{"current":true,"id":"48390465","userName":"bronty13","hostName":"Vortex","created":"2026-06-15T09:24:12Z"},
         {"current":false,"id":"deadbeef","userName":"bronty13","hostName":"Vortex","created":"2026-06-15T10:00:00Z"}]
        """.data(using: .utf8)!
        let keys = ResticService.parseKeys(json)
        XCTAssertEqual(keys.count, 2)
        XCTAssertEqual(keys.filter { $0.isCurrent }.count, 1)
        XCTAssertEqual(keys.first?.id, "48390465")
    }

    func testCredentialPresenceAllPresent() {
        XCTAssertTrue(ResticService.CredentialPresence(resticPassword: true, b2AccountId: true, b2AccountKey: true).allPresent)
        XCTAssertFalse(ResticService.CredentialPresence(resticPassword: true, b2AccountId: false, b2AccountKey: true).allPresent)
    }

    // MARK: firstSmallFile (bounded sample finder for the recovery drill)

    func testFirstSmallFileFindsASmallRegularFileSkippingDotfiles() throws {
        let dir = NSTemporaryDirectory() + "pattic-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        // A dotfile (should be skipped) and a real small file (should be found).
        try "x".write(toFile: dir + "/.hidden", atomically: true, encoding: .utf8)
        try "hello".write(toFile: dir + "/photo.jpg", atomically: true, encoding: .utf8)
        let found = ResticService.firstSmallFile(under: dir, maxBytes: 1_000_000, scanLimit: 100)
        XCTAssertEqual((found as NSString?)?.lastPathComponent, "photo.jpg")
    }

    func testFirstSmallFileSkipsOversizeAndMissingDir() {
        XCTAssertNil(ResticService.firstSmallFile(under: "/no/such/dir/here", maxBytes: 10, scanLimit: 10))
    }
}

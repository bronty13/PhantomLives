import XCTest
@testable import PurpleAtticCore

final class FreeSpaceTests: XCTestCase {

    func testEstimateZeroWhenNoOriginals() {
        XCTAssertEqual(FreeSpaceCheck.estimatedRequiredBytes(originalsBytes: 0, keepHEIC: true, keepJPEG: true), 0)
    }

    func testEstimateOriginalsOnly() {
        // HEIC pass only ≈ originals × 1, plus 10% slack.
        let est = FreeSpaceCheck.estimatedRequiredBytes(originalsBytes: 1_000_000, keepHEIC: true, keepJPEG: false)
        XCTAssertEqual(est, 1_100_000)
    }

    func testEstimateBothPassesLargerThanOriginalsOnly() {
        let originals = FreeSpaceCheck.estimatedRequiredBytes(originalsBytes: 1_000_000, keepHEIC: true, keepJPEG: false)
        let both = FreeSpaceCheck.estimatedRequiredBytes(originalsBytes: 1_000_000, keepHEIC: true, keepJPEG: true)
        XCTAssertGreaterThan(both, originals, "adding the JPEG pass must raise the estimate")
        // 1.0 + 0.5 = 1.5×, +10% slack = 1.65×.
        XCTAssertEqual(both, 1_650_000)
    }

    func testSufficiencyAndUnmeasured() {
        let ok = FreeSpaceCheck.DestinationSpace(label: "Primary", base: "/x",
                                                 freeBytes: 2_000, requiredBytes: 1_000)
        XCTAssertTrue(ok.sufficient)
        XCTAssertFalse(ok.unmeasured)

        let tight = FreeSpaceCheck.DestinationSpace(label: "Primary", base: "/x",
                                                    freeBytes: 500, requiredBytes: 1_000)
        XCTAssertFalse(tight.sufficient)

        let unknown = FreeSpaceCheck.DestinationSpace(label: "Mirror 1", base: "/y",
                                                      freeBytes: nil, requiredBytes: 1_000)
        XCTAssertFalse(unknown.sufficient, "can't confirm space → treated as not sufficient")
        XCTAssertTrue(unknown.unmeasured)
    }

    func testEvaluateCoversPrimaryMirrorsAndVault() {
        var p = ArchiveProfile(name: "T", primaryDestination: "/Volumes/Primary",
                               mirrorDestinations: ["/Volumes/M1", "/Volumes/M2"])
        p.cloudVaultPath = "/Users/me/Vault"
        let spaces = FreeSpaceCheck.evaluate(profile: p, originalsBytes: 1_000_000)
        XCTAssertEqual(spaces.map { $0.label }, ["Primary", "Mirror 1", "Mirror 2", "Cloud vault"])
        // None of these volumes exist on a CI box → all unmeasured (nil), and required > 0.
        XCTAssertTrue(spaces.allSatisfy { $0.requiredBytes > 0 })
    }

    func testEvaluateSkipsBlankDestinations() {
        let p = ArchiveProfile(name: "T", primaryDestination: "", mirrorDestinations: [""])
        XCTAssertTrue(FreeSpaceCheck.evaluate(profile: p, originalsBytes: 1_000_000).isEmpty)
    }

    func testFreeBytesNilForUnmountedPath() {
        XCTAssertNil(FreeSpaceCheck.freeBytes(atVolumePath: "/Volumes/DefinitelyNotMounted-PurpleAttic-xyz"))
        XCTAssertNil(FreeSpaceCheck.freeBytes(atVolumePath: "   "))
    }

    func testFreeBytesPositiveForRealPath() throws {
        // The temp dir always exists and is on a real volume.
        let free = FreeSpaceCheck.freeBytes(atVolumePath: FileManager.default.temporaryDirectory.path)
        XCTAssertNotNil(free)
        XCTAssertGreaterThan(free ?? 0, 0)
    }
}

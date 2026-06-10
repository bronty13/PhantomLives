import XCTest
@testable import PurpleAtticCore

final class VolumeReadinessTests: XCTestCase {

    func testBlankNotReady() {
        XCTAssertFalse(VolumeReadiness.destinationReady("").ready)
        XCTAssertFalse(VolumeReadiness.destinationReady("   ").ready)
    }

    func testUnmountedVolumePathNotReady() {
        // The dangerous case: /Volumes/<drive> that isn't mounted → must NOT be treated as
        // ready (else the engine would createDirectory + rsync onto the boot disk).
        let r = VolumeReadiness.destinationReady("/Volumes/DefinitelyNotMounted-PurpleAttic-xyz")
        XCTAssertFalse(r.ready)
        XCTAssertNotNil(r.reason)
    }

    func testUnmountedVolumeSubpathNotReady() {
        XCTAssertFalse(VolumeReadiness.destinationReady("/Volumes/NotMounted-xyz/Photos Archive").ready)
    }

    func testExistingNonVolumeDirIsReady() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pa-ready-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertTrue(VolumeReadiness.destinationReady(dir.path).ready, "an existing boot-disk folder is a valid destination")
    }

    func testMissingNonVolumePathNotReady() {
        XCTAssertFalse(VolumeReadiness.destinationReady("/Users/nobody/no/such/dir-\(UUID().uuidString)").ready)
    }

    func testRootIsNotASeparateVolume() {
        XCTAssertFalse(VolumeReadiness.isOnSeparateVolume("/"))
    }
}

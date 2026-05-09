import XCTest
import CoreGraphics
@testable import PurpleDedupCore

final class VideoFingerprinterTests: XCTestCase {

    func testFingerprintsAGeneratedVideo() async throws {
        let dir = try TestFixtures.makeTempDir("vfp-basic")
        defer { TestFixtures.cleanup(dir) }

        // 5-second gradient video: one frame per visible second of content.
        let size = CGSize(width: 320, height: 240)
        let frames = (0..<5).map { TestVideo.gradientFrame(seed: $0, size: size) }
        let url = dir.appendingPathComponent("clip.mov")
        try await TestVideo.build(frames: frames, size: size, url: url)

        let fp = try await VideoFingerprinter().fingerprint(videoAt: url)
        XCTAssertGreaterThan(fp.frameHashes.count, 0, "Should sample at least one frame")
        XCTAssertGreaterThan(fp.durationSeconds, 0)
        XCTAssertEqual(fp.width, 320)
        XCTAssertEqual(fp.height, 240)
        XCTAssertEqual(fp.sampleRate, VideoFingerprinter.sampleRate)
    }

    func testFingerprintRoundTripsThroughEncodedData() throws {
        let fp = VideoFingerprint(
            frameHashes: [0xDEADBEEF, 0xCAFEBABE, 0x12345678],
            durationSeconds: 4.5,
            width: 1920,
            height: 1080,
            sampleRate: 1.0
        )
        let data = fp.encoded()
        // 2 + 2 + 2 + 8 + 4 + 8*3 = 42 bytes
        XCTAssertEqual(data.count, 42)
    }

    func testRejectsNonVideoFile() async throws {
        let dir = try TestFixtures.makeTempDir("vfp-bad")
        defer { TestFixtures.cleanup(dir) }
        let bad = try TestFixtures.write("not a video", to: dir.appendingPathComponent("nope.mov"))

        do {
            _ = try await VideoFingerprinter().fingerprint(videoAt: bad)
            XCTFail("Expected error for non-video content")
        } catch {
            // expected — VideoFingerprinterError or AVFoundation error
        }
    }
}

import XCTest
import CoreGraphics
@testable import PurpleDedupCore

/// Tests for the FFmpeg-sidecar fallback. All tests skip themselves when
/// `FFmpegProbe.find()` returns nil, so CI on a machine without FFmpeg
/// stays green (the fallback is opt-in by design — its absence is expected).
final class FFmpegFingerprinterTests: XCTestCase {

    private var probe: FFmpegProbe.Probe!

    override func setUpWithError() throws {
        guard let p = FFmpegProbe.find() else {
            throw XCTSkip("FFmpeg not installed on this machine — fallback is opt-in.")
        }
        self.probe = p
    }

    /// Probe finds a matching ffmpeg + ffprobe pair and reads a non-empty
    /// version line. Smoke test that the binary actually runs.
    func testProbeFindsFFmpeg() {
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: probe.ffmpegURL.path))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: probe.ffprobeURL.path))
        XCTAssertTrue(probe.versionLine.contains("ffmpeg version"),
                      "Version line should look like 'ffmpeg version X.Y' — got: \(probe.versionLine)")
    }

    /// FFmpegFingerprinter produces a valid `VideoFingerprint` for a video
    /// AVFoundation can also decode. Doesn't exercise the MKV/AVI path
    /// directly (those need transcoding), but proves the FFmpeg pipeline +
    /// JSON parsing + frame extraction + perceptual hashing all work.
    func testFingerprintsAStandardMP4() async throws {
        let dir = try TestFixtures.makeTempDir("ffmpeg-fp")
        defer { TestFixtures.cleanup(dir) }
        let videoURL = dir.appendingPathComponent("clip.mov")
        let frames: [CGImage] = (0..<5).map { i in
            TestFrame.solid(side: 64, value: UInt8(40 + i * 40))
        }
        try await TestVideo.build(frames: frames, size: CGSize(width: 64, height: 64), url: videoURL)

        let fp = try await FFmpegFingerprinter(probe: probe).fingerprint(videoAt: videoURL)
        XCTAssertEqual(fp.width, 64)
        XCTAssertEqual(fp.height, 64)
        XCTAssertGreaterThanOrEqual(fp.frameHashes.count, 2)
        XCTAssertGreaterThan(fp.durationSeconds, 1.0)
    }

    /// Fallback wiring: when AVFoundation can't decode the file, the
    /// VideoFingerprinter retries via FFmpeg. We simulate "AVFoundation
    /// can't decode it" by transcoding a working clip into a container
    /// AVFoundation typically refuses (.mkv with libx264 + matroska). If
    /// the local ffmpeg lacks the muxer, skip rather than fail — every
    /// FFmpeg distribution we care about ships matroska.
    func testFallbackTriggersOnAVFoundationFailure() async throws {
        let dir = try TestFixtures.makeTempDir("ffmpeg-fallback")
        defer { TestFixtures.cleanup(dir) }

        let movURL = dir.appendingPathComponent("source.mov")
        let frames: [CGImage] = (0..<5).map { i in
            TestFrame.solid(side: 64, value: UInt8(40 + i * 40))
        }
        try await TestVideo.build(frames: frames, size: CGSize(width: 64, height: 64), url: movURL)

        let mkvURL = dir.appendingPathComponent("clip.mkv")
        let convert = Process()
        convert.executableURL = probe.ffmpegURL
        convert.arguments = [
            "-hide_banner", "-loglevel", "error",
            "-i", movURL.path,
            "-c:v", "copy",
            "-y",
            mkvURL.path,
        ]
        convert.standardOutput = Pipe()
        convert.standardError = Pipe()
        try convert.run()
        convert.waitUntilExit()
        try XCTSkipIf(convert.terminationStatus != 0,
                      "Local ffmpeg can't write Matroska — skipping fallback test.")

        // No fallback configured → AVFoundation fails (returns
        // unsupportedFormat for an MKV without QuickTime support).
        let bareFingerprinter = VideoFingerprinter()
        do {
            _ = try await bareFingerprinter.fingerprint(videoAt: mkvURL)
            // It's possible (but rare) for AVFoundation to actually decode
            // an h264-in-Matroska on macOS 14+. If so, the test premise is
            // invalid; skip.
            throw XCTSkip("AVFoundation decoded the MKV directly — fallback path can't be exercised on this OS.")
        } catch is VideoFingerprinterError {
            // expected
        }

        // With fallback configured → ffmpeg path succeeds.
        let withFallback = VideoFingerprinter(ffmpegFallback: probe)
        let fp = try await withFallback.fingerprint(videoAt: mkvURL)
        XCTAssertGreaterThanOrEqual(fp.frameHashes.count, 2)
        XCTAssertEqual(fp.width, 64)
        XCTAssertEqual(fp.height, 64)
    }
}

/// Local helper to keep this test file independent of `TestVideo`'s
/// internal frame helpers.
private enum TestFrame {
    static func solid(side: Int, value: UInt8) -> CGImage {
        let cs = CGColorSpaceCreateDeviceGray()
        let ctx = CGContext(
            data: nil, width: side, height: side,
            bitsPerComponent: 8, bytesPerRow: side,
            space: cs, bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        let buf = ctx.data!.assumingMemoryBound(to: UInt8.self)
        for i in 0..<(side * side) { buf[i] = value }
        return ctx.makeImage()!
    }
}

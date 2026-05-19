import XCTest
@testable import PurpleReel

/// Foundation coverage for the composable `TranscodeOptions` value
/// type. Verifies defaults, equality, and Codable round-trip so the
/// model can carry custom-preset persistence + the new Convert
/// dialog's edit state without surprise.
final class TranscodeOptionsTests: XCTestCase {

    func testDefaultsAreCopyChannelsInMOVContainer() {
        let o = TranscodeOptions()
        XCTAssertEqual(o.container, .mov)
        XCTAssertEqual(o.video, .copy)
        XCTAssertEqual(o.audio, .copy)
        XCTAssertEqual(o.trimming, .none)
        XCTAssertFalse(o.filters.denoise)
        XCTAssertEqual(o.filters.fadeInSeconds, 0)
        XCTAssertEqual(o.filters.fadeOutSeconds, 0)
        XCTAssertEqual(o.cameraLUT, .none)
        XCTAssertEqual(o.creativeLUT, .none)
        XCTAssertFalse(o.overlays.timecodeEnabled)
        XCTAssertEqual(o.overlays.timecodePosition, .bottomCenter)
        XCTAssertTrue(o.containerSettings.streamable)
    }

    func testEqualityIsValueWise() {
        let a = TranscodeOptions()
        let b = TranscodeOptions()
        XCTAssertEqual(a, b)
        var c = a
        c.trimming = .inToOut
        XCTAssertNotEqual(a, c)
    }

    /// Round-trip via JSONEncoder/Decoder — every nested type must be
    /// Codable so the eventual "Save as preset…" path can persist
    /// without manual serialization plumbing.
    func testJSONRoundTripPreservesEveryField() throws {
        var o = TranscodeOptions()
        o.container = .mp4
        o.video = .reencode(.defaultH264)
        o.audio = .reencode(.defaultAAC)
        o.filters.denoise = true
        o.filters.fadeInSeconds = 1.5
        o.filters.fadeOutSeconds = 2.0
        o.cameraLUT = .file(path: "/Users/x/cube.cube")
        o.creativeLUT = .asDefinedInPlayer
        o.overlays.timecodeEnabled = true
        o.overlays.timecodePosition = .topRight
        o.overlays.timecodeOpacity = 0.6
        o.containerSettings.embedXMPMetadata = true
        o.containerSettings.keepSourceTimestamps = true
        o.containerSettings.timecodeSource = .zeroBased
        o.trimming = .inToOut

        let data = try JSONEncoder().encode(o)
        let back = try JSONDecoder().decode(TranscodeOptions.self, from: data)
        XCTAssertEqual(o, back)
    }

    func testH264DefaultIsBitrate10000kbps() {
        guard case .bitrate(let kbps) = VideoEncoding.defaultH264.quality
        else { return XCTFail("Expected bitrate quality on default H.264") }
        XCTAssertEqual(kbps, 10_000)
        XCTAssertEqual(VideoEncoding.defaultH264.codec, .h264)
        XCTAssertEqual(VideoEncoding.defaultH264.frameRate, .likeSource)
        XCTAssertEqual(VideoEncoding.defaultH264.size, .likeSource)
    }

    func testProResDefaultIsCodecDefaultQuality() {
        XCTAssertEqual(VideoEncoding.defaultProRes422.quality, .codecDefault)
        XCTAssertEqual(VideoEncoding.defaultProRes422.codec, .prores422)
    }

    func testAACDefaultIs48k192kbps() {
        XCTAssertEqual(AudioEncoding.defaultAAC.codec, .aac)
        XCTAssertEqual(AudioEncoding.defaultAAC.sampleRate, 48_000)
        XCTAssertEqual(AudioEncoding.defaultAAC.bitrateKbps, 192)
    }

    /// Apple-native flag drives the encoder-backend routing in C3.
    /// H.264 / HEVC / ProRes family all native; DNxHD / Cineform /
    /// WebM / FLV / WMV all go to ffmpeg.
    func testIsAppleNativeRoutingClassification() {
        XCTAssertTrue(VideoCodec.h264.isAppleNative)
        XCTAssertTrue(VideoCodec.hevc.isAppleNative)
        XCTAssertTrue(VideoCodec.prores422.isAppleNative)
        XCTAssertTrue(VideoCodec.prores422hq.isAppleNative)
        XCTAssertTrue(VideoCodec.prores4444.isAppleNative)
        XCTAssertFalse(VideoCodec.dnxhd.isAppleNative)
        XCTAssertFalse(VideoCodec.dnxhr.isAppleNative)
        XCTAssertFalse(VideoCodec.cineform.isAppleNative)
        XCTAssertFalse(VideoCodec.vp8.isAppleNative)
        XCTAssertFalse(VideoCodec.vp9.isAppleNative)
        XCTAssertFalse(VideoCodec.flashVideo.isAppleNative)
        XCTAssertFalse(VideoCodec.wmv.isAppleNative)
    }

    func testNinePositionOverlayCasesCoverFullGrid() {
        let positions = OverlayPosition.allCases
        XCTAssertEqual(positions.count, 9)
        XCTAssertTrue(positions.contains(.topLeft))
        XCTAssertTrue(positions.contains(.center))
        XCTAssertTrue(positions.contains(.bottomRight))
    }

    func testAudioOnlyContainerExtensionDefersToCodec() {
        // The audio-only container's extension is empty — the audio
        // codec drives the filename suffix (.wav / .m4a / .mp3 / …).
        XCTAssertEqual(ContainerFormat.audioOnly.fileExtension, "")
    }
}

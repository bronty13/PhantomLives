import XCTest
import AVFoundation
@testable import PurpleReel

/// Coverage for `TranscodeOptions.resolveBackend()` — the C3 bridge
/// from the composable spec to the runtime that `TranscodeJob`
/// already executes (AVAssetExportSession preset name vs ffmpeg argv).
final class TranscodeOptionsResolverTests: XCTestCase {

    // MARK: - Pass-through

    func testCopyCopyResolvesToPassthroughPreset() {
        let opts = TranscodeOptions(container: .mov,
                                     video: .copy,
                                     audio: .copy)
        guard case .avAssetExport(let name, let ext, let always)
                = opts.resolveBackend()
        else { return XCTFail("Expected avAssetExport result") }
        XCTAssertEqual(name, AVAssetExportPresetPassthrough)
        XCTAssertEqual(ext, "mov")
        XCTAssertTrue(always,
                       "Passthrough is always available — no compatibility probe needed")
    }

    func testCopyCopyMP4ResolvesToPassthroughInMP4() {
        let opts = TranscodeOptions(container: .mp4,
                                     video: .copy,
                                     audio: .copy)
        guard case .avAssetExport(_, let ext, _) = opts.resolveBackend()
        else { return XCTFail() }
        XCTAssertEqual(ext, "mp4")
    }

    // MARK: - Apple-native video routing

    func testH264_1080PixelSizePicksApple1920x1080Preset() {
        var opts = TranscodeOptions()
        opts.video = .reencode(VideoEncoding(
            codec: .h264, profile: .auto,
            frameRate: .likeSource,
            size: .fixed(width: 1920, height: 1080),
            displayAspectRatio: .physical, rotation: .automatic,
            fieldType: .progressive,
            quality: .bitrate(kbps: 10_000)
        ))
        guard case .avAssetExport(let name, _, _) = opts.resolveBackend()
        else { return XCTFail() }
        XCTAssertEqual(name, AVAssetExportPreset1920x1080)
    }

    func testH264_4KSizePicksApple3840x2160Preset() {
        var opts = TranscodeOptions()
        opts.video = .reencode(VideoEncoding(
            codec: .h264, profile: .auto,
            frameRate: .likeSource,
            size: .fixed(width: 3840, height: 2160),
            displayAspectRatio: .physical, rotation: .automatic,
            fieldType: .progressive,
            quality: .bitrate(kbps: 50_000)
        ))
        guard case .avAssetExport(let name, _, _) = opts.resolveBackend()
        else { return XCTFail() }
        XCTAssertEqual(name, AVAssetExportPreset3840x2160)
    }

    func testH264_LikeSourcePicksHighestQuality() {
        var opts = TranscodeOptions()
        opts.video = .reencode(VideoEncoding.defaultH264)
        guard case .avAssetExport(let name, _, _) = opts.resolveBackend()
        else { return XCTFail() }
        XCTAssertEqual(name, AVAssetExportPresetHighestQuality)
    }

    func testHEVC_4KPicksHEVC3840x2160Preset() {
        var opts = TranscodeOptions()
        opts.video = .reencode(VideoEncoding(
            codec: .hevc, profile: .auto,
            frameRate: .likeSource,
            size: .fixed(width: 3840, height: 2160),
            displayAspectRatio: .physical, rotation: .automatic,
            fieldType: .progressive, quality: .codecDefault
        ))
        guard case .avAssetExport(let name, _, _) = opts.resolveBackend()
        else { return XCTFail() }
        XCTAssertEqual(name, AVAssetExportPresetHEVC3840x2160)
    }

    func testProRes422PicksAppleProRes422LPCM() {
        var opts = TranscodeOptions()
        opts.video = .reencode(VideoEncoding.defaultProRes422)
        guard case .avAssetExport(let name, let ext, let always)
                = opts.resolveBackend()
        else { return XCTFail() }
        XCTAssertEqual(name, AVAssetExportPresetAppleProRes422LPCM)
        XCTAssertEqual(ext, "mov")
        XCTAssertTrue(always, "ProRes 422 is always available on macOS")
    }

    /// ProRes 422 HQ/LT/Proxy have no AVAssetExportSession constant on
    /// macOS — must fall through to ffmpeg's `prores_ks`.
    func testProRes422HQFallsThroughToFFmpeg() {
        var opts = TranscodeOptions()
        opts.video = .reencode(VideoEncoding(
            codec: .prores422hq, profile: .auto,
            frameRate: .likeSource, size: .likeSource,
            displayAspectRatio: .physical, rotation: .automatic,
            fieldType: .progressive, quality: .codecDefault
        ))
        guard case .ffmpeg(let args, _) = opts.resolveBackend()
        else { return XCTFail("Expected ffmpeg fallback for ProRes HQ") }
        XCTAssertTrue(args.contains("prores_ks"))
        XCTAssertTrue(args.contains("3"), "ProRes HQ is prores_ks profile 3")
    }

    // MARK: - ffmpeg routing for non-Apple codecs

    func testDNxHRRoutesToFFmpegWithDnxhdEncoderAndProfile() {
        var opts = TranscodeOptions()
        opts.video = .reencode(VideoEncoding(
            codec: .dnxhr, profile: .dnxhr_hq,
            frameRate: .fixed(23.976), size: .likeSource,
            displayAspectRatio: .physical, rotation: .automatic,
            fieldType: .progressive, quality: .codecDefault
        ))
        guard case .ffmpeg(let args, _) = opts.resolveBackend()
        else { return XCTFail() }
        XCTAssertTrue(args.contains("dnxhd"),
                       "DNxHR uses ffmpeg's `dnxhd` encoder")
        XCTAssertTrue(args.contains("dnxhr_hq"))
        XCTAssertTrue(args.contains("yuv422p"))
        XCTAssertTrue(args.contains("{IN}"))
        XCTAssertTrue(args.contains("{OUT}"))
    }

    func testVP9RoutesToFFmpegWithLibvpxVP9AndWebMExtension() {
        var opts = TranscodeOptions()
        opts.video = .reencode(VideoEncoding(
            codec: .vp9, profile: .auto,
            frameRate: .likeSource, size: .likeSource,
            displayAspectRatio: .physical, rotation: .automatic,
            fieldType: .progressive, quality: .bitrate(kbps: 2000)
        ))
        opts.audio = .reencode(AudioEncoding(
            codec: .vorbis, sampleRate: 48_000, bitrateKbps: 192
        ))
        guard case .ffmpeg(let args, let ext) = opts.resolveBackend()
        else { return XCTFail() }
        XCTAssertTrue(args.contains("libvpx-vp9"))
        XCTAssertTrue(args.contains("2000k"),
                       "Bitrate quality should pass through as -b:v")
        XCTAssertEqual(ext, "webm")
    }

    // MARK: - Audio-only output

    func testAudioOnlyWavRoutesToFFmpegWithVnAndPCM() {
        var opts = TranscodeOptions(container: .audioOnly)
        opts.audio = .reencode(AudioEncoding(
            codec: .pcm16, sampleRate: 48_000, bitrateKbps: 0
        ))
        guard case .ffmpeg(let args, let ext) = opts.resolveBackend()
        else { return XCTFail() }
        XCTAssertTrue(args.contains("-vn"),
                       "Audio-only must disable video stream")
        XCTAssertTrue(args.contains("pcm_s16le"))
        XCTAssertEqual(ext, "wav")
    }

    func testAudioOnlyMP3CarriesBitrateAndExtension() {
        var opts = TranscodeOptions(container: .audioOnly)
        opts.audio = .reencode(AudioEncoding(
            codec: .mp3, sampleRate: 44_100, bitrateKbps: 256
        ))
        guard case .ffmpeg(let args, let ext) = opts.resolveBackend()
        else { return XCTFail() }
        XCTAssertTrue(args.contains("libmp3lame"))
        XCTAssertTrue(args.contains("256k"))
        XCTAssertEqual(ext, "mp3")
    }

    // MARK: - Filter chain

    func testFixedSizeEmitsScaleFilter() {
        var opts = TranscodeOptions(container: .mp4)
        opts.video = .reencode(VideoEncoding(
            codec: .vp9, profile: .auto,
            frameRate: .likeSource,
            size: .fixed(width: 1280, height: 720),
            displayAspectRatio: .physical, rotation: .automatic,
            fieldType: .progressive, quality: .codecDefault
        ))
        guard case .ffmpeg(let args, _) = opts.resolveBackend()
        else { return XCTFail() }
        XCTAssertTrue(args.contains("-vf"))
        let vfIdx = args.firstIndex(of: "-vf")!
        XCTAssertEqual(args[args.index(after: vfIdx)], "scale=1280:720")
    }

    func testHalfScaleEmitsCustomScaleExpression() {
        var opts = TranscodeOptions(container: .mov)
        opts.video = .reencode(VideoEncoding(
            codec: .vp9, profile: .auto,
            frameRate: .likeSource,
            size: .scale(0.5),
            displayAspectRatio: .physical, rotation: .automatic,
            fieldType: .progressive, quality: .codecDefault
        ))
        guard case .ffmpeg(let args, _) = opts.resolveBackend()
        else { return XCTFail() }
        XCTAssertTrue(args.contains("-vf"))
        // Half-resolution scale picks the even-rounding form.
        XCTAssertTrue(args.contains("scale='trunc(iw/2.0/2)*2':-2"))
    }
}

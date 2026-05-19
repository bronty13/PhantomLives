import XCTest
@testable import PurpleReel

/// Coverage for the C5 preset → TranscodeOptions translator
/// (`TranscodePreset.defaultOptions()`). Each Convert-dialog Settings…
/// sheet binds against the resolved options, so a wrong mapping
/// would surface "Copy" everywhere instead of the preset's real
/// encoding shape.
final class PresetDefaultOptionsTests: XCTestCase {

    // MARK: - Apple-native presets

    func testH264_1080PresetMapsToH264Reencode() {
        let h264 = TranscodePreset.all.first { $0.id == "h264-1080p" }!
        let opts = h264.defaultOptions()
        guard case .reencode(let e) = opts.video
        else { return XCTFail("Expected video re-encode for H.264 preset") }
        XCTAssertEqual(e.codec, .h264)
        XCTAssertEqual(e.size, .fixed(width: 1920, height: 1080))
        XCTAssertEqual(opts.container, .mp4)
    }

    func testHEVC_1080PresetMapsToHEVCReencode() {
        let hevc = TranscodePreset.all.first { $0.id == "hevc-1080p" }!
        let opts = hevc.defaultOptions()
        guard case .reencode(let e) = opts.video
        else { return XCTFail("Expected video re-encode for HEVC preset") }
        XCTAssertEqual(e.codec, .hevc)
        XCTAssertEqual(e.size, .fixed(width: 1920, height: 1080))
    }

    func testProRes422PresetMapsToProRes422Reencode() {
        let p = TranscodePreset.all.first { $0.id == "prores-422" }!
        let opts = p.defaultOptions()
        guard case .reencode(let e) = opts.video
        else { return XCTFail() }
        XCTAssertEqual(e.codec, .prores422)
        XCTAssertEqual(opts.container, .mov)
    }

    func testPassthroughPresetMapsToCopyCopy() {
        let p = TranscodePreset.all.first { $0.id == "passthrough" }!
        let opts = p.defaultOptions()
        XCTAssertEqual(opts.video, .copy)
        XCTAssertEqual(opts.audio, .copy)
    }

    // MARK: - ffmpeg presets

    func testDNxHR_SQPresetMapsToDNxHRReencode() {
        let p = TranscodePreset.all.first { $0.id == "dnxhr-sq" }!
        let opts = p.defaultOptions()
        guard case .reencode(let e) = opts.video
        else { return XCTFail("Expected DNxHR re-encode") }
        XCTAssertEqual(e.codec, .dnxhr,
                        "ffmpeg presets with `-profile:v dnxhr_*` route to .dnxhr")
    }

    func testCineformPresetMapsToCineformReencode() {
        let p = TranscodePreset.all.first { $0.id == "cineform" }!
        let opts = p.defaultOptions()
        guard case .reencode(let e) = opts.video
        else { return XCTFail() }
        XCTAssertEqual(e.codec, .cineform)
    }

    func testProResProxyPresetMapsToProResProxyViaPrioFile() {
        // PresetCatalog.editing-prores-proxy uses ffmpeg's prores_ks
        // with -profile:v 0; the mapper should recognize that as the
        // Proxy variant.
        let p = (TranscodePreset.all + PresetCatalog.extended)
            .first { $0.id == "editing-prores-proxy" }!
        let opts = p.defaultOptions()
        guard case .reencode(let e) = opts.video
        else { return XCTFail() }
        XCTAssertEqual(e.codec, .prores422proxy)
    }

    // MARK: - Audio-only presets

    func testWavAudioPresetMapsToAudioOnlyContainerAndPCM16() {
        let p = PresetCatalog.extended.first { $0.id == "audio-wav16" }!
        let opts = p.defaultOptions()
        XCTAssertEqual(opts.container, .audioOnly)
        XCTAssertEqual(opts.video, .disabled,
                        "-vn in ffmpeg recipe disables the video channel")
        guard case .reencode(let a) = opts.audio
        else { return XCTFail("Audio channel should be re-encode") }
        XCTAssertEqual(a.codec, .pcm16)
    }

    func testM4APresetCarriesAACBitrate() {
        let p = PresetCatalog.extended.first { $0.id == "audio-m4a192" }!
        let opts = p.defaultOptions()
        guard case .reencode(let a) = opts.audio else { return XCTFail() }
        XCTAssertEqual(a.codec, .aac)
        XCTAssertEqual(a.bitrateKbps, 192)
    }

    // MARK: - DNxHD bitrate extraction

    func testDNxHDPresetCarriesBitrate() {
        let p = PresetCatalog.extended.first { $0.id == "dnxhd-1080p2997-220" }!
        let opts = p.defaultOptions()
        guard case .reencode(let e) = opts.video else { return XCTFail() }
        XCTAssertEqual(e.codec, .dnxhd,
                        "ffmpeg dnxhd preset without dnxhr_* profile stays DNxHD")
        guard case .bitrate(let kbps) = e.quality else {
            return XCTFail("Expected bitrate quality")
        }
        XCTAssertEqual(kbps, 220_000,
                        "220M ffmpeg arg should parse as 220 000 kbit/s")
    }

    // MARK: - Round-trip

    /// Every preset in the combined catalog must produce a non-default
    /// TranscodeOptions — `TranscodeOptions()` is the "Copy/Copy MOV"
    /// fallback, which is only correct for the passthrough preset.
    /// Any other preset that lands on the default suggests the mapper
    /// missed a codec.
    func testEveryNonPassthroughPresetMapsToNonDefault() {
        let defaultOpts = TranscodeOptions()
        for preset in TranscodePreset.combined() {
            if preset.id == "passthrough" { continue }
            // Rewrap presets ARE legitimately copy/copy — they just
            // change container, not encoding.
            if preset.category == .rewrap { continue }
            let opts = preset.defaultOptions()
            XCTAssertNotEqual(opts, defaultOpts,
                               "Preset \(preset.id) maps to default TranscodeOptions — codec mapper missed it")
        }
    }
}

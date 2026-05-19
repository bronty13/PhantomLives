import XCTest
import AVFoundation
@testable import PurpleReel

/// Coverage for the C18 audio-only path in Combine Clips. The
/// service skips the video track entirely when the preset's
/// `isAudioOnly` is true, so the catalogue needs to flag m4a + WAV
/// + AIFF correctly. Export-session-level integration (verifying
/// the .m4a actually plays) is left to manual QA — these tests
/// pin the catalogue rules.
final class AudioOnlyPresetTests: XCTestCase {

    func testM4APresetExistsInCatalogueAndIsAudioOnly() {
        let preset = TranscodePreset.all.first { $0.id == "m4a-audio-only" }
        XCTAssertNotNil(preset, "Expected `m4a-audio-only` in TranscodePreset.all")
        XCTAssertTrue(preset?.isAudioOnly == true,
                       "`m4a-audio-only` must be flagged isAudioOnly")
        XCTAssertEqual(preset?.fileExtension, "m4a")
        XCTAssertEqual(preset?.category, .audio)
        XCTAssertEqual(preset?.avPresetName, AVAssetExportPresetAppleM4A)
    }

    func testVideoPresetsAreNotMarkedAudioOnly() {
        for id in ["h264-1080p", "h264-720p", "hevc-1080p",
                   "prores-422", "prores-422-proxy", "passthrough"] {
            let p = TranscodePreset.all.first { $0.id == id }!
            XCTAssertFalse(p.isAudioOnly,
                            "Video preset \(id) must not be marked isAudioOnly")
        }
    }

    /// `isAudioOnly` is checked against multiple inputs (category,
    /// avPresetName, fileExtension) so a future WAV / AIFF preset
    /// — once we add one — picks up the audio-only treatment without
    /// the service needing to learn another constant. Verify the
    /// extension-based fallback path so the rule is documented.
    func testWAVAndAIFFExtensionsFallBackToAudioOnly() {
        let wavPreset = TranscodePreset(
            id: "wav-test", name: "WAV test",
            avPresetName: AVAssetExportPresetPassthrough,
            fileExtension: "wav", suffix: "_wav",
            category: .editing,
            alwaysAvailable: true, ffmpegArgs: nil
        )
        XCTAssertTrue(wavPreset.isAudioOnly,
                       "fileExtension == wav should imply isAudioOnly")

        let aiffPreset = TranscodePreset(
            id: "aiff-test", name: "AIFF test",
            avPresetName: AVAssetExportPresetPassthrough,
            fileExtension: "aiff", suffix: "_aiff",
            category: .editing,
            alwaysAvailable: true, ffmpegArgs: nil
        )
        XCTAssertTrue(aiffPreset.isAudioOnly,
                       "fileExtension == aiff should imply isAudioOnly")
    }
}

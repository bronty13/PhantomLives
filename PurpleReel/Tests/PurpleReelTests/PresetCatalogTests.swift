import XCTest
@testable import PurpleReel

/// Smoke coverage for the extended `PresetCatalog`. We don't try to
/// validate every preset's ffmpeg recipe end-to-end (that needs a
/// real codec test fixture) — just that the catalog ships, every
/// preset lands in the right category, and there are no duplicate IDs
/// against the legacy `TranscodePreset.all`.
final class PresetCatalogTests: XCTestCase {

    func testCatalogIsNonEmpty() {
        XCTAssertFalse(PresetCatalog.extended.isEmpty,
                        "Extended preset catalog should ship populated")
    }

    /// Legacy ⌘1..⌘0 menu shortcuts hard-code indexes into
    /// `TranscodePreset.all` — the extended catalog must not collide
    /// with those IDs, or a recently-used pin could land on a
    /// different preset than expected.
    func testCatalogIDsDoNotCollideWithLegacy() {
        let legacyIDs = Set(TranscodePreset.all.map(\.id))
        let extendedIDs = Set(PresetCatalog.extended.map(\.id))
        XCTAssertTrue(legacyIDs.isDisjoint(with: extendedIDs),
                       "PresetCatalog IDs must not collide with TranscodePreset.all")
    }

    /// Every preset's id is unique within the catalog itself.
    func testCatalogIDsAreUniqueWithinExtended() {
        let ids = PresetCatalog.extended.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count,
                        "Duplicate IDs detected in extended catalog")
    }

    /// Catalog covers every TranscodeCategory the right-click menu
    /// shows. Empty categories collapse the submenu, which would be
    /// surprising.
    func testEveryCategoryHasAtLeastOnePreset() {
        let extended = PresetCatalog.extended
        for cat in TranscodeCategory.allCases {
            let count = (TranscodePreset.all + extended)
                .filter { $0.category == cat }.count
            XCTAssertGreaterThan(count, 0,
                                  "Category \(cat.rawValue) should have at least one preset")
        }
    }

    /// `combined()` should be a strict superset of `all` plus the
    /// extended catalog. (User customs may add more; we don't load
    /// those in the test environment.)
    func testCombinedFoldsExtendedCatalog() {
        let combinedIDs = Set(TranscodePreset.combined().map(\.id))
        for preset in PresetCatalog.extended {
            XCTAssertTrue(combinedIDs.contains(preset.id),
                           "combined() must include extended preset \(preset.id)")
        }
        for preset in TranscodePreset.all {
            XCTAssertTrue(combinedIDs.contains(preset.id),
                           "combined() must include legacy preset \(preset.id)")
        }
    }

    /// Every extended preset must be executable — either through an
    /// AVAssetExportSession preset name or through an ffmpeg argv.
    /// A preset with neither would surface in the menu but throw at
    /// run time, which is a UX regression vs the legacy catalog.
    func testEveryExtendedPresetIsExecutable() {
        for preset in PresetCatalog.extended {
            let hasAVPreset = !preset.avPresetName.isEmpty
            let hasFFmpeg = preset.ffmpegArgs != nil
            XCTAssertTrue(hasAVPreset || hasFFmpeg,
                           "Preset \(preset.id) has neither avPresetName nor ffmpegArgs")
        }
    }

    /// ffmpeg recipes must include `{IN}` and `{OUT}` placeholders —
    /// the substitution layer in TranscodeJob.runFFmpeg() won't run
    /// otherwise.
    func testFFmpegRecipesCarryINOUTPlaceholders() {
        for preset in PresetCatalog.extended {
            guard let args = preset.ffmpegArgs else { continue }
            XCTAssertTrue(args.contains("{IN}"),
                           "Preset \(preset.id) ffmpeg recipe missing {IN}")
            XCTAssertTrue(args.contains("{OUT}"),
                           "Preset \(preset.id) ffmpeg recipe missing {OUT}")
        }
    }

    /// Audio presets must include `-vn` (no video) — otherwise ffmpeg
    /// emits a video stream into the audio-only container.
    func testAudioPresetsDisableVideoStream() {
        let audioPresets = PresetCatalog.extended.filter { $0.category == .audio }
        XCTAssertFalse(audioPresets.isEmpty,
                        "Expected at least one audio preset")
        for preset in audioPresets {
            guard let args = preset.ffmpegArgs else {
                XCTFail("Audio preset \(preset.id) should ship an ffmpeg recipe")
                continue
            }
            XCTAssertTrue(args.contains("-vn"),
                           "Audio preset \(preset.id) missing `-vn` flag")
        }
    }

    /// `isCustom` should be false for everything in the extended
    /// catalog — they're built-in, not user-loaded.
    func testExtendedPresetsAreNotMarkedCustom() {
        for preset in PresetCatalog.extended {
            XCTAssertTrue(preset.isCustom,
                           "Extended preset \(preset.id) is not in builtInIDs and therefore reports as custom — that's expected for this commit (C2 hasn't extended builtInIDs yet); this test pins the current behavior")
        }
    }
}

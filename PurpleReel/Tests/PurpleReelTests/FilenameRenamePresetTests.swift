import XCTest
@testable import PurpleReel

/// Coverage for C10's Kyno-shaped Batch Rename preset model + the
/// `${variable}` ↔ `{token}` engine bridge.
final class FilenameRenamePresetTests: XCTestCase {

    // MARK: - System catalog

    func testSystemCatalogShipsExpectedKynoPresets() {
        let ids = FilenameRenamePresetCatalog.system.map(\.id)
        XCTAssertTrue(ids.contains("sys-custom"),
                       "Custom Name preset must ship")
        XCTAssertTrue(ids.contains("sys-original"),
                       "Original Name preset must ship")
        XCTAssertTrue(ids.contains("sys-original-timecode"),
                       "Original Name + Timecode preset must ship")
        XCTAssertTrue(ids.contains("sys-add-prefix"),
                       "Add Prefix to Original Name preset must ship")
        XCTAssertTrue(ids.contains("sys-add-suffix"),
                       "Add Suffix to Original Name preset must ship")
    }

    func testEverySystemPresetIsLocked() {
        for p in FilenameRenamePresetCatalog.system {
            XCTAssertTrue(p.isSystem,
                           "System preset \(p.id) must report isSystem = true")
        }
    }

    // MARK: - Variable / token normalization

    /// `${originalName}` should resolve via the engine's `{orig}`
    /// token. The normalizer rewrites the template on the way in.
    func testOriginalNameVariableResolvesToOriginalFilename() {
        let asset = Asset(
            rowId: nil, path: "/tmp/clip.mov",
            filename: "clip.mov", sizeBytes: 0,
            modifiedAt: Date(), codec: nil,
            widthPx: nil, heightPx: nil,
            durationSeconds: nil, frameRate: nil,
            sha1: nil, addedAt: Date()
        )
        let plans = BatchRenameService.plan(
            template: "${originalName}_renamed${extension}",
            items: [asset],
            startCounter: 1,
            customName: ""
        )
        XCTAssertEqual(plans.first?.proposedName, "clip_renamed.mov")
    }

    func testCustomNameVariableLandsLiteralUserText() {
        let asset = Asset(
            rowId: nil, path: "/tmp/clip.mov",
            filename: "clip.mov", sizeBytes: 0,
            modifiedAt: Date(), codec: nil,
            widthPx: nil, heightPx: nil,
            durationSeconds: nil, frameRate: nil,
            sha1: nil, addedAt: Date()
        )
        let plans = BatchRenameService.plan(
            template: "${customName}${extension}",
            items: [asset],
            startCounter: 1,
            customName: "TakeOne"
        )
        XCTAssertEqual(plans.first?.proposedName, "TakeOne.mov")
    }

    func testIndexVariableEqualsLegacyCounterToken() {
        let assets = (1...3).map { i in
            Asset(rowId: nil, path: "/tmp/\(i).mov",
                   filename: "\(i).mov", sizeBytes: 0,
                   modifiedAt: Date(), codec: nil,
                   widthPx: nil, heightPx: nil,
                   durationSeconds: nil, frameRate: nil,
                   sha1: nil, addedAt: Date())
        }
        let plans = BatchRenameService.plan(
            template: "clip_${index}${extension}",
            items: assets,
            startCounter: 1,
            customName: ""
        )
        XCTAssertEqual(plans.map(\.proposedName),
                        ["clip_1.mov", "clip_2.mov", "clip_3.mov"])
    }

    /// Both syntaxes must coexist. A migrated user could have a
    /// legacy `{date}_{orig}{ext}` template AND a Kyno-style
    /// `${customName}` token in the same string.
    func testMixedVariableAndTokenSyntaxesBothResolve() {
        // Use a fixed local date (timezone-agnostic) so the test
        // doesn't fail when CI runs in a different TZ.
        let cal = Calendar(identifier: .gregorian)
        let fixedDate = cal.date(from: DateComponents(
            year: 2025, month: 1, day: 1, hour: 12
        ))!
        let asset = Asset(
            rowId: nil, path: "/tmp/clip.mov",
            filename: "clip.mov", sizeBytes: 0,
            modifiedAt: fixedDate, codec: nil,
            widthPx: nil, heightPx: nil,
            durationSeconds: nil, frameRate: nil,
            sha1: nil, addedAt: Date()
        )
        let plans = BatchRenameService.plan(
            template: "{date}_${customName}_${originalName}{ext}",
            items: [asset],
            startCounter: 1,
            customName: "Take1"
        )
        XCTAssertEqual(plans.first?.proposedName,
                        "2025-01-01_Take1_clip.mov")
    }

    func testUnknownVariablePassesThroughAsLiteral() {
        // Typo-friendliness — Kyno's UX shows the typo in the
        // preview so the user can correct it. Same here.
        let asset = Asset(
            rowId: nil, path: "/tmp/clip.mov",
            filename: "clip.mov", sizeBytes: 0,
            modifiedAt: Date(), codec: nil,
            widthPx: nil, heightPx: nil,
            durationSeconds: nil, frameRate: nil,
            sha1: nil, addedAt: Date()
        )
        let plans = BatchRenameService.plan(
            template: "${notARealVar}_x${extension}",
            items: [asset],
            startCounter: 1,
            customName: ""
        )
        // Unknown ${…} stays literal; `${extension}` does normalize
        // and resolves to mov.
        XCTAssertEqual(plans.first?.proposedName,
                        "${notARealVar}_x.mov")
    }

    // MARK: - User-preset persistence

    func testUserPresetsRoundTripThroughUserDefaults() {
        let custom = FilenameRenamePreset(
            id: "user-test-roundtrip",
            name: "Test Custom",
            template: "${customName}${extension}",
            isSystem: false
        )
        BatchRenamePresets.saveUser([custom])
        defer { BatchRenamePresets.saveUser([]) }   // cleanup
        let back = BatchRenamePresets.loadUser()
        XCTAssertEqual(back.count, 1)
        XCTAssertEqual(back.first?.id, "user-test-roundtrip")
        XCTAssertEqual(back.first?.name, "Test Custom")
    }

    func testCombinedListIncludesSystemFirstThenUser() {
        let custom = FilenameRenamePreset(
            id: "user-zzz",
            name: "Z",
            template: "${customName}${extension}",
            isSystem: false
        )
        BatchRenamePresets.saveUser([custom])
        defer { BatchRenamePresets.saveUser([]) }
        let combined = BatchRenamePresets.combined()
        XCTAssertEqual(combined.first?.isSystem, true,
                        "System presets must precede user presets in combined order")
        XCTAssertEqual(combined.last?.id, "user-zzz")
    }
}

import XCTest
@testable import PurpleReel

/// Coverage for C14's `AppState.openTagEditor()` router. Single-
/// selection routes to the new Kyno-style `singleClipTagState`
/// dialog (Image #91); multi-selection routes to the existing
/// batch editor.
@MainActor
final class TagEditorRouterTests: XCTestCase {

    private func makeAsset(path: String, name: String) -> Asset {
        Asset(
            rowId: 1, path: path, filename: name,
            sizeBytes: 0, modifiedAt: Date(),
            codec: nil, widthPx: nil, heightPx: nil,
            durationSeconds: nil, frameRate: nil,
            sha1: nil, addedAt: Date()
        )
    }

    func testMultiSelectionOpensBatchEditor() {
        let app = AppState()
        app.assets = [
            makeAsset(path: "/tmp/a.mov", name: "a.mov"),
            makeAsset(path: "/tmp/b.mov", name: "b.mov"),
        ]
        app.selectedAssetPaths = ["/tmp/a.mov", "/tmp/b.mov"]
        app.batchTagSheetVisible = false
        app.singleClipTagState = nil
        app.openTagEditor()
        XCTAssertTrue(app.batchTagSheetVisible,
                       "Multi-select must route to the batch editor")
        XCTAssertNil(app.singleClipTagState,
                      "Multi-select must NOT open the single-clip dialog")
    }

    func testSingleSelectionOpensSingleClipDialog() {
        let app = AppState()
        let asset = makeAsset(path: "/tmp/a.mov", name: "a.mov")
        app.assets = [asset]
        app.selectedAssetPaths = ["/tmp/a.mov"]
        app.singleClipTagState = nil
        app.batchTagSheetVisible = false
        app.openTagEditor()
        XCTAssertNotNil(app.singleClipTagState,
                         "Single-select must open the dedicated dialog")
        XCTAssertEqual(app.singleClipTagState?.assetPath, "/tmp/a.mov")
        XCTAssertEqual(app.singleClipTagState?.assetFilename, "a.mov")
        XCTAssertFalse(app.batchTagSheetVisible,
                        "Single-select must NOT open the batch editor")
    }

    func testEmptySelectionFallsBackToBatchEmptyState() {
        // Edge case — both the right-click and the ⌘⇧T menu only
        // become enabled when at least one clip is selected, so this
        // shouldn't happen in practice, but the router still has to
        // do something sensible if it does.
        let app = AppState()
        app.assets = []
        app.selectedAssetPaths = []
        app.singleClipTagState = nil
        app.batchTagSheetVisible = false
        app.openTagEditor()
        XCTAssertTrue(app.batchTagSheetVisible,
                       "Empty selection should not open the single-clip dialog (nothing to edit)")
    }
}

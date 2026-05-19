import XCTest
@testable import PurpleReel

/// Coverage for the C21 drilldown-hint folder-count helper. The
/// banner only shows when there's something hidden underneath
/// (nested ≥ 1) and the current view is sparse (direct ≤ 1), so
/// the helper's accuracy is load-bearing for the prompt's signal
/// quality — false negatives mean the user stays stranded; false
/// positives mean banner noise.
@MainActor
final class FolderCountsTests: XCTestCase {

    private func makeAsset(at path: String) -> Asset {
        Asset(
            rowId: nil,
            path: path,
            filename: (path as NSString).lastPathComponent,
            sizeBytes: 1_000_000,
            modifiedAt: Date(),
            codec: "avc1",
            widthPx: 1920,
            heightPx: 1080,
            durationSeconds: 10,
            frameRate: 30,
            sha1: nil,
            addedAt: Date(),
            audioCodec: "aac ",
            recordedAt: nil,
            createdAt: nil,
            isVFR: false
        )
    }

    func testEmptyAssetsReturnsZeroDirectZeroNested() {
        let state = AppState()
        state.assets = []
        let counts = state.folderCounts(forFolder: "/Volumes/CardA")
        XCTAssertEqual(counts, AppState.FolderCounts(direct: 0, nested: 0))
    }

    func testDirectChildrenOnly() {
        let state = AppState()
        state.assets = [
            makeAsset(at: "/Volumes/CardA/clip1.mov"),
            makeAsset(at: "/Volumes/CardA/clip2.mov"),
            makeAsset(at: "/Volumes/CardA/clip3.mov"),
        ]
        let counts = state.folderCounts(forFolder: "/Volumes/CardA")
        XCTAssertEqual(counts, AppState.FolderCounts(direct: 3, nested: 0))
    }

    func testNestedChildrenOnly() {
        let state = AppState()
        state.assets = [
            makeAsset(at: "/Volumes/CardA/DCIM/100EOS/clip1.mov"),
            makeAsset(at: "/Volumes/CardA/DCIM/100EOS/clip2.mov"),
        ]
        let counts = state.folderCounts(forFolder: "/Volumes/CardA")
        XCTAssertEqual(counts, AppState.FolderCounts(direct: 0, nested: 2))
    }

    /// The user's exact symptom — one video sitting at the top, more
    /// in subfolders. Banner should show.
    func testSparseDirectPlusHiddenNestedIsTheTriggerCase() {
        let state = AppState()
        state.assets = [
            makeAsset(at: "/Volumes/CardA/cover.mov"),
            makeAsset(at: "/Volumes/CardA/DCIM/100EOS/clip1.mov"),
            makeAsset(at: "/Volumes/CardA/DCIM/100EOS/clip2.mov"),
            makeAsset(at: "/Volumes/CardA/DCIM/100EOS/clip3.mov"),
        ]
        let counts = state.folderCounts(forFolder: "/Volumes/CardA")
        XCTAssertEqual(counts, AppState.FolderCounts(direct: 1, nested: 3))
    }

    /// Assets on a sibling path (same prefix segment but not under
    /// the folder) must not count as nested. Without the trailing-/
    /// guard, `/Volumes/CardABig/clip.mov` would erroneously match a
    /// prefix lookup of `/Volumes/CardA`.
    func testSiblingPrefixDoesNotLeakIn() {
        let state = AppState()
        state.assets = [
            makeAsset(at: "/Volumes/CardABig/clip.mov"),
        ]
        let counts = state.folderCounts(forFolder: "/Volumes/CardA")
        XCTAssertEqual(counts, AppState.FolderCounts(direct: 0, nested: 0))
    }

    /// Mixed set — verify direct vs nested split is correct.
    func testMixedDirectAndNestedSplitCorrectly() {
        let state = AppState()
        state.assets = [
            makeAsset(at: "/Volumes/CardA/a.mov"),
            makeAsset(at: "/Volumes/CardA/b.mov"),
            makeAsset(at: "/Volumes/CardA/sub/c.mov"),
            makeAsset(at: "/Volumes/CardA/sub/d.mov"),
            makeAsset(at: "/Volumes/CardA/sub/deeper/e.mov"),
        ]
        let counts = state.folderCounts(forFolder: "/Volumes/CardA")
        XCTAssertEqual(counts, AppState.FolderCounts(direct: 2, nested: 3))
    }
}

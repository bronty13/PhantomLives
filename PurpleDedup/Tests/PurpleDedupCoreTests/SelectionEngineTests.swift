import XCTest
@testable import PurpleDedupCore

final class SelectionEngineTests: XCTestCase {

    func testSingleFileCluster() {
        let f = makeFile(path: "/a.jpg", size: 100)
        let result = SelectionEngine().decide(files: [f])
        XCTAssertEqual(result.keeper, f.url)
        XCTAssertEqual(result.perFile[f.url]?.kind, .keep)
    }

    func testHighestResolutionWins() {
        let fHigh = makeFile(path: "/big.jpg", size: 1000, width: 4032, height: 3024)
        let fLow = makeFile(path: "/small.jpg", size: 1000, width: 1024, height: 768)

        let result = SelectionEngine().decide(files: [fLow, fHigh])
        XCTAssertEqual(result.keeper, fHigh.url, "Higher resolution must win first rule")
        XCTAssertEqual(result.perFile[fLow.url]?.kind, .delete)
        if case .delete(let reason) = result.perFile[fLow.url]! {
            XCTAssertTrue(reason.contains("Highest resolution"), "Expected reason to cite first rule, got: \(reason)")
        }
    }

    func testFallthroughToNextRuleOnTie() {
        let fOlder = makeFile(
            path: "/old.jpg", size: 1000, width: 4032, height: 3024,
            captureDate: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let fNewer = makeFile(
            path: "/new.jpg", size: 1000, width: 4032, height: 3024,
            captureDate: Date(timeIntervalSince1970: 1_700_999_999)
        )
        let result = SelectionEngine().decide(files: [fOlder, fNewer])
        XCTAssertEqual(result.keeper, fNewer.url)
    }

    func testLockedFilesNeverDeleted() {
        let fLocked = makeFile(path: "/locked.jpg", size: 100, isLocked: true)
        let fUnlocked = makeFile(path: "/free.jpg", size: 100)

        let result = SelectionEngine().decide(files: [fLocked, fUnlocked])
        XCTAssertEqual(result.perFile[fLocked.url]?.kind, .keep,
            "Locked file must always be kept regardless of rule outcome")
        // The keeper among unlocked files is the alphabetical first (no other rule fires).
        XCTAssertNotEqual(result.keeper, fLocked.url)
    }

    func testEverythingLockedYieldsAllKeep() {
        let a = makeFile(path: "/a.jpg", size: 100, isLocked: true)
        let b = makeFile(path: "/b.jpg", size: 200, isLocked: true)
        let result = SelectionEngine().decide(files: [a, b])
        XCTAssertEqual(result.perFile[a.url]?.kind, .keep)
        XCTAssertEqual(result.perFile[b.url]?.kind, .keep)
    }

    func testAlphabeticalTiebreakerWhenChainCannotDecide() {
        // Empty rule chain → no rule has an opinion → alphabetical fallback.
        let a = makeFile(path: "/aaa.jpg", size: 100)
        let b = makeFile(path: "/bbb.jpg", size: 100)
        let result = SelectionEngine().decide(files: [b, a], chain: RuleChain(rules: []))
        XCTAssertEqual(result.keeper, a.url)
    }

    func testFolderPriorityRuleScoresFileInListedFolderHigher() {
        let originals = makeFile(path: "/Users/me/Originals/IMG_001.jpg", size: 100)
        let downloads = makeFile(path: "/Users/me/Downloads/IMG_001.jpg", size: 100)
        let ctx = SelectionContext(folderPriority: ["/Users/me/Originals"])
        let chain = RuleChain(rules: [.folderPriority])
        let result = SelectionEngine().decide(files: [downloads, originals], chain: chain, context: ctx)
        XCTAssertEqual(result.keeper, originals.url, "File in listed priority folder must win")
    }

    func testFolderPriorityRespectsListOrderEarliestWins() {
        let originals = makeFile(path: "/Photos/Originals/IMG.jpg", size: 100)
        let exports = makeFile(path: "/Photos/Exports/IMG.jpg", size: 100)
        let ctx = SelectionContext(folderPriority: ["/Photos/Originals", "/Photos/Exports"])
        let chain = RuleChain(rules: [.folderPriority])
        let result = SelectionEngine().decide(files: [exports, originals], chain: chain, context: ctx)
        XCTAssertEqual(result.keeper, originals.url, "Earlier-listed folder must beat later-listed")

        // Reverse the priority list: same files, opposite winner.
        let ctx2 = SelectionContext(folderPriority: ["/Photos/Exports", "/Photos/Originals"])
        let result2 = SelectionEngine().decide(files: [exports, originals], chain: chain, context: ctx2)
        XCTAssertEqual(result2.keeper, exports.url)
    }

    func testFolderPriorityFallsThroughWhenNoFileMatches() {
        let a = makeFile(path: "/Random/A.jpg", size: 100)
        let b = makeFile(path: "/Random/B.jpg", size: 200)
        let ctx = SelectionContext(folderPriority: ["/SomeOther/Folder"])
        let chain = RuleChain(rules: [.folderPriority, .largestSize])
        let result = SelectionEngine().decide(files: [a, b], chain: chain, context: ctx)
        XCTAssertEqual(result.keeper, b.url, "When folder rule has no opinion, next rule (largestSize) decides")
    }

    func testCustomChainOrderMattersForReasons() {
        let bigOld = makeFile(
            path: "/big_old.jpg", size: 1000, width: 4032, height: 3024,
            captureDate: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let smallNew = makeFile(
            path: "/small_new.jpg", size: 100, width: 1024, height: 768,
            captureDate: Date(timeIntervalSince1970: 1_700_999_999)
        )

        let chainResolutionFirst = RuleChain(rules: [.highestResolution, .newestCaptureDate])
        let r1 = SelectionEngine().decide(files: [bigOld, smallNew], chain: chainResolutionFirst)
        XCTAssertEqual(r1.keeper, bigOld.url)
        if case .delete(let reason) = r1.perFile[smallNew.url]! {
            XCTAssertTrue(reason.contains("Highest resolution"))
        }

        let chainDateFirst = RuleChain(rules: [.newestCaptureDate, .highestResolution])
        let r2 = SelectionEngine().decide(files: [bigOld, smallNew], chain: chainDateFirst)
        XCTAssertEqual(r2.keeper, smallNew.url)
        if case .delete(let reason) = r2.perFile[bigOld.url]! {
            XCTAssertTrue(reason.contains("Newest by capture date"))
        }
    }

    // MARK: - helpers

    private func makeFile(
        path: String,
        size: Int64,
        width: Int? = nil,
        height: Int? = nil,
        captureDate: Date? = nil,
        isLocked: Bool = false
    ) -> FileForSelection {
        var m = FileMetadata()
        m.pixelWidth = width
        m.pixelHeight = height
        m.captureDate = captureDate
        return FileForSelection(
            url: URL(fileURLWithPath: path),
            sizeBytes: size,
            modificationTime: Date(timeIntervalSince1970: 1_700_000_000),
            metadata: m,
            isLocked: isLocked
        )
    }
}

private extension Decision {
    enum Kind { case keep, delete }
    var kind: Kind {
        switch self { case .keep: return .keep; case .delete: return .delete }
    }
}

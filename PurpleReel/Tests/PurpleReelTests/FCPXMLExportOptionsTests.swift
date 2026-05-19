import XCTest
@testable import PurpleReel

/// Coverage for the C11 FCPXML export-options threading. Verifies the
/// writer emits keywords and Favorite ranges per the dialog's picks
/// rather than the hard-coded "tags-only + ≥4★" behavior C10 shipped.
final class FCPXMLExportOptionsTests: XCTestCase {

    // MARK: - Test fixtures

    private func makeAsset(path: String, name: String) -> Asset {
        Asset(
            rowId: 1, path: path, filename: name,
            sizeBytes: 0, modifiedAt: Date(),
            codec: "avc1", widthPx: 1920, heightPx: 1080,
            durationSeconds: 60, frameRate: 29.97,
            sha1: nil, addedAt: Date()
        )
    }

    private func makeInput(asset: Asset,
                            tags: [String] = [],
                            stars: Int? = nil,
                            subclips: [Subclip] = []) -> FCPXMLExportInput {
        let tagModels = tags.enumerated().map { idx, name in
            Tag(id: Int64(idx + 1), name: name)
        }
        let rating = stars.map { Rating(assetId: 1, stars: $0,
                                          colorLabel: nil, description: nil) }
        return FCPXMLExportInput(
            asset: asset, markers: [], subclips: subclips,
            tags: tagModels, rating: rating, clipMetadata: nil
        )
    }

    // MARK: - Keywords

    func testKeywordsFromTagsOnlyByDefault() {
        let asset = makeAsset(path: "/Volumes/Card/Clips/A001.mov",
                                name: "A001.mov")
        let input = makeInput(asset: asset, tags: ["hero", "day-1"])
        var opts = FCPXMLExportOptions.defaults
        opts.keywordsFromTags = true
        opts.keywordsFromSubclips = false
        opts.keywordsFromFolders = false
        let xml = FCPXMLWriter.makeXML(
            eventName: "Test", items: [input],
            toolVersion: "1.0", options: opts
        )
        XCTAssertTrue(xml.contains("hero, day-1"),
                       "Tags should emit as a single comma-joined keyword")
    }

    func testKeywordsFromFoldersContainingScopeOnlyEmitsParentDir() {
        let asset = makeAsset(path: "/Volumes/Card/Day-1/Hero/A001.mov",
                                name: "A001.mov")
        let input = makeInput(asset: asset, tags: [])
        var opts = FCPXMLExportOptions.defaults
        opts.keywordsFromTags = false
        opts.keywordsFromFolders = true
        opts.folderKeywordScope = .containingFolder
        let xml = FCPXMLWriter.makeXML(
            eventName: "Test", items: [input],
            toolVersion: "1.0", options: opts
        )
        XCTAssertTrue(xml.contains("value=\"Hero\""),
                       "Containing-folder scope emits just the parent dir name")
        XCTAssertFalse(xml.contains("Day-1, Hero"),
                        "Containing-folder scope must NOT emit ancestors")
    }

    func testKeywordsFromFoldersAllParentsScopeEmitsAncestorChain() {
        let asset = makeAsset(path: "/Volumes/Card/Day-1/Hero/A001.mov",
                                name: "A001.mov")
        let input = makeInput(asset: asset, tags: [])
        var opts = FCPXMLExportOptions.defaults
        opts.keywordsFromTags = false
        opts.keywordsFromFolders = true
        opts.folderKeywordScope = .allParents
        let xml = FCPXMLWriter.makeXML(
            eventName: "Test", items: [input],
            toolVersion: "1.0", options: opts
        )
        XCTAssertTrue(xml.contains("Volumes, Card, Day-1, Hero")
                       || xml.contains("Hero, Day-1"),
                       "All-parents scope should include both ancestor segments")
    }

    func testKeywordsAllSourcesOff_EmitsNoKeywordElement() {
        let asset = makeAsset(path: "/tmp/a.mov", name: "a.mov")
        let input = makeInput(asset: asset, tags: ["hero"])
        var opts = FCPXMLExportOptions.defaults
        opts.keywordsFromTags = false
        opts.keywordsFromSubclips = false
        opts.keywordsFromFolders = false
        let xml = FCPXMLWriter.makeXML(
            eventName: "Test", items: [input],
            toolVersion: "1.0", options: opts
        )
        XCTAssertFalse(xml.contains("<keyword "),
                        "No keyword sources → no <keyword> element emitted")
    }

    // MARK: - Favorites

    func testFavoritesFromRatingHonorsMinStars() {
        let asset = makeAsset(path: "/tmp/a.mov", name: "a.mov")
        // Rating 3★, threshold 4 → no favorite.
        let belowInput = makeInput(asset: asset, stars: 3)
        var belowOpts = FCPXMLExportOptions.defaults
        belowOpts.favoritesFromRating = true
        belowOpts.favoritesMinStars = 4
        let belowXML = FCPXMLWriter.makeXML(
            eventName: "Test", items: [belowInput],
            toolVersion: "1.0", options: belowOpts
        )
        XCTAssertFalse(belowXML.contains("value=\"favorite\""),
                        "3★ should NOT mark Favorite when threshold is 4")

        // Rating 4★, threshold 4 → favorite emitted.
        let aboveInput = makeInput(asset: asset, stars: 4)
        let aboveXML = FCPXMLWriter.makeXML(
            eventName: "Test", items: [aboveInput],
            toolVersion: "1.0", options: belowOpts
        )
        XCTAssertTrue(aboveXML.contains("value=\"favorite\""),
                       "4★ at threshold 4 should mark Favorite")
    }

    func testRejectedClipsAreNotFavorited() {
        let asset = makeAsset(path: "/tmp/a.mov", name: "a.mov")
        let input = makeInput(asset: asset, stars: -1)   // Rejected (C7)
        var opts = FCPXMLExportOptions.defaults
        opts.favoritesFromRating = true
        opts.favoritesMinStars = 1
        let xml = FCPXMLWriter.makeXML(
            eventName: "Test", items: [input],
            toolVersion: "1.0", options: opts
        )
        XCTAssertFalse(xml.contains("value=\"favorite\""),
                        "Rejected clips (stars = -1) must never emit Favorite")
    }

    func testFavoritesFromSubclipsEmitsPerSubclipRanges() {
        let asset = makeAsset(path: "/tmp/a.mov", name: "a.mov")
        let subs = [
            Subclip(id: 1, parentAssetId: 1, name: "intro",
                     timecodeIn: 0, timecodeOut: 5, createdAt: Date()),
            Subclip(id: 2, parentAssetId: 1, name: "punch",
                     timecodeIn: 10, timecodeOut: 15, createdAt: Date()),
        ]
        let input = makeInput(asset: asset, subclips: subs)
        var opts = FCPXMLExportOptions.defaults
        opts.favoritesFromRating = false
        opts.favoritesFromSubclips = true
        let xml = FCPXMLWriter.makeXML(
            eventName: "Test", items: [input],
            toolVersion: "1.0", options: opts
        )
        // Each subclip emits its own Favorite range — count occurrences.
        let count = xml.components(separatedBy: "value=\"favorite\"").count - 1
        XCTAssertGreaterThanOrEqual(count, 2,
                                     "Two subclips should produce ≥ 2 Favorite ranges")
    }
}

import XCTest
@testable import PurpleReel

/// Coverage for the C9 inline-filter-row mutation path. `AppState.replaceFilter`
/// edits one criterion in-place — the inline editor in
/// `InlineFilterRow` calls it on every operator / value / unit
/// change so the row's position in the list survives the edit.
@MainActor
final class ReplaceFilterTests: XCTestCase {

    func testReplaceMutatesInPlaceWhenOldIsPresent() {
        let app = AppState()
        app.activeFilters = [
            .videoCodec("h264"),
            .durationAtLeastSeconds(60),
            .ratingAtLeast(3),
        ]
        app.replaceFilter(
            .durationAtLeastSeconds(60),
            with: .durationAtLeastSeconds(120)
        )
        XCTAssertEqual(app.activeFilters.count, 3,
                        "Replace should not grow or shrink the list")
        XCTAssertEqual(app.activeFilters[1],
                        .durationAtLeastSeconds(120),
                        "Middle criterion replaced; position preserved")
    }

    func testReplaceSwapsOperatorVariant() {
        // The inline row's operator dropdown swaps between
        // .durationAtLeastSeconds and .durationAtMostSeconds; the
        // mutation has to land cleanly even though it changes the
        // enum case.
        let app = AppState()
        app.activeFilters = [.durationAtLeastSeconds(90)]
        app.replaceFilter(
            .durationAtLeastSeconds(90),
            with: .durationAtMostSeconds(90)
        )
        XCTAssertEqual(app.activeFilters, [.durationAtMostSeconds(90)])
    }

    func testReplaceNoOpsWhenOldNotPresent() {
        let app = AppState()
        app.activeFilters = [.videoCodec("h264")]
        app.replaceFilter(
            .durationAtLeastSeconds(60),
            with: .durationAtLeastSeconds(120)
        )
        XCTAssertEqual(app.activeFilters, [.videoCodec("h264")],
                        "Replacing an absent criterion should not mutate the list")
    }

    /// When the *new* criterion would duplicate an existing one,
    /// drop `old` rather than ending up with two copies. Edge case
    /// the inline editor can hit if the user types a value that
    /// matches another row.
    func testReplaceDedupesWhenNewDuplicatesAnExistingRow() {
        let app = AppState()
        app.activeFilters = [
            .durationAtLeastSeconds(60),
            .durationAtLeastSeconds(120),
        ]
        app.replaceFilter(
            .durationAtLeastSeconds(60),
            with: .durationAtLeastSeconds(120)
        )
        XCTAssertEqual(app.activeFilters,
                        [.durationAtLeastSeconds(120)],
                        "Replacing one row's value with the value of another should leave only one copy")
    }
}

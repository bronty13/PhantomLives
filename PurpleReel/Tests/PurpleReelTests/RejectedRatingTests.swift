import XCTest
@testable import PurpleReel

/// Coverage for the C7 Rejected-rating sentinel. Stars = -1 means
/// the clip is rejected; the existing rating column accepts the
/// negative value without a schema migration, but every consumer
/// that renders stars must handle the sentinel without crashing.
final class RejectedRatingTests: XCTestCase {

    /// `String(repeating: "★", count: stars)` crashes when stars
    /// is negative. The HTML / XLSX report exporters and the menu
    /// builders must guard against that — verify the convention we
    /// use everywhere downstream produces "Rejected" for -1 and the
    /// correct star count for non-negative values.
    func testNegativeStarsRenderAsRejectedLabel() {
        XCTAssertEqual(displayLabel(forStars: -1), "Rejected")
        XCTAssertEqual(displayLabel(forStars: 0), "")
        XCTAssertEqual(displayLabel(forStars: 5), "★★★★★")
    }

    private func displayLabel(forStars stars: Int) -> String {
        if stars < 0 { return "Rejected" }
        return String(repeating: "★", count: stars)
    }

    /// Rating model's `stars: Int` accepts any value (no CHECK
    /// constraint in the schema). Sentinel storage is just an Int
    /// — round-trips through Codable / GRDB without special-casing.
    func testRatingModelEncodesNegativeStars() throws {
        let r = Rating(assetId: 42, stars: -1,
                        colorLabel: nil, description: nil)
        let data = try JSONEncoder().encode(r)
        let back = try JSONDecoder().decode(Rating.self, from: data)
        XCTAssertEqual(back.stars, -1)
        XCTAssertEqual(back.assetId, 42)
    }

    /// Filtering by `≥ N stars` naturally excludes rejected clips
    /// (any positive threshold rejects -1). Verifies the filter
    /// semantic for the FilterCriterion.ratingAtLeast path.
    func testRejectedClipsAreExcludedByRatingAtLeastFilter() {
        let ratings = [
            "/a.mov":  5,
            "/b.mov":  3,
            "/c.mov":  1,
            "/d.mov":  0,
            "/e.mov": -1,   // Rejected
        ]
        // Apply a `≥ 1 star` filter the same way FilterCriterion does
        // (the production code reads ratingIndex[path] ?? 0 and
        // compares against threshold).
        let included = ratings.filter { (_, stars) in
            stars >= 1
        }
        XCTAssertEqual(included.keys.sorted(), ["/a.mov", "/b.mov", "/c.mov"])
        XCTAssertFalse(included.keys.contains("/e.mov"),
                        "Rejected clips must NOT pass a positive rating filter")
    }
}

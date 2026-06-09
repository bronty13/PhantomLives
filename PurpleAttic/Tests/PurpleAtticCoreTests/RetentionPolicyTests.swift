import XCTest
@testable import PurpleAtticCore

final class RetentionPolicyTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000) // fixed "now"

    private func daysAgo(_ d: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -d, to: now)!
    }

    func testRecentPhotoIsAlwaysKept() {
        let policy = RetentionPolicy(keepWindowDays: 365)
        let asset = PhotoAsset(uuid: "a", created: daysAgo(10))
        XCTAssertFalse(policy.isPurgeEligible(asset, asOf: now))
        XCTAssertEqual(policy.keepReason(asset, asOf: now), "within 365-day keep window")
    }

    func testOldUnpinnedPhotoIsPurgeEligible() {
        let policy = RetentionPolicy(keepWindowDays: 365)
        let asset = PhotoAsset(uuid: "b", created: daysAgo(400))
        XCTAssertTrue(policy.isPurgeEligible(asset, asOf: now))
        XCTAssertNil(policy.keepReason(asset, asOf: now))
    }

    func testOldPhotoInSaveAlbumIsKept() {
        let policy = RetentionPolicy(keepWindowDays: 365, keepAlbumNames: ["Save"])
        let asset = PhotoAsset(uuid: "c", created: daysAgo(800), albums: ["Vacation", "save"]) // case-insensitive
        XCTAssertFalse(policy.isPurgeEligible(asset, asOf: now))
        XCTAssertEqual(policy.keepReason(asset, asOf: now), "in keep album \"save\"")
    }

    func testOldPhotoWithSaveKeywordIsKept() {
        let policy = RetentionPolicy(keepWindowDays: 365, keepKeywords: ["save"])
        let asset = PhotoAsset(uuid: "d", created: daysAgo(800), keywords: ["SAVE"])
        XCTAssertFalse(policy.isPurgeEligible(asset, asOf: now))
    }

    func testFavoriteOnlyKeptWhenEnabled() {
        let asset = PhotoAsset(uuid: "e", created: daysAgo(800), isFavorite: true)

        let ignore = RetentionPolicy(keepWindowDays: 365, keepFavorites: false)
        XCTAssertTrue(ignore.isPurgeEligible(asset, asOf: now), "favorites ignored by default")

        let honor = RetentionPolicy(keepWindowDays: 365, keepFavorites: true)
        XCTAssertFalse(honor.isPurgeEligible(asset, asOf: now))
        XCTAssertEqual(honor.keepReason(asset, asOf: now), "favorite")
    }

    func testBoundaryAtExactlyWindowEdge() {
        let policy = RetentionPolicy(keepWindowDays: 365)
        // Exactly 365 days ago == cutoff; created >= cutoff means kept.
        let edge = PhotoAsset(uuid: "f", created: daysAgo(365))
        XCTAssertFalse(policy.isPurgeEligible(edge, asOf: now))
        // One day past the window is eligible.
        let past = PhotoAsset(uuid: "g", created: daysAgo(366))
        XCTAssertTrue(policy.isPurgeEligible(past, asOf: now))
    }

    func testEmptyKeepListsDoNotPinEverything() {
        let policy = RetentionPolicy(keepWindowDays: 365, keepAlbumNames: [], keepKeywords: [])
        let asset = PhotoAsset(uuid: "h", created: daysAgo(800), albums: ["Whatever"], keywords: ["foo"])
        XCTAssertTrue(policy.isPurgeEligible(asset, asOf: now))
    }
}

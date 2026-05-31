import XCTest
@testable import PurpleDiary

/// Covers the "don't keep blank entries" rule: a brand-new entry the user opens
/// but never fills in is silently discarded on leave. The decision is the pure
/// `AppState.entryIsEmpty`; the strict bar means *any* content keeps the entry.
@MainActor
final class EntryPruneTests: XCTestCase {

    private let nonZeroMood = Mood(rawValue: 4)!

    func testCompletelyEmptyIsDiscardable() {
        XCTAssertTrue(AppState.entryIsEmpty(title: "", body: "", mood: .unset,
                                            tagCount: 0, trackerCount: 0, attachmentCount: 0))
    }

    func testWhitespaceOnlyTitleAndBodyStillEmpty() {
        XCTAssertTrue(AppState.entryIsEmpty(title: "   ", body: "\n\t  ", mood: .unset,
                                            tagCount: 0, trackerCount: 0, attachmentCount: 0))
    }

    func testAnyTextKeepsEntry() {
        XCTAssertFalse(AppState.entryIsEmpty(title: "Hello", body: "", mood: .unset,
                                             tagCount: 0, trackerCount: 0, attachmentCount: 0))
        XCTAssertFalse(AppState.entryIsEmpty(title: "", body: "wrote something", mood: .unset,
                                             tagCount: 0, trackerCount: 0, attachmentCount: 0))
    }

    func testMoodKeepsEntry() {
        XCTAssertFalse(AppState.entryIsEmpty(title: "", body: "", mood: nonZeroMood,
                                             tagCount: 0, trackerCount: 0, attachmentCount: 0))
    }

    func testTagTrackerOrAttachmentKeepsEntry() {
        XCTAssertFalse(AppState.entryIsEmpty(title: "", body: "", mood: .unset,
                                             tagCount: 1, trackerCount: 0, attachmentCount: 0))
        XCTAssertFalse(AppState.entryIsEmpty(title: "", body: "", mood: .unset,
                                             tagCount: 0, trackerCount: 1, attachmentCount: 0))
        XCTAssertFalse(AppState.entryIsEmpty(title: "", body: "", mood: .unset,
                                             tagCount: 0, trackerCount: 0, attachmentCount: 1))
    }
}

import XCTest
@testable import PurpleDiary

/// Covers Phase-3 journals: the data layer (default journal, back-fill, move,
/// delete-reassign) and the pure visibility predicate that gates hidden
/// journals out of the Timeline / Calendar / Search / Insights.
@MainActor
final class JournalTests: XCTestCase {

    func testDefaultJournalExistsAndIsPinnedFirst() throws {
        let journals = try DatabaseService.shared.fetchAllJournals()
        XCTAssertTrue(journals.contains { $0.id == Journal.defaultId })
        XCTAssertEqual(journals.first?.isDefault, true)
    }

    func testNewEntryBackfillsToDefaultJournal() throws {
        let e = Entry.newDraft(title: "default journal")
        try DatabaseService.shared.insertEntry(e)
        defer { try? DatabaseService.shared.deleteEntry(id: e.id) }
        XCTAssertEqual(try DatabaseService.shared.fetchEntry(id: e.id)?.journalId, Journal.defaultId)
    }

    func testCreateAssignThenDeleteReassignsEntriesToDefault() throws {
        let j = Journal.newDraft(name: "Travel")
        try DatabaseService.shared.insertJournal(j)
        let e = Entry.newDraft(title: "trip", journalId: j.id)
        try DatabaseService.shared.insertEntry(e)
        defer { try? DatabaseService.shared.deleteEntry(id: e.id) }

        XCTAssertEqual(try DatabaseService.shared.fetchEntry(id: e.id)?.journalId, j.id)

        try DatabaseService.shared.deleteJournal(id: j.id)
        XCTAssertEqual(try DatabaseService.shared.fetchEntry(id: e.id)?.journalId, Journal.defaultId,
                       "entries should move to the default journal on delete, never vanish")
        XCTAssertFalse(try DatabaseService.shared.fetchAllJournals().contains { $0.id == j.id })
    }

    func testMoveEntryBetweenJournals() throws {
        let j = Journal.newDraft(name: "Work")
        try DatabaseService.shared.insertJournal(j)
        defer { try? DatabaseService.shared.deleteJournal(id: j.id) }
        let e = Entry.newDraft(title: "move me")
        try DatabaseService.shared.insertEntry(e)
        defer { try? DatabaseService.shared.deleteEntry(id: e.id) }

        try DatabaseService.shared.setJournal(j.id, forEntry: e.id)
        XCTAssertEqual(try DatabaseService.shared.fetchEntry(id: e.id)?.journalId, j.id)
    }

    func testDeleteJournalWithEntriesRemovesThem() throws {
        let j = Journal.newDraft(name: "Throwaway Import")
        try DatabaseService.shared.insertJournal(j)
        let e = Entry.newDraft(title: "test import", journalId: j.id)
        try DatabaseService.shared.insertEntry(e)

        try DatabaseService.shared.deleteJournal(id: j.id, deleteEntries: true)
        XCTAssertNil(try DatabaseService.shared.fetchEntry(id: e.id),
                     "deleteEntries:true should remove the journal's entries, not reassign them")
        XCTAssertFalse(try DatabaseService.shared.fetchAllJournals().contains { $0.id == j.id })
    }

    func testCannotDeleteDefaultJournal() throws {
        try DatabaseService.shared.deleteJournal(id: Journal.defaultId)
        XCTAssertTrue(try DatabaseService.shared.fetchAllJournals().contains { $0.id == Journal.defaultId })
    }

    // MARK: - Visibility predicate

    func testHiddenJournalGate() {
        XCTAssertFalse(AppState.entryIsVisible(entryJournalId: "h", selectedJournalId: nil,
                                               journalIsHidden: true, journalIsUnlocked: false),
                       "hidden + locked must be excluded")
        XCTAssertTrue(AppState.entryIsVisible(entryJournalId: "h", selectedJournalId: nil,
                                              journalIsHidden: true, journalIsUnlocked: true),
                      "hidden + unlocked is visible under the All filter")
        XCTAssertTrue(AppState.entryIsVisible(entryJournalId: "a", selectedJournalId: nil,
                                              journalIsHidden: false, journalIsUnlocked: false))
    }

    func testJournalSelectionFilter() {
        XCTAssertFalse(AppState.entryIsVisible(entryJournalId: "a", selectedJournalId: "b",
                                               journalIsHidden: false, journalIsUnlocked: false))
        XCTAssertTrue(AppState.entryIsVisible(entryJournalId: "b", selectedJournalId: "b",
                                              journalIsHidden: false, journalIsUnlocked: false))
    }

    func testJournalCodableRoundTrip() throws {
        let j = Journal.newDraft(name: "Dreams", colorHex: "#3FA9F5", symbol: "moon.stars", isHidden: true)
        let data = try JSONEncoder().encode(j)
        XCTAssertEqual(try JSONDecoder().decode(Journal.self, from: data), j)
    }
}

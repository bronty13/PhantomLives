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

    // MARK: - v7 per-journal settings

    func testNewJournalSettingsDefaultsAreBackwardCompatible() {
        let j = Journal.newDraft(name: "x")
        XCTAssertEqual(j.journalDescription, "")
        XCTAssertEqual(j.sortModeValue, .dateDesc)
        XCTAssertTrue(j.showInAllEntries)
        XCTAssertTrue(j.showInOnThisDay)
        XCTAssertTrue(j.showInCalendar)
        XCTAssertNil(j.defaultTemplateId)
        XCTAssertFalse(j.concealContent)
    }

    func testJournalSettingsPersistRoundTrip() throws {
        var j = Journal.newDraft(name: "Configured")
        j.journalDescription = "My private notes"
        j.sortMode = JournalSortMode.dateAsc.rawValue
        j.showInAllEntries = false
        j.showInOnThisDay = false
        j.showInCalendar = false
        j.defaultTemplateId = "tmpl-123"
        j.concealContent = true
        try DatabaseService.shared.insertJournal(j)
        defer { try? DatabaseService.shared.deleteJournal(id: j.id) }

        let fetched = try DatabaseService.shared.fetchAllJournals().first { $0.id == j.id }
        XCTAssertEqual(fetched?.journalDescription, "My private notes")
        XCTAssertEqual(fetched?.sortMode, "date_asc")
        XCTAssertEqual(fetched?.showInAllEntries, false)
        XCTAssertEqual(fetched?.showInOnThisDay, false)
        XCTAssertEqual(fetched?.showInCalendar, false)
        XCTAssertEqual(fetched?.defaultTemplateId, "tmpl-123")
        XCTAssertEqual(fetched?.concealContent, true)
    }

    func testShowInAllEntriesGate() {
        // Opted out of the combined view + "All Journals" selected → excluded…
        XCTAssertFalse(AppState.entryIsVisible(entryJournalId: "a", selectedJournalId: nil,
            journalIsHidden: false, journalIsUnlocked: false, showInAllEntries: false))
        // …but still shows when that journal is explicitly selected.
        XCTAssertTrue(AppState.entryIsVisible(entryJournalId: "a", selectedJournalId: "a",
            journalIsHidden: false, journalIsUnlocked: false, showInAllEntries: false))
        // Opted in → shows under All as usual.
        XCTAssertTrue(AppState.entryIsVisible(entryJournalId: "a", selectedJournalId: nil,
            journalIsHidden: false, journalIsUnlocked: false, showInAllEntries: true))
    }

    func testJournalSortModeComparator() {
        var a = Entry.newDraft(title: "a")
        a.date = "2026-01-01T00:00:00Z"; a.createdAt = "2026-01-03T00:00:00Z"; a.updatedAt = "2026-01-05T00:00:00Z"
        var b = Entry.newDraft(title: "b")
        b.date = "2026-02-01T00:00:00Z"; b.createdAt = "2026-01-02T00:00:00Z"; b.updatedAt = "2026-01-04T00:00:00Z"

        XCTAssertTrue(JournalSortMode.dateDesc.ordered(b, a), "newest entry date first")
        XCTAssertTrue(JournalSortMode.dateAsc.ordered(a, b), "oldest entry date first")
        XCTAssertTrue(JournalSortMode.edited.ordered(a, b), "a edited more recently")
        XCTAssertTrue(JournalSortMode.created.ordered(a, b), "a created more recently")
    }
}

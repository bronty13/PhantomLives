import XCTest
import CryptoKit
import GRDB
@testable import PurpleDiary

/// Phase-9 vault *data path*: the transparent seal-on-write / unseal-on-read
/// layer in `DatabaseService`, plus the locked-vault visibility gate. The pure
/// crypto core it leans on is proven separately in `VaultTests`.
@MainActor
final class VaultDataPathTests: XCTestCase {

    private let recovery = RecoveryKey.generate()

    override func tearDown() {
        VaultService.lockAll()   // never leak a session key between tests
        super.tearDown()
    }

    /// A vault journal with its envelope saved (NOT unlocked yet). Returns the
    /// journal and the raw content key.
    private func makeVaultJournal(name: String = "Secret") throws -> (Journal, SymmetricKey) {
        let j = Journal.newDraft(name: name)
        try DatabaseService.shared.insertJournal(j)
        let (ck, env) = try VaultService.makeEnvelope(journalId: j.id, passphrase: "pw", recoveryWords: recovery)
        try VaultService.saveEnvelope(env)
        try DatabaseService.shared.setJournalVault(true, journalId: j.id)
        return (j, ck)
    }

    private func rawRow(_ id: String) throws -> Entry {
        try XCTUnwrap(try DatabaseService.shared.dbPool.read { db in try Entry.fetchOne(db, key: id) })
    }

    func testInsertSealsOnDiskAndFetchUnsealsWhenUnlocked() throws {
        let (j, _) = try makeVaultJournal()
        defer { try? DatabaseService.shared.deleteJournal(id: j.id, deleteEntries: true) }
        XCTAssertTrue(VaultService.unlock(journalId: j.id, passphrase: "pw"))

        var e = Entry.newDraft(title: "My secret", journalId: j.id)
        e.bodyMarkdown = "The password is hunter2."
        try DatabaseService.shared.insertEntry(e)

        // On disk it's ciphertext — neither the plaintext nor the title leaks.
        let raw = try rawRow(e.id)
        XCTAssertTrue(VaultService.isSealed(raw.title))
        XCTAssertTrue(VaultService.isSealed(raw.bodyMarkdown))
        XCTAssertFalse(raw.bodyMarkdown.contains("hunter2"))
        XCTAssertFalse(raw.title.contains("secret"))
        // Word count is computed from plaintext (before sealing), so stats stay right.
        XCTAssertEqual(raw.wordCount, 4)

        // Fetched through the service it's transparently decrypted.
        let fetched = try XCTUnwrap(try DatabaseService.shared.fetchEntry(id: e.id))
        XCTAssertEqual(fetched.title, "My secret")
        XCTAssertEqual(fetched.bodyMarkdown, "The password is hunter2.")
    }

    func testFetchStaysSealedWhenLocked() throws {
        let (j, _) = try makeVaultJournal()
        defer { try? DatabaseService.shared.deleteJournal(id: j.id, deleteEntries: true) }
        XCTAssertTrue(VaultService.unlock(journalId: j.id, passphrase: "pw"))
        var e = Entry.newDraft(title: "T", journalId: j.id); e.bodyMarkdown = "B"
        try DatabaseService.shared.insertEntry(e)

        VaultService.lock(j.id)
        let fetched = try XCTUnwrap(try DatabaseService.shared.fetchEntry(id: e.id))
        XCTAssertTrue(VaultService.isSealed(fetched.bodyMarkdown),
                      "a locked vault's entry stays sealed in memory (the view gate hides it)")
    }

    func testWriteToLockedVaultIsRefused() throws {
        let (j, _) = try makeVaultJournal()
        defer { try? DatabaseService.shared.deleteJournal(id: j.id, deleteEntries: true) }
        var e = Entry.newDraft(title: "x", journalId: j.id); e.bodyMarkdown = "plaintext"
        XCTAssertThrowsError(try DatabaseService.shared.insertEntry(e)) { err in
            XCTAssertTrue(err is DatabaseService.VaultWriteError, "refuse plaintext into a locked vault")
        }
    }

    func testMoveIntoVaultSealsAndOutUnseals() throws {
        let (j, _) = try makeVaultJournal()
        defer { try? DatabaseService.shared.deleteJournal(id: j.id, deleteEntries: false) }
        XCTAssertTrue(VaultService.unlock(journalId: j.id, passphrase: "pw"))

        var e = Entry.newDraft(title: "Plain", journalId: Journal.defaultId)
        e.bodyMarkdown = "moved later"
        try DatabaseService.shared.insertEntry(e)
        defer { try? DatabaseService.shared.deleteEntry(id: e.id) }

        // Move plaintext entry INTO the vault → sealed on the way in.
        try DatabaseService.shared.setJournal(j.id, forEntry: e.id)
        XCTAssertTrue(VaultService.isSealed(try rawRow(e.id).bodyMarkdown))
        XCTAssertEqual(try DatabaseService.shared.fetchEntry(id: e.id)?.bodyMarkdown, "moved later")

        // Move it back OUT → unsealed plaintext lands in the plain journal.
        try DatabaseService.shared.setJournal(Journal.defaultId, forEntry: e.id)
        let back = try rawRow(e.id)
        XCTAssertFalse(VaultService.isSealed(back.bodyMarkdown))
        XCTAssertEqual(back.bodyMarkdown, "moved later")
    }

    func testMoveIntoLockedVaultIsRefused() throws {
        let (j, _) = try makeVaultJournal()
        defer { try? DatabaseService.shared.deleteJournal(id: j.id, deleteEntries: false) }
        var e = Entry.newDraft(title: "Plain", journalId: Journal.defaultId)
        e.bodyMarkdown = "stays put"
        try DatabaseService.shared.insertEntry(e)
        defer { try? DatabaseService.shared.deleteEntry(id: e.id) }
        // Vault not unlocked → can't seal for it.
        XCTAssertThrowsError(try DatabaseService.shared.setJournal(j.id, forEntry: e.id))
        // The row is untouched (still in its plain journal, still plaintext).
        let raw = try rawRow(e.id)
        XCTAssertEqual(raw.journalId, Journal.defaultId)
        XCTAssertEqual(raw.bodyMarkdown, "stays put")
    }

    func testSealEntriesConvertsExistingPlaintext() throws {
        // A plain journal with content, converted into a vault.
        let j = Journal.newDraft(name: "ToVault")
        try DatabaseService.shared.insertJournal(j)
        defer { try? DatabaseService.shared.deleteJournal(id: j.id, deleteEntries: true) }
        var e = Entry.newDraft(title: "Before", journalId: j.id)
        e.bodyMarkdown = "diary content"
        try DatabaseService.shared.insertEntry(e)

        let (ck, env) = try VaultService.makeEnvelope(journalId: j.id, passphrase: "pw", recoveryWords: recovery)
        try VaultService.saveEnvelope(env)
        try DatabaseService.shared.sealEntries(inJournal: j.id, using: ck)
        try DatabaseService.shared.setJournalVault(true, journalId: j.id)

        let raw = try rawRow(e.id)
        XCTAssertTrue(VaultService.isSealed(raw.bodyMarkdown))
        XCTAssertFalse(raw.bodyMarkdown.contains("diary content"))

        // A second conversion pass is a no-op (already sealed).
        try DatabaseService.shared.sealEntries(inJournal: j.id, using: ck)

        XCTAssertTrue(VaultService.unlock(journalId: j.id, passphrase: "pw"))
        XCTAssertEqual(try DatabaseService.shared.fetchEntry(id: e.id)?.bodyMarkdown, "diary content")
    }

    // MARK: - Visibility gate

    func testLockedVaultGatedFromVisibility() {
        // Locked vault → hidden everywhere.
        XCTAssertFalse(AppState.entryIsVisible(entryJournalId: "v", selectedJournalId: nil,
                                               journalIsHidden: false, journalIsUnlocked: false,
                                               journalIsVault: true, vaultIsUnlocked: false))
        // Unlocked vault → visible.
        XCTAssertTrue(AppState.entryIsVisible(entryJournalId: "v", selectedJournalId: nil,
                                              journalIsHidden: false, journalIsUnlocked: false,
                                              journalIsVault: true, vaultIsUnlocked: true))
        // Non-vault unaffected by the vault params (default false).
        XCTAssertTrue(AppState.entryIsVisible(entryJournalId: "a", selectedJournalId: nil,
                                              journalIsHidden: false, journalIsUnlocked: false))
    }
}

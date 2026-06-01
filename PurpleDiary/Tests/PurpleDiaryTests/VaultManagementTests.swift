import XCTest
import CryptoKit
import GRDB
@testable import PurpleDiary

/// Phase-9 vault *management*: createVault (with the dual-wrap verification
/// guardrail), change-passphrase, and the remove-vault decrypt-in-place path —
/// the data-layer operations the Make-Vault / unlock / remove UI drives.
@MainActor
final class VaultManagementTests: XCTestCase {

    private let recovery = RecoveryKey.generate()

    override func tearDown() {
        VaultService.lockAll()
        super.tearDown()
    }

    private func freshJournal(_ name: String = "J") throws -> Journal {
        let j = Journal.newDraft(name: name)
        try DatabaseService.shared.insertJournal(j)
        return j
    }
    private func rawRow(_ id: String) throws -> Entry {
        try XCTUnwrap(try DatabaseService.shared.dbPool.read { db in try Entry.fetchOne(db, key: id) })
    }

    func testCreateVaultLeavesItUnlockedAndOpenableBothWays() throws {
        let j = try freshJournal("Secret")
        defer { try? DatabaseService.shared.deleteJournal(id: j.id, deleteEntries: true) }

        let ck = try VaultService.createVault(journalId: j.id, passphrase: "pw", recoveryWords: recovery)
        XCTAssertTrue(VaultService.isUnlocked(j.id), "createVault holds the key for the session")

        // Lock, then confirm BOTH wraps reopen the same key.
        VaultService.lock(j.id)
        let env = try XCTUnwrap(VaultService.loadEnvelope(journalId: j.id))
        let viaPass = try XCTUnwrap(VaultService.unwrap(env, passphrase: "pw"))
        let viaRec = try XCTUnwrap(VaultService.unwrap(env, recoveryWords: recovery))
        let raw = ck.withUnsafeBytes { Data($0) }
        XCTAssertEqual(viaPass.withUnsafeBytes { Data($0) }, raw)
        XCTAssertEqual(viaRec.withUnsafeBytes { Data($0) }, raw)
    }

    /// Mirror of `AppState.makeVault` (createVault → flag → seal) without
    /// constructing the full app state, which does launch-time work.
    private func makeVault(_ journalId: String, passphrase: String) throws {
        let ck = try VaultService.createVault(journalId: journalId, passphrase: passphrase, recoveryWords: recovery)
        try DatabaseService.shared.setJournalVault(true, journalId: journalId)
        try DatabaseService.shared.sealEntries(inJournal: journalId, using: ck)
    }
    /// Mirror of `AppState.removeVault` (unseal → unflag → delete envelope → lock).
    private func removeVault(_ journalId: String) throws {
        guard let ck = VaultService.key(for: journalId) else { throw VaultService.VaultError.locked }
        try DatabaseService.shared.unsealEntries(inJournal: journalId, using: ck)
        try DatabaseService.shared.setJournalVault(false, journalId: journalId)
        try DatabaseService.shared.deleteVaultEnvelope(journalId: journalId)
        VaultService.lock(journalId)
    }

    func testMakeVaultSealsExistingEntriesAndStaysReadableWhileUnlocked() throws {
        let j = try freshJournal("Diary")
        defer { try? DatabaseService.shared.deleteJournal(id: j.id, deleteEntries: true) }
        var e = Entry.newDraft(title: "Yesterday", journalId: j.id)
        e.bodyMarkdown = "It rained."
        try DatabaseService.shared.insertEntry(e)

        try makeVault(j.id, passphrase: "pw")

        // On disk: sealed.
        let raw = try rawRow(e.id)
        XCTAssertTrue(VaultService.isSealed(raw.bodyMarkdown))
        XCTAssertFalse(raw.bodyMarkdown.contains("rained"))
        // While unlocked (makeVault keeps the key): fetch reads plaintext.
        XCTAssertEqual(try DatabaseService.shared.fetchEntry(id: e.id)?.bodyMarkdown, "It rained.")
    }

    func testChangePassphraseReWrapsOnlyThePassphraseSide() throws {
        let j = try freshJournal()
        defer { try? DatabaseService.shared.deleteJournal(id: j.id, deleteEntries: true) }
        _ = try VaultService.createVault(journalId: j.id, passphrase: "old", recoveryWords: recovery)

        try VaultService.changePassphrase(journalId: j.id, newPassphrase: "new")
        VaultService.lock(j.id)

        XCTAssertFalse(VaultService.unlock(journalId: j.id, passphrase: "old"), "old passphrase no longer works")
        XCTAssertTrue(VaultService.unlock(journalId: j.id, passphrase: "new"))
        VaultService.lock(j.id)
        XCTAssertTrue(VaultService.unlock(journalId: j.id, recoveryWords: recovery), "recovery wrap is untouched")
    }

    func testChangePassphraseRequiresUnlocked() throws {
        let j = try freshJournal()
        defer { try? DatabaseService.shared.deleteJournal(id: j.id, deleteEntries: true) }
        _ = try VaultService.createVault(journalId: j.id, passphrase: "pw", recoveryWords: recovery)
        VaultService.lock(j.id)
        XCTAssertThrowsError(try VaultService.changePassphrase(journalId: j.id, newPassphrase: "x"))
    }

    func testRemoveVaultDecryptsInPlace() throws {
        let j = try freshJournal("ToOpen")
        defer { try? DatabaseService.shared.deleteJournal(id: j.id, deleteEntries: true) }
        var e = Entry.newDraft(title: "Sealed", journalId: j.id)
        e.bodyMarkdown = "back to plaintext"
        try DatabaseService.shared.insertEntry(e)

        try makeVault(j.id, passphrase: "pw")
        XCTAssertTrue(VaultService.isSealed(try rawRow(e.id).bodyMarkdown))

        try removeVault(j.id)

        // Plaintext on disk again, flag + envelope gone, key dropped.
        let raw = try rawRow(e.id)
        XCTAssertFalse(VaultService.isSealed(raw.bodyMarkdown))
        XCTAssertEqual(raw.bodyMarkdown, "back to plaintext")
        let journal = try XCTUnwrap(try DatabaseService.shared.fetchAllJournals().first { $0.id == j.id })
        XCTAssertFalse(journal.isVault)
        XCTAssertNil(try VaultService.loadEnvelope(journalId: j.id))
        XCTAssertFalse(VaultService.isUnlocked(j.id))
    }

    func testRemoveVaultRequiresUnlocked() throws {
        let j = try freshJournal()
        defer { try? DatabaseService.shared.deleteJournal(id: j.id, deleteEntries: true) }
        try makeVault(j.id, passphrase: "pw")
        VaultService.lock(j.id)
        XCTAssertThrowsError(try removeVault(j.id))
    }
}

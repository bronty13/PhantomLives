import XCTest
import CryptoKit
import GRDB
@testable import PurpleDiary

/// Phase-9 vault attachment sealing: a vault entry's attachment `data` and
/// `thumbnail_data` blobs are ciphertext on disk and transparently decrypted on
/// read when the vault is unlocked, with the same locked-refusal and
/// convert/remove/move re-keying as entry text.
@MainActor
final class VaultAttachmentTests: XCTestCase {

    private let recovery = RecoveryKey.generate()
    private let db = DatabaseService.shared

    override func tearDown() { VaultService.lockAll(); super.tearDown() }

    private func vaultJournal(unlocked: Bool) throws -> Journal {
        let j = Journal.newDraft(name: "Secret")
        try db.insertJournal(j)
        _ = try VaultService.createVault(journalId: j.id, passphrase: "pw", recoveryWords: recovery)
        try db.setJournalVault(true, journalId: j.id)
        if !unlocked { VaultService.lock(j.id) }
        return j
    }
    private func entry(in journalId: String) throws -> Entry {
        let e = Entry.newDraft(title: "e", journalId: journalId)
        try db.insertEntry(e)
        return e
    }
    private func attachment(_ entryId: String, body: Data, thumb: Data?) -> Attachment {
        Attachment(id: UUID().uuidString, entryId: entryId, kind: "photo", filename: "p.jpg",
                   mimeType: "image/jpeg", sizeBytes: Int64(body.count), width: 8, height: 8,
                   data: body, thumbnailData: thumb, sourceAssetId: nil, createdAt: DatabaseService.isoNow())
    }
    private func rawAttachment(_ id: String) throws -> Attachment {
        try XCTUnwrap(try db.dbPool.read { d in try Attachment.fetchOne(d, key: id) })
    }

    func testInsertSealsBlobsAndReadDecrypts() throws {
        let j = try vaultJournal(unlocked: true)
        defer { try? db.deleteJournal(id: j.id, deleteEntries: true) }
        let e = try entry(in: j.id)
        let body = Data("the-actual-image-bytes".utf8)
        let thumb = Data("thumbnail-bytes".utf8)
        try db.insertAttachment(attachment(e.id, body: body, thumb: thumb))

        // On disk: sealed, plaintext absent.
        let id = try XCTUnwrap(try db.attachmentThumbs(forEntry: e.id).first?.id)
        let raw = try rawAttachment(id)
        XCTAssertTrue(VaultService.isSealedData(raw.data))
        XCTAssertTrue(VaultService.isSealedData(try XCTUnwrap(raw.thumbnailData)))
        XCTAssertFalse(raw.data.starts(with: Data("the-actual".utf8)))

        // Through the service (unlocked): plaintext back.
        let full = try XCTUnwrap(try db.attachment(id: id))
        XCTAssertEqual(full.data, body)
        XCTAssertEqual(full.thumbnailData, thumb)
        XCTAssertEqual(try db.attachments(forEntry: e.id).first?.data, body)
        XCTAssertEqual(try db.attachmentThumb(id: id)?.thumbnailData, thumb)
    }

    func testInsertIntoLockedVaultRefused() throws {
        let j = try vaultJournal(unlocked: true)
        defer { try? db.deleteJournal(id: j.id, deleteEntries: true) }
        let e = try entry(in: j.id)
        VaultService.lock(j.id)
        XCTAssertThrowsError(try db.insertAttachment(attachment(e.id, body: Data("x".utf8), thumb: nil))) { err in
            XCTAssertTrue(err is DatabaseService.VaultWriteError)
        }
    }

    func testConvertSealsExistingAttachmentsAndRemoveUnseals() throws {
        // Plain journal + entry + plaintext attachment.
        let j = Journal.newDraft(name: "Plain")
        try db.insertJournal(j)
        defer { try? db.deleteJournal(id: j.id, deleteEntries: true) }
        let e = try entry(in: j.id)
        let body = Data("photo-payload".utf8)
        try db.insertAttachment(attachment(e.id, body: body, thumb: Data("t".utf8)))
        let id = try XCTUnwrap(try db.attachmentThumbs(forEntry: e.id).first?.id)
        XCTAssertFalse(VaultService.isSealedData(try rawAttachment(id).data))

        // Convert to a vault (mirror AppState.makeVault's attachment step).
        let ck = try VaultService.createVault(journalId: j.id, passphrase: "pw", recoveryWords: recovery)
        try db.setJournalVault(true, journalId: j.id)
        try db.rekeyAttachments(inJournal: j.id, key: ck, seal: true)
        XCTAssertTrue(VaultService.isSealedData(try rawAttachment(id).data))
        XCTAssertEqual(try db.attachment(id: id)?.data, body, "still readable while unlocked")

        // Remove the vault → blobs decrypt in place.
        try db.rekeyAttachments(inJournal: j.id, key: ck, seal: false)
        let raw = try rawAttachment(id)
        XCTAssertFalse(VaultService.isSealedData(raw.data))
        XCTAssertEqual(raw.data, body)
    }

    func testMoveEntryWithAttachmentIntoVaultSeals() throws {
        let vault = try vaultJournal(unlocked: true)
        defer { try? db.deleteJournal(id: vault.id, deleteEntries: false) }
        let e = Entry.newDraft(title: "p", journalId: Journal.defaultId)
        try db.insertEntry(e)
        defer { try? db.deleteEntry(id: e.id) }
        let body = Data("moving-photo".utf8)
        try db.insertAttachment(attachment(e.id, body: body, thumb: nil))
        let id = try XCTUnwrap(try db.attachmentThumbs(forEntry: e.id).first?.id)
        XCTAssertFalse(VaultService.isSealedData(try rawAttachment(id).data))

        try db.setJournal(vault.id, forEntry: e.id)
        XCTAssertTrue(VaultService.isSealedData(try rawAttachment(id).data), "attachment sealed on move-in")
        XCTAssertEqual(try db.attachment(id: id)?.data, body)

        try db.setJournal(Journal.defaultId, forEntry: e.id)
        XCTAssertFalse(VaultService.isSealedData(try rawAttachment(id).data), "unsealed on move-out")
    }
}

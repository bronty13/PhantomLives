import AppKit
import CryptoKit
import Foundation
import GRDB
import UniformTypeIdentifiers

/// Phase 5 — content-addressed local file storage for attachments.
///
/// Per `HANDOFF.md` § Attachments storage (2026-05-10), file content
/// lives at `~/Library/Application Support/PurpleLife/attachments/<sha256>.<ext>`.
/// The `attachments` row is metadata only. Same content referenced by
/// multiple object/field pairs de-duplicates on disk (one file, many
/// refs). Deleting a ref leaves the file in place unless no other ref
/// uses it.
///
/// **Encryption-at-rest (slice A3)**: file content is wrapped with
/// `EncryptedJSON` under the `KeyStore` DEK before being written to
/// disk. The sha256 used for content-addressing is still computed over
/// the *plaintext* so dedup keeps working; the on-disk bytes are AES-GCM
/// ciphertext. `read(sha256:)` decrypts on demand; `image(forSha256:)`
/// is the NSImage convenience. The legacy `fileURL(forSha256:)` is
/// retained for callers that need a stable path identifier (it points
/// at ciphertext now — never feed it to `NSImage(contentsOf:)`).
///
/// CloudKit `CKAsset` sync is deferred to a follow-up — Phase 4 only
/// syncs the JSON `fields_json` blob.
@MainActor
enum AttachmentService {

    /// Resolver wired by `AppState` at launch so this enum-of-statics
    /// can fetch the current encryption key without taking a `KeyStore`
    /// dependency at the call site. Returns nil when no key is set —
    /// in that mode reads/writes operate on plaintext bytes, which is
    /// the path that XCTest-mode tests exercise.
    static var keyResolver: (() -> SymmetricKey?)?

    private static var currentKey: SymmetricKey? { keyResolver?() }

    /// Wired by `AppState` at launch — gives the service access to the
    /// CloudKit sync surface so `add()` / `deleteRow()` can fan out
    /// per-attachment pushes. Optional so tests that don't initialize
    /// sync still work (the push/delete becomes a no-op).
    static var sync: CloudKitSyncService?

    /// Lazy-fetch dedupe. When a read path finds a row with no local
    /// file, it kicks off a CloudKit fetch via the sync service; the
    /// fetch is fire-and-forget and posts
    /// `objectsChangedRemotelyNotification` when done. Concurrent
    /// callers asking for the same sha (e.g. a record list rendering
    /// 12 photos that share the same shoot cover thumbnail) must NOT
    /// all enqueue duplicate fetches. The in-flight set guards that.
    /// `AttachmentService` is `@MainActor`, so all access to this
    /// set is already serialized via the main actor.
    private static var inFlightFetches: Set<String> = []

    enum AttachError: Error, LocalizedError {
        case fileNotFound(URL)
        case copyFailed(String)
        case missingParent(String)

        var errorDescription: String? {
            switch self {
            case .fileNotFound(let url): return "File not found: \(url.path)"
            case .copyFailed(let msg):   return "Couldn't copy file: \(msg)"
            case .missingParent(let id): return "Attachment parent missing: \(id)"
            }
        }
    }

    static var directory: URL {
        DatabaseService.shared.attachmentsDirectory
    }

    // MARK: - Add

    /// Imports a file from anywhere on disk into the attachments store.
    /// Returns the persisted `Attachment` row (including the new sha256
    /// ref) so callers can write `attachment.sha256` into a record's
    /// `.attachment` field via `ObjectEngine.update`.
    ///
    /// The sha256 is computed over the *plaintext* (so dedup spans the
    /// encrypted-at-rest boundary cleanly). The on-disk file is wrapped
    /// with `EncryptedJSON` when a DEK is available.
    @discardableResult
    static func add(from source: URL, parentObjectId: String, fieldKey: String) throws -> Attachment {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else { throw AttachError.fileNotFound(source) }

        let plaintext = try Data(contentsOf: source)
        let hash = sha256(data: plaintext)
        let ext = source.pathExtension.lowercased()
        let storedURL = directory.appendingPathComponent(filename(for: hash, ext: ext))

        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: storedURL.path) {
            do {
                _ = try EncryptedJSON.safeWrite(plaintext, to: storedURL, key: currentKey)
            } catch {
                throw AttachError.copyFailed(error.localizedDescription)
            }
        }

        let mime = UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
        let row = Attachment(
            id: UUID().uuidString,
            parentObjectId: parentObjectId,
            fieldKey: fieldKey,
            sha256: hash,
            filename: source.lastPathComponent,
            mimeType: mime,
            sizeBytes: Int64(plaintext.count),
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        try DatabaseService.shared.dbPool.write { db in
            try row.insert(db)
        }
        // Fire-and-forget CloudKit push. Same pattern as `ObjectEngine`
        // and `SchemaRegistry` — local write completes first; the
        // sync hop happens out of band so a flaky network never
        // blocks the user's attach action.
        if let sync = sync {
            Task { await sync.pushAttachment(row) }
        }
        return row
    }

    // MARK: - Lookup

    /// Returns the on-disk URL for a stored attachment, or `nil` if no
    /// row for that sha256 exists or the file has been pruned. The URL
    /// points at ciphertext when at-rest encryption is in force — use
    /// `read(sha256:)` for content, `image(forSha256:)` for images.
    ///
    /// **Lazy fetch.** If a row exists but the file is missing locally
    /// (the normal state for an attachment that just synced in from a
    /// peer Mac via CloudKit), this method kicks off a background
    /// fetch through `CloudKitSyncService.fetchAttachmentAssetIfMissing`
    /// and returns `nil` for THIS call. When the fetch completes and
    /// writes the file, `objectsChangedRemotelyNotification` fires
    /// and the calling view re-renders, at which point this method
    /// returns the URL. Concurrent calls for the same sha are
    /// deduplicated via the in-flight set.
    static func fileURL(forSha256 hash: String) -> URL? {
        do {
            let row = try DatabaseService.shared.dbPool.read { db in
                try Attachment.filter(Column("sha256") == hash).fetchOne(db)
            }
            guard let row else { return nil }
            let url = directory.appendingPathComponent(filename(for: hash, ext: pathExt(of: row.filename)))
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
            requestLazyFetchIfNeeded(attachmentId: row.id, sha256: hash)
            return nil
        } catch {
            NSLog("PurpleLife: AttachmentService.fileURL failed — \(error.localizedDescription)")
            return nil
        }
    }

    /// Fire-and-forget kickoff of a CloudKit fetch for the asset bytes
    /// of an attachment whose row exists locally but whose file
    /// doesn't. Deduplicates concurrent requests by sha. Caller (the
    /// `fileURL` / `read` / `image` accessors) returns `nil` for the
    /// current call; the view re-renders on
    /// `objectsChangedRemotelyNotification` after the fetch completes.
    private static func requestLazyFetchIfNeeded(attachmentId: String, sha256: String) {
        guard let sync else { return }
        if inFlightFetches.contains(sha256) { return }
        inFlightFetches.insert(sha256)
        Task { @MainActor in
            await sync.fetchAttachmentAssetIfMissing(
                attachmentId: attachmentId, sha256: sha256
            )
            inFlightFetches.remove(sha256)
        }
    }

    /// Returns the **plaintext** content bytes for a stored attachment,
    /// decrypting on the fly when the file is wrapped. Returns nil when
    /// the file is missing or when it's wrapped and no DEK is available
    /// (locked keystore). Throwing is reserved for tamper detection —
    /// AES-GCM throws if the ciphertext was corrupted.
    static func read(sha256 hash: String) throws -> Data? {
        guard let url = fileURL(forSha256: hash) else { return nil }
        let raw = try Data(contentsOf: url)
        return try EncryptedJSON.unwrap(raw, key: currentKey)
    }

    /// Convenience: load an image-bearing attachment. Returns nil for
    /// non-image content, missing files, or decrypt failures. Callers
    /// that need to surface decrypt errors should use `read(sha256:)`
    /// directly.
    static func image(forSha256 hash: String) -> NSImage? {
        guard let data = try? read(sha256: hash) else { return nil }
        return NSImage(data: data)
    }

    /// All attachment rows for one object — sorted by field then created_at.
    static func list(forParent parentObjectId: String) throws -> [Attachment] {
        try DatabaseService.shared.dbPool.read { db in
            try Attachment
                .filter(Column("parent_object_id") == parentObjectId)
                .order(Column("field_key"), Column("created_at"))
                .fetchAll(db)
        }
    }

    /// First attachment row for a specific (parent, field) — `.attachment`
    /// fields hold a single ref today; this is the lookup helper.
    static func first(forParent parentObjectId: String, fieldKey: String) throws -> Attachment? {
        try DatabaseService.shared.dbPool.read { db in
            try Attachment
                .filter(Column("parent_object_id") == parentObjectId
                        && Column("field_key") == fieldKey)
                .order(Column("created_at").desc)
                .fetchOne(db)
        }
    }

    // MARK: - Delete

    /// Removes a single attachment row. The on-disk content file is
    /// kept if any other row still references the same sha256. Returns
    /// `true` if the row was removed.
    @discardableResult
    static func deleteRow(id: String) throws -> Bool {
        let fm = FileManager.default
        let removed: Bool = try DatabaseService.shared.dbPool.write { db in
            guard let row = try Attachment.fetchOne(db, key: id) else { return false }
            _ = try Attachment.deleteOne(db, key: id)

            // Reference count check — only delete the file when no row
            // shares its sha256.
            let remaining = try Attachment
                .filter(Column("sha256") == row.sha256)
                .fetchCount(db)
            if remaining == 0 {
                let url = directory.appendingPathComponent(filename(for: row.sha256, ext: pathExt(of: row.filename)))
                try? fm.removeItem(at: url)
            }
            return true
        }
        // Echo the deletion to CloudKit so peers drop their copies
        // too. Same fire-and-forget shape as the add() push.
        if removed, let sync = sync {
            Task { await sync.pushDeleteAttachment(id: id) }
        }
        return removed
    }

    /// Convenience: clear the attachment ref attached to a specific
    /// (parent, field). Used when the user clears a `.attachment`
    /// field in the detail editor.
    static func clear(forParent parentObjectId: String, fieldKey: String) throws {
        let rows = try DatabaseService.shared.dbPool.read { db in
            try Attachment
                .filter(Column("parent_object_id") == parentObjectId
                        && Column("field_key") == fieldKey)
                .fetchAll(db)
        }
        for row in rows {
            try deleteRow(id: row.id)
        }
    }

    // MARK: - One-shot encrypt-existing-files sweep

    /// Walks the attachments directory and wraps any file that doesn't
    /// already have the `EncryptedJSON` magic header. Idempotent — files
    /// already encrypted are skipped. Returns the (encrypted, skipped)
    /// counts so the caller can log a one-line summary.
    ///
    /// Failure mode: per-file `try?` so one bad file doesn't abort the
    /// sweep; failures land in `NSLog`. The user's data is never lost —
    /// the original file is only removed after the encrypted version is
    /// in place (atomic write via `EncryptedJSON.safeWrite`).
    @discardableResult
    static func encryptExistingFilesIfNeeded() -> (encrypted: Int, skipped: Int) {
        guard let key = currentKey else { return (0, 0) }
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: directory,
                                                        includingPropertiesForKeys: nil) else {
            return (0, 0)
        }
        var encrypted = 0
        var skipped = 0
        for url in entries {
            // Only touch regular files — skip subdirs / symlinks.
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { continue }
            guard let data = try? Data(contentsOf: url) else { continue }
            if EncryptedJSON.hasMagic(data) {
                skipped += 1
                continue
            }
            do {
                let wrapped = try EncryptedJSON.wrap(data, key: key)
                try wrapped.write(to: url, options: .atomic)
                encrypted += 1
            } catch {
                NSLog("PurpleLife: failed to encrypt attachment \(url.lastPathComponent) — \(error.localizedDescription)")
            }
        }
        if encrypted > 0 {
            NSLog("PurpleLife: encrypted \(encrypted) attachment file(s) on launch; \(skipped) already encrypted")
        }
        return (encrypted, skipped)
    }

    // MARK: - Sync ingress

    /// Sync path: write plaintext bytes that just arrived from a peer
    /// to the local attachments directory, re-wrapped under this
    /// Mac's local DEK. Caller (CloudKitSyncService.applyRemoteAttachment)
    /// has already confirmed the sha256 matches the metadata; we just
    /// route the bytes through `EncryptedJSON.safeWrite` so the
    /// on-disk shape is identical to a locally-added attachment.
    ///
    /// No-op when the file already exists at the expected path (content
    /// is content-addressed; bytes already there match by sha).
    /// Does NOT push back to CloudKit — that would loop with the same
    /// record we just received.
    static func writeIncomingPlaintext(_ plaintext: Data, sha256 hash: String, filename: String) throws {
        let fm = FileManager.default
        let ext = (filename as NSString).pathExtension.lowercased()
        let url = directory.appendingPathComponent(self.filename(for: hash, ext: ext))
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        if fm.fileExists(atPath: url.path) { return }
        do {
            _ = try EncryptedJSON.safeWrite(plaintext, to: url, key: currentKey)
        } catch {
            throw AttachError.copyFailed(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    static func sha256(data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func filename(for hash: String, ext: String) -> String {
        ext.isEmpty ? hash : "\(hash).\(ext)"
    }

    private static func pathExt(of filename: String) -> String {
        (filename as NSString).pathExtension.lowercased()
    }
}

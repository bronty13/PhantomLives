import Foundation
import CryptoKit
import AppKit
import UniformTypeIdentifiers

/// Encrypted blob storage for arbitrary file attachments. Mirrors the
/// `LogStore` pattern: a single off-main actor, an index file mapping
/// stable UUIDs to filesystem locations + metadata, and a per-file
/// `.bin` payload sealed with the keystore-derived DEK via
/// `EncryptedJSON.safeWrite`.
///
/// What it stores
/// --------------
/// Each blob is one file at `<supportDir>/blobs/<uuid>.bin` plus a
/// row in `<supportDir>/blobs/index.json`. The row carries the
/// original filename, MIME type guess, byte size BEFORE encryption,
/// creation timestamp, and an optional `attachedTo` UUID linking
/// back to the entity that owns it (an AddressEntry today; future
/// channels / messages later). The blob payload itself is opaque
/// bytes — could be an image, a document, a recording, a binary —
/// the store doesn't care.
///
/// Why a separate store rather than inline `Data` on AddressEntry?
/// ----------------------------------------------------------------
/// Inline `Data` (the photo path) is fine for tiny payloads; an avatar
/// rounds to ~10 KB. A document attachment can easily be 5 MB. Inlining
/// 5 MB of base64 in `settings.json` makes every settings save rewrite
/// the whole encrypted envelope and forces every settings load to
/// decrypt that megabyte. The blob store keeps `settings.json` small
/// — only the metadata reference lives there — and pays the encrypt /
/// decrypt cost only when the user actually opens the attachment.
///
/// Owner reference
/// ---------------
/// `AddressEntry.attachments: [AttachmentRef]` carries the (id,
/// filename, sizeBytes, contentType) tuple inline so the editor can
/// list attachments without round-tripping through the store. The
/// store is the source of truth for the actual bytes; the inline
/// refs are a denormalised view for UI rendering. When the user
/// removes an attachment, the editor flips both: drops the ref AND
/// asks the store to delete the blob.
///
/// Concurrency
/// -----------
/// `actor` so reads / writes serialise without a lock dance. The
/// EncryptedJSON envelope handles the cryptography; this layer just
/// owns the file naming + index + lifecycle.
actor BlobStore {

    /// Per-blob metadata persisted in `index.json`.
    struct BlobRecord: Codable, Identifiable, Hashable {
        var id: UUID = UUID()
        var filename: String
        /// MIME type or `application/octet-stream` when guessing fails.
        /// Used by the UI for icon selection and Open With routing.
        var contentType: String
        /// Plaintext byte size before encryption. Roughly equals the
        /// disk file size minus the AES-GCM tag + magic header.
        var sizeBytes: Int
        var createdAt: Date = Date()
        /// Owner reference — the UUID of the entity (AddressEntry
        /// today) the user attached this blob to. nil = orphan; the
        /// store keeps it but no editor surfaces it. Future GC pass
        /// could prune orphans older than N days.
        var attachedTo: UUID?
    }

    /// Lightweight per-attachment reference inlined on owners
    /// (e.g. `AddressEntry.attachments`) so editors render lists
    /// without touching the store. Mirrors the on-disk record's
    /// shape minus the timestamps the UI doesn't need at list time.
    struct AttachmentRef: Codable, Identifiable, Hashable {
        var id: UUID
        var filename: String
        var contentType: String
        var sizeBytes: Int
    }

    private let baseDir: URL
    private let indexURL: URL
    private var index: [UUID: BlobRecord] = [:]
    private var key: SymmetricKey?

    init(supportDirectoryURL: URL) {
        let dir = supportDirectoryURL.appendingPathComponent("blobs", isDirectory: true)
        self.baseDir = dir
        self.indexURL = dir.appendingPathComponent("index.json")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Inline the load — calling actor-isolated `loadIndex()` from
        // init triggers a Swift 6 isolation diagnostic. The work is
        // synchronous and pre-isolation, so doing it inline is safe.
        if let raw = try? Data(contentsOf: indexURL),
           let plain = try? EncryptedJSON.unwrap(raw, key: nil),
           let decoded = try? JSONDecoder().decode([BlobRecord].self, from: plain) {
            self.index = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
        }
        // Encrypted files at init time stay empty until the keystore
        // pushes a key in via setEncryptionKey, which re-loads.
    }

    /// Push the keystore DEK in. nil = plaintext mode (no key set up
    /// yet); reads still succeed against unencrypted-on-disk files.
    /// Called by ChatModel whenever the keystore unlocks / locks /
    /// changes its current key.
    func setEncryptionKey(_ key: SymmetricKey?) {
        let changed = (key != nil) != (self.key != nil)
        self.key = key
        if changed {
            // Re-load the index so an encrypted index that was
            // unreadable a moment ago decodes now (matches
            // BotHost.setEncryptionKey behaviour).
            loadIndex()
        }
    }

    // MARK: - CRUD

    /// Persist `data` as a new blob with the given metadata. Returns
    /// the new record's id (also embedded in the record itself), or
    /// nil on I/O failure. Caller is responsible for inlining the
    /// matching AttachmentRef on the owner.
    @discardableResult
    func store(data: Data,
               filename: String,
               contentType: String,
               attachedTo: UUID?) -> BlobRecord? {
        let record = BlobRecord(
            filename: filename,
            contentType: contentType.isEmpty ? "application/octet-stream" : contentType,
            sizeBytes: data.count,
            attachedTo: attachedTo
        )
        let url = blobURL(for: record.id)
        do {
            _ = try EncryptedJSON.safeWrite(data, to: url, key: key)
        } catch {
            return nil
        }
        index[record.id] = record
        saveIndex()
        return record
    }

    /// Convenience overload that reads `fileURL` from disk before
    /// storing. Returns nil when the file isn't readable.
    @discardableResult
    func store(fileURL: URL, attachedTo: UUID?) -> BlobRecord? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let mime = mimeTypeGuess(for: fileURL)
        return store(
            data: data,
            filename: fileURL.lastPathComponent,
            contentType: mime,
            attachedTo: attachedTo
        )
    }

    /// Read the plaintext bytes for `id`. nil when the blob is missing
    /// or the keystore is locked. Caller decides what to do with the
    /// bytes (write to a temp file for Open / Reveal, hand to a
    /// preview view, etc.).
    func read(_ id: UUID) -> Data? {
        let url = blobURL(for: id)
        guard let raw = try? Data(contentsOf: url) else { return nil }
        return try? EncryptedJSON.unwrap(raw, key: key)
    }

    /// Drop a blob. Removes the on-disk file AND the index row.
    /// Idempotent — calling twice is fine.
    func delete(_ id: UUID) {
        let url = blobURL(for: id)
        try? FileManager.default.removeItem(at: url)
        index.removeValue(forKey: id)
        saveIndex()
    }

    /// Snapshot of the index, mainly for diagnostic UI. Sorted by
    /// most-recent first.
    func allRecords() -> [BlobRecord] {
        index.values.sorted { $0.createdAt > $1.createdAt }
    }

    /// Look up a single record (metadata only — no payload read).
    /// Returns nil when the id is unknown, which can happen if the
    /// owner inlined an AttachmentRef that's since been deleted out
    /// from under it (the editor uses this to filter stale rows).
    func record(_ id: UUID) -> BlobRecord? {
        index[id]
    }

    /// Materialise a blob into a temp file for "Open With…" / "Reveal
    /// in Finder" affordances. Returns the temp URL on success;
    /// caller is responsible for not leaning on the file long-term
    /// (the OS will reap the temp dir). nil = blob missing or locked.
    func writeToTempFile(_ id: UUID) -> URL? {
        guard let plain = read(id), let rec = record(id) else { return nil }
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PurpleIRC-blobs", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let url = tmpDir.appendingPathComponent(rec.filename)
        try? plain.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Index persistence

    private func loadIndex() {
        guard let raw = try? Data(contentsOf: indexURL) else {
            index = [:]
            return
        }
        guard let plain = try? EncryptedJSON.unwrap(raw, key: key),
              let decoded = try? JSONDecoder().decode([BlobRecord].self, from: plain) else {
            // Encrypted index with no key yet, or a corrupt file —
            // start empty rather than crash; the user's data on disk
            // is still safe.
            index = [:]
            return
        }
        index = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
    }

    private func saveIndex() {
        let records = Array(index.values)
        guard let json = try? JSONEncoder().encode(records) else { return }
        _ = try? EncryptedJSON.safeWrite(json, to: indexURL, key: key)
    }

    // MARK: - Helpers

    private func blobURL(for id: UUID) -> URL {
        baseDir.appendingPathComponent("\(id.uuidString).bin", isDirectory: false)
    }

    /// Quick MIME guess from the file extension. Wraps the system
    /// `UTType` machinery; falls back to `application/octet-stream`
    /// when the extension isn't recognised. Off-main safe.
    private func mimeTypeGuess(for url: URL) -> String {
        let ext = url.pathExtension
        guard !ext.isEmpty else { return "application/octet-stream" }
        if let type = UTType(filenameExtension: ext),
           let mime = type.preferredMIMEType {
            return mime
        }
        return "application/octet-stream"
    }
}


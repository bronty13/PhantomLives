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
/// CloudKit `CKAsset` sync is deferred to a follow-up — Phase 4 only
/// syncs the JSON `fields_json` blob.
@MainActor
enum AttachmentService {

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
    @discardableResult
    static func add(from source: URL, parentObjectId: String, fieldKey: String) throws -> Attachment {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else { throw AttachError.fileNotFound(source) }

        let data = try Data(contentsOf: source)
        let hash = sha256(data: data)
        let ext = source.pathExtension.lowercased()
        let storedURL = directory.appendingPathComponent(filename(for: hash, ext: ext))

        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: storedURL.path) {
            do {
                try data.write(to: storedURL, options: .atomic)
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
            sizeBytes: Int64(data.count),
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        try DatabaseService.shared.dbPool.write { db in
            try row.insert(db)
        }
        return row
    }

    // MARK: - Lookup

    /// Returns the on-disk URL for a stored attachment, or `nil` if no
    /// row for that sha256 exists or the file has been pruned. Callers
    /// should treat `nil` as "rendering placeholder".
    static func fileURL(forSha256 hash: String) -> URL? {
        do {
            let row = try DatabaseService.shared.dbPool.read { db in
                try Attachment.filter(Column("sha256") == hash).fetchOne(db)
            }
            guard let row else { return nil }
            let url = directory.appendingPathComponent(filename(for: hash, ext: pathExt(of: row.filename)))
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        } catch {
            NSLog("PurpleLife: AttachmentService.fileURL failed — \(error.localizedDescription)")
            return nil
        }
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
        return try DatabaseService.shared.dbPool.write { db in
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

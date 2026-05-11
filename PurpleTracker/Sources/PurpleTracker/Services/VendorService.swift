import Foundation
import GRDB
import CryptoKit
import UniformTypeIdentifiers

/// CRUD wrappers for the Third Party domain. Lives parallel to the Matter
/// methods on `DatabaseService` — kept in its own service so vendor work can
/// evolve without churning the main file.
@MainActor
enum VendorService {

    private static var pool: DatabasePool { DatabaseService.shared.dbPool }

    // MARK: - Vendor

    static func fetchAllLive() throws -> [Vendor] {
        try pool.read { db in
            try Vendor.filter(Column("deleted_at") == nil)
                .order(Column("name").asc)
                .fetchAll(db)
        }
    }

    static func fetchTrashed() throws -> [Vendor] {
        try pool.read { db in
            try Vendor.filter(Column("deleted_at") != nil)
                .order(Column("deleted_at").desc)
                .fetchAll(db)
        }
    }

    static func fetch(id: String) throws -> Vendor? {
        try pool.read { db in try Vendor.fetchOne(db, key: id) }
    }

    static func insert(_ vendor: Vendor) throws {
        try pool.write { db in
            var v = vendor
            try v.insert(db)
        }
    }

    /// Update + bump `updated_at`.
    static func update(_ vendor: Vendor) throws {
        var v = vendor
        v.updatedAt = Date()
        try pool.write { db in try v.update(db) }
    }

    /// Soft-delete — set `deleted_at`. Cascades for matters are NOT triggered;
    /// matter rows keep their `vendor_id` pointing at the trashed vendor.
    /// `purge` performs the hard delete + cascade.
    static func softDelete(id: String) throws {
        try pool.write { db in
            try db.execute(sql: "UPDATE vendor SET deleted_at = ? WHERE id = ?",
                           arguments: [Date(), id])
        }
    }

    static func restore(id: String) throws {
        try pool.write { db in
            try db.execute(sql: "UPDATE vendor SET deleted_at = NULL WHERE id = ?",
                           arguments: [id])
        }
    }

    static func purge(id: String) throws {
        try pool.write { db in _ = try Vendor.deleteOne(db, key: id) }
    }

    // MARK: - Contacts

    static func fetchContacts(vendorId: String) throws -> [VendorContact] {
        try pool.read { db in
            try VendorContact
                .filter(Column("vendor_id") == vendorId)
                .fetchAll(db)
        }
    }

    static func upsertContact(_ c: VendorContact) throws {
        try pool.write { db in var x = c; try x.save(db) }
    }

    static func deleteContact(id: String) throws {
        try pool.write { db in _ = try VendorContact.deleteOne(db, key: id) }
    }

    // MARK: - Products

    static func fetchProducts(vendorId: String) throws -> [VendorProduct] {
        try pool.read { db in
            try VendorProduct
                .filter(Column("vendor_id") == vendorId)
                .order(Column("sort_order").asc)
                .fetchAll(db)
        }
    }

    static func upsertProduct(_ p: VendorProduct) throws {
        try pool.write { db in var x = p; try x.save(db) }
    }

    static func deleteProduct(id: String) throws {
        try pool.write { db in _ = try VendorProduct.deleteOne(db, key: id) }
    }

    // MARK: - Year amounts

    static func fetchYearAmounts(vendorId: String) throws -> [VendorYearAmount] {
        try pool.read { db in
            try VendorYearAmount
                .filter(Column("vendor_id") == vendorId)
                .order(Column("year").asc)
                .fetchAll(db)
        }
    }

    /// Upsert one (vendor, year) row. Composite PK forces save semantics.
    static func upsertYearAmount(_ y: VendorYearAmount) throws {
        try pool.write { db in
            try db.execute(
                sql: """
                INSERT INTO vendor_year_amount (vendor_id, year, budget_cents, actual_override_cents)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(vendor_id, year) DO UPDATE SET
                  budget_cents = excluded.budget_cents,
                  actual_override_cents = excluded.actual_override_cents
                """,
                arguments: [y.vendorId, y.year, y.budgetCents, y.actualOverrideCents]
            )
        }
    }

    // MARK: - Notes

    static func fetchNotes(vendorId: String) throws -> [VendorNote] {
        try pool.read { db in
            try VendorNote
                .filter(Column("vendor_id") == vendorId)
                .order(Column("created_at").desc)
                .fetchAll(db)
        }
    }

    static func upsertNote(_ n: VendorNote) throws {
        try pool.write { db in var x = n; try x.save(db) }
    }

    static func deleteNote(id: String) throws {
        try pool.write { db in _ = try VendorNote.deleteOne(db, key: id) }
    }

    // MARK: - Attachments

    static func fetchAttachments(vendorId: String, kind: VendorAttachmentKind? = nil, parentId: String? = nil) throws -> [VendorAttachment] {
        try pool.read { db in
            var q = VendorAttachment.filter(Column("vendor_id") == vendorId)
            if let kind { q = q.filter(Column("kind") == kind.rawValue) }
            if let parentId { q = q.filter(Column("parent_id") == parentId) }
            return try q.order(Column("added_at").asc).fetchAll(db)
        }
    }

    static func fetchAttachmentsMetadata(vendorId: String, kind: VendorAttachmentKind? = nil, parentId: String? = nil) throws -> [(id: String, filename: String, sizeBytes: Int64, mimeType: String, sha1: String, lastVerifyOk: Bool, kind: String, parentId: String?)] {
        try pool.read { db in
            var sql = """
                SELECT id, filename, size_bytes, mime_type, sha1, last_verify_ok, kind, parent_id
                FROM vendor_attachment WHERE vendor_id = ?
                """
            var args: [DatabaseValueConvertible] = [vendorId]
            if let kind {
                sql += " AND kind = ?"
                args.append(kind.rawValue)
            }
            if let parentId {
                sql += " AND parent_id = ?"
                args.append(parentId)
            }
            sql += " ORDER BY added_at ASC"
            return try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args)).map { r in
                (
                    id: r["id"] as String,
                    filename: r["filename"] as String,
                    sizeBytes: r["size_bytes"] as Int64,
                    mimeType: r["mime_type"] as String,
                    sha1: r["sha1"] as String,
                    lastVerifyOk: (r["last_verify_ok"] as Int) != 0,
                    kind: r["kind"] as String,
                    parentId: r["parent_id"] as String?
                )
            }
        }
    }

    /// Ingest a file from disk → BLOB row.
    static func ingestAttachment(fileURL: URL, vendorId: String, kind: VendorAttachmentKind, parentId: String? = nil) throws -> VendorAttachment {
        let data = try Data(contentsOf: fileURL)
        let h = AttachmentService.hashes(for: data)
        let mime = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType
            ?? "application/octet-stream"
        let a = VendorAttachment(
            id: UUID().uuidString,
            vendorId: vendorId,
            kind: kind.rawValue,
            parentId: parentId,
            filename: fileURL.lastPathComponent,
            sizeBytes: Int64(data.count),
            mimeType: mime,
            data: data,
            md5: h.md5,
            sha1: h.sha1,
            sha256: h.sha256,
            addedAt: Date(),
            lastVerifiedAt: Date(),
            lastVerifyOk: true
        )
        try pool.write { db in var x = a; try x.insert(db) }
        return a
    }

    /// Verify SHA1 over the BLOB and update bookkeeping. Returns (tempURL, verified).
    static func openAttachment(id: String) throws -> (url: URL, verified: Bool) {
        guard let att: VendorAttachment = try pool.read({ db in
            try VendorAttachment.fetchOne(db, key: id)
        }) else {
            throw NSError(domain: "PurpleTracker", code: 404,
                          userInfo: [NSLocalizedDescriptionKey: "Vendor attachment not found"])
        }
        let recomputed = AttachmentService.hashes(for: att.data).sha1
        let ok = recomputed.caseInsensitiveCompare(att.sha1) == .orderedSame
        try pool.write { db in
            try db.execute(
                sql: "UPDATE vendor_attachment SET last_verified_at = ?, last_verify_ok = ? WHERE id = ?",
                arguments: [Date(), ok ? 1 : 0, att.id]
            )
        }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pt-vendor-\(att.id)-\(att.filename)")
        try? FileManager.default.removeItem(at: tempURL)
        try att.data.write(to: tempURL)
        return (tempURL, ok)
    }

    static func deleteAttachment(id: String) throws {
        try pool.write { db in _ = try VendorAttachment.deleteOne(db, key: id) }
    }

    // MARK: - Linked Matters

    /// Matters whose `vendor_id` points at this vendor (live only).
    static func fetchLinkedMatters(vendorId: String) throws -> [Matter] {
        try pool.read { db in
            try Matter
                .filter(Column("vendor_id") == vendorId)
                .filter(Column("deleted_at") == nil)
                .order(Column("modified_at").desc)
                .fetchAll(db)
        }
    }
}

import Foundation
import GRDB

/// Sole owner of the GRDB `DatabasePool` for `purplepeek.sqlite`. Runs the append-only
/// migrator at init and exposes thin per-record CRUD wrappers. Migration logic lives in
/// `static applyMigrations(to:)` so the test suite applies the *real* migrator against an
/// in-memory database instead of a duplicated fixture that would drift over time.
@MainActor
final class DatabaseService {
    static let shared = DatabaseService()

    private(set) var dbPool: DatabasePool

    static var supportDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("PurplePeek", isDirectory: true)
    }

    var databaseURL: URL {
        Self.supportDirectory.appendingPathComponent("purplepeek.sqlite")
    }

    private init() {
        let dir = Self.supportDirectory
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbURL = dir.appendingPathComponent("purplepeek.sqlite")
        dbPool = try! DatabasePool(path: dbURL.path)
        try! migrate()
    }

    /// Re-open the underlying GRDB pool against the on-disk database. Used after a
    /// backup-restore so the running process picks up the swapped file.
    func reopenDatabase() throws {
        dbPool = try DatabasePool(path: databaseURL.path)
        try migrate()
    }

    // MARK: - Migrations

    private func migrate() throws {
        try Self.applyMigrations(to: dbPool)
    }

    /// Public entry point so tests can apply the real schema to an in-memory
    /// `DatabaseQueue`. Add new versions here — never inside `init()` — and never edit a
    /// shipped migration (migrations are immutable once committed; see CLAUDE.md).
    static func applyMigrations(to writer: DatabaseWriter) throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial") { db in
            try db.create(table: "scan_roots") { t in
                t.column("path", .text).primaryKey()
                t.column("last_scanned_at", .text).notNull()
                t.column("total_files", .integer).notNull().defaults(to: 0)
                t.column("label", .text)
            }

            try db.create(table: "media_files") { t in
                t.column("id", .text).primaryKey()
                t.column("scan_root", .text).notNull()
                    .references("scan_roots", column: "path", onDelete: .cascade)
                t.column("file_path", .text).notNull().unique()
                t.column("file_name", .text).notNull()
                t.column("file_type", .text).notNull()      // photo | video | audio
                t.column("file_size", .integer)
                t.column("file_modified_at", .text)
                t.column("keep", .integer)                  // NULL=undecided, 1=keep, 0=skip
                t.column("is_favorite", .integer).notNull().defaults(to: 0)
                t.column("title", .text)
                t.column("caption", .text)
                t.column("imported_at", .text)
                t.column("exported_at", .text)
                t.column("deleted_at", .text)
                t.column("photos_asset_id", .text)
                t.column("created_at", .text).notNull()
                t.column("updated_at", .text).notNull()
            }
            try db.create(index: "idx_media_files_scan_root",   on: "media_files", columns: ["scan_root"])
            try db.create(index: "idx_media_files_keep",         on: "media_files", columns: ["keep"])
            try db.create(index: "idx_media_files_imported_at",  on: "media_files", columns: ["imported_at"])
            try db.create(index: "idx_media_files_deleted_at",   on: "media_files", columns: ["deleted_at"])

            try db.create(table: "keywords") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull().unique().collate(.nocase)
                t.column("source", .text).notNull().defaults(to: "local")
                t.column("created_at", .text).notNull()
            }

            try db.create(table: "file_keywords") { t in
                t.column("file_id", .text).notNull()
                    .references("media_files", column: "id", onDelete: .cascade)
                t.column("keyword_id", .text).notNull()
                    .references("keywords", column: "id", onDelete: .cascade)
                t.primaryKey(["file_id", "keyword_id"])
            }
            try db.create(index: "idx_file_keywords_keyword", on: "file_keywords", columns: ["keyword_id"])

            try db.create(table: "file_albums") { t in
                t.column("file_id", .text).notNull()
                    .references("media_files", column: "id", onDelete: .cascade)
                t.column("album_name", .text).notNull()
                t.primaryKey(["file_id", "album_name"])
            }
            try db.create(index: "idx_file_albums_album", on: "file_albums", columns: ["album_name"])
        }

        // v2: per-item "hidden" decision (mirrors PHAsset.isHidden). Added as a new
        // migration — v1_initial is shipped and must never be edited (CLAUDE.md).
        migrator.registerMigration("v2_add_is_hidden") { db in
            try db.alter(table: "media_files") { t in
                t.add(column: "is_hidden", .integer).notNull().defaults(to: 0)
            }
        }

        // v3: "missing on disk" timestamp. Set by a re-scan when a previously-discovered
        // file is no longer found under its scan root; cleared when the file reappears. Lets
        // a refresh reconcile deletions/moves without losing the user's decisions on a file
        // that may yet return (NULL = present, ISO string = first noticed gone).
        migrator.registerMigration("v3_add_missing_at") { db in
            try db.alter(table: "media_files") { t in
                t.add(column: "missing_at", .text)
            }
            try db.create(index: "idx_media_files_missing_at", on: "media_files", columns: ["missing_at"])
        }

        // v4: user-defined sidebar sections + per-root ordering. A root's `section_id` is NULL
        // when it lives in the implicit default ("Folders") group; `sort_order` orders roots
        // within their group. No DB-level FK on section_id — deleting a section falls its roots
        // back to the default group in app code (see `deleteSection`).
        migrator.registerMigration("v4_add_sidebar_sections") { db in
            try db.create(table: "sidebar_sections") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("sort_order", .integer).notNull().defaults(to: 0)
                t.column("created_at", .text).notNull()
            }
            try db.alter(table: "scan_roots") { t in
                t.add(column: "section_id", .text)
                t.add(column: "sort_order", .integer).notNull().defaults(to: 0)
            }
            try db.create(index: "idx_scan_roots_section", on: "scan_roots", columns: ["section_id"])
        }

        try migrator.migrate(writer)
    }

    // MARK: - ScanRoot reads

    func fetchAllScanRoots() throws -> [ScanRoot] {
        try dbPool.read { db in
            // Manual order is primary; recency is the tiebreak for roots that share a slot
            // (e.g. freshly scanned roots that haven't been reordered yet).
            try ScanRoot
                .order(Column("sort_order"), Column("last_scanned_at").desc)
                .fetchAll(db)
        }
    }

    // MARK: - Sidebar section reads

    func fetchAllSections() throws -> [SidebarSection] {
        try dbPool.read { db in
            try SidebarSection.order(Column("sort_order"), Column("name")).fetchAll(db)
        }
    }

    // MARK: - MediaFile reads

    func fetchMediaFiles(scanRoot: String) throws -> [MediaFile] {
        try dbPool.read { db in
            try MediaFile
                .filter(Column("scan_root") == scanRoot)
                .order(Column("file_path"))
                .fetchAll(db)
        }
    }

    // MARK: - Keyword reads

    func fetchAllKeywords() throws -> [Keyword] {
        try dbPool.read { db in
            try Keyword.order(Column("name")).fetchAll(db)
        }
    }

    // MARK: - Scan writes

    /// Create the scan-root row if it doesn't exist (so media_files' FK is satisfied). A new
    /// root appends to the end of the default group (one past the current max `sort_order`);
    /// an existing root is left untouched (its group + position are preserved).
    func ensureScanRoot(path: String, now: String) throws {
        try dbPool.write { db in
            try db.execute(
                sql: """
                INSERT OR IGNORE INTO scan_roots (path, last_scanned_at, total_files, sort_order)
                VALUES (?, ?, 0, (SELECT COALESCE(MAX(sort_order), -1) + 1 FROM scan_roots))
                """,
                arguments: [path, now]
            )
        }
    }

    func updateScanRootStats(path: String, totalFiles: Int, now: String) throws {
        try dbPool.write { db in
            try db.execute(
                sql: "UPDATE scan_roots SET total_files = ?, last_scanned_at = ? WHERE path = ?",
                arguments: [totalFiles, now, path]
            )
        }
    }

    // MARK: - MediaFile decision updates

    func updateKeep(id: String, keep: Int?, now: String) throws {
        try dbPool.write { db in
            try db.execute(sql: "UPDATE media_files SET keep = ?, updated_at = ? WHERE id = ?",
                           arguments: [keep, now, id])
        }
    }

    func updateFavorite(id: String, isFavorite: Bool, now: String) throws {
        try dbPool.write { db in
            try db.execute(sql: "UPDATE media_files SET is_favorite = ?, updated_at = ? WHERE id = ?",
                           arguments: [isFavorite ? 1 : 0, now, id])
        }
    }

    func updateHidden(id: String, isHidden: Bool, now: String) throws {
        try dbPool.write { db in
            try db.execute(sql: "UPDATE media_files SET is_hidden = ?, updated_at = ? WHERE id = ?",
                           arguments: [isHidden ? 1 : 0, now, id])
        }
    }

    func updateTitle(id: String, title: String?, now: String) throws {
        try dbPool.write { db in
            try db.execute(sql: "UPDATE media_files SET title = ?, updated_at = ? WHERE id = ?",
                           arguments: [title, now, id])
        }
    }

    func updateCaption(id: String, caption: String?, now: String) throws {
        try dbPool.write { db in
            try db.execute(sql: "UPDATE media_files SET caption = ?, updated_at = ? WHERE id = ?",
                           arguments: [caption, now, id])
        }
    }

    func markImported(id: String, assetId: String?, now: String) throws {
        try dbPool.write { db in
            try db.execute(sql: "UPDATE media_files SET imported_at = ?, photos_asset_id = ?, updated_at = ? WHERE id = ?",
                           arguments: [now, assetId, now, id])
        }
    }

    func markExported(id: String, now: String) throws {
        try dbPool.write { db in
            try db.execute(sql: "UPDATE media_files SET exported_at = ?, updated_at = ? WHERE id = ?",
                           arguments: [now, now, id])
        }
    }

    func markDeleted(id: String, now: String) throws {
        try dbPool.write { db in
            try db.execute(sql: "UPDATE media_files SET deleted_at = ?, updated_at = ? WHERE id = ?",
                           arguments: [now, now, id])
        }
    }

    // MARK: - Scan-root management (Settings → Scan Roots)

    /// Forget a scanned path entirely. The `ON DELETE CASCADE` chain removes its
    /// media_files and their keyword/album junction rows. Does NOT touch files on disk.
    func deleteScanRoot(path: String) throws {
        try dbPool.write { db in
            try db.execute(sql: "DELETE FROM scan_roots WHERE path = ?", arguments: [path])
        }
    }

    func updateScanRootLabel(path: String, label: String?) throws {
        try dbPool.write { db in
            try db.execute(sql: "UPDATE scan_roots SET label = ? WHERE path = ?", arguments: [label, path])
        }
    }

    // MARK: - Sidebar sections + ordering

    /// Create a section, appended after existing ones. Returns the new row.
    @discardableResult
    func createSection(name: String, now: String) throws -> SidebarSection {
        try dbPool.write { db in
            let order = try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(sort_order), -1) + 1 FROM sidebar_sections") ?? 0
            var section = SidebarSection(id: UUID().uuidString, name: name, sortOrder: order, createdAt: now)
            try section.insert(db)
            return section
        }
    }

    func renameSection(id: String, name: String) throws {
        try dbPool.write { db in
            try db.execute(sql: "UPDATE sidebar_sections SET name = ? WHERE id = ?", arguments: [name, id])
        }
    }

    /// Delete a section; its roots fall back to the default group (section_id ← NULL).
    func deleteSection(id: String) throws {
        try dbPool.write { db in
            try db.execute(sql: "UPDATE scan_roots SET section_id = NULL WHERE section_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM sidebar_sections WHERE id = ?", arguments: [id])
        }
    }

    /// Assign a root to a section (NULL = default group), placing it at the end of that group.
    /// `section_id IS ?` matches the NULL group when `sectionId` is nil.
    func setScanRootSection(path: String, sectionId: String?) throws {
        try dbPool.write { db in
            let order = try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(MAX(sort_order), -1) + 1 FROM scan_roots WHERE section_id IS ?",
                arguments: [sectionId]
            ) ?? 0
            try db.execute(
                sql: "UPDATE scan_roots SET section_id = ?, sort_order = ? WHERE path = ?",
                arguments: [sectionId, order, path]
            )
        }
    }

    /// Persist a new within-group order: assign 0…n-1 to the given paths in order.
    func reorderScanRoots(orderedPaths: [String]) throws {
        try dbPool.write { db in
            for (i, path) in orderedPaths.enumerated() {
                try db.execute(sql: "UPDATE scan_roots SET sort_order = ? WHERE path = ?", arguments: [i, path])
            }
        }
    }

    /// Remove scan roots not scanned since `cutoff` (ISO string). Returns the count removed.
    @discardableResult
    func deleteScanRootsOlderThan(cutoff: String) throws -> Int {
        try dbPool.write { db in
            let stale = try String.fetchAll(db, sql: "SELECT path FROM scan_roots WHERE last_scanned_at < ?",
                                            arguments: [cutoff])
            for path in stale {
                try db.execute(sql: "DELETE FROM scan_roots WHERE path = ?", arguments: [path])
            }
            return stale.count
        }
    }

    // MARK: - Keyword CRUD

    /// Create a keyword (or return the existing one with the same case-insensitive name).
    @discardableResult
    func createKeyword(name: String, source: String = "local", now: String) throws -> Keyword {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return try dbPool.write { db in
            if let existing = try Keyword.filter(Column("name") == trimmed).fetchOne(db) {
                return existing
            }
            var kw = Keyword(id: UUID().uuidString, name: trimmed, source: source, createdAt: now)
            try kw.insert(db)
            return kw
        }
    }

    /// Bulk-add keyword names (skipping ones that already exist, case-insensitively).
    /// Returns the number newly inserted.
    @discardableResult
    func importKeywords(names: [String], source: String, now: String) throws -> Int {
        try dbPool.write { db in
            var added = 0
            for raw in names {
                let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                if try Keyword.filter(Column("name") == name).fetchCount(db) == 0 {
                    try db.execute(sql: "INSERT INTO keywords (id,name,source,created_at) VALUES (?,?,?,?)",
                                   arguments: [UUID().uuidString, name, source, now])
                    added += 1
                }
            }
            return added
        }
    }

    func deleteKeyword(id: String) throws {
        try dbPool.write { db in
            _ = try Keyword.deleteOne(db, key: id)   // cascade removes file_keywords rows
        }
    }

    func keywordUsageCount(keywordId: String) throws -> Int {
        try dbPool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM file_keywords WHERE keyword_id = ?",
                             arguments: [keywordId]) ?? 0
        }
    }

    // MARK: - File ⇄ Keyword junction

    func keywordIds(forFile fileId: String) throws -> [String] {
        try dbPool.read { db in
            try String.fetchAll(db, sql: "SELECT keyword_id FROM file_keywords WHERE file_id = ?",
                                arguments: [fileId])
        }
    }

    /// Keyword *names* for a file (for embedding into Photos imports).
    func keywordNames(forFile fileId: String) throws -> [String] {
        try dbPool.read { db in
            try String.fetchAll(db, sql: """
                SELECT k.name FROM file_keywords fk
                JOIN keywords k ON k.id = fk.keyword_id
                WHERE fk.file_id = ? ORDER BY k.name
                """, arguments: [fileId])
        }
    }

    /// Replace a file's keyword set.
    func setKeywords(fileId: String, keywordIds: [String]) throws {
        try dbPool.write { db in
            try db.execute(sql: "DELETE FROM file_keywords WHERE file_id = ?", arguments: [fileId])
            for kid in keywordIds {
                try db.execute(sql: "INSERT OR IGNORE INTO file_keywords (file_id, keyword_id) VALUES (?, ?)",
                               arguments: [fileId, kid])
            }
        }
    }

    // MARK: - File ⇄ Album junction

    func albums(forFile fileId: String) throws -> [String] {
        try dbPool.read { db in
            try String.fetchAll(db, sql: "SELECT album_name FROM file_albums WHERE file_id = ? ORDER BY album_name",
                                arguments: [fileId])
        }
    }

    /// Replace a file's album set.
    func setAlbums(fileId: String, albumNames: [String]) throws {
        try dbPool.write { db in
            try db.execute(sql: "DELETE FROM file_albums WHERE file_id = ?", arguments: [fileId])
            for name in albumNames {
                try db.execute(sql: "INSERT OR IGNORE INTO file_albums (file_id, album_name) VALUES (?, ?)",
                               arguments: [fileId, name])
            }
        }
    }

    /// All distinct album names used across PurplePeek (for the album picker's quick-add list).
    func distinctAlbumNames() throws -> [String] {
        try dbPool.read { db in
            try String.fetchAll(db, sql: "SELECT DISTINCT album_name FROM file_albums ORDER BY album_name")
        }
    }

    /// Upsert a batch of discovered files. On a `file_path` conflict (a re-scan), only the
    /// file's on-disk metadata is refreshed — `scan_root`, `keep`, `is_favorite`, `title`,
    /// `caption`, import/delete state, and `id` are all preserved. This is what lets a user
    /// revisit a folder without losing decisions, and honors the nested-root rule (a file
    /// keeps the root it was first discovered under).
    func upsertScannedFiles(_ files: [ScannedFile], scanRoot: String, now: String) throws {
        try dbPool.write { db in
            // Prepare the statement once and reuse it for every row — re-parsing the SQL per
            // row was a real cost on large (tens of thousands of files) scans.
            let stmt = try db.makeStatement(sql: """
                INSERT INTO media_files
                    (id, scan_root, file_path, file_name, file_type, file_size,
                     file_modified_at, is_favorite, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?)
                ON CONFLICT(file_path) DO UPDATE SET
                    file_name = excluded.file_name,
                    file_type = excluded.file_type,
                    file_size = excluded.file_size,
                    file_modified_at = excluded.file_modified_at,
                    updated_at = excluded.updated_at,
                    missing_at = NULL
                """)
            for f in files {
                stmt.arguments = [
                    UUID().uuidString, scanRoot, f.path, f.name, f.type.rawValue,
                    f.size, f.modifiedAt, now, now
                ]
                try stmt.execute()
            }
        }
    }

    /// Reconcile on-disk deletions after a re-scan: flag every non-deleted, not-already-missing
    /// row under `scanRoot` whose `updated_at` is older than this scan's timestamp as missing.
    ///
    /// `upsertScannedFiles` stamps every file *found this scan* with `updated_at = now` (and
    /// clears its `missing_at`), so any surviving row with `updated_at < now` is precisely the
    /// set that wasn't found — i.e. removed or moved out from under the root. This watermark
    /// approach scales to tens of thousands of files without materializing a path set. Pass the
    /// **same `now`** used for the upsert batches. Returns the number of rows newly marked.
    @discardableResult
    func markMissingFiles(scanRoot: String, now: String) throws -> Int {
        try dbPool.write { db in
            try db.execute(sql: """
                UPDATE media_files SET missing_at = ?, updated_at = ?
                WHERE scan_root = ?
                  AND deleted_at IS NULL
                  AND missing_at IS NULL
                  AND updated_at < ?
                """, arguments: [now, now, scanRoot, now])
            return db.changesCount
        }
    }
}

import CryptoKit
import Foundation
import GRDB

/// Sole owner of the GRDB `DatabasePool` for `diary.sqlite`. Runs the
/// append-only migrator at init and exposes thin per-record CRUD wrappers.
/// Migration logic lives in `static applyMigrations(to:)` so the test suite
/// applies the *real* migrator instead of a duplicated fixture — drift between
/// production schema and tests would defeat the migration tests.
///
/// **Migrations are immutable** (per CLAUDE.md): never edit a shipped
/// migration. Add a new `registerMigration` block instead.
///
/// **At-rest encryption**: the vendored SQLCipher amalgamation (see
/// `Vendor/SQLCipher/`) shadows the system `libsqlite3.dylib` at link time, so
/// GRDB's `sqlite3_*` calls land in SQLCipher. When `keyResolver` returns a DEK,
/// every `DatabasePool` connection runs `PRAGMA key` at open via
/// `Configuration.prepareDatabase`, making the whole `diary.sqlite` file opaque
/// ciphertext on disk. On first launch after this ships, an existing plaintext
/// `diary.sqlite` is detected (SQLite-3 magic-header probe) and copied into a
/// SQLCipher-keyed sibling via `sqlcipher_export()`, then atomically renamed.
/// One-shot per install; idempotent because the probe skips already-encrypted
/// files. With `keyResolver == nil`, SQLCipher behaves exactly like plain
/// SQLite — that's the path the test suite exercises.
@MainActor
final class DatabaseService {
    static let shared = DatabaseService()

    private(set) var dbPool: DatabasePool

    /// Resolver wired by `AppState` so the singleton can fetch the DEK without
    /// taking a `KeyStore` dependency at the call site. nil → no encryption
    /// (plaintext fallback). `nonisolated(unsafe)` because it's read from GRDB's
    /// background queues inside `prepareDatabase`.
    nonisolated(unsafe) static var keyResolver: (() -> SymmetricKey?)?

    private static var currentKey: SymmetricKey? { keyResolver?() }

    /// First 16 bytes of an unencrypted SQLite 3 file. SQLCipher encrypts these
    /// bytes too, so a magic-header match reliably means "plaintext SQLite that
    /// needs migration".
    nonisolated private static let plainSQLiteMagic: [UInt8] = Array("SQLite format 3\0".utf8)

    /// True when `dbPool` points at a temp placeholder instead of the real
    /// on-disk DB — init couldn't open the file (encrypted + no key in scope
    /// yet, the normal property-init ordering) or `reopenDatabase()` threw.
    /// `AppState` reads this after wiring the resolver: if still true after
    /// `reopenDatabase`, the on-disk file is encrypted with a key we don't have
    /// and the app surfaces the recovery UX.
    private(set) var isUsingPlaceholderPool: Bool = false

    static var supportDirectory: URL { AppSettings.supportDirectory }

    var databaseURL: URL {
        Self.supportDirectory.appendingPathComponent("diary.sqlite")
    }

    private init() {
        let dir = Self.supportDirectory
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbURL = dir.appendingPathComponent("diary.sqlite")

        // If a DEK is already in scope and the on-disk file is still plaintext,
        // migrate it to SQLCipher before any pool opens against it.
        if let key = Self.currentKey, Self.isPlaintextSQLite(at: dbURL) {
            do {
                try Self.migratePlaintextToSQLCipher(at: dbURL, key: key)
                NSLog("PurpleDiary: migrated plaintext diary.sqlite to SQLCipher")
            } catch {
                NSLog("PurpleDiary: SQLCipher migration failed — \(error.localizedDescription); continuing")
            }
        }

        // At property-init time `keyResolver` is almost always nil — this
        // singleton is built when AppState reads `DatabaseService.shared` during
        // its OWN property init, before AppState wires the resolver. So
        // `makeConfiguration()` returns a bare config (no PRAGMA key). Opening
        // an already-encrypted file with that config fails immediately. Crashing
        // with `try!` would brick every launch after the first migration;
        // instead substitute a temp placeholder pool so the property stays
        // non-nil, and let `AppState.init` call `reopenDatabase()` (after wiring
        // the resolver) to swap in the real keyed pool.
        do {
            dbPool = try DatabasePool(path: dbURL.path, configuration: Self.makeConfiguration())
            try migrate()
        } catch {
            NSLog("PurpleDiary: DB open deferred to keyed reopen — \(error.localizedDescription)")
            let placeholderPath = NSTemporaryDirectory() + "purplediary-throwaway-\(UUID().uuidString).sqlite"
            dbPool = try! DatabasePool(path: placeholderPath)
            isUsingPlaceholderPool = true
        }
    }

    /// Re-open the underlying GRDB pool against the on-disk database with the
    /// current key. Used after wiring the key resolver at launch and after a
    /// backup-restore so the running process picks up the swapped file.
    func reopenDatabase() throws {
        // If the file is plaintext + we have a key, migrate before opening.
        // Drop the existing pool first (onto a throwaway temp file) so the old
        // pool's file handles release, then checkpoint + prune leftover journal
        // files, THEN migrate with no other handles open to the source.
        if let key = Self.currentKey, Self.isPlaintextSQLite(at: databaseURL) {
            let throwawayPath = NSTemporaryDirectory() + "purplediary-throwaway-\(UUID().uuidString).sqlite"
            dbPool = try DatabasePool(path: throwawayPath)
            Self.checkpointAndPruneJournalFiles(at: databaseURL)
            try Self.migratePlaintextToSQLCipher(at: databaseURL, key: key)
        }
        dbPool = try DatabasePool(path: databaseURL.path, configuration: Self.makeConfiguration())
        try migrate()
        isUsingPlaceholderPool = false
        Self.purgeMigrationThrowaways()
    }

    /// Move the unreadable on-disk DB (+ WAL/shm) into a timestamped
    /// `.unrecoverable-<stamp>/` sibling and drop the live pool onto a throwaway
    /// so the files aren't held open. The caller then mints a new key and calls
    /// `reopenDatabase()` to create a fresh encrypted DB at the original path.
    /// The quarantine is never deleted — a later Keychain/recovery-key restore
    /// could still salvage it.
    func quarantineDatabaseFiles() throws {
        let fm = FileManager.default
        let support = Self.supportDirectory
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let quarantine = support.appendingPathComponent(".unrecoverable-\(stamp)", isDirectory: true)
        try fm.createDirectory(at: quarantine, withIntermediateDirectories: true)
        // Release the source file handles by reassigning the pool to a throwaway.
        let throwaway = NSTemporaryDirectory() + "purplediary-throwaway-\(UUID().uuidString).sqlite"
        dbPool = try DatabasePool(path: throwaway)
        isUsingPlaceholderPool = true
        for name in ["diary.sqlite", "diary.sqlite-wal", "diary.sqlite-shm"] {
            let src = support.appendingPathComponent(name)
            if fm.fileExists(atPath: src.path) {
                try? fm.moveItem(at: src, to: quarantine.appendingPathComponent(name))
            }
        }
    }

    // MARK: - SQLCipher configuration & migration

    /// Build a GRDB `Configuration` that sets `PRAGMA key` on every new
    /// connection. With no key (tests, edge cases) it's a bare default —
    /// SQLCipher without a key behaves like plain SQLite, so plaintext files
    /// keep working.
    nonisolated static func makeConfiguration() -> Configuration {
        var config = Configuration()
        guard let key = keyResolver?() else { return config }
        let hexKey = hexEncoded(key.rawData)
        config.prepareDatabase { db in
            // SQLCipher's raw-key form is the SQL string `x'HEX'` (recognised as
            // a raw blob, no KDF over it). Built with single-quoted SQL, the
            // inner `'` doubled. DO NOT switch to double quotes — SQLCipher is
            // built with SQLITE_DQS=0, so `"x'HEX'"` parses as an identifier and
            // silently produces a mismatched key.
            try db.execute(sql: "PRAGMA key = 'x''\(hexKey)'''")
            // Zetetic's documented best-practice defaults — set explicitly to
            // future-proof against SQLCipher changing internal defaults.
            try db.execute(sql: "PRAGMA cipher_page_size = 4096")
            try db.execute(sql: "PRAGMA kdf_iter = 256000")
            try db.execute(sql: "PRAGMA cipher_hmac_algorithm = HMAC_SHA512")
            try db.execute(sql: "PRAGMA cipher_kdf_algorithm = PBKDF2_HMAC_SHA512")
        }
        return config
    }

    nonisolated private static func hexEncoded(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    /// Does the on-disk DB look like it holds SQLCipher-encrypted data we'd lose
    /// if we minted a fresh DEK? "Looks encrypted" = exists, non-trivial size,
    /// and NOT plaintext-SQLite. Used by AppState's bootstrap guard. `static` so
    /// the guard can probe without forcing the `shared` singleton to build (and
    /// thus migrate) before the launch backup has run.
    static func databaseFileLooksEncrypted() -> Bool {
        let url = supportDirectory.appendingPathComponent("diary.sqlite")
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path),
              let attrs = try? fm.attributesOfItem(atPath: url.path),
              let size = (attrs[.size] as? NSNumber)?.intValue,
              size > 4096
        else { return false }
        return !isPlaintextSQLite(at: url)
    }

    /// True when `url` points at an existing file whose first 16 bytes are the
    /// SQLite 3 magic header (i.e. plaintext, needs the SQLCipher migration).
    nonisolated static func isPlaintextSQLite(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: plainSQLiteMagic.count),
              head.count == plainSQLiteMagic.count else { return false }
        return Array(head) == plainSQLiteMagic
    }

    /// One-shot: copy a plaintext SQLite DB into a freshly-keyed SQLCipher
    /// sibling via `sqlcipher_export()`, then atomically rename the encrypted
    /// file over the plaintext one.
    nonisolated static func migratePlaintextToSQLCipher(at url: URL, key: SymmetricKey) throws {
        let fm = FileManager.default
        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).sqlcipher.tmp")
        try? fm.removeItem(at: tempURL)

        let hexKey = hexEncoded(key.rawData)
        // Open plaintext DB with no key. `writeWithoutTransaction` runs the
        // ATTACH + sqlcipher_export + DETACH outside a transaction — DETACH
        // fails with "database is locked" inside one.
        let plainQueue = try DatabaseQueue(path: url.path)
        try plainQueue.writeWithoutTransaction { db in
            try db.execute(sql: "ATTACH DATABASE ? AS encrypted KEY 'x''\(hexKey)'''",
                           arguments: [tempURL.path])
            try db.execute(sql: "SELECT sqlcipher_export('encrypted')")
            try db.execute(sql: "DETACH DATABASE encrypted")
        }
        _ = plainQueue  // keep alive until here, then release so the rename can replace the file

        try fm.removeItem(at: url)
        try fm.moveItem(at: tempURL, to: url)
    }

    /// Force the plaintext source DB to checkpoint its WAL into the main file,
    /// switch out of WAL mode, then remove leftover `-wal`/`-shm`/`-journal`
    /// files so the migration runs against a clean single-file state.
    nonisolated private static func checkpointAndPruneJournalFiles(at url: URL) {
        do {
            let queue = try DatabaseQueue(path: url.path)
            try queue.writeWithoutTransaction { db in
                try db.execute(sql: "PRAGMA journal_mode = DELETE")
            }
            _ = queue
        } catch {
            NSLog("PurpleDiary: pre-migration WAL checkpoint failed — \(error.localizedDescription)")
        }
        let fm = FileManager.default
        for suffix in ["-wal", "-shm", "-journal"] {
            try? fm.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    /// Sweep `NSTemporaryDirectory()` for the throwaway SQLite files
    /// `reopenDatabase` creates to release the old pool's handles before the
    /// SQLCipher migration. Idempotent.
    nonisolated private static func purgeMigrationThrowaways() {
        let fm = FileManager.default
        let dir = NSTemporaryDirectory()
        guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { return }
        for name in entries where name.hasPrefix("purplediary-throwaway-") {
            try? fm.removeItem(atPath: dir + name)
        }
    }

    // MARK: - Migrations

    private func migrate() throws {
        try Self.applyMigrations(to: dbPool)
    }

    /// Public entry point so tests can apply the real schema to an in-memory
    /// `DatabaseQueue` instead of duplicating the migration body and drifting
    /// over time. Add new versions inside this function — never inside
    /// `init()` — to keep test coverage automatic.
    static func applyMigrations(to writer: DatabaseWriter) throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial") { db in
            try db.create(table: "entries") { t in
                t.column("id", .text).primaryKey()
                t.column("date", .text).notNull()
                t.column("title", .text).notNull().defaults(to: "")
                t.column("body_markdown", .text).notNull().defaults(to: "")
                t.column("mood_rating", .integer).notNull().defaults(to: 0)
                t.column("word_count", .integer).notNull().defaults(to: 0)
                // Phase-2 auto-context columns — nullable, created now so the
                // import services don't need a follow-up migration.
                t.column("latitude", .double)
                t.column("longitude", .double)
                t.column("place_name", .text)
                t.column("weather_summary", .text)
                t.column("temperature_c", .double)
                t.column("created_at", .text).notNull()
                t.column("updated_at", .text).notNull()
            }
            try db.create(index: "idx_entries_date", on: "entries", columns: ["date"])
            try db.create(index: "idx_entries_mood", on: "entries", columns: ["mood_rating"])

            try db.create(table: "tags") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().collate(.nocase)
                t.column("color_hex", .text).notNull().defaults(to: "#888888")
                t.uniqueKey(["name"])
            }

            try db.create(table: "entry_tags") { t in
                t.column("entry_id", .text).notNull()
                    .references("entries", column: "id", onDelete: .cascade)
                t.column("tag_id", .integer).notNull()
                    .references("tags", column: "id", onDelete: .cascade)
                t.primaryKey(["entry_id", "tag_id"])
            }

            try db.create(table: "people") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull().defaults(to: "")
                t.column("notes", .text).notNull().defaults(to: "")
            }

            try db.create(table: "entry_people") { t in
                t.column("entry_id", .text).notNull()
                    .references("entries", column: "id", onDelete: .cascade)
                t.column("person_id", .text).notNull()
                    .references("people", column: "id", onDelete: .cascade)
                t.primaryKey(["entry_id", "person_id"])
            }
        }

        // Phase-2 tracker tags + per-entry values. Append-only: v1_initial is
        // shipped and immutable (editing it would change the GRDB hash and
        // brick every encrypted install). See CLAUDE.md → "SQL migrations are
        // immutable" and the SecurityMiscTests frozen-migration guard.
        migrator.registerMigration("v2_trackers") { db in
            try db.create(table: "tracker_tags") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().collate(.nocase)
                t.column("unit", .text).notNull().defaults(to: "")
                t.column("kind", .text).notNull().defaults(to: "number")
                t.column("color_hex", .text).notNull().defaults(to: "#7C5CFF")
                t.uniqueKey(["name"])
            }
            try db.create(table: "tracker_values") { t in
                t.column("entry_id", .text).notNull()
                    .references("entries", column: "id", onDelete: .cascade)
                t.column("tracker_tag_id", .integer).notNull()
                    .references("tracker_tags", column: "id", onDelete: .cascade)
                t.column("value", .double).notNull().defaults(to: 0)
                t.primaryKey(["entry_id", "tracker_tag_id"])
            }
            try db.create(index: "idx_tracker_values_tag", on: "tracker_values", columns: ["tracker_tag_id"])
        }

        // Phase-2 photo attachments. Append-only (v1_initial + v2_trackers stay
        // frozen). Bytes are stored in the `data` BLOB so they're encrypted at
        // rest by SQLCipher and captured by the backup zip — no separate
        // plaintext attachment files. See SecurityMiscTests' frozen-migration
        // guard and Docs/SECURITY.md §3.
        migrator.registerMigration("v3_attachments") { db in
            try db.create(table: "attachments") { t in
                t.column("id", .text).primaryKey()
                t.column("entry_id", .text).notNull()
                    .references("entries", column: "id", onDelete: .cascade)
                t.column("kind", .text).notNull().defaults(to: "photo")
                t.column("filename", .text).notNull().defaults(to: "")
                t.column("mime_type", .text).notNull().defaults(to: "image/jpeg")
                t.column("size_bytes", .integer).notNull().defaults(to: 0)
                t.column("width", .integer).notNull().defaults(to: 0)
                t.column("height", .integer).notNull().defaults(to: 0)
                t.column("data", .blob).notNull()
                t.column("thumbnail_data", .blob)
                t.column("source_asset_id", .text)
                t.column("created_at", .text).notNull()
            }
            try db.create(index: "idx_attachments_entry", on: "attachments", columns: ["entry_id"])
        }

        // Phase-3 journals. Append-only (v1…v3 stay frozen). Creates the
        // `journals` table, seeds the always-present default journal, adds a
        // NOT NULL `journal_id` to `entries` (existing rows back-fill to the
        // default via the column DEFAULT), and indexes it. Hidden journals are
        // an app-level visibility gate at this phase — bytes remain under the
        // single DB DEK. See SecurityMiscTests' frozen-migration guard.
        migrator.registerMigration("v4_journals") { db in
            try db.create(table: "journals") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull().defaults(to: "Journal")
                t.column("color_hex", .text).notNull().defaults(to: "#7C5CFF")
                t.column("symbol", .text).notNull().defaults(to: "book.closed")
                t.column("is_hidden", .integer).notNull().defaults(to: 0)
                t.column("sort_order", .integer).notNull().defaults(to: 0)
                t.column("created_at", .text).notNull().defaults(to: "")
            }
            try db.execute(sql: """
                INSERT INTO journals (id, name, color_hex, symbol, is_hidden, sort_order, created_at)
                VALUES (?, 'Journal', '#7C5CFF', 'book.closed', 0, 0, ?)
                """, arguments: [Journal.defaultId, Self.isoNow()])
            // Existing entries back-fill to the default journal via the DEFAULT.
            try db.alter(table: "entries") { t in
                t.add(column: "journal_id", .text).notNull().defaults(to: Journal.defaultId)
            }
            try db.create(index: "idx_entries_journal", on: "entries", columns: ["journal_id"])
        }

        // Phase-5 entry templates. Append-only (v1…v4 stay frozen).
        migrator.registerMigration("v5_templates") { db in
            try db.create(table: "templates") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull().defaults(to: "Template")
                t.column("body", .text).notNull().defaults(to: "")
                t.column("sort_order", .integer).notNull().defaults(to: 0)
                t.column("created_at", .text).notNull().defaults(to: "")
            }
        }

        try migrator.migrate(writer)
    }

    func seedDefaultTagsIfEmpty() throws {
        try dbPool.write { db in
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tags") ?? 0
            guard count == 0 else { return }
            let defaults: [(String, String)] = [
                ("personal", "#7C5CFF"),
                ("work",     "#3FA9F5"),
                ("travel",   "#3FB950"),
                ("health",   "#E8A93B"),
                ("ideas",    "#F08C2E"),
                ("gratitude","#D14B5C"),
            ]
            for (name, hex) in defaults {
                var tag = Tag(rowId: nil, name: name, colorHex: hex)
                try tag.insert(db)
            }
        }
    }

    // MARK: - Entries

    func fetchAllEntries() throws -> [Entry] {
        try dbPool.read { db in
            try Entry.order(Column("date").desc).fetchAll(db)
        }
    }

    func fetchEntry(id: String) throws -> Entry? {
        try dbPool.read { db in
            try Entry.fetchOne(db, key: id)
        }
    }

    func insertEntry(_ entry: Entry) throws {
        try dbPool.write { db in
            var mutable = entry
            mutable.refreshWordCount()
            try mutable.insert(db)
        }
    }

    /// Insert many entries in a single transaction. The bulk path for the
    /// sample-data facility — one write instead of N (far cheaper for 100 rows)
    /// and atomic rollback if any row fails. Word counts are refreshed per row.
    func bulkInsertEntries(_ entries: [Entry]) throws {
        guard !entries.isEmpty else { return }
        try dbPool.write { db in
            for entry in entries {
                var mutable = entry
                mutable.refreshWordCount()
                try mutable.insert(db)
            }
        }
    }

    func updateEntry(_ entry: Entry) throws {
        var stamped = entry
        stamped.updatedAt = Self.isoNow()
        stamped.refreshWordCount()
        try dbPool.write { db in
            try stamped.update(db)
        }
    }

    func deleteEntry(id: String) throws {
        try dbPool.write { db in
            _ = try Entry.deleteOne(db, key: id)
        }
    }

    /// Delete many entries by id in one transaction; returns the number of rows
    /// that actually existed and were deleted (ids not present are ignored).
    @discardableResult
    func deleteEntries(ids: [String]) throws -> Int {
        guard !ids.isEmpty else { return 0 }
        return try dbPool.write { db in
            try Entry.deleteAll(db, keys: ids)
        }
    }

    // MARK: - Journals

    /// All journals, default first, then by sort order and name.
    func fetchAllJournals() throws -> [Journal] {
        try dbPool.read { db in
            try Journal
                .order(Column("sort_order").asc, Column("name").asc)
                .fetchAll(db)
                .sorted { a, b in
                    if a.isDefault != b.isDefault { return a.isDefault }   // default pinned first
                    if a.sortOrder != b.sortOrder { return a.sortOrder < b.sortOrder }
                    return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                }
        }
    }

    func insertJournal(_ journal: Journal) throws {
        try dbPool.write { db in
            var mutable = journal
            try mutable.insert(db)
        }
    }

    func updateJournal(_ journal: Journal) throws {
        try dbPool.write { db in try journal.update(db) }
    }

    /// Delete a journal, first reassigning its entries to the default journal so
    /// nothing is lost. The default journal itself cannot be deleted.
    func deleteJournal(id: String) throws {
        guard id != Journal.defaultId else { return }
        try dbPool.write { db in
            try db.execute(sql: "UPDATE entries SET journal_id = ? WHERE journal_id = ?",
                           arguments: [Journal.defaultId, id])
            _ = try Journal.deleteOne(db, key: id)
        }
    }

    /// Move a single entry into a journal.
    func setJournal(_ journalId: String, forEntry entryId: String) throws {
        try dbPool.write { db in
            try db.execute(sql: "UPDATE entries SET journal_id = ?, updated_at = ? WHERE id = ?",
                           arguments: [journalId, Self.isoNow(), entryId])
        }
    }

    /// entry counts per journal id — feeds the sidebar badges.
    func entryCountByJournal() throws -> [String: Int] {
        try dbPool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT journal_id, COUNT(*) AS n FROM entries GROUP BY journal_id
                """)
            var out: [String: Int] = [:]
            for row in rows { out[row["journal_id"]] = row["n"] }
            return out
        }
    }

    // MARK: - Templates

    func fetchAllTemplates() throws -> [Template] {
        try dbPool.read { db in
            try Template.order(Column("sort_order").asc, Column("name").asc).fetchAll(db)
        }
    }

    func insertTemplate(_ template: Template) throws {
        try dbPool.write { db in var m = template; try m.insert(db) }
    }

    func updateTemplate(_ template: Template) throws {
        try dbPool.write { db in try template.update(db) }
    }

    func deleteTemplate(id: String) throws {
        try dbPool.write { db in _ = try Template.deleteOne(db, key: id) }
    }

    /// Seed a couple of starter templates the first time (table empty), so the
    /// feature is discoverable. Mirrors `seedDefaultTagsIfEmpty`.
    func seedDefaultTemplatesIfEmpty() throws {
        try dbPool.write { db in
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM templates") ?? 0
            guard count == 0 else { return }
            let defaults: [(String, String)] = [
                ("Daily check-in",
                 "## {{weekday}}, {{date}}\n\n**Today I…**\n- \n\n**One good thing:** \n\n**On my mind:** "),
                ("Gratitude",
                 "## Grateful — {{date}}\n\n1. \n2. \n3. "),
            ]
            for (i, (name, body)) in defaults.enumerated() {
                var t = Template.newDraft(name: name, body: body, sortOrder: i)
                try t.insert(db)
            }
        }
    }

    // MARK: - Tags

    func fetchAllTags() throws -> [Tag] {
        try dbPool.read { db in
            try Tag.order(Column("name").asc).fetchAll(db)
        }
    }

    func saveTag(_ tag: inout Tag) throws {
        try dbPool.write { db in
            try tag.save(db)
        }
    }

    func deleteTag(id: Int64) throws {
        try dbPool.write { db in
            _ = try Tag.deleteOne(db, key: id)
        }
    }

    func tagIDs(forEntry entryId: String) throws -> [Int64] {
        try dbPool.read { db in
            try Int64.fetchAll(
                db,
                sql: "SELECT tag_id FROM entry_tags WHERE entry_id = ?",
                arguments: [entryId]
            )
        }
    }

    func setTags(_ tagIds: [Int64], forEntry entryId: String) throws {
        try dbPool.write { db in
            try EntryTag.filter(Column("entry_id") == entryId).deleteAll(db)
            for tid in Set(tagIds) {
                let row = EntryTag(entryId: entryId, tagId: tid)
                try row.insert(db)
            }
        }
    }

    /// entry.id → [Tag], built from a single join query for the whole journal.
    func tagsByEntry() throws -> [String: [Tag]] {
        try dbPool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT et.entry_id AS entry_id, t.id AS id, t.name AS name, t.color_hex AS color_hex
                FROM entry_tags et
                JOIN tags t ON t.id = et.tag_id
                """)
            var out: [String: [Tag]] = [:]
            for row in rows {
                let eid: String = row["entry_id"]
                let tag = Tag(rowId: row["id"], name: row["name"], colorHex: row["color_hex"])
                out[eid, default: []].append(tag)
            }
            return out
        }
    }

    // MARK: - People

    func fetchAllPeople() throws -> [Person] {
        try dbPool.read { db in
            try Person.order(Column("name").asc).fetchAll(db)
        }
    }

    func savePerson(_ p: Person) throws {
        try dbPool.write { db in
            var mutable = p
            try mutable.save(db)
        }
    }

    func deletePerson(id: String) throws {
        try dbPool.write { db in
            _ = try Person.deleteOne(db, key: id)
        }
    }

    func personIDs(forEntry entryId: String) throws -> [String] {
        try dbPool.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT person_id FROM entry_people WHERE entry_id = ?",
                arguments: [entryId]
            )
        }
    }

    func setPeople(_ personIds: [String], forEntry entryId: String) throws {
        try dbPool.write { db in
            try EntryPerson.filter(Column("entry_id") == entryId).deleteAll(db)
            for pid in Set(personIds) {
                let row = EntryPerson(entryId: entryId, personId: pid)
                try row.insert(db)
            }
        }
    }

    func peopleByEntry() throws -> [String: [Person]] {
        try dbPool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT ep.entry_id AS entry_id, p.id AS id, p.name AS name, p.notes AS notes
                FROM entry_people ep
                JOIN people p ON p.id = ep.person_id
                """)
            var out: [String: [Person]] = [:]
            for row in rows {
                let eid: String = row["entry_id"]
                let person = Person(id: row["id"], name: row["name"], notes: row["notes"])
                out[eid, default: []].append(person)
            }
            return out
        }
    }

    // MARK: - Trackers

    func fetchAllTrackerTags() throws -> [TrackerTag] {
        try dbPool.read { db in
            try TrackerTag.order(Column("name").asc).fetchAll(db)
        }
    }

    func saveTrackerTag(_ tracker: inout TrackerTag) throws {
        try dbPool.write { db in
            try tracker.save(db)
        }
    }

    func deleteTrackerTag(id: Int64) throws {
        try dbPool.write { db in
            _ = try TrackerTag.deleteOne(db, key: id)
        }
    }

    /// Set (or clear) a tracker's value on one entry. A nil `value` removes the
    /// row — the editor uses this to "unlog" a tracker for an entry.
    func setTrackerValue(_ value: Double?, trackerTagId: Int64, forEntry entryId: String) throws {
        try dbPool.write { db in
            if let value {
                try TrackerValue(entryId: entryId, trackerTagId: trackerTagId, value: value)
                    .upsert(db)
            } else {
                try TrackerValue
                    .filter(Column("entry_id") == entryId && Column("tracker_tag_id") == trackerTagId)
                    .deleteAll(db)
            }
        }
    }

    /// trackerTagId → value for one entry.
    func trackerValues(forEntry entryId: String) throws -> [Int64: Double] {
        try dbPool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT tracker_tag_id, value FROM tracker_values WHERE entry_id = ?",
                arguments: [entryId]
            )
            var out: [Int64: Double] = [:]
            for row in rows { out[row["tracker_tag_id"]] = row["value"] }
            return out
        }
    }

    /// entry.id → (trackerTagId → value), one query for the whole journal —
    /// feeds the Insights tracker graphs.
    func trackerValuesByEntry() throws -> [String: [Int64: Double]] {
        try dbPool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT entry_id, tracker_tag_id, value FROM tracker_values
                """)
            var out: [String: [Int64: Double]] = [:]
            for row in rows {
                let eid: String = row["entry_id"]
                out[eid, default: [:]][row["tracker_tag_id"]] = row["value"]
            }
            return out
        }
    }

    // MARK: - Attachments

    /// Full attachment rows (including the `data` BLOB) for one entry, oldest
    /// first. Used by export and by the full-image viewer.
    func attachments(forEntry entryId: String) throws -> [Attachment] {
        try dbPool.read { db in
            try Attachment
                .filter(Column("entry_id") == entryId)
                .order(Column("created_at").asc)
                .fetchAll(db)
        }
    }

    /// One full attachment row (including the `data` BLOB) by id — backs the
    /// full-size viewer / video player.
    func attachment(id: String) throws -> Attachment? {
        try dbPool.read { db in try Attachment.fetchOne(db, key: id) }
    }

    /// Lightweight thumbnails (no full `data` BLOB) for one entry — drives the
    /// editor's photo strip.
    func attachmentThumbs(forEntry entryId: String) throws -> [AttachmentThumb] {
        try dbPool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT id, entry_id, kind, mime_type, filename, thumbnail_data, width, height
                FROM attachments WHERE entry_id = ? ORDER BY created_at ASC
                """, arguments: [entryId])
            return rows.map { AttachmentThumb(row: $0) }
        }
    }

    func insertAttachment(_ attachment: Attachment) throws {
        try dbPool.write { db in
            var mutable = attachment
            try mutable.insert(db)
        }
    }

    func deleteAttachment(id: String) throws {
        try dbPool.write { db in
            _ = try Attachment.deleteOne(db, key: id)
        }
    }

    /// True if a photo with this `PHAsset.localIdentifier` is already attached to
    /// the entry — lets the import path skip duplicates.
    func attachmentExists(entryId: String, sourceAssetId: String) throws -> Bool {
        try dbPool.read { db in
            try Attachment
                .filter(Column("entry_id") == entryId && Column("source_asset_id") == sourceAssetId)
                .fetchCount(db) > 0
        }
    }

    /// entry.id → attachment count, one query for the whole journal. Feeds the
    /// export note and any timeline badges.
    func attachmentCountByEntry() throws -> [String: Int] {
        try dbPool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT entry_id, COUNT(*) AS n FROM attachments GROUP BY entry_id
                """)
            var out: [String: Int] = [:]
            for row in rows { out[row["entry_id"]] = row["n"] }
            return out
        }
    }

    // MARK: - Helpers

    static func isoNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    static func isoDate(_ d: Date) -> String {
        ISO8601DateFormatter().string(from: d)
    }
}

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

        // Phase-9 vault: a journal can be sealed under its own per-journal content
        // key (CK). `is_vault` flags it; `vault_envelopes` stores CK wrapped under
        // both a passphrase-derived KEK and the 24-word recovery key, so the
        // journal's text is opaque even with the DB open, yet recoverable. Append-
        // only. See Docs/SECURITY.md / SCOPING.md Phase 9.
        migrator.registerMigration("v6_vault") { db in
            try db.alter(table: "journals") { t in
                t.add(column: "is_vault", .integer).notNull().defaults(to: 0)
            }
            try db.create(table: "vault_envelopes") { t in
                t.column("journal_id", .text).primaryKey()
                    .references("journals", column: "id", onDelete: .cascade)
                t.column("pass_salt", .blob).notNull()
                t.column("pass_iters", .integer).notNull()
                t.column("pass_wrap", .blob).notNull()
                t.column("recovery_salt", .blob).notNull()
                t.column("recovery_iters", .integer).notNull()
                t.column("recovery_wrap", .blob).notNull()
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
        let vaultIds = try vaultJournalIds()
        let raw = try dbPool.read { db in
            try Entry.order(Column("date").desc).fetchAll(db)
        }
        return raw.map { unsealForRead($0, vaultIds: vaultIds) }
    }

    func fetchEntry(id: String) throws -> Entry? {
        let vaultIds = try vaultJournalIds()
        guard let raw = try dbPool.read({ db in try Entry.fetchOne(db, key: id) }) else { return nil }
        return unsealForRead(raw, vaultIds: vaultIds)
    }

    func insertEntry(_ entry: Entry) throws {
        let vaultIds = try vaultJournalIds()
        var prepared = entry
        prepared.refreshWordCount()
        prepared = try sealForWrite(prepared, vaultIds: vaultIds)
        try dbPool.write { db in
            var mutable = prepared
            try mutable.insert(db)
        }
    }

    /// Insert many entries in a single transaction. The bulk path for the
    /// sample-data facility — one write instead of N (far cheaper for 100 rows)
    /// and atomic rollback if any row fails. Word counts are refreshed per row.
    func bulkInsertEntries(_ entries: [Entry]) throws {
        guard !entries.isEmpty else { return }
        let vaultIds = try vaultJournalIds()
        let prepared: [Entry] = try entries.map { entry in
            var mutable = entry
            mutable.refreshWordCount()
            return try sealForWrite(mutable, vaultIds: vaultIds)
        }
        try dbPool.write { db in
            for entry in prepared {
                var mutable = entry
                try mutable.insert(db)
            }
        }
    }

    func updateEntry(_ entry: Entry) throws {
        let vaultIds = try vaultJournalIds()
        var stamped = entry
        stamped.updatedAt = Self.isoNow()
        stamped.refreshWordCount()
        stamped = try sealForWrite(stamped, vaultIds: vaultIds)
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

    /// Delete a journal. When `deleteEntries` is false (default) its entries are
    /// first reassigned to the default journal so nothing is lost; when true, the
    /// entries (and their cascaded tags/trackers/attachments) are deleted along
    /// with the journal — used to clean up a throwaway import. The default
    /// journal itself cannot be deleted.
    func deleteJournal(id: String, deleteEntries: Bool = false) throws {
        guard id != Journal.defaultId else { return }
        try dbPool.write { db in
            if deleteEntries {
                // FK cascades from entries → entry_tags / tracker_values / attachments.
                try db.execute(sql: "DELETE FROM entries WHERE journal_id = ?", arguments: [id])
            } else {
                try db.execute(sql: "UPDATE entries SET journal_id = ? WHERE journal_id = ?",
                               arguments: [Journal.defaultId, id])
            }
            _ = try Journal.deleteOne(db, key: id)
        }
    }

    /// Move a single entry into a journal, re-keying its text across the vault
    /// boundary: unseal with the source vault's key (if any) and re-seal under
    /// the destination vault's key (if any). Moving in or out of a *locked*
    /// vault throws `VaultWriteError.lockedVault` — we can neither read the
    /// source plaintext nor seal for the destination without the session key.
    func setJournal(_ journalId: String, forEntry entryId: String) throws {
        let vaultIds = try vaultJournalIds()
        guard let raw = try dbPool.read({ db in try Entry.fetchOne(db, key: entryId) }) else { return }
        let srcVault = vaultIds.contains(raw.journalId)
        let dstVault = vaultIds.contains(journalId)

        // Fast path: neither side is a vault — a plain journal_id update.
        if !srcVault && !dstVault {
            try dbPool.write { db in
                try db.execute(sql: "UPDATE entries SET journal_id = ?, updated_at = ? WHERE id = ?",
                               arguments: [journalId, Self.isoNow(), entryId])
            }
            return
        }

        var srcKey: SymmetricKey?
        var dstKey: SymmetricKey?
        var title = raw.title
        var body = raw.bodyMarkdown
        if srcVault {
            guard let k = VaultService.key(for: raw.journalId) else { throw VaultWriteError.lockedVault }
            srcKey = k
            title = VaultService.unseal(title, key: k) ?? title
            body = VaultService.unseal(body, key: k) ?? body
        }
        if dstVault {
            guard let k = VaultService.key(for: journalId) else { throw VaultWriteError.lockedVault }
            dstKey = k
            title = try VaultService.seal(title, key: k)
            body = try VaultService.seal(body, key: k)
        }
        try dbPool.write { db in
            try db.execute(sql: """
                UPDATE entries SET journal_id = ?, title = ?, body_markdown = ?, updated_at = ? WHERE id = ?
                """, arguments: [journalId, title, body, Self.isoNow(), entryId])
        }
        // Re-key the entry's attachment blobs across the same boundary.
        try rekeyAttachmentsForEntry(entryId, srcKey: srcKey, dstKey: dstKey)
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

    // MARK: - Vault envelopes (Phase 9)

    func saveVaultEnvelope(_ env: VaultEnvelope) throws {
        try dbPool.write { db in var m = env; try m.save(db) }
    }

    func vaultEnvelope(journalId: String) throws -> VaultEnvelope? {
        try dbPool.read { db in try VaultEnvelope.fetchOne(db, key: journalId) }
    }

    /// Flip a journal's vault flag (the envelope is stored separately).
    func setJournalVault(_ isVault: Bool, journalId: String) throws {
        try dbPool.write { db in
            try db.execute(sql: "UPDATE journals SET is_vault = ? WHERE id = ?",
                           arguments: [isVault ? 1 : 0, journalId])
        }
    }

    // MARK: - Vault transparent sealing (Phase 9)

    enum VaultWriteError: Error, LocalizedError {
        /// Attempted to write (or move into/out of) a vault entry while the vault
        /// is locked — refused so a vault's plaintext never lands on disk and a
        /// sealed entry is never orphaned by re-keying it with no key in hand.
        case lockedVault
        var errorDescription: String? {
            "This entry belongs to a locked vault. Unlock the vault before saving or moving it."
        }
    }

    /// Journal ids flagged `is_vault` — the set whose entry text is sealed under
    /// a per-journal content key. One small read, resolved at each entry
    /// boundary so seal/unseal decisions never go stale against a converted
    /// journal.
    func vaultJournalIds() throws -> Set<String> {
        try dbPool.read { db in
            Set(try String.fetchAll(db, sql: "SELECT id FROM journals WHERE is_vault = 1"))
        }
    }

    /// Decrypt a vault entry's title + body for in-memory use. Non-vault
    /// entries — and vault entries whose journal is locked (no session key) or
    /// sealed under a key we can't produce — pass through unchanged; a locked
    /// entry stays sealed and is gated out of every view by
    /// `AppState.visibleEntries`.
    private func unsealForRead(_ entry: Entry, vaultIds: Set<String>) -> Entry {
        guard vaultIds.contains(entry.journalId),
              let key = VaultService.key(for: entry.journalId) else { return entry }
        var e = entry
        e.title = VaultService.unseal(entry.title, key: key) ?? entry.title
        e.bodyMarkdown = VaultService.unseal(entry.bodyMarkdown, key: key) ?? entry.bodyMarkdown
        return e
    }

    /// Seal a vault entry's title + body before it touches disk. Non-vault
    /// entries pass through. A *locked* vault throws `lockedVault` rather than
    /// persist plaintext — unless the text is already sealed (an unchanged
    /// round-trip), which is left intact.
    private func sealForWrite(_ entry: Entry, vaultIds: Set<String>) throws -> Entry {
        guard vaultIds.contains(entry.journalId) else { return entry }
        guard let key = VaultService.key(for: entry.journalId) else {
            if VaultService.isSealed(entry.title) || VaultService.isSealed(entry.bodyMarkdown) {
                return entry
            }
            throw VaultWriteError.lockedVault
        }
        var e = entry
        e.title = try VaultService.seal(entry.title, key: key)
        e.bodyMarkdown = try VaultService.seal(entry.bodyMarkdown, key: key)
        return e
    }

    /// `(isVault, key)` for the journal owning `entryId`. `key` is nil when the
    /// vault is locked. A non-vault entry returns `(false, nil)`. Used to decide
    /// attachment-blob sealing, which follows the owning entry's journal.
    private func vaultContextForEntry(_ entryId: String) throws -> (isVault: Bool, key: SymmetricKey?) {
        let row = try dbPool.read { db in
            try Row.fetchOne(db, sql: """
                SELECT j.id AS jid, j.is_vault AS isv
                FROM entries e JOIN journals j ON j.id = e.journal_id
                WHERE e.id = ?
                """, arguments: [entryId])
        }
        guard let row, (row["isv"] as Int64? ?? 0) == 1 else { return (false, nil) }
        let jid: String = row["jid"]
        return (true, VaultService.key(for: jid))
    }

    /// Decrypt an attachment's sealed `data` / `thumbnail_data` under `key`.
    /// Plaintext blobs (non-vault, or sealed under a key we don't have) pass
    /// through unchanged.
    private func unsealAttachment(_ a: Attachment, key: SymmetricKey) -> Attachment {
        var m = a
        if VaultService.isSealedData(a.data), let d = VaultService.unsealData(a.data, key: key) { m.data = d }
        if let t = a.thumbnailData, VaultService.isSealedData(t), let u = VaultService.unsealData(t, key: key) {
            m.thumbnailData = u
        }
        return m
    }

    private func unsealThumb(_ t: AttachmentThumb, key: SymmetricKey) -> AttachmentThumb {
        guard let data = t.thumbnailData, VaultService.isSealedData(data),
              let u = VaultService.unsealData(data, key: key) else { return t }
        var m = t
        m.thumbnailData = u
        return m
    }

    func deleteVaultEnvelope(journalId: String) throws {
        try dbPool.write { db in _ = try VaultEnvelope.deleteOne(db, key: journalId) }
    }

    /// Reverse of `sealEntries`: decrypt a journal's sealed entries back to
    /// plaintext under `key` — the data-layer step of *removing* a vault. Rows
    /// not sealed are skipped (idempotent). Crypto runs on the main actor here,
    /// before the write closure.
    func unsealEntries(inJournal journalId: String, using key: SymmetricKey) throws {
        let rows = try dbPool.read { db in
            try Entry.filter(Column("journal_id") == journalId).fetchAll(db)
        }
        let plain: [Entry] = rows.compactMap { e in
            guard VaultService.isSealed(e.title) || VaultService.isSealed(e.bodyMarkdown) else { return nil }
            var m = e
            if let t = VaultService.unseal(e.title, key: key) { m.title = t }
            if let b = VaultService.unseal(e.bodyMarkdown, key: key) { m.bodyMarkdown = b }
            return m
        }
        guard !plain.isEmpty else { return }
        try dbPool.write { db in
            for e in plain { try e.update(db) }
        }
    }

    /// Seal (`seal == true`) or unseal (`false`) every attachment blob belonging
    /// to a journal's entries under `key` — the attachment counterpart of
    /// `sealEntries` / `unsealEntries`. Idempotent: blobs already in the target
    /// state are skipped. Crypto runs on the main actor here, before the write.
    func rekeyAttachments(inJournal journalId: String, key: SymmetricKey, seal: Bool) throws {
        let rows = try dbPool.read { db in
            try Attachment
                .filter(sql: "entry_id IN (SELECT id FROM entries WHERE journal_id = ?)", arguments: [journalId])
                .fetchAll(db)
        }
        let changed: [Attachment] = try rows.compactMap { a in
            let dataSealed = VaultService.isSealedData(a.data)
            let thumbSealed = a.thumbnailData.map(VaultService.isSealedData) ?? true   // nil ⇒ nothing to do
            if seal {
                if dataSealed && thumbSealed { return nil }
                var m = a
                if !dataSealed { m.data = try VaultService.sealData(a.data, key: key) }
                if let t = a.thumbnailData, !VaultService.isSealedData(t) {
                    m.thumbnailData = try VaultService.sealData(t, key: key)
                }
                return m
            } else {
                let hasSealed = dataSealed || (a.thumbnailData.map(VaultService.isSealedData) ?? false)
                if !hasSealed { return nil }
                var m = a
                if dataSealed, let d = VaultService.unsealData(a.data, key: key) { m.data = d }
                if let t = a.thumbnailData, VaultService.isSealedData(t), let u = VaultService.unsealData(t, key: key) {
                    m.thumbnailData = u
                }
                return m
            }
        }
        guard !changed.isEmpty else { return }
        try dbPool.write { db in for a in changed { try a.update(db) } }
    }

    /// Re-key one entry's attachment blobs when it crosses a journal boundary:
    /// unseal with `srcKey` (moving out of a vault) then seal with `dstKey`
    /// (moving into one). Either may be nil.
    private func rekeyAttachmentsForEntry(_ entryId: String, srcKey: SymmetricKey?, dstKey: SymmetricKey?) throws {
        guard srcKey != nil || dstKey != nil else { return }
        let rows = try dbPool.read { db in
            try Attachment.filter(Column("entry_id") == entryId).fetchAll(db)
        }
        guard !rows.isEmpty else { return }
        let changed: [Attachment] = try rows.map { a in
            var dataBytes = a.data
            var thumbBytes = a.thumbnailData
            if let srcKey {
                if VaultService.isSealedData(dataBytes), let d = VaultService.unsealData(dataBytes, key: srcKey) { dataBytes = d }
                if let t = thumbBytes, VaultService.isSealedData(t), let u = VaultService.unsealData(t, key: srcKey) { thumbBytes = u }
            }
            if let dstKey {
                if !VaultService.isSealedData(dataBytes) { dataBytes = try VaultService.sealData(dataBytes, key: dstKey) }
                if let t = thumbBytes, !VaultService.isSealedData(t) { thumbBytes = try VaultService.sealData(t, key: dstKey) }
            }
            var m = a
            m.data = dataBytes
            m.thumbnailData = thumbBytes
            return m
        }
        try dbPool.write { db in for a in changed { try a.update(db) } }
    }

    /// Seal every not-yet-sealed entry in a journal under `key` — the data-layer
    /// step of converting an existing journal into a vault. Reads each row's
    /// current plaintext and rewrites it sealed in one transaction; rows already
    /// sealed are skipped so a re-run (or partial prior conversion) is a no-op.
    /// Crypto runs on the main actor here, before the write closure.
    func sealEntries(inJournal journalId: String, using key: SymmetricKey) throws {
        let rows = try dbPool.read { db in
            try Entry.filter(Column("journal_id") == journalId).fetchAll(db)
        }
        let sealed: [Entry] = try rows.compactMap { e in
            let titleSealed = VaultService.isSealed(e.title)
            let bodySealed = VaultService.isSealed(e.bodyMarkdown)
            if titleSealed && bodySealed { return nil }
            var m = e
            if !titleSealed { m.title = try VaultService.seal(e.title, key: key) }
            if !bodySealed { m.bodyMarkdown = try VaultService.seal(e.bodyMarkdown, key: key) }
            return m
        }
        guard !sealed.isEmpty else { return }
        try dbPool.write { db in
            for e in sealed { try e.update(db) }
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
            // The starter set for a fresh install. The full curated set is
            // browsable from Manage Templates… → Add from Library… (so existing
            // installs, whose table is non-empty and never re-seeds, can still
            // pull the rest in). See TemplateLibrary.
            for (i, curated) in TemplateLibrary.seedDefaults.enumerated() {
                var t = Template.newDraft(name: curated.name, body: curated.body, sortOrder: i)
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
        let key = try vaultContextForEntry(entryId).key
        let raw = try dbPool.read { db in
            try Attachment
                .filter(Column("entry_id") == entryId)
                .order(Column("created_at").asc)
                .fetchAll(db)
        }
        guard let key else { return raw }
        return raw.map { unsealAttachment($0, key: key) }
    }

    /// One full attachment row (including the `data` BLOB) by id — backs the
    /// full-size viewer / video player.
    func attachment(id: String) throws -> Attachment? {
        guard let raw = try dbPool.read({ db in try Attachment.fetchOne(db, key: id) }) else { return nil }
        guard let key = try vaultContextForEntry(raw.entryId).key else { return raw }
        return unsealAttachment(raw, key: key)
    }

    /// One lightweight thumbnail projection by id (no full `data` BLOB) — backs
    /// inline-media rendering in the editor preview.
    func attachmentThumb(id: String) throws -> AttachmentThumb? {
        guard let thumb = try dbPool.read({ db -> AttachmentThumb? in
            let row = try Row.fetchOne(db, sql: """
                SELECT id, entry_id, kind, mime_type, filename, thumbnail_data, width, height
                FROM attachments WHERE id = ?
                """, arguments: [id])
            return row.map { AttachmentThumb(row: $0) }
        }) else { return nil }
        guard let key = try vaultContextForEntry(thumb.entryId).key else { return thumb }
        return unsealThumb(thumb, key: key)
    }

    /// Lightweight thumbnails (no full `data` BLOB) for one entry — drives the
    /// editor's photo strip.
    func attachmentThumbs(forEntry entryId: String) throws -> [AttachmentThumb] {
        let key = try vaultContextForEntry(entryId).key
        let raw = try dbPool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, entry_id, kind, mime_type, filename, thumbnail_data, width, height
                FROM attachments WHERE entry_id = ? ORDER BY created_at ASC
                """, arguments: [entryId]).map { AttachmentThumb(row: $0) }
        }
        guard let key else { return raw }
        return raw.map { unsealThumb($0, key: key) }
    }

    func insertAttachment(_ attachment: Attachment) throws {
        let ctx = try vaultContextForEntry(attachment.entryId)
        var prepared = attachment
        if ctx.isVault {
            // Adding media to a vault entry: seal its bytes. Refuse if the vault
            // is locked rather than write plaintext into it.
            guard let key = ctx.key else { throw VaultWriteError.lockedVault }
            prepared.data = try VaultService.sealData(attachment.data, key: key)
            if let thumb = attachment.thumbnailData {
                prepared.thumbnailData = try VaultService.sealData(thumb, key: key)
            }
        }
        try dbPool.write { db in
            var mutable = prepared
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

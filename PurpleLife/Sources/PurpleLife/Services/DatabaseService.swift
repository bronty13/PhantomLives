import CryptoKit
import Foundation
import GRDB

/// Sole owner of the GRDB `DatabasePool` for `purplelife.sqlite`. Runs the
/// append-only migrator at init and exposes thin per-record CRUD wrappers.
/// Migration logic lives in `static applyMigrations(to:)` so the test suite
/// applies the *real* migrator instead of a duplicated fixture — drift
/// between production schema and tests would defeat the migration tests.
///
/// **At-rest encryption (slice A2)**: the vendored SQLCipher 4.6.1
/// amalgamation (see `Vendor/SQLCipher/`) provides an encrypted-at-rest
/// SQLite. At link time SQLCipher's `sqlite3_*` symbols shadow the
/// system `libsqlite3.dylib`, so GRDB's `CSQLite`-imported calls land
/// in SQLCipher. When `keyResolver` returns a DEK, every `DatabasePool`
/// connection runs `PRAGMA key` at open via
/// `Configuration.prepareDatabase`. The whole `purplelife.sqlite` file
/// — objects table, FTS5 index, attachments metadata, indexes —
/// becomes opaque ciphertext on disk. The earlier slice A2' column-
/// level wrap on `fields_json` is now redundant; its seal/unseal
/// helpers are retained for transitional read-back of upgrade
/// installs whose row content was wrapped during the A2'-only window.
///
/// **Migration**: on first launch after A2 ships, an existing
/// plaintext `purplelife.sqlite` is detected (via SQLite-3 magic
/// header probe) and copied into a SQLCipher-keyed sibling file via
/// the `sqlcipher_export()` PRAGMA, then atomically renamed. One-shot
/// per install; idempotent because the magic-header check skips
/// already-encrypted files on subsequent launches.
@MainActor
final class DatabaseService {
    static let shared = DatabaseService()

    private(set) var dbPool: DatabasePool

    /// Resolver wired by `AppState` so the singleton can fetch the DEK
    /// without taking a `KeyStore` dependency at the call site. nil → no
    /// encryption (plaintext fallback, the path tests exercise — SQLCipher
    /// without a key behaves exactly like plain SQLite, so the test
    /// suite's existing pattern of operating against
    /// `~/Library/Application Support/PurpleLife/purplelife.sqlite`
    /// continues to work even with SQLCipher linked).
    nonisolated(unsafe) static var keyResolver: (() -> SymmetricKey?)?

    private static var currentKey: SymmetricKey? { keyResolver?() }

    /// First 16 bytes of an unencrypted SQLite 3 file. SQLCipher encrypts
    /// these bytes too, so a magic-header match is a reliable test for
    /// "this file is plaintext SQLite and needs migration".
    ///
    /// `nonisolated` because the constant is Sendable and gets read from
    /// `isPlaintextSQLite(at:)` — a `nonisolated` static helper that
    /// runs on whatever queue GRDB hands it. Without this, Swift 6's
    /// strict-concurrency checking flags the access as an isolation
    /// violation (already a warning in Swift 5 mode).
    nonisolated private static let plainSQLiteMagic: [UInt8] = Array("SQLite format 3\0".utf8)

    static var supportDirectory: URL {
        // Under XCTest, route persistence to a fresh per-process temp
        // directory instead of the user's real Application Support.
        // The singleton's open path can't decrypt the user's SQLCipher
        // DB at test-time (no key resolver, by design — AppState's
        // keystore bootstrap is skipped under XCTest), and the previous
        // behaviour of sharing the user's plaintext production DB
        // disappeared the moment we shipped page-level encryption.
        // A per-process path also means parallel test invocations and
        // local dev runs can't stomp on each other.
        if isUnderXCTest { return testSupportDirectoryCached }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("PurpleLife", isDirectory: true)
    }

    nonisolated private static let isUnderXCTest: Bool =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    /// Per-process Application-Support stand-in used when running under
    /// XCTest. Created on first read; the directory is freshly emptied
    /// so each test process starts with a clean DB + attachments dir +
    /// no stale settings.json. Tests that need to share state between
    /// methods rely on the same path, but each test invocation gets a
    /// pristine directory.
    nonisolated private static let testSupportDirectoryCached: URL = {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("PurpleLife-tests-\(ProcessInfo.processInfo.processIdentifier)",
                                    isDirectory: true)
        let fm = FileManager.default
        try? fm.removeItem(at: url)
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    var databaseURL: URL {
        Self.supportDirectory.appendingPathComponent("purplelife.sqlite")
    }

    var attachmentsDirectory: URL {
        Self.supportDirectory.appendingPathComponent("attachments", isDirectory: true)
    }

    private init() {
        let dir = Self.supportDirectory
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let attDir = dir.appendingPathComponent("attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: attDir, withIntermediateDirectories: true)
        let dbURL = dir.appendingPathComponent("purplelife.sqlite")

        // If a DEK is available and the on-disk file is still plaintext,
        // migrate it to SQLCipher before any DatabasePool opens against
        // it. The migration uses `sqlcipher_export()` which copies row
        // content + indexes into a freshly-keyed sibling file; we then
        // atomically swap it in for the plaintext original.
        if let key = Self.currentKey, Self.isPlaintextSQLite(at: dbURL) {
            do {
                try Self.migratePlaintextToSQLCipher(at: dbURL, key: key)
                NSLog("PurpleLife: migrated plaintext purplelife.sqlite to SQLCipher")
            } catch {
                NSLog("PurpleLife: SQLCipher migration failed — \(error.localizedDescription); continuing with plaintext DB")
            }
        }

        // At property-init time `keyResolver` is almost always nil — the
        // singleton is constructed when AppState reads `DatabaseService.shared`
        // during its OWN property init, which runs BEFORE AppState wires
        // the resolver in its init body. Result: `makeConfiguration()`
        // returns a bare config (no PRAGMA key). Opening an already-
        // SQLCipher-encrypted file with that config fails the page MAC
        // check immediately and SQLite reports "file is not a database".
        //
        // Crashing here with `try!` would brick every launch after the
        // first migration. Instead: try the open; on failure (encrypted
        // file + no key in scope), substitute a temp-file placeholder
        // pool so the property remains non-nil. `AppState.init` calls
        // `reopenDatabase()` immediately after wiring the resolver,
        // which replaces the placeholder with the real keyed pool.
        do {
            dbPool = try DatabasePool(path: dbURL.path, configuration: Self.makeConfiguration())
            try migrate()
        } catch {
            NSLog("PurpleLife: DB open deferred to keyed reopen — \(error.localizedDescription)")
            let placeholderPath = NSTemporaryDirectory()
                + "purplelife-throwaway-\(UUID().uuidString).sqlite"
            dbPool = try! DatabasePool(path: placeholderPath)
        }
    }

    /// Re-open the underlying GRDB pool against the on-disk database. Used
    /// after a backup-restore so the running process picks up the swapped file.
    func reopenDatabase() throws {
        // If the file is plaintext + we have a key, migrate before opening.
        //
        // The migration is fragile in one specific way: if the existing
        // `dbPool` is still holding the plaintext file open with an
        // active WAL, two bad things can happen — (1) `sqlcipher_export`
        // doesn't fully propagate WAL-only pages into the encrypted
        // sibling, and (2) after the atomic rename, the leftover
        // `purplelife.sqlite-wal` and `-shm` files from the old plain-
        // text pool sit alongside the new SQLCipher main file. SQLite
        // then tries to apply the plaintext WAL onto the SQLCipher main
        // at read time and the connection bombs with "database disk
        // image is malformed."
        //
        // Defence: drop the existing pool first (forces a throwaway
        // reassignment so the old pool's ARC reaches zero and its file
        // handles release), then checkpoint + delete any leftover
        // journal files, THEN run the migration with no other handles
        // open to the source file.
        if let key = Self.currentKey, Self.isPlaintextSQLite(at: databaseURL) {
            // Reassign dbPool to a transient pool on a TEMP FILE so the
            // original pool's connections to the plaintext source get
            // released via Swift ARC. A `:memory:` path WON'T work here
            // — GRDB's DatabasePool requires WAL mode, which is not
            // available for in-memory databases. ("could not activate
            // WAL Mode at path: :memory:".) Use a real file on the
            // local tmpfs instead.
            let throwawayPath = NSTemporaryDirectory()
                + "purplelife-throwaway-\(UUID().uuidString).sqlite"
            dbPool = try DatabasePool(path: throwawayPath)
            Self.checkpointAndPruneJournalFiles(at: databaseURL)
            try Self.migratePlaintextToSQLCipher(at: databaseURL, key: key)
        }
        dbPool = try DatabasePool(path: databaseURL.path, configuration: Self.makeConfiguration())
        try migrate()
        // Best-effort cleanup of any throwaway temp DBs left behind by
        // prior migration runs in this process or earlier launches.
        Self.purgeMigrationThrowaways()
    }

    /// Force the plaintext source DB to checkpoint its WAL into the main
    /// file, then close, then remove any leftover `-wal`, `-shm`, and
    /// `-journal` files. After this returns there are no journal files
    /// alongside `purplelife.sqlite` — the migration's fresh
    /// `DatabaseQueue` will run against a clean single-file state.
    nonisolated private static func checkpointAndPruneJournalFiles(at url: URL) {
        do {
            let queue = try DatabaseQueue(path: url.path)
            try queue.writeWithoutTransaction { db in
                // PRAGMA journal_mode = DELETE forces an immediate WAL
                // checkpoint and switches journaling out of WAL mode, so
                // the -wal and -shm files become eligible for removal.
                try db.execute(sql: "PRAGMA journal_mode = DELETE")
            }
            _ = queue
        } catch {
            NSLog("PurpleLife: pre-migration WAL checkpoint failed — \(error.localizedDescription)")
        }
        let fm = FileManager.default
        for suffix in ["-wal", "-shm", "-journal"] {
            let aux = URL(fileURLWithPath: url.path + suffix)
            try? fm.removeItem(at: aux)
        }
    }

    /// Sweep `NSTemporaryDirectory()` for the throwaway SQLite files
    /// `reopenDatabase` creates to drop the old pool's file handles
    /// before running the SQLCipher migration. Called after the
    /// final keyed pool open so the throwaway pool's connections
    /// have been released. Idempotent — no-op when there's nothing
    /// to remove. Includes `-wal` / `-shm` / `-journal` siblings.
    nonisolated private static func purgeMigrationThrowaways() {
        let fm = FileManager.default
        let dir = NSTemporaryDirectory()
        guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { return }
        for name in entries where name.hasPrefix("purplelife-throwaway-") {
            try? fm.removeItem(atPath: dir + name)
        }
    }

    // MARK: - SQLCipher configuration

    /// Build a GRDB `Configuration` that sets `PRAGMA key` on every new
    /// connection. When `keyResolver` returns nil (tests, edge cases),
    /// the configuration is a bare default — SQLCipher without a key
    /// behaves exactly like plain SQLite, so plaintext files keep
    /// working.
    nonisolated static func makeConfiguration() -> Configuration {
        var config = Configuration()
        guard let key = keyResolver?() else { return config }
        let hexKey = hexEncoded(key.rawData)
        config.prepareDatabase { db in
            // SQLCipher's binary-key form is the *string value* `x'HEX'`
            // (which the PRAGMA-key parser then recognizes as a raw blob,
            // no KDF). We build it with single-quoted SQL and the inner
            // `'` doubled (SQL's escape for a literal single-quote inside
            // a single-quoted string). DO NOT switch to double quotes —
            // our SQLCipher is built with SQLITE_DQS=0 so `"x'HEX'"` is
            // parsed as an identifier, and ATTACH KEY vs PRAGMA key
            // resolve that ambiguity differently, silently producing
            // mismatched encryption / decryption keys.
            try db.execute(sql: "PRAGMA key = 'x''\(hexKey)'''")
            // Recommended SQLCipher PRAGMA defaults — match Zetetic's
            // documented best practice. Setting these explicitly future-
            // proofs us against SQLCipher 5 changing internal defaults.
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

    /// True when `url` points at an existing file whose first 16 bytes
    /// are the SQLite 3 magic header. Used to detect upgrade-time
    /// plaintext DBs that need the SQLCipher migration.
    nonisolated static func isPlaintextSQLite(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: plainSQLiteMagic.count),
              head.count == plainSQLiteMagic.count else { return false }
        return Array(head) == plainSQLiteMagic
    }

    /// One-shot: copy a plaintext SQLite DB into a freshly-keyed
    /// SQLCipher sibling via the `sqlcipher_export()` PRAGMA, then
    /// atomically rename the encrypted file over the plaintext one.
    ///
    /// `sqlcipher_export` is SQLCipher's documented migration path. It
    /// copies the schema + every row, including indexes and triggers,
    /// in a single SQL call. Faster and less error-prone than walking
    /// the schema row-by-row.
    nonisolated static func migratePlaintextToSQLCipher(at url: URL, key: SymmetricKey) throws {
        let fm = FileManager.default
        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).sqlcipher.tmp")
        try? fm.removeItem(at: tempURL)

        let hexKey = hexEncoded(key.rawData)

        // Open plaintext DB with no key. `writeWithoutTransaction` runs
        // the ATTACH + sqlcipher_export + DETACH sequence outside of a
        // SQLite transaction — DETACH fails with "database is locked"
        // when called inside one because the attached database still
        // has an active reference.
        let plainQueue = try DatabaseQueue(path: url.path)
        try plainQueue.writeWithoutTransaction { db in
            try db.execute(sql: "ATTACH DATABASE ? AS encrypted KEY 'x''\(hexKey)'''",
                           arguments: [tempURL.path])
            try db.execute(sql: "SELECT sqlcipher_export('encrypted')")
            try db.execute(sql: "DETACH DATABASE encrypted")
        }
        // Let the local `plainQueue` go out of scope so the atomic rename
        // below can replace the file without a "resource busy".
        _ = plainQueue

        try fm.removeItem(at: url)
        try fm.moveItem(at: tempURL, to: url)
    }

    // MARK: - Migrations

    private func migrate() throws {
        try Self.applyMigrations(to: dbPool)
    }

    /// Public entry point so tests can apply the real schema to an in-memory
    /// `DatabaseQueue`. Add new versions to this function — never inside
    /// `init()` — to keep test coverage automatic.
    /// Marked `nonisolated` so test helpers don't all need `@MainActor`;
    /// the body is pure schema construction with no actor-isolated state.
    nonisolated static func applyMigrations(to writer: DatabaseWriter) throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_objects") { db in
            // Single objects table per the storage shape locked in PLAN.md.
            // Typed columns for things every object has + a JSON `fields_json`
            // blob for everything else. The blob travels through CloudKit's
            // `encryptedValues` in Phase 4; locally it's plaintext (FileVault
            // is the on-disk encryption layer).
            try db.create(table: "objects") { t in
                t.column("id", .text).primaryKey()
                t.column("type_id", .text).notNull()
                t.column("parent_id", .text)
                t.column("fields_json", .text).notNull().defaults(to: "{}")
                t.column("created_at", .text).notNull()
                t.column("updated_at", .text).notNull()
            }
            try db.create(index: "idx_objects_type",       on: "objects", columns: ["type_id"])
            try db.create(index: "idx_objects_parent",     on: "objects", columns: ["parent_id"])
            try db.create(index: "idx_objects_updated_at", on: "objects", columns: ["updated_at"])
        }

        // v2 — attachments metadata table. Per the attachments decision in
        // HANDOFF.md (2026-05-10), file content lives at
        // ~/Library/Application Support/PurpleLife/attachments/<sha256>.<ext>;
        // this table is metadata only. Content-addressing means the same
        // file referenced by multiple objects de-duplicates on disk.
        migrator.registerMigration("v2_attachments") { db in
            try db.create(table: "attachments") { t in
                t.column("id", .text).primaryKey()
                t.column("parent_object_id", .text).notNull()
                    .references("objects", column: "id", onDelete: .cascade)
                t.column("field_key", .text).notNull()
                t.column("sha256", .text).notNull()
                t.column("filename", .text).notNull()
                t.column("mime_type", .text).notNull().defaults(to: "application/octet-stream")
                t.column("size_bytes", .integer).notNull().defaults(to: 0)
                t.column("created_at", .text).notNull()
            }
            try db.create(index: "idx_attachments_parent",
                          on: "attachments",
                          columns: ["parent_object_id"])
            try db.create(index: "idx_attachments_sha256",
                          on: "attachments",
                          columns: ["sha256"])
        }

        // v3 — FTS5 virtual table for `SearchService`. Phase 2 search runs
        // over decrypted fields at index time; the FTS table is rebuilt
        // from scratch on launch (cheap for the row counts we'll see) and
        // maintained incrementally on each ObjectEngine mutation. The
        // recommended `objects_fts` shape: typed `object_id` + `type_id`
        // (UNINDEXED so `MATCH` doesn't consider them), plus `title` and
        // `body` text content.
        migrator.registerMigration("v3_fts5") { db in
            try db.create(virtualTable: "objects_fts", using: FTS5()) { t in
                t.tokenizer = .porter()
                t.column("object_id").notIndexed()
                t.column("type_id").notIndexed()
                t.column("title")
                t.column("body")
            }
        }

        try migrator.migrate(writer)
    }

    // MARK: - Object CRUD
    //
    // Writes go straight through to GRDB — the SQLCipher layer below
    // encrypts the SQLite page bytes as they hit disk, so no per-column
    // wrapping is needed on top. Reads still pass through
    // `unsealFromStorage` to gracefully handle rows that were written
    // during the A2'-only window when `fields_json` was column-wrapped;
    // the helper detects the magic header and unwraps when present,
    // pass-through otherwise.

    func insertObject(_ object: ObjectRecord) throws {
        try dbPool.write { db in
            try object.insert(db)
        }
    }

    func updateObject(_ object: ObjectRecord) throws {
        var stamped = object
        stamped.updatedAt = Self.isoNow()
        try dbPool.write { db in
            try stamped.update(db)
        }
    }

    func upsertObject(_ object: ObjectRecord) throws {
        try dbPool.write { db in
            try object.save(db)
        }
    }

    func deleteObject(id: String) throws {
        try dbPool.write { db in
            _ = try ObjectRecord.deleteOne(db, key: id)
        }
    }

    func fetchObject(id: String) throws -> ObjectRecord? {
        let key = Self.currentKey
        return try dbPool.read { db in
            guard let row = try ObjectRecord.fetchOne(db, key: id) else { return nil }
            return Self.unsealFromStorage(row, key: key)
        }
    }

    func fetchAllObjects() throws -> [ObjectRecord] {
        let key = Self.currentKey
        return try dbPool.read { db in
            try ObjectRecord.order(Column("updated_at").desc).fetchAll(db)
                .map { Self.unsealFromStorage($0, key: key) }
        }
    }

    func fetchObjects(typeId: String) throws -> [ObjectRecord] {
        let key = Self.currentKey
        return try dbPool.read { db in
            try ObjectRecord
                .filter(Column("type_id") == typeId)
                .order(Column("updated_at").desc)
                .fetchAll(db)
                .map { Self.unsealFromStorage($0, key: key) }
        }
    }

    func fetchChildren(parentId: String) throws -> [ObjectRecord] {
        let key = Self.currentKey
        return try dbPool.read { db in
            try ObjectRecord
                .filter(Column("parent_id") == parentId)
                .order(Column("updated_at").desc)
                .fetchAll(db)
                .map { Self.unsealFromStorage($0, key: key) }
        }
    }

    // MARK: - Column-level encryption

    /// Wrap an in-memory `ObjectRecord` for storage. Returns a copy whose
    /// `fieldsJSON` is the base64 of an `EncryptedJSON` envelope when a
    /// key is provided, the original plaintext when `key == nil`.
    ///
    /// `nonisolated` + explicit-key parameter so the function can run
    /// inside GRDB's background queues. Callers grab the key on the
    /// main actor first, then pass it through.
    nonisolated static func sealForStorage(_ record: ObjectRecord, key: SymmetricKey?) -> ObjectRecord {
        guard let key else { return record }
        guard let plain = record.fieldsJSON.data(using: .utf8) else { return record }
        do {
            let wrapped = try EncryptedJSON.wrap(plain, key: key)
            var sealed = record
            sealed.fieldsJSON = wrapped.base64EncodedString()
            return sealed
        } catch {
            NSLog("PurpleLife: sealForStorage failed — \(error.localizedDescription)")
            return record
        }
    }

    /// Inverse of `sealForStorage`. Tolerant of plaintext rows (legacy
    /// data pre-migration) — detects them via the EncryptedJSON magic
    /// header inside the base64-decoded bytes.
    nonisolated static func unsealFromStorage(_ stored: ObjectRecord, key: SymmetricKey?) -> ObjectRecord {
        // Try base64 decode. Plaintext JSON ("{...}") will b64-decode
        // to garbage; the magic-header check below filters those out
        // by detecting that the leading bytes aren't `PLIF\x01`.
        guard let raw = Data(base64Encoded: stored.fieldsJSON),
              EncryptedJSON.hasMagic(raw) else {
            return stored
        }
        guard let key else {
            // Encrypted bytes on disk but keystore locked — return the
            // record with empty fields rather than crashing. Higher
            // layers will surface this as "no data visible" until the
            // keystore unlocks.
            var blanked = stored
            blanked.fieldsJSON = "{}"
            return blanked
        }
        do {
            let plain = try EncryptedJSON.unwrap(raw, key: key)
            var clear = stored
            clear.fieldsJSON = String(data: plain, encoding: .utf8) ?? "{}"
            return clear
        } catch {
            NSLog("PurpleLife: unsealFromStorage failed (\(stored.id)) — \(error.localizedDescription)")
            var blanked = stored
            blanked.fieldsJSON = "{}"
            return blanked
        }
    }

    /// Launch-time sweep that walks every row and wraps any plaintext
    /// `fields_json` value. Idempotent — rows already wrapped are
    /// skipped via the magic-header check. Returns the (encrypted,
    /// skipped) counts for the launch log.
    @discardableResult
    func encryptExistingObjectsIfNeeded() -> (encrypted: Int, skipped: Int) {
        guard let key = Self.currentKey else { return (0, 0) }
        var encrypted = 0
        var skipped = 0
        do {
            try dbPool.write { db in
                let rows = try Row.fetchAll(db, sql: "SELECT id, fields_json FROM objects")
                for row in rows {
                    let id: String = row["id"]
                    let stored: String = row["fields_json"]
                    // If the stored value base64-decodes to magic-headered
                    // bytes, it's already encrypted.
                    if let raw = Data(base64Encoded: stored), EncryptedJSON.hasMagic(raw) {
                        skipped += 1
                        continue
                    }
                    guard let plain = stored.data(using: .utf8) else { continue }
                    let wrapped = try EncryptedJSON.wrap(plain, key: key)
                    let b64 = wrapped.base64EncodedString()
                    try db.execute(
                        sql: "UPDATE objects SET fields_json = ? WHERE id = ?",
                        arguments: [b64, id]
                    )
                    encrypted += 1
                }
            }
        } catch {
            NSLog("PurpleLife: encryptExistingObjectsIfNeeded failed — \(error.localizedDescription)")
        }
        if encrypted > 0 {
            NSLog("PurpleLife: encrypted \(encrypted) object row(s) on launch; \(skipped) already encrypted")
        }
        return (encrypted, skipped)
    }

    func objectCount() throws -> Int {
        try dbPool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM objects") ?? 0
        }
    }

    func objectCount(typeId: String) throws -> Int {
        try dbPool.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM objects WHERE type_id = ?",
                arguments: [typeId]
            ) ?? 0
        }
    }

    // MARK: - Helpers

    static func isoNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

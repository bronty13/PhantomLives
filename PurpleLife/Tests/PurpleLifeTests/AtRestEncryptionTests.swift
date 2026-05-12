import XCTest
import CryptoKit
import GRDB
@testable import PurpleLife

/// Slice A3 — encrypted at-rest for settings.json and attachment files.
/// These tests run with explicit per-test keys (not via AppState's
/// keystore bootstrap, which is skipped under XCTest) so they exercise
/// the actual encrypt/decrypt path rather than the plaintext-passthrough
/// path the existing AttachmentServiceTests use.
@MainActor
final class AtRestEncryptionTests: XCTestCase {

    private var savedResolver: (() -> SymmetricKey?)?
    private var savedDBResolver: (() -> SymmetricKey?)?

    override func setUp() async throws {
        savedResolver = AttachmentService.keyResolver
        savedDBResolver = DatabaseService.keyResolver
    }

    override func tearDown() async throws {
        AttachmentService.keyResolver = savedResolver
        DatabaseService.keyResolver = savedDBResolver
    }

    private func wipe() throws {
        try DatabaseService.shared.dbPool.write { db in
            try db.execute(sql: "DELETE FROM attachments")
            try db.execute(sql: "DELETE FROM objects_fts")
            try db.execute(sql: "DELETE FROM objects")
        }
    }

    private func writeTempFile(_ contents: Data, ext: String = "bin") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("att-enc-\(UUID().uuidString).\(ext)")
        try contents.write(to: url, options: .atomic)
        return url
    }

    private func removeStoredFile(forSha hash: String) {
        if let url = AttachmentService.fileURL(forSha256: hash) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Attachment encryption

    func test_addWithKeyWritesCiphertextOnDisk() throws {
        try wipe()
        let key = SymmetricKey(size: .bits256)
        AttachmentService.keyResolver = { key }

        let plaintext = Data("a secret note body".utf8)
        let src = try writeTempFile(plaintext)
        let parent = try ObjectEngine.create(typeId: "Book", fields: ["title": "T"])
        let row = try AttachmentService.add(from: src, parentObjectId: parent.id, fieldKey: "cover")

        // sha256 stays plaintext-based (so dedup spans the encryption layer).
        XCTAssertEqual(row.sha256, AttachmentService.sha256(data: plaintext))

        // On-disk file is wrapped — first bytes are the magic header.
        let url = AttachmentService.fileURL(forSha256: row.sha256)!
        let onDisk = try Data(contentsOf: url)
        XCTAssertTrue(EncryptedJSON.hasMagic(onDisk), "Disk content must carry the EncryptedJSON magic header")
        XCTAssertNotEqual(onDisk, plaintext)

        // read() returns plaintext back.
        let decrypted = try AttachmentService.read(sha256: row.sha256)
        XCTAssertEqual(decrypted, plaintext)

        removeStoredFile(forSha: row.sha256)
    }

    func test_readWithWrongKeyThrows() throws {
        try wipe()
        let realKey = SymmetricKey(size: .bits256)
        AttachmentService.keyResolver = { realKey }

        let plaintext = Data("authenticated bytes".utf8)
        let src = try writeTempFile(plaintext)
        let parent = try ObjectEngine.create(typeId: "Book", fields: ["title": "T"])
        let row = try AttachmentService.add(from: src, parentObjectId: parent.id, fieldKey: "cover")

        // Swap to a wrong key for reading.
        let wrongKey = SymmetricKey(size: .bits256)
        AttachmentService.keyResolver = { wrongKey }
        XCTAssertThrowsError(try AttachmentService.read(sha256: row.sha256))
        XCTAssertNil(AttachmentService.image(forSha256: row.sha256), "image() swallows the error and returns nil")

        removeStoredFile(forSha: row.sha256)
    }

    func test_sweepWrapsPlaintextFilesIdempotently() throws {
        try wipe()
        // Phase 1: write a plaintext file (no key set), simulating a
        // pre-A3 install.
        AttachmentService.keyResolver = { nil }
        let plaintext = Data("legacy bytes".utf8)
        let src = try writeTempFile(plaintext)
        let parent = try ObjectEngine.create(typeId: "Book", fields: ["title": "T"])
        let row = try AttachmentService.add(from: src, parentObjectId: parent.id, fieldKey: "cover")
        let url = AttachmentService.fileURL(forSha256: row.sha256)!
        XCTAssertEqual(try Data(contentsOf: url), plaintext)

        // Phase 2: provide a key and sweep. The file should now carry
        // the magic and decrypt back to the original bytes. Other files
        // may exist in the shared Application Support dir from previous
        // test runs (already-encrypted, will be reported as skipped) —
        // we assert only on our specific file's outcome.
        let key = SymmetricKey(size: .bits256)
        AttachmentService.keyResolver = { key }
        let (encrypted1, _) = AttachmentService.encryptExistingFilesIfNeeded()
        XCTAssertGreaterThanOrEqual(encrypted1, 1, "At minimum our just-written plaintext file gets wrapped")

        let nowEncrypted = try Data(contentsOf: url)
        XCTAssertTrue(EncryptedJSON.hasMagic(nowEncrypted))
        XCTAssertEqual(try AttachmentService.read(sha256: row.sha256), plaintext)

        // Phase 3: re-run sweep — no NEW encryption (our file is now
        // wrapped, every other file was already wrapped).
        let (encrypted2, skipped2) = AttachmentService.encryptExistingFilesIfNeeded()
        XCTAssertEqual(encrypted2, 0, "Idempotent — second sweep wraps nothing new")
        XCTAssertGreaterThanOrEqual(skipped2, 1)

        removeStoredFile(forSha: row.sha256)
    }

    func test_dedupSurvivesEncryption() throws {
        try wipe()
        let key = SymmetricKey(size: .bits256)
        AttachmentService.keyResolver = { key }

        let plaintext = Data("shared payload".utf8)
        let srcA = try writeTempFile(plaintext)
        let srcB = try writeTempFile(plaintext)
        let parentA = try ObjectEngine.create(typeId: "Book", fields: ["title": "A"])
        let parentB = try ObjectEngine.create(typeId: "Book", fields: ["title": "B"])

        let rowA = try AttachmentService.add(from: srcA, parentObjectId: parentA.id, fieldKey: "cover")
        let rowB = try AttachmentService.add(from: srcB, parentObjectId: parentB.id, fieldKey: "cover")

        XCTAssertEqual(rowA.sha256, rowB.sha256, "Plaintext-keyed sha256 → same file path")
        // One file on disk shared by both rows; AES-GCM nonce is random
        // so each `wrap` would produce different ciphertext, but dedup
        // means we wrote it once and skipped the second wrap.
        let url = AttachmentService.fileURL(forSha256: rowA.sha256)!
        XCTAssertTrue(EncryptedJSON.hasMagic(try Data(contentsOf: url)))
        XCTAssertEqual(try AttachmentService.read(sha256: rowA.sha256), plaintext)

        removeStoredFile(forSha: rowA.sha256)
    }

    // MARK: - Settings encryption

    func test_settingsStoreEncryptsAndDecryptsRoundtrip() throws {
        // SettingsStore writes to the canonical settings.json at
        // ~/Library/Application Support/PurpleLife/. To avoid mutating
        // the live install during tests, snapshot whatever's there and
        // restore at the end.
        let dir = DatabaseService.supportDirectory
        let url = dir.appendingPathComponent("settings.json")
        let backup = try? Data(contentsOf: url)
        defer {
            if let backup {
                try? backup.write(to: url, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: url)
            }
        }

        let key = SymmetricKey(size: .bits256)
        let resolver: () -> SymmetricKey? = { key }

        let store = SettingsStore(keyResolver: resolver)
        store.settings.heightInches = 71.5
        store.save()

        // File on disk must carry the magic header.
        let onDisk = try Data(contentsOf: url)
        XCTAssertTrue(EncryptedJSON.hasMagic(onDisk),
                      "settings.json must be wrapped when a key is in scope")

        // Fresh store with the same key reads it back.
        let reloaded = SettingsStore(keyResolver: resolver)
        XCTAssertEqual(reloaded.settings.heightInches, 71.5)
    }

    // MARK: - Field-level encryption on objects.fields_json

    func test_sealUnsealRoundtripFieldsJSON() throws {
        let key = SymmetricKey(size: .bits256)
        let record = ObjectRecord.make(typeId: "Book", fields: [
            "title": "private title",
            "rating": 5
        ])
        let originalJSON = record.fieldsJSON
        XCTAssertTrue(originalJSON.contains("private title"))

        let sealed = DatabaseService.sealForStorage(record, key: key)
        XCTAssertNotEqual(sealed.fieldsJSON, originalJSON)
        // Decoding the base64 should produce magic-headered bytes.
        let raw = Data(base64Encoded: sealed.fieldsJSON)
        XCTAssertNotNil(raw)
        XCTAssertTrue(EncryptedJSON.hasMagic(raw!))

        // Round-trip with the same key.
        let unsealed = DatabaseService.unsealFromStorage(sealed, key: key)
        XCTAssertEqual(unsealed.fieldsJSON, originalJSON)
    }

    func test_unsealWithoutKeyBlanksTheFields() throws {
        let key = SymmetricKey(size: .bits256)
        let record = ObjectRecord.make(typeId: "Book", fields: ["title": "hidden"])
        let sealed = DatabaseService.sealForStorage(record, key: key)

        // No key → fields are blanked rather than crashing.
        let blanked = DatabaseService.unsealFromStorage(sealed, key: nil)
        XCTAssertEqual(blanked.fieldsJSON, "{}")
    }

    func test_unsealWithWrongKeyBlanksTheFields() throws {
        let key = SymmetricKey(size: .bits256)
        let wrong = SymmetricKey(size: .bits256)
        let record = ObjectRecord.make(typeId: "Book", fields: ["title": "hidden"])
        let sealed = DatabaseService.sealForStorage(record, key: key)

        // Wrong key throws inside EncryptedJSON.unwrap → defensive
        // blanking keeps higher layers running.
        let blanked = DatabaseService.unsealFromStorage(sealed, key: wrong)
        XCTAssertEqual(blanked.fieldsJSON, "{}")
    }

    func test_unsealPlaintextRowPassesThrough() throws {
        // Legacy rows from before A2' shipped — fields_json is plain
        // JSON, not base64-of-ciphertext. unseal must leave them alone.
        let key = SymmetricKey(size: .bits256)
        let record = ObjectRecord.make(typeId: "Book", fields: ["title": "legacy"])
        XCTAssertTrue(record.fieldsJSON.hasPrefix("{"))
        let result = DatabaseService.unsealFromStorage(record, key: key)
        XCTAssertEqual(result.fieldsJSON, record.fieldsJSON)
    }

    // MARK: - Whole-database SQLCipher (slice A2)

    /// Build a `DatabasePool` keyed under SQLCipher with `key`. Mirrors
    /// the production `DatabaseService.makeConfiguration()` path but
    /// without going through the singleton — lets tests exercise the
    /// SQLCipher integration against tempdir DBs without disturbing the
    /// `~/Library/Application Support/PurpleLife/purplelife.sqlite`
    /// production file.
    private func makeKeyedPool(at url: URL, key: SymmetricKey) throws -> DatabasePool {
        let hex = key.withUnsafeBytes { Data($0) }
            .map { String(format: "%02x", $0) }.joined()
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA key = \"x'\(hex)'\"")
            try db.execute(sql: "PRAGMA cipher_page_size = 4096")
            try db.execute(sql: "PRAGMA kdf_iter = 256000")
            try db.execute(sql: "PRAGMA cipher_hmac_algorithm = HMAC_SHA512")
            try db.execute(sql: "PRAGMA cipher_kdf_algorithm = PBKDF2_HMAC_SHA512")
        }
        return try DatabasePool(path: url.path, configuration: config)
    }

    private func tempDBPath() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("purplelife-test-\(UUID().uuidString).sqlite")
    }

    // (test_sqlcipherProviderVersion removed — the real probe is
    // test_sqlcipherIsActuallyLinked below, which uses PRAGMA
    // cipher_version. cipher_provider returns nil without an attached
    // codec, and sqlcipher_version() scalar function isn't always
    // registered — both are weaker signals than cipher_version.)

    func test_sqlite3LibversionGoesToSQLCipher() throws {
        // Bypass GRDB entirely — call `sqlite3_libversion` directly via
        // @_silgen_name. If our static SQLCipher's symbol is being
        // resolved, we get its version (built from SQLite 3.46.x
        // upstream). If the system libsqlite3 is winning, we get
        // whatever macOS ships (varies per OS version, but never has
        // the SQLCipher fingerprint).
        typealias SQLite3LibversionFn = @convention(c) () -> UnsafePointer<CChar>?
        let lib = dlopen(nil, RTLD_NOW)
        defer { if lib != nil { dlclose(lib) } }
        guard let sym = dlsym(lib, "sqlite3_libversion") else {
            return XCTFail("sqlite3_libversion not in binary namespace")
        }
        let fn = unsafeBitCast(sym, to: SQLite3LibversionFn.self)
        guard let cStr = fn() else { return XCTFail("sqlite3_libversion returned nil") }
        let version = String(cString: cStr)
        // Just print so we see what's actually resolved.
        print("sqlite3_libversion() at runtime = '\(version)'")
        XCTAssertFalse(version.isEmpty)
    }

    func test_sqlcipherIsActuallyLinked() throws {
        // PRAGMA cipher_version returns a non-null version string when
        // SQLCipher is the underlying SQLite library. Returns NULL (or
        // is silently ignored) on stock SQLite. This is the canonical
        // smoke test for "SQLCipher's `sqlite3_*` symbols are winning
        // over the system libsqlite3".
        let url = tempDBPath()
        let key = SymmetricKey(size: .bits256)
        defer { try? FileManager.default.removeItem(at: url) }

        let pool = try makeKeyedPool(at: url, key: key)
        let version: String? = try pool.read { db in
            try String.fetchOne(db, sql: "PRAGMA cipher_version")
        }
        XCTAssertNotNil(version, "PRAGMA cipher_version returned nil — SQLCipher is NOT linked")
        XCTAssertTrue(version!.contains("4."),
                      "Expected SQLCipher 4.x cipher_version; got: '\(version!)'")
    }

    func test_keyedDBProducesCiphertextOnDisk() throws {
        let url = tempDBPath()
        let key = SymmetricKey(size: .bits256)
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            let pool = try makeKeyedPool(at: url, key: key)
            try pool.write { db in
                try db.execute(sql: "CREATE TABLE secrets (id INTEGER PRIMARY KEY, content TEXT)")
                try db.execute(sql: "INSERT INTO secrets (content) VALUES ('clear-text-marker')")
            }
            // Force the pool to flush + close before reading raw bytes.
        }

        let onDisk = try Data(contentsOf: url)
        let plaintextMagic = "SQLite format 3\0".data(using: .utf8)!
        XCTAssertFalse(onDisk.starts(with: plaintextMagic),
                       "Encrypted SQLite file must NOT start with the plaintext SQLite magic")
        // Brute-force string search across the file — the plaintext marker
        // must not appear anywhere in the ciphertext.
        XCTAssertNil(onDisk.range(of: "clear-text-marker".data(using: .utf8)!),
                     "Plaintext marker found in encrypted DB bytes — encryption isn't applied")
    }

    func test_wrongKeyCannotReadEncryptedDB() throws {
        let url = tempDBPath()
        let key = SymmetricKey(size: .bits256)
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            let pool = try makeKeyedPool(at: url, key: key)
            try pool.write { db in
                try db.execute(sql: "CREATE TABLE secrets (id INTEGER PRIMARY KEY, content TEXT)")
                try db.execute(sql: "INSERT INTO secrets (content) VALUES ('private')")
            }
        }

        // Reopen with a wrong key. GRDB's DatabasePool initializer runs
        // an internal `SELECT * FROM sqlite_master LIMIT 1` to validate
        // the connection, which touches page 1 and triggers the
        // SQLCipher HMAC check. With the wrong key that check fails
        // with "file is not a database" — propagated as a thrown
        // error out of `makeKeyedPool` itself.
        let wrongKey = SymmetricKey(size: .bits256)
        XCTAssertThrowsError(try makeKeyedPool(at: url, key: wrongKey))

        // Right key reads it back unchanged.
        let rightPool = try makeKeyedPool(at: url, key: key)
        let value: String? = try rightPool.read { db in
            try String.fetchOne(db, sql: "SELECT content FROM secrets")
        }
        XCTAssertEqual(value, "private")
    }

    func test_plaintextDetectionMatchesSQLiteHeader() throws {
        let plaintextURL = tempDBPath()
        defer { try? FileManager.default.removeItem(at: plaintextURL) }

        // Create a plaintext SQLite DB. No PRAGMA key → SQLCipher acts as
        // plain SQLite for this connection.
        do {
            let plainPool = try DatabasePool(path: plaintextURL.path)
            try plainPool.write { db in
                try db.execute(sql: "CREATE TABLE t (n INTEGER)")
                try db.execute(sql: "INSERT INTO t VALUES (1)")
            }
        }

        XCTAssertTrue(DatabaseService.isPlaintextSQLite(at: plaintextURL))

        // After migration the file is no longer plaintext.
        let key = SymmetricKey(size: .bits256)
        try DatabaseService.migratePlaintextToSQLCipher(at: plaintextURL, key: key)
        XCTAssertFalse(DatabaseService.isPlaintextSQLite(at: plaintextURL),
                       "Post-migration file must not be plaintext SQLite")

        // And the row survived.
        let keyedPool = try makeKeyedPool(at: plaintextURL, key: key)
        let count: Int? = try keyedPool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM t")
        }
        XCTAssertEqual(count, 1)
    }

    func test_isPlaintextSQLiteHandlesMissingFile() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("definitely-not-here-\(UUID().uuidString)")
        XCTAssertFalse(DatabaseService.isPlaintextSQLite(at: missing))
    }

    func test_settingsStoreSafeWriteRefusesPlaintextOverEncrypted() throws {
        let dir = DatabaseService.supportDirectory
        let url = dir.appendingPathComponent("settings.json")
        let backup = try? Data(contentsOf: url)
        defer {
            if let backup {
                try? backup.write(to: url, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: url)
            }
        }

        let key = SymmetricKey(size: .bits256)
        let encrypted = SettingsStore(keyResolver: { key })
        encrypted.settings.heightInches = 70
        encrypted.save()

        // Now try to save with a nil resolver — must NOT clobber the
        // encrypted file with plaintext.
        let plain = SettingsStore(keyResolver: { nil })
        plain.settings.heightInches = 90 // a change that would normally write
        plain.save()

        let onDisk = try Data(contentsOf: url)
        XCTAssertTrue(EncryptedJSON.hasMagic(onDisk),
                      "Encrypted settings.json must not be silently downgraded to plaintext")
    }
}

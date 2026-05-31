import XCTest
import CryptoKit
import GRDB
@testable import PurpleDiary

/// Exercises the real SQLCipher path: a keyed `DatabasePool` (built via
/// `DatabaseService.makeConfiguration()`) must write ciphertext on disk, refuse
/// a wrong key, and the plaintext→SQLCipher migration must preserve rows.
@MainActor
final class AtRestEncryptionTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("pd-atrest-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        // CRITICAL: never leave a global key resolver set — it would change
        // DatabaseService behaviour for every other test.
        DatabaseService.keyResolver = nil
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeRow(_ db: Database, body: String) throws {
        try db.execute(sql: "CREATE TABLE IF NOT EXISTS t (id INTEGER PRIMARY KEY, body TEXT)")
        try db.execute(sql: "INSERT INTO t (body) VALUES (?)", arguments: [body])
    }

    func testKeyedDatabaseWritesCiphertextOnDisk() throws {
        let key = SymmetricKey(size: .bits256)
        DatabaseService.keyResolver = { key }
        let dbURL = tempDir.appendingPathComponent("enc.sqlite")
        do {
            let pool = try DatabasePool(path: dbURL.path, configuration: DatabaseService.makeConfiguration())
            try pool.write { try makeRow($0, body: "top secret diary line") }
            _ = pool
        }
        // The on-disk file must NOT be plaintext SQLite, and its bytes must not
        // contain our cleartext.
        XCTAssertFalse(DatabaseService.isPlaintextSQLite(at: dbURL),
                       "an encrypted DB must not carry the plaintext SQLite header")
        let raw = try Data(contentsOf: dbURL)
        XCTAssertFalse(raw.range(of: Data("top secret diary line".utf8)) != nil,
                       "plaintext content must not appear in the encrypted file")
    }

    func testWrongKeyCannotRead() throws {
        let key = SymmetricKey(size: .bits256)
        let dbURL = tempDir.appendingPathComponent("enc.sqlite")
        DatabaseService.keyResolver = { key }
        do {
            let pool = try DatabasePool(path: dbURL.path, configuration: DatabaseService.makeConfiguration())
            try pool.write { try makeRow($0, body: "hello") }
            _ = pool
        }
        // Reopen with a different key — the first read must fail.
        let wrong = SymmetricKey(size: .bits256)
        DatabaseService.keyResolver = { wrong }
        XCTAssertThrowsError(
            try {
                let pool = try DatabasePool(path: dbURL.path, configuration: DatabaseService.makeConfiguration())
                _ = try pool.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM t") }
            }(),
            "a wrong key must not be able to read the encrypted database"
        )
    }

    func testPlaintextMigrationPreservesRows() throws {
        let dbURL = tempDir.appendingPathComponent("plain.sqlite")
        // 1. Write a plaintext DB (no key).
        DatabaseService.keyResolver = nil
        do {
            let q = try DatabaseQueue(path: dbURL.path)
            try q.write { db in
                try makeRow(db, body: "row one")
                try db.execute(sql: "INSERT INTO t (body) VALUES (?)", arguments: ["row two"])
            }
            _ = q
        }
        XCTAssertTrue(DatabaseService.isPlaintextSQLite(at: dbURL))

        // 2. Migrate it to SQLCipher with a fresh key.
        let key = SymmetricKey(size: .bits256)
        try DatabaseService.migratePlaintextToSQLCipher(at: dbURL, key: key)
        XCTAssertFalse(DatabaseService.isPlaintextSQLite(at: dbURL), "file should be encrypted after migration")

        // 3. Reopen keyed and confirm both rows survived.
        DatabaseService.keyResolver = { key }
        let pool = try DatabasePool(path: dbURL.path, configuration: DatabaseService.makeConfiguration())
        let count = try pool.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM t") }
        XCTAssertEqual(count, 2, "all rows must survive the plaintext→SQLCipher migration")
    }
}

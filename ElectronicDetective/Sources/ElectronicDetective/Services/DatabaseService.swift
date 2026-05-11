import Foundation
import GRDB

/// SQLite-backed persistence for ElectronicDetective. Two tables:
///
///   • `current_session` — a single row (id = 1) carrying the in-flight
///     `GameSession` as JSON. Replaced on every mutation; cleared by starting
///     a new game.
///   • `session_history` — append-only record of every game that reached a
///     terminal outcome (`solved` / `allWrong` / `abandoned`).
///
/// The whole `GameSession` is `Codable` so we get away with a single JSON
/// column per row — no per-field schema means we don't have to migrate the
/// DB every time a model changes.
@MainActor
final class DatabaseService {

    static let shared = DatabaseService()

    /// `~/Library/Application Support/ElectronicDetective/` — created on
    /// demand. Public so `BackupService` knows what to zip.
    static let supportDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = appSupport.appendingPathComponent("ElectronicDetective", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    let pool: DatabasePool

    /// Production initializer — opens the canonical DB at the support dir.
    private convenience init() {
        let url = DatabaseService.supportDirectory.appendingPathComponent("database.sqlite")
        try! self.init(path: url.path)
    }

    /// Test seam — open an arbitrary DB path. Used by `DatabaseServiceTests`.
    init(path: String) throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        pool = try DatabasePool(path: path, configuration: config)
        try Self.migrator.migrate(pool)
    }

    // MARK: - Migrations

    /// Append-only. Each migration runs once; never edit a published one —
    /// add a new one.
    private static let migrator: DatabaseMigrator = {
        var m = DatabaseMigrator()
        m.registerMigration("v1_session_tables") { db in
            try db.execute(sql: """
                CREATE TABLE current_session (
                    id           INTEGER PRIMARY KEY CHECK (id = 1),
                    session_json TEXT NOT NULL,
                    updated_at   TEXT NOT NULL
                );
                """)
            try db.execute(sql: """
                CREATE TABLE session_history (
                    id            INTEGER PRIMARY KEY AUTOINCREMENT,
                    started_at    TEXT    NOT NULL,
                    finished_at   TEXT    NOT NULL,
                    difficulty    INTEGER NOT NULL,
                    player_count  INTEGER NOT NULL,
                    outcome       TEXT    NOT NULL,
                    murderer_id   INTEGER NOT NULL,
                    session_json  TEXT    NOT NULL
                );
                """)
            try db.execute(sql: "CREATE INDEX history_finished_idx ON session_history(finished_at DESC);")
        }
        return m
    }()

    // MARK: - Current session

    func saveCurrentSession(_ session: GameSession?) throws {
        try pool.write { db in
            try db.execute(sql: "DELETE FROM current_session")
            guard let s = session else { return }
            let data = try Self.encoder.encode(s)
            let json = String(data: data, encoding: .utf8) ?? ""
            try db.execute(
                sql: "INSERT INTO current_session (id, session_json, updated_at) VALUES (1, ?, ?)",
                arguments: [json, Self.isoNow()]
            )
        }
    }

    func loadCurrentSession() throws -> GameSession? {
        try pool.read { db in
            guard let json = try String.fetchOne(
                db, sql: "SELECT session_json FROM current_session WHERE id = 1"
            ) else { return nil }
            guard let data = json.data(using: .utf8) else { return nil }
            return try Self.decoder.decode(GameSession.self, from: data)
        }
    }

    // MARK: - History

    struct HistoryEntry: Identifiable, Hashable, Sendable {
        let id: Int64
        let startedAt: Date
        let finishedAt: Date
        let difficulty: Difficulty
        let playerCount: Int
        let outcome: GameSession.Outcome
        let murdererId: Int
    }

    /// Idempotent: appending a session whose start+finish already exist in
    /// the history is a no-op. Lets `AppState.accuse` call this on every
    /// outcome transition without worrying about double-writes.
    func appendHistory(_ session: GameSession) throws {
        guard let finished = session.finishedAt,
              session.outcome != .inProgress else { return }
        try pool.write { db in
            let exists = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM session_history WHERE started_at = ? AND finished_at = ?",
                arguments: [Self.iso(session.startedAt), Self.iso(finished)]
            ) ?? 0
            if exists > 0 { return }
            let data = try Self.encoder.encode(session)
            let json = String(data: data, encoding: .utf8) ?? ""
            try db.execute(sql: """
                INSERT INTO session_history (started_at, finished_at, difficulty, player_count, outcome, murderer_id, session_json)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    Self.iso(session.startedAt),
                    Self.iso(finished),
                    session.difficulty.rawValue,
                    session.players.count,
                    session.outcome.rawValue,
                    session.gameCase.murdererId,
                    json
                ])
        }
    }

    func fetchHistory(limit: Int = 200) throws -> [HistoryEntry] {
        try pool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT id, started_at, finished_at, difficulty, player_count, outcome, murderer_id
                FROM session_history
                ORDER BY finished_at DESC
                LIMIT ?
                """, arguments: [limit])
            return rows.compactMap { row -> HistoryEntry? in
                guard let id = row["id"] as Int64?,
                      let startedRaw  = row["started_at"]  as String?,
                      let finishedRaw = row["finished_at"] as String?,
                      let diffRaw     = row["difficulty"]  as Int?,
                      let playerCount = row["player_count"] as Int?,
                      let outcomeRaw  = row["outcome"]     as String?,
                      let murdererId  = row["murderer_id"] as Int?,
                      let started  = Self.parseISO(startedRaw),
                      let finished = Self.parseISO(finishedRaw),
                      let diff     = Difficulty(rawValue: diffRaw),
                      let outcome  = GameSession.Outcome(rawValue: outcomeRaw)
                else { return nil }
                return HistoryEntry(
                    id: id, startedAt: started, finishedAt: finished,
                    difficulty: diff, playerCount: playerCount,
                    outcome: outcome, murdererId: murdererId
                )
            }
        }
    }

    func clearHistory() throws {
        try pool.write { db in try db.execute(sql: "DELETE FROM session_history") }
    }

    // MARK: - Codable / date helpers

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    private static func iso(_ d: Date) -> String { isoFormatter.string(from: d) }
    private static func isoNow() -> String       { iso(Date()) }
    private static func parseISO(_ s: String) -> Date? { isoFormatter.date(from: s) }
}

import Foundation
import GRDB

@MainActor
enum IDGeneratorService {

    /// Generates the next clip ID in the form `YYYY-MM-DD-#####`, where the
    /// date is derived from `contentDate` if provided, else today. The 5-digit
    /// suffix expands automatically if a single day overflows past 99999.
    /// `id_sequences.date_key` stays in compact "yyyyMMdd" form so it doubles
    /// as a daily counter regardless of display formatting changes.
    static func next(forContentDate contentDate: Date?) throws -> String {
        let date = contentDate ?? Date()
        let compactKey = dateKey(forDate: date)
        let prettyDate = prettyDateKey(forDate: date)
        let pool = DatabaseService.shared.dbPool

        let seq: Int = try pool.write { db in
            let current = try Int.fetchOne(db,
                sql: "SELECT last_seq FROM id_sequences WHERE date_key = ?",
                arguments: [compactKey]) ?? 0
            let next = current + 1
            try db.execute(sql: """
                INSERT INTO id_sequences (date_key, last_seq) VALUES (?, ?)
                ON CONFLICT(date_key) DO UPDATE SET last_seq = excluded.last_seq
                """, arguments: [compactKey, next])
            return next
        }

        if seq < 100000 {
            return "\(prettyDate)-\(String(format: "%05d", seq))"
        }
        return "\(prettyDate)-\(seq)"
    }

    /// Compact "yyyyMMdd" — used as the storage key for daily sequence counters.
    static func dateKey(forDate date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt.string(from: date)
    }

    /// Display-formatted "yyyy-MM-dd".
    static func prettyDateKey(forDate date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt.string(from: date)
    }
}

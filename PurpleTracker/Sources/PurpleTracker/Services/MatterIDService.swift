import Foundation
import GRDB

/// Allocates the next Matter ID for a given calendar date in the form
/// `YYYY-MM-DD-#####`. Implementation: a `matter_id_counter` row per date
/// holding `next_seq`. `allocate(on:)` runs in a write transaction so two
/// concurrent inserts never see the same value, and the entire (allocate +
/// insert matter) flow is performed inside a single GRDB write so the counter
/// can never be advanced for a Matter that fails to insert.
enum MatterIDService {

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Format an integer sequence into the canonical 5-zero-padded suffix.
    /// Sequences ≥ 100,000 in a single day still render correctly (no clamp);
    /// the format is preserved as much padding as needed.
    static func format(date: Date, sequence: Int) -> String {
        let day = dateFormatter.string(from: date)
        return String(format: "%@-%05d", day, sequence)
    }

    /// Allocate the next sequence for `date` and execute `insert` in the same
    /// write transaction with the resulting ID. The closure receives a
    /// `Database` handle so it can perform additional inserts (e.g., a
    /// matching cadence row) atomically. Returns the assigned Matter ID.
    @discardableResult
    static func allocateAndInsert(
        on date: Date = Date(),
        in pool: DatabaseWriter,
        insert: (Database, _ matterId: String) throws -> Void
    ) throws -> String {
        try pool.write { db in
            let day = dateFormatter.string(from: date)
            let seq: Int = try Int.fetchOne(
                db,
                sql: """
                INSERT INTO matter_id_counter (date, next_seq) VALUES (?, 2)
                ON CONFLICT(date) DO UPDATE SET next_seq = next_seq + 1
                RETURNING next_seq - 1
                """,
                arguments: [day]
            ) ?? 1
            let id = String(format: "%@-%05d", day, seq)
            try insert(db, id)
            return id
        }
    }
}

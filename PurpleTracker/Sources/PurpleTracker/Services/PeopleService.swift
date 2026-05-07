import Foundation
import GRDB

/// Imports the ADP IMP UserFeed CSV (sample headers shipped daily into
/// `~/Downloads/ADP_IMP_UserFeed_YYYY-MM-DD.csv`) and exposes lookup helpers
/// used by the Requestor picker on a Matter.
@MainActor
enum PeopleService {

    struct ImportResult {
        var inserted: Int
        var updated: Int
        var skipped: Int
        var totalRows: Int
        var sourceFilename: String
    }

    // MARK: - Import

    /// Parse + upsert in one transaction. Associate ID is the stable PK; rows
    /// without one are skipped (the ADP feed has empty rows for FEAD-only
    /// records). Names/titles/etc. are overwritten on every import so a
    /// re-import always reflects the latest snapshot.
    static func importCSV(at url: URL) throws -> ImportResult {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
            throw NSError(domain: "PeopleService", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "CSV is not UTF-8 / Latin-1."])
        }
        let rows = parseCSV(text)
        guard let header = rows.first else {
            throw NSError(domain: "PeopleService", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Empty CSV."])
        }
        let idx = HeaderIndex(header: header)
        guard idx.associateId >= 0 else {
            throw NSError(domain: "PeopleService", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Missing 'Associate ID' column."])
        }

        var inserted = 0
        var updated = 0
        var skipped = 0
        let now = Date()
        try DatabaseService.shared.dbPool.write { db in
            for row in rows.dropFirst() {
                let associateId = idx.value(.associateId, in: row).trimmingCharacters(in: .whitespaces)
                if associateId.isEmpty { skipped += 1; continue }

                let p = Person(
                    id: associateId,
                    firstName: idx.value(.firstName, in: row),
                    lastName: idx.value(.lastName, in: row),
                    preferredName: idx.value(.preferredName, in: row),
                    jobTitle: idx.value(.jobTitle, in: row),
                    workEmail: idx.value(.workEmail, in: row),
                    department: idx.value(.department, in: row),
                    location: idx.value(.location, in: row),
                    positionStatus: idx.value(.positionStatus, in: row),
                    managerAssociateId: idx.value(.managerAssociateId, in: row),
                    updatedAt: now
                )

                let exists = try Bool.fetchOne(
                    db,
                    sql: "SELECT EXISTS(SELECT 1 FROM person WHERE id = ?)",
                    arguments: [associateId]
                ) ?? false

                var saved = p
                try saved.save(db)
                if exists { updated += 1 } else { inserted += 1 }
            }
        }
        return ImportResult(
            inserted: inserted,
            updated: updated,
            skipped: skipped,
            totalRows: rows.count - 1,
            sourceFilename: url.lastPathComponent
        )
    }

    // MARK: - Lookups

    /// Locate the newest `ADP_IMP_UserFeed_YYYY-MM-DD.csv` in the user's
    /// `~/Downloads/`. Filenames sort lexicographically as dates, so the last
    /// one wins. Returns `nil` if nothing matches.
    static func latestADPFileInDownloads() -> URL? {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads")
        let candidates = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        let matches = candidates
            .filter { $0.hasPrefix("ADP_IMP_UserFeed_") && $0.hasSuffix(".csv") }
            .sorted()
        guard let latest = matches.last else { return nil }
        return dir.appendingPathComponent(latest)
    }

    static func fetchAll(activeOnly: Bool = false) throws -> [Person] {
        try DatabaseService.shared.dbPool.read { db in
            var rows = try Person
                .order(Column("last_name").asc, Column("first_name").asc)
                .fetchAll(db)
            if activeOnly { rows = rows.filter { $0.isActive } }
            return rows
        }
    }

    static func fetch(id: String) throws -> Person? {
        guard !id.isEmpty else { return nil }
        return try DatabaseService.shared.dbPool.read { db in
            try Person.fetchOne(db, key: id)
        }
    }

    /// Latest `updated_at` seen in the table — used to render "Last imported"
    /// in Settings.
    static func lastImportDate() throws -> Date? {
        try DatabaseService.shared.dbPool.read { db in
            try Date.fetchOne(db, sql: "SELECT MAX(updated_at) FROM person")
        }
    }

    // MARK: - CSV parser

    /// Header → column index mapper that's tolerant of column-order changes
    /// in the ADP feed.
    private struct HeaderIndex {
        enum Field {
            case associateId, firstName, lastName, preferredName, jobTitle
            case workEmail, department, location, positionStatus, managerAssociateId
        }
        var associateId = -1, firstName = -1, lastName = -1, preferredName = -1
        var jobTitle = -1, workEmail = -1, department = -1, location = -1
        var positionStatus = -1, managerAssociateId = -1

        init(header: [String]) {
            for (i, raw) in header.enumerated() {
                let h = raw.trimmingCharacters(in: .whitespaces).lowercased()
                switch h {
                case "associate id":                          associateId = i
                case "first name":                            firstName = i
                case "last name":                             lastName = i
                case "preferred name":                        preferredName = i
                case "job title description":                 jobTitle = i
                case "work contact: work email":              workEmail = i
                case "home department description":           department = i
                case "location description":                  location = i
                case "position status":                       positionStatus = i
                case "reports to associate id":               managerAssociateId = i
                default: break
                }
            }
        }

        func value(_ field: Field, in row: [String]) -> String {
            let i: Int
            switch field {
            case .associateId: i = associateId
            case .firstName: i = firstName
            case .lastName: i = lastName
            case .preferredName: i = preferredName
            case .jobTitle: i = jobTitle
            case .workEmail: i = workEmail
            case .department: i = department
            case .location: i = location
            case .positionStatus: i = positionStatus
            case .managerAssociateId: i = managerAssociateId
            }
            guard i >= 0, i < row.count else { return "" }
            return row[i].trimmingCharacters(in: .whitespaces)
        }
    }

    /// RFC-4180-ish CSV parser. Handles `"`-quoted fields with embedded
    /// commas, newlines, and `""` escapes.
    ///
    /// Iterates over Unicode scalars (not `Character`) because Swift collapses
    /// `\r\n` into a single grapheme cluster — a `Character` equal to neither
    /// `"\r"` nor `"\n"` — which would silently break Windows line endings.
    /// Also strips a leading BOM and tolerates lone `\r` (classic Mac) endings.
    static func parseCSV(_ raw: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false

        let scalars = Array(raw.unicodeScalars)
        var i = 0
        // Strip UTF-8 BOM if present
        if !scalars.isEmpty, scalars[0] == "\u{FEFF}" { i = 1 }

        func endField()   { row.append(field); field = "" }
        func endRow()     { endField(); rows.append(row); row = [] }

        while i < scalars.count {
            let c = scalars[i]
            if inQuotes {
                if c == "\"" {
                    let next = i + 1
                    if next < scalars.count, scalars[next] == "\"" {
                        field.append("\""); i = next + 1; continue
                    }
                    inQuotes = false
                } else {
                    field.unicodeScalars.append(c)
                }
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",":  endField()
                case "\r":
                    let next = i + 1
                    if next < scalars.count, scalars[next] == "\n" {
                        endRow(); i = next + 1; continue
                    }
                    endRow()
                case "\n": endRow()
                default:   field.unicodeScalars.append(c)
                }
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows.filter { !($0.count == 1 && $0[0].isEmpty) }
    }
}

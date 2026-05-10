import Foundation

/// Phase 5 — import WeightTracker's CSV export into PurpleLife `Weight`
/// records. Per `PLAN.md` § Open questions, the default for the
/// WeightTracker / PurpleLife coexistence question is (b) coexist + CSV
/// import. This service is that import path.
///
/// WeightTracker CSV shape:
///   Date,Weight (lb),Notes
///   "2026-05-10 12:34:56 +0000",182.50,"Felt strong."
///
/// Header may also be "Weight (kg)"; the importer respects that and
/// converts to pounds before storing (the Weight type's `pounds` field
/// is unit-fixed, matching the seed schema).
@MainActor
enum WeightCSVImporter {

    struct Report {
        var imported: Int = 0
        var skipped: Int = 0
        var errors: [String] = []
    }

    enum ImportError: Error, LocalizedError {
        case noFile
        case unreadable(String)
        case emptyFile

        var errorDescription: String? {
            switch self {
            case .noFile:           return "No file selected"
            case .unreadable(let m): return "Couldn't read file: \(m)"
            case .emptyFile:        return "File is empty"
            }
        }
    }

    /// Imports rows from a CSV file. Returns a `Report` summarizing
    /// what landed. Each row becomes a new Weight record — duplicates
    /// aren't detected; the user can clean up in PurpleLife if needed.
    static func importCSV(from url: URL) throws -> Report {
        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw ImportError.unreadable(error.localizedDescription)
        }
        guard !content.isEmpty else { throw ImportError.emptyFile }

        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard let header = lines.first else { throw ImportError.emptyFile }
        let dataRows = Array(lines.dropFirst())

        let unitToPoundsFactor: Double = header.lowercased().contains("(kg") ? 2.2046226218 : 1.0

        var report = Report()
        for (idx, raw) in dataRows.enumerated() {
            let cells = parseCSVRow(raw)
            guard cells.count >= 2 else {
                report.skipped += 1
                report.errors.append("Row \(idx + 2): \(cells.count) column\(cells.count == 1 ? "" : "s"), need at least 2")
                continue
            }
            let dateField = cells[0]
            let weightField = cells[1]
            let notesField = cells.count >= 3 ? cells[2] : ""

            guard let date = parseDate(dateField) else {
                report.skipped += 1
                report.errors.append("Row \(idx + 2): unparseable date \"\(dateField)\"")
                continue
            }
            guard let raw = Double(weightField.trimmingCharacters(in: .whitespaces)) else {
                report.skipped += 1
                report.errors.append("Row \(idx + 2): unparseable weight \"\(weightField)\"")
                continue
            }
            let pounds = raw * unitToPoundsFactor

            do {
                _ = try ObjectEngine.create(
                    typeId: "Weight",
                    fields: [
                        "date": isoDateOnly(date),
                        "pounds": pounds,
                        "notes": notesField,
                        "source": "Imported"
                    ]
                )
                report.imported += 1
            } catch {
                report.skipped += 1
                report.errors.append("Row \(idx + 2): \(error.localizedDescription)")
            }
        }
        return report
    }

    // MARK: - Parsers

    /// Minimal CSV row parser that handles double-quoted fields (with
    /// `""` escaping) — enough for WeightTracker's output without
    /// pulling a parsing library in.
    static func parseCSVRow(_ row: String) -> [String] {
        var cells: [String] = []
        var current = ""
        var inQuotes = false
        var i = row.startIndex
        while i < row.endIndex {
            let c = row[i]
            if inQuotes {
                if c == "\"" {
                    let next = row.index(after: i)
                    if next < row.endIndex, row[next] == "\"" {
                        current.append("\"")
                        i = row.index(after: next)
                        continue
                    } else {
                        inQuotes = false
                    }
                } else {
                    current.append(c)
                }
            } else {
                if c == "," {
                    cells.append(current)
                    current = ""
                } else if c == "\"" {
                    inQuotes = true
                } else {
                    current.append(c)
                }
            }
            i = row.index(after: i)
        }
        cells.append(current)
        return cells
    }

    /// Tries the common Date-string shapes WeightTracker can emit.
    static func parseDate(_ s: String) -> Date? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: trimmed) { return d }
        // `\(Date())` default description: "2026-05-10 12:34:56 +0000"
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        for fmt in [
            "yyyy-MM-dd HH:mm:ss Z",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd",
            "MM/dd/yyyy",
            "M/d/yyyy"
        ] {
            df.dateFormat = fmt
            if let d = df.date(from: trimmed) { return d }
        }
        return nil
    }

    private static func isoDateOnly(_ date: Date) -> String {
        // PurpleLife Weight.date is a `.date` field — store as ISO-8601
        // datetime at midnight UTC so it round-trips through the
        // detail editor's DatePicker.
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd'T'00:00:00Z"
        df.timeZone = TimeZone(secondsFromGMT: 0)
        return df.string(from: date)
    }
}

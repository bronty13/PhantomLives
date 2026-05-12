import Foundation
import MasterClipperCore

/// Parses a Clips4Sale on-demand storefront export (XLSX or pipe-delimited
/// CSV — C4S labels the file `.csv` but uses `|` as the field separator)
/// into `C4SHistoricalRecord` rows. The caller decides which `store` the
/// rows belong to and then hands them to
/// `DatabaseService.replaceC4SHistorical(store:with:)`.
enum C4SHistoricalImportService {

    /// What the export looks like — column index → field. Both the XLSX
    /// and the pipe-CSV format share this exact 14-column header.
    static let expectedHeader: [String] = [
        "Clip Status", "Clip ID", "Clip Tracking Tag", "Clip Title",
        "Clip Description", "Categories", "Keywords",
        "Clip Filename", "Clip Thumbnail Filename", "Clip Preview Filename",
        "Performers", "Price",
        "Sales # (total sales even after refunds)",
        // The income column header includes a curly apostrophe in the
        // C4S export; we don't match on the literal value, just on
        // column position, so a header mismatch on row 1 is tolerated.
        "Income for last 6 months $ (creator's income excluding C4S %)"
    ]

    enum ImportError: Error, LocalizedError {
        case unsupportedExtension(String)
        case emptyFile
        case noRows

        var errorDescription: String? {
            switch self {
            case .unsupportedExtension(let ext):
                return "Unsupported file type '.\(ext)'. Use a Clips4Sale export (.xlsx or .csv)."
            case .emptyFile: return "The selected file is empty."
            case .noRows:    return "No data rows found in the file (only a header row?)."
            }
        }
    }

    /// Parse `url` into rows. `store` is stamped onto every row but the
    /// caller is responsible for the actual DB replace.
    static func parse(url: URL, store: String) throws -> [C4SHistoricalRecord] {
        let ext = url.pathExtension.lowercased()
        let importedAt = isoNow()

        let rows: [[String]]
        switch ext {
        case "xlsx":
            rows = try parseXLSX(url: url)
        case "csv", "txt", "tsv":
            rows = try parseDelimited(url: url)
        default:
            // Unknown / missing extension — sniff the file. XLSX files
            // are zip archives and start with the `PK\x03\x04` magic.
            // Anything else we treat as the C4S pipe-delimited format.
            if isZip(url: url) {
                rows = try parseXLSX(url: url)
            } else {
                rows = try parseDelimited(url: url)
            }
        }

        guard !rows.isEmpty else { throw ImportError.emptyFile }

        // Drop the header row if it matches the first expected column —
        // C4S always emits one. If somehow the header is missing we still
        // import every row; the cost of a bad header row is one
        // garbage record that the user can spot in the grid.
        var dataRows = rows
        if let firstCell = dataRows.first?.first,
           firstCell.caseInsensitiveCompare("Clip Status") == .orderedSame {
            dataRows.removeFirst()
        }

        guard !dataRows.isEmpty else { throw ImportError.noRows }

        return dataRows.compactMap { row -> C4SHistoricalRecord? in
            guard !row.allSatisfy(\.isEmpty) else { return nil }
            return C4SHistoricalRecord(
                id: nil,
                store: store,
                clipStatus:        cell(row, 0),
                clipId:            cell(row, 1),
                trackingTag:       cell(row, 2),
                title:             cell(row, 3),
                descriptionText:   cell(row, 4),
                categories:        cell(row, 5),
                keywords:          cell(row, 6),
                clipFilename:      cell(row, 7),
                thumbnailFilename: cell(row, 8),
                previewFilename:   cell(row, 9),
                performers:        cell(row, 10),
                priceCents:        moneyToCents(cell(row, 11)),
                salesCount:        intOrNil(cell(row, 12)),
                incomeCents:       moneyToCents(cell(row, 13)),
                importedAt:        importedAt
            )
        }
    }

    // MARK: - XLSX

    private static func parseXLSX(url: URL) throws -> [[String]] {
        let sheets = try XLSXReader.read(url: url)
        // C4S puts everything in the first sheet (the file we ship with
        // happens to call it "Sheet1"). If the file has multiple sheets
        // we pick the one with the most rows — defensive but
        // overwhelmingly the right thing.
        guard let sheet = sheets.max(by: { $0.rows.count < $1.rows.count }) else {
            throw ImportError.emptyFile
        }
        return sheet.rows
    }

    // MARK: - Pipe-delimited CSV (C4S misnames it .csv)

    /// Hand-rolled parser. C4S export rules we care about:
    ///   • field separator = `|`
    ///   • quote char = `"` ; doubled `""` inside a quoted field is a literal `"`
    ///   • quoted fields can span newlines (descriptions often do)
    ///   • bare newlines outside quotes terminate a row
    private static func parseDelimited(url: URL) throws -> [[String]] {
        let raw = try String(contentsOf: url, encoding: .utf8)
        guard !raw.isEmpty else { throw ImportError.emptyFile }

        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = raw.unicodeScalars.makeIterator()

        while let scalar = iterator.next() {
            let ch = Character(scalar)
            if inQuotes {
                if ch == "\"" {
                    // Peek next: a doubled quote is an escape.
                    var copy = iterator
                    if let nxt = copy.next(), Character(nxt) == "\"" {
                        field.append("\"")
                        iterator = copy
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(ch)
                }
            } else {
                switch ch {
                case "\"":
                    inQuotes = true
                case "|":
                    row.append(field); field = ""
                case "\r":
                    // Swallow — handled by the \n that usually follows on
                    // mixed-line-ending files. If it arrives alone, the
                    // \n branch below will still terminate the row when
                    // we eventually hit one, or at EOF.
                    continue
                case "\n":
                    row.append(field); field = ""
                    if !(row.count == 1 && row[0].isEmpty) {
                        rows.append(row)
                    }
                    row = []
                default:
                    field.append(ch)
                }
            }
        }
        // Flush trailing field/row if file didn't end with a newline.
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            if !(row.count == 1 && row[0].isEmpty) {
                rows.append(row)
            }
        }
        return rows
    }

    // MARK: - Cell helpers

    private static func cell(_ row: [String], _ idx: Int) -> String {
        guard idx < row.count else { return "" }
        return row[idx].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "3.99" → 399, "" → nil. Tolerates "$3.99" and "1,200.00".
    private static func moneyToCents(_ raw: String) -> Int? {
        let cleaned = raw
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return nil }
        guard let d = Double(cleaned) else { return nil }
        return Int((d * 100).rounded())
    }

    private static func intOrNil(_ raw: String) -> Int? {
        let cleaned = raw
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return nil }
        return Int(cleaned)
    }

    /// True if the file's first 4 bytes match the ZIP magic `PK\x03\x04`.
    /// XLSX is a zip archive; everything else we accept (pipe CSV, plain
    /// text) starts with printable ASCII.
    private static func isZip(url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 4)) ?? Data()
        return head.count == 4 && head[0] == 0x50 && head[1] == 0x4B
            && (head[2] == 0x03 || head[2] == 0x05 || head[2] == 0x07)
    }

    /// Local ISO-now without depending on `DatabaseService.isoNow()`,
    /// which is `@MainActor` and can't be called from this nonisolated
    /// parser. Mirrors the project-wide format (`yyyy-MM-dd'T'HH:mm:ss`).
    private static func isoNow() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt.string(from: Date())
    }
}

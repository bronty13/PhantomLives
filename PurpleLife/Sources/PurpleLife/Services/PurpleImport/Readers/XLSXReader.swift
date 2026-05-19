import Foundation
import CoreXLSX

/// Excel (.xlsx) reader for Purple Import. Backed by CoreXLSX 0.14.x —
/// read-only XLSX parser, MIT-licensed.
///
/// Shape: always tabular. Each row in the chosen sheet (within an
/// optional column range) becomes a `SourceRow`; columns are addressed
/// by header-row values when `headerRow > 0`, else by A/B/C-style
/// column references.
///
/// Options:
///   • `sheetName` (String) — picks a worksheet by name. Default is
///     the first sheet in the workbook.
///   • `headerRow` (Int, default 1) — 1-based row that carries column
///     headers. Set to 0 to skip header parsing and use `col_A`,
///     `col_B`, … names.
///   • `firstDataRow` (Int) — 1-based row to start reading data from.
///     Defaults to `headerRow + 1` when headers are on, else 1.
///   • `startColumn` (String) — e.g. "A". Default: first non-empty.
///   • `endColumn` (String) — e.g. "F". Default: last non-empty.
final class XLSXReader: PurpleImportSourceReader {

    var format: PurpleImport.SourceFormat { .xlsx }

    private var sheetName: String?
    private var headerRow: Int = 1
    private var firstDataRow: Int?
    private var startColumn: String?
    private var endColumn: String?

    func setOptions(_ options: [String: Any]) {
        if let s = options["sheetName"] as? String, !s.isEmpty { self.sheetName = s }
        if let h = options["headerRow"] as? Int { self.headerRow = h }
        if let r = options["firstDataRow"] as? Int { self.firstDataRow = r }
        if let s = options["startColumn"] as? String, !s.isEmpty { self.startColumn = s.uppercased() }
        if let s = options["endColumn"] as? String, !s.isEmpty { self.endColumn = s.uppercased() }
    }

    // MARK: - PurpleImportSourceReader

    func probe(_ source: PurpleImport.SourceInput) async throws -> PurpleImport.SourceShape {
        let preview = try await preview(source, sampleSize: 50)
        return preview.shape
    }

    func preview(_ source: PurpleImport.SourceInput, sampleSize: Int) async throws -> PurpleImport.SourcePreview {
        let parsed = try loadWorkbook(source)
        let rows = try extractRows(parsed: parsed, maxDataRows: sampleSize)
        var kinds: [String: FieldKind] = [:]
        for col in rows.columns {
            let samples = rows.rows.compactMap { $0[col] }
            kinds[col] = FieldValueCoercer.inferKind(samples: samples)
        }
        let sourceRows: [PurpleImport.SourceRow] = rows.rows.enumerated().map { (i, dict) in
            var cells: [PurpleImport.SourceLocator: Any] = [:]
            for (k, v) in dict { cells[.column(k)] = v }
            return PurpleImport.SourceRow(cells: cells, rowIndex: i)
        }
        return PurpleImport.SourcePreview(
            shape: .tabular(columns: rows.columns, inferredKinds: kinds),
            sampleRows: sourceRows,
            totalRows: nil
        )
    }

    func read(_ source: PurpleImport.SourceInput) -> AsyncThrowingStream<PurpleImport.SourceRow, Error> {
        AsyncThrowingStream { continuation in
            do {
                let parsed = try loadWorkbook(source)
                let rows = try extractRows(parsed: parsed, maxDataRows: nil)
                for (i, dict) in rows.rows.enumerated() {
                    if Task.isCancelled { break }
                    var cells: [PurpleImport.SourceLocator: Any] = [:]
                    for (k, v) in dict { cells[.column(k)] = v }
                    continuation.yield(PurpleImport.SourceRow(cells: cells, rowIndex: i))
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    // MARK: - Workbook loading

    private struct ParsedWorkbook {
        let worksheet: Worksheet
        let sharedStrings: SharedStrings?
        /// styleIndex values whose number-format is a date / time /
        /// date-time. Populated from `Styles.cellFormats` + a lookup
        /// into `Styles.numberFormats` (and the OOXML built-in IDs).
        /// Empty when no styles are present.
        let dateStyleIndices: Set<Int>
    }

    private func loadWorkbook(_ source: PurpleImport.SourceInput) throws -> ParsedWorkbook {
        let file = try makeFile(source)
        guard let workbook = try file.parseWorkbooks().first else {
            throw XLSXReaderError.openFailed(source.label)
        }
        let pathsAndNames = try file.parseWorksheetPathsAndNames(workbook: workbook)
        // Pick the worksheet. `sheetName` wins (case-insensitive); else first.
        let pair: (name: String?, path: String)? = {
            if let want = sheetName {
                return pathsAndNames.first { $0.name?.caseInsensitiveCompare(want) == .orderedSame }
            }
            return pathsAndNames.first
        }()
        guard let chosen = pair else {
            throw XLSXReaderError.sheetNotFound(sheetName ?? "(first)")
        }
        let worksheet = try file.parseWorksheet(at: chosen.path)
        let sharedStrings = try? file.parseSharedStrings()
        let styles = try? file.parseStyles()
        let dateStyleIndices = Self.detectDateStyleIndices(in: styles)
        return ParsedWorkbook(
            worksheet: worksheet,
            sharedStrings: sharedStrings,
            dateStyleIndices: dateStyleIndices
        )
    }

    /// OOXML built-in numFmtIds whose format is a date/time. The spec
    /// reserves a small range for these; anything ≥ 164 is a custom
    /// format whose actual `formatCode` we have to inspect.
    private static let builtInDateFormatIDs: Set<Int> = [
        14, 15, 16, 17,        // m/d/yyyy, d-mmm-yy, d-mmm, mmm-yy
        18, 19, 20, 21,        // h:mm AM/PM, h:mm:ss AM/PM, h:mm, h:mm:ss
        22,                    // m/d/yyyy h:mm
        45, 46, 47             // mm:ss, [h]:mm:ss, mm:ss.0
    ]

    /// Walks `Styles.cellFormats` and returns the set of cell-format
    /// indices (the value cells refer to via `styleIndex`) whose
    /// number-format is a date / time. Two sources: built-in ID
    /// range, and custom format codes whose `formatCode` matches
    /// date-token heuristics.
    static func detectDateStyleIndices(in styles: Styles?) -> Set<Int> {
        guard let styles, let cellFormats = styles.cellFormats else { return [] }
        // Map numFmtId → formatCode for custom (≥ 164) formats. The
        // built-in IDs don't appear here; the spec implies them.
        let customCodes: [Int: String] = (styles.numberFormats?.items ?? [])
            .reduce(into: [:]) { acc, nf in acc[nf.id] = nf.formatCode }

        var indices: Set<Int> = []
        for (cellFormatIndex, fmt) in cellFormats.items.enumerated() {
            let fid = fmt.numberFormatId
            if Self.builtInDateFormatIDs.contains(fid) {
                indices.insert(cellFormatIndex)
            } else if let code = customCodes[fid], isLikelyDateFormatCode(code) {
                indices.insert(cellFormatIndex)
            }
        }
        return indices
    }

    /// Excel custom format codes use `y`/`m`/`d`/`h`/`s` tokens for
    /// date and time parts. The minimal heuristic: any of those
    /// tokens outside a literal-string segment marks it as a date.
    /// We strip quoted literals and bracketed conditionals (e.g.
    /// `[Red]`, `[$-409]`) before checking, otherwise a currency
    /// code containing `d` (USD) would false-positive.
    static func isLikelyDateFormatCode(_ code: String) -> Bool {
        // Strip "..." / '...' quoted literals.
        var s = code
        s = s.replacingOccurrences(of: "\"[^\"]*\"", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "'[^']*'", with: "", options: .regularExpression)
        // Strip [bracketed] directives.
        s = s.replacingOccurrences(of: "\\[[^\\]]*\\]", with: "", options: .regularExpression)
        let lower = s.lowercased()
        // y is unambiguous; mm/dd/hh/ss only when paired with another
        // date/time token nearby. The cheap test: just look for any
        // of the unambiguous date markers.
        if lower.contains("y") { return true }   // yyyy / yy / y
        if lower.contains("d") && lower.contains("m") { return true }  // d-m, dd-mm, m/d
        if lower.contains("h") && lower.contains(":") { return true }  // h:mm
        if lower.contains("am/pm") { return true }
        return false
    }

    private func makeFile(_ source: PurpleImport.SourceInput) throws -> XLSXFile {
        // CoreXLSX 0.14.x has two non-uniform inits:
        //   XLSXFile(filepath:) is failable, non-throwing.
        //   XLSXFile(data:)     throws, non-failable.
        // Both shapes get normalized here into one throwing path.
        switch source {
        case .url(let url):
            guard let f = XLSXFile(filepath: url.path) else {
                throw XLSXReaderError.openFailed(url.lastPathComponent)
            }
            return f
        case .data(let data, _):
            return try XLSXFile(data: data)
        }
    }

    /// Available sheet names — used by the wizard's sheet picker.
    static func sheetNames(in source: PurpleImport.SourceInput) throws -> [String] {
        let file: XLSXFile
        switch source {
        case .url(let url):
            guard let f = XLSXFile(filepath: url.path) else { return [] }
            file = f
        case .data(let d, _):
            file = try XLSXFile(data: d)
        }
        guard let workbook = try file.parseWorkbooks().first else { return [] }
        let pairs = try file.parseWorksheetPathsAndNames(workbook: workbook)
        return pairs.compactMap { $0.name }
    }

    // MARK: - Row extraction

    private struct ExtractedRows {
        let columns: [String]
        let rows: [[String: Any]]
    }

    private func extractRows(parsed: ParsedWorkbook, maxDataRows: Int?) throws -> ExtractedRows {
        let ws = parsed.worksheet
        let allRows = ws.data?.rows ?? []
        guard !allRows.isEmpty else { return ExtractedRows(columns: [], rows: []) }

        let headerRowVal = headerRow
        let firstData = firstDataRow ?? (headerRowVal > 0 ? headerRowVal + 1 : 1)

        // Pull the header row if requested.
        var headers: [String: String] = [:]  // column letters → header label
        if headerRowVal > 0,
           let hRow = allRows.first(where: { $0.reference == UInt(headerRowVal) }) {
            for cell in hRow.cells {
                let colRef = cell.reference.column.value
                // Headers are always treated as strings — even if a
                // workbook has stuck a date style on the header row,
                // we want "Weight (kg)" not "2024-01-15".
                let label = stringValue(of: cell, sharedStrings: parsed.sharedStrings, dateStyles: [])
                if !label.isEmpty { headers[colRef] = label }
            }
        }

        // Sweep data rows to figure out the column footprint.
        let dataRowsLowerBound = UInt(firstData)
        let dataRows = allRows.filter { $0.reference >= dataRowsLowerBound }

        let startIdx = startColumn.flatMap(columnLetterIndex(from:))
        let endIdx = endColumn.flatMap(columnLetterIndex(from:))

        var seenColumns: Set<String> = Set(headers.keys)
        for row in dataRows {
            for cell in row.cells {
                seenColumns.insert(cell.reference.column.value)
            }
        }
        // Apply the start/end column window AFTER aggregating. Doing
        // it inside the data-row loop alone leaves header-row entries
        // outside the window in place — surfaced by
        // testStartColumnOptionTrimsLeftColumns.
        let filteredColumns = seenColumns.filter { letter in
            let idx = columnLetterIndex(from: letter) ?? 0
            if let s = startIdx, idx < s { return false }
            if let e = endIdx, idx > e { return false }
            return true
        }
        let orderedColumns = filteredColumns.sorted {
            (columnLetterIndex(from: $0) ?? 0) < (columnLetterIndex(from: $1) ?? 0)
        }

        // Resolve column labels: header value if known, else col_<letter>.
        let columnLabels: [String] = orderedColumns.map { letter in
            headers[letter] ?? "col_\(letter)"
        }
        let labelByLetter = Dictionary(uniqueKeysWithValues: zip(orderedColumns, columnLabels))

        // Build records.
        var out: [[String: Any]] = []
        for row in dataRows {
            if let cap = maxDataRows, out.count >= cap { break }
            var rec: [String: Any] = [:]
            for cell in row.cells {
                let letter = cell.reference.column.value
                guard let label = labelByLetter[letter] else { continue }
                rec[label] = stringValue(
                    of: cell,
                    sharedStrings: parsed.sharedStrings,
                    dateStyles: parsed.dateStyleIndices
                )
            }
            // Skip fully-empty rows so trailing blank lines don't
            // generate empty records.
            if rec.values.contains(where: { !isEmptyValue($0) }) {
                out.append(rec)
            }
        }
        return ExtractedRows(columns: columnLabels, rows: out)
    }

    // MARK: - Cell decoding

    private func stringValue(of cell: Cell, sharedStrings: SharedStrings?, dateStyles: Set<Int>) -> String {
        // Excel-date cells: numeric value + a date number-format
        // style. Convert the serial to an ISO date string here so
        // downstream coercion to `.date` / `.dateTime` works without
        // each consumer having to know about Excel serials.
        if let styleIndex = cell.styleIndex,
           dateStyles.contains(styleIndex),
           let raw = cell.value,
           let serial = Double(raw) {
            return Self.isoStringFromExcelSerial(serial)
        }
        // Regular string lookup. `cell.stringValue(_:)` requires
        // non-optional SharedStrings; when nil, fall through to
        // `cell.value` (raw stored numeric or inline) or
        // `inlineString.text`.
        if let shared = sharedStrings, let s = cell.stringValue(shared) {
            return s
        }
        if let inline = cell.inlineString?.text { return inline }
        return cell.value ?? ""
    }

    /// Excel stores dates as days since 1899-12-30 (the offset that
    /// reconciles the famous 1900-leap-year bug). Fractional part is
    /// the time of day (0.5 = noon). Returns:
    ///   • "yyyy-MM-dd"               when there's no fractional part
    ///   • "yyyy-MM-ddTHH:mm:ssZ"      when there is one
    /// Mac-style 1904 workbooks aren't auto-detected — Excel for Mac
    /// has used the 1900 base since 2008, so the 1904 system is rare
    /// in real-world files. If a user reports off-by-1462 days we
    /// add the option then.
    static func isoStringFromExcelSerial(_ serial: Double) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let epoch = cal.date(from: DateComponents(
            timeZone: TimeZone(identifier: "UTC"),
            year: 1899, month: 12, day: 30
        )) ?? Date(timeIntervalSince1970: 0)
        let wholeDays = Int(serial.rounded(.towardZero))
        let fractional = serial - Double(wholeDays)
        guard let date = cal.date(byAdding: .day, value: wholeDays, to: epoch) else {
            return String(serial)
        }
        if fractional == 0 {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "UTC")
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: date)
        }
        // Add fractional-day seconds.
        let secondsInDay = 86_400
        let extraSeconds = Int((fractional * Double(secondsInDay)).rounded())
        let withTime = date.addingTimeInterval(TimeInterval(extraSeconds))
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: withTime)
    }

    private func isEmptyValue(_ v: Any) -> Bool {
        if let s = v as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if v is NSNull { return true }
        return false
    }

    // MARK: - Column-letter helpers

    /// Excel's column letters are base-26 (A=1, Z=26, AA=27, …).
    private func columnLetterIndex(from letters: String) -> Int? {
        guard !letters.isEmpty else { return nil }
        var n = 0
        for c in letters.uppercased() {
            guard let scalar = c.asciiValue, (65...90).contains(scalar) else { return nil }
            n = n * 26 + Int(scalar - 64)
        }
        return n
    }
}

// MARK: - Errors

enum XLSXReaderError: LocalizedError {
    case openFailed(String)
    case sheetNotFound(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let path):
            return "Couldn't open Excel file ‘\(path)’ — verify it's a valid .xlsx."
        case .sheetNotFound(let name):
            return "Worksheet ‘\(name)’ not found in this workbook."
        }
    }
}

private extension PurpleImport.SourceInput {
    var label: String {
        switch self {
        case .url(let url):              return url.lastPathComponent
        case .data(_, let hint):         return hint ?? "inline data"
        }
    }
}

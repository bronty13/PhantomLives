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
        return ParsedWorkbook(worksheet: worksheet, sharedStrings: sharedStrings)
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
                let label = stringValue(of: cell, sharedStrings: parsed.sharedStrings)
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
                rec[label] = stringValue(of: cell, sharedStrings: parsed.sharedStrings)
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

    private func stringValue(of cell: Cell, sharedStrings: SharedStrings?) -> String {
        // `cell.stringValue(_:)` requires non-optional SharedStrings;
        // when nil, fall through to `cell.value` (the raw stored
        // numeric string) or an inline string.
        if let shared = sharedStrings, let s = cell.stringValue(shared) {
            return s
        }
        if let inline = cell.inlineString?.text { return inline }
        return cell.value ?? ""
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

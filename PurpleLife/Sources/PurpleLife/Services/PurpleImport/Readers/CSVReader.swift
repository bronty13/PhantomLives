import Foundation

/// RFC-4180 CSV reader for Purple Import. Pure Swift, no dependencies.
///
/// Quoting rules implemented:
///   • Cell may be quoted (`"…"`); inside, `""` escapes one quote.
///   • Quoted cells may contain `,`, `\n`, `\r`.
///   • Unquoted cells are terminated by the delimiter or any line
///     terminator (CRLF / LF / CR).
///   • Trailing newline at end of file is tolerated.
///
/// Encoding: tries UTF-8 BOM, then UTF-16 BOM, then UTF-8 plain,
/// then Latin-1 (ISO-8859-1) as a last resort. Latin-1 never fails
/// to decode, so the chain always terminates.
///
/// Header row: default is "first row is a header." User can override
/// via the `hasHeader` source option (Bool). With a header, columns
/// are the trimmed header values; without, columns are auto-named
/// `col_1`, `col_2`, ….
final class CSVReader: PurpleImportSourceReader {

    var format: PurpleImport.SourceFormat { .csv }

    private var delimiter: Character = ","
    private var hasHeader: Bool = true
    private var encodingOverride: String.Encoding?

    func setOptions(_ options: [String: Any]) {
        if let d = options["delimiter"] as? String, let c = d.first {
            self.delimiter = c
        }
        if let h = options["hasHeader"] as? Bool {
            self.hasHeader = h
        }
        if let e = options["encoding"] as? String {
            // Only honor named encodings we support; anything else
            // falls through the detection chain.
            switch e.lowercased() {
            case "utf-8":   encodingOverride = .utf8
            case "utf-16":  encodingOverride = .utf16
            case "latin-1", "iso-8859-1": encodingOverride = .isoLatin1
            default:        encodingOverride = nil
            }
        }
    }

    // MARK: - PurpleImportSourceReader

    func probe(_ source: PurpleImport.SourceInput) async throws -> PurpleImport.SourceShape {
        let preview = try await preview(source, sampleSize: 200)
        return preview.shape
    }

    func preview(_ source: PurpleImport.SourceInput, sampleSize: Int) async throws -> PurpleImport.SourcePreview {
        let text = try loadText(source)
        let rows = try parse(text, maxRows: sampleSize + (hasHeader ? 1 : 0))
        guard !rows.isEmpty else {
            return PurpleImport.SourcePreview(
                shape: .tabular(columns: [], inferredKinds: [:]),
                sampleRows: [],
                totalRows: 0
            )
        }

        let columns: [String]
        let dataRows: [[String]]
        if hasHeader {
            columns = rows[0].map { $0.trimmingCharacters(in: .whitespaces) }
            dataRows = Array(rows.dropFirst())
        } else {
            let count = rows[0].count
            columns = (1...max(count, 1)).map { "col_\($0)" }
            dataRows = rows
        }

        // Build SourceRows. Missing trailing cells in a short row are
        // treated as empty strings — same behavior the wizard's
        // preview ends up showing.
        let sourceRows: [PurpleImport.SourceRow] = dataRows.enumerated().map { (i, cells) in
            var dict: [PurpleImport.SourceLocator: Any] = [:]
            for (colIdx, name) in columns.enumerated() {
                let value: Any = colIdx < cells.count ? cells[colIdx] : ""
                dict[.column(name)] = value
            }
            return PurpleImport.SourceRow(cells: dict, rowIndex: i)
        }

        // Infer kinds per column from the sample.
        var kinds: [String: FieldKind] = [:]
        for name in columns {
            let column = sourceRows.compactMap { $0.cell(at: .column(name)) }
            kinds[name] = FieldValueCoercer.inferKind(samples: column)
        }

        return PurpleImport.SourcePreview(
            shape: .tabular(columns: columns, inferredKinds: kinds),
            sampleRows: sourceRows,
            totalRows: nil
        )
    }

    func read(_ source: PurpleImport.SourceInput) -> AsyncThrowingStream<PurpleImport.SourceRow, Error> {
        AsyncThrowingStream { continuation in
            do {
                let text = try loadText(source)
                let rows = try parse(text, maxRows: nil)
                let columns: [String]
                let dataRows: [[String]]
                if hasHeader, !rows.isEmpty {
                    columns = rows[0].map { $0.trimmingCharacters(in: .whitespaces) }
                    dataRows = Array(rows.dropFirst())
                } else if !rows.isEmpty {
                    let count = rows[0].count
                    columns = (1...max(count, 1)).map { "col_\($0)" }
                    dataRows = rows
                } else {
                    columns = []
                    dataRows = []
                }
                for (i, cells) in dataRows.enumerated() {
                    if Task.isCancelled { break }
                    var dict: [PurpleImport.SourceLocator: Any] = [:]
                    for (colIdx, name) in columns.enumerated() {
                        let value: Any = colIdx < cells.count ? cells[colIdx] : ""
                        dict[.column(name)] = value
                    }
                    continuation.yield(PurpleImport.SourceRow(cells: dict, rowIndex: i))
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    // MARK: - Loading

    private func loadText(_ source: PurpleImport.SourceInput) throws -> String {
        switch source {
        case .url(let url):
            let data = try Data(contentsOf: url)
            return try decode(data)
        case .data(let data, _):
            return try decode(data)
        }
    }

    private func decode(_ data: Data) throws -> String {
        // 1) Explicit override wins.
        if let enc = encodingOverride, let s = String(data: data, encoding: enc) {
            return s
        }
        // 2) UTF-8 BOM (EF BB BF).
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            return String(data: data.dropFirst(3), encoding: .utf8) ?? ""
        }
        // 3) UTF-16 BOM (FF FE or FE FF).
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            if let s = String(data: data, encoding: .utf16) { return s }
        }
        // 4) UTF-8 plain.
        if let s = String(data: data, encoding: .utf8) { return s }
        // 5) Latin-1 fallback — never fails.
        return String(data: data, encoding: .isoLatin1) ?? ""
    }

    // MARK: - Parser

    /// Parses CSV text into rows-of-strings. `maxRows` caps work for
    /// the preview path; nil reads the whole file.
    ///
    /// Note on line endings: Swift's `String` iteration treats `\r\n`
    /// as a single `Character` (one grapheme cluster), which would
    /// hide CRLF from a per-Character matcher. We normalize to `\n`
    /// before parsing — same effect as the conventional "always
    /// canonicalize newlines on read" preprocessor step.
    private func parse(_ originalText: String, maxRows: Int?) throws -> [[String]] {
        let text = originalText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var rows: [[String]] = []
        var current: [String] = []
        var cell = ""
        var inQuotes = false
        var i = text.startIndex

        func finishCell() {
            current.append(cell)
            cell = ""
        }
        func finishRow() {
            // Skip a fully-empty trailing row (the final newline at
            // EOF is normal and shouldn't produce a zero-cell row).
            if !(current.count == 1 && current[0].isEmpty) {
                rows.append(current)
            }
            current = []
        }

        while i < text.endIndex {
            let c = text[i]
            if let cap = maxRows, rows.count >= cap {
                break
            }
            if inQuotes {
                if c == "\"" {
                    let next = text.index(after: i)
                    if next < text.endIndex, text[next] == "\"" {
                        cell.append("\"")
                        i = text.index(after: next)
                        continue
                    } else {
                        inQuotes = false
                    }
                } else {
                    cell.append(c)
                }
            } else {
                if c == "\"" {
                    inQuotes = true
                } else if c == delimiter {
                    finishCell()
                } else if c == "\n" {
                    finishCell()
                    finishRow()
                } else {
                    cell.append(c)
                }
            }
            i = text.index(after: i)
        }
        // Flush any trailing cell / row that wasn't terminated by a newline.
        if !cell.isEmpty || !current.isEmpty {
            finishCell()
            finishRow()
        }
        return rows
    }
}

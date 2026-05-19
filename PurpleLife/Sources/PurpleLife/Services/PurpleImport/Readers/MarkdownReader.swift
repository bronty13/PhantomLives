import Foundation

/// Markdown reader for Purple Import. Two shapes:
///
/// 1. **Tabular** — GFM-style pipe tables. The first table found in the
///    document is the source; the wizard's `rootPath` option lets the
///    user pick a later one by index (`"table.1"`). Cells are
///    surfaced as `.column(<header>)` locators, same shape as CSV.
///
/// 2. **Tree (frontmatter)** — YAML/TOML-style frontmatter block at
///    the top of the document (delimited by `---` for YAML, `+++` for
///    TOML). Keys become `.path("$.key")` locators. The body text
///    after the frontmatter is exposed as `.path("$._body")` so a
///    mapping can write the rest of the document into a long-text
///    field.
///
/// 3. **Plain document** — no tables and no frontmatter. Surfaces as
///    a single-record `.document(richText:)` shape that the wizard's
///    Word/PDF v1 path also produces; the body lives at
///    `.path("$._body")`.
///
/// The reader auto-detects which shape applies. The user can force
/// one via the `mode` option (`"table"`, `"frontmatter"`, `"document"`).
final class MarkdownReader: PurpleImportSourceReader {

    var format: PurpleImport.SourceFormat { .markdown }

    private enum Mode: String { case auto, table, frontmatter, document }
    private var mode: Mode = .auto
    private var tableIndex: Int = 0

    func setOptions(_ options: [String: Any]) {
        if let s = options["mode"] as? String, let m = Mode(rawValue: s) {
            self.mode = m
        }
        if let i = options["tableIndex"] as? Int {
            self.tableIndex = i
        }
    }

    // MARK: - PurpleImportSourceReader

    func probe(_ source: PurpleImport.SourceInput) async throws -> PurpleImport.SourceShape {
        let preview = try await preview(source, sampleSize: 50)
        return preview.shape
    }

    func preview(_ source: PurpleImport.SourceInput, sampleSize: Int) async throws -> PurpleImport.SourcePreview {
        let text = try loadText(source)
        let resolved = resolveMode(in: text)

        switch resolved {
        case .table:
            let tables = parseAllTables(in: text)
            guard !tables.isEmpty else {
                return PurpleImport.SourcePreview(
                    shape: .tabular(columns: [], inferredKinds: [:]),
                    sampleRows: [],
                    totalRows: 0
                )
            }
            let table = tables[min(tableIndex, tables.count - 1)]
            let rows = table.rows.prefix(sampleSize)
            let sourceRows: [PurpleImport.SourceRow] = rows.enumerated().map { (i, cells) in
                var dict: [PurpleImport.SourceLocator: Any] = [:]
                for (colIdx, name) in table.headers.enumerated() {
                    dict[.column(name)] = colIdx < cells.count ? cells[colIdx] : ""
                }
                return PurpleImport.SourceRow(cells: dict, rowIndex: i)
            }
            var kinds: [String: FieldKind] = [:]
            for name in table.headers {
                let column = sourceRows.compactMap { $0.cell(at: .column(name)) }
                kinds[name] = FieldValueCoercer.inferKind(samples: column)
            }
            return PurpleImport.SourcePreview(
                shape: .tabular(columns: table.headers, inferredKinds: kinds),
                sampleRows: sourceRows,
                totalRows: table.rows.count
            )

        case .frontmatter:
            let (fm, body) = parseFrontmatter(in: text)
            var keys = fm.keys.sorted()
            var cells: [PurpleImport.SourceLocator: Any] = [:]
            for k in keys { cells[.path("$.\(k)")] = fm[k] ?? "" }
            cells[.path("$._body")] = body
            keys.append("_body")
            let row = PurpleImport.SourceRow(cells: cells, rowIndex: 0)
            return PurpleImport.SourcePreview(
                shape: .tree(rootPaths: keys.map { "$.\($0)" }),
                sampleRows: [row],
                totalRows: 1
            )

        default:  // .document or .auto-with-no-structure
            let body = text
            let row = PurpleImport.SourceRow(
                cells: [.path("$._body"): body],
                rowIndex: 0
            )
            return PurpleImport.SourcePreview(
                shape: .document(richText: body),
                sampleRows: [row],
                totalRows: 1
            )
        }
    }

    func read(_ source: PurpleImport.SourceInput) -> AsyncThrowingStream<PurpleImport.SourceRow, Error> {
        AsyncThrowingStream { continuation in
            do {
                let text = try loadText(source)
                let resolved = resolveMode(in: text)

                switch resolved {
                case .table:
                    let tables = parseAllTables(in: text)
                    if tables.isEmpty { continuation.finish(); return }
                    let table = tables[min(tableIndex, tables.count - 1)]
                    for (i, cells) in table.rows.enumerated() {
                        if Task.isCancelled { break }
                        var dict: [PurpleImport.SourceLocator: Any] = [:]
                        for (colIdx, name) in table.headers.enumerated() {
                            dict[.column(name)] = colIdx < cells.count ? cells[colIdx] : ""
                        }
                        continuation.yield(PurpleImport.SourceRow(cells: dict, rowIndex: i))
                    }

                case .frontmatter:
                    let (fm, body) = parseFrontmatter(in: text)
                    var cells: [PurpleImport.SourceLocator: Any] = [:]
                    for (k, v) in fm { cells[.path("$.\(k)")] = v }
                    cells[.path("$._body")] = body
                    continuation.yield(PurpleImport.SourceRow(cells: cells, rowIndex: 0))

                default:
                    continuation.yield(PurpleImport.SourceRow(
                        cells: [.path("$._body"): text],
                        rowIndex: 0
                    ))
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
            return decodeUTF8WithFallbacks(data)
        case .data(let data, _):
            return decodeUTF8WithFallbacks(data)
        }
    }

    private func decodeUTF8WithFallbacks(_ data: Data) -> String {
        // BOM-aware UTF-8 first; Latin-1 fallback never fails.
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            return String(data: data.dropFirst(3), encoding: .utf8) ?? ""
        }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1) ?? ""
    }

    // MARK: - Mode resolution

    private func resolveMode(in text: String) -> Mode {
        if mode != .auto { return mode }
        if hasFrontmatter(text) { return .frontmatter }
        if !parseAllTables(in: text).isEmpty { return .table }
        return .document
    }

    private func hasFrontmatter(_ text: String) -> Bool {
        let trimmed = text.drop(while: { $0.isWhitespace })
        return trimmed.hasPrefix("---\n") || trimmed.hasPrefix("---\r\n")
            || trimmed.hasPrefix("+++\n") || trimmed.hasPrefix("+++\r\n")
    }

    // MARK: - Frontmatter

    /// Parse YAML / TOML frontmatter. Intentionally minimal — supports
    /// `key: value` and `key = "value"` shapes, scalar values only.
    /// Nested mappings / arrays land in the body section by design;
    /// the wizard's "Create new type from this source" step doesn't
    /// have a great UI for them yet.
    private func parseFrontmatter(in text: String) -> ([String: String], String) {
        var fm: [String: String] = [:]
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        guard !lines.isEmpty else { return (fm, "") }
        guard lines[0] == "---" || lines[0] == "+++" else { return (fm, text) }
        let delimiter = String(lines[0])

        var endIdx: Int? = nil
        for i in 1..<lines.count where lines[i] == Substring(delimiter) {
            endIdx = i
            break
        }
        guard let end = endIdx else { return (fm, text) }

        for i in 1..<end {
            let line = String(lines[i]).trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if let colon = line.firstIndex(of: ":") {
                let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                let val = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                fm[key] = stripQuotes(val)
                continue
            }
            if let eq = line.firstIndex(of: "=") {
                let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
                let val = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                fm[key] = stripQuotes(val)
                continue
            }
        }
        let body = lines[(end + 1)...].joined(separator: "\n")
        return (fm, body)
    }

    private func stripQuotes(_ s: String) -> String {
        if s.count >= 2, (s.first == "\"" && s.last == "\"") || (s.first == "'" && s.last == "'") {
            return String(s.dropFirst().dropLast())
        }
        return s
    }

    // MARK: - GFM tables

    private struct Table {
        let headers: [String]
        let rows: [[String]]
    }

    /// Find every GFM pipe table in the text. A table is a header
    /// row, a separator row (`| --- | --- |` with optional alignment
    /// colons), and one or more data rows. Lines that don't fit the
    /// table shape between rows terminate the table.
    private func parseAllTables(in text: String) -> [Table] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var tables: [Table] = []
        var i = 0
        while i < lines.count {
            // Look for header + separator pair.
            if i + 1 < lines.count, isLikelyTableRow(lines[i]), isSeparator(lines[i + 1]) {
                let headers = parsePipeRow(lines[i])
                var dataRows: [[String]] = []
                var j = i + 2
                while j < lines.count, isLikelyTableRow(lines[j]) {
                    dataRows.append(parsePipeRow(lines[j]))
                    j += 1
                }
                tables.append(Table(headers: headers, rows: dataRows))
                i = j
                continue
            }
            i += 1
        }
        return tables
    }

    private func isLikelyTableRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.contains("|")
    }

    private func isSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("-") else { return false }
        let body = trimmed
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "|", with: "")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
        return body.isEmpty
    }

    private func parsePipeRow(_ line: String) -> [String] {
        var s = line.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("|") { s.removeFirst() }
        if s.hasSuffix("|") { s.removeLast() }
        return s.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

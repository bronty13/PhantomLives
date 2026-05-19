import AppKit
import Foundation
import WebKit

/// Per-type record exporter.
///
/// Writes a single file to the user's resolved export directory
/// (default: `~/Downloads/PurpleLife/`, overridable in Settings → Export)
/// or returns formatted text for clipboard use. CSV is the workhorse —
/// rows = records, columns = the type's field definitions, with link
/// fields resolved to the referenced record's title and multi-select
/// joined by `|`. Markdown is the same row data shaped as a Markdown
/// table; HTML/PDF wraps the data in a styled standalone document
/// (PDF via WKWebView's print pipeline, same approach as Timeliner).
///
/// The pure formatters (`formatCSV`, `formatMarkdown`, `formatHTML`)
/// take resolver closures rather than touching `ObjectEngine` /
/// `AttachmentService` directly. That keeps them deterministic for
/// unit tests and free of `@MainActor` constraints.
@MainActor
enum ExportService {

    enum Format: String, CaseIterable {
        case csv, markdown, html, pdf

        var fileExtension: String {
            switch self {
            case .csv:      return "csv"
            case .markdown: return "md"
            case .html:     return "html"
            case .pdf:      return "pdf"
            }
        }

        var menuLabel: String {
            switch self {
            case .csv:      return "CSV"
            case .markdown: return "Markdown"
            case .html:     return "HTML"
            case .pdf:      return "PDF"
            }
        }
    }

    enum ExportError: Error, LocalizedError {
        case writeFailed(String)
        case pdfFailed(String)

        var errorDescription: String? {
            switch self {
            case .writeFailed(let s): return s
            case .pdfFailed(let s):   return "PDF render failed: \(s)"
            }
        }
    }

    // MARK: - File export

    /// Format the records and write them to a stamped file under the
    /// resolved export directory. Returns the URL written so the caller
    /// can reveal it in Finder.
    @discardableResult
    static func export(
        records: [ObjectRecord],
        type: ObjectType,
        format: Format,
        exportDir: URL,
        linkTitle: (String) -> String? = { _ in nil },
        attachmentLabel: (String) -> String? = { _ in nil }
    ) async throws -> URL {
        try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
        let stamp = filenameStamp()
        let safeName = sanitizeFilename(type.pluralName.isEmpty ? type.name : type.pluralName)
        let outURL = exportDir.appendingPathComponent("\(safeName)-\(stamp).\(format.fileExtension)")

        switch format {
        case .csv:
            let text = formatCSV(records: records, type: type, linkTitle: linkTitle, attachmentLabel: attachmentLabel)
            try writeText(text, to: outURL)
        case .markdown:
            let text = formatMarkdown(records: records, type: type, linkTitle: linkTitle, attachmentLabel: attachmentLabel)
            try writeText(text, to: outURL)
        case .html:
            let text = formatHTML(records: records, type: type, linkTitle: linkTitle, attachmentLabel: attachmentLabel)
            try writeText(text, to: outURL)
        case .pdf:
            let html = formatHTML(records: records, type: type, linkTitle: linkTitle, attachmentLabel: attachmentLabel)
            let pdfData = try await renderHTMLToPDF(html: html)
            do {
                try pdfData.write(to: outURL, options: .atomic)
            } catch {
                throw ExportError.writeFailed(error.localizedDescription)
            }
        }
        return outURL
    }

    /// Copy formatted text to the system clipboard. Only the text-based
    /// formats (csv, markdown, html) make sense here — the PDF path
    /// produces binary data and is file-only.
    static func copyToClipboard(
        records: [ObjectRecord],
        type: ObjectType,
        format: Format,
        linkTitle: (String) -> String? = { _ in nil },
        attachmentLabel: (String) -> String? = { _ in nil }
    ) {
        let text: String
        switch format {
        case .csv:
            text = formatCSV(records: records, type: type, linkTitle: linkTitle, attachmentLabel: attachmentLabel)
        case .markdown:
            text = formatMarkdown(records: records, type: type, linkTitle: linkTitle, attachmentLabel: attachmentLabel)
        case .html:
            text = formatHTML(records: records, type: type, linkTitle: linkTitle, attachmentLabel: attachmentLabel)
        case .pdf:
            // PDFs aren't text — bail early rather than silently copy
            // an HTML stand-in the caller didn't ask for.
            return
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    // MARK: - Formatters (pure)

    /// CSV. Header row is the field display names plus the always-present
    /// id / created_at / updated_at columns; each subsequent row is one
    /// record with cells in the same order.
    nonisolated static func formatCSV(
        records: [ObjectRecord],
        type: ObjectType,
        linkTitle: (String) -> String? = { _ in nil },
        attachmentLabel: (String) -> String? = { _ in nil }
    ) -> String {
        var lines: [String] = []
        let headers = ["id"] + type.fields.map(\.name) + ["created_at", "updated_at"]
        lines.append(headers.map(csvEscape).joined(separator: ","))

        for record in records {
            let fields = record.fields()
            var cells: [String] = [record.id]
            for def in type.fields {
                let raw = fields[def.key]
                cells.append(renderCell(raw, kind: def.kind, options: def.options,
                                        linkTitle: linkTitle, attachmentLabel: attachmentLabel))
            }
            cells.append(record.createdAt)
            cells.append(record.updatedAt)
            lines.append(cells.map(csvEscape).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Markdown table. Same header / row shape as CSV. Cells with pipes
    /// or newlines are escaped (`|` → `\|`, newline → `<br>`) so the
    /// table stays well-formed.
    nonisolated static func formatMarkdown(
        records: [ObjectRecord],
        type: ObjectType,
        linkTitle: (String) -> String? = { _ in nil },
        attachmentLabel: (String) -> String? = { _ in nil }
    ) -> String {
        let title = type.pluralName.isEmpty ? type.name : type.pluralName
        var out = "# \(title)\n\n"
        out += "_\(records.count) record\(records.count == 1 ? "" : "s") · exported \(humanStamp())_\n\n"

        let headers = ["id"] + type.fields.map(\.name) + ["created_at", "updated_at"]
        out += "| " + headers.map(markdownEscape).joined(separator: " | ") + " |\n"
        out += "| " + headers.map { _ in "---" }.joined(separator: " | ") + " |\n"

        for record in records {
            let fields = record.fields()
            var cells: [String] = [record.id]
            for def in type.fields {
                let raw = fields[def.key]
                cells.append(renderCell(raw, kind: def.kind, options: def.options,
                                        linkTitle: linkTitle, attachmentLabel: attachmentLabel))
            }
            cells.append(record.createdAt)
            cells.append(record.updatedAt)
            out += "| " + cells.map(markdownEscape).joined(separator: " | ") + " |\n"
        }
        return out
    }

    /// Standalone HTML. One `<table>` styled with inline CSS. The
    /// resulting document opens in any browser unmodified and is the
    /// input to the PDF renderer.
    nonisolated static func formatHTML(
        records: [ObjectRecord],
        type: ObjectType,
        linkTitle: (String) -> String? = { _ in nil },
        attachmentLabel: (String) -> String? = { _ in nil }
    ) -> String {
        let title = type.pluralName.isEmpty ? type.name : type.pluralName
        let headers = ["id"] + type.fields.map(\.name) + ["created_at", "updated_at"]

        var rowsHTML = ""
        for record in records {
            let fields = record.fields()
            var cells: [String] = [record.id]
            for def in type.fields {
                let raw = fields[def.key]
                cells.append(renderCell(raw, kind: def.kind, options: def.options,
                                        linkTitle: linkTitle, attachmentLabel: attachmentLabel))
            }
            cells.append(record.createdAt)
            cells.append(record.updatedAt)
            rowsHTML += "    <tr>" + cells.map { "<td>\(htmlEscape($0))</td>" }.joined() + "</tr>\n"
        }
        let headerHTML = headers.map { "<th>\(htmlEscape($0))</th>" }.joined()
        let count = records.count

        return """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <title>\(htmlEscape(title)) — PurpleLife</title>
          <style>\(makeCSS())</style>
        </head>
        <body>
          <header>
            <h1>\(htmlEscape(title))</h1>
            <div class="meta">\(count) record\(count == 1 ? "" : "s") · exported \(humanStamp())</div>
          </header>
          <table>
            <thead><tr>\(headerHTML)</tr></thead>
            <tbody>
        \(rowsHTML)    </tbody>
          </table>
          <footer>Generated by PurpleLife</footer>
        </body>
        </html>
        """
    }

    // MARK: - Cell rendering

    /// Render one field value to its export-cell string. Independent of
    /// output format; CSV / Markdown / HTML each apply their own escaping
    /// after this returns.
    nonisolated static func renderCell(
        _ raw: Any?,
        kind: FieldKind,
        options: [FieldOption],
        linkTitle: (String) -> String?,
        attachmentLabel: (String) -> String?
    ) -> String {
        guard let raw, !(raw is NSNull) else { return "" }

        switch kind {
        case .text, .longText, .url, .email:
            return stringValue(raw)
        case .richText:
            // Exports take the plain mirror — CSV / Markdown / HTML don't
            // surface RTF natively, and the PDF path renders the same
            // plain mirror via the existing HTML pipeline. If a future
            // export format wants the rich content, it can branch here
            // on the `rtf` blob.
            if let dict = raw as? [String: Any],
               let plain = dict["plain"] as? String {
                return plain
            }
            return stringValue(raw)
        case .noteLog:
            // Render each entry as "[timestamp] plain text" and trailing
            // " [attachments: filename1, filename2]" when present.
            // Newest first to match the editor order.
            guard let dict = raw as? [String: Any],
                  let entries = dict["entries"] as? [[String: Any]] else {
                return ""
            }
            let sorted = entries.sorted { l, r in
                ((l["createdAt"] as? String) ?? "") > ((r["createdAt"] as? String) ?? "")
            }
            return sorted.map { entry -> String in
                let stamp = (entry["createdAt"] as? String) ?? ""
                let plain = (entry["plain"] as? String) ?? ""
                let atts = (entry["attachments"] as? [[String: Any]]) ?? []
                let names = atts.compactMap { $0["filename"] as? String }
                var line = "[\(stamp)] \(plain)"
                if !names.isEmpty {
                    line += " [attachments: \(names.joined(separator: ", "))]"
                }
                return line
            }.joined(separator: "\n")
        case .number:
            if let d = raw as? Double {
                return formatNumber(d)
            }
            if let i = raw as? Int {
                return String(i)
            }
            return stringValue(raw)
        case .date, .dateTime:
            return stringValue(raw)
        case .boolean:
            if let b = raw as? Bool { return b ? "true" : "false" }
            return stringValue(raw)
        case .select:
            let id = stringValue(raw)
            return options.first(where: { $0.id == id })?.name ?? id
        case .multiSelect:
            let ids: [String]
            if let arr = raw as? [String] {
                ids = arr
            } else if let arr = raw as? [Any] {
                ids = arr.map { stringValue($0) }
            } else {
                ids = stringValue(raw).split(separator: "|").map(String.init)
            }
            let names = ids.map { id in
                options.first(where: { $0.id == id })?.name ?? id
            }
            return names.joined(separator: "|")
        case .link:
            let id = stringValue(raw)
            return linkTitle(id) ?? id
        case .rating:
            if let i = raw as? Int { return String(i) }
            if let d = raw as? Double { return String(Int(d.rounded())) }
            return stringValue(raw)
        case .attachment:
            let sha = stringValue(raw)
            return attachmentLabel(sha) ?? sha
        }
    }

    // MARK: - PDF

    /// Renders an HTML string to PDF data via an off-screen WKWebView.
    /// Same pipeline as `Timeliner.ExportService.exportCaseAsPDF`; the
    /// only difference is that we write to a generic per-type filename
    /// rather than a case-specific one.
    /// Exposed (was `private`) so the Phase 4 Purple Export PDF
    /// writer can hand a pre-rendered HTML string straight to this
    /// pipeline without re-implementing the WKWebView dance.
    static func renderHTMLToPDF(html: String) async throws -> Data {
        // 8.5 × 11 in at 72 dpi — US letter portrait.
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let webView = WKWebView(frame: pageRect)
        let coordinator = LoadCoordinator()
        webView.navigationDelegate = coordinator

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            coordinator.completion = { result in
                switch result {
                case .success: cont.resume()
                case .failure(let e): cont.resume(throwing: e)
                }
            }
            webView.loadHTMLString(html, baseURL: nil)
        }

        let config = WKPDFConfiguration()
        config.rect = pageRect
        do {
            return try await webView.pdf(configuration: config)
        } catch {
            throw ExportError.pdfFailed(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    nonisolated private static func writeText(_ text: String, to url: URL) throws {
        do {
            try text.data(using: .utf8)?.write(to: url, options: .atomic)
        } catch {
            throw ExportError.writeFailed(error.localizedDescription)
        }
    }

    nonisolated private static func stringValue(_ raw: Any) -> String {
        if let s = raw as? String { return s }
        return "\(raw)"
    }

    nonisolated private static func formatNumber(_ d: Double) -> String {
        // Trim trailing zeros for whole numbers; otherwise keep up to 6
        // significant digits. Avoids "12.0" when the user typed 12,
        // avoids scientific notation for ordinary values.
        if d.rounded() == d, abs(d) < 1e15 {
            return String(Int64(d))
        }
        return String(d)
    }

    nonisolated static func csvEscape(_ s: String) -> String {
        // RFC 4180 — quote a cell if it contains comma, quote, or newline;
        // double any embedded quotes.
        let needsQuoting = s.contains(",") || s.contains("\"") || s.contains("\n") || s.contains("\r")
        if !needsQuoting { return s }
        let escaped = s.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    nonisolated static func markdownEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "|", with: "\\|")
         .replacingOccurrences(of: "\n", with: "<br>")
    }

    /// Exposed (was `private`) so the Phase 4 Purple Export writers
    /// can reuse it without duplicating the entity-encoding rules.
    nonisolated static func htmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
         .replacingOccurrences(of: "'", with: "&#39;")
    }

    /// Exposed (was `private`) so the Phase 4 Purple Export runner
    /// can use the same filename-safe sanitizer for its template
    /// substitution.
    nonisolated static func sanitizeFilename(_ s: String) -> String {
        let unsafe = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = s.components(separatedBy: unsafe).joined(separator: "-")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
    }

    nonisolated private static func filenameStamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f.string(from: Date())
    }

    nonisolated private static func humanStamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: Date())
    }

    nonisolated private static func makeCSS() -> String { """
    :root {
      --bg: #ffffff;
      --text: #18181b;
      --muted: #71717a;
      --border: rgba(0,0,0,0.08);
      --header-bg: #f4f4f5;
      --row-alt: #fafafa;
      --accent: #8b65c1;
    }
    * { box-sizing: border-box; }
    html, body {
      margin: 0; padding: 0;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
      color: var(--text); background: var(--bg);
    }
    header {
      max-width: 1100px; margin: 0 auto; padding: 32px 24px 16px;
      border-bottom: 1px solid var(--border);
    }
    header h1 { font-size: 1.6rem; margin: 0 0 6px; color: var(--accent); }
    header .meta { color: var(--muted); font-size: 0.85rem; }
    table {
      width: 100%; max-width: 1100px; margin: 24px auto;
      border-collapse: collapse; font-size: 0.85rem;
    }
    th, td {
      text-align: left; padding: 8px 10px;
      border-bottom: 1px solid var(--border);
      vertical-align: top;
    }
    th {
      background: var(--header-bg); color: var(--muted);
      font-weight: 600; text-transform: uppercase;
      font-size: 0.7rem; letter-spacing: 0.05em;
    }
    tbody tr:nth-child(even) { background: var(--row-alt); }
    footer {
      max-width: 1100px; margin: 0 auto; padding: 16px 24px 40px;
      text-align: center; color: var(--muted); font-size: 0.75rem;
    }
    """ }
}

/// Bridges WKWebView's `didFinish` / `didFail` callbacks to a single
/// completion closure so we can `await` the page load before asking
/// for PDF data. Same pattern as Timeliner.
@MainActor
private final class LoadCoordinator: NSObject, WKNavigationDelegate {
    var completion: ((Result<Void, Error>) -> Void)?
    private var fired = false

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !fired else { return }
        fired = true
        completion?(.success(()))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard !fired else { return }
        fired = true
        completion?(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard !fired else { return }
        fired = true
        completion?(.failure(error))
    }
}

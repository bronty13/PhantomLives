import Foundation
import WebKit
import AppKit

/// Whole-journal export to Markdown, HTML, PDF, or JSON.
///
/// Every format is produced from the entries/tags/people already loaded in
/// `AppState`, grouped chronologically by year → month. Output lands in the
/// user's resolved export directory (default `~/Downloads/PurpleDiary/`) as a
/// single stamped file. Nothing leaves the Mac — this is the only way journal
/// content is ever written outside the encrypted database, and it happens only
/// when the user asks.
///
/// The render functions (`renderMarkdown`, `renderHTML`, `encodeJSON`) are pure
/// on their inputs (modulo the timestamp baked into the footer) so they're
/// snapshot-testable; `export(...)` is the side-effecting dispatcher. The PDF
/// path renders the same HTML through an off-screen `WKWebView` so the PDF and
/// HTML exports look identical, just paginated.
@MainActor
enum ExportService {

    enum Format: String, CaseIterable, Identifiable, Hashable {
        case markdown, html, pdf, json
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .markdown: return "Markdown"
            case .html:     return "HTML"
            case .pdf:      return "PDF"
            case .json:     return "JSON"
            }
        }
        var fileExtension: String {
            switch self {
            case .markdown: return "md"
            case .html:     return "html"
            case .pdf:      return "pdf"
            case .json:     return "json"
            }
        }
        var systemImage: String {
            switch self {
            case .markdown: return "text.alignleft"
            case .html:     return "globe"
            case .pdf:      return "doc.richtext"
            case .json:     return "curlybraces"
            }
        }
    }

    enum ExportError: Error, LocalizedError {
        case writeFailed(String)
        var errorDescription: String? {
            switch self { case .writeFailed(let s): return s }
        }
    }

    // MARK: - Public API

    /// Render + write the journal in `format`. Returns the URL of the written
    /// file. Creates `exportDir` on demand.
    @discardableResult
    static func export(
        format: Format,
        entries: [Entry],
        people: [Person],
        tagsByEntry: [String: [Tag]],
        peopleByEntry: [String: [Person]],
        exportDir: URL
    ) async throws -> URL {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: exportDir, withIntermediateDirectories: true)
        } catch {
            throw ExportError.writeFailed("Couldn't create the export folder: \(error.localizedDescription)")
        }

        let sorted = entries.sorted { $0.dateValue < $1.dateValue }
        let url = exportDir.appendingPathComponent("PurpleDiary-Journal-\(filenameStamp()).\(format.fileExtension)")

        do {
            switch format {
            case .markdown:
                let md = renderMarkdown(entries: sorted, tagsByEntry: tagsByEntry, peopleByEntry: peopleByEntry)
                try md.data(using: .utf8)?.write(to: url, options: .atomic)
            case .html:
                let html = renderHTML(entries: sorted, tagsByEntry: tagsByEntry, peopleByEntry: peopleByEntry)
                try html.data(using: .utf8)?.write(to: url, options: .atomic)
            case .json:
                let data = try encodeJSON(entries: sorted, people: people, tagsByEntry: tagsByEntry, peopleByEntry: peopleByEntry)
                try data.write(to: url, options: .atomic)
            case .pdf:
                let html = renderHTML(entries: sorted, tagsByEntry: tagsByEntry, peopleByEntry: peopleByEntry)
                let pdf = try await renderPDFData(html: html)
                try pdf.write(to: url, options: .atomic)
            }
        } catch let e as ExportError {
            throw e
        } catch {
            throw ExportError.writeFailed(error.localizedDescription)
        }
        return url
    }

    // MARK: - Markdown

    /// One Markdown document. Entries grouped under `## Year` / `### Month`
    /// headings, each entry a `####` section with a metadata line (date, mood
    /// stars, tags, people) followed by its body verbatim (it's already
    /// Markdown). Plain text, no front-matter — opens cleanly in any editor or
    /// Obsidian/Bear-style vault.
    static func renderMarkdown(
        entries: [Entry],
        tagsByEntry: [String: [Tag]],
        peopleByEntry: [String: [Person]]
    ) -> String {
        var out = "# My PurpleDiary Journal\n\n"
        out += "_\(entries.count) " + (entries.count == 1 ? "entry" : "entries") + " · exported \(humanStamp())_\n\n"

        if entries.isEmpty {
            out += "_No entries yet._\n"
            return out
        }

        for yg in groupByYearMonth(entries) {
            out += "## \(yg.year)\n\n"
            for mg in yg.months {
                out += "### \(mg.label)\n\n"
                for e in mg.entries {
                    let title = e.title.isEmpty ? "Untitled" : e.title
                    out += "#### \(title)\n\n"

                    var meta: [String] = [longDate(e.dateValue)]
                    if e.mood != .unset {
                        meta.append("\(starString(e.moodRating)) \(e.mood.label)")
                    }
                    let tags = (tagsByEntry[e.id] ?? []).map { "#\($0.name)" }
                    if !tags.isEmpty { meta.append(tags.joined(separator: " ")) }
                    let ppl = (peopleByEntry[e.id] ?? []).map(\.name).filter { !$0.isEmpty }
                    if !ppl.isEmpty { meta.append("with " + ppl.joined(separator: ", ")) }
                    if let place = e.placeName, !place.isEmpty { meta.append("📍 \(place)") }
                    out += "*\(meta.joined(separator: " · "))*\n\n"

                    let body = e.bodyMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
                    out += (body.isEmpty ? "_(no text)_" : body) + "\n\n"
                    out += "---\n\n"
                }
            }
        }
        out += "_Generated by PurpleDiary._\n"
        return out
    }

    // MARK: - HTML

    /// Self-contained, zero-dependency HTML document (inline CSS, purple theme).
    /// Same markup drives the PDF export. Bodies render through a small inline
    /// Markdown pass (bold/italic/code/links/line-breaks); block-level Markdown
    /// is escaped and shown literally to keep the output deterministic.
    static func renderHTML(
        entries: [Entry],
        tagsByEntry: [String: [Tag]],
        peopleByEntry: [String: [Person]]
    ) -> String {
        var body = ""
        body += "<header>\n"
        body += "  <h1>My PurpleDiary Journal</h1>\n"
        body += "  <div class='meta'>\(entries.count) " + (entries.count == 1 ? "entry" : "entries") + " · exported \(escape(humanStamp()))</div>\n"
        body += "</header>\n"

        if entries.isEmpty {
            body += "<main><p class='empty'>No entries yet.</p></main>\n"
        } else {
            body += "<main>\n"
            for yg in groupByYearMonth(entries) {
                body += "<section class='year'>\n  <h2>\(escape(yg.year))</h2>\n"
                for mg in yg.months {
                    body += "  <div class='month'>\n    <h3>\(escape(mg.label))</h3>\n"
                    for e in mg.entries {
                        body += renderEntryHTML(e,
                                                tags: tagsByEntry[e.id] ?? [],
                                                people: peopleByEntry[e.id] ?? [])
                    }
                    body += "  </div>\n"
                }
                body += "</section>\n"
            }
            body += "</main>\n"
        }
        body += "<footer>Generated by <strong>PurpleDiary</strong> · \(escape(humanStamp()))</footer>\n"

        return """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width,initial-scale=1">
          <title>My PurpleDiary Journal</title>
          <style>\(makeCSS())</style>
        </head>
        <body>
        \(body)</body>
        </html>
        """
    }

    private static func renderEntryHTML(_ e: Entry, tags: [Tag], people: [Person]) -> String {
        var s = "    <article class='entry'>\n"
        s += "      <div class='entry-head'>\n"
        s += "        <h4>\(escape(e.title.isEmpty ? "Untitled" : e.title))</h4>\n"
        s += "        <span class='date'>\(escape(longDate(e.dateValue)))</span>\n"
        s += "      </div>\n"

        if e.mood != .unset {
            s += "      <div class='mood' title='\(escape(e.mood.label))'>\(starHTML(e.moodRating)) <span>\(escape(e.mood.label))</span></div>\n"
        }

        let bodyText = e.bodyMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        if bodyText.isEmpty {
            s += "      <div class='body empty'>(no text)</div>\n"
        } else {
            s += "      <div class='body'>\(renderInlineMarkdown(bodyText))</div>\n"
        }

        if !tags.isEmpty || !people.isEmpty || (e.placeName.map { !$0.isEmpty } ?? false) {
            s += "      <div class='chips'>\n"
            for t in tags {
                s += "        <span class='chip tag' style='--c: \(escape(t.colorHex));'>\(escape(t.name))</span>\n"
            }
            for p in people where !p.name.isEmpty {
                s += "        <span class='chip person'>\(escape(p.name))</span>\n"
            }
            if let place = e.placeName, !place.isEmpty {
                s += "        <span class='chip place'>📍 \(escape(place))</span>\n"
            }
            s += "      </div>\n"
        }
        s += "    </article>\n"
        return s
    }

    // MARK: - JSON

    /// Versioned, round-trippable export model. `schemaVersion` lets a future
    /// importer (Phase 3) recognize the shape. Carries every entry field plus
    /// resolved tag names and people, and the global people roster.
    struct JournalExport: Codable, Equatable {
        var schemaVersion: Int
        var app: String
        var exportedAt: String
        var entryCount: Int
        var entries: [EntryExport]
        var people: [PersonExport]
    }
    struct EntryExport: Codable, Equatable {
        var id: String
        var date: String
        var title: String
        var bodyMarkdown: String
        var moodRating: Int
        var wordCount: Int
        var tags: [String]
        var people: [String]          // person ids linked to this entry
        var latitude: Double?
        var longitude: Double?
        var placeName: String?
        var weatherSummary: String?
        var temperatureC: Double?
        var createdAt: String
        var updatedAt: String
    }
    struct PersonExport: Codable, Equatable {
        var id: String
        var name: String
        var notes: String
    }

    static let jsonSchemaVersion = 1

    static func buildExportModel(
        entries: [Entry],
        people: [Person],
        tagsByEntry: [String: [Tag]],
        peopleByEntry: [String: [Person]]
    ) -> JournalExport {
        let entryModels = entries.map { e in
            EntryExport(
                id: e.id,
                date: e.date,
                title: e.title,
                bodyMarkdown: e.bodyMarkdown,
                moodRating: e.moodRating,
                wordCount: e.wordCount,
                tags: (tagsByEntry[e.id] ?? []).map(\.name),
                people: (peopleByEntry[e.id] ?? []).map(\.id),
                latitude: e.latitude,
                longitude: e.longitude,
                placeName: e.placeName,
                weatherSummary: e.weatherSummary,
                temperatureC: e.temperatureC,
                createdAt: e.createdAt,
                updatedAt: e.updatedAt
            )
        }
        return JournalExport(
            schemaVersion: jsonSchemaVersion,
            app: "PurpleDiary",
            exportedAt: ISO8601DateFormatter().string(from: Date()),
            entryCount: entryModels.count,
            entries: entryModels,
            people: people.map { PersonExport(id: $0.id, name: $0.name, notes: $0.notes) }
        )
    }

    static func encodeJSON(
        entries: [Entry],
        people: [Person],
        tagsByEntry: [String: [Tag]],
        peopleByEntry: [String: [Person]]
    ) throws -> Data {
        let model = buildExportModel(entries: entries, people: people,
                                     tagsByEntry: tagsByEntry, peopleByEntry: peopleByEntry)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(model)
    }

    // MARK: - PDF

    /// Render `html` to PDF data via an off-screen `WKWebView`. US-letter
    /// portrait at 72 dpi. Waits for the load to finish before asking for the
    /// PDF (WKWebView renders mid-load and would otherwise produce a blank page).
    static func renderPDFData(html: String) async throws -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)   // 8.5×11in
        let webView = WKWebView(frame: pageRect)
        let coordinator = LoadCoordinator()
        webView.navigationDelegate = coordinator

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            coordinator.completion = { result in
                switch result {
                case .success:        cont.resume()
                case .failure(let e): cont.resume(throwing: e)
                }
            }
            webView.loadHTMLString(html, baseURL: nil)
        }

        let config = WKPDFConfiguration()
        config.rect = pageRect
        return try await webView.pdf(configuration: config)
    }

    // MARK: - Inline markdown + escaping

    /// Tiny inline markdown → HTML: **bold**, *italic*, `code`, line breaks.
    /// Everything is HTML-escaped first, so user content can never inject
    /// markup. Block constructs (headings, lists) are left as literal text —
    /// deterministic, and good enough for a journal-body export.
    private static func renderInlineMarkdown(_ raw: String) -> String {
        var s = escape(raw)
        s = s.replacingOccurrences(of: #"\*\*([^*]+)\*\*"#, with: "<strong>$1</strong>", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?<!\*)\*([^*\n]+)\*(?!\*)"#, with: "<em>$1</em>", options: .regularExpression)
        s = s.replacingOccurrences(of: #"`([^`]+)`"#, with: "<code>$1</code>", options: .regularExpression)
        s = s.replacingOccurrences(of: "\n", with: "<br>\n")
        return s
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
         .replacingOccurrences(of: "'", with: "&#39;")
    }

    // MARK: - Grouping + formatting helpers

    struct YearGroup { let year: String; let months: [MonthGroup] }
    struct MonthGroup { let label: String; let entries: [Entry] }

    /// Group entries chronologically (ascending) by year then month.
    static func groupByYearMonth(_ entries: [Entry]) -> [YearGroup] {
        let cal = Calendar(identifier: .gregorian)
        let byYear = Dictionary(grouping: entries) { String(cal.component(.year, from: $0.dateValue)) }
        return byYear.keys.sorted().map { year in
            let yearEntries = byYear[year] ?? []
            let byMonth = Dictionary(grouping: yearEntries) { cal.component(.month, from: $0.dateValue) }
            let months = byMonth.keys.sorted().map { m -> MonthGroup in
                let label = DateFormatter().monthSymbols[m - 1]
                let es = (byMonth[m] ?? []).sorted { $0.dateValue < $1.dateValue }
                return MonthGroup(label: label, entries: es)
            }
            return YearGroup(year: year, months: months)
        }
    }

    private static func longDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEEE, MMM d, yyyy · h:mm a"
        return f.string(from: d)
    }

    private static func filenameStamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f.string(from: Date())
    }

    private static func humanStamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: Date())
    }

    private static func starString(_ n: Int) -> String {
        let filled = max(0, min(5, n))
        return String(repeating: "★", count: filled) + String(repeating: "☆", count: 5 - filled)
    }

    private static func starHTML(_ n: Int) -> String {
        let filled = max(0, min(5, n))
        var s = ""
        for i in 1...5 { s += "<span class='star \(i <= filled ? "on" : "off")'>\(i <= filled ? "★" : "☆")</span>" }
        return s
    }

    private static func makeCSS() -> String { """
    :root {
      --bg: #faf8ff;
      --surface: #ffffff;
      --text: #1f1936;
      --muted: #6b6585;
      --accent: #7c5cff;
      --border: #e7e0fb;
      --star: #f5b301;
    }
    * { box-sizing: border-box; }
    html, body {
      margin: 0; padding: 0;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
      color: var(--text); background: var(--bg);
      line-height: 1.55;
    }
    header {
      max-width: 820px; margin: 0 auto; padding: 40px 28px 16px;
      border-bottom: 3px solid var(--accent);
    }
    header h1 { font-size: 2rem; margin: 0 0 6px; color: var(--accent); }
    header .meta { color: var(--muted); font-size: 0.9rem; }
    main { max-width: 820px; margin: 0 auto; padding: 8px 28px 40px; }
    p.empty { color: var(--muted); font-style: italic; }
    section.year > h2 {
      font-size: 1.5rem; margin: 28px 0 8px; color: var(--accent);
      border-bottom: 1px solid var(--border); padding-bottom: 4px;
    }
    .month > h3 {
      font-size: 0.85rem; text-transform: uppercase; letter-spacing: 0.06em;
      color: var(--muted); margin: 18px 0 10px; font-weight: 700;
    }
    article.entry {
      background: var(--surface); border: 1px solid var(--border);
      border-left: 4px solid var(--accent); border-radius: 12px;
      padding: 16px 18px; margin-bottom: 14px;
      box-shadow: 0 1px 3px rgba(124,92,255,0.06);
      page-break-inside: avoid;
    }
    .entry-head { display: flex; justify-content: space-between; align-items: baseline; gap: 12px; }
    .entry-head h4 { margin: 0; font-size: 1.15rem; }
    .entry-head .date { color: var(--muted); font-size: 0.8rem; white-space: nowrap; }
    .mood { margin: 6px 0; font-size: 0.85rem; color: var(--muted); }
    .mood .star.on { color: var(--star); }
    .mood .star.off { color: var(--border); }
    .mood span { margin-left: 6px; }
    .body { margin: 8px 0 4px; }
    .body.empty { color: var(--muted); font-style: italic; }
    .body code {
      background: #f0ecff; padding: 1px 5px; border-radius: 5px;
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 0.9em;
    }
    .chips { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 10px; }
    .chip {
      font-size: 0.72rem; padding: 3px 9px; border-radius: 999px;
      background: #f3f0ff; color: var(--text); border: 1px solid var(--border);
    }
    .chip.tag {
      background: color-mix(in srgb, var(--c) 16%, white);
      border-color: color-mix(in srgb, var(--c) 45%, white);
    }
    .chip.person::before { content: "@ "; color: var(--muted); }
    footer {
      max-width: 820px; margin: 0 auto; padding: 20px 28px 48px;
      text-align: center; color: var(--muted); font-size: 0.8rem;
    }
    """ }
}

/// Bridges WKWebView's `didFinish` / `didFail` callbacks to a single completion
/// closure so `renderPDFData` can `await` the page load before asking for PDF
/// data. Ported from Timeliner's ExportService.
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

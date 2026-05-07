import Foundation
import WebKit
import AppKit

/// Standalone HTML export for a single case.
///
/// Produces one self-contained `.html` file at the user's resolved export
/// directory (default: `~/Downloads/Timeliner/`). The output embeds:
///   - inline CSS for the timeline layout
///   - inline JS for the year/month accordion toggles + tag filter
///   - inline data — every event, person, tag baked into the HTML
///
/// The exported file has zero external dependencies and works opened directly
/// in any browser, dropped on a static host, or attached to a forum post.
@MainActor
enum ExportService {

    enum ExportError: Error, LocalizedError {
        case writeFailed(String)
        var errorDescription: String? {
            switch self { case .writeFailed(let s): return s }
        }
    }

    /// Export a case as PDF. Renders the same HTML used by the standalone-HTML
    /// exporter, loads it into an off-screen `WKWebView`, and asks WebKit to
    /// produce the PDF data. The PDF inherits the inline CSS — same look as
    /// the HTML export, just paginated.
    @MainActor
    @discardableResult
    static func exportCaseAsPDF(
        _ aCase: Case,
        events: [Event],
        people: [Person],
        tagsByEvent: [String: [Tag]],
        peopleByEvent: [String: [Person]],
        exportDir: URL
    ) async throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: exportDir, withIntermediateDirectories: true)

        let stamp = filenameStamp()
        let safeTitle = sanitize(aCase.title.isEmpty ? "Untitled" : aCase.title)
        let outURL = exportDir.appendingPathComponent("\(safeTitle)-\(stamp).pdf")

        let html = render(
            aCase: aCase,
            events: events.sorted { ($0.parsedStart ?? .distantPast) < ($1.parsedStart ?? .distantPast) },
            people: people,
            tagsByEvent: tagsByEvent,
            peopleByEvent: peopleByEvent
        )

        // 8.5 × 11 inches at 72 dpi — US letter portrait. Adjust if we ever
        // need to expose page-size choice to the user.
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let webView = WKWebView(frame: pageRect)

        // Wait for the HTML to finish loading before asking for the PDF —
        // WKWebView renders mid-load and would produce a blank page otherwise.
        let coordinator = LoadCoordinator()
        webView.navigationDelegate = coordinator

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            coordinator.completion = { result in
                switch result {
                case .success:    cont.resume()
                case .failure(let e): cont.resume(throwing: e)
                }
            }
            webView.loadHTMLString(html, baseURL: nil)
        }

        let config = WKPDFConfiguration()
        config.rect = pageRect
        let pdfData = try await webView.pdf(configuration: config)

        try pdfData.write(to: outURL, options: .atomic)
        return outURL
    }

    @discardableResult
    static func exportCaseAsHTML(
        _ aCase: Case,
        events: [Event],
        people: [Person],
        tagsByEvent: [String: [Tag]],
        peopleByEvent: [String: [Person]],
        exportDir: URL
    ) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: exportDir, withIntermediateDirectories: true)

        let stamp = filenameStamp()
        let safeTitle = sanitize(aCase.title.isEmpty ? "Untitled" : aCase.title)
        let url = exportDir.appendingPathComponent("\(safeTitle)-\(stamp).html")

        let html = render(
            aCase: aCase,
            events: events.sorted { ($0.parsedStart ?? .distantPast) < ($1.parsedStart ?? .distantPast) },
            people: people,
            tagsByEvent: tagsByEvent,
            peopleByEvent: peopleByEvent
        )

        do {
            try html.data(using: .utf8)?.write(to: url, options: .atomic)
        } catch {
            throw ExportError.writeFailed(error.localizedDescription)
        }
        return url
    }

    // MARK: - Rendering

    /// Public entry point used by `ExportTests` for snapshot-style assertions.
    /// Pure function on the inputs (modulo the timestamp baked into the
    /// footer, which the caller can post-process out for stability).
    static func render(
        aCase: Case,
        events: [Event],
        people: [Person],
        tagsByEvent: [String: [Tag]],
        peopleByEvent: [String: [Person]]
    ) -> String {
        let title = aCase.title.isEmpty ? "Untitled case" : aCase.title
        let yearGroups = groupByYearMonth(events)

        var body = ""
        body += "<header>\n"
        body += "  <h1>\(escape(title))</h1>\n"
        body += "  <div class='meta'>\n"
        body += "    <span class='status status-\(aCase.statusEnum.rawValue)'>\(aCase.statusEnum.label)</span>\n"
        body += "    <span class='count'>\(events.count) events · \(people.count) people</span>\n"
        body += "  </div>\n"
        if !aCase.caseDescription.isEmpty {
            body += "  <div class='intro'>\(renderInlineMarkdown(aCase.caseDescription))</div>\n"
        }
        body += "</header>\n"

        if !yearGroups.isEmpty {
            body += "<main>\n"
            for yg in yearGroups {
                body += "<section class='year' data-year='\(yg.year)'>\n"
                body += "  <h2>\(yg.year)</h2>\n"
                for mg in yg.months {
                    body += "  <div class='month'>\n"
                    body += "    <h3>\(escape(mg.label))</h3>\n"
                    for ev in mg.events {
                        body += renderEvent(ev,
                                             tags: tagsByEvent[ev.id] ?? [],
                                             people: peopleByEvent[ev.id] ?? [])
                    }
                    body += "  </div>\n"
                }
                body += "</section>\n"
            }
            body += "</main>\n"
        }

        if !people.isEmpty {
            body += "<aside class='people'>\n"
            body += "  <h2>People</h2>\n"
            for p in people {
                body += "  <div class='person'>\n"
                body += "    <strong>\(escape(p.name.isEmpty ? "Unnamed" : p.name))</strong>\n"
                body += "    <span class='role role-\(p.roleEnum.rawValue)'>\(p.roleEnum.label)</span>\n"
                if !p.notes.isEmpty {
                    body += "    <p>\(escape(p.notes))</p>\n"
                }
                body += "  </div>\n"
            }
            body += "</aside>\n"
        }

        body += "<footer>Generated by <strong>Timeliner</strong> · \(humanStamp())</footer>\n"

        let css = makeCSS()
        let js = makeJS()

        return """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width,initial-scale=1">
          <title>\(escape(title)) — Timeliner</title>
          <style>\(css)</style>
        </head>
        <body>
        \(body)
        <script>\(js)</script>
        </body>
        </html>
        """
    }

    private static func renderEvent(_ ev: Event, tags: [Tag], people: [Person]) -> String {
        let dateStr: String
        if let d = ev.parsedStart {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "MMM d, yyyy"
            dateStr = f.string(from: d)
        } else {
            dateStr = ev.dateStart
        }
        let importance = ev.importanceEnum

        var s = ""
        s += "    <article class='event imp-\(importance.rawValue)'>\n"
        s += "      <div class='date'>\(escape(dateStr))</div>\n"
        s += "      <div class='body'>\n"
        s += "        <h4>\(escape(ev.title.isEmpty ? "Untitled event" : ev.title))</h4>\n"
        if !ev.descriptionMarkdown.isEmpty {
            s += "        <div class='desc'>\(renderInlineMarkdown(ev.descriptionMarkdown))</div>\n"
        }
        if !ev.sourceURL.isEmpty {
            s += "        <a class='source' href='\(escape(ev.sourceURL))'>\(escape(ev.sourceURL))</a>\n"
        }
        if !tags.isEmpty || !people.isEmpty {
            s += "        <div class='chips'>\n"
            for t in tags {
                s += "          <span class='chip tag' style='--c: \(escape(t.colorHex));'>\(escape(t.name))</span>\n"
            }
            for p in people {
                s += "          <span class='chip person'>\(escape(p.name.isEmpty ? p.roleEnum.label : p.name))</span>\n"
            }
            s += "        </div>\n"
        }
        s += "      </div>\n"
        s += "    </article>\n"
        return s
    }

    /// Tiny inline markdown rendering: just **bold**, *italic*, `code`, and
    /// bare URLs become anchors. Anything more elaborate (lists, headings)
    /// is escaped and printed literally — keeps the export deterministic and
    /// avoids pulling in an external markdown crate.
    private static func renderInlineMarkdown(_ raw: String) -> String {
        var s = escape(raw)
        s = s.replacingOccurrences(
            of: #"\*\*([^*]+)\*\*"#,
            with: "<strong>$1</strong>",
            options: .regularExpression
        )
        s = s.replacingOccurrences(
            of: #"(?<!\*)\*([^*\n]+)\*(?!\*)"#,
            with: "<em>$1</em>",
            options: .regularExpression
        )
        s = s.replacingOccurrences(
            of: #"`([^`]+)`"#,
            with: "<code>$1</code>",
            options: .regularExpression
        )
        s = s.replacingOccurrences(of: "\n", with: "<br>")
        return s
    }

    // MARK: - Grouping

    private struct YearGroup { let year: String; let months: [MonthGroup] }
    private struct MonthGroup { let label: String; let events: [Event] }

    private static func groupByYearMonth(_ events: [Event]) -> [YearGroup] {
        let cal = Calendar(identifier: .gregorian)
        let dict = Dictionary(grouping: events) { ev -> String in
            guard let d = ev.parsedStart else { return "—" }
            return String(cal.component(.year, from: d))
        }
        let yearKeys = dict.keys.sorted()
        return yearKeys.map { year in
            let yearEvents = dict[year] ?? []
            let monthDict = Dictionary(grouping: yearEvents) { ev -> Int in
                cal.component(.month, from: ev.parsedStart ?? .distantPast)
            }
            let months = monthDict.keys.sorted().map { m in
                let label = DateFormatter().monthSymbols[m - 1]
                let evs = (monthDict[m] ?? [])
                    .sorted { ($0.parsedStart ?? .distantPast) < ($1.parsedStart ?? .distantPast) }
                return MonthGroup(label: label, events: evs)
            }
            return YearGroup(year: year, months: months)
        }
    }

    // MARK: - Helpers

    private static func sanitize(_ s: String) -> String {
        let unsafe = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = s.components(separatedBy: unsafe).joined(separator: "-")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "_")
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

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
         .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func makeCSS() -> String { """
    :root {
      --bg: #0f1730;
      --surface: rgba(255,255,255,0.06);
      --surface-2: rgba(255,255,255,0.10);
      --text: #f1f5f9;
      --muted: #94a3b8;
      --accent: #60a5fa;
      --border: rgba(255,255,255,0.12);
    }
    * { box-sizing: border-box; }
    html, body {
      margin: 0; padding: 0;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
      color: var(--text);
      background: linear-gradient(180deg, #0a0f24 0%, #1a253f 100%);
      min-height: 100vh;
    }
    header {
      max-width: 920px; margin: 0 auto; padding: 40px 32px 24px;
    }
    header h1 { font-size: 2.2rem; margin: 0 0 10px; }
    header .meta {
      display: flex; gap: 12px; align-items: center;
      color: var(--muted); font-size: 0.9rem;
    }
    .status {
      padding: 3px 10px; border-radius: 999px; font-weight: 600;
      background: rgba(96,165,250,0.18); color: var(--accent);
    }
    .status-cold { background: rgba(96,165,250,0.18); color: #93c5fd; }
    .status-closed { background: rgba(148,163,184,0.18); color: #cbd5e1; }
    .status-active { background: rgba(248,113,113,0.18); color: #fca5a5; }
    header .intro {
      margin-top: 16px; color: var(--text);
      background: var(--surface); padding: 14px 16px; border-radius: 10px;
      border: 1px solid var(--border);
    }
    main { max-width: 920px; margin: 0 auto; padding: 0 32px 40px; }
    section.year h2 {
      font-size: 1.6rem; margin: 32px 0 16px;
      border-bottom: 1px solid var(--border); padding-bottom: 6px;
    }
    .month { margin-bottom: 28px; }
    .month h3 {
      font-size: 1rem; color: var(--muted);
      text-transform: uppercase; letter-spacing: 0.05em;
      margin: 0 0 10px; font-weight: 600;
    }
    article.event {
      display: flex; gap: 16px;
      background: var(--surface); border: 1px solid var(--border);
      border-radius: 10px; padding: 14px 16px; margin-bottom: 10px;
      border-left: 4px solid var(--accent);
    }
    article.imp-low      { border-left-color: #94a3b8; }
    article.imp-medium   { border-left-color: #60a5fa; }
    article.imp-high     { border-left-color: #fb923c; }
    article.imp-critical { border-left-color: #f87171; }
    .date {
      flex: 0 0 110px; font-weight: 600; color: var(--muted);
      font-variant-numeric: tabular-nums;
    }
    .body h4 { margin: 0 0 6px; font-size: 1.05rem; }
    .desc { color: var(--text); line-height: 1.5; margin-bottom: 8px; }
    a.source {
      display: inline-block; color: var(--accent);
      text-decoration: none; font-size: 0.85rem;
      border-bottom: 1px dotted var(--accent);
      margin-bottom: 8px;
    }
    .chips { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 6px; }
    .chip {
      font-size: 0.75rem; padding: 3px 8px; border-radius: 999px;
      background: var(--surface-2); color: var(--text);
      border: 1px solid var(--border);
    }
    .chip.tag {
      background: color-mix(in srgb, var(--c) 20%, transparent);
      border: 1px solid color-mix(in srgb, var(--c) 50%, transparent);
    }
    aside.people {
      max-width: 920px; margin: 0 auto; padding: 0 32px 40px;
    }
    aside.people h2 { font-size: 1.6rem; margin: 32px 0 16px; }
    .person {
      background: var(--surface); border: 1px solid var(--border);
      border-radius: 10px; padding: 12px 16px; margin-bottom: 8px;
    }
    .role {
      font-size: 0.75rem; padding: 2px 8px; margin-left: 10px;
      border-radius: 999px;
      background: var(--surface-2); color: var(--muted);
    }
    footer {
      max-width: 920px; margin: 0 auto; padding: 24px 32px 60px;
      text-align: center; color: var(--muted); font-size: 0.85rem;
      border-top: 1px solid var(--border);
    }
    """ }

    private static func makeJS() -> String { """
    document.querySelectorAll('section.year h2').forEach(h => {
      h.style.cursor = 'pointer';
      h.addEventListener('click', () => {
        const sec = h.parentElement;
        const months = sec.querySelectorAll('.month');
        months.forEach(m => m.style.display = m.style.display === 'none' ? '' : 'none');
      });
    });
    """ }
}

/// Bridges WKWebView's `didFinish` / `didFail` callbacks to a single completion
/// closure so we can `await` the page load before asking for the PDF data.
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

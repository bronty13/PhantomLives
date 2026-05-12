import Foundation
import MasterClipperCore

@MainActor
enum HtmlExportService {

    /// Build a self-contained HTML report. Every card is **pre-rendered** as
    /// static HTML in the document body so the file works in any environment
    /// — even ones that disable JavaScript entirely (iOS Files preview, some
    /// in-app webviews, email previews, screen-reader extracts).
    ///
    /// The JS layer is a progressive enhancement: if it runs, the search /
    /// persona / status filters dynamically hide non-matching cards. If it
    /// doesn't run, every card stays visible and the user falls back to the
    /// browser's built-in Find-in-Page.
    static func build(clips: [Clip], appState: AppState) -> String {
        let now = ExportService.isoNow()

        // Pre-render each card. All searchable text is folded into a
        // `data-search` attribute (lowercased) so the JS filter is a single
        // includes() per token.
        let cards = clips.map { card(for: $0, appState: appState) }.joined(separator: "\n")

        let personas = Array(Set(clips.map(\.personaCode))).sorted()
        let statuses = Array(Set(clips.map { $0.statusEnum.label })).sorted()

        let personaOptions = personas.map {
            #"<option value="\#(escapeAttr($0))">\#(escapeHtml($0))</option>"#
        }.joined(separator: "")
        let statusOptions = statuses.map {
            #"<option value="\#(escapeAttr($0))">\#(escapeHtml($0))</option>"#
        }.joined(separator: "")

        return """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
        <title>MasterClipper export · \(now)</title>
        <style>
        :root {
          color-scheme: light dark;
          --pad: 14px;
          --bg-card: rgba(127,127,127,0.07);
          --bg-card-strong: rgba(127,127,127,0.14);
          --border: rgba(127,127,127,0.22);
          --muted: #777;
        }
        @media (prefers-color-scheme: dark) { :root { --muted: #aaa; } }
        * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
        html, body { margin: 0; padding: 0; }
        body {
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
          font-size: 16px; line-height: 1.45;
          padding: var(--pad); max-width: 1400px; margin: 0 auto;
        }
        h1 { margin: 0 0 4px; font-size: 1.4em; }
        .meta { color: var(--muted); font-size: 0.9em; margin-bottom: 14px; }
        .filters {
          position: sticky; top: 0; z-index: 10;
          display: flex; flex-wrap: wrap; gap: 8px;
          padding: 10px; margin: 0 -10px 14px;
          background: rgba(127,127,127,0.10);
          backdrop-filter: blur(10px); -webkit-backdrop-filter: blur(10px);
          border-radius: 10px;
        }
        .filters input, .filters select {
          font-size: 16px; padding: 10px 12px; border-radius: 8px;
          border: 1px solid var(--border);
          background: rgba(255,255,255,0.45); flex: 1 1 160px; min-width: 0;
          color: inherit;
        }
        @media (prefers-color-scheme: dark) {
          .filters input, .filters select { background: rgba(0,0,0,0.25); }
        }
        .cards { display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 12px; }
        .card {
          background: var(--bg-card); border: 1px solid var(--border);
          border-radius: 12px; padding: 14px; overflow: hidden;
        }
        .card.hidden { display: none; }
        .card .head { display: flex; align-items: flex-start; gap: 10px; margin-bottom: 8px; }
        .pill {
          display: inline-flex; align-items: center; gap: 4px;
          padding: 4px 10px; border-radius: 999px;
          font-weight: 700; font-size: 0.78em; color: white; flex-shrink: 0;
        }
        .pill::before { content: "♥"; font-size: 0.9em; }
        .title {
          font-weight: 600; font-size: 1.08em;
          word-wrap: break-word; overflow-wrap: break-word;
          flex: 1; min-width: 0;
        }
        .meta-row {
          display: flex; flex-wrap: wrap; gap: 8px;
          font-size: 0.82em; color: var(--muted); margin-bottom: 10px;
        }
        .meta-row .id { font-family: ui-monospace, "SF Mono", monospace; font-size: 0.95em; }
        .chip {
          display: inline-block; padding: 2px 8px; border-radius: 999px;
          background: var(--bg-card-strong); font-size: 0.78em; margin: 2px 3px 0 0;
        }
        .chips { margin: 6px 0 8px; }
        .desc {
          font-size: 0.95em; margin: 6px 0;
          word-wrap: break-word; overflow-wrap: break-word; white-space: pre-wrap;
        }
        details summary {
          cursor: pointer; padding: 8px 0; color: var(--muted);
          font-size: 0.85em; list-style: none; user-select: none;
        }
        details summary::-webkit-details-marker { display: none; }
        details summary::after { content: " ▾"; }
        details[open] summary::after { content: " ▴"; }
        details > .body {
          margin-top: 6px; padding-top: 10px;
          border-top: 1px solid var(--border); font-size: 0.92em;
        }
        .row { margin: 6px 0; word-wrap: break-word; overflow-wrap: break-word; }
        .row .label { display: inline-block; min-width: 100px; color: var(--muted); }
        .postings { display: flex; flex-wrap: wrap; gap: 4px; margin-top: 4px; }
        .post-pill {
          font-size: 0.72em; padding: 2px 6px; border-radius: 4px;
          font-family: ui-monospace, "SF Mono", monospace;
          background: var(--bg-card-strong); color: var(--muted);
        }
        .post-pill.posted { background: rgba(80,200,120,0.25); color: rgb(40,160,90); }
        @media (prefers-color-scheme: dark) {
          .post-pill.posted { color: rgb(120,220,150); }
        }
        @media (max-width: 480px) {
          body { padding: 8px; }
          .filters { padding: 8px; margin: 0 -8px 10px; }
          .card { padding: 12px; border-radius: 10px; }
          .title { font-size: 1em; }
        }
        </style>
        </head>
        <body>

        <h1>MasterClipper export</h1>
        <div class="meta"><span id="visibleCount">\(clips.count)</span> of \(clips.count) clips · exported \(now)</div>

        <div class="filters">
          <input type="search" id="q" placeholder="Search title, description, keywords…" autocorrect="off" autocapitalize="off">
          <select id="persona"><option value="">All personas</option>\(personaOptions)</select>
          <select id="status"><option value="">All statuses</option>\(statusOptions)</select>
        </div>

        <div class="cards" id="cards">
        \(cards)
        </div>

        <noscript>
          <p style="color:#c33;font-size:0.9em;margin-top:14px">JavaScript is disabled — search and filters won't work, but every clip is still visible above.</p>
        </noscript>

        <script>
        (function () {
          var cards   = document.querySelectorAll('.card');
          var qEl     = document.getElementById('q');
          var pEl     = document.getElementById('persona');
          var sEl     = document.getElementById('status');
          var countEl = document.getElementById('visibleCount');
          if (!cards.length || !qEl || !pEl || !sEl || !countEl) return;
          function tokens(t) { return (t || '').trim().toLowerCase().split(/\\s+/).filter(Boolean); }
          function update() {
            var toks = tokens(qEl.value);
            var p = pEl.value, s = sEl.value;
            var visible = 0;
            for (var i = 0; i < cards.length; i++) {
              var card = cards[i];
              var blob = card.getAttribute('data-search') || '';
              var ok = true;
              for (var j = 0; j < toks.length; j++) {
                if (blob.indexOf(toks[j]) === -1) { ok = false; break; }
              }
              if (ok && p && card.getAttribute('data-persona') !== p) ok = false;
              if (ok && s && card.getAttribute('data-status')  !== s) ok = false;
              if (ok) { card.classList.remove('hidden'); visible++; }
              else    { card.classList.add('hidden'); }
            }
            countEl.textContent = visible;
          }
          qEl.addEventListener('input', update);
          pEl.addEventListener('change', update);
          sEl.addEventListener('change', update);
        })();
        </script>
        </body></html>
        """
    }

    // MARK: - Card rendering

    private static func card(for clip: Clip, appState: AppState) -> String {
        let cats = categoryNames(forClip: clip.id, appState: appState)
        let postings = ((try? DatabaseService.shared.fetchPostings(forClip: clip.id)) ?? [])
            .map { p -> (String, String?, String) in
                let site = appState.sites.first(where: { $0.id == p.siteId })
                return (site?.code ?? site?.displayName ?? "", p.postedDate, p.statusEnum.rawValue)
            }
        let personaColor = appState.personas.first(where: { $0.code == clip.personaCode })?.colorHex ?? "#888888"

        // Searchable blob — lowercased, used by the filter JS
        let searchBlob = ([
            clip.id, clip.title, clip.personaCode,
            clip.descriptionRaw, clip.descriptionRefined,
            clip.notes, clip.keywords, clip.performers,
            clip.externalClipId ?? "",
        ] + cats).joined(separator: " ").lowercased()

        // Meta row
        var metaParts: [String] = []
        if let secs = clip.lengthSeconds {
            metaParts.append("<span>⏱ \(escapeHtml(formatLength(secs)))</span>")
        }
        if let cents = clip.priceCents {
            metaParts.append("<span>$\(String(format: "%.2f", Double(cents) / 100))</span>")
        }
        if let g = clip.goLiveDate, !g.isEmpty {
            metaParts.append("<span>📅 \(escapeHtml(g))</span>")
        }
        metaParts.append("<span>\(escapeHtml(clip.statusEnum.label))</span>")
        metaParts.append(#"<span class="id">\#(escapeHtml(clip.id))</span>"#)

        // Categories
        let chipsHtml: String
        if cats.isEmpty {
            chipsHtml = ""
        } else {
            let chips = cats.map { #"<span class="chip">\#(escapeHtml($0))</span>"# }.joined()
            chipsHtml = #"<div class="chips">\#(chips)</div>"#
        }

        // Description (refined preferred)
        let bodyDesc: String
        let preferred = clip.descriptionRefined.isEmpty ? clip.descriptionRaw : clip.descriptionRefined
        if preferred.trimmingCharacters(in: .whitespaces).isEmpty {
            bodyDesc = ""
        } else {
            bodyDesc = #"<div class="desc">\#(escapeHtml(preferred))</div>"#
        }

        // Details: extras + raw fallback + notes + postings
        var detailsParts: [String] = []
        if let ext = clip.externalClipId, !ext.isEmpty {
            detailsParts.append(#"<div class="row"><span class="label">External ID:</span> \#(escapeHtml(ext))</div>"#)
        }
        if !clip.performers.isEmpty {
            detailsParts.append(#"<div class="row"><span class="label">Performers:</span> \#(escapeHtml(clip.performers))</div>"#)
        }
        if !clip.keywords.isEmpty {
            detailsParts.append(#"<div class="row"><span class="label">Keywords:</span> \#(escapeHtml(clip.keywords))</div>"#)
        }
        if let cd = clip.contentDate, !cd.isEmpty {
            detailsParts.append(#"<div class="row"><span class="label">Content date:</span> \#(escapeHtml(cd))</div>"#)
        }
        if !clip.descriptionRefined.isEmpty,
           !clip.descriptionRaw.isEmpty,
           clip.descriptionRefined != clip.descriptionRaw {
            detailsParts.append(#"<div class="row"><span class="label">Raw description:</span></div>"#)
            detailsParts.append(#"<div class="desc">\#(escapeHtml(clip.descriptionRaw))</div>"#)
        }
        if !clip.notes.isEmpty {
            detailsParts.append(#"<div class="row"><span class="label">Notes:</span></div>"#)
            detailsParts.append(#"<div class="desc">\#(escapeHtml(clip.notes))</div>"#)
        }
        if !postings.isEmpty {
            let pills = postings.map { (code, date, status) -> String in
                let cls = status == "posted" ? "post-pill posted" : "post-pill"
                let dateSuffix = date.map { " " + $0 } ?? ""
                return #"<span class="\#(cls)">\#(escapeHtml(code))\#(escapeHtml(dateSuffix))</span>"#
            }.joined()
            detailsParts.append(#"""
                <div class="row"><span class="label">Posted to:</span>
                  <div class="postings">\#(pills)</div>
                </div>
            """#)
        }
        let detailsHtml = detailsParts.isEmpty
            ? ""
            : #"""
                <details>
                  <summary>More details</summary>
                  <div class="body">\#(detailsParts.joined())</div>
                </details>
            """#

        let title = clip.title.isEmpty ? "Untitled" : clip.title
        return #"""
        <article class="card"
                 data-persona="\#(escapeAttr(clip.personaCode))"
                 data-status="\#(escapeAttr(clip.statusEnum.label))"
                 data-search="\#(escapeAttr(searchBlob))">
          <div class="head">
            <span class="pill" style="background:\#(escapeAttr(personaColor))">\#(escapeHtml(clip.personaCode))</span>
            <div class="title">\#(escapeHtml(title))</div>
          </div>
          <div class="meta-row">\#(metaParts.joined())</div>
          \#(chipsHtml)
          \#(bodyDesc)
          \#(detailsHtml)
        </article>
        """#
    }

    // MARK: - Helpers

    private static func categoryNames(forClip id: String, appState: AppState) -> [String] {
        let ids = (try? DatabaseService.shared.categoryIds(forClip: id)) ?? []
        return ids.compactMap { cid in appState.categories.first(where: { $0.id == cid })?.name }
    }

    private static func formatLength(_ secs: Int) -> String {
        let h = secs / 3600, m = (secs % 3600) / 60, s = secs % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    /// HTML escape for element text content.
    private static func escapeHtml(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
         .replacingOccurrences(of: "'", with: "&#39;")
    }

    /// HTML escape for an attribute value (double-quoted). Same as escapeHtml
    /// but kept separate so each call site documents its own intent.
    private static func escapeAttr(_ s: String) -> String { escapeHtml(s) }
}

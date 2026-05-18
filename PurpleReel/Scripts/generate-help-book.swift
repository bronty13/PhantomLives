#!/usr/bin/env swift
//
// Generates the PurpleReel.help bundle from the repo-root .md docs so
// the standard macOS Help menu search field can index and surface
// them. Run before xcodegen — `build-app.sh` does this automatically.
//
// Output layout (Apple Help Book convention):
//
//   Sources/PurpleReel/Resources/PurpleReel.help/
//     Contents/
//       Info.plist
//       Resources/
//         en.lproj/
//           PurpleReelHelp.html         (table of contents page)
//           USER_MANUAL.html
//           INSTALL.html
//           SHORTCUTS.html
//           KYNO_PARITY_ROADMAP.html
//           KYNO_RESEARCH.html
//
// `hiutil` is run by `build-app.sh` after this script to produce the
// search index (.helpindex) inside en.lproj/.
//
// The Markdown → HTML converter is deliberately minimal: handles the
// constructs our docs actually use — ATX headings, paragraphs, lists
// (ordered + unordered), pipe tables, fenced code, inline code, bold,
// italic, links. Not CommonMark-complete; sufficient for our four
// docs.

import Foundation

let fm = FileManager.default
let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
let repoRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let helpRoot = repoRoot
    .appendingPathComponent("Sources/PurpleReel/Resources/PurpleReel.help")
let enLproj = helpRoot
    .appendingPathComponent("Contents/Resources/en.lproj")

let docs: [(file: String, title: String)] = [
    ("USER_MANUAL.md",         "User Manual"),
    ("INSTALL.md",             "Install & Setup"),
    ("SHORTCUTS.md",           "Keyboard Shortcuts"),
    ("KYNO_PARITY_ROADMAP.md", "Roadmap"),
    ("KYNO_RESEARCH.md",       "Kyno Feature Research"),
]

// MARK: - Filesystem setup

try? fm.removeItem(at: helpRoot)
try fm.createDirectory(at: enLproj, withIntermediateDirectories: true)

// MARK: - Bundle Info.plist

let helpBookID = "com.bronty13.PurpleReel.help"
let infoPlist = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
"http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleIdentifier</key>
    <string>\(helpBookID)</string>
    <key>CFBundleName</key>
    <string>PurpleReel Help</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>HPDBookAccessPath</key>
    <string>PurpleReelHelp.html</string>
    <key>HPDBookIconPath</key>
    <string></string>
    <key>HPDBookIndexPath</key>
    <string>PurpleReelHelp.helpindex</string>
    <key>HPDBookTitle</key>
    <string>PurpleReel Help</string>
    <key>HPDBookType</key>
    <string>3</string>
</dict>
</plist>
"""
try infoPlist.write(
    to: helpRoot.appendingPathComponent("Contents/Info.plist"),
    atomically: true, encoding: .utf8)

// MARK: - HTML template

func htmlTemplate(title: String, body: String) -> String {
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="AppleTitle" content="\(escapeAttr(title))">
        <meta name="description" content="\(escapeAttr(title)) — PurpleReel documentation">
        <title>\(escapeHTML(title))</title>
        <style>
            body {
                font: 14px -apple-system, sans-serif;
                color: #222;
                max-width: 720px;
                margin: 20px auto;
                padding: 0 20px;
                line-height: 1.5;
            }
            h1, h2, h3, h4, h5, h6 { color: #111; line-height: 1.25; margin: 1em 0 0.4em; }
            h1 { border-bottom: 1px solid #ddd; padding-bottom: 0.3em; }
            h2 { border-bottom: 1px solid #eee; padding-bottom: 0.2em; margin-top: 1.4em; }
            code { background: #f2f2f2; padding: 1px 4px; border-radius: 3px; font: 12px ui-monospace, Menlo, monospace; }
            pre { background: #f6f6f6; padding: 8px 10px; border-radius: 4px; overflow-x: auto; }
            pre code { background: transparent; padding: 0; }
            table { border-collapse: collapse; margin: 0.8em 0; }
            th, td { padding: 4px 10px; border: 1px solid #ddd; text-align: left; vertical-align: top; }
            th { background: #f6f6f6; }
            a { color: #6a4ac0; text-decoration: none; }
            a:hover { text-decoration: underline; }
            ul, ol { margin: 0.4em 0 0.8em; padding-left: 24px; }
            blockquote { color: #555; border-left: 3px solid #ddd; margin: 0.6em 0; padding: 0.2em 0.8em; }
            hr { border: none; border-top: 1px solid #eee; margin: 1.4em 0; }
            nav.home { font-size: 12px; margin: 0 0 12px; color: #888; }
            nav.home a { color: #6a4ac0; }
        </style>
    </head>
    <body>
        <nav class="home"><a href="PurpleReelHelp.html">← PurpleReel Help home</a></nav>
        \(body)
    </body>
    </html>
    """
}

func escapeHTML(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;")
     .replacingOccurrences(of: "<", with: "&lt;")
     .replacingOccurrences(of: ">", with: "&gt;")
}
func escapeAttr(_ s: String) -> String {
    escapeHTML(s).replacingOccurrences(of: "\"", with: "&quot;")
}

// MARK: - Minimal Markdown → HTML

/// Tiny converter. Tuned for our four docs: ATX headings, paragraphs,
/// fenced code, inline code, bold (** **), italic (* *), [text](url),
/// unordered (-) and ordered (1.) lists, pipe tables, horizontal rules.
///
/// Anti-feature: keeps the implementation small enough to maintain. If
/// we ever need true CommonMark conformance, swap in cmark via SPM.
func markdownToHTML(_ md: String) -> String {
    let lines = md.components(separatedBy: "\n")
    var out: [String] = []
    var i = 0
    var inCodeBlock = false
    var codeBuffer: [String] = []
    var paragraphBuffer: [String] = []

    func flushParagraph() {
        guard !paragraphBuffer.isEmpty else { return }
        let joined = paragraphBuffer.joined(separator: " ")
        out.append("<p>\(inline(joined))</p>")
        paragraphBuffer.removeAll()
    }

    func inline(_ s: String) -> String {
        var t = escapeHTML(s)
        // Inline code first (so emphasis inside doesn't get parsed).
        t = applyRegex(t, #"`([^`]+)`"#) { match, line in
            return "<code>\(match[1])</code>"
        }
        // [text](url)
        t = applyRegex(t, #"\[([^\]]+)\]\(([^)]+)\)"#) { match, _ in
            let label = String(match[1]), url = String(match[2])
            return "<a href=\"\(escapeAttr(url))\">\(label)</a>"
        }
        // Bold ** **
        t = applyRegex(t, #"\*\*([^*]+)\*\*"#) { match, _ in
            return "<strong>\(match[1])</strong>"
        }
        // Italic * *
        t = applyRegex(t, #"(?<![\*])\*([^*]+)\*(?![\*])"#) { match, _ in
            return "<em>\(match[1])</em>"
        }
        return t
    }

    while i < lines.count {
        let line = lines[i]
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Fenced code block
        if trimmed.hasPrefix("```") {
            if inCodeBlock {
                let body = codeBuffer.joined(separator: "\n")
                out.append("<pre><code>\(escapeHTML(body))</code></pre>")
                codeBuffer.removeAll()
                inCodeBlock = false
            } else {
                flushParagraph()
                inCodeBlock = true
            }
            i += 1
            continue
        }
        if inCodeBlock {
            codeBuffer.append(line)
            i += 1
            continue
        }

        // Blank line → paragraph break
        if trimmed.isEmpty {
            flushParagraph()
            i += 1
            continue
        }

        // Horizontal rule
        if trimmed == "---" || trimmed == "***" {
            flushParagraph()
            out.append("<hr>")
            i += 1
            continue
        }

        // ATX heading
        if let heading = parseHeading(trimmed) {
            flushParagraph()
            out.append("<h\(heading.level)>\(inline(heading.text))</h\(heading.level)>")
            i += 1
            continue
        }

        // Pipe table — header line, separator line, then rows.
        if trimmed.hasPrefix("|"),
           i + 1 < lines.count,
           lines[i + 1].trimmingCharacters(in: .whitespaces).contains("---") {
            flushParagraph()
            let headerCells = splitTableRow(trimmed)
            // Skip separator
            i += 2
            var bodyRows: [[String]] = []
            while i < lines.count {
                let row = lines[i].trimmingCharacters(in: .whitespaces)
                if row.hasPrefix("|") {
                    bodyRows.append(splitTableRow(row))
                    i += 1
                } else { break }
            }
            var html = "<table><thead><tr>"
            for cell in headerCells { html += "<th>\(inline(cell))</th>" }
            html += "</tr></thead><tbody>"
            for r in bodyRows {
                html += "<tr>"
                for cell in r { html += "<td>\(inline(cell))</td>" }
                html += "</tr>"
            }
            html += "</tbody></table>"
            out.append(html)
            continue
        }

        // Unordered list
        if trimmed.hasPrefix("- ") {
            flushParagraph()
            var items: [String] = []
            while i < lines.count {
                let t = lines[i].trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("- ") {
                    items.append(String(t.dropFirst(2)))
                    i += 1
                } else { break }
            }
            var html = "<ul>"
            for item in items { html += "<li>\(inline(item))</li>" }
            html += "</ul>"
            out.append(html)
            continue
        }

        // Ordered list — match the `N.` prefix
        if let firstDot = trimmed.firstIndex(of: "."),
           let n = Int(trimmed[..<firstDot]),
           n >= 1,
           firstDot < trimmed.index(before: trimmed.endIndex),
           trimmed[trimmed.index(after: firstDot)] == " " {
            flushParagraph()
            var items: [String] = []
            while i < lines.count {
                let t = lines[i].trimmingCharacters(in: .whitespaces)
                if let fd = t.firstIndex(of: "."),
                   Int(t[..<fd]) != nil,
                   fd < t.index(before: t.endIndex),
                   t[t.index(after: fd)] == " " {
                    items.append(String(t[t.index(fd, offsetBy: 2)...]))
                    i += 1
                } else { break }
            }
            var html = "<ol>"
            for item in items { html += "<li>\(inline(item))</li>" }
            html += "</ol>"
            out.append(html)
            continue
        }

        // Blockquote
        if trimmed.hasPrefix("> ") {
            flushParagraph()
            var quoteLines: [String] = []
            while i < lines.count,
                  lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("> ") {
                quoteLines.append(String(lines[i].trimmingCharacters(in: .whitespaces).dropFirst(2)))
                i += 1
            }
            out.append("<blockquote><p>\(inline(quoteLines.joined(separator: " ")))</p></blockquote>")
            continue
        }

        // Default: paragraph text — accumulate until blank line.
        paragraphBuffer.append(trimmed)
        i += 1
    }
    flushParagraph()
    if !codeBuffer.isEmpty {
        out.append("<pre><code>\(escapeHTML(codeBuffer.joined(separator: "\n")))</code></pre>")
    }
    return out.joined(separator: "\n")
}

func parseHeading(_ s: String) -> (level: Int, text: String)? {
    guard s.hasPrefix("#") else { return nil }
    var level = 0
    var idx = s.startIndex
    while idx < s.endIndex, s[idx] == "#", level < 6 {
        level += 1
        idx = s.index(after: idx)
    }
    guard level > 0, idx < s.endIndex, s[idx] == " " else { return nil }
    let text = String(s[idx...]).trimmingCharacters(in: .whitespaces)
    return (level, text)
}

func splitTableRow(_ s: String) -> [String] {
    var t = s
    if t.hasPrefix("|") { t.removeFirst() }
    if t.hasSuffix("|") { t.removeLast() }
    return t.components(separatedBy: "|").map {
        $0.trimmingCharacters(in: .whitespaces)
    }
}

/// Tiny regex helper that returns transformed text. Matches in
/// order; each replacement closure can read the capture groups.
func applyRegex(_ s: String, _ pattern: String,
                _ transform: (Array<Substring>, String) -> String) -> String {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return s }
    let nss = s as NSString
    var result = ""
    var lastEnd = 0
    let full = NSRange(location: 0, length: nss.length)
    regex.enumerateMatches(in: s, options: [], range: full) { match, _, _ in
        guard let m = match else { return }
        result += nss.substring(with: NSRange(location: lastEnd,
                                                length: m.range.location - lastEnd))
        var groups: [Substring] = []
        for g in 0..<m.numberOfRanges {
            let r = m.range(at: g)
            if r.location == NSNotFound {
                groups.append("")
            } else {
                groups.append(Substring(nss.substring(with: r)))
            }
        }
        result += transform(groups, s)
        lastEnd = m.range.location + m.range.length
    }
    if lastEnd < nss.length {
        result += nss.substring(with: NSRange(location: lastEnd, length: nss.length - lastEnd))
    }
    return result
}

// MARK: - Per-doc HTML emission

for doc in docs {
    let src = repoRoot.appendingPathComponent(doc.file)
    guard let md = try? String(contentsOf: src, encoding: .utf8) else {
        fputs("warning: \(doc.file) not found, skipping\n", stderr)
        continue
    }
    let body = markdownToHTML(md)
    // Rewrite internal .md links to .html so the help pages cross-link
    // correctly inside the .help bundle.
    let bodyRewritten = body
        .replacingOccurrences(of: "USER_MANUAL.md",         with: "USER_MANUAL.html")
        .replacingOccurrences(of: "INSTALL.md",             with: "INSTALL.html")
        .replacingOccurrences(of: "SHORTCUTS.md",           with: "SHORTCUTS.html")
        .replacingOccurrences(of: "KYNO_PARITY_ROADMAP.md", with: "KYNO_PARITY_ROADMAP.html")
        .replacingOccurrences(of: "KYNO_RESEARCH.md", with: "KYNO_RESEARCH.html")
        .replacingOccurrences(of: "README.md",
                                with: "https://github.com/bronty13/PhantomLives/tree/main/PurpleReel")
        .replacingOccurrences(of: "INTEGRATION_TEST_PLAN.md",
                                with: "https://github.com/bronty13/PhantomLives/blob/main/PurpleReel/INTEGRATION_TEST_PLAN.md")
    let html = htmlTemplate(title: doc.title, body: bodyRewritten)
    let outFile = enLproj.appendingPathComponent(
        (doc.file as NSString).deletingPathExtension + ".html")
    try html.write(to: outFile, atomically: true, encoding: .utf8)
}

// MARK: - Table-of-contents landing page

let tocBody = """
<h1>PurpleReel Help</h1>
<p>This help book is bundled inside the app, indexed by macOS so
the Help menu's search field finds matching topics across every doc.</p>
<ul>
\(docs.map { "<li><a href=\"\(($0.file as NSString).deletingPathExtension).html\">\($0.title)</a></li>" }.joined(separator: "\n"))
</ul>
<p>The canonical (Markdown) versions live in the repository alongside
this app's source. They're also reachable via the <strong>Help</strong>
menu in PurpleReel.</p>
"""
let tocHTML = htmlTemplate(title: "PurpleReel Help", body: tocBody)
try tocHTML.write(
    to: enLproj.appendingPathComponent("PurpleReelHelp.html"),
    atomically: true, encoding: .utf8)

print("Wrote \(helpRoot.path) (\(docs.count + 1) HTML pages)")

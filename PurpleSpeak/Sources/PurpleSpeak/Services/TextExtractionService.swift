import Foundation
import AppKit
import PDFKit

/// Pulls readable plain text out of the formats a Speechify-class reader is
/// expected to open: PDF, EPUB, DOCX/DOC, RTF, HTML, plain text, and remote
/// web articles. Each entry point returns `(title, text)` so the caller can
/// seed the library row.
enum TextExtractionService {

    enum ExtractionError: Error, LocalizedError {
        case unsupported(String)
        case empty
        case readFailed(String)

        var errorDescription: String? {
            switch self {
            case .unsupported(let ext): return "Don't know how to read “.\(ext)” files yet."
            case .empty:                return "No readable text was found."
            case .readFailed(let s):    return s
            }
        }
    }

    /// File extensions we can open via `extract(fileURL:)`.
    static let supportedExtensions: Set<String> =
        ["pdf", "epub", "docx", "doc", "rtf", "rtfd", "txt", "text", "md", "markdown", "html", "htm"]

    @MainActor
    static func extract(fileURL url: URL) throws -> (title: String, text: String) {
        let ext = url.pathExtension.lowercased()
        let baseTitle = url.deletingPathExtension().lastPathComponent
        let text: String
        switch ext {
        case "pdf":
            text = try extractPDF(url)
        case "epub":
            text = try extractEPUB(url)
        case "docx", "doc", "rtf", "rtfd":
            text = try extractAttributed(url, ext: ext)
        case "html", "htm":
            text = try extractHTMLFile(url)
        case "txt", "text", "md", "markdown":
            text = try readPlain(url)
        default:
            throw ExtractionError.unsupported(ext)
        }
        let cleaned = normalize(text)
        guard !cleaned.isEmpty else { throw ExtractionError.empty }
        return (baseTitle, cleaned)
    }

    // MARK: - PDF

    static func extractPDF(_ url: URL) throws -> String {
        guard let pdf = PDFDocument(url: url) else {
            throw ExtractionError.readFailed("Couldn't open the PDF.")
        }
        var parts: [String] = []
        for i in 0..<pdf.pageCount {
            if let s = pdf.page(at: i)?.string { parts.append(s) }
        }
        return parts.joined(separator: "\n\n")
    }

    // MARK: - DOCX / RTF (AppKit document readers)

    static func extractAttributed(_ url: URL, ext: String) throws -> String {
        let docType: NSAttributedString.DocumentType
        switch ext {
        case "docx", "doc": docType = .officeOpenXML
        case "rtf":         docType = .rtf
        case "rtfd":        docType = .rtfd
        default:            docType = .plain
        }
        do {
            let attr = try NSAttributedString(
                url: url,
                options: [.documentType: docType],
                documentAttributes: nil
            )
            return attr.string
        } catch {
            // Fall back to letting AppKit sniff the type.
            if let attr = try? NSAttributedString(url: url, options: [:], documentAttributes: nil) {
                return attr.string
            }
            throw ExtractionError.readFailed(error.localizedDescription)
        }
    }

    // MARK: - Plain text

    static func readPlain(_ url: URL) throws -> String {
        if let s = try? String(contentsOf: url, encoding: .utf8) { return s }
        if let s = try? String(contentsOf: url, encoding: .isoLatin1) { return s }
        throw ExtractionError.readFailed("Couldn't decode the text file.")
    }

    // MARK: - HTML

    @MainActor
    static func extractHTMLFile(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return try htmlToText(data)
    }

    /// Strip HTML to plain text via AppKit's HTML reader (handles entities,
    /// block structure, etc.). Must run on the main thread — NSAttributedString
    /// HTML import touches WebKit internals.
    @MainActor
    static func htmlToText(_ data: Data) throws -> String {
        let attr = try NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.html,
                      .characterEncoding: String.Encoding.utf8.rawValue],
            documentAttributes: nil
        )
        return attr.string
    }

    // MARK: - Web articles

    /// Fetch a URL and reduce it to article text. The readability pass is a
    /// pragmatic heuristic: prefer the first <article>…</article>, else <main>,
    /// else <body>; strip <script>/<style>; then hand the reduced HTML to the
    /// AppKit HTML reader for entity/tag handling.
    @MainActor
    static func extractWebArticle(_ pageURL: URL) async throws -> (title: String, text: String) {
        let (data, _) = try await URLSession.shared.data(from: pageURL)
        guard let html = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
            throw ExtractionError.readFailed("Couldn't decode the page.")
        }
        let title = firstMatch(in: html, pattern: "<title[^>]*>(.*?)</title>")
            .map { stripTags($0) } ?? pageURL.host ?? "Web article"

        let reduced = readabilityReduce(html)
        let text = try htmlToText(Data(reduced.utf8))
        let cleaned = normalize(text)
        guard !cleaned.isEmpty else { throw ExtractionError.empty }
        return (title.trimmingCharacters(in: .whitespacesAndNewlines), cleaned)
    }

    private static func readabilityReduce(_ html: String) -> String {
        var s = html
        // Drop script/style/nav/header/footer/aside blocks.
        for tag in ["script", "style", "noscript", "nav", "header", "footer", "aside", "form"] {
            s = remove(blockTag: tag, from: s)
        }
        if let article = firstMatch(in: s, pattern: "<article[^>]*>([\\s\\S]*?)</article>") {
            return article
        }
        if let main = firstMatch(in: s, pattern: "<main[^>]*>([\\s\\S]*?)</main>") {
            return main
        }
        if let body = firstMatch(in: s, pattern: "<body[^>]*>([\\s\\S]*?)</body>") {
            return body
        }
        return s
    }

    private static func remove(blockTag tag: String, from html: String) -> String {
        let pattern = "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>"
        return html.replacingOccurrences(of: pattern, with: " ",
                                         options: [.regularExpression, .caseInsensitive])
    }

    private static func stripTags(_ s: String) -> String {
        s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
         .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstMatch(in s: String, pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    // MARK: - EPUB

    /// Unzip the EPUB, read the OPF spine for reading order, concatenate the
    /// referenced XHTML documents, and strip them to text. Falls back to a
    /// filename-sorted sweep of all (x)html if the OPF can't be parsed.
    @MainActor
    static func extractEPUB(_ url: URL) throws -> String {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory
            .appendingPathComponent("ps-epub-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        try unzip(url, to: staging)

        let orderedDocs = epubSpineDocuments(in: staging)
            ?? fallbackHTMLDocuments(in: staging)
        guard !orderedDocs.isEmpty else { throw ExtractionError.empty }

        var parts: [String] = []
        for doc in orderedDocs {
            if let data = try? Data(contentsOf: doc),
               let text = try? htmlToText(data) {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { parts.append(trimmed) }
            }
        }
        return parts.joined(separator: "\n\n")
    }

    /// Locate the OPF via META-INF/container.xml, then resolve <spine> idrefs
    /// to <manifest> hrefs, returning the chapter files in reading order.
    private static func epubSpineDocuments(in root: URL) -> [URL]? {
        let containerURL = root.appendingPathComponent("META-INF/container.xml")
        guard let containerXML = try? String(contentsOf: containerURL, encoding: .utf8),
              let opfRel = firstMatch(in: containerXML, pattern: "full-path=\"([^\"]+)\"")
        else { return nil }

        let opfURL = root.appendingPathComponent(opfRel)
        let opfDir = opfURL.deletingLastPathComponent()
        guard let opf = try? String(contentsOf: opfURL, encoding: .utf8) else { return nil }

        // manifest: id -> href
        var manifest: [String: String] = [:]
        if let re = try? NSRegularExpression(pattern: "<item\\b[^>]*>", options: [.caseInsensitive]) {
            let ns = opf as NSString
            for m in re.matches(in: opf, range: NSRange(location: 0, length: ns.length)) {
                let item = ns.substring(with: m.range)
                if let id = firstMatch(in: item, pattern: "id=\"([^\"]+)\""),
                   let href = firstMatch(in: item, pattern: "href=\"([^\"]+)\"") {
                    manifest[id] = href
                }
            }
        }
        // spine order: itemref idref="..."
        var ordered: [URL] = []
        if let re = try? NSRegularExpression(pattern: "<itemref\\b[^>]*idref=\"([^\"]+)\"", options: [.caseInsensitive]) {
            let ns = opf as NSString
            for m in re.matches(in: opf, range: NSRange(location: 0, length: ns.length)) where m.numberOfRanges > 1 {
                let idref = ns.substring(with: m.range(at: 1))
                if let href = manifest[idref] {
                    ordered.append(opfDir.appendingPathComponent(href))
                }
            }
        }
        return ordered.isEmpty ? nil : ordered
    }

    private static func fallbackHTMLDocuments(in root: URL) -> [URL] {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        var found: [URL] = []
        for case let u as URL in en {
            let e = u.pathExtension.lowercased()
            if e == "xhtml" || e == "html" || e == "htm" { found.append(u) }
        }
        return found.sorted { $0.path < $1.path }
    }

    private static func unzip(_ archive: URL, to dest: URL) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        proc.arguments = ["-q", "-o", archive.path, "-d", dest.path]
        let errPipe = Pipe()
        proc.standardError = errPipe
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            let err = String(data: errPipe.fileHandleForReading.availableData, encoding: .utf8) ?? ""
            throw ExtractionError.readFailed("unzip exit \(proc.terminationStatus): \(err)")
        }
    }

    // MARK: - Normalization

    /// Collapse runs of blank lines and trailing whitespace so the reader
    /// pane and highlight ranges aren't thrown off by PDF/HTML artifacts.
    static func normalize(_ text: String) -> String {
        var s = text.replacingOccurrences(of: "\r\n", with: "\n")
        s = s.replacingOccurrences(of: "\r", with: "\n")
        // Collapse 3+ newlines to 2.
        s = s.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        // Strip trailing spaces on each line.
        s = s.replacingOccurrences(of: "[ \\t]+\n", with: "\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

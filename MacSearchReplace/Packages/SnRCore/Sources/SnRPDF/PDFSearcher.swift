import Foundation
import PDFKit
import SnRSearch

/// Read-only PDF text search.
///
/// PDFKit gives us per-page text but not per-line numbering, so we synthesize
/// "lines" by splitting on `\n` within each page and report (page, lineInPage)
/// using the `Hit.line` field encoded as `pageNumber * 10000 + lineInPage`.
/// Replace is intentionally unsupported (PDF text replace is unsafe in
/// general).
public struct PDFSearcher: Sendable {

    public init() {}

    public static func isPDF(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "pdf"
    }

    public func search(
        url: URL,
        pattern: String,
        kind: SearchSpec.PatternKind,
        caseInsensitive: Bool
    ) throws -> FileMatches? {
        guard let doc = PDFDocument(url: url) else { return nil }

        let regex: NSRegularExpression
        do {
            let pat = (kind == .literal) ? NSRegularExpression.escapedPattern(for: pattern) : pattern
            var opts: NSRegularExpression.Options = []
            if caseInsensitive { opts.insert(.caseInsensitive) }
            regex = try NSRegularExpression(pattern: pat, options: opts)
        }

        var hits: [Hit] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i), let text = page.string else { continue }
            let pageNumber = i + 1
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            for (lineIdx, line) in lines.enumerated() {
                let ns = line as NSString
                regex.enumerateMatches(
                    in: line,
                    range: NSRange(location: 0, length: ns.length)
                ) { result, _, _ in
                    guard let r = result else { return }
                    let matched = ns.substring(with: r.range)
                    hits.append(Hit(
                        line: pageNumber * 10000 + (lineIdx + 1),
                        columnStart: r.range.location + 1,
                        columnEnd: r.range.location + r.range.length + 1,
                        byteStart: r.range.location,
                        byteEnd: r.range.location + r.range.length,
                        preview: line,
                        matchedText: matched
                    ))
                }
            }
        }
        guard !hits.isEmpty else { return nil }
        return FileMatches(url: url, hits: hits)
    }

    public static func decodeLine(_ encoded: Int) -> (page: Int, lineInPage: Int) {
        (encoded / 10000, encoded % 10000)
    }
}

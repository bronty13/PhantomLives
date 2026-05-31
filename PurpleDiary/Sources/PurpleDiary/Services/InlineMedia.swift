import Foundation

/// Inline media in an entry body. An attachment can be placed *within* the
/// Markdown text — with a caption and any prose before/after — using a Markdown
/// image whose URL is our private scheme:
///
///     ![caption](pd-attachment://<attachmentId>)
///
/// In **Write** mode this is just text you can move or recaption; in **Preview**
/// the referenced attachment renders in place (`MarkdownEditor`). The same
/// attachment still appears in the strip for management. Pure + testable.
enum InlineMedia {

    static let scheme = "pd-attachment://"

    /// Build a body reference for an attachment.
    static func ref(attachmentId: String, caption: String = "") -> String {
        "![\(caption)](\(scheme)\(attachmentId))"
    }

    enum Segment: Equatable {
        case text(String)
        case media(id: String, caption: String)
    }

    /// Split a body into text / inline-media segments, in order. Text around and
    /// between media refs is preserved exactly (that's the "story").
    static func parse(_ body: String) -> [Segment] {
        guard let re = try? NSRegularExpression(
            pattern: "!\\[([^\\]]*)\\]\\(\(NSRegularExpression.escapedPattern(for: scheme))([^)]+)\\)")
        else { return [.text(body)] }

        let ns = body as NSString
        var segments: [Segment] = []
        var cursor = 0
        re.enumerateMatches(in: body, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match else { return }
            if match.range.location > cursor {
                segments.append(.text(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))))
            }
            let caption = ns.substring(with: match.range(at: 1))
            let id = ns.substring(with: match.range(at: 2))
            segments.append(.media(id: id, caption: caption))
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length {
            segments.append(.text(ns.substring(from: cursor)))
        }
        return segments.isEmpty ? [.text(body)] : segments
    }

    /// True if the body has at least one inline media ref (lets the editor skip
    /// the block renderer when there's nothing inline).
    static func hasInlineMedia(_ body: String) -> Bool {
        body.contains(scheme)
    }

    /// Rewrite Day One `dayone-moment://<id>` refs into our attachment refs using
    /// a moment-id → attachment-id map (built after importing the media). Refs
    /// with no mapped attachment fall back to a readable marker so nothing breaks
    /// and the position/caption are still kept.
    static func rewriteDayOneBody(_ body: String, momentToAttachment: [String: String]) -> String {
        // Day One uses `dayone-moment://<id>` for photos and
        // `dayone-moment:/video/<id>` (single slash) for video/audio/pdf — so
        // allow 1–2 slashes after the colon, then an optional kind segment.
        guard let re = try? NSRegularExpression(
            pattern: "!?\\[([^\\]]*)\\]\\(dayone-moment:/{1,2}(?:(video|audio|pdf)/)?([^)]+)\\)")
        else { return body }
        let ns = body as NSString
        var result = ""
        var cursor = 0
        re.enumerateMatches(in: body, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match else { return }
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let caption = ns.substring(with: match.range(at: 1))
            let kind = match.range(at: 2).location != NSNotFound ? ns.substring(with: match.range(at: 2)) : ""
            let momentId = ns.substring(with: match.range(at: 3))
            if let attId = momentToAttachment[momentId] {
                result += ref(attachmentId: attId, caption: caption)
            } else {
                let glyph = kind == "video" ? "🎬" : kind == "audio" ? "🎵" : kind == "pdf" ? "📄" : "📷"
                let cap = caption.trimmingCharacters(in: .whitespaces)
                result += cap.isEmpty ? "\(glyph) photo" : "\(glyph) \(cap)"
            }
            cursor = match.range.location + match.range.length
        }
        result += ns.substring(from: cursor)
        return result
    }
}

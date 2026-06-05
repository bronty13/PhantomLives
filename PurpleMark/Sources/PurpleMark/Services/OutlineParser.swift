import Foundation

/// A heading in the document outline (TOC).
struct OutlineItem: Identifiable, Equatable {
    let id = UUID()
    let level: Int        // 1…6
    let title: String
    let line: Int         // 0-based line index of the heading
}

/// Live document statistics for the status bar.
struct DocStats: Equatable {
    var words: Int = 0
    var characters: Int = 0
    var lines: Int = 0
    var readMinutes: Int = 0
}

/// Parses markdown text for the outline sidebar and the status-bar counts.
/// Deliberately lightweight — a single linear scan, no full markdown parse.
enum OutlineParser {
    /// Extracts ATX headings (`#`…`######`). Skips headings inside fenced code
    /// blocks so a `# comment` line in a code sample doesn't pollute the TOC.
    static func outline(from text: String) -> [OutlineItem] {
        var items: [OutlineItem] = []
        var inFence = false
        var fenceMarker = ""
        let lines = text.components(separatedBy: "\n")
        for (index, raw) in lines.enumerated() {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            // Track ``` / ~~~ fenced code blocks.
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let marker = String(trimmed.prefix(3))
                if !inFence {
                    inFence = true; fenceMarker = marker
                } else if trimmed.hasPrefix(fenceMarker) {
                    inFence = false
                }
                continue
            }
            guard !inFence, trimmed.hasPrefix("#") else { continue }
            var level = 0
            for ch in trimmed { if ch == "#" { level += 1 } else { break } }
            guard level >= 1, level <= 6 else { continue }
            let rest = trimmed.dropFirst(level)
            // A valid ATX heading requires a space after the #'s.
            guard rest.first == " " || rest.isEmpty else { continue }
            let title = rest.trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { continue }
            items.append(OutlineItem(level: level, title: title, line: index))
        }
        return items
    }

    static func stats(from text: String) -> DocStats {
        var s = DocStats()
        s.characters = text.count
        s.lines = text.isEmpty ? 0 : text.components(separatedBy: "\n").count
        let words = text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
        s.words = words.count
        s.readMinutes = max(1, Int((Double(s.words) / 200.0).rounded(.up)))
        if s.words == 0 { s.readMinutes = 0 }
        return s
    }
}

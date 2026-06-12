import Foundation

/// A heading in the document outline (TOC).
struct OutlineItem: Identifiable, Equatable, Sendable {
    let id = UUID()
    let level: Int        // 1…6
    let title: String
    let line: Int         // 0-based line index of the heading

    static func == (lhs: OutlineItem, rhs: OutlineItem) -> Bool {
        lhs.level == rhs.level && lhs.title == rhs.title && lhs.line == rhs.line
    }
}

/// Live document statistics for the status bar.
struct DocStats: Equatable, Sendable {
    var words: Int = 0
    var characters: Int = 0
    var lines: Int = 0
    var readMinutes: Int = 0
}

/// Convenience wrappers over `DocumentIndex` (the single-pass scanner). Kept as
/// the stable API for callers/tests that only need one piece; the app itself
/// builds a full `DocumentIndex` once per (debounced) edit instead.
enum OutlineParser {
    /// Extracts ATX headings (`#`…`######`), skipping fenced code blocks.
    static func outline(from text: String) -> [OutlineItem] {
        DocumentIndex.build(from: text).outline
    }

    static func stats(from text: String) -> DocStats {
        DocumentIndex.build(from: text).stats
    }
}

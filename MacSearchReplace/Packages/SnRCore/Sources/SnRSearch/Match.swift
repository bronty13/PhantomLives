import Foundation

/// A normalized representation of one search "hit" — a contiguous span of
/// bytes/characters within a single file that matched the search criteria.
public struct Hit: Sendable, Identifiable, Hashable {
    public let id: UUID
    public let line: Int           // 1-based line number (0 for binary mode)
    public let columnStart: Int    // 1-based UTF-16 column start
    public let columnEnd: Int
    public let byteStart: Int
    public let byteEnd: Int
    public let preview: String     // surrounding line(s), trimmed
    public let matchedText: String
    public var replacement: String?
    public var accepted: Bool

    public init(
        id: UUID = UUID(),
        line: Int,
        columnStart: Int,
        columnEnd: Int,
        byteStart: Int,
        byteEnd: Int,
        preview: String,
        matchedText: String,
        replacement: String? = nil,
        accepted: Bool = true
    ) {
        self.id = id
        self.line = line
        self.columnStart = columnStart
        self.columnEnd = columnEnd
        self.byteStart = byteStart
        self.byteEnd = byteEnd
        self.preview = preview
        self.matchedText = matchedText
        self.replacement = replacement
        self.accepted = accepted
    }
}

/// All hits within a single file.
public struct FileMatches: Sendable, Identifiable, Hashable {
    public var id: URL { url }
    public let url: URL
    public var hits: [Hit]

    public init(url: URL, hits: [Hit]) {
        self.url = url
        self.hits = hits
    }
}

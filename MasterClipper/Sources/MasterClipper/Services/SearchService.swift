import Foundation

enum SearchService {

    /// Tokenize on whitespace, AND-search across the indicated columns.
    /// Empty input matches nothing-special — caller should skip applying the filter.
    static func matches(clip: Clip, query: String, includeNotes: Bool) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return true }

        let tokens = trimmed
            .split(whereSeparator: { $0.isWhitespace })
            .map { String($0).lowercased() }

        var fields: [String] = [
            clip.title,
            clip.descriptionRaw,
            clip.descriptionRefined,
            clip.keywords,
            clip.performers,
            clip.trackingTag ?? "",
            clip.externalClipId ?? "",
            clip.id,
        ]
        if includeNotes { fields.append(clip.notes) }

        let haystack = fields.joined(separator: "\n").lowercased()
        return tokens.allSatisfy { haystack.contains($0) }
    }
}

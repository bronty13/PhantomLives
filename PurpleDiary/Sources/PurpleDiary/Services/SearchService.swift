import Foundation

/// Ranked, in-memory search across entries. Mirrors Timeliner's ranking
/// philosophy: title-prefix beats title-substring beats body match. Operates
/// on the already-loaded `[Entry]` slice so it stays instant for a personal
/// journal's row counts (no FTS table needed yet — revisit if a journal grows
/// past tens of thousands of entries).
enum SearchService {

    struct Result: Identifiable, Hashable {
        let entry: Entry
        let score: Int
        var id: String { entry.id }
    }

    /// Higher score = better match. Entries with no match are dropped.
    /// - 100: title starts with the query
    /// -  60: title contains the query
    /// -  30: body contains the query
    /// -  20: a tag name contains the query
    static func search(
        _ query: String,
        in entries: [Entry],
        tagsByEntry: [String: [Tag]] = [:],
        peopleByEntry: [String: [Person]] = [:]
    ) -> [Result] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else {
            // Empty query → all entries, newest first, neutral score.
            return entries
                .sorted { $0.date > $1.date }
                .map { Result(entry: $0, score: 0) }
        }

        var results: [Result] = []
        for entry in entries {
            var score = 0
            let title = entry.title.lowercased()
            if title.hasPrefix(q) {
                score = max(score, 100)
            } else if title.contains(q) {
                score = max(score, 60)
            }
            if entry.bodyMarkdown.lowercased().contains(q) {
                score = max(score, 30)
            }
            if let tags = tagsByEntry[entry.id],
               tags.contains(where: { $0.name.lowercased().contains(q) }) {
                score = max(score, 20)
            }
            if let people = peopleByEntry[entry.id],
               people.contains(where: { $0.name.lowercased().contains(q) }) {
                score = max(score, 20)
            }
            if score > 0 {
                results.append(Result(entry: entry, score: score))
            }
        }
        // Sort by score desc, then newest first as a stable tiebreaker.
        return results.sorted {
            $0.score != $1.score ? $0.score > $1.score : $0.entry.date > $1.entry.date
        }
    }
}

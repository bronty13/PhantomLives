import Foundation
import SwiftUI

/// Cross-case ranked search across the in-memory model. Pure function on
/// the data slices the caller passes in, so it's trivial to unit-test.
enum SearchService {
    enum Kind: Hashable {
        case case_
        case event(caseId: String)
        case person(caseId: String)
        case tag

        var label: String {
            switch self {
            case .case_:  return "Case"
            case .event:  return "Event"
            case .person: return "Person"
            case .tag:    return "Tag"
            }
        }

        var systemImage: String {
            switch self {
            case .case_:  return "folder.fill"
            case .event:  return "calendar.badge.clock"
            case .person: return "person.fill"
            case .tag:    return "tag.fill"
            }
        }

        var tint: Color {
            switch self {
            case .case_:  return .blue
            case .event:  return .purple
            case .person: return .green
            case .tag:    return .orange
            }
        }
    }

    struct Hit: Identifiable, Hashable {
        let id: String          // composite "kind:rowID" so SwiftUI lists are stable
        let kind: Kind
        let title: String
        let subtitle: String
        let score: Int
    }

    /// Score: title-prefix > title-substring > body/notes substring.
    /// Higher is better. Ties broken by kind priority (cases first).
    static func run(
        query: String,
        cases: [Case],
        events: [Event],
        people: [Person],
        tags: [Tag],
        tagsByEvent: [String: [Tag]]
    ) -> [Hit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }

        var hits: [Hit] = []

        for c in cases {
            if let s = score(text: c.title, body: c.caseDescription, query: q) {
                hits.append(Hit(
                    id: "case:\(c.id)",
                    kind: .case_,
                    title: c.title.isEmpty ? "Untitled case" : c.title,
                    subtitle: c.caseDescription,
                    score: s
                ))
            }
        }
        for e in events {
            if let s = score(text: e.title, body: e.descriptionMarkdown, query: q) {
                let date = e.parsedStart?.formatted(date: .abbreviated, time: .omitted) ?? ""
                hits.append(Hit(
                    id: "event:\(e.id)",
                    kind: .event(caseId: e.caseId),
                    title: e.title.isEmpty ? "Untitled event" : e.title,
                    subtitle: [date, e.descriptionMarkdown].filter { !$0.isEmpty }.joined(separator: " — "),
                    score: s
                ))
            }
        }
        for p in people {
            if let s = score(text: p.name, body: p.notes, query: q) {
                hits.append(Hit(
                    id: "person:\(p.id)",
                    kind: .person(caseId: p.caseId),
                    title: p.name.isEmpty ? "Unnamed" : p.name,
                    subtitle: p.roleEnum.label + (p.notes.isEmpty ? "" : " — \(p.notes)"),
                    score: s
                ))
            }
        }
        for t in tags {
            if let s = score(text: t.name, body: "", query: q) {
                hits.append(Hit(
                    id: "tag:\(t.rowId ?? -1)",
                    kind: .tag,
                    title: t.name,
                    subtitle: "",
                    score: s
                ))
            }
        }

        // Stable sort: score desc, then kind priority, then title asc.
        return hits.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if priority(lhs.kind) != priority(rhs.kind) { return priority(lhs.kind) < priority(rhs.kind) }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private static func score(text: String, body: String, query: String) -> Int? {
        let title = text.lowercased()
        let body = body.lowercased()
        if title == query { return 100 }
        if title.hasPrefix(query) { return 80 }
        if title.contains(query) { return 60 }
        if body.contains(query) { return 30 }
        return nil
    }

    private static func priority(_ kind: Kind) -> Int {
        switch kind {
        case .case_:  return 0
        case .event:  return 1
        case .person: return 2
        case .tag:    return 3
        }
    }
}

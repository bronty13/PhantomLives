import Foundation

/// Aggregates all TimeEntry rows by Initiative or Goal and renders a
/// Markdown report. Useful for monthly reviews and stakeholder updates.
enum TimeByTagReport {

    enum GroupBy { case initiative, goal }

    static func render(group: GroupBy,
                       matters: [Matter],
                       entries: [TimeEntry],
                       initiatives: [Initiative],
                       goals: [Goal],
                       matterInitiativeIds: [String: Set<String>],
                       matterGoalIds: [String: Set<String>],
                       since: Date? = nil) -> String {
        let mattersById = Dictionary(uniqueKeysWithValues: matters.map { ($0.id, $0) })
        let cutoff = since ?? .distantPast

        var byTag: [String: Int] = [:]   // tagId -> seconds
        var unmapped: Int = 0
        for e in entries where e.startedAt >= cutoff {
            guard let m = mattersById[e.matterId] else { continue }
            let tags: Set<String>
            switch group {
            case .initiative: tags = matterInitiativeIds[m.id] ?? []
            case .goal:       tags = matterGoalIds[m.id] ?? []
            }
            if tags.isEmpty {
                unmapped += e.seconds
            } else {
                // Split time evenly across each tag — simple, predictable, and
                // documented in the user manual.
                let share = e.seconds / max(1, tags.count)
                for t in tags { byTag[t, default: 0] += share }
            }
        }
        let names: [String: String]
        switch group {
        case .initiative: names = Dictionary(uniqueKeysWithValues: initiatives.map { ($0.id, $0.name) })
        case .goal:       names = Dictionary(uniqueKeysWithValues: goals.map { ($0.id, $0.name) })
        }
        let title = group == .initiative ? "Initiative" : "Goal"
        var out = "# Time by \(title)\n\n"
        if let s = since {
            out += "_Since: \(s.formatted(date: .abbreviated, time: .omitted))_\n\n"
        }
        out += "| \(title) | Hours |\n|---|---:|\n"
        let rows = byTag.map { ($0.key, $0.value) }
            .sorted { $0.1 > $1.1 }
        for (tagId, seconds) in rows {
            let n = names[tagId] ?? tagId
            out += "| \(n) | \(String(format: "%.2f", Double(seconds) / 3600.0)) |\n"
        }
        if unmapped > 0 {
            out += "| _(no \(title.lowercased()) tagged)_ | \(String(format: "%.2f", Double(unmapped) / 3600.0)) |\n"
        }
        return out
    }
}

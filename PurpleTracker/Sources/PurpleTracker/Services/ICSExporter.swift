import Foundation

/// Writes a one-shot `.ics` file containing one VEVENT per open Matter that
/// has a due date. Subscribe to the file from Calendar.app (File →
/// New Calendar Subscription → file://…). Re-export to refresh.
enum ICSExporter {

    @MainActor
    static func render(matters: [Matter], statusValues: [(name: String, sortOrder: Int)]) -> String {
        let terminal = statusValues.last?.name ?? "Closed"
        let open = matters.filter { $0.status != terminal && $0.dueAt != nil && $0.deletedAt == nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        let stamp = f.string(from: Date()).replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ":", with: "")
        var out = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//PurpleTracker//1.3//EN
        CALSCALE:GREGORIAN
        METHOD:PUBLISH
        """
        for m in open {
            guard let due = m.dueAt else { continue }
            let dueStr = f.string(from: due).replacingOccurrences(of: "-", with: "")
                .replacingOccurrences(of: ":", with: "")
            let uid = "purpletracker-\(m.id)@local"
            let summary = escape("\(m.id) — \(m.title.isEmpty ? "(untitled)" : m.title)")
            out += """

            BEGIN:VEVENT
            UID:\(uid)
            DTSTAMP:\(stamp)
            DTSTART:\(dueStr)
            DTEND:\(dueStr)
            SUMMARY:\(summary)
            DESCRIPTION:Status: \(escape(m.status))\\nPriority: \(escape(m.priority))
            END:VEVENT
            """
        }
        out += "\nEND:VCALENDAR\n"
        return out
    }

    @MainActor
    static func write(matters: [Matter],
                      statusValues: [(name: String, sortOrder: Int)],
                      settingsStore: SettingsStore) throws -> URL {
        let body = render(matters: matters, statusValues: statusValues)
        let dir = settingsStore.resolvedExportDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("PurpleTracker-Due.ics")
        try body.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}

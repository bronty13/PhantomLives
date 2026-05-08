import SwiftUI

/// Append-only audit log for the Matter — surfaces every status / priority /
/// type / title change plus soft-delete / restore events. Newest first.
struct HistoryTab: View {
    let matter: Matter
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if app.auditEvents.isEmpty {
                ContentUnavailableView("No history yet", systemImage: "clock.arrow.circlepath",
                    description: Text("Changes to status, priority, type, or title will appear here."))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical)
            } else {
                ForEach(app.auditEvents) { e in
                    HStack(alignment: .top) {
                        Image(systemName: icon(for: e.kind))
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        VStack(alignment: .leading) {
                            Text(headline(for: e)).font(.body)
                            Text(e.ts.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
            }
        }
    }

    private func icon(for kind: String) -> String {
        switch kind {
        case "status":   return "circle.lefthalf.filled"
        case "priority": return "exclamationmark.triangle"
        case "type":     return "tag"
        case "title":    return "pencil"
        case "deleted":  return "trash"
        case "restored": return "arrow.uturn.backward"
        default:         return "circle"
        }
    }

    private func headline(for e: AuditEvent) -> String {
        switch e.kind {
        case "deleted":  return "Moved to Trash"
        case "restored": return "Restored from Trash"
        case "created":  return "Created"
        default:
            return "\(e.kind.capitalized): \"\(e.beforeValue)\" → \"\(e.afterValue)\""
        }
    }
}

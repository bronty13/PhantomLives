import SwiftUI

/// Master list of soft-deleted Matters. Drives `TrashView` which shows the
/// detail of the currently-selected trashed Matter.
struct TrashListView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        List(app.trashedMatters, selection: Binding(
            get: { app.selectedMatterId },
            set: { if let id = $0 { app.selectedMatterId = id } }
        )) { m in
            VStack(alignment: .leading) {
                Text(m.title.isEmpty ? "(untitled)" : m.title)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(m.id).font(.system(.caption, design: .monospaced))
                    if let d = m.deletedAt {
                        Text("deleted \(d.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .tag(m.id)
        }
        .navigationTitle("Trash (\(app.trashedMatters.count))")
    }
}

/// Detail pane for a trashed Matter — read-only summary plus Restore / Purge
/// buttons. Trashed Matters are auto-purged 30 days after deletion on launch.
struct TrashView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        if let id = app.selectedMatterId,
           let m = app.trashedMatters.first(where: { $0.id == id }) {
            VStack(alignment: .leading, spacing: 16) {
                Text(m.title.isEmpty ? "(untitled)" : m.title)
                    .font(.title2.bold())
                Text(m.id).font(.system(.title3, design: .monospaced))
                if let d = m.deletedAt {
                    Label("Deleted \(d.formatted(date: .complete, time: .shortened))",
                          systemImage: "trash")
                        .foregroundStyle(.secondary)
                }
                Text("Trashed Matters are permanently purged 30 days after deletion.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button {
                        try? app.restoreMatter(id: m.id)
                    } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
                        .buttonStyle(.borderedProminent)
                    Button(role: .destructive) {
                        try? app.purgeMatter(id: m.id)
                    } label: { Label("Delete Permanently", systemImage: "trash.fill") }
                }
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ContentUnavailableView(
                "Trash is empty",
                systemImage: "trash",
                description: Text("Soft-deleted Matters appear here. They are purged after 30 days.")
            )
        }
    }
}

import SwiftUI

struct MatterListView: View {
    @EnvironmentObject var app: AppState
    @State private var multiSelection: Set<String> = []
    @State private var showBulkPriority: Bool = false
    @State private var bulkPriority: MatterPriority = .p3Medium

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search Matter ID, title, content, or person", text: $app.searchQuery)
                    .textFieldStyle(.plain)
                if !app.searchQuery.isEmpty {
                    Button { app.searchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.10))

            List(selection: $multiSelection) {
                ForEach(app.filteredMatters) { m in
                    MatterRow(matter: m)
                        .tag(m.id)
                        .contextMenu {
                            if multiSelection.count > 1, multiSelection.contains(m.id) {
                                Section("\(multiSelection.count) selected") {
                                    Menu("Set Priority") {
                                        ForEach(MatterPriority.allCases) { p in
                                            Button(p.rawValue) { bulkSetPriority(p) }
                                        }
                                    }
                                    Menu("Set Status") {
                                        ForEach(app.statusValues, id: \.name) { sv in
                                            Button(sv.name) { bulkSetStatus(sv.name) }
                                        }
                                    }
                                    Button(role: .destructive) {
                                        bulkSoftDelete()
                                    } label: { Label("Move to Trash", systemImage: "trash") }
                                }
                            } else {
                                Menu("Set Priority") {
                                    ForEach(MatterPriority.allCases) { p in
                                        Button(p.rawValue) { setPriority(matter: m, p) }
                                    }
                                }
                                Button(role: .destructive) {
                                    try? app.deleteMatter(id: m.id)
                                } label: { Label("Move to Trash", systemImage: "trash") }
                            }
                        }
                }
            }
            .listStyle(.inset)
            .onChange(of: multiSelection) { _, newSel in
                // Single-tap behavior preserved: when exactly one is selected,
                // update the active Matter so the detail pane follows.
                if newSel.count == 1, let id = newSel.first {
                    app.selectMatter(id: id)
                }
            }
        }
        .navigationTitle(navigationTitle)
    }

    private func setPriority(matter: Matter, _ p: MatterPriority) {
        var x = matter; x.priority = p.rawValue
        try? app.updateMatter(x)
    }

    private func bulkSetPriority(_ p: MatterPriority) {
        for id in multiSelection {
            if var m = app.matters.first(where: { $0.id == id }) {
                m.priority = p.rawValue
                try? app.updateMatter(m)
            }
        }
    }
    private func bulkSetStatus(_ s: String) {
        for id in multiSelection {
            if let m = app.matters.first(where: { $0.id == id }) {
                try? app.updateMatterStatus(m, to: s)
            }
        }
    }
    private func bulkSoftDelete() {
        for id in multiSelection { try? app.deleteMatter(id: id) }
        multiSelection.removeAll()
    }

    private var navigationTitle: String {
        switch app.sidebarSection {
        case .all: return "All Matters (\(app.filteredMatters.count))"
        case .status(let s): return "\(s) (\(app.filteredMatters.count))"
        case .type(let id): return "\(app.typesById[id]?.name ?? "Type") (\(app.filteredMatters.count))"
        case .dueSoon: return "Due Soon (\(app.filteredMatters.count))"
        case .overdue: return "Overdue (\(app.filteredMatters.count))"
        case .weeklyTimesheet: return "Weekly Timesheet"
        case .today: return "Today"
        case .timeDashboard: return "Time Dashboard"
        case .analytics: return "Analytics"
        case .capacity: return "Capacity"
        case .trash: return "Trash (\(app.trashedMatters.count))"
        case .savedSearch(let id):
            let name = app.savedSearches.first(where: { $0.id == id })?.name ?? "Saved Search"
            return "\(name) (\(app.filteredMatters.count))"
        case .thirdPartiesAll: return "Third Parties"
        case .noteType: return "Notes"
        }
    }
}

struct MatterRow: View {
    let matter: Matter
    @EnvironmentObject var app: AppState

    /// Total interested parties (internal + external) that are populated.
    /// Surfaced as a small badge so the list reflects the new IP fields.
    private var partyCount: Int {
        let internalIPs = [
            matter.interestedParty1AssociateId, matter.interestedParty2AssociateId,
            matter.interestedParty3AssociateId, matter.interestedParty4AssociateId,
            matter.interestedParty5AssociateId
        ].filter { !$0.isEmpty }.count
        let externalIPs = [
            matter.externalInterestedParty1, matter.externalInterestedParty2,
            matter.externalInterestedParty3, matter.externalInterestedParty4,
            matter.externalInterestedParty5
        ].filter { !$0.isEmpty }.count
        return internalIPs + externalIPs
    }

    var body: some View {
        let type = app.typesById[matter.typeId]
        let color = type.flatMap { Color(hex: $0.colorHex) } ?? .gray
        let isRunning = app.timer.activeMatterId == matter.id
        HStack(spacing: 10) {
            Rectangle()
                .fill(color)
                .frame(width: 4)
                .cornerRadius(2)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(matter.id)
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                        .foregroundStyle(color)
                    if isRunning {
                        HStack(spacing: 3) {
                            Image(systemName: "timer")
                                .font(.caption2.weight(.bold))
                            Text(TimeFormat.hms(app.timer.elapsedSeconds))
                                .font(.system(.caption2, design: .monospaced).weight(.bold))
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.green.opacity(0.22))
                        .foregroundStyle(Color.green)
                        .cornerRadius(4)
                    }
                    Spacer()
                    if let due = matter.dueAt {
                        Text(due, style: .date)
                            .font(.caption2)
                            .foregroundStyle(due < Date() && matter.status != "Closed" ? .red : .secondary)
                    }
                }
                Text(matter.title.isEmpty ? "(untitled)" : matter.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    let priority = MatterPriority.parse(matter.priority)
                    Text(priority.shortTag)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(priority.color.opacity(0.22))
                        .foregroundStyle(priority.color)
                        .cornerRadius(4)
                        .help(priority.rawValue)
                    Text(type?.name ?? "Unknown")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(color.opacity(0.20))
                        .foregroundStyle(color)
                        .cornerRadius(4)
                    Text(matter.status)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let secs = app.totalSecondsByMatter[matter.id], secs > 0 {
                        Label(TimeFormat.hm(secs), systemImage: "timer")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if partyCount > 0 {
                        Label("\(partyCount)", systemImage: "person.2.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .help("\(partyCount) interested part\(partyCount == 1 ? "y" : "ies")")
                    }
                    // Subtask progress, only when there are any. The aggregate
                    // counts are precomputed in AppState.subtaskCounts to keep
                    // the per-row render cheap.
                    if let counts = app.subtaskCounts[matter.id], counts.total > 0 {
                        Label("\(counts.done)/\(counts.total)", systemImage: "checklist")
                            .font(.caption2)
                            .foregroundStyle(counts.done == counts.total ? .green : .secondary)
                            .help("Subtasks completed")
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Copy Matter ID") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(matter.id, forType: .string)
            }
            Button("Copy Brief") { ExportService.copyBrief(matter) }
            Divider()
            Button("Delete", role: .destructive) {
                try? app.deleteMatter(id: matter.id)
            }
        }
    }
}

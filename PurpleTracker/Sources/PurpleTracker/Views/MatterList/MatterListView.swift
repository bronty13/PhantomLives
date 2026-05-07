import SwiftUI

struct MatterListView: View {
    @EnvironmentObject var app: AppState

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

            List(selection: Binding(
                get: { app.selectedMatterId },
                set: { if let id = $0 { app.selectMatter(id: id) } }
            )) {
                ForEach(app.filteredMatters) { m in
                    MatterRow(matter: m)
                        .tag(m.id)
                }
            }
            .listStyle(.inset)
        }
        .navigationTitle(navigationTitle)
    }

    private var navigationTitle: String {
        switch app.sidebarSection {
        case .all: return "All Matters (\(app.filteredMatters.count))"
        case .status(let s): return "\(s) (\(app.filteredMatters.count))"
        case .type(let id): return "\(app.typesById[id]?.name ?? "Type") (\(app.filteredMatters.count))"
        case .dueSoon: return "Due Soon (\(app.filteredMatters.count))"
        case .overdue: return "Overdue (\(app.filteredMatters.count))"
        case .weeklyTimesheet: return "Weekly Timesheet"
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

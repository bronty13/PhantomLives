import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        List {
            Section("Overview") {
                row("All Matters", "tray.full", section: .all)
                row("Due Soon",    "clock",     section: .dueSoon)
                row("Overdue",     "exclamationmark.triangle", section: .overdue)
            }
            Section("Status") {
                ForEach(app.statusValues, id: \.name) { sv in
                    row(sv.name, "circle.fill", section: .status(sv.name))
                }
            }
            Section("Type") {
                ForEach(app.types) { t in
                    HStack {
                        Circle()
                            .fill(Color(hex: t.colorHex) ?? .gray)
                            .frame(width: 10, height: 10)
                        Text(t.name)
                            .lineLimit(1)
                    }
                    .contentShape(Rectangle())
                    .background(
                        rowBackground(for: .type(t.id))
                    )
                    .onTapGesture { app.sidebarSection = .type(t.id) }
                }
            }
            Section("Tools") {
                row("Weekly Timesheet", "calendar.badge.clock", section: .weeklyTimesheet)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("PurpleTracker")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(app.types) { t in
                        Button(t.name) {
                            _ = try? app.createMatter(typeId: t.id)
                        }
                    }
                } label: {
                    Label("New Matter", systemImage: "plus")
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ title: String, _ icon: String, section: AppState.SidebarSection) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
        }
        .contentShape(Rectangle())
        .background(rowBackground(for: section))
        .onTapGesture { app.sidebarSection = section }
    }

    private func rowBackground(for section: AppState.SidebarSection) -> some View {
        Group {
            if app.sidebarSection == section {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.accentColor.opacity(0.20))
            } else {
                Color.clear
            }
        }
    }
}

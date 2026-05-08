import SwiftUI

/// A focused at-a-glance view: things due today, due this week, overdue,
/// and the active timer. Click any row to open that Matter.
struct TodayDashboardView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                section("Overdue", systemImage: "exclamationmark.triangle.fill", color: .red,
                        rows: overdue)
                section("Due Today", systemImage: "calendar.badge.exclamationmark", color: .orange,
                        rows: dueToday)
                section("Due This Week", systemImage: "calendar", color: .blue,
                        rows: dueThisWeek)
                section("In Progress (no due date)", systemImage: "play.circle", color: .secondary,
                        rows: inProgressNoDue)
            }
            .padding()
        }
        .navigationTitle("Today")
    }

    private var open: [Matter] {
        let terminal = app.statusValues.last?.name ?? "Closed"
        return app.matters.filter { $0.status != terminal }
    }
    private var now: Date { Date() }
    private var endOfToday: Date {
        Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: now) ?? now
    }
    private var endOfWeek: Date {
        Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
    }
    private var overdue: [Matter] {
        open.filter { ($0.dueAt ?? .distantFuture) < now }
            .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
    }
    private var dueToday: [Matter] {
        open.filter { d in
            guard let due = d.dueAt else { return false }
            return due >= now && due <= endOfToday
        }
    }
    private var dueThisWeek: [Matter] {
        open.filter { d in
            guard let due = d.dueAt else { return false }
            return due > endOfToday && due <= endOfWeek
        }
    }
    private var inProgressNoDue: [Matter] {
        let inprog = app.statusValues.dropFirst().first?.name ?? "In-Progress"
        return open.filter { $0.dueAt == nil && $0.status == inprog }
    }

    @ViewBuilder
    private func section(_ title: String, systemImage: String, color: Color, rows: [Matter]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(color)
            if rows.isEmpty {
                Text("Nothing here.").foregroundStyle(.secondary).font(.caption)
            } else {
                ForEach(rows) { m in
                    Button { app.selectMatter(id: m.id) } label: {
                        HStack {
                            PriorityPill(value: m.priority)
                            Text(m.id).font(.system(.caption, design: .monospaced))
                            Text(m.title).lineLimit(1)
                            Spacer()
                            if let due = m.dueAt {
                                Text(due.formatted(date: .abbreviated, time: .shortened))
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
        }
    }
}

/// Reusable colored pill for the P# priority value.
/// Uses a slightly higher background opacity in dark mode so the pill stays
/// legible against the darker window chrome.
struct PriorityPill: View {
    let value: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = MatterPriority.parse(value)
        Text(p.shortTag)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(p.color.opacity(scheme == .dark ? 0.40 : 0.25))
            .foregroundStyle(p.color)
            .cornerRadius(4)
    }
}

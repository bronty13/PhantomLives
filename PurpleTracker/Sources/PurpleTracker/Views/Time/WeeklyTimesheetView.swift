import SwiftUI

/// Global cross-Matter weekly timesheet. Sums seconds per Matter per ISO week
/// across all time entries in the database.
struct WeeklyTimesheetView: View {
    @EnvironmentObject var app: AppState
    @State private var allEntries: [TimeEntry] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Weekly Timesheet").font(.title2.weight(.semibold))
                Spacer()
                Button("Refresh") { reload() }
            }
            .padding(.horizontal)

            ScrollView {
                ForEach(weeks, id: \.self) { week in
                    weekSection(week)
                }
            }
        }
        .onAppear { reload() }
        .navigationTitle("Weekly Timesheet")
    }

    private func reload() {
        allEntries = (try? DatabaseService.shared.fetchAllTimeEntries()) ?? []
    }

    private var weeks: [String] {
        let cal = Calendar(identifier: .iso8601)
        let keys = Set(allEntries.map { e -> String in
            let c = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: e.startedAt)
            return String(format: "%04d-W%02d", c.yearForWeekOfYear ?? 0, c.weekOfYear ?? 0)
        })
        return Array(keys).sorted(by: >)
    }

    @ViewBuilder
    private func weekSection(_ week: String) -> some View {
        let cal = Calendar(identifier: .iso8601)
        let entries = allEntries.filter { e in
            let c = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: e.startedAt)
            let key = String(format: "%04d-W%02d", c.yearForWeekOfYear ?? 0, c.weekOfYear ?? 0)
            return key == week
        }
        let grouped = Dictionary(grouping: entries) { $0.matterId }
        let weekTotal = entries.reduce(0) { $0 + $1.seconds }

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(week).font(.headline.monospaced())
                Spacer()
                Text("Total \(TimeFormat.hm(weekTotal))").bold()
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.10))

            ForEach(grouped.keys.sorted(), id: \.self) { mid in
                let mEntries = grouped[mid] ?? []
                let total = mEntries.reduce(0) { $0 + $1.seconds }
                let title = app.matters.first { $0.id == mid }?.title ?? "(deleted)"
                HStack {
                    Text(mid).font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 150, alignment: .leading)
                    Text(title).lineLimit(1)
                    Spacer()
                    Text(TimeFormat.hm(total)).monospacedDigit()
                }
                .padding(.horizontal)
                .padding(.vertical, 2)
            }
            Divider()
        }
    }
}

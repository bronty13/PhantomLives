import SwiftUI
import Charts

/// Time tracked per day across all Matters, with a breakdown by Type.
/// Useful for weekly self-reviews.
struct TimeDashboardView: View {
    @EnvironmentObject var app: AppState
    @State private var entries: [TimeEntry] = []
    @State private var rangeDays: Int = 14

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Picker("Range", selection: $rangeDays) {
                    Text("Last 7 days").tag(7)
                    Text("Last 14 days").tag(14)
                    Text("Last 30 days").tag(30)
                    Text("Last 90 days").tag(90)
                }
                .pickerStyle(.segmented)
                .frame(width: 480)

                Text("Hours per day")
                    .font(.headline)
                Chart(perDay, id: \.day) { row in
                    BarMark(
                        x: .value("Day", row.day, unit: .day),
                        y: .value("Hours", row.hours)
                    )
                    .foregroundStyle(.purple)
                }
                .frame(height: 220)

                Text("Hours per Type")
                    .font(.headline)
                Chart(perType, id: \.typeName) { row in
                    BarMark(
                        x: .value("Type", row.typeName),
                        y: .value("Hours", row.hours)
                    )
                    .foregroundStyle(by: .value("Type", row.typeName))
                }
                .frame(height: 220)

                summary
            }
            .padding()
        }
        .navigationTitle("Time Dashboard")
        .onAppear(perform: load)
        .onChange(of: rangeDays) { _, _ in load() }
    }

    private var summary: some View {
        let total = filtered.map(\.seconds).reduce(0, +)
        return Label("Total: \(TimeFormat.hm(total))", systemImage: "clock.fill")
            .font(.title3.weight(.semibold))
    }

    private var filtered: [TimeEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -rangeDays, to: Date()) ?? Date()
        return entries.filter { $0.startedAt >= cutoff }
    }

    private struct DayRow { let day: Date; let hours: Double }
    private var perDay: [DayRow] {
        var bucket: [Date: Int] = [:]
        let cal = Calendar.current
        for e in filtered {
            let day = cal.startOfDay(for: e.startedAt)
            bucket[day, default: 0] += e.seconds
        }
        return bucket.keys.sorted().map { d in
            DayRow(day: d, hours: Double(bucket[d] ?? 0) / 3600.0)
        }
    }

    private struct TypeRow { let typeName: String; let hours: Double }
    private var perType: [TypeRow] {
        let mattersById = Dictionary(uniqueKeysWithValues: app.matters.map { ($0.id, $0) })
        let typesById = app.typesById
        var bucket: [String: Int] = [:]
        for e in filtered {
            guard let m = mattersById[e.matterId] else { continue }
            let typeName = typesById[m.typeId]?.name ?? "Unknown"
            bucket[typeName, default: 0] += e.seconds
        }
        return bucket.map { TypeRow(typeName: $0.key, hours: Double($0.value) / 3600.0) }
            .sorted { $0.hours > $1.hours }
    }

    private func load() {
        entries = (try? DatabaseService.shared.fetchAllTimeEntries()) ?? []
    }
}

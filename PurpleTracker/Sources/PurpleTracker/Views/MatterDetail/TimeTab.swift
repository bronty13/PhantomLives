import SwiftUI

struct TimeTab: View {
    let matter: Matter
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            timerSection
            Divider()
            entriesSection
            Divider()
            weeklySection
        }
    }

    @ViewBuilder
    private var timerSection: some View {
        let isActive = app.timer.activeMatterId == matter.id
        let total = app.totalSecondsByMatter[matter.id] ?? 0
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading) {
                Text("Total time worked").font(.caption).foregroundStyle(.secondary)
                Text(TimeFormat.hms(total + (isActive ? app.timer.elapsedSeconds : 0)))
                    .font(.system(.largeTitle, design: .monospaced).weight(.bold))
            }
            Spacer()
            if isActive {
                Text("Running: \(TimeFormat.hms(app.timer.elapsedSeconds))")
                    .font(.system(.title3, design: .monospaced))
                    .foregroundStyle(.green)
                Button {
                    _ = app.timer.stop()
                } label: { Label("Stop", systemImage: "stop.circle.fill") }
                    .controlSize(.large)
                    .tint(.red)
            } else {
                Button {
                    app.timer.start(matterId: matter.id)
                } label: { Label("Start", systemImage: "play.circle.fill") }
                    .controlSize(.large)
                    .tint(.green)
            }
        }
    }

    private var entriesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Entries").font(.headline)
            if app.timeEntries.isEmpty {
                Text("No time entries yet.").foregroundStyle(.secondary)
            } else {
                Table(app.timeEntries) {
                    TableColumn("Started") { e in
                        Text(e.startedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    TableColumn("Ended") { e in
                        Text(e.endedAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "—")
                    }
                    TableColumn("Duration") { e in Text(TimeFormat.hm(e.seconds)) }
                    TableColumn("Note") { e in Text(e.note) }
                }
                .frame(minHeight: 180)
            }
        }
    }

    /// Per-Matter weekly grouping (ISO week). The global cross-Matter
    /// timesheet lives in `WeeklyTimesheetView`.
    private var weeklySection: some View {
        let grouped = Dictionary(grouping: app.timeEntries) { e -> String in
            let cal = Calendar(identifier: .iso8601)
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: e.startedAt)
            return String(format: "%04d-W%02d",
                          comps.yearForWeekOfYear ?? 0, comps.weekOfYear ?? 0)
        }
        return VStack(alignment: .leading, spacing: 6) {
            Text("By Week").font(.headline)
            ForEach(grouped.keys.sorted(by: >), id: \.self) { week in
                let entries = grouped[week] ?? []
                let total = entries.reduce(0) { $0 + $1.seconds }
                HStack {
                    Text(week).font(.system(.body, design: .monospaced))
                    Spacer()
                    Text(TimeFormat.hm(total)).bold()
                }
            }
        }
    }
}

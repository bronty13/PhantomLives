import SwiftUI

/// Month-grid calendar. Days with entries get a colored dot; clicking a day
/// jumps to the timeline with that day's first entry selected (or creates a
/// new entry on that day if none exists).
struct CalendarView: View {
    @EnvironmentObject private var appState: AppState
    @State private var visibleMonth: Date = Date()

    private let cal = Calendar.current

    var body: some View {
        VStack(spacing: 12) {
            monthHeader
            weekdayHeader
            grid
            legend
            Spacer()
        }
        .padding(20)
    }

    private var monthHeader: some View {
        HStack {
            Button { shift(by: -1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.plain)
            Spacer()
            Text(monthTitle)
                .font(.title2.weight(.semibold))
            Spacer()
            Button { shift(by: 1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.plain)
        }
    }

    /// Heatmap key: faint → strong, by how much you wrote that day.
    private var legend: some View {
        HStack(spacing: 6) {
            Spacer()
            Text("Less").font(.caption2).foregroundStyle(.secondary)
            ForEach(0...4, id: \.self) { level in
                RoundedRectangle(cornerRadius: 3)
                    .fill(appState.effectiveAccentColor.opacity(CalendarHeatmap.opacity(level: level)))
                    .frame(width: 12, height: 12)
            }
            Text("More").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(weekdaySymbols, id: \.self) { sym in
                Text(sym)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var grid: some View {
        let days = monthDays
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                if let day {
                    dayCell(day)
                } else {
                    Color.clear.frame(height: 56)
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let entriesOnDay = appState.visibleEntries.filter { cal.isDate($0.dateValue, inSameDayAs: day) }
        let words = entriesOnDay.reduce(0) { $0 + $1.wordCount }
        let level = CalendarHeatmap.level(words: words)
        let isToday = cal.isDateInToday(day)
        let accent = appState.effectiveAccentColor
        let fill = entriesOnDay.isEmpty
            ? Color.secondary.opacity(0.06)
            : accent.opacity(CalendarHeatmap.opacity(level: level))
        return Button {
            open(day: day, existing: entriesOnDay)
        } label: {
            VStack(spacing: 4) {
                Text("\(cal.component(.day, from: day))")
                    .font(.callout)
                    .foregroundStyle(level >= 3 ? .white : (isToday ? accent : .primary))
                if entriesOnDay.count > 1 {
                    Text("\(entriesOnDay.count)")
                        .font(.caption2)
                        .foregroundStyle(level >= 3 ? .white.opacity(0.9) : .secondary)
                } else {
                    Spacer().frame(height: 6)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(fill, in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isToday ? accent : .clear, lineWidth: isToday ? 1.5 : 0)
            )
        }
        .buttonStyle(.plain)
        .help(entriesOnDay.isEmpty ? "" : "\(entriesOnDay.count) " +
              (entriesOnDay.count == 1 ? "entry" : "entries") + " · \(words) words")
    }

    // MARK: - Actions

    private func open(day: Date, existing: [Entry]) {
        if let first = existing.sorted(by: { $0.date > $1.date }).first {
            appState.selectedEntryId = first.id
        } else {
            _ = try? appState.createEntry(date: day)
        }
        appState.selectedSection = .timeline
    }

    private func shift(by months: Int) {
        if let d = cal.date(byAdding: .month, value: months, to: visibleMonth) {
            visibleMonth = d
        }
    }

    // MARK: - Date helpers

    private var monthTitle: String {
        let f = DateFormatter(); f.dateFormat = "LLLL yyyy"
        return f.string(from: visibleMonth)
    }

    private var weekdaySymbols: [String] {
        var symbols = cal.shortWeekdaySymbols
        if appState.settings.weekStartsMonday {
            symbols.append(symbols.removeFirst())
        }
        return symbols
    }

    /// Days of the visible month, padded with leading `nil`s so the 1st lands
    /// under the right weekday column.
    private var monthDays: [Date?] {
        guard let interval = cal.dateInterval(of: .month, for: visibleMonth) else { return [] }
        let firstDay = interval.start
        let daysInMonth = cal.range(of: .day, in: .month, for: visibleMonth)?.count ?? 30
        let weekday = cal.component(.weekday, from: firstDay) // 1 = Sunday
        let leadingBlanks: Int
        if appState.settings.weekStartsMonday {
            leadingBlanks = (weekday + 5) % 7   // shift so Monday = 0
        } else {
            leadingBlanks = weekday - 1
        }
        var cells: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for d in 0..<daysInMonth {
            cells.append(cal.date(byAdding: .day, value: d, to: firstDay))
        }
        return cells
    }
}

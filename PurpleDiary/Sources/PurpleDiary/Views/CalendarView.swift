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
        let entriesOnDay = appState.entries.filter { cal.isDate($0.dateValue, inSameDayAs: day) }
        let isToday = cal.isDateInToday(day)
        return Button {
            open(day: day, existing: entriesOnDay)
        } label: {
            VStack(spacing: 4) {
                Text("\(cal.component(.day, from: day))")
                    .font(.callout)
                    .foregroundStyle(isToday ? Color.accentColor : .primary)
                if !entriesOnDay.isEmpty {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                } else {
                    Spacer().frame(height: 6)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                isToday ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 6)
            )
        }
        .buttonStyle(.plain)
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

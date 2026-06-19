import SwiftUI
import AppKit

/// Month-grid calendar. Days with entries are tinted by a word-count heatmap and
/// — Diarium-style — show a **photo from that day's entry** behind the date when
/// one exists. Clicking a day jumps to the timeline with that day's first entry
/// selected (or creates a new entry on that day if none exists).
struct CalendarView: View {
    @EnvironmentObject private var appState: AppState
    @State private var visibleMonth: Date = Date()

    /// dayStart → the first available attachment thumbnail for that day, for the
    /// visible month. Precomputed (not fetched per-cell) so a redraw doesn't hit
    /// the DB ~31×; rebuilt when the month, the journal filter, or attachments
    /// change. See `reloadThumbs`.
    @State private var thumbsByDay: [Date: NSImage] = [:]

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
        .onAppear { reloadThumbs() }
        .onChange(of: visibleMonth) { _, _ in reloadThumbs() }
        .onChange(of: appState.selectedJournalId) { _, _ in reloadThumbs() }
        .onChange(of: appState.attachmentCountByEntry) { _, _ in reloadThumbs() }
    }

    /// Build `thumbsByDay` for the visible month: for each day that has an entry
    /// with at least one attachment, take the first thumbnail (newest entry wins).
    /// Uses the cheap `attachmentThumbs` projection (thumbnail BLOB only, no
    /// full-res data) and is bounded by the month's entries-with-attachments.
    private func reloadThumbs() {
        let monthEntries = appState.visibleEntries
            .filter { (appState.attachmentCountByEntry[$0.id] ?? 0) > 0 &&
                      cal.isDate($0.dateValue, equalTo: visibleMonth, toGranularity: .month) }
            .sorted { $0.dateValue > $1.dateValue }   // newest first → most recent photo wins
        var map: [Date: NSImage] = [:]
        for e in monthEntries {
            let day = cal.startOfDay(for: e.dateValue)
            if map[day] != nil { continue }
            if let thumb = try? DatabaseService.shared.attachmentThumbs(forEntry: e.id)
                .first(where: { $0.thumbnailData != nil }),
               let data = thumb.thumbnailData, let img = NSImage(data: data) {
                map[day] = img
            }
        }
        thumbsByDay = map
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
        let photo = thumbsByDay[cal.startOfDay(for: day)]
        // Over a photo the date is always white-on-scrim; otherwise it follows the
        // heatmap depth / today accent as before.
        let dayColor: Color = photo != nil ? .white
            : (level >= 3 ? .white : (isToday ? accent : .primary))
        return Button {
            open(day: day, existing: entriesOnDay)
        } label: {
            ZStack {
                cellBackground(photo: photo, entriesOnDay: entriesOnDay, level: level, accent: accent)
                VStack(spacing: 4) {
                    Text("\(cal.component(.day, from: day))")
                        .font(.callout)
                        .foregroundStyle(dayColor)
                        .shadow(color: photo != nil ? .black.opacity(0.6) : .clear, radius: 1, y: 0.5)
                    if entriesOnDay.count > 1 {
                        Text("\(entriesOnDay.count)")
                            .font(.caption2)
                            .foregroundStyle((photo != nil || level >= 3) ? .white.opacity(0.9) : .secondary)
                    } else {
                        Spacer().frame(height: 6)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isToday ? accent : .clear, lineWidth: isToday ? 1.5 : 0)
            )
        }
        .buttonStyle(.plain)
        .help(entriesOnDay.isEmpty ? "" : "\(entriesOnDay.count) " +
              (entriesOnDay.count == 1 ? "entry" : "entries") + " · \(words) words")
    }

    /// The cell's background layer: a day photo (with a legibility scrim + a hint
    /// of the heatmap tint) when one exists, otherwise the flat heatmap fill.
    @ViewBuilder
    private func cellBackground(photo: NSImage?, entriesOnDay: [Entry], level: Int, accent: Color) -> some View {
        if let photo {
            Image(nsImage: photo)
                .resizable()
                .scaledToFill()
                .overlay(
                    // Darken top (where the date sits) + keep a faint accent tint
                    // so the heatmap signal survives behind the photo.
                    LinearGradient(colors: [.black.opacity(0.55), .black.opacity(0.10)],
                                   startPoint: .top, endPoint: .center)
                )
                .overlay(accent.opacity(0.14))
        } else {
            (entriesOnDay.isEmpty
                ? Color.secondary.opacity(0.06)
                : accent.opacity(CalendarHeatmap.opacity(level: level)))
        }
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

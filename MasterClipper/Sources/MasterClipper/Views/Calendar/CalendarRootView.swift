import SwiftUI

enum CalendarMode: String, CaseIterable, Hashable {
    case year, quarter, month, week, day

    var label: String {
        switch self {
        case .year:    return "Year"
        case .quarter: return "Quarter"
        case .month:   return "Month"
        case .week:    return "Week"
        case .day:     return "Day"
        }
    }
}

struct CalendarRootView: View {
    @EnvironmentObject private var appState: AppState

    @State private var mode: CalendarMode = .month
    @State private var anchorDate: Date = Date()
    @State private var eventsByDate: [String: [CalendarEvent]] = [:]
    @State private var loadError: String?
    @State private var generatorYear: Int = Calendar.current.component(.year, from: Date())
    @State private var lastGenSummary: String?

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        c.firstWeekday = 1
        return c
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .navigationTitle("Calendar")
        .onAppear {
            mode = CalendarMode(rawValue: appState.settings.calendarDefaultView) ?? .month
            reload()
        }
        .onChange(of: anchorDate) { _, _ in reload() }
        .onChange(of: mode)       { _, _ in reload() }
        // When the underlying clip list changes (import, edit, delete), the
        // synthesized go-live entries change too. Re-augment.
        .onChange(of: appState.clips.count) { _, _ in reload() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("View", selection: $mode) {
                ForEach(CalendarMode.allCases, id: \.self) { m in
                    Text(m.label).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 380)

            Button {
                anchorDate = stepDate(by: -1)
            } label: { Image(systemName: "chevron.left") }
            Button("Today") { anchorDate = Date() }
            Button {
                anchorDate = stepDate(by: 1)
            } label: { Image(systemName: "chevron.right") }

            Text(headerLabel)
                .font(.headline)
                .frame(minWidth: 200, alignment: .leading)

            Spacer()

            Stepper(value: $generatorYear, in: 2020...2099) {
                Text("Year \(generatorYear)").font(.caption)
            }
            .frame(width: 180)

            Button("Generate") { runGenerate() }

            if let s = lastGenSummary {
                Text(s).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.background.secondary)
    }

    // MARK: - Content router

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .year:    yearView
        case .quarter: quarterView
        case .month:   monthView
        case .week:    weekView
        case .day:     dayView
        }
    }

    // MARK: - Year view

    private var yearView: some View {
        ScrollView {
            let year = calendar.component(.year, from: anchorDate)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 16) {
                ForEach(1...12, id: \.self) { month in
                    miniMonthCell(year: year, month: month)
                        .onTapGesture {
                            if let d = calendar.date(from: DateComponents(year: year, month: month, day: 1)) {
                                anchorDate = d
                                mode = .month
                            }
                        }
                }
            }
            .padding(16)
        }
    }

    private func miniMonthCell(year: Int, month: Int) -> some View {
        let monthName = calendar.monthSymbols[month - 1]
        let dates = datesInMonth(year: year, month: month)
        return VStack(alignment: .leading, spacing: 4) {
            Text(monthName).font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 7), spacing: 1) {
                ForEach(["S","M","T","W","T","F","S"], id: \.self) { d in
                    Text(d).font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(dates, id: \.self) { dateOpt in
                    if let date = dateOpt {
                        let key = DatabaseService.isoDate(date)
                        let hasEvent = (eventsByDate[key]?.isEmpty == false)
                        ZStack {
                            Circle()
                                .fill(hasEvent ? Color.accentColor.opacity(0.4) : Color.clear)
                                .frame(width: 18, height: 18)
                            Text("\(calendar.component(.day, from: date))")
                                .font(.caption2)
                        }
                    } else {
                        Text(" ").font(.caption2)
                    }
                }
            }
        }
        .padding(8)
        .background(.background.secondary)
        .cornerRadius(6)
    }

    // MARK: - Quarter view

    private var quarterView: some View {
        ScrollView {
            let year = calendar.component(.year, from: anchorDate)
            let month = calendar.component(.month, from: anchorDate)
            let quarter = (month - 1) / 3
            let months = (1...3).map { quarter * 3 + $0 }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ForEach(months, id: \.self) { m in
                    miniMonthCell(year: year, month: m)
                        .frame(minHeight: 220)
                }
            }
            .padding(16)
        }
    }

    // MARK: - Month view

    private var monthView: some View {
        let year = calendar.component(.year, from: anchorDate)
        let month = calendar.component(.month, from: anchorDate)
        let dates = datesInMonth(year: year, month: month)

        return ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(["Sun","Mon","Tue","Wed","Thu","Fri","Sat"], id: \.self) { d in
                    Text(d).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                ForEach(Array(dates.enumerated()), id: \.offset) { (_, dateOpt) in
                    if let date = dateOpt {
                        dayCell(date: date)
                    } else {
                        Color.clear.frame(minHeight: 80)
                    }
                }
            }
            .padding(12)
        }
    }

    private func dayCell(date: Date) -> some View {
        let key = DatabaseService.isoDate(date)
        let events = eventsByDate[key] ?? []
        return VStack(alignment: .leading, spacing: 2) {
            Text("\(calendar.component(.day, from: date))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            ForEach(events) { event in
                eventChip(event)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 80, alignment: .topLeading)
        .background(.background.secondary)
        .cornerRadius(4)
        .onTapGesture {
            anchorDate = date
            mode = .day
        }
    }

    // MARK: - Week / Day

    private var weekView: some View {
        let week = datesInWeek(of: anchorDate)
        return ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(week, id: \.self) { date in
                    dayRow(date: date)
                }
            }
            .padding(16)
        }
    }

    private var dayView: some View {
        let key = DatabaseService.isoDate(anchorDate)
        let events = eventsByDate[key] ?? []
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(longLabel(for: anchorDate))
                    .font(.title2.weight(.semibold))
                if events.isEmpty {
                    Text("Nothing scheduled.").foregroundStyle(.secondary).font(.callout)
                } else {
                    ForEach(events) { event in
                        eventCard(event)
                    }
                }
            }
            .padding(20)
        }
    }

    private func dayRow(date: Date) -> some View {
        let key = DatabaseService.isoDate(date)
        let events = eventsByDate[key] ?? []
        return VStack(alignment: .leading, spacing: 4) {
            Text(longLabel(for: date)).font(.headline)
            if events.isEmpty {
                Text("—").foregroundStyle(.tertiary).font(.caption)
            } else {
                ForEach(events) { eventCard($0) }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary)
        .cornerRadius(6)
    }

    // MARK: - Event chip / card

    private func eventChip(_ event: CalendarEvent) -> some View {
        let title = event.title.isEmpty
            ? clipTitle(forEventClipId: event.clipId)
            : event.title
        let display = "\(title.isEmpty ? "—" : title)[\(event.personaCode)]"
        return Text(display)
            .font(.caption2)
            .lineLimit(1)
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(personaColor(for: event.personaCode).opacity(0.25), in: RoundedRectangle(cornerRadius: 3))
    }

    private func eventCard(_ event: CalendarEvent) -> some View {
        let categories = clipCategories(forEventClipId: event.clipId)
        return HStack(alignment: .top, spacing: 10) {
            Circle().fill(personaColor(for: event.personaCode))
                .frame(width: 10, height: 10).padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(event.title.isEmpty ? clipTitle(forEventClipId: event.clipId) : event.title)[\(event.personaCode)]")
                    .font(.body.weight(.medium))
                if !categories.isEmpty {
                    Text(categories.joined(separator: ", "))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !event.notes.isEmpty {
                    Text(event.notes).font(.caption).foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
        .padding(8)
        .background(.background.secondary)
        .cornerRadius(6)
    }

    // MARK: - Helpers

    private var headerLabel: String {
        switch mode {
        case .year:    return "\(calendar.component(.year, from: anchorDate))"
        case .quarter:
            let m = calendar.component(.month, from: anchorDate)
            return "Q\((m - 1) / 3 + 1) \(calendar.component(.year, from: anchorDate))"
        case .month:
            let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; return f.string(from: anchorDate)
        case .week:
            let week = datesInWeek(of: anchorDate)
            let f = DateFormatter(); f.dateFormat = "MMM d"
            if let first = week.first, let last = week.last {
                return "\(f.string(from: first)) – \(f.string(from: last))"
            }
            return ""
        case .day:
            return longLabel(for: anchorDate)
        }
    }

    private func longLabel(for date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d, yyyy"
        return f.string(from: date)
    }

    private func datesInMonth(year: Int, month: Int) -> [Date?] {
        var dates: [Date?] = []
        guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: first) else {
            return dates
        }
        let leading = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        for _ in 0..<leading { dates.append(nil) }
        for day in range {
            if let d = calendar.date(from: DateComponents(year: year, month: month, day: day)) {
                dates.append(d)
            }
        }
        while dates.count % 7 != 0 { dates.append(nil) }
        return dates
    }

    private func datesInWeek(of date: Date) -> [Date] {
        let weekday = calendar.component(.weekday, from: date)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        guard let start = calendar.date(byAdding: .day, value: -offset, to: date) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private func stepDate(by direction: Int) -> Date {
        switch mode {
        case .year:    return calendar.date(byAdding: .year,  value: direction, to: anchorDate) ?? anchorDate
        case .quarter: return calendar.date(byAdding: .month, value: direction * 3, to: anchorDate) ?? anchorDate
        case .month:   return calendar.date(byAdding: .month, value: direction, to: anchorDate) ?? anchorDate
        case .week:    return calendar.date(byAdding: .day,   value: direction * 7, to: anchorDate) ?? anchorDate
        case .day:     return calendar.date(byAdding: .day,   value: direction, to: anchorDate) ?? anchorDate
        }
    }

    private func reload() {
        let (start, end): (Date, Date)
        switch mode {
        case .year:
            let y = calendar.component(.year, from: anchorDate)
            (start, end) = CalendarService.dateRange(year: y) ?? (anchorDate, anchorDate)
        case .quarter:
            let m = calendar.component(.month, from: anchorDate)
            let qStart = ((m - 1) / 3) * 3 + 1
            let y = calendar.component(.year, from: anchorDate)
            start = calendar.date(from: DateComponents(year: y, month: qStart, day: 1)) ?? anchorDate
            end   = calendar.date(byAdding: .day, value: -1,
                                  to: calendar.date(byAdding: .month, value: 3, to: start) ?? start) ?? start
        case .month:
            let comps = calendar.dateComponents([.year, .month], from: anchorDate)
            start = calendar.date(from: comps) ?? anchorDate
            end   = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? anchorDate
        case .week:
            let week = datesInWeek(of: anchorDate)
            start = week.first ?? anchorDate
            end   = week.last  ?? anchorDate
        case .day:
            start = anchorDate
            end   = anchorDate
        }

        do {
            eventsByDate = try CalendarService.eventsByDate(start: start, end: end)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
        augmentWithClipGoLiveDates(start: start, end: end)
    }

    /// Pull every active clip whose `goLiveDate` falls in the visible range and
    /// surface it on the calendar. If a `calendar_events` row already links to
    /// the clip we leave it alone; otherwise we synthesize a display-only entry
    /// (negative id so it doesn't collide with any real auto-incremented row).
    /// No DB writes — pure view augmentation.
    private func augmentWithClipGoLiveDates(start: Date, end: Date) {
        let isoFmt = DateFormatter()
        isoFmt.dateFormat = "yyyy-MM-dd"
        isoFmt.locale = Locale(identifier: "en_US_POSIX")

        var fakeId: Int64 = -1
        for clip in appState.clips where !clip.archived {
            guard let go = clip.goLiveDate, !go.isEmpty,
                  let goDate = isoFmt.date(from: go),
                  goDate >= start, goDate <= end else { continue }
            let existing = eventsByDate[go] ?? []
            // Already represented (real event linked to this clip) — skip.
            if existing.contains(where: { $0.clipId == clip.id }) { continue }
            let synth = CalendarEvent(
                id: fakeId,
                date: go,
                personaCode: clip.personaCode,
                clipId: clip.id,
                title: clip.title,
                notes: "",
                createdAt: "",
                updatedAt: ""
            )
            fakeId -= 1
            eventsByDate[go, default: []].append(synth)
        }
        // Stable per-day order: persona code asc.
        for key in eventsByDate.keys {
            eventsByDate[key]?.sort { lhs, rhs in
                if lhs.personaCode != rhs.personaCode {
                    return lhs.personaCode < rhs.personaCode
                }
                return (lhs.title) < (rhs.title)
            }
        }
    }

    private func runGenerate() {
        do {
            let r = try CalendarService.generateYear(generatorYear, rules: appState.calendarRules)
            lastGenSummary = "+\(r.inserted) / \(r.skipped) existed"
            reload()
        } catch {
            lastGenSummary = "Failed: \(error.localizedDescription)"
        }
    }

    private func personaColor(for code: String) -> Color {
        if let p = appState.persona(forCode: code), let c = Color(hex: p.colorHex) {
            return c
        }
        return .accentColor
    }

    private func clipTitle(forEventClipId clipId: String?) -> String {
        guard let id = clipId else { return "" }
        return appState.clips.first(where: { $0.id == id })?.title ?? ""
    }

    private func clipCategories(forEventClipId clipId: String?) -> [String] {
        guard let id = clipId else { return [] }
        let ids = (try? DatabaseService.shared.categoryIds(forClip: id)) ?? []
        return ids.compactMap { cid in appState.categories.first { $0.id == cid }?.name }
    }
}

import SwiftUI

/// Case timeline view. Two visualizations share the same filter state:
///   - **List** (Phase 1): vertical chronological list with year/month section headers
///   - **Map**  (Phase 2): horizontal pan/zoom Canvas with importance-colored dots
struct TimelineView: View {
    @EnvironmentObject private var appState: AppState
    let caseId: String

    enum DisplayMode: String, CaseIterable, Hashable { case list, map }

    @State private var displayMode: DisplayMode = .list
    @State private var query: String = ""
    @State private var importanceFilter: Set<Importance> = []
    @State private var tagFilter: Set<Int64> = []
    @State private var dateLow: Date?
    @State private var dateHigh: Date?

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            switch displayMode {
            case .list: list
            case .map:
                HorizontalTimelineView(caseId: caseId, events: filtered)
                    .environmentObject(appState)
            }
        }
    }

    private var events: [Event] {
        appState.events
            .filter { $0.caseId == caseId }
            .sorted { ($0.parsedStart ?? .distantPast) < ($1.parsedStart ?? .distantPast) }
    }

    private var filtered: [Event] {
        var out = events
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            out = out.filter {
                $0.title.lowercased().contains(q)
                    || $0.descriptionMarkdown.lowercased().contains(q)
            }
        }
        if !importanceFilter.isEmpty {
            out = out.filter { importanceFilter.contains($0.importanceEnum) }
        }
        if !tagFilter.isEmpty {
            out = out.filter { ev in
                guard let tags = appState.tagsByEvent[ev.id] else { return false }
                return !Set(tags.compactMap(\.rowId)).intersection(tagFilter).isEmpty
            }
        }
        if let lo = dateLow {
            out = out.filter { ($0.parsedStart ?? .distantFuture) >= startOfDay(lo) }
        }
        if let hi = dateHigh {
            out = out.filter { ($0.parsedStart ?? .distantPast) <= endOfDay(hi) }
        }
        return out
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Picker("", selection: $displayMode) {
                    Image(systemName: "list.bullet").tag(DisplayMode.list)
                    Image(systemName: "calendar.day.timeline.left").tag(DisplayMode.map)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 96)
                .help("Switch between list and horizontal timeline")
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter events…", text: $query)
                    .textFieldStyle(.plain)
                Spacer()
                DatePicker("From", selection: Binding(
                    get: { dateLow ?? .distantPast },
                    set: { dateLow = $0 == .distantPast ? nil : $0 }
                ), displayedComponents: .date)
                .labelsHidden()
                .help("Filter — start date")
                Text("→").foregroundStyle(.secondary)
                DatePicker("To", selection: Binding(
                    get: { dateHigh ?? .distantFuture },
                    set: { dateHigh = $0 == .distantFuture ? nil : $0 }
                ), displayedComponents: .date)
                .labelsHidden()
                .help("Filter — end date")
                Button("Clear") {
                    query = ""
                    importanceFilter = []
                    tagFilter = []
                    dateLow = nil
                    dateHigh = nil
                }
                .disabled(query.isEmpty && importanceFilter.isEmpty && tagFilter.isEmpty
                          && dateLow == nil && dateHigh == nil)
            }
            HStack(spacing: 8) {
                ForEach(Importance.allCases, id: \.self) { imp in
                    FilterToggle(
                        active: importanceFilter.contains(imp),
                        tint: imp.tint,
                        label: imp.label
                    ) {
                        if importanceFilter.contains(imp) { importanceFilter.remove(imp) }
                        else { importanceFilter.insert(imp) }
                    }
                }
                Divider().frame(height: 16)
                ForEach(appState.tags) { tag in
                    if let id = tag.rowId {
                        FilterToggle(
                            active: tagFilter.contains(id),
                            tint: Color(hex: tag.colorHex) ?? .gray,
                            label: tag.name
                        ) {
                            if tagFilter.contains(id) { tagFilter.remove(id) }
                            else { tagFilter.insert(id) }
                        }
                    }
                }
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - List

    @ViewBuilder
    private var list: some View {
        if filtered.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "calendar.badge.clock").font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text(events.isEmpty
                     ? "No events yet — add one with ⌘E."
                     : "No events match the current filters.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(grouped, id: \.id) { group in
                        Section {
                            VStack(spacing: 0) {
                                ForEach(group.months, id: \.id) { month in
                                    MonthBlock(
                                        monthLabel: month.label,
                                        events: month.events
                                    )
                                }
                            }
                        } header: {
                            HStack {
                                Text(group.year)
                                    .font(.system(.title2, design: .rounded, weight: .heavy))
                                    .monospacedDigit()
                                Rectangle()
                                    .fill(.secondary.opacity(0.3))
                                    .frame(height: 1)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(.background.opacity(0.96))
                        }
                    }
                }
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Grouping

    private struct YearGroup { let id: String; let year: String; let months: [MonthGroup] }
    private struct MonthGroup { let id: String; let label: String; let events: [Event] }

    private var grouped: [YearGroup] {
        let cal = Calendar.current
        let dict = Dictionary(grouping: filtered) { ev -> String in
            let d = ev.parsedStart ?? .distantPast
            return TimelineDateFormatters.yearOnly.string(from: d)
        }
        let sortedYears = dict.keys.sorted()
        return sortedYears.map { year in
            let yearEvents = dict[year] ?? []
            let monthDict = Dictionary(grouping: yearEvents) { ev -> Int in
                cal.component(.month, from: ev.parsedStart ?? .distantPast)
            }
            let months = monthDict.keys.sorted().map { m -> MonthGroup in
                let evs = (monthDict[m] ?? [])
                    .sorted { ($0.parsedStart ?? .distantPast) < ($1.parsedStart ?? .distantPast) }
                let label = TimelineDateFormatters.monthYear.monthSymbols[m - 1]
                return MonthGroup(id: "\(year)-\(m)", label: label, events: evs)
            }
            return YearGroup(id: year, year: year, months: months)
        }
    }

    private func startOfDay(_ d: Date) -> Date {
        Calendar.current.startOfDay(for: d)
    }

    private func endOfDay(_ d: Date) -> Date {
        let cal = Calendar.current
        return cal.date(byAdding: .second, value: 86399, to: cal.startOfDay(for: d)) ?? d
    }
}

// MARK: - Month block

private struct MonthBlock: View {
    @EnvironmentObject private var appState: AppState
    let monthLabel: String
    let events: [Event]

    @State private var editingEvent: Event?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(monthLabel)
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
                .padding(.top, 6)
                .padding(.bottom, 4)

            ForEach(events) { ev in
                EventRow(
                    event: ev,
                    tags: appState.tagsByEvent[ev.id] ?? [],
                    people: appState.peopleByEvent[ev.id] ?? []
                )
                .padding(.horizontal, 24)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { editingEvent = ev }
                .contextMenu {
                    Button("Edit Event") { editingEvent = ev }
                    Button("Delete Event", role: .destructive) {
                        try? appState.deleteEvent(id: ev.id)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.background.opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.secondary.opacity(0.18), lineWidth: 0.5)
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
        }
        .sheet(item: $editingEvent) { ev in
            EventEditorSheet(event: ev, isNew: false)
                .environmentObject(appState)
        }
    }
}

// MARK: - Event row

private struct EventRow: View {
    @EnvironmentObject private var appState: AppState
    let event: Event
    let tags: [Tag]
    let people: [Person]

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 2) {
                Text(dayString)
                    .font(appState.font(for: .eventDate))
                    .monospacedDigit()
                Text(monthShort)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let timeStr {
                    Text(timeStr)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 56)
            .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    ImportanceBadge(importance: event.importanceEnum, compact: false)
                    Text(event.title.isEmpty ? "Untitled event" : event.title)
                        .font(appState.font(for: .eventTitle))
                    Spacer()
                }
                if !event.descriptionMarkdown.isEmpty {
                    MarkdownText(text: event.descriptionMarkdown)
                        .font(appState.font(for: .eventBody))
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
                if !event.sourceURL.isEmpty {
                    Link(destination: URL(string: event.sourceURL) ?? URL(fileURLWithPath: "/")) {
                        Label(event.sourceURL, systemImage: "link")
                            .font(.caption)
                    }
                    .foregroundStyle(.tint)
                    .lineLimit(1)
                }
                if !tags.isEmpty || !people.isEmpty || attachmentCount > 0 {
                    HStack(spacing: 6) {
                        ForEach(tags) { TagChip(tag: $0, compact: true) }
                        ForEach(people) { p in
                            PersonRoleChip(
                                person: p,
                                colorHex: appState.settingsStore.roleColorHex(for: p.roleEnum)
                            )
                        }
                        if attachmentCount > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "paperclip")
                                    .font(.caption2)
                                Text("\(attachmentCount)")
                                    .font(.caption2.monospacedDigit())
                            }
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(.secondary.opacity(0.15)))
                            .foregroundStyle(.secondary)
                            .help("\(attachmentCount) attachment\(attachmentCount == 1 ? "" : "s")")
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// Cheap O(1) lookup against the AppState-cached attachment count.
    private var attachmentCount: Int {
        appState.attachmentCounts[event.id] ?? 0
    }

    private var dayString: String {
        guard let d = event.parsedStart else { return "—" }
        return String(Calendar.current.component(.day, from: d))
    }

    private var monthShort: String {
        guard let d = event.parsedStart else { return "" }
        return TimelineDateFormatters.dayMonth.shortMonthSymbols[Calendar.current.component(.month, from: d) - 1]
    }

    private var timeStr: String? {
        guard let d = event.parsedStart else { return nil }
        let cal = Calendar.current
        let h = cal.component(.hour, from: d)
        let m = cal.component(.minute, from: d)
        // Treat midnight as date-only (no time stored)
        if h == 0 && m == 0 { return nil }
        return TimelineDateFormatters.timeOnly.string(from: d)
    }
}

// MARK: - Filter toggle helper

private struct FilterToggle: View {
    let active: Bool
    let tint: Color
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Circle().fill(tint).frame(width: 6, height: 6)
                Text(label).font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(active ? tint.opacity(0.25) : .clear)
            )
            .overlay(
                Capsule().stroke(tint.opacity(active ? 0.6 : 0.3), lineWidth: 0.7)
            )
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }
}

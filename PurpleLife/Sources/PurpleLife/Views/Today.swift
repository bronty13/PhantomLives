import SwiftUI

/// Today / Planner — Phase 3 starter, with prototype-aligned polish.
///
/// Layout:
/// - **Main column**: header → today timeline (auto-generated from any
///   record carrying a date/dateTime field that resolves to today) →
///   the user's saved-query panels.
/// - **Right rail (320 px)**: "linked-from-today" cards — currently
///   reading book + latest weight, looked up via the existing seeded
///   `SavedQuery` rows.
///
/// The timeline and rail are visualization layers on top of data the
/// engine already serves; they don't introduce a new persistence path.
/// The Phase 3 acceptance gate ("Today queries the object engine, no
/// hard-coded modules") still holds — the timeline is one cross-type
/// scan, the rail looks up named saved queries.
struct TodayScreen: View {
    @EnvironmentObject private var appState: AppState

    @State private var openingRecordId: String?
    @State private var showingEditor = false

    var body: some View {
        HStack(spacing: 0) {
            mainColumn
                .frame(maxWidth: .infinity)
            Divider()
            linkedFromRail
                .frame(width: 320)
        }
        .navigationTitle("Today")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingEditor = true
                } label: {
                    Label("Edit panels", systemImage: "slider.horizontal.3")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            SavedQueriesEditor()
                .environmentObject(appState)
        }
        .sheet(isPresented: Binding(
            get: { openingRecordId != nil },
            set: { if !$0 { openingRecordId = nil } }
        )) {
            if let id = openingRecordId {
                ObjectDetailSheet(recordId: id, onChange: { appState.reloadAll() })
                    .environmentObject(appState)
            }
        }
    }

    // MARK: - Main column

    private var mainColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                let timeline = todayTimelineRows()
                if !timeline.isEmpty {
                    TimelinePanel(rows: timeline, onOpen: { openingRecordId = $0 })
                }
                ForEach(appState.settingsStore.settings.todayQueries) { query in
                    QueryPanel(query: query, onOpen: { openingRecordId = $0 })
                }
                if appState.settingsStore.settings.todayQueries.isEmpty && timeline.isEmpty {
                    emptyState
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.title.weight(.bold))
            Text("\(appState.objectCount) object\(appState.objectCount == 1 ? "" : "s") across \(appState.schema.visibleTypes.count) type\(appState.schema.visibleTypes.count == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No saved queries yet.")
                .font(.headline).foregroundStyle(.secondary)
            Text("Today panels are driven by saved queries. Customization UI is queued.")
                .font(.subheadline).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 40)
    }

    // MARK: - Timeline

    /// Find every record across every type that carries a date or
    /// dateTime field whose value resolves to today's calendar day,
    /// and return them sorted chronologically. The "time" for sorting
    /// is the dateTime if present, otherwise midnight (date-only
    /// records sort to the top of the day, which matches the
    /// prototype's behavior of putting all-day events above timed
    /// ones).
    private func todayTimelineRows() -> [TimelineRow] {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart

        var rows: [TimelineRow] = []
        let typed = (try? ObjectEngine.allWithTypes(schema: appState.schema)) ?? []
        for (record, type) in typed {
            // Prefer the type's calendarDateKey if set, otherwise the
            // first date-bearing field. Records without a date field
            // never appear in the timeline.
            let dateKey = type.calendarDateKey
                ?? type.fields.first(where: { $0.kind.canDateForCalendar })?.key
            guard let dateKey, let dateField = type.field(forKey: dateKey) else { continue }
            let raw = record.fields()[dateKey]
            guard let parsed = FieldDisplay.parsedDate(raw),
                  parsed >= todayStart, parsed < tomorrowStart else { continue }
            rows.append(TimelineRow(
                date: parsed,
                hasTime: dateField.kind == .dateTime,
                record: record,
                type: type
            ))
        }
        return rows.sorted { $0.date < $1.date }
    }

    // MARK: - Right rail

    private var linkedFromRail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Today's linked objects")
                    .font(.caption).fontWeight(.semibold).tracking(0.4)
                    .textCase(.uppercase).foregroundStyle(.tertiary)
                    .padding(.bottom, 2)

                // The view-builder emits EmptyView when the named query
                // is missing or returns nothing, so calling these
                // unconditionally is fine — empty slots collapse silently.
                railCard(forSavedQueryNamed: "Currently reading", subtitle: "Reading")
                railCard(forSavedQueryNamed: "Latest weight", subtitle: "Weight")
                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.sidebarOpaque.opacity(0.4))
    }

    /// Find the named saved query, run it, and render the first result
    /// as a small card. Returns nil if the query doesn't exist or
    /// returned no results — the rail then collapses that slot.
    @ViewBuilder
    private func railCard(forSavedQueryNamed name: String, subtitle: String) -> some View {
        if let query = appState.settingsStore.settings.todayQueries.first(where: { $0.name == name }),
           let first = QueryRunner.run(query, schema: appState.schema).first {
            RailCard(
                subtitle: subtitle,
                record: first.record,
                type: first.type,
                onOpen: { openingRecordId = first.record.id }
            )
        }
    }
}

// MARK: - Timeline row + panel

struct TimelineRow: Identifiable {
    let id = UUID()
    let date: Date
    let hasTime: Bool
    let record: ObjectRecord
    let type: ObjectType
}

private struct TimelinePanel: View {
    let rows: [TimelineRow]
    var onOpen: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                TimelineRowView(
                    row: row,
                    isLast: index == rows.count - 1,
                    onOpen: { onOpen(row.record.id) }
                )
            }
        }
        .padding(.leading, 76)
    }
}

private struct TimelineRowView: View {
    let row: TimelineRow
    let isLast: Bool
    var onOpen: () -> Void

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "h:mm a"
        return f
    }()

    var body: some View {
        let tone = Color(hex: row.type.colorHex) ?? .accentColor
        ZStack(alignment: .topLeading) {
            // The connecting line + dot live in an absolute layer so
            // the card itself doesn't need to know about its position
            // in the sequence.
            HStack(spacing: 0) {
                timeColumn
                    .frame(width: 56, alignment: .trailing)
                    .padding(.trailing, 14)
                cardColumn(tone: tone)
            }
            // Connector line (drawn behind everything else)
            if !isLast {
                Rectangle()
                    .fill(Theme.hairline)
                    .frame(width: 1)
                    .offset(x: 75, y: 18)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            // Dot — sits between the time column and the card column,
            // overlaying the connector line.
            Circle()
                .fill(tone)
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .stroke(Theme.bg, lineWidth: 3)
                )
                .offset(x: 70, y: 8)
        }
        .padding(.bottom, 14)
    }

    private var timeColumn: some View {
        Text(row.hasTime ? Self.timeFormatter.string(from: row.date) : "all day")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.top, 8)
    }

    private func cardColumn(tone: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(tone.opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: row.type.systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tone)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(FieldDisplay.title(of: row.record, in: row.type))
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(row.type.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.cardBorder, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onOpen() }
    }
}

// MARK: - Right rail card

private struct RailCard: View {
    let subtitle: String
    let record: ObjectRecord
    let type: ObjectType
    var onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(subtitle)
                .font(.caption2).fontWeight(.semibold).tracking(0.4)
                .textCase(.uppercase).foregroundStyle(.tertiary)
            Text(FieldDisplay.title(of: record, in: type))
                .font(.body.weight(.semibold))
                .lineLimit(2)

            // Two supporting fields under the title — same pattern as
            // the existing QueryPanel cards.
            ForEach(supportingFields, id: \.id) { field in
                HStack(spacing: 4) {
                    Text(field.name)
                        .font(.caption2).foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                    FieldDisplay.cell(field: field, value: record.fields()[field.key])
                        .font(.caption)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.cardBorder, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onOpen() }
    }

    private var supportingFields: [FieldDef] {
        Array(type.fields
            .filter { $0.key != type.primaryFieldKey
                   && $0.kind != .longText
                   && $0.kind != .attachment }
            .prefix(2))
    }
}

// MARK: - QueryPanel (unchanged from prior implementation)

/// One panel = one `SavedQuery`. The Today view repeats this without
/// branching on query content; that's what keeps the screen "no
/// hard-coded modules".
private struct QueryPanel: View {
    @EnvironmentObject private var appState: AppState
    let query: SavedQuery
    var onOpen: (String) -> Void

    var body: some View {
        let results = QueryRunner.run(query, schema: appState.schema)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: query.systemImage)
                    .foregroundStyle(.tint)
                Text(query.name)
                    .font(.headline)
                Text("\(results.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                if let typeId = query.typeId {
                    Button {
                        appState.selectedTypeId = typeId
                    } label: {
                        HStack(spacing: 4) {
                            Text("See all")
                            Image(systemName: "arrow.right")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                }
            }
            if results.isEmpty {
                Text("Nothing matches yet.")
                    .font(.callout).foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
            } else {
                cardGrid(results: results)
            }
        }
        .padding(16)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.cardBorder, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func cardGrid(results: [(record: ObjectRecord, type: ObjectType)]) -> some View {
        let columns = [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 10)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(results, id: \.record.id) { item in
                resultCard(record: item.record, type: item.type)
                    .onTapGesture(count: 2) { onOpen(item.record.id) }
            }
        }
    }

    private func resultCard(record: ObjectRecord, type: ObjectType) -> some View {
        let supporting = type.fields
            .filter { $0.key != type.primaryFieldKey && $0.kind != .longText && $0.kind != .attachment }
            .prefix(2)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: type.systemImage)
                    .foregroundStyle(Color(hex: type.colorHex) ?? .accentColor)
                    .imageScale(.small)
                Text(type.name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.4)
            }
            Text(FieldDisplay.title(of: record, in: type))
                .font(.body.weight(.semibold))
                .lineLimit(2)
            ForEach(Array(supporting), id: \.id) { field in
                HStack(spacing: 4) {
                    Text(field.name)
                        .font(.caption2).foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                    FieldDisplay.cell(field: field, value: record.fields()[field.key])
                        .font(.caption)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bg.opacity(0.6))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.hairline, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

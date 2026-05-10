import SwiftUI

/// Container for the four list views (table / kanban / calendar / gallery)
/// over a single object type. Phase 2 acceptance gate (`PLAN.md`) requires
/// all four to render real records — this screen owns the view-kind
/// switcher and the create / detail-sheet flows that are common to them.
struct RecordsScreen: View {
    @EnvironmentObject private var appState: AppState
    let typeId: String

    enum ViewKind: String, CaseIterable, Identifiable {
        case table, kanban, calendar, gallery
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        var systemImage: String {
            switch self {
            case .table:    return "tablecells"
            case .kanban:   return "rectangle.split.3x1"
            case .calendar: return "calendar"
            case .gallery:  return "square.grid.3x2"
            }
        }
    }

    @State private var viewKind: ViewKind = .table
    @State private var rows: [ObjectRecord] = []
    @State private var error: String?
    @State private var editingRecordId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if let error {
                Text(error).foregroundStyle(.red).padding()
            } else if rows.isEmpty {
                emptyState
            } else {
                body(for: viewKind)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Picker("View", selection: $viewKind) {
                    ForEach(viewKindsForCurrentType, id: \.self) { kind in
                        Label(kind.label, systemImage: kind.systemImage).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    addEmpty()
                } label: {
                    Label("New \(type?.name ?? "object")", systemImage: "plus")
                }
                .disabled(type == nil)
            }
        }
        .onAppear { reload() }
        .onChange(of: typeId) { _, _ in
            // Re-pick a sensible default view when switching types — calendar
            // / gallery / kanban require certain field kinds and may not be
            // applicable.
            viewKind = defaultViewKind
            reload()
        }
        .sheet(isPresented: Binding(
            get: { editingRecordId != nil },
            set: { if !$0 { editingRecordId = nil } }
        )) {
            if let id = editingRecordId {
                ObjectDetailSheet(recordId: id, onChange: { reload(); appState.reloadAll() })
                    .environmentObject(appState)
            }
        }
        .onChange(of: appState.openRecordRequest) { _, requested in
            // Quick Switcher (or any other source) has asked us to open
            // a record. Match it up to a row and present the detail sheet.
            if let id = requested {
                editingRecordId = id
                appState.openRecordRequest = nil
            }
        }
    }

    var type: ObjectType? { appState.schema.type(id: typeId) }

    private var defaultViewKind: ViewKind { .table }

    /// Hide kanban / calendar / gallery for types whose schema can't
    /// support them — there's no point showing a calendar tab if the
    /// type has no date field.
    private var viewKindsForCurrentType: [ViewKind] {
        var kinds: [ViewKind] = [.table]
        guard let t = type else { return kinds }
        if t.fields.contains(where: { $0.kind == .select })            { kinds.append(.kanban) }
        if t.fields.contains(where: { $0.kind.canDateForCalendar })    { kinds.append(.calendar) }
        if t.fields.contains(where: { $0.kind == .attachment })        { kinds.append(.gallery) }
        return kinds
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            if let t = type {
                Image(systemName: t.systemImage)
                    .foregroundStyle(Color(hex: t.colorHex) ?? .accentColor)
                Text(t.pluralName).font(.title2).bold()
                Text("\(rows.count)")
                    .font(.title3).monospacedDigit().foregroundStyle(.secondary)
            } else {
                Text("Unknown type").font(.title2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: type?.systemImage ?? "tray")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No \(type?.pluralName.lowercased() ?? "objects") yet")
                .font(.headline).foregroundStyle(.secondary)
            Text("Click + in the toolbar to create one.")
                .font(.subheadline).foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func body(for kind: ViewKind) -> some View {
        if let t = type {
            switch kind {
            case .table:
                RecordsTableBody(type: t, rows: rows, onOpen: openRecord, onDelete: deleteRow)
            case .kanban:
                RecordsKanbanBody(type: t, rows: rows, onOpen: openRecord)
            case .calendar:
                RecordsCalendarBody(type: t, rows: rows, onOpen: openRecord)
            case .gallery:
                RecordsGalleryBody(type: t, rows: rows, onOpen: openRecord)
            }
        }
    }

    // MARK: - Actions

    private func reload() {
        do {
            rows = try appState.database.fetchObjects(typeId: typeId)
            error = nil
        } catch {
            self.error = error.localizedDescription
            rows = []
        }
    }

    private func addEmpty() {
        guard let t = type else { return }
        do {
            let created = try ObjectEngine.create(typeId: t.id)
            appState.reloadAll()
            reload()
            editingRecordId = created.id
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func openRecord(_ id: String) { editingRecordId = id }

    private func deleteRow(_ row: ObjectRecord) {
        do {
            try ObjectEngine.delete(id: row.id)
            appState.reloadAll()
            reload()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Table body

struct RecordsTableBody: View {
    let type: ObjectType
    let rows: [ObjectRecord]
    var onOpen: (String) -> Void
    var onDelete: (ObjectRecord) -> Void

    var body: some View {
        let fields = orderedFields(for: type)
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                headerRow(fields: fields)
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    dataRow(fields: fields, row: row, even: index.isMultiple(of: 2))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func orderedFields(for t: ObjectType) -> [FieldDef] {
        guard let primaryKey = t.primaryFieldKey else { return t.fields }
        var ordered = t.fields
        if let idx = ordered.firstIndex(where: { $0.key == primaryKey }), idx > 0 {
            ordered.insert(ordered.remove(at: idx), at: 0)
        }
        return ordered
    }

    private func columnWidth(for field: FieldDef) -> CGFloat {
        switch field.kind {
        case .longText:                  return 320
        case .text, .url, .email, .link: return 200
        case .number:                    return 100
        case .date, .dateTime:           return 160
        case .boolean:                   return 60
        case .select:                    return 140
        case .multiSelect:               return 220
        case .rating:                    return 110
        case .attachment:                return 80
        }
    }

    private func headerRow(fields: [FieldDef]) -> some View {
        HStack(spacing: 0) {
            ForEach(fields, id: \.id) { field in
                Text(field.name)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase).tracking(0.5)
                    .foregroundStyle(.secondary)
                    .frame(width: columnWidth(for: field), alignment: .leading)
                    .padding(.vertical, 8).padding(.horizontal, 12)
            }
        }
        .background(Color.secondary.opacity(0.08))
        .overlay(alignment: .bottom) { Divider() }
    }

    private func dataRow(fields: [FieldDef], row: ObjectRecord, even: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(fields, id: \.id) { field in
                FieldDisplay.cell(
                    field: field,
                    value: row.fields()[field.key],
                    isPrimary: field.key == type.primaryFieldKey
                )
                .frame(width: columnWidth(for: field), alignment: .leading)
                .padding(.vertical, 10).padding(.horizontal, 12)
            }
        }
        .contentShape(Rectangle())
        .background(even ? Color.clear : Color.secondary.opacity(0.04))
        .overlay(alignment: .bottom) { Divider().opacity(0.6) }
        .onTapGesture(count: 2) { onOpen(row.id) }
        .contextMenu {
            Button("Open") { onOpen(row.id) }
            Divider()
            Button("Delete", role: .destructive) { onDelete(row) }
        }
    }
}

// MARK: - Kanban body

struct RecordsKanbanBody: View {
    let type: ObjectType
    let rows: [ObjectRecord]
    var onOpen: (String) -> Void

    var body: some View {
        if let groupField = groupingField {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(columnsByOption(for: groupField), id: \.0) { (label, opt, items) in
                        column(label: label, option: opt, records: items)
                    }
                    if !ungrouped.isEmpty {
                        column(label: "—", option: nil, records: ungrouped)
                    }
                }
                .padding(16)
            }
        } else {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "rectangle.split.3x1")
                    .font(.system(size: 40)).foregroundStyle(.tertiary)
                Text("This type has no select field to group by.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("Add a select field in the schema editor (⇧⌘S) to enable kanban view.")
                    .font(.caption).foregroundStyle(.tertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var groupingField: FieldDef? {
        if let key = type.kanbanGroupKey, let f = type.field(forKey: key), f.kind == .select { return f }
        return type.fields.first { $0.kind == .select }
    }

    /// Records keyed by the option name they hold for `groupField`.
    private func columnsByOption(for field: FieldDef) -> [(String, FieldOption?, [ObjectRecord])] {
        field.options.map { opt in
            (opt.name, opt as FieldOption?, rows.filter { ($0.fields()[field.key] as? String) == opt.name })
        }
    }

    private var ungrouped: [ObjectRecord] {
        guard let f = groupingField else { return rows }
        let names = Set(f.options.map(\.name))
        return rows.filter {
            let v = ($0.fields()[f.key] as? String) ?? ""
            return v.isEmpty || !names.contains(v)
        }
    }

    private func column(label: String, option: FieldOption?, records: [ObjectRecord]) -> some View {
        let columnColor: Color = option?.colorHex.flatMap(Color.init(hex:)) ?? .secondary
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(columnColor).frame(width: 8, height: 8)
                Text(label).font(.caption.weight(.semibold))
                    .textCase(.uppercase).tracking(0.5)
                Text("\(records.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
            }
            ForEach(records) { record in
                kanbanCard(record: record)
            }
        }
        .frame(width: 260, alignment: .topLeading)
    }

    private func kanbanCard(record: ObjectRecord) -> some View {
        let fields = type.fields.filter {
            $0.key != type.primaryFieldKey
            && $0.kind != .longText
            && $0.kind != .attachment
        }.prefix(3)

        return VStack(alignment: .leading, spacing: 6) {
            Text(FieldDisplay.title(of: record, in: type))
                .font(.body.weight(.semibold))
                .lineLimit(2)
            ForEach(Array(fields), id: \.id) { field in
                HStack(spacing: 6) {
                    Image(systemName: field.kind.systemImage)
                        .foregroundStyle(.tertiary).imageScale(.small)
                    Text(field.name).font(.caption2).foregroundStyle(.tertiary)
                    Spacer()
                    FieldDisplay.cell(field: field, value: record.fields()[field.key])
                        .font(.caption)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.18)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onOpen(record.id) }
    }
}

// MARK: - Calendar body

struct RecordsCalendarBody: View {
    let type: ObjectType
    let rows: [ObjectRecord]
    var onOpen: (String) -> Void

    @State private var month: Date = Date()

    var body: some View {
        if dateField == nil {
            VStack {
                Spacer()
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 40)).foregroundStyle(.tertiary)
                Text("This type has no date field.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                monthHeader
                Divider()
                monthGrid
            }
        }
    }

    private var dateField: FieldDef? {
        if let key = type.calendarDateKey, let f = type.field(forKey: key), f.kind.canDateForCalendar { return f }
        return type.fields.first { $0.kind.canDateForCalendar }
    }

    private var monthHeader: some View {
        HStack {
            Button { month = Calendar.current.date(byAdding: .month, value: -1, to: month) ?? month } label: {
                Image(systemName: "chevron.left")
            }
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(.title3).bold().frame(width: 240, alignment: .center)
            Button { month = Calendar.current.date(byAdding: .month, value: 1, to: month) ?? month } label: {
                Image(systemName: "chevron.right")
            }
            Button("Today") { month = Date() }
                .buttonStyle(.bordered)
            Spacer()
        }
        .padding(16)
    }

    private var monthGrid: some View {
        let cal = Calendar.current
        let days = monthDays(for: month)
        let recordsByDay = recordsGroupedByDay()

        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { day in
                    Text(day)
                        .font(.caption.weight(.semibold)).textCase(.uppercase).tracking(0.5)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
            }
            .background(Color.secondary.opacity(0.08))
            Divider()

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                ForEach(days, id: \.self) { day in
                    dayCell(day: day, isCurrentMonth: cal.isDate(day, equalTo: month, toGranularity: .month),
                            records: recordsByDay[cal.startOfDay(for: day), default: []])
                }
            }
        }
    }

    private var weekdaySymbols: [String] {
        let f = DateFormatter()
        f.locale = Locale.current
        // Sunday-first (US default) but local overrides; keep first-letter form to fit narrow cells.
        return f.veryShortStandaloneWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
    }

    private func dayCell(day: Date, isCurrentMonth: Bool, records: [ObjectRecord]) -> some View {
        let dayNumber = Calendar.current.component(.day, from: day)
        return VStack(alignment: .leading, spacing: 2) {
            Text("\(dayNumber)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isCurrentMonth ? .primary : .tertiary)
                .padding(.bottom, 2)
            ForEach(records.prefix(3)) { record in
                Text(FieldDisplay.title(of: record, in: type))
                    .font(.caption2)
                    .lineLimit(1)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background((Color(hex: type.colorHex) ?? .accentColor).opacity(0.18))
                    .foregroundStyle(Color(hex: type.colorHex) ?? .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onTapGesture(count: 2) { onOpen(record.id) }
            }
            if records.count > 3 {
                Text("+\(records.count - 3) more")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
        .background(isCurrentMonth ? Color.clear : Color.secondary.opacity(0.04))
        .overlay {
            Rectangle().stroke(Color.secondary.opacity(0.12), lineWidth: 0.5)
        }
    }

    private func monthDays(for month: Date) -> [Date] {
        let cal = Calendar.current
        guard let monthStart = cal.dateInterval(of: .month, for: month)?.start,
              let monthEnd = cal.dateInterval(of: .month, for: month)?.end else { return [] }
        // Pad to start of week for the row containing monthStart.
        let weekday = cal.component(.weekday, from: monthStart)
        let firstWeekday = cal.firstWeekday
        let prePad = (weekday - firstWeekday + 7) % 7
        let gridStart = cal.date(byAdding: .day, value: -prePad, to: monthStart)!

        var days: [Date] = []
        var cursor = gridStart
        while cursor < monthEnd || days.count % 7 != 0 {
            days.append(cursor)
            cursor = cal.date(byAdding: .day, value: 1, to: cursor)!
            if days.count >= 42 { break } // 6 weeks max
        }
        return days
    }

    private func recordsGroupedByDay() -> [Date: [ObjectRecord]] {
        guard let field = dateField else { return [:] }
        let cal = Calendar.current
        var out: [Date: [ObjectRecord]] = [:]
        for r in rows {
            guard let d = FieldDisplay.parsedDate(r.fields()[field.key]) else { continue }
            let day = cal.startOfDay(for: d)
            out[day, default: []].append(r)
        }
        return out
    }
}

// MARK: - Gallery body

struct RecordsGalleryBody: View {
    let type: ObjectType
    let rows: [ObjectRecord]
    var onOpen: (String) -> Void

    private let columns = [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(rows) { record in
                    galleryCard(record: record)
                        .onTapGesture(count: 2) { onOpen(record.id) }
                }
            }
            .padding(16)
        }
    }

    private func galleryCard(record: ObjectRecord) -> some View {
        let supportingField = type.fields.first { $0.kind == .select || $0.kind == .rating }
        return VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                imageOrPlaceholder(for: record)
                if let f = supportingField, f.kind == .rating {
                    FieldDisplay.ratingView(value: record.fields()[f.key])
                        .padding(6)
                        .background(.thinMaterial, in: Capsule())
                        .padding(8)
                }
            }
            Text(FieldDisplay.title(of: record, in: type))
                .font(.body.weight(.semibold))
                .lineLimit(2)
            if let f = supportingField, f.kind == .select {
                FieldDisplay.selectChip(value: record.fields()[f.key], options: f.options)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Renders the real attachment image when the type's
    /// `galleryAttachmentKey` field has a sha256 ref that resolves to a
    /// readable image. Falls back to the type-tinted gradient stand-in
    /// otherwise.
    @ViewBuilder
    private func imageOrPlaceholder(for record: ObjectRecord) -> some View {
        if let key = type.galleryAttachmentKey,
           let sha = record.fields()[key] as? String, !sha.isEmpty,
           let url = AttachmentService.fileURL(forSha256: sha),
           let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(4/3, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15)))
        } else {
            placeholderImage
        }
    }

    private var placeholderImage: some View {
        let base = Color(hex: type.colorHex) ?? .accentColor
        return RoundedRectangle(cornerRadius: 10)
            .fill(LinearGradient(
                colors: [base.opacity(0.6), base.opacity(0.2)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
            .aspectRatio(4/3, contentMode: .fit)
            .overlay {
                Image(systemName: type.systemImage)
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.6))
            }
    }
}

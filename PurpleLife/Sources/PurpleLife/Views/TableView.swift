import SwiftUI

/// Generic spreadsheet over any object type. Phase 2 starting point —
/// columns derive from the type's `fields` in order. Rendered as a
/// horizontally-scrollable grid built from `LazyVGrid` rows so the
/// column count is dynamic (SwiftUI's native `Table` requires static
/// columns at compile time, which doesn't fit a runtime-defined schema).
struct TableViewScreen: View {
    @EnvironmentObject private var appState: AppState
    let typeId: String

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
                tableBody
            }
        }
        .toolbar {
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
        .onChange(of: typeId) { _, _ in reload() }
        .sheet(isPresented: Binding(
            get: { editingRecordId != nil },
            set: { if !$0 { editingRecordId = nil } }
        )) {
            if let id = editingRecordId {
                ObjectDetailSheet(recordId: id, onChange: { reload(); appState.reloadAll() })
                    .environmentObject(appState)
            }
        }
    }

    private var type: ObjectType? {
        appState.schema.type(id: typeId)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
    private var tableBody: some View {
        if let t = type {
            let fields = orderedFields(for: t)
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
    }

    private func headerRow(fields: [FieldDef]) -> some View {
        HStack(spacing: 0) {
            ForEach(fields, id: \.id) { field in
                Text(field.name)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .foregroundStyle(.secondary)
                    .frame(width: columnWidth(for: field), alignment: .leading)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
            }
        }
        .background(Color.secondary.opacity(0.08))
        .overlay(alignment: .bottom) { Divider() }
    }

    private func dataRow(fields: [FieldDef], row: ObjectRecord, even: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(fields, id: \.id) { field in
                cell(field: field, row: row)
                    .frame(width: columnWidth(for: field), alignment: .leading)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
            }
        }
        .contentShape(Rectangle())
        .background(even ? Color.clear : Color.secondary.opacity(0.04))
        .overlay(alignment: .bottom) {
            Divider().opacity(0.6)
        }
        .onTapGesture(count: 2) { editingRecordId = row.id }
        .contextMenu {
            Button("Open") { editingRecordId = row.id }
            Divider()
            Button("Delete", role: .destructive) { deleteRow(row) }
        }
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

    private func orderedFields(for t: ObjectType) -> [FieldDef] {
        guard let primaryKey = t.primaryFieldKey else { return t.fields }
        var ordered = t.fields
        if let primaryIdx = ordered.firstIndex(where: { $0.key == primaryKey }), primaryIdx > 0 {
            let primary = ordered.remove(at: primaryIdx)
            ordered.insert(primary, at: 0)
        }
        return ordered
    }

    @ViewBuilder
    private func cell(field: FieldDef, row: ObjectRecord) -> some View {
        let value = row.fields()[field.key]
        let isPrimary = field.key == type?.primaryFieldKey
        let raw = stringValue(value)

        switch field.kind {
        case .text, .longText, .url, .email:
            if raw.isEmpty {
                if isPrimary {
                    Text("Untitled")
                        .italic()
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                } else {
                    Text("—")
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text(raw).lineLimit(1)
            }
        case .number:
            if let s = numberValueOrNil(value) {
                Text(s).monospacedDigit()
            } else {
                Text("—").foregroundStyle(.tertiary)
            }
        case .date, .dateTime:
            if let s = dateValueOrNil(value, includeTime: field.kind == .dateTime) {
                Text(s).foregroundStyle(.secondary)
            } else {
                Text("—").foregroundStyle(.tertiary)
            }
        case .boolean:
            Image(systemName: (value as? Bool) == true ? "checkmark.square.fill" : "square")
                .foregroundStyle((value as? Bool) == true ? Color.green : .secondary)
        case .select:
            selectChip(value: value, options: field.options)
        case .multiSelect:
            multiSelectChips(value: value, options: field.options)
        case .link:
            if raw.isEmpty {
                Text("—").foregroundStyle(.tertiary)
            } else {
                Text(raw).foregroundStyle(.tint).underline()
            }
        case .rating:
            ratingView(value: value)
        case .attachment:
            if raw.isEmpty {
                Text("—").foregroundStyle(.tertiary)
            } else {
                Image(systemName: "paperclip").foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Cell renderers

    private func stringValue(_ v: Any?) -> String {
        if let s = v as? String, !s.isEmpty { return s }
        return ""
    }

    private func numberValueOrNil(_ v: Any?) -> String? {
        if let d = v as? Double { return d.formatted() }
        if let i = v as? Int    { return "\(i)" }
        return nil
    }

    private func dateValueOrNil(_ v: Any?, includeTime: Bool) -> String? {
        guard let s = v as? String, !s.isEmpty,
              let date = ISO8601DateFormatter().date(from: s) else {
            return nil
        }
        return date.formatted(date: .abbreviated, time: includeTime ? .shortened : .omitted)
    }

    private func selectChip(value: Any?, options: [FieldOption]) -> some View {
        let label = stringValue(value)
        let opt = options.first { $0.name == label }
        let chipColor: Color = opt?.colorHex.flatMap(Color.init(hex:)) ?? .secondary
        return Group {
            if !label.isEmpty {
                Text(label)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(chipColor.opacity(0.2))
                    .foregroundStyle(chipColor)
                    .clipShape(Capsule())
            } else {
                Text("—").foregroundStyle(.tertiary)
            }
        }
    }

    private func multiSelectChips(value: Any?, options: [FieldOption]) -> some View {
        let labels = (value as? [String]) ?? []
        return HStack(spacing: 4) {
            ForEach(labels, id: \.self) { label in
                let opt = options.first { $0.name == label }
                let chipColor: Color = opt?.colorHex.flatMap(Color.init(hex:)) ?? .secondary
                Text(label)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(chipColor.opacity(0.2))
                    .foregroundStyle(chipColor)
                    .clipShape(Capsule())
            }
        }
    }

    private func ratingView(value: Any?) -> some View {
        let stars = (value as? Int) ?? Int((value as? Double) ?? 0)
        return HStack(spacing: 1) {
            ForEach(0..<5, id: \.self) { i in
                Image(systemName: i < stars ? "star.fill" : "star")
                    .foregroundStyle(i < stars ? Color.yellow : .secondary)
                    .imageScale(.small)
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

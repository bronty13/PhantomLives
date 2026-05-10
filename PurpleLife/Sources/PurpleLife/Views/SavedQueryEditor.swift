import SwiftUI

/// Phase 3 — let the user customize the Today panels. Two views:
///
/// - `SavedQueriesEditor` — sheet listing every saved query with reorder
///   / delete / add controls and an inline open-for-edit action.
/// - `SavedQueryEditor`  — sheet form for one saved query (add or edit),
///   schema-aware: the field pickers are scoped to the selected type's
///   actual fields.
struct SavedQueriesEditor: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var editing: SavedQuery?
    @State private var creatingNew: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Today panels").font(.title2).bold()
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
            Divider()

            if appState.settingsStore.settings.todayQueries.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(appState.settingsStore.settings.todayQueries) { query in
                        row(query: query)
                    }
                    .onMove(perform: move)
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }

            Divider()
            HStack {
                Button {
                    creatingNew = true
                } label: {
                    Label("Add panel", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                Spacer()
                Button("Restore defaults") {
                    restoreDefaults()
                }
            }
            .padding(16)
        }
        .frame(minWidth: 520, minHeight: 460)
        .sheet(item: $editing) { query in
            SavedQueryEditor(initial: query) { updated in
                replace(query, with: updated)
                editing = nil
            } onDelete: {
                delete(query)
                editing = nil
            }
            .environmentObject(appState)
        }
        .sheet(isPresented: $creatingNew) {
            SavedQueryEditor(initial: makeBlank()) { created in
                var s = appState.settings
                s.todayQueries.append(created)
                appState.settings = s
                creatingNew = false
            } onDelete: {
                creatingNew = false
            }
            .environmentObject(appState)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "rectangle.stack")
                .font(.system(size: 40)).foregroundStyle(.tertiary)
            Text("No panels.").font(.headline).foregroundStyle(.secondary)
            Text("Click Add panel below to create one, or Restore defaults to get the starter set back.")
                .font(.subheadline).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center).padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(query: SavedQuery) -> some View {
        HStack(spacing: 10) {
            Image(systemName: query.systemImage)
                .foregroundStyle(.tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(query.name).font(.body)
                Text(summary(of: query))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            if query.builtIn {
                Text("default")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
            }
            Button { editing = query } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            .help("Edit panel")
            Button(role: .destructive) { delete(query) } label: {
                Image(systemName: "trash").foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Delete panel")
        }
        .padding(.vertical, 4)
    }

    private func summary(of query: SavedQuery) -> String {
        var parts: [String] = []
        if let typeId = query.typeId, let t = appState.schema.type(id: typeId) {
            parts.append(t.pluralName)
        } else {
            parts.append("All types")
        }
        if let key = query.filterFieldKey, let v = query.filterValue {
            switch v {
            case .string(let s):     parts.append("\(key) = \(s)")
            case .bool(let b):       parts.append("\(key) = \(b)")
            case .withinDays(let d): parts.append("updated within \(d)d")
            case .nonEmpty:          parts.append("\(key) is set")
            }
        } else if case .withinDays(let d) = query.filterValue {
            parts.append("updated within \(d)d")
        }
        parts.append("limit \(query.limit)")
        return parts.joined(separator: " · ")
    }

    // MARK: - Mutations

    private func makeBlank() -> SavedQuery {
        SavedQuery.make(
            name: "New panel",
            systemImage: "rectangle.stack",
            typeId: appState.schema.visibleTypes.first?.id,
            limit: 5
        )
    }

    private func replace(_ query: SavedQuery, with updated: SavedQuery) {
        var s = appState.settings
        if let idx = s.todayQueries.firstIndex(where: { $0.id == query.id }) {
            s.todayQueries[idx] = updated
        }
        appState.settings = s
    }

    private func delete(_ query: SavedQuery) {
        var s = appState.settings
        s.todayQueries.removeAll { $0.id == query.id }
        appState.settings = s
    }

    private func move(from source: IndexSet, to destination: Int) {
        var s = appState.settings
        s.todayQueries.move(fromOffsets: source, toOffset: destination)
        appState.settings = s
    }

    private func restoreDefaults() {
        var s = appState.settings
        let existingIds = Set(s.todayQueries.map(\.id))
        for seed in SavedQuerySeed.allDefaults where !existingIds.contains(seed.id) {
            s.todayQueries.append(seed)
        }
        appState.settings = s
    }
}

// MARK: - Single-query editor

struct SavedQueryEditor: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State var working: SavedQuery
    let originalId: String
    var onSave: (SavedQuery) -> Void
    var onDelete: () -> Void

    @State private var filterEnabled: Bool
    @State private var filterStringValue: String
    @State private var filterDays: Int
    @State private var filterKind: FilterKind

    enum FilterKind: String, CaseIterable, Identifiable {
        case none, equals, withinDays, nonEmpty
        var id: String { rawValue }
        var label: String {
            switch self {
            case .none:       return "No filter"
            case .equals:     return "Field equals…"
            case .withinDays: return "Updated within N days"
            case .nonEmpty:   return "Field is set"
            }
        }
    }

    init(initial: SavedQuery, onSave: @escaping (SavedQuery) -> Void, onDelete: @escaping () -> Void) {
        _working = State(initialValue: initial)
        self.originalId = initial.id
        self.onSave = onSave
        self.onDelete = onDelete

        switch initial.filterValue {
        case .none:
            _filterEnabled = State(initialValue: false)
            _filterKind = State(initialValue: .none)
            _filterStringValue = State(initialValue: "")
            _filterDays = State(initialValue: 7)
        case .string(let s):
            _filterEnabled = State(initialValue: true)
            _filterKind = State(initialValue: .equals)
            _filterStringValue = State(initialValue: s)
            _filterDays = State(initialValue: 7)
        case .bool(let b):
            _filterEnabled = State(initialValue: true)
            _filterKind = State(initialValue: .equals)
            _filterStringValue = State(initialValue: b ? "true" : "false")
            _filterDays = State(initialValue: 7)
        case .withinDays(let d):
            _filterEnabled = State(initialValue: true)
            _filterKind = State(initialValue: .withinDays)
            _filterStringValue = State(initialValue: "")
            _filterDays = State(initialValue: d)
        case .nonEmpty:
            _filterEnabled = State(initialValue: true)
            _filterKind = State(initialValue: .nonEmpty)
            _filterStringValue = State(initialValue: "")
            _filterDays = State(initialValue: 7)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                Form {
                    panelMetaSection
                    typeSection
                    filterSection
                    sortSection
                }
                .formStyle(.grouped)
                .padding(.bottom, 8)
            }
            Divider()
            footer
        }
        .frame(minWidth: 520, minHeight: 600)
    }

    private var header: some View {
        HStack {
            Image(systemName: working.systemImage).foregroundStyle(.tint)
            Text(working.name.isEmpty ? "New panel" : working.name)
                .font(.title2).bold()
            Spacer()
        }
        .padding(20)
    }

    private var panelMetaSection: some View {
        Section("Panel") {
            TextField("Name", text: $working.name)
            Picker("Icon", selection: $working.systemImage) {
                ForEach(iconChoices, id: \.self) { name in
                    Label(name, systemImage: name).tag(name)
                }
            }
            .pickerStyle(.menu)
            Stepper("Limit: \(working.limit)", value: $working.limit, in: 1...100)
        }
    }

    private var typeSection: some View {
        Section("Type") {
            Picker("Type", selection: typeBinding) {
                Text("All types").tag(String?.none)
                ForEach(appState.schema.visibleTypes) { type in
                    Label(type.pluralName, systemImage: type.systemImage).tag(String?.some(type.id))
                }
            }
            .pickerStyle(.menu)
            if working.typeId == nil, filterKind == .equals {
                Text("Field-equals filter requires a specific type.")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private var filterSection: some View {
        Section("Filter") {
            Picker("Filter", selection: $filterKind) {
                ForEach(FilterKind.allCases) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .pickerStyle(.menu)
            switch filterKind {
            case .none:
                Text("Show every record matching the type.")
                    .font(.caption).foregroundStyle(.secondary)
            case .equals:
                if let type = currentType {
                    Picker("Field", selection: filterFieldBinding) {
                        Text("Pick a field").tag(String?.none)
                        ForEach(type.fields) { f in
                            Label(f.name, systemImage: f.kind.systemImage).tag(String?.some(f.key))
                        }
                    }
                    .pickerStyle(.menu)
                    if let key = working.filterFieldKey, let f = type.field(forKey: key), f.kind == .select {
                        Picker("Value", selection: $filterStringValue) {
                            Text("—").tag("")
                            ForEach(f.options) { opt in
                                Text(opt.name).tag(opt.name)
                            }
                        }
                        .pickerStyle(.menu)
                    } else {
                        TextField("Value", text: $filterStringValue)
                    }
                } else {
                    Text("Pick a type above to choose a field.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            case .withinDays:
                Stepper("Within last \(filterDays) day\(filterDays == 1 ? "" : "s")",
                        value: $filterDays, in: 1...365)
                Text("Compares against `updated_at`.")
                    .font(.caption).foregroundStyle(.tertiary)
            case .nonEmpty:
                if let type = currentType {
                    Picker("Field", selection: filterFieldBinding) {
                        Text("Pick a field").tag(String?.none)
                        ForEach(type.fields) { f in
                            Label(f.name, systemImage: f.kind.systemImage).tag(String?.some(f.key))
                        }
                    }
                    .pickerStyle(.menu)
                } else {
                    Text("Pick a type above to choose a field.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var sortSection: some View {
        Section("Sort") {
            if let type = currentType {
                Picker("Sort by", selection: sortFieldBinding) {
                    Text("Last modified (default)").tag(String?.none)
                    ForEach(type.fields) { f in
                        Label(f.name, systemImage: f.kind.systemImage).tag(String?.some(f.key))
                    }
                }
                .pickerStyle(.menu)
            } else {
                Picker("Sort by", selection: sortFieldBinding) {
                    Text("Last modified").tag(String?.none)
                }
                .pickerStyle(.menu)
                .disabled(true)
            }
            Toggle("Descending", isOn: $working.descending)
        }
    }

    private var footer: some View {
        HStack {
            if !working.builtIn {
                Button("Delete", role: .destructive) {
                    onDelete()
                    dismiss()
                }
            }
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Save") { commit() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(working.name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(20)
    }

    // MARK: - Helpers

    private var currentType: ObjectType? {
        working.typeId.flatMap { appState.schema.type(id: $0) }
    }

    private var typeBinding: Binding<String?> {
        Binding(
            get: { working.typeId },
            set: { newValue in
                working.typeId = newValue
                // Reset field-tied state since the field set changes.
                working.filterFieldKey = nil
                working.sortFieldKey = nil
                filterStringValue = ""
            }
        )
    }

    private var filterFieldBinding: Binding<String?> {
        Binding(
            get: { working.filterFieldKey },
            set: { working.filterFieldKey = $0 }
        )
    }

    private var sortFieldBinding: Binding<String?> {
        Binding(
            get: { working.sortFieldKey },
            set: { working.sortFieldKey = $0 }
        )
    }

    private var iconChoices: [String] {
        [
            "rectangle.stack", "sparkles", "calendar", "calendar.day.timeline.left",
            "book.closed", "book", "person.2", "person.crop.circle", "scalemass",
            "checkmark.circle", "star", "camera", "photo", "tag", "flag",
            "pin", "house", "globe", "graduationcap", "fork.knife"
        ]
    }

    private func commit() {
        // Project the filter UI back onto SavedQuery.FilterValue.
        switch filterKind {
        case .none:
            working.filterFieldKey = nil
            working.filterValue = nil
        case .equals:
            if let _ = working.filterFieldKey, !filterStringValue.isEmpty {
                working.filterValue = .string(filterStringValue)
            } else {
                working.filterFieldKey = nil
                working.filterValue = nil
            }
        case .withinDays:
            working.filterFieldKey = nil
            working.filterValue = .withinDays(filterDays)
        case .nonEmpty:
            if working.filterFieldKey == nil {
                working.filterValue = nil
            } else {
                working.filterValue = .nonEmpty
            }
        }
        // Preserve the original id for edits — `_=originalId` stops a
        // missed-rename from accidentally creating a new panel.
        working.id = originalId
        onSave(working)
        dismiss()
    }
}

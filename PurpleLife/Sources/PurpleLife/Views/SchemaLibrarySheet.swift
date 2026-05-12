import SwiftUI

/// Searchable gallery of curated schemas the user can import into their
/// workspace from the Schema Editor. Presented as a sheet over the
/// editor window; users browse by category, search by free-text, preview
/// the field list, and tap Import to clone the entry into their
/// SchemaRegistry as a brand-new user-defined type.
///
/// The entries come from `SchemaLibrary.entries`. Each import goes
/// through `Entry.materialize()` which stamps fresh UUIDs on the type
/// and every field so the same library entry can be imported multiple
/// times without colliding.
struct SchemaLibrarySheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    /// Callback fired after a successful import with the new type's id,
    /// so the parent (SchemaEditor) can select it.
    var onImported: ((String) -> Void)?

    @State private var selectedCategory: SchemaLibrary.Category? = nil
    @State private var query: String = ""
    @State private var selectedEntryId: String? = nil
    @State private var lastImported: String? = nil   // entry id whose green checkmark is showing

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                categorySidebar
                    .frame(minWidth: 200, idealWidth: 220, maxWidth: 280)
                resultsList
                    .frame(minWidth: 320, idealWidth: 360, maxWidth: 460)
                previewPane
                    .frame(minWidth: 360)
            }
        }
        .frame(minWidth: 960, minHeight: 600)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "books.vertical.fill")
                .imageScale(.large)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("Schema library").font(.title3.weight(.semibold))
                Text("Import a ready-made schema, then customize it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            TextField("Search the library", text: $query)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(Theme.bg.opacity(0.6))
    }

    // MARK: - Category sidebar

    private var categorySidebar: some View {
        List(selection: Binding<SchemaLibrary.Category?>(
            get: { selectedCategory },
            set: { selectedCategory = $0 }
        )) {
            Section("Browse") {
                HStack {
                    Image(systemName: "tray.full")
                        .foregroundStyle(.secondary)
                    Text("All")
                    Spacer()
                    Text("\(SchemaLibrary.entries.count)")
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
                .tag(SchemaLibrary.Category?.none)

                ForEach(SchemaLibrary.Category.allCases, id: \.self) { cat in
                    let count = SchemaLibrary.entries.filter { $0.category == cat }.count
                    HStack {
                        Image(systemName: cat.systemImage)
                            .foregroundStyle(.secondary)
                            .frame(width: 22)
                        Text(cat.rawValue)
                            .lineLimit(1)
                        Spacer()
                        if count > 0 {
                            Text("\(count)")
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                        }
                    }
                    .tag(SchemaLibrary.Category?.some(cat))
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Results list

    private var filteredEntries: [SchemaLibrary.Entry] {
        SchemaLibrary.search(query: query, category: selectedCategory)
    }

    private var resultsList: some View {
        VStack(spacing: 0) {
            HStack {
                Text(selectedCategory?.rawValue ?? (query.isEmpty ? "All schemas" : "Search results"))
                    .font(.headline)
                Spacer()
                Text("\(filteredEntries.count)")
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            Divider()

            if filteredEntries.isEmpty {
                emptyState
            } else {
                List(selection: Binding<String?>(
                    get: { selectedEntryId },
                    set: { selectedEntryId = $0 }
                )) {
                    ForEach(filteredEntries) { entry in
                        entryRow(entry).tag(entry.id)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: false))
            }
        }
    }

    private func entryRow(_ entry: SchemaLibrary.Entry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: entry.template.systemImage)
                .foregroundStyle(Color(hex: entry.template.colorHex) ?? .accentColor)
                .imageScale(.medium)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.template.pluralName).font(.body)
                Text(entry.blurb)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text("\(entry.template.fields.count)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
            if lastImported == entry.id {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .imageScale(.small)
                    .accessibilityLabel("Imported")
            }
        }
        .padding(.vertical, 2)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .imageScale(.large)
                .foregroundStyle(.tertiary)
            Text("No schemas match \"\(query)\"")
                .font(.body)
                .foregroundStyle(.secondary)
            Text("Try a different search or pick another category.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Preview pane

    @ViewBuilder
    private var previewPane: some View {
        if let id = selectedEntryId, let entry = SchemaLibrary.entry(id: id) {
            entryPreview(entry)
        } else if let first = filteredEntries.first {
            // Auto-select the first result so the preview pane isn't
            // empty when the sheet opens.
            entryPreview(first)
                .onAppear { selectedEntryId = first.id }
        } else {
            VStack {
                Spacer()
                Image(systemName: "rectangle.dashed")
                    .imageScale(.large)
                    .foregroundStyle(.tertiary)
                Text("Pick a schema to preview")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func entryPreview(_ entry: SchemaLibrary.Entry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hero
            HStack(spacing: 12) {
                Image(systemName: entry.template.systemImage)
                    .foregroundStyle(Color(hex: entry.template.colorHex) ?? .accentColor)
                    .imageScale(.large)
                    .font(.system(size: 24))
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.template.name).font(.title3.weight(.semibold))
                    HStack(spacing: 6) {
                        Image(systemName: entry.category.systemImage)
                            .imageScale(.small)
                            .foregroundStyle(.tertiary)
                        Text(entry.category.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    importEntry(entry)
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(entry.blurb)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 18).padding(.top, 14)

                    viewDefaultsCard(entry)

                    Text("Fields")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.5)
                        .padding(.horizontal, 18).padding(.top, 4)

                    VStack(spacing: 0) {
                        ForEach(entry.template.fields) { field in
                            fieldRow(field, primary: entry.template.primaryFieldKey == field.key)
                        }
                    }
                    .padding(.horizontal, 18)
                }
                .padding(.bottom, 18)
            }
        }
    }

    private func viewDefaultsCard(_ entry: SchemaLibrary.Entry) -> some View {
        let primary = entry.template.fields.first { $0.key == entry.template.primaryFieldKey }?.name
        let kanban  = entry.template.fields.first { $0.key == entry.template.kanbanGroupKey }?.name
        let calendar = entry.template.fields.first { $0.key == entry.template.calendarDateKey }?.name
        let gallery = entry.template.fields.first { $0.key == entry.template.galleryAttachmentKey }?.name

        return VStack(alignment: .leading, spacing: 6) {
            Text("VIEW DEFAULTS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
            HStack(spacing: 14) {
                viewDefaultBadge(label: "Primary", systemImage: "star", value: primary)
                viewDefaultBadge(label: "Kanban", systemImage: "rectangle.split.3x1", value: kanban)
                viewDefaultBadge(label: "Calendar", systemImage: "calendar", value: calendar)
                viewDefaultBadge(label: "Gallery", systemImage: "photo.on.rectangle", value: gallery)
            }
        }
        .padding(.horizontal, 18).padding(.top, 6)
    }

    private func viewDefaultBadge(label: String, systemImage: String, value: String?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .imageScale(.small)
                .foregroundStyle(value == nil ? .tertiary : .secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.caption2).foregroundStyle(.tertiary)
                Text(value ?? "—")
                    .font(.caption)
                    .foregroundStyle(value == nil ? .tertiary : .primary)
                    .lineLimit(1)
            }
        }
    }

    private func fieldRow(_ field: FieldDef, primary: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: field.kind.systemImage)
                .foregroundStyle(.secondary)
                .imageScale(.medium)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(field.name).font(.body)
                    if primary {
                        Text("primary")
                            .font(.caption2)
                            .foregroundStyle(Theme.accent)
                    }
                    if field.required {
                        Text("required")
                            .font(.caption2)
                            .foregroundStyle(.red.opacity(0.85))
                    }
                }
                HStack(spacing: 6) {
                    Text(field.kind.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                    if !field.options.isEmpty {
                        Text("\(field.options.count) options")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if let desc = field.description, !desc.isEmpty {
                        Text(desc)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline).frame(height: 0.5)
        }
    }

    // MARK: - Actions

    private func importEntry(_ entry: SchemaLibrary.Entry) {
        let fresh = entry.materialize()
        appState.schema.upsertType(fresh)
        lastImported = entry.id
        onImported?(fresh.id)
        // Reset the green-check hint after a moment so the sheet stays
        // honest about which row is "fresh" if the user imports another.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if lastImported == entry.id { lastImported = nil }
        }
    }
}

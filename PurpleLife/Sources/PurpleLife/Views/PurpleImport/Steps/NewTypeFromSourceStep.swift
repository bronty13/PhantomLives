import SwiftUI

/// Step 3a — define a new type inline. Minimal author UI; the full
/// Schema Editor handles complex shapes.
struct NewTypeFromSourceStep: View {
    @ObservedObject var model: ImportWizardModel
    @State private var iconSearch: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Define the new type").font(.title3).bold()
                Form {
                    Section {
                        TextField("Singular name", text: binding(\.name))
                        TextField("Plural name", text: binding(\.pluralName))
                        iconPickerRow
                        Toggle("Place in Vault", isOn: binding(\.isVault))
                    }
                    Section("Proposed fields") {
                        if let fields = model.draft.newTypeTemplate?.fields {
                            ForEach(Array(fields.enumerated()), id: \.offset) { idx, _ in
                                HStack(spacing: 10) {
                                    Image(systemName: fields[idx].kind.systemImage)
                                        .frame(width: 18).foregroundStyle(.secondary)
                                    TextField("Name", text: fieldBinding(idx, \.name))
                                    Picker("Kind", selection: fieldBinding(idx, \.kind)) {
                                        ForEach(FieldKind.allCases, id: \.self) { k in
                                            Text(k.displayName).tag(k)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(width: 160)
                                    Toggle("Required", isOn: fieldBinding(idx, \.required))
                                        .toggleStyle(.checkbox)
                                        .labelsHidden()
                                }
                            }
                        } else {
                            Text("No fields proposed — go back and run a source preview.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
                .formStyle(.grouped)
            }
            .padding(20)
        }
    }

    // MARK: - Icon picker

    /// Hand-picked SF Symbols covering the schema shapes most users
    /// build first: people, places, time, content, money, hobbies,
    /// data. Search filters this list live, so the user can find an
    /// icon by typing a fragment ("box" → archivebox, shippingbox,
    /// cube). Free-form SF-Symbol name entry happens by clicking the
    /// "Use ‘…’" button when the search string is a valid catalog
    /// name not in this curated list.
    private static let quickIcons: [String] = [
        // People & contact
        "person", "person.2", "person.3", "person.crop.circle", "person.text.rectangle",
        "envelope", "phone", "message", "bubble.left",
        // Places & travel
        "house", "building.2", "map", "location", "globe",
        "airplane", "car", "tram", "bicycle",
        // Time & schedule
        "calendar", "calendar.badge.clock", "clock", "timer", "alarm",
        "stopwatch", "hourglass",
        // Tasks & status
        "checkmark.circle", "checklist", "list.bullet", "list.bullet.clipboard",
        "exclamationmark.triangle", "flag", "bookmark", "tag",
        // Content & docs
        "book", "book.closed", "books.vertical",
        "doc", "doc.text", "note.text", "newspaper",
        "highlighter", "pencil", "square.and.pencil",
        // Media
        "photo", "photo.on.rectangle", "camera", "video", "film",
        "music.note", "music.note.list", "headphones", "speaker.wave.2",
        // Hobbies & lifestyle
        "scalemass", "figure.walk", "figure.run", "dumbbell", "sportscourt",
        "fork.knife", "cup.and.saucer", "wineglass", "leaf", "pawprint",
        // Money & shopping
        "cart", "bag", "creditcard", "banknote", "dollarsign.circle",
        "chart.bar", "chart.line.uptrend.xyaxis",
        // Containers & organization
        "tray.full", "folder", "archivebox", "shippingbox", "cube",
        "tray.and.arrow.down", "square.stack.3d.up",
        // Generic / fallback
        "star", "heart", "sparkles", "questionmark.circle", "circle.grid.2x2",
        "ellipsis.circle", "info.circle"
    ]

    private var filteredIcons: [String] {
        let q = iconSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return Self.quickIcons }
        return Self.quickIcons.filter { $0.lowercased().contains(q) }
    }

    /// `true` when the search string is a valid-looking SF Symbol
    /// name that renders to an actual glyph — so the user can use it
    /// even if it isn't in `quickIcons`. NSImage's resolution is the
    /// safest "is this a real symbol?" probe on macOS.
    private var isSearchAValidSymbol: Bool {
        let q = iconSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !q.contains(" ") else { return false }
        return NSImage(systemSymbolName: q, accessibilityDescription: nil) != nil
    }

    @ViewBuilder
    private var iconPickerRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top line: live preview + search field. The search both
            // filters the palette below and (when it resolves to a
            // real symbol) offers a one-click "use this name" button.
            HStack(spacing: 10) {
                Image(systemName: model.draft.newTypeTemplate?.systemImage ?? "questionmark.circle")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Icon").font(.body)
                    Text("Click an icon below, or search by name")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.tertiary)
                    TextField("Search icons (e.g. star, calendar, book)", text: $iconSearch)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .frame(width: 220)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.08))
                )
            }

            // Filtered palette. Click to set.
            if filteredIcons.isEmpty {
                noResultsHint
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.fixed(32), spacing: 4), count: 18),
                        alignment: .leading, spacing: 4
                    ) {
                        ForEach(filteredIcons, id: \.self) { name in
                            Button {
                                model.draft.newTypeTemplate?.systemImage = name
                            } label: {
                                Image(systemName: name)
                                    .font(.body)
                                    .frame(width: 28, height: 28)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(model.draft.newTypeTemplate?.systemImage == name
                                                  ? Color.accentColor.opacity(0.25)
                                                  : Color.secondary.opacity(0.08))
                                    )
                            }
                            .buttonStyle(.plain)
                            .help(name)
                        }
                    }
                    .padding(.horizontal, 2).padding(.vertical, 4)
                }
                .frame(maxHeight: 96)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var noResultsHint: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No icons match ‘\(iconSearch)’ in the curated set.")
                .font(.caption).foregroundStyle(.secondary)
            if isSearchAValidSymbol {
                // The search string is a valid catalog name (resolves
                // to an actual SF Symbol glyph) — let the user accept
                // it directly.
                Button {
                    model.draft.newTypeTemplate?.systemImage = iconSearch.trimmingCharacters(in: .whitespacesAndNewlines)
                    iconSearch = ""
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: iconSearch.trimmingCharacters(in: .whitespacesAndNewlines))
                        Text("Use ‘\(iconSearch.trimmingCharacters(in: .whitespacesAndNewlines))’")
                    }
                }
                .controlSize(.small)
            } else {
                Text("Browse the full SF Symbols catalog at developer.apple.com/sf-symbols, then paste an exact symbol name.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Bindings

    private func binding<T>(_ keyPath: WritableKeyPath<SavedImportMapping.NewTypeTemplate, T>) -> Binding<T> {
        Binding(
            get: { model.draft.newTypeTemplate![keyPath: keyPath] },
            set: { newValue in model.draft.newTypeTemplate?[keyPath: keyPath] = newValue }
        )
    }

    private func fieldBinding<T>(_ index: Int, _ keyPath: WritableKeyPath<SavedImportMapping.NewTypeTemplate.ProposedField, T>) -> Binding<T> {
        Binding(
            get: { model.draft.newTypeTemplate!.fields[index][keyPath: keyPath] },
            set: { newValue in model.draft.newTypeTemplate?.fields[index][keyPath: keyPath] = newValue }
        )
    }
}

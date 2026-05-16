import SwiftUI
import UniformTypeIdentifiers
import AppKit

/// Schema editor — the distinctive screen from the design (per
/// `Design/MANIFEST.md`). Shows the visible types in a left rail and the
/// selected type's field list on the right, with a field-type palette
/// at the bottom for adding new fields. Both click-to-add and
/// drag-from-palette work; the field list is also a drop destination
/// for the palette.
struct SchemaEditorScreen: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.undoManager) private var undoManager

    @State private var selectedTypeId: String?
    @State private var editingFieldId: String?
    @State private var renamingFieldId: String?
    @State private var newTypeName: String = ""

    // Library + import/export state
    @State private var showLibrary = false
    @State private var showResetConfirm = false
    @State private var importError: String? = nil
    @State private var showMultiExport = false
    @State private var multiExportSelection: Set<String> = []
    @State private var showManageTags = false
    @State private var showTypeTagPicker = false
    /// Field id whose `.select` / `.multiSelect` options sheet is open.
    /// Single-value because only one sheet can be modally presented
    /// at a time; `nil` means no editor is showing.
    @State private var editingOptionsForFieldId: String?

    var body: some View {
        HSplitView {
            typesRail
                .frame(minWidth: 220, idealWidth: 240, maxWidth: 320)
            VStack(spacing: 0) {
                fieldList
                Divider()
                fieldPalette
            }
        }
        .navigationTitle("Schema editor")
        .toolbar { toolbarContent }
        .sheet(isPresented: $showLibrary) {
            SchemaLibrarySheet(onImported: { newId in
                selectedTypeId = newId
            })
            .environmentObject(appState)
        }
        .sheet(isPresented: $showMultiExport) {
            MultiSchemaExportSheet(
                selection: $multiExportSelection,
                onExport: { ids in
                    exportTypes(ids: ids)
                    showMultiExport = false
                }
            )
            .environmentObject(appState)
        }
        .sheet(isPresented: $showManageTags) {
            TagManagementSheet()
                .environmentObject(appState)
        }
        .sheet(isPresented: Binding(
            get: { editingOptionsForFieldId != nil },
            set: { if !$0 { editingOptionsForFieldId = nil } }
        )) {
            if let typeId = selectedTypeId, let fieldId = editingOptionsForFieldId {
                SelectOptionsEditor(typeId: typeId, fieldId: fieldId)
                    .environmentObject(appState)
            }
        }
        .alert("Reset built-in schemas?", isPresented: $showResetConfirm) {
            Button("Reset", role: .destructive) {
                appState.schema.resetBuiltInsToDefaults()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This restores the built-in types (Planner, Notes, People, Books, etc.) to their default shape. Your records are kept — only the schema definitions change. Custom types you've created are not affected.")
        }
        .alert("Import failed", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .onAppear {
            // Schema Editor is its own window — its undo manager is
            // separate from the main window's. Wire it before any
            // type / field mutation so ⌘Z in this window restores
            // the prior schema state.
            appState.schema.undoManager = undoManager
            ObjectEngine.undoManager = undoManager
            if selectedTypeId == nil {
                selectedTypeId = appState.schema.visibleTypes.first?.id
            }
        }
    }

    // MARK: - Types rail

    private var typesRail: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Types").font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            Divider()

            List(selection: Binding(
                get: { selectedTypeId },
                set: { selectedTypeId = $0 }
            )) {
                ForEach(appState.schema.types) { type in
                    typeRailRow(type).tag(type.id)
                }
            }
            .listStyle(.sidebar)

            Divider()
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    TextField("New type name", text: $newTypeName)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") { addType() }
                        .disabled(newTypeName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Button {
                    showLibrary = true
                } label: {
                    Label("Browse library…", systemImage: "books.vertical")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.small)
                .help("Import a curated schema from the library")
            }
            .padding(12)
        }
    }

    private func typeRailRow(_ type: ObjectType) -> some View {
        HStack {
            Image(systemName: type.systemImage)
                .foregroundStyle(Color(hex: type.colorHex) ?? .accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(type.pluralName).font(.body)
                Text(type.builtIn ? "built-in" : "custom")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if type.isVault {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.tertiary)
                    .imageScale(.small)
                    .help("In the Vault — hidden from the regular sidebar")
            }
            if type.builtIn && appState.schema.hiddenBuiltInIds.contains(type.id) {
                Image(systemName: "eye.slash")
                    .foregroundStyle(.tertiary)
                    .imageScale(.small)
            }
            Text("\(type.fields.count)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .contextMenu {
            Button("Export \(type.pluralName)…") {
                exportTypes(ids: [type.id])
            }
            Divider()
            Button(type.isVault ? "Move out of Vault" : "Move to Vault") {
                appState.schema.setVault(type.id, isVault: !type.isVault)
            }
            if type.builtIn {
                Button(appState.schema.hiddenBuiltInIds.contains(type.id) ? "Show in sidebar" : "Hide from sidebar") {
                    appState.schema.setHidden(type.id, hidden: !appState.schema.hiddenBuiltInIds.contains(type.id))
                }
            } else {
                Divider()
                Button("Delete type", role: .destructive) {
                    appState.schema.deleteType(id: type.id)
                    if selectedTypeId == type.id {
                        selectedTypeId = appState.schema.visibleTypes.first?.id
                    }
                }
            }
        }
    }

    // MARK: - Field list

    @ViewBuilder
    private var fieldList: some View {
        if let typeId = selectedTypeId, let type = appState.schema.type(id: typeId) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: type.systemImage)
                        .foregroundStyle(Color(hex: type.colorHex) ?? .accentColor)
                        .imageScale(.large)
                    Text(type.name).font(.title2).bold()
                    Text("·").foregroundStyle(.tertiary)
                    Text("\(type.fields.count) field\(type.fields.count == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.vertical, 14)
                Divider()

                typeTagsRow(type: type)

                Divider()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(type.fields) { field in
                            fieldRow(field: field, on: type)
                        }
                        // Drop zone hint when the list is short — gives
                        // users an obvious target to drop a palette
                        // tile onto. Hidden once the list grows past
                        // two fields (the row chrome itself becomes the
                        // visual target).
                        if type.fields.count < 3 {
                            dropZoneHint
                        }
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .dropDestination(for: FieldKindTransfer.self) { items, _ in
                    var added = false
                    for item in items {
                        if let kind = FieldKind(rawValue: item.rawKind) {
                            addField(kind: kind)
                            added = true
                        }
                    }
                    return added
                }
            }
        } else {
            VStack {
                Spacer()
                Text("Pick a type from the left.")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func fieldRow(field: FieldDef, on type: ObjectType) -> some View {
        HStack(spacing: 10) {
            Image(systemName: field.kind.systemImage)
                .foregroundStyle(.secondary)
                .imageScale(.medium)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                if renamingFieldId == field.id {
                    TextField("Field name", text: Binding(
                        get: { field.name },
                        set: { newName in
                            var f = field
                            f.name = newName
                            appState.schema.updateField(f, onTypeId: type.id)
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { renamingFieldId = nil }
                } else {
                    Text(field.name).font(.body)
                }
                HStack(spacing: 6) {
                    Text(field.kind.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                    if field.required {
                        Text("required")
                            .font(.caption2)
                            .foregroundStyle(.red.opacity(0.85))
                    }
                    if type.primaryFieldKey == field.key {
                        Text("primary")
                            .font(.caption2)
                            .foregroundStyle(.tint)
                    }
                    if field.kind == .select || field.kind == .multiSelect {
                        Button {
                            editingOptionsForFieldId = field.id
                        } label: {
                            Text("\(field.options.count) option\(field.options.count == 1 ? "" : "s") · Edit")
                                .font(.caption2)
                                .foregroundStyle(.tint)
                        }
                        .buttonStyle(.plain)
                        .help("Add, rename, recolor, reorder, or delete the option values")
                    }
                }
            }
            Spacer()
            Menu {
                Button(renamingFieldId == field.id ? "Stop renaming" : "Rename") {
                    renamingFieldId = (renamingFieldId == field.id) ? nil : field.id
                }
                if field.kind == .select || field.kind == .multiSelect {
                    Button("Edit options…") {
                        editingOptionsForFieldId = field.id
                    }
                }
                Button(field.required ? "Make optional" : "Make required") {
                    var f = field
                    f.required = !f.required
                    appState.schema.updateField(f, onTypeId: type.id)
                }
                Divider()
                Button("Move up") {
                    appState.schema.moveField(fieldId: field.id, onTypeId: type.id, by: -1)
                }
                .disabled(type.fields.first?.id == field.id)
                Button("Move down") {
                    appState.schema.moveField(fieldId: field.id, onTypeId: type.id, by: +1)
                }
                .disabled(type.fields.last?.id == field.id)
                Divider()
                Button("Delete field", role: .destructive) {
                    appState.schema.removeField(fieldId: field.id, fromTypeId: type.id)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline).frame(height: 0.5)
        }
    }

    /// Dashed drop-target hint shown under a short field list. Once
    /// the user has three or more fields, the list itself is large
    /// enough to be an obvious drop target without the prompt.
    private var dropZoneHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.rectangle.on.rectangle")
                .foregroundStyle(.tertiary)
            Text("Drag a field type here")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Theme.cardBorder, style: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
        )
        .padding(.horizontal, 20)
        .padding(.top, 6)
    }

    // MARK: - Type-scope tags

    /// Tag chips that apply to every record of this type. Distinct from
    /// per-record tags (Detail.swift's `TagPillRow`) — these are stored
    /// on `ObjectType.tags` and resolved alongside per-record tags via
    /// `TagService.effectiveTagIds(for:in:)`.
    private func typeTagsRow(type: ObjectType) -> some View {
        let vocab = Dictionary(uniqueKeysWithValues: TagService.allTags.map { ($0.id, $0) })
        let resolved = type.tags.compactMap { vocab[$0] }
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "tag")
                    .foregroundStyle(.tertiary)
                    .imageScale(.small)
                Text("Tags")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase).tracking(0.5)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 80, alignment: .leading)
            SchemaEditorTagFlow {
                ForEach(resolved, id: \.id) { tag in
                    typeTagPill(tag: tag, type: type)
                }
                addTypeTagButton(type: type)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
    }

    private func typeTagPill(tag: TagDef, type: ObjectType) -> some View {
        let color = tag.colorHex.flatMap(Color.init(hex:)) ?? .secondary
        return HStack(spacing: 4) {
            Text(tag.name)
                .font(.caption.weight(.medium))
            Button {
                let remaining = type.tags.filter { $0 != tag.id }
                appState.schema.setTypeTags(remaining, onTypeId: type.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .imageScale(.small)
                    .foregroundStyle(color.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("Remove \(tag.name) from this type")
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(color.opacity(0.20))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }

    private func addTypeTagButton(type: ObjectType) -> some View {
        Button {
            showTypeTagPicker = true
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "plus")
                    .imageScale(.small)
                Text("Add tag")
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color.secondary.opacity(0.08))
            .foregroundStyle(.secondary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showTypeTagPicker, arrowEdge: .bottom) {
            TagChipPicker(selectedTagIds: Set(type.tags)) { picked in
                if !type.tags.contains(picked) {
                    appState.schema.setTypeTags(type.tags + [picked], onTypeId: type.id)
                }
                showTypeTagPicker = false
            }
        }
    }

    // MARK: - Field palette

    private var fieldPalette: some View {
        // Wrapping grid of field-type tiles. Previously a horizontal
        // ScrollView with `showsIndicators: false`, which made the
        // right-edge tiles silently inaccessible at any window width
        // that couldn't fit every FieldKind in one row. An adaptive
        // LazyVGrid wraps onto a second row as needed, so every type
        // is reachable without scrolling.
        VStack(alignment: .leading, spacing: 8) {
            Text("ADD A FIELD")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
                .padding(.horizontal, 20).padding(.top, 12)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 92, maximum: 110), spacing: 8, alignment: .leading)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(FieldKind.allCases, id: \.self) { kind in
                    paletteTile(kind: kind)
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 12)
        }
        .background(Theme.bg.opacity(0.6))
    }

    private func paletteTile(kind: FieldKind) -> some View {
        Button {
            addField(kind: kind)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: kind.systemImage)
                    .imageScale(.medium)
                Text(kind.displayName)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Theme.cardBorder, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(selectedTypeId == nil)
        // Drag affordance — payload is the FieldKind's raw value; the
        // field list above accepts it and calls addField. Click-to-add
        // still works for users who don't reach for drag.
        .draggable(FieldKindTransfer(rawKind: kind.rawValue)) {
            VStack(spacing: 4) {
                Image(systemName: kind.systemImage).imageScale(.medium)
                Text(kind.displayName).font(.caption)
            }
            .frame(width: 92, height: 56)
            .background(Theme.accent.opacity(0.18))
            .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Theme.accent, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Actions

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                showLibrary = true
            } label: {
                Label("Library", systemImage: "books.vertical")
            }
            .help("Browse the schema library")

            Menu {
                Button("Import from file…") {
                    importFromFile()
                }
                if let selected = selectedSelectableType {
                    Divider()
                    Button("Export \(selected.pluralName)…") {
                        exportTypes(ids: [selected.id])
                    }
                }
                Button("Export multiple…") {
                    multiExportSelection = []
                    showMultiExport = true
                }
                Button("Export all…") {
                    exportTypes(ids: appState.schema.types.map(\.id))
                }
                Divider()
                Button("Manage tags…") {
                    showManageTags = true
                }
                Divider()
                Button("Reset built-ins to defaults…", role: .destructive) {
                    showResetConfirm = true
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .help("Import, export, and reset")
        }
    }

    /// Currently selected type if it can sensibly be exported as a
    /// single item. Always non-nil when `selectedTypeId` resolves.
    private var selectedSelectableType: ObjectType? {
        guard let id = selectedTypeId else { return nil }
        return appState.schema.type(id: id)
    }

    // MARK: - Import / export actions

    private func exportTypes(ids: [String]) {
        let types = ids.compactMap { appState.schema.type(id: $0) }
        guard !types.isEmpty else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = SchemaIO.defaultFilenameForBundle(types)
        panel.directoryURL = appState.settingsStore.resolvedExportDirectory
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.json]
        panel.allowsOtherFileTypes = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try SchemaIO.write(types, to: url)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                NSLog("PurpleLife: schema export failed — \(error.localizedDescription)")
                Task { @MainActor in
                    importError = "Couldn't export schema: \(error.localizedDescription)"
                }
            }
        }
    }

    private func importFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = appState.settingsStore.resolvedExportDirectory
        panel.begin { response in
            guard response == .OK else { return }
            do {
                var imported: [ObjectType] = []
                for url in panel.urls {
                    let types = try SchemaIO.read(from: url)
                    imported.append(contentsOf: types)
                }
                Task { @MainActor in
                    let ids = appState.schema.importTypes(imported)
                    if let firstId = ids.first {
                        selectedTypeId = firstId
                    }
                }
            } catch {
                Task { @MainActor in
                    importError = "Couldn't import: \(error.localizedDescription)"
                }
            }
        }
    }

    private func addType() {
        let name = newTypeName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let id = name.replacingOccurrences(of: " ", with: "")
        let type = ObjectType(
            id: id,
            name: name,
            pluralName: name + "s",
            systemImage: "square.grid.2x2",
            colorHex: "#9D4DCC",
            fields: [
                FieldDef.make(name: "Title", kind: .text, required: true),
                FieldDef.make(name: "Notes", kind: .longText)
            ],
            builtIn: false,
            primaryFieldKey: "title",
            kanbanGroupKey: nil,
            calendarDateKey: nil,
            galleryAttachmentKey: nil
        )
        appState.schema.upsertType(type)
        newTypeName = ""
        selectedTypeId = id
    }

    private func addField(kind: FieldKind) {
        guard let typeId = selectedTypeId else { return }
        // Dedupe the default name so multiple clicks don't produce
        // colliding keys.
        let baseName = "New \(kind.displayName.lowercased())"
        var name = baseName
        var n = 1
        if let type = appState.schema.type(id: typeId) {
            while type.fields.contains(where: { $0.name == name }) {
                n += 1
                name = "\(baseName) \(n)"
            }
        }
        let field = FieldDef.make(name: name, kind: kind)
        appState.schema.addField(field, toTypeId: typeId)
        renamingFieldId = field.id
    }
}

/// Transferable payload for dragging a field-type tile from the
/// palette onto the field list. Carries just the `FieldKind.rawValue`
/// — the editor maps it back to a real `FieldKind` and calls
/// `addField(kind:)`. Codable + a single `.data` representation is
/// enough for an in-process drag; we never serialize this across
/// process boundaries.
struct FieldKindTransfer: Codable, Transferable {
    let rawKind: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}

/// Wrapping flow layout used by the Schema editor's type-tags row.
/// `TagPillRow.FlowLayout` is fileprivate; duplicating the ~30 lines
/// here keeps the two views decoupled and avoids leaking the helper
/// into a shared module before there are three callers.
struct SchemaEditorTagFlow<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        SchemaEditorFlowLayout(spacing: 6) {
            content()
        }
    }
}

struct SchemaEditorFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, maxRowWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                maxRowWidth = max(maxRowWidth, x - spacing)
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        maxRowWidth = max(maxRowWidth, x - spacing)
        return CGSize(width: maxRowWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

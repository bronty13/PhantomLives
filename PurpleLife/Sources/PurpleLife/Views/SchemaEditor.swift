import SwiftUI

/// Schema editor — the distinctive screen from the design (per
/// `Design/MANIFEST.md`). Shows the visible types in a left rail and the
/// selected type's field list on the right, with a field-type palette
/// at the bottom for adding new fields. Phase 2 starting point — the
/// drag-from-palette interaction in the prototype is approximated here
/// as click-to-add; full drag-and-drop lands once the rest of Phase 2
/// is in.
struct SchemaEditorScreen: View {
    @EnvironmentObject private var appState: AppState

    @State private var selectedTypeId: String?
    @State private var editingFieldId: String?
    @State private var renamingFieldId: String?
    @State private var newTypeName: String = ""

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
        .onAppear {
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
            HStack(spacing: 6) {
                TextField("New type name", text: $newTypeName)
                    .textFieldStyle(.roundedBorder)
                Button("Add") { addType() }
                    .disabled(newTypeName.trimmingCharacters(in: .whitespaces).isEmpty)
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
            if type.builtIn {
                Button(appState.schema.hiddenBuiltInIds.contains(type.id) ? "Show in sidebar" : "Hide from sidebar") {
                    appState.schema.setHidden(type.id, hidden: !appState.schema.hiddenBuiltInIds.contains(type.id))
                }
            } else {
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

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(type.fields) { field in
                            fieldRow(field: field, on: type)
                        }
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                }
            }
            Spacer()
            Menu {
                Button(renamingFieldId == field.id ? "Stop renaming" : "Rename") {
                    renamingFieldId = (renamingFieldId == field.id) ? nil : field.id
                }
                Button(field.required ? "Make optional" : "Make required") {
                    var f = field
                    f.required = !f.required
                    appState.schema.updateField(f, onTypeId: type.id)
                }
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

    // MARK: - Field palette

    private var fieldPalette: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ADD A FIELD")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
                .padding(.horizontal, 20).padding(.top, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FieldKind.allCases, id: \.self) { kind in
                        Button {
                            addField(kind: kind)
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: kind.systemImage)
                                    .imageScale(.medium)
                                Text(kind.displayName)
                                    .font(.caption)
                            }
                            .frame(width: 92, height: 56)
                            .background(Theme.card)
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(Theme.cardBorder, lineWidth: 0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .disabled(selectedTypeId == nil)
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 12)
            }
        }
        .background(Theme.bg.opacity(0.6))
    }

    // MARK: - Actions

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

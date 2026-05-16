import SwiftUI
import AppKit

/// Modal editor for the option list of a `.select` or `.multiSelect`
/// field. Add / rename / recolor / reorder / delete options here; the
/// existing alternative was to hand-edit `schema.json`. All mutations
/// fan through `SchemaRegistry.updateField` so undo + CloudKit
/// schema-sync stay consistent — same envelope every other schema
/// edit uses.
///
/// Renaming an option does NOT rewrite the records that referenced
/// the old name. That's intentional for now: option storage on a
/// record is the option's *name* (string), not its id, so a rename
/// would orphan existing values. The editor surfaces this as a
/// caption under the rename field so the user isn't surprised.
struct SelectOptionsEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    let typeId: String
    let fieldId: String

    @State private var draft: [FieldOption] = []
    @State private var newOptionName: String = ""
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if draft.isEmpty {
                emptyState
            } else {
                optionsList
            }
            Divider()
            footer
        }
        .frame(minWidth: 460, minHeight: 360)
        .onAppear(perform: load)
    }

    // MARK: - Header / footer / empty

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Edit options").font(.title2).bold()
                if let field = currentField {
                    Text("\(field.name) · \(field.kind.displayName)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Done") { commitAndDismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("Add an option…", text: $newOptionName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addNewOption)
                Button("Add", action: addNewOption)
                    .disabled(newOptionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("Renaming an option won't update records already carrying the old value — the option name is the stored value.")
                .font(.caption2).foregroundStyle(.tertiary)
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(12)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 32)).foregroundStyle(.tertiary)
            Text("No options yet.")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("Add an option below to start populating the picker.")
                .font(.caption).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var optionsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(draft) { opt in
                    row(for: opt)
                    Divider()
                }
            }
        }
    }

    // MARK: - Row

    private func row(for opt: FieldOption) -> some View {
        let idx = draft.firstIndex(of: opt)
        return HStack(spacing: 10) {
            ColorPicker("", selection: colorBinding(for: opt))
                .labelsHidden()
                .frame(width: 28)
                .help("Tap to change this option's color")

            TextField(opt.name, text: nameBinding(for: opt))
                .textFieldStyle(.roundedBorder)

            Spacer()

            Button {
                guard let i = idx, i > 0 else { return }
                draft.swapAt(i, i - 1)
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(idx == 0)
            .help("Move up")

            Button {
                guard let i = idx, i < draft.count - 1 else { return }
                draft.swapAt(i, i + 1)
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(idx == draft.count - 1)
            .help("Move down")

            Button(role: .destructive) {
                draft.removeAll { $0.id == opt.id }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete this option")
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
    }

    // MARK: - Bindings

    private func nameBinding(for opt: FieldOption) -> Binding<String> {
        Binding(
            get: { opt.name },
            set: { newName in
                guard let idx = draft.firstIndex(where: { $0.id == opt.id }) else { return }
                draft[idx].name = newName
            }
        )
    }

    private func colorBinding(for opt: FieldOption) -> Binding<Color> {
        Binding(
            get: { opt.colorHex.flatMap(Color.init(hex:)) ?? .gray },
            set: { color in
                guard let idx = draft.firstIndex(where: { $0.id == opt.id }) else { return }
                draft[idx].colorHex = Self.hexRGB(of: color)
            }
        )
    }

    // MARK: - Actions

    private func load() {
        guard let field = currentField else { return }
        draft = field.options
    }

    private func addNewOption() {
        let trimmed = newOptionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if draft.contains(where: { $0.name.lowercased() == trimmed.lowercased() }) {
            error = "An option named \u{201C}\(trimmed)\u{201D} already exists."
            return
        }
        draft.append(FieldOption.make(trimmed))
        newOptionName = ""
        error = nil
    }

    private func commitAndDismiss() {
        guard var field = currentField else { dismiss(); return }
        // Drop empty / duplicate names before persisting — the user
        // may have left a blank textfield or typed a duplicate while
        // editing inline.
        var seen: Set<String> = []
        let cleaned = draft.compactMap { opt -> FieldOption? in
            let trimmed = opt.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { return nil }
            var fresh = opt
            fresh.name = trimmed
            return fresh
        }
        field.options = cleaned
        appState.schema.updateField(field, onTypeId: typeId)
        dismiss()
    }

    // MARK: - Lookup

    private var currentField: FieldDef? {
        appState.schema.type(id: typeId)?.field(forKey: fieldKey) ?? appState.schema.type(id: typeId)?.fields.first(where: { $0.id == fieldId })
    }

    private var fieldKey: String {
        appState.schema.type(id: typeId)?.fields.first(where: { $0.id == fieldId })?.key ?? ""
    }

    /// `#RRGGBB` — mirrors `TagManagementSheet.hexRGB(of:)`. Kept
    /// local so the sheets stay independent until a third caller
    /// needs the same helper.
    private static func hexRGB(of color: Color) -> String {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.black
        let r = Int(round(ns.redComponent * 255))
        let g = Int(round(ns.greenComponent * 255))
        let b = Int(round(ns.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

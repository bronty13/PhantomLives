import SwiftUI

/// "Manage Filename Presets" dialog (Kyno-parity, Image #90).
/// Two-pane layout: list of presets on the left, action buttons on
/// the right, template editor + Add Variable along the bottom.
/// System presets are locked (🔒) — non-editable, non-deletable, but
/// the user can Duplicate one to start a custom from a known shape.
struct ManageFilenamePresetsSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var presets: [FilenameRenamePreset]
    @State private var selectedID: String?

    init() {
        // Snapshot the combined catalog into local state so edits
        // commit on OK rather than mutating UserDefaults live (lets
        // Cancel discard cleanly).
        _presets = State(initialValue: BatchRenamePresets.combined())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                presetList
                Divider()
                actionPane
            }
            Divider()
            templateEditor
            Divider()
            footer
        }
        .frame(width: 760, height: 540)
    }

    private var header: some View {
        HStack {
            Text("Manage Filename Presets").font(.headline)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    // MARK: - Preset list

    private var presetList: some View {
        List(selection: $selectedID) {
            ForEach($presets) { $preset in
                HStack(spacing: 8) {
                    Image(systemName: preset.isSystem ? "lock.fill" : "lock.open")
                        .foregroundStyle(preset.isSystem
                                          ? AnyShapeStyle(HierarchicalShapeStyle.secondary)
                                          : AnyShapeStyle(TintShapeStyle.tint))
                        .font(.caption)
                    if preset.isSystem {
                        Text(preset.name)
                    } else {
                        TextField("", text: $preset.name)
                            .textFieldStyle(.plain)
                    }
                }
                .tag(preset.id)
            }
            // Footer hint when a system preset is selected — Kyno's
            // italic guidance from Image #90.
            HStack {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption2)
                Text("Duplicate system presets to modify them")
                    .font(.caption.italic())
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 6)
        }
        .frame(width: 520)
    }

    // MARK: - Right-side actions

    private var actionPane: some View {
        VStack(spacing: 10) {
            Button("Delete") {
                guard let id = selectedID,
                      let idx = presets.firstIndex(where: { $0.id == id }),
                      !presets[idx].isSystem
                else { return }
                presets.remove(at: idx)
                selectedID = nil
            }
            .disabled(!canDeleteSelected)
            Button("Duplicate") {
                duplicateSelected()
            }
            .disabled(selectedID == nil)
            Spacer()
        }
        .padding(12)
        .frame(width: 200, alignment: .top)
    }

    private var canDeleteSelected: Bool {
        guard let id = selectedID,
              let p = presets.first(where: { $0.id == id })
        else { return false }
        return !p.isSystem
    }

    private func duplicateSelected() {
        guard let id = selectedID,
              let src = presets.first(where: { $0.id == id }) else { return }
        let copy = FilenameRenamePreset(
            id: "user-\(UUID().uuidString)",
            name: "\(src.name) Copy",
            template: src.template,
            isSystem: false
        )
        presets.append(copy)
        selectedID = copy.id
    }

    // MARK: - Template editor

    private var templateEditor: some View {
        HStack(spacing: 8) {
            TextField("Template",
                        text: Binding<String>(
                            get: { selectedPreset?.template ?? "" },
                            set: { newTemplate in
                                guard let id = selectedID,
                                      let idx = presets.firstIndex(where: {
                                          $0.id == id
                                      }),
                                      !presets[idx].isSystem
                                else { return }
                                presets[idx].template = newTemplate
                            }
                        ))
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .disabled(selectedPreset?.isSystem ?? true)
            Menu("Add Variable") {
                ForEach(BatchRenamePresets.variables, id: \.key) { v in
                    Button(v.label) {
                        appendVariable("${\(v.key)}")
                    }
                }
            }
            .disabled(selectedPreset?.isSystem ?? true)
            .frame(width: 140)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var selectedPreset: FilenameRenamePreset? {
        guard let id = selectedID else { return nil }
        return presets.first { $0.id == id }
    }

    private func appendVariable(_ token: String) {
        guard let id = selectedID,
              let idx = presets.firstIndex(where: { $0.id == id }),
              !presets[idx].isSystem
        else { return }
        presets[idx].template += token
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("OK") { save() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func save() {
        // Only user-presets ride to UserDefaults; system presets are
        // hard-coded in the catalog and can't drift.
        let userOnly = presets.filter { !$0.isSystem }
        BatchRenamePresets.saveUser(userOnly)
        dismiss()
    }
}

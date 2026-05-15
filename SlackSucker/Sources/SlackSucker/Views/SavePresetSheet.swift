import SwiftUI

/// Modal for naming a preset before saving. The closure produces the
/// request snapshot the form is currently composing so the save can be
/// atomic — the user can't have a form state that the preset disagrees
/// with at the moment of save.
struct SavePresetSheet: View {
    @EnvironmentObject var presets: PresetStore
    @Environment(\.dismiss) private var dismiss

    var buildRequest: () -> ArchiveRequest
    @State private var name: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Save preset")
                .font(AppFont.display(16, weight: .semibold))
            TextField("Preset name", text: $name)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    presets.upsert(ArchivePreset(name: name.isEmpty ? "Untitled" : name,
                                                 request: buildRequest()))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
    }
}

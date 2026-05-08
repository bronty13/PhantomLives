import SwiftUI

/// Modal sheet shown when the user clicks the ☆ Save preset chip in the
/// header. Captures the current form values and persists them under a
/// user-chosen name. Empty / whitespace-only names are rejected.
struct SavePresetSheet: View {
    @EnvironmentObject private var presets: PresetStore
    @Binding var isPresented: Bool

    /// Snapshot of form values at the moment the sheet was opened.
    let contact: String
    let start: Date?
    let end: Date?
    let mode: ExportMode
    let transcribe: Bool
    let transcribeModel: WhisperModel
    let emoji: EmojiMode

    @State private var name: String = ""

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var canSave: Bool {
        !trimmedName.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "star.fill")
                    .font(.title2)
                    .foregroundStyle(.yellow)
                Text("Save preset")
                    .font(.title3).bold()
            }
            Text("Captures the current Contact, date range, Mode, Transcribe toggle/model, and Emoji handling. Saved presets appear in the sidebar; click one to apply it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Name").font(.callout).bold()
                TextField("e.g. Sallie · last 7 days", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { if canSave { save() } }
            }

            VStack(alignment: .leading, spacing: 4) {
                summaryRow("Contact",     value: contact.isEmpty ? "—" : contact)
                summaryRow("Range",       value: rangeText)
                summaryRow("Mode",        value: mode.label)
                summaryRow("Transcribe",  value: transcribe ? "on (\(transcribeModel.shortLabel))" : "off")
                summaryRow("Emoji",       value: emoji.label)
            }
            .padding(10)
            .background(Color.primary.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 6))

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Save preset") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private var rangeText: String {
        guard let s = start, let e = end else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy · HH:mm"
        return "\(f.string(from: s)) → \(f.string(from: e))"
    }

    private func summaryRow(_ key: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer()
        }
    }

    private func save() {
        guard canSave else { return }
        let preset = ExportPreset(
            name: trimmedName,
            contact: contact,
            start: start,
            end: end,
            mode: mode,
            transcribe: transcribe,
            transcribeModel: transcribeModel,
            emoji: emoji
        )
        presets.upsert(preset)
        isPresented = false
    }
}

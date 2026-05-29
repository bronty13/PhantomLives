import SwiftUI

/// Create / duplicate / rename / delete presets. Presented as a sheet
/// from the console's `⋯` menu and also embedded as the Settings
/// "Presets" tab (`embedded: true` drops the sheet chrome).
struct ManagePresetsView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var presetStore: PresetStore
    @Environment(\.dismiss) private var dismiss

    var embedded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !embedded {
                HStack {
                    Text("Manage Presets").font(.headline)
                    Spacer()
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(20)
                Divider()
            }

            List {
                Section("Built-in") {
                    ForEach(Preset.builtIns) { preset in
                        row(preset, deletable: false)
                    }
                }
                Section("My Presets") {
                    if presetStore.userPresets.isEmpty {
                        Text("No saved presets yet. Save the current settings from the console, or duplicate a built-in below.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(presetStore.userPresets) { preset in
                        row(preset, deletable: true)
                    }
                }
            }

            Divider()
            HStack {
                Button {
                    var snap = settings.liveSnapshot
                    snap.name = "New Preset"
                    let stored = presetStore.add(snap)
                    settings.activePresetIDRaw = stored.id.uuidString
                } label: {
                    Label("New from current settings", systemImage: "plus")
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: embedded ? nil : 480,
               height: embedded ? nil : 460)
    }

    @ViewBuilder
    private func row(_ preset: Preset, deletable: Bool) -> some View {
        HStack(spacing: 8) {
            if deletable {
                TextField("Name", text: nameBinding(preset))
                    .textFieldStyle(.plain)
            } else {
                Text(preset.name)
            }
            if isActive(preset) {
                Text("active")
                    .font(.caption2)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                    .foregroundStyle(Color.accentColor)
            }
            Spacer()
            summary(preset)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Button("Apply") { settings.apply(preset) }
                .buttonStyle(.borderless)
            Button {
                presetStore.duplicate(preset)
            } label: { Image(systemName: "plus.square.on.square") }
                .buttonStyle(.borderless)
                .help("Duplicate")
            if deletable {
                Button(role: .destructive) {
                    presetStore.delete(id: preset.id)
                    if settings.activePresetIDRaw == preset.id.uuidString {
                        settings.activePresetIDRaw = ""
                    }
                } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .help("Delete")
            }
        }
    }

    /// One-line description of a preset's character.
    private func summary(_ p: Preset) -> Text {
        var parts: [String] = [p.profile.displayName]
        if p.engine == .deepFilterNet { parts.append("Neural") }
        if p.loudnessTarget != .none { parts.append(p.loudnessTarget.displayName) }
        if p.deEsserEnabled { parts.append("de-ess") }
        if p.deClickerEnabled { parts.append("de-click") }
        if p.preserveStereo { parts.append("stereo") }
        if p.tuning.hasAnyOverride { parts.append("tuned") }
        return Text(parts.joined(separator: " · "))
    }

    private func isActive(_ preset: Preset) -> Bool {
        settings.activePresetIDRaw == preset.id.uuidString
    }

    private func nameBinding(_ preset: Preset) -> Binding<String> {
        Binding(
            get: { preset.name },
            set: { presetStore.rename(id: preset.id, to: $0) }
        )
    }
}

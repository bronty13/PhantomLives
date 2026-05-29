import SwiftUI

/// The shared processing console — the always-visible control surface
/// for a run. Lives in one place and is rendered by both `DropZoneView`
/// (empty state) and `ClipDetailView` (a clip is selected).
///
/// Layout, top to bottom:
///   1. Preset bar — apply / save / manage presets.
///   2. Profile strength + blurb.
///   3. A row of rotary `Knob`s for the per-filter parameters.
///   4. A row of toggle switches (enhancement, de-esser, …).
///   5. Compact engine / loudness / format pickers.
///
/// The knobs bind straight into `settings.filterTuning` (nil field =
/// inherit the profile default), so turning one immediately puts the
/// preset into the "(Modified)" state.
struct ProcessingPanel: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var presetStore: PresetStore

    @State private var showSaveSheet = false
    @State private var showManageSheet = false
    @State private var newPresetName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            presetBar
            Divider()
            profileRow
            knobRow
            Divider()
            toggleRow
            pickerRow
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        )
        .sheet(isPresented: $showSaveSheet) { saveSheet }
        .sheet(isPresented: $showManageSheet) {
            ManagePresetsView()
                .environmentObject(settings)
                .environmentObject(presetStore)
        }
    }

    // MARK: - Preset bar

    private var presetBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "slider.horizontal.below.square.filled.and.square")
                .foregroundStyle(.secondary)

            Menu {
                Section("Built-in") {
                    ForEach(Preset.builtIns) { preset in
                        Button(preset.name) { settings.apply(preset) }
                    }
                }
                if !presetStore.userPresets.isEmpty {
                    Section("My Presets") {
                        ForEach(presetStore.userPresets) { preset in
                            Button(preset.name) { settings.apply(preset) }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(presetTitle).fontWeight(.medium)
                    if isModified {
                        Text("Modified")
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.orange.opacity(0.2)))
                            .foregroundStyle(.orange)
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()

            Menu {
                Button("Save as New Preset…") {
                    newPresetName = ""
                    showSaveSheet = true
                }
                if let active = activePreset, !active.builtIn, isModified {
                    Button("Update “\(active.name)”") {
                        var updated = active
                        let snap = settings.liveSnapshot
                        updated.profile = snap.profile
                        updated.enhancementEnabled = snap.enhancementEnabled
                        updated.engine = snap.engine
                        updated.loudnessTarget = snap.loudnessTarget
                        updated.deEsserEnabled = snap.deEsserEnabled
                        updated.deClickerEnabled = snap.deClickerEnabled
                        updated.preserveStereo = snap.preserveStereo
                        updated.dereverbEnabled = snap.dereverbEnabled
                        updated.tuning = snap.tuning
                        presetStore.update(updated)
                    }
                }
                if let active = activePreset, isModified {
                    Button("Revert to “\(active.name)”") { settings.apply(active) }
                }
                Divider()
                Button("Manage Presets…") { showManageSheet = true }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Save, update, or manage presets")
        }
    }

    // MARK: - Profile

    private var profileRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("", selection: Binding(
                get: { settings.profile },
                set: { settings.profile = $0 }
            )) {
                ForEach(ProcessingProfile.allCases) { p in
                    Text(p.displayName).tag(p)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(settings.profile.blurb)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Knobs

    private var knobRow: some View {
        HStack(alignment: .top, spacing: 10) {
            Knob(label: "High-pass",
                 value: tuningBinding(\.highpassHz),
                 defaultValue: 80,
                 range: FilterTuning.Bounds.highpassHz,
                 step: 1, unit: "Hz")

            Knob(label: "Denoise",
                 value: tuningBinding(\.afftdnNR),
                 defaultValue: defaultAfftdnNR,
                 range: FilterTuning.Bounds.afftdnNR,
                 step: 0.5, unit: "dB",
                 enabled: settings.processingEngine == .ffmpegOnly)

            Knob(label: "De-ess",
                 value: tuningBinding(\.deEsserIntensity),
                 defaultValue: 0.4,
                 range: FilterTuning.Bounds.deEsserIntensity,
                 step: 0.05, unit: "",
                 enabled: settings.deEsserEnabled)

            Knob(label: "Comp thr",
                 value: tuningBinding(\.compressorThresholdDB),
                 defaultValue: -22,
                 range: FilterTuning.Bounds.compressorThresholdDB,
                 step: 0.5, unit: "dB",
                 enabled: compressorEnabled)

            Knob(label: "Comp rat",
                 value: tuningBinding(\.compressorRatio),
                 defaultValue: 3,
                 range: FilterTuning.Bounds.compressorRatio,
                 step: 0.5, unit: ":1",
                 enabled: compressorEnabled)

            Knob(label: "Limiter",
                 value: tuningBinding(\.limiterCeiling),
                 defaultValue: 0.97,
                 range: FilterTuning.Bounds.limiterCeiling,
                 step: 0.01, unit: "",
                 enabled: settings.enhancementEnabled)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Toggles

    private var toggleRow: some View {
        HStack(spacing: 16) {
            toggle("Enhance", $settings.enhancementEnabled,
                   help: "Compression + limiting + normalization (podcast-style).")
            toggle("De-esser", $settings.deEsserEnabled,
                   help: "Sibilance reduction.")
            toggle("De-clicker", $settings.deClickerEnabled,
                   help: "Click / pop removal.")
            toggle("Stereo", $settings.preserveStereo,
                   help: "Skip the mono downmix.")
            toggle("Dereverb", $settings.dereverbEnabled,
                   help: "Reduce reverb (DeepFilterNet engine only).",
                   enabled: settings.processingEngine == .deepFilterNet)
            Spacer()
        }
    }

    private func toggle(_ label: String,
                        _ binding: Binding<Bool>,
                        help: String,
                        enabled: Bool = true) -> some View {
        Toggle(label, isOn: binding)
            .toggleStyle(.checkbox)
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.45)
            .help(help)
    }

    // MARK: - Pickers

    private var pickerRow: some View {
        HStack(spacing: 14) {
            labeledPicker("Engine", width: 150) {
                Picker("", selection: Binding(
                    get: { settings.processingEngine },
                    set: { settings.processingEngine = $0 }
                )) {
                    Text("ffmpeg").tag(ProcessingEngine.ffmpegOnly)
                    Text("DeepFilterNet").tag(ProcessingEngine.deepFilterNet)
                }
                .labelsHidden()
            }
            labeledPicker("Loudness", width: 170) {
                Picker("", selection: Binding(
                    get: { settings.loudnessTarget },
                    set: { settings.loudnessTarget = $0 }
                )) {
                    ForEach(LoudnessTarget.allCases) { t in
                        Text(t.displayName).tag(t)
                    }
                }
                .labelsHidden()
            }
            labeledPicker("Output", width: 150) {
                Picker("", selection: Binding(
                    get: { settings.outputFormat },
                    set: { settings.outputFormat = $0 }
                )) {
                    ForEach(OutputFormat.allCases) { f in
                        Text(f.displayName).tag(f)
                    }
                }
                .labelsHidden()
            }
            Spacer()
        }
    }

    private func labeledPicker<Content: View>(_ label: String,
                                              width: CGFloat,
                                              @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            content().frame(width: width)
        }
    }

    // MARK: - Save sheet

    private var saveSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Save preset").font(.headline)
            Text("Saves the current profile, engine, toggles, and all knob values as a reusable preset.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Preset name", text: $newPresetName)
                .textFieldStyle(.roundedBorder)
                .onSubmit(commitSave)
            HStack {
                Spacer()
                Button("Cancel") { showSaveSheet = false }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { commitSave() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(newPresetName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func commitSave() {
        let name = newPresetName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        var snap = settings.liveSnapshot
        snap.name = name
        let stored = presetStore.add(snap)
        settings.activePresetIDRaw = stored.id.uuidString
        showSaveSheet = false
    }

    // MARK: - Derived state

    private var activePreset: Preset? {
        guard let id = UUID(uuidString: settings.activePresetIDRaw) else { return nil }
        return presetStore.preset(id: id)
    }

    private var isModified: Bool {
        guard let active = activePreset else { return false }
        return !settings.matchesLive(active)
    }

    private var presetTitle: String {
        if let active = activePreset { return active.name }
        // No explicit selection — surface a built-in if the live
        // settings happen to equal one, otherwise call it custom.
        if let match = presetStore.all.first(where: { settings.matchesLive($0) }) {
            return match.name
        }
        return "Custom"
    }

    private var compressorEnabled: Bool {
        settings.enhancementEnabled && settings.profile != .light
    }

    private var defaultAfftdnNR: Double {
        switch settings.profile {
        case .light:      return 8
        case .medium:     return 12
        case .aggressive: return 20
        }
    }

    private func tuningBinding(_ keyPath: WritableKeyPath<FilterTuning, Double?>) -> Binding<Double?> {
        Binding(
            get: { settings.filterTuning[keyPath: keyPath] },
            set: {
                var t = settings.filterTuning
                t[keyPath: keyPath] = $0
                settings.filterTuning = t
            }
        )
    }
}

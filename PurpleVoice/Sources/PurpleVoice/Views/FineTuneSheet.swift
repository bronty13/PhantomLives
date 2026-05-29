import SwiftUI

/// Sheet that exposes the per-filter knobs of `FilterTuning`. Pulls
/// defaults from the active profile so each slider's "Use profile
/// default" button restores a meaningful value.
///
/// UX choices:
/// - One master toggle ("Apply custom tuning") gates whether any
///   overrides are used at all. Off means every value falls back to
///   the profile default, even if the sliders show overridden values.
/// - Each slider has an explicit "reset to default" button that
///   clears the override (`nil` on the FilterTuning field). The
///   slider then snaps back to the profile-default value.
/// - Numeric values display in monospaced digits alongside each
///   slider so the user can see the exact filter parameter.
struct FineTuneSheet: View {
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    /// Live working copy. Committed to `settings.filterTuning` on
    /// "Save"; abandoned on "Cancel". A working copy is needed
    /// because each slider edits a different optional field.
    @State private var tuning: FilterTuning = .inherited
    @State private var customEnabled: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    masterToggle
                    Divider()
                    section(title: "Pre-processing") {
                        slider(
                            label: "High-pass cutoff",
                            unit: "Hz",
                            value: $tuning.highpassHz,
                            defaultValue: 80,
                            range: FilterTuning.Bounds.highpassHz,
                            step: 1,
                            help: "Frequency below which low rumble is removed. Defaults to 80 Hz."
                        )
                    }
                    section(title: "Denoise (ffmpeg engine)") {
                        slider(
                            label: "Noise reduction",
                            unit: "dB",
                            value: $tuning.afftdnNR,
                            defaultValue: defaultAfftdnNR,
                            range: FilterTuning.Bounds.afftdnNR,
                            step: 0.5,
                            help: "How hard `afftdn` attenuates stationary noise. Higher = more cleanup, more artifacts."
                        )
                    }
                    section(title: "De-esser") {
                        slider(
                            label: "Intensity",
                            unit: "",
                            value: $tuning.deEsserIntensity,
                            defaultValue: 0.4,
                            range: FilterTuning.Bounds.deEsserIntensity,
                            step: 0.05,
                            help: "Sibilance reduction strength. Only applied when the de-esser is enabled."
                        )
                    }
                    section(title: "Compressor") {
                        slider(
                            label: "Threshold",
                            unit: "dB",
                            value: $tuning.compressorThresholdDB,
                            defaultValue: -22,
                            range: FilterTuning.Bounds.compressorThresholdDB,
                            step: 0.5,
                            help: "Level above which compression begins. More negative = more compression on quiet content."
                        )
                        slider(
                            label: "Ratio",
                            unit: ":1",
                            value: $tuning.compressorRatio,
                            defaultValue: 3,
                            range: FilterTuning.Bounds.compressorRatio,
                            step: 0.5,
                            help: "How much the signal above threshold is squashed. 1:1 = off; 3:1 is gentle; 10:1 is heavy."
                        )
                    }
                    section(title: "Limiter") {
                        slider(
                            label: "Ceiling",
                            unit: "",
                            value: $tuning.limiterCeiling,
                            defaultValue: 0.97,
                            range: FilterTuning.Bounds.limiterCeiling,
                            step: 0.01,
                            help: "Brick-wall peak ceiling, 0–1 linear. 0.97 ≈ -0.26 dBFS; lower values leave more headroom."
                        )
                    }
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(width: 560, height: 540)
        .onAppear {
            tuning = settings.filterTuning
            customEnabled = settings.customTuningEnabled
        }
    }

    // MARK: - Top / bottom chrome

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Fine-tune filter parameters")
                    .font(.headline)
                Text("Overrides apply on top of your profile (\(settings.profile.displayName)).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }

    private var footer: some View {
        HStack {
            Button("Reset all to profile") {
                tuning = .inherited
            }
            .help("Clear every override; everything inherits from the active profile.")
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Save") {
                settings.customTuningEnabled = customEnabled
                settings.filterTuning = tuning
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var masterToggle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $customEnabled) {
                Text("Apply custom tuning")
                    .font(.subheadline.weight(.semibold))
            }
            Text(customEnabled
                 ? "Sliders below override the profile defaults. Disable to fall back to the profile without losing your slider values."
                 : "Sliders are remembered but inactive. Turn this on to apply them.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Building blocks

    @ViewBuilder
    private func section<Content: View>(title: String,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 14) { content() }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.secondary.opacity(0.06))
                )
        }
    }

    /// Single labelled slider with current-value readout and a
    /// "reset to default" pill. Binds against an `Optional<Double>`
    /// where `nil` means "use the profile default" — the slider
    /// itself always shows a number (the default when nil) so the
    /// user doesn't see "no value."
    private func slider(label: String,
                        unit: String,
                        value: Binding<Double?>,
                        defaultValue: Double,
                        range: ClosedRange<Double>,
                        step: Double,
                        help: String) -> some View {
        let effective = value.wrappedValue ?? defaultValue
        let isOverride = value.wrappedValue != nil
        let displayValue = String(format: stepFormat(step), effective)

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.callout)
                Spacer()
                Text("\(displayValue)\(unit.isEmpty ? "" : " \(unit)")")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(isOverride ? .primary : .secondary)
                if isOverride {
                    Button {
                        value.wrappedValue = nil
                    } label: {
                        Image(systemName: "arrow.uturn.backward.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Reset to profile default (\(String(format: stepFormat(step), defaultValue))\(unit.isEmpty ? "" : " \(unit)"))")
                }
            }
            Slider(
                value: Binding(
                    get: { effective },
                    set: { value.wrappedValue = $0 }
                ),
                in: range,
                step: step
            )
            Text(help)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .opacity(customEnabled ? 1 : 0.55)
    }

    // MARK: - Helpers

    /// Format string for the step granularity. 0.05 step → 2 dp;
    /// 0.5 step → 1 dp; 1.0+ → 0 dp.
    private func stepFormat(_ step: Double) -> String {
        if step >= 1 { return "%.0f" }
        if step >= 0.1 { return "%.1f" }
        return "%.2f"
    }

    /// The afftdn `nr` default depends on the active profile — light
    /// 8 dB, medium 12 dB, aggressive 20 dB. Mirrors the constants in
    /// `FilterChainBuilder`.
    private var defaultAfftdnNR: Double {
        switch settings.profile {
        case .light:      return 8
        case .medium:     return 12
        case .aggressive: return 20
        }
    }
}

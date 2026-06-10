import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Highlights

struct HighlightsSetup: View {
    @ObservedObject var settings: SettingsStore
    @State private var selection: UUID?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(settings.settings.highlightRules) { rule in
                        HStack {
                            Image(systemName: rule.enabled ? "sparkles" : "sparkle")
                                .foregroundStyle(rule.enabled
                                                 ? (rule.colorHex.flatMap { Color(hex: $0) } ?? .orange)
                                                 : .secondary)
                            VStack(alignment: .leading) {
                                Text(rule.name.isEmpty ? "(unnamed rule)" : rule.name)
                                Text(rule.pattern.isEmpty ? "(no pattern)" : rule.pattern)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .tag(rule.id)
                    }
                }
                Divider()
                HStack {
                    Button {
                        var rule = HighlightRule()
                        rule.name = "New highlight"
                        settings.upsertHighlight(rule)
                        selection = rule.id
                    } label: { Image(systemName: "plus") }
                    Button {
                        if let id = selection {
                            settings.removeHighlight(id: id)
                            selection = settings.settings.highlightRules.first?.id
                        }
                    } label: { Image(systemName: "minus") }
                        .disabled(selection == nil)
                    Spacer()
                }
                .padding(6)
            }
            .frame(width: 240)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if let id = selection,
               let i = settings.settings.highlightRules.firstIndex(where: { $0.id == id }) {
                HighlightRuleEditor(rule: Binding(
                    get: { settings.settings.highlightRules[i] },
                    set: { settings.settings.highlightRules[i] = $0 }
                ), settings: settings)
            } else {
                VStack {
                    Spacer()
                    Text("Select a highlight rule").foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .onAppear {
            if selection == nil { selection = settings.settings.highlightRules.first?.id }
        }
    }
}

struct HighlightRuleEditor: View {
    @Binding var rule: HighlightRule
    @ObservedObject var settings: SettingsStore
    /// Live colour for the ColorPicker — kept separate from `rule.colorHex`
    /// because a Binding(get:set:) wrapped around the hex string round-trip
    /// chokes on Color/hex conversion drift, and the user's selection
    /// silently doesn't stick. Sync explicitly via .onChange.
    @State private var pickerColor: Color = .orange
    /// Validation result for the pattern field. Cached in @State because a
    /// computed property re-compiled the NSRegularExpression on every
    /// re-render of the Form — which, with the whole-store objectWillChange
    /// fanout, meant every keystroke anywhere in Setup. Recomputed only
    /// when the pattern / regex toggle actually change.
    @State private var regexError: String? = nil

    private func validatePattern() {
        guard rule.isRegex, !rule.pattern.isEmpty else {
            regexError = nil
            return
        }
        do {
            _ = try NSRegularExpression(pattern: rule.pattern, options: [])
            regexError = nil
        } catch {
            regexError = "Invalid regex: \(error.localizedDescription)"
        }
    }

    var body: some View {
        Form {
            Section("Rule") {
                TextField("Name", text: $rule.name)
                Toggle("Enabled", isOn: $rule.enabled)
            }
            Section("Match") {
                TextField("Pattern", text: $rule.pattern)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                Toggle("Regular expression", isOn: $rule.isRegex)
                Toggle("Case sensitive", isOn: $rule.caseSensitive)
                if let err = regexError {
                    Text(err).font(.caption).foregroundStyle(.orange)
                }
            }
            Section("Appearance") {
                Toggle("Custom color", isOn: Binding(
                    get: { rule.colorHex != nil },
                    set: { enabled in
                        if enabled {
                            let hex = rule.colorHex ?? "#FFA500"
                            rule.colorHex = hex
                            pickerColor = Color(hex: hex) ?? .orange
                        } else {
                            rule.colorHex = nil
                        }
                    }
                ))
                if rule.colorHex != nil {
                    // ColorPicker bound to a real @State — much more
                    // reliable than a Binding(get:set:) over the hex string.
                    // Live changes propagate to rule.colorHex via onChange.
                    ColorPicker("Color", selection: $pickerColor, supportsOpacity: false)
                        .onChange(of: pickerColor) { _, new in
                            // Only commit while custom mode is on, so
                            // toggling off-then-on doesn't accidentally
                            // overwrite the saved colour with the picker
                            // default.
                            if rule.colorHex != nil {
                                rule.colorHex = new.hexRGB
                            }
                        }
                }
            }
            // Keep pickerColor in sync when the user switches between rules
            // or when colorHex is mutated from elsewhere (e.g. settings reload).
            .onAppear { syncPickerColor(); validatePattern() }
            .onChange(of: rule.id) { _, _ in syncPickerColor(); validatePattern() }
            .onChange(of: rule.pattern) { _, _ in validatePattern() }
            .onChange(of: rule.isRegex) { _, _ in validatePattern() }
            Section("Actions on match") {
                Toggle("Play highlight sound", isOn: $rule.playSound)
                Toggle("Bounce Dock icon", isOn: $rule.bounceDock)
                Toggle("System notification", isOn: $rule.systemNotify)
            }
            Section("Networks") {
                NetworkMultiPicker(settings: settings, selected: $rule.networks)
            }
        }
        .formStyle(.grouped)
    }

    /// Pull the current rule's hex into the live ColorPicker state.
    /// Called on appear and on rule.id change so swapping between rules in
    /// the master list resets the picker to the right colour.
    private func syncPickerColor() {
        pickerColor = (rule.colorHex.flatMap { Color(hex: $0) }) ?? .orange
    }
}


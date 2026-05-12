import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Bot (native triggers + seen)

struct BotSetup: View {
    @ObservedObject var settings: SettingsStore
    let engine: BotEngine
    @EnvironmentObject var model: ChatModel
    @State private var selection: UUID?

    var body: some View {
        // Wrap in ScrollView — the assistant section + seen + triggers
        // together blow past the sheet's minHeight on smaller screens,
        // and without scrolling the header (which contains the Done
        // button) gets pushed off the top edge of the dialog.
        ScrollView {
            VStack(spacing: 16) {
                assistantSection
                Divider()
                seenSection
                Divider()
                triggersSection
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var assistantSection: some View {
        AssistantSetupSection(settings: settings)
    }

    private var seenSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Track joins, parts, quits, and messages for /seen",
                       isOn: $settings.settings.seenTrackingEnabled)
                Text("When enabled, PurpleIRC keeps a last-seen record per network at \(settings.supportDirectoryURL.appendingPathComponent("seen").path). Use /seen <nick> in any buffer to look up a record.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let conn = model.activeConnection {
                    HStack {
                        Text("Active network: \(conn.displayName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("View seen log…") {
                            model.showSetup = false
                            model.showSeenList = true
                        }
                        Button("Clear seen data for this network", role: .destructive) {
                            engine.seenStore.clear(
                                networkID: conn.id,
                                networkSlug: SeenStore.slug(for: conn.displayName)
                            )
                        }
                        .disabled(!settings.settings.seenTrackingEnabled)
                    }
                }
            }
            .padding(6)
        } label: {
            Label("Seen tracker", systemImage: "eye")
        }
    }

    private var triggersSection: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(settings.settings.triggerRules) { rule in
                        HStack {
                            Image(systemName: rule.enabled ? "bolt.fill" : "bolt.slash")
                                .foregroundStyle(rule.enabled ? Color.accentColor : Color.secondary)
                            VStack(alignment: .leading) {
                                Text(rule.name.isEmpty ? "(unnamed trigger)" : rule.name)
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
                        var rule = TriggerRule()
                        rule.name = "New trigger"
                        settings.upsertTrigger(rule)
                        selection = rule.id
                    } label: { Image(systemName: "plus") }
                    Button {
                        if let id = selection {
                            settings.removeTrigger(id: id)
                            selection = settings.settings.triggerRules.first?.id
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
               let i = settings.settings.triggerRules.firstIndex(where: { $0.id == id }) {
                TriggerRuleEditor(rule: Binding(
                    get: { settings.settings.triggerRules[i] },
                    set: { settings.settings.triggerRules[i] = $0 }
                ), settings: settings)
            } else {
                VStack {
                    Spacer()
                    Text("Select a trigger rule, or add one with + to get started.\nExample: pattern `!rules`, response `The channel rules are at https://example.com/rules`.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .onAppear {
            if selection == nil { selection = settings.settings.triggerRules.first?.id }
        }
    }
}

struct TriggerRuleEditor: View {
    @Binding var rule: TriggerRule
    @ObservedObject var settings: SettingsStore

    private var regexError: String? {
        guard rule.isRegex, !rule.pattern.isEmpty else { return nil }
        do {
            _ = try NSRegularExpression(pattern: rule.pattern, options: [])
            return nil
        } catch {
            return "Invalid regex: \(error.localizedDescription)"
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
                Picker("Scope", selection: $rule.scope) {
                    ForEach(TriggerScope.allCases) { s in
                        Text(s.displayName).tag(s)
                    }
                }
                if let err = regexError {
                    Text(err).font(.caption).foregroundStyle(.orange)
                }
            }
            Section("Response") {
                SpellCheckedTextEditor(text: $rule.response)
                    .frame(minHeight: 60)
                Text("Placeholders: $nick (sender), $channel (target), $match (full match), $1..$9 (regex capture groups).")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Section("Networks") {
                NetworkMultiPicker(settings: settings, selected: $rule.networks)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Shared: network multi-picker

struct NetworkMultiPicker: View {
    @ObservedObject var settings: SettingsStore
    @Binding var selected: [UUID]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("All networks", isOn: Binding(
                get: { selected.isEmpty },
                set: { if $0 { selected = [] } }
            ))
            if !selected.isEmpty || !settings.settings.servers.isEmpty {
                ForEach(ServerProfile.sortedByName(settings.settings.servers)) { profile in
                    Toggle(profile.name, isOn: Binding(
                        get: { selected.contains(profile.id) },
                        set: { on in
                            if on {
                                if !selected.contains(profile.id) { selected.append(profile.id) }
                            } else {
                                selected.removeAll { $0 == profile.id }
                            }
                        }
                    ))
                    .disabled(selected.isEmpty)  // disabled while "all networks" mode is on
                    .foregroundStyle(selected.isEmpty ? .secondary : .primary)
                }
            }
        }
    }
}


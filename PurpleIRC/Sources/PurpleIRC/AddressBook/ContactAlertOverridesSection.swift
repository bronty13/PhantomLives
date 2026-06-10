import SwiftUI

/// Per-contact alert override card. Three tri-state toggles plus an
/// optional custom sound name. Nil = inherit global; .some(true/false)
/// = explicit override. Surfaces the global value as a label so the
/// user knows what "inherit" resolves to in context.
struct ContactAlertOverridesSection: View {
    @Binding var entry: AddressEntry
    @EnvironmentObject var model: ChatModel

    var body: some View {
        let g = model.settings.settings
        VStack(alignment: .leading, spacing: 10) {
            triState(
                title: "System notification banner",
                value: $entry.alertOverride.systemBanner,
                globalValue: g.systemNotificationsOnWatchHit
            )
            triState(
                title: "Play sound",
                value: $entry.alertOverride.playSound,
                globalValue: g.playSoundOnWatchHit
            )
            triState(
                title: "Bounce Dock icon",
                value: $entry.alertOverride.bounceDock,
                globalValue: g.bounceDockOnWatchHit
            )

            HStack {
                Text("Custom sound:")
                    .frame(width: 130, alignment: .leading)
                Picker("", selection: Binding(
                    get: { entry.alertOverride.customSoundName ?? "" },
                    set: { entry.alertOverride.customSoundName = $0.isEmpty ? nil : $0 }
                )) {
                    Text("Use default").tag("")
                    ForEach(builtInSoundNames, id: \.self) { name in
                        Text(name.isEmpty ? "— none —" : name).tag(name)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
                if let name = entry.alertOverride.customSoundName, !name.isEmpty {
                    Button("▶") { NSSound(named: name)?.play() }
                        .buttonStyle(.borderless)
                }
            }

            Divider()

            HStack {
                Text("Message sound:")
                    .frame(width: 130, alignment: .leading)
                Picker("", selection: Binding(
                    get: { entry.alertOverride.messageSoundName ?? "" },
                    set: { entry.alertOverride.messageSoundName = $0.isEmpty ? nil : $0 }
                )) {
                    Text("None").tag("")
                    ForEach(builtInSoundNames, id: \.self) { name in
                        Text(name.isEmpty ? "— none —" : name).tag(name)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
                if let name = entry.alertOverride.messageSoundName, !name.isEmpty {
                    Button("▶") { NSSound(named: name)?.play() }
                        .buttonStyle(.borderless)
                }
            }
            Text("Plays on **any** message from this contact — a private query or a channel line. Leave at “None” to use the global per-event sounds on Setup → Notifications & Sounds.")
                .font(.caption).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("Custom banner text:")
                    .frame(width: 130, alignment: .leading)
                TextField("Optional override of the banner body", text: Binding(
                    get: { entry.alertOverride.customBannerMessage ?? "" },
                    set: { entry.alertOverride.customBannerMessage = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Reset to defaults") {
                    entry.alertOverride = ContactAlertOverride()
                }
                .disabled(entry.alertOverride.isDefault)
            }

            Text("Per-contact overrides win over the global toggles on Setup → Notifications & Sounds. Inherit = use the global value (shown after each toggle).")
                .font(.caption).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func triState(title: String,
                          value: Binding<Bool?>,
                          globalValue: Bool) -> some View {
        HStack {
            Text(title)
                .frame(width: 220, alignment: .leading)
            Picker("", selection: Binding(
                get: {
                    switch value.wrappedValue {
                    case nil:   return "inherit"
                    case true?: return "on"
                    case false?:return "off"
                    }
                },
                set: { sel in
                    switch sel {
                    case "on":  value.wrappedValue = true
                    case "off": value.wrappedValue = false
                    default:    value.wrappedValue = nil
                    }
                }
            )) {
                Text("Inherit (\(globalValue ? "on" : "off"))").tag("inherit")
                Text("On").tag("on")
                Text("Off").tag("off")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 200)
            Spacer()
        }
    }
}

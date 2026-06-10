import SwiftUI
import AppKit

// MARK: - Notifications & Sounds

/// The single home for every way PurpleIRC can grab the user's attention:
/// quiet-mode, watchlist alerts, mentions, per-event sounds, and the
/// per-contact sound throttle. Merged with the former separate Sounds tab
/// (1.0.764) so alert tuning never spans multiple tabs — the only knobs
/// that live elsewhere are deliberately scoped ones: per-rule overrides on
/// the rule editor (Highlights) and per-contact overrides on the contact
/// card (Address Book).
struct NotificationsSetup: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section("Quiet mode") {
                Toggle("Don't alert for the conversation I'm viewing",
                       isOn: $settings.settings.quietWhenBufferVisible)
                Text("When PurpleIRC is the frontmost app and a message lands in the buffer you have selected, skip the sound, banner, and Dock bounce — you're already reading it. The row tint and @ marker still render. Alerts for *other* buffers and while the app is in the background are unaffected.")
                    .font(.caption).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Watched contacts") {
                Toggle("Play sound", isOn: $settings.settings.playSoundOnWatchHit)
                Toggle("Bounce Dock icon", isOn: $settings.settings.bounceDockOnWatchHit)
                Toggle("Show macOS notification banner",
                       isOn: $settings.settings.systemNotificationsOnWatchHit)
                Toggle("Open query when a watched contact first messages me",
                       isOn: $settings.settings.popQueryBufferOnWatch)
                Text("A watch hit fires when a watched address-book contact comes online (via MONITOR or ISON polling) or speaks while you're connected. *Open query* additionally switches the active network and selects the new query buffer when a watched contact's PRIVMSG creates a fresh conversation — off by default so it doesn't yank you out of what you're doing. Per-contact overrides live on the contact's card in the Address Book (⇧⌘B).")
                    .font(.caption).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Own-nick mention") {
                Toggle("Alert when someone says my nick",
                       isOn: $settings.settings.highlightOnOwnNick)
                Text("Mentions tint the row, mark it with @, play the *mention* event sound below, and fire the banner + Dock-bounce channels from *Watched contacts*. Alerts are deduped per sender — a burst of mentions from one person produces one alert every few seconds, not a pile.")
                    .font(.caption).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Event sounds") {
                Toggle("Enable event sounds", isOn: $settings.settings.soundsEnabled)
                Text("Master switch for the per-event sounds below. Choices are saved either way.")
                    .font(.caption).foregroundStyle(.tertiary)
                ForEach(SoundEventKind.allCases) { kind in
                    HStack {
                        Text(kind.displayName)
                        Spacer()
                        Picker("", selection: soundBinding(for: kind)) {
                            ForEach(builtInSoundNames, id: \.self) { n in
                                Text(n.isEmpty ? "— none —" : n).tag(n)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 160)
                        Button("▶") {
                            let name = settings.settings.eventSounds[kind.rawValue] ?? ""
                            if !name.isEmpty { NSSound(named: name)?.play() }
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            Section("Per-contact message sounds") {
                Stepper(value: $settings.settings.contactSoundThrottleSeconds, in: 0...3600) {
                    HStack {
                        Text("Throttle (minimum seconds between sounds per contact)")
                        Spacer()
                        TextField("",
                                  value: $settings.settings.contactSoundThrottleSeconds,
                                  format: .number.grouping(.never))
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
                    }
                }
                Text("A contact's message sound (set per contact in the Address Book) plays on any message from them. This limits it to at most one sound per contact within the window, so a chatty contact doesn't stutter the sound. 0 = play every message. The throttle is per-nick, so different contacts can still each sound.")
                    .font(.caption).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Highlight rules") {
                Text("Per-rule sound / dock / banner toggles live alongside the rule editor on the **Highlights** tab. Rule alerts share the same per-sender dedupe as mentions, so a message that both mentions you and matches a rule alerts once.")
                    .font(.caption).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("System") {
                Text("PurpleIRC requests notification permission the first time the app launches. If you denied it, grant access in **System Settings → Notifications → PurpleIRC**.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
    }

    private func soundBinding(for kind: SoundEventKind) -> Binding<String> {
        Binding(
            get: { settings.settings.eventSounds[kind.rawValue] ?? "" },
            set: { settings.settings.eventSounds[kind.rawValue] = $0 }
        )
    }
}

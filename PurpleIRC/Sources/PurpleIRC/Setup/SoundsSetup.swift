import SwiftUI
import AppKit

/// Setup → Personalization → Sounds. Master enable switch plus per-event
/// sound picker (channel-message, watchlist-hit, highlight, etc.). The
/// list of built-in macOS system sounds is read from `builtInSoundNames`
/// in SoundsAndThemes.swift; the per-event keys live in
/// `AppSettings.eventSounds` and are addressed by `SoundEventKind`.
///
/// Extracted from the monolithic `SetupView.swift` in 1.0.236 — see
/// the Setup/ subdirectory for sibling tab files. SetupView itself now
/// dispatches to these via its `content` switch and stays a slim router.
struct SoundsSetup: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section("Master") {
                Toggle("Enable event sounds", isOn: $settings.settings.soundsEnabled)
                Text("Master switch. Per-event sound choices below are saved either way.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Section("Per-event") {
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

import SwiftUI

struct ExternalRefsSettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore

    var body: some View {
        Form {
            Text("Display labels for the three external-reference slots on each Matter.")
                .font(.caption).foregroundStyle(.secondary)
            row("External 1", binding: bind(\.external1Label))
            row("External 2", binding: bind(\.external2Label))
            row("External 3", binding: bind(\.external3Label))
        }
    }

    private func row(_ title: String, binding: Binding<String>) -> some View {
        HStack {
            Text(title).frame(width: 90, alignment: .trailing).foregroundStyle(.secondary)
            TextField("", text: binding).textFieldStyle(.roundedBorder)
        }
    }

    private func bind<T>(_ kp: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(
            get: { settingsStore.settings[keyPath: kp] },
            set: { v in
                var s = settingsStore.settings
                s[keyPath: kp] = v
                settingsStore.settings = s
                settingsStore.save()
            }
        )
    }
}

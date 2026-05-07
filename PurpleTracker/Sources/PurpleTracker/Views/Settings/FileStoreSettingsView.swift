import SwiftUI

struct FileStoreSettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore

    var body: some View {
        Form {
            Text("Path templates for the two file-store slots assigned to a new Matter. Substitutions: `{year}`, `{date}` (Matter ID's date prefix), `{title}`.")
                .font(.caption).foregroundStyle(.secondary)
            row("Primary",   binding: bind(\.fileStorePrimaryTemplate))
            row("Secondary", binding: bind(\.fileStoreSecondaryTemplate))

            Divider()
            HStack {
                Text("Preview (with title \"Sample Matter\"):").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            preview(template: settingsStore.settings.fileStorePrimaryTemplate)
            preview(template: settingsStore.settings.fileStoreSecondaryTemplate)
        }
    }

    private func row(_ title: String, binding: Binding<String>) -> some View {
        HStack {
            Text(title).frame(width: 90, alignment: .trailing).foregroundStyle(.secondary)
            TextField("", text: binding)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
        }
    }

    private func preview(template: String) -> some View {
        Text(FileStoreService.render(template: template, title: "Sample Matter"))
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
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

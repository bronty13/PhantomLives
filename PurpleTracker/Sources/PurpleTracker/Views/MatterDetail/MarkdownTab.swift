import SwiftUI

struct MarkdownTab: View {
    let field: WritableKeyPath<Matter, String>
    @Binding var matter: Matter
    let label: String
    @EnvironmentObject var settingsStore: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.headline)
            SpellCheckTextEditor(
                text: Binding(
                    get: { matter[keyPath: field] },
                    set: { matter[keyPath: field] = $0 }
                ),
                autocorrectEnabled: settingsStore.settings.autocorrectEnabled
            )
            .frame(minHeight: 360)
        }
    }
}

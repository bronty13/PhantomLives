import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Shortcuts & Aliases

/// User-defined `/alias` entries, listed and editable. Keyboard shortcut
/// customization is documented but not yet wired (the menu items in
/// Phase 2 use built-in shortcuts).
struct ShortcutsAliasesSetup: View {
    @ObservedObject var settings: SettingsStore
    @State private var newName: String = ""
    @State private var newExpansion: String = ""

    private var aliasesSorted: [(String, String)] {
        settings.settings.userAliases.sorted(by: { $0.key < $1.key })
    }

    var body: some View {
        Form {
            Section("User aliases") {
                if aliasesSorted.isEmpty {
                    Text("No user aliases yet. Add one below or use `/alias <name> <expansion>` in any chat buffer.")
                        .font(.caption).foregroundStyle(.tertiary)
                } else {
                    ForEach(aliasesSorted, id: \.0) { name, expansion in
                        HStack {
                            Text("/\(name)")
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 120, alignment: .leading)
                            Text("→")
                                .foregroundStyle(.secondary)
                            Text(expansion)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer()
                            Button(role: .destructive) {
                                settings.settings.userAliases.removeValue(forKey: name)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
            Section("Add an alias") {
                HStack {
                    TextField("name", text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                    Text("→").foregroundStyle(.secondary)
                    TextField("/expansion", text: $newExpansion)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") { addAlias() }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty
                                  || newExpansion.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text("Aliases are resolved before built-in commands, so you can shadow built-ins on purpose. Example: name `j`, expansion `/join` makes `/j #foo` join `#foo`.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Section("Keyboard shortcuts") {
                Text("PurpleIRC ships with built-in keyboard shortcuts for every menu item — see the menus or the Help → Slash Command Reference… sheet for the full list. User-customizable shortcuts are scheduled for a later round.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
    }

    private func addAlias() {
        let name = newName.trimmingCharacters(in: .whitespaces).lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let expansion = newExpansion.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !expansion.isEmpty else { return }
        settings.settings.userAliases[name] = expansion
        newName = ""
        newExpansion = ""
    }
}


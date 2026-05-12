import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Ignore list

struct IgnoreSetup: View {
    @ObservedObject var settings: SettingsStore
    @State private var newMask: String = ""
    @State private var newNote: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("nick!user@host (globs allowed)", text: $newMask)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                TextField("Note (optional)", text: $newNote)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    let m = newMask.trimmingCharacters(in: .whitespaces)
                    guard !m.isEmpty else { return }
                    var e = IgnoreEntry(); e.mask = m; e.note = newNote
                    settings.upsertIgnore(e)
                    newMask = ""; newNote = ""
                }
                .disabled(newMask.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
            Divider()
            if settings.settings.ignoreList.isEmpty {
                ContentUnavailableView(
                    "No ignore entries",
                    systemImage: "nosign",
                    description: Text("Block nicks, hostmasks, or full patterns. `*` and `?` globs are supported.")
                )
                .padding(40)
            } else {
                List {
                    ForEach($settings.settings.ignoreList) { $entry in
                        HStack {
                            TextField("mask", text: $entry.mask)
                                .textFieldStyle(.plain)
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 220, alignment: .leading)
                            TextField("note", text: $entry.note)
                                .textFieldStyle(.plain)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Toggle("CTCP", isOn: $entry.ignoreCTCP)
                                .toggleStyle(.checkbox)
                            Toggle("Notices", isOn: $entry.ignoreNotices)
                                .toggleStyle(.checkbox)
                            Button {
                                settings.removeIgnore(id: entry.id)
                            } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}


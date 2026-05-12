import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Channels

struct ChannelsSetup: View {
    @ObservedObject var settings: SettingsStore
    @EnvironmentObject var model: ChatModel
    @State private var newName: String = ""
    @State private var newNote: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("#channel", text: $newName)
                    .textFieldStyle(.roundedBorder)
                TextField("Note (optional)", text: $newNote)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    let trimmed = newName.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    let name = trimmed.hasPrefix("#") ? trimmed : "#" + trimmed
                    settings.settings.savedChannels.append(
                        SavedChannel(name: name, note: newNote,
                                     serverID: settings.settings.selectedServerID)
                    )
                    newName = ""; newNote = ""
                }
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
            Divider()
            if settings.settings.savedChannels.isEmpty {
                ContentUnavailableView(
                    "No saved channels",
                    systemImage: "number.square",
                    description: Text("Save channels for one-click join from the sidebar. These also auto-join on connect.")
                )
                .padding(40)
            } else {
                List {
                    ForEach($settings.settings.savedChannels) { $ch in
                        HStack {
                            Image(systemName: "number")
                                .foregroundStyle(Color.accentColor)
                            TextField("#channel", text: $ch.name)
                                .textFieldStyle(.plain)
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 180, alignment: .leading)
                            TextField("note", text: $ch.note)
                                .textFieldStyle(.plain)
                                .foregroundStyle(.secondary)
                            Picker("Server", selection: Binding(
                                get: { ch.serverID ?? UUID() },
                                set: { ch.serverID = $0 }
                            )) {
                                Text("Any").tag(UUID())
                                ForEach(settings.settings.servers) { s in
                                    Text(s.name).tag(s.id)
                                }
                            }
                            .frame(width: 140)
                            Button("Join") {
                                model.quickJoin(ch.name)
                            }
                            .disabled(model.connectionState != .connected)
                            Button {
                                settings.removeChannel(id: ch.id)
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


import SwiftUI

struct SetupView: View {
    @EnvironmentObject var model: ChatModel
    @ObservedObject var settings: SettingsStore
    @State private var tab: Tab = .servers

    enum Tab: String, CaseIterable, Identifiable {
        case servers = "Servers"
        case addressBook = "Address Book"
        case channels = "Channels"
        var id: String { rawValue }
        var systemImage: String {
            switch self {
            case .servers: return "server.rack"
            case .addressBook: return "person.crop.rectangle.stack"
            case .channels: return "number"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "gearshape.2")
                    .font(.title2)
                    .foregroundStyle(Color.purple)
                Text("PurpleIRC Setup").font(.title3.weight(.semibold))
                Spacer()
                Text(settings.fileURLForDisplay)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .truncationMode(.middle)
                    .lineLimit(1)
                Button("Done") { model.showSetup = false }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider()
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { t in
                    Label(t.rawValue, systemImage: t.systemImage).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal).padding(.top, 8).padding(.bottom, 4)

            Group {
                switch tab {
                case .servers:     ServersSetup(settings: settings)
                case .addressBook: AddressBookSetup(settings: settings)
                case .channels:    ChannelsSetup(settings: settings)
                }
            }
            .padding()
        }
        .frame(minWidth: 700, minHeight: 520)
    }
}

// MARK: - Servers

struct ServersSetup: View {
    @ObservedObject var settings: SettingsStore
    @State private var selection: UUID?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(settings.settings.servers) { s in
                        HStack {
                            Image(systemName: s.useTLS ? "lock.fill" : "lock.open")
                                .foregroundStyle(s.useTLS ? .green : .secondary)
                            VStack(alignment: .leading) {
                                Text(s.name).font(.body)
                                Text("\(s.host):\(s.port)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(s.id)
                    }
                }
                Divider()
                HStack {
                    Button {
                        let new = ServerProfile()
                        settings.settings.servers.append(new)
                        selection = new.id
                    } label: { Image(systemName: "plus") }
                    Button {
                        if let id = selection {
                            settings.removeServer(id: id)
                            selection = settings.settings.servers.first?.id
                        }
                    } label: { Image(systemName: "minus") }
                    .disabled(selection == nil || settings.settings.servers.count <= 1)
                    Spacer()
                    Button("Set active") {
                        if let id = selection {
                            settings.settings.selectedServerID = id
                        }
                    }
                    .disabled(selection == nil || selection == settings.settings.selectedServerID)
                }
                .padding(6)
            }
            .frame(width: 240)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if let id = selection ?? settings.settings.selectedServerID,
               let i = settings.settings.servers.firstIndex(where: { $0.id == id }) {
                ServerEditor(server: Binding(
                    get: { settings.settings.servers[i] },
                    set: { settings.settings.servers[i] = $0 }
                ))
            } else {
                VStack {
                    Spacer()
                    Text("Select a server").foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .onAppear {
            if selection == nil {
                selection = settings.settings.selectedServerID ?? settings.settings.servers.first?.id
            }
        }
    }
}

struct ServerEditor: View {
    @Binding var server: ServerProfile
    var body: some View {
        Form {
            Section("Profile") {
                TextField("Name", text: $server.name)
            }
            Section("Connection") {
                TextField("Host", text: $server.host)
                Stepper(value: $server.port, in: 1...65535) {
                    TextField("Port", value: $server.port, format: .number)
                }
                Toggle("Use TLS", isOn: $server.useTLS)
                    .onChange(of: server.useTLS) { _, new in
                        if new, server.port == 6667 { server.port = 6697 }
                        if !new, server.port == 6697 { server.port = 6667 }
                    }
                Toggle("Auto-reconnect on drop", isOn: $server.autoReconnect)
            }
            Section("Identity") {
                TextField("Nickname", text: $server.nick)
                TextField("Username", text: $server.user)
                TextField("Real name", text: $server.realName)
                SecureField("Server password (optional)", text: $server.password)
            }
            Section("Authentication (SASL)") {
                Picker("Mechanism", selection: $server.saslMechanism) {
                    ForEach(SASLMechanism.allCases) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                if server.saslMechanism == .plain {
                    TextField("Account (defaults to nick)", text: $server.saslAccount)
                    SecureField("SASL password", text: $server.saslPassword)
                }
                if server.saslMechanism == .external {
                    Text("EXTERNAL uses the client certificate presented over TLS. PurpleIRC does not yet load client certs, so this will typically fail.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            Section("NickServ fallback") {
                SecureField("NickServ password (ignored when SASL is set)", text: $server.nickServPassword)
                Text("Sent as PRIVMSG NickServ :IDENTIFY <password> after welcome, only when SASL is disabled.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Section("Perform on connect") {
                TextEditor(text: $server.performOnConnect)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 80)
                Text("One command per line. Slash commands (like /mode +x) and raw IRC lines (like MODE purple-user +x) both work. Runs after MOTD, before auto-join.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Section("Auto-join") {
                TextField("#channel1, #channel2", text: $server.autoJoin)
                Text("Channels listed here join automatically after login, in addition to channels under the Channels tab.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Address Book

struct AddressBookSetup: View {
    @ObservedObject var settings: SettingsStore
    @State private var newNick: String = ""
    @State private var newNote: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Nickname", text: $newNick)
                    .textFieldStyle(.roundedBorder)
                TextField("Note (optional)", text: $newNote)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    let n = newNick.trimmingCharacters(in: .whitespaces)
                    guard !n.isEmpty else { return }
                    settings.settings.addressBook.append(
                        AddressEntry(nick: n, note: newNote, watch: true)
                    )
                    newNick = ""; newNote = ""
                }
                .disabled(newNick.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
            Divider()
            if settings.settings.addressBook.isEmpty {
                ContentUnavailableView(
                    "No contacts yet",
                    systemImage: "person.crop.circle.badge.plus",
                    description: Text("Add nicknames to track. Toggle ‘Watch’ to get alerts when they come online.")
                )
                .padding(40)
            } else {
                List {
                    ForEach($settings.settings.addressBook) { $entry in
                        HStack {
                            Toggle(isOn: $entry.watch) {
                                Image(systemName: entry.watch ? "bell.fill" : "bell.slash")
                            }
                            .toggleStyle(.button)
                            .help(entry.watch ? "Alerts enabled" : "Alerts disabled")

                            TextField("nickname", text: $entry.nick)
                                .textFieldStyle(.plain)
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 160, alignment: .leading)
                            TextField("note", text: $entry.note)
                                .textFieldStyle(.plain)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                settings.removeAddress(id: entry.id)
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

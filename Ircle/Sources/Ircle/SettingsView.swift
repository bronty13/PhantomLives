import SwiftUI
import IRCKit

struct SettingsView: View {
    var body: some View {
        TabView {
            ConnectionSettingsView()
                .tabItem { Label("Servers", systemImage: "network") }
            AppearanceSettingsView()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
            BackupSettingsView()
                .tabItem { Label("Backup", systemImage: "externaldrive") }
        }
        .frame(width: 600, height: 460)
    }
}

// MARK: - Connection (multi-server manager)

struct ConnectionSettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var model: IrcleModel
    @State private var selectedID: UUID?

    private var servers: [ServerProfile] { settingsStore.settings.servers }

    var body: some View {
        HStack(spacing: 0) {
            serverList
                .frame(width: 180)
            Divider()
            if let binding = selectedBinding {
                ServerEditor(profile: binding)
                    .id(binding.wrappedValue.id)   // reset field focus on switch
            } else {
                VStack {
                    Spacer()
                    Text("Select or add a server.").foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear { if selectedID == nil { selectedID = servers.first?.id } }
    }

    private var serverList: some View {
        VStack(spacing: 0) {
            List(selection: $selectedID) {
                ForEach(servers) { server in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(isConnected(server) ? Color.green : Color.secondary.opacity(0.4))
                            .frame(width: 7, height: 7)
                        Text(server.name).lineLimit(1)
                    }
                    .tag(server.id)
                }
            }
            Divider()
            HStack(spacing: 2) {
                Button(action: addServer) { Image(systemName: "plus") }
                Button(action: removeSelected) { Image(systemName: "minus") }
                    .disabled(selectedID == nil)
                Button(action: duplicateSelected) { Image(systemName: "plus.square.on.square") }
                    .disabled(selectedID == nil)
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 6).padding(.vertical, 4)
        }
    }

    private func isConnected(_ server: ServerProfile) -> Bool {
        model.sessions.contains { $0.profileID == server.id && $0.isConnected }
    }

    private var selectedBinding: Binding<ServerProfile>? {
        guard let id = selectedID,
              let idx = settingsStore.settings.servers.firstIndex(where: { $0.id == id })
        else { return nil }
        return Binding(
            get: { settingsStore.settings.servers[idx] },
            set: { settingsStore.settings.servers[idx] = $0 }
        )
    }

    private func addServer() {
        var p = ServerProfile()
        p.name = "New Server"
        settingsStore.settings.servers.append(p)
        selectedID = p.id
    }

    private func removeSelected() {
        guard let id = selectedID else { return }
        settingsStore.settings.servers.removeAll { $0.id == id }
        selectedID = servers.first?.id
    }

    private func duplicateSelected() {
        guard let id = selectedID,
              let original = servers.first(where: { $0.id == id }) else { return }
        var copy = original
        copy.id = UUID()
        copy.name = original.name + " copy"
        settingsStore.settings.servers.append(copy)
        selectedID = copy.id
    }
}

private struct ServerEditor: View {
    @EnvironmentObject var model: IrcleModel
    @Binding var profile: ServerProfile

    private var session: IrcleSession? {
        model.sessions.first { $0.profileID == profile.id }
    }

    var body: some View {
        Form {
            Section("Server") {
                TextField("Name", text: $profile.name)
                TextField("Host", text: $profile.host)
                TextField("Port", value: $profile.port, format: .number)
                Toggle("Use TLS (SSL)", isOn: $profile.useTLS)
            }
            Section("Identity") {
                TextField("Nickname", text: $profile.nick)
                TextField("Username", text: $profile.user)
                TextField("Real name", text: $profile.realName)
            }
            Section("Authentication") {
                Picker("SASL", selection: $profile.saslMechanism) {
                    ForEach(SASLMechanism.allCases) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                if profile.saslMechanism == .plain {
                    TextField("Account", text: $profile.saslAccount)
                    SecureField("Password", text: $profile.saslPassword)
                }
                SecureField("Server password (optional)", text: $profile.serverPassword)
            }
            Section("Auto-join") {
                TextField("Channels (space-separated)", text: Binding(
                    get: { profile.autoJoin.joined(separator: " ") },
                    set: { profile.autoJoin = $0.split(separator: " ").map(String.init) }
                ))
            }
            Section {
                HStack {
                    Button("Connect") { model.connect(to: profile) }
                    Button("Disconnect") { session?.disconnect() }
                        .disabled(session?.isConnected != true)
                    Spacer()
                    if session?.isConnected == true {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green).font(.caption)
                    }
                }
                Text("Edits apply on the next connect.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Appearance

struct AppearanceSettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Appearance", selection: $settingsStore.settings.appearance) {
                    ForEach(IrcleAppearance.allCases) { a in
                        Text(a.displayName).tag(a)
                    }
                }
                .pickerStyle(.radioGroup)
            }
            Section("Messages") {
                Toggle("Show timestamps", isOn: $settingsStore.settings.showTimestamps)
                HStack {
                    Text("Font size")
                    Slider(value: $settingsStore.settings.fontSize, in: 9...18, step: 1)
                    Text("\(Int(settingsStore.settings.fontSize)) pt")
                        .monospacedDigit().frame(width: 44, alignment: .trailing)
                }
            }
        }
        .formStyle(.grouped)
    }
}

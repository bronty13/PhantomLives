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
                    .help("Add a new server")
                Button(action: removeSelected) { Image(systemName: "minus") }
                    .disabled(selectedID == nil)
                    .help("Remove the selected server")
                Button(action: duplicateSelected) { Image(systemName: "plus.square.on.square") }
                    .disabled(selectedID == nil)
                    .help("Duplicate the selected server")
                Spacer()
                Button(action: addMissingDefaults) { Image(systemName: "list.star") }
                    .help("Add common IRC networks (Libera, OFTC, Undernet, …) that aren't already in the list")
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
              settingsStore.settings.servers.contains(where: { $0.id == id })
        else { return nil }
        // IMPORTANT: look up by id inside the closures — never capture an array
        // index. Removing a server shrinks the array while SwiftUI may still
        // read a previously-built binding; a captured index would then be out
        // of range (crash). An id lookup degrades to a no-op / default instead.
        let store = settingsStore
        return Binding(
            get: { store.settings.servers.first(where: { $0.id == id }) ?? ServerProfile() },
            set: { newValue in
                if let idx = store.settings.servers.firstIndex(where: { $0.id == id }) {
                    store.settings.servers[idx] = newValue
                }
            }
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

    /// Append any well-known networks whose name isn't already in the list.
    /// Idempotent and non-destructive — never edits or removes existing servers.
    private func addMissingDefaults() {
        let existing = Set(servers.map { $0.name.lowercased() })
        let missing = ServerProfile.defaultServers().filter {
            !existing.contains($0.name.lowercased())
        }
        guard !missing.isEmpty else { return }
        settingsStore.settings.servers.append(contentsOf: missing)
        if selectedID == nil { selectedID = missing.first?.id }
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

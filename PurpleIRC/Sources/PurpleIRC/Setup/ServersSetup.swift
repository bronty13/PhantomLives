import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Servers

struct ServersSetup: View {
    @ObservedObject var settings: SettingsStore
    @State private var selection: UUID?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(ServerProfile.sortedByName(settings.settings.servers)) { s in
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
                    Menu {
                        Button("Set active") {
                            if let id = selection {
                                settings.settings.selectedServerID = id
                            }
                        }
                        .disabled(selection == nil || selection == settings.settings.selectedServerID)
                        Divider()
                        Button("Add missing default networks") {
                            addMissingDefaults()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
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

    /// Append any entries from `ServerProfile.defaultServers()` whose name
    /// doesn't already appear in the user's list. Idempotent; safe to click
    /// multiple times. Doesn't touch existing edited profiles, and doesn't
    /// re-add networks the user deliberately deleted in this session — it
    /// only matches by name, so if they removed "Undernet", clicking this
    /// will bring it back. That's the intended behavior (recover missing
    /// defaults after carrying settings over from an older install).
    private func addMissingDefaults() {
        let existingNames = Set(settings.settings.servers.map { $0.name.lowercased() })
        let missing = ServerProfile.defaultServers().filter {
            !existingNames.contains($0.name.lowercased())
        }
        guard !missing.isEmpty else { return }
        settings.settings.servers.append(contentsOf: missing)
    }
}

struct ServerEditor: View {
    @Binding var server: ServerProfile
    @EnvironmentObject var model: ChatModel
    /// Stable sentinel used in the identity Picker to mean "no linked identity".
    /// Any value works as long as it's constant and won't collide with a real
    /// Identity.id, so a hardcoded all-zeros UUID is fine.
    private static let customSentinel = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    /// Bridge `themeOverrideID: String?` (nil = no override) to a String
    /// the Picker can drive (empty string = no override). Avoids a
    /// branch on Optional in the picker selection.
    private var themeOverrideBinding: Binding<String> {
        Binding(
            get: { server.themeOverrideID ?? "" },
            set: { server.themeOverrideID = $0.isEmpty ? nil : $0 }
        )
    }

    var body: some View {
        Form {
            Section("Profile") {
                TextField("Name", text: $server.name)
            }
            Section("Connection") {
                TextField("Host", text: $server.host)
                Stepper(value: $server.port, in: 1...65535) {
                    TextField("Port", value: $server.port, format: .number.grouping(.never))
                }
                Toggle("Use TLS", isOn: $server.useTLS)
                    .onChange(of: server.useTLS) { _, new in
                        if new, server.port == 6667 { server.port = 6697 }
                        if !new, server.port == 6697 { server.port = 6667 }
                    }
                Toggle("Auto-reconnect on drop", isOn: $server.autoReconnect)
            }
            Section("Identity") {
                Picker("Use identity", selection: Binding(
                    get: { server.identityID ?? Self.customSentinel },
                    set: { newID in
                        server.identityID = (newID == Self.customSentinel) ? nil : newID
                    }
                )) {
                    Text("— Custom (use fields below) —")
                        .tag(Self.customSentinel)
                    ForEach(model.settings.settings.identities) { id in
                        Text(id.name.isEmpty ? "(unnamed)" : id.name).tag(id.id)
                    }
                }
                if let linked = model.settings.identity(withID: server.identityID) {
                    // Identity linked — show the values that will actually be
                    // used on the wire, read-only, so the user can see at a
                    // glance what the profile resolves to.
                    LabeledContent("Nickname")  { Text(linked.nick.isEmpty    ? "—" : linked.nick)    .foregroundStyle(.secondary) }
                    LabeledContent("Username")  { Text(linked.user.isEmpty    ? "—" : linked.user)    .foregroundStyle(.secondary) }
                    LabeledContent("Real name") { Text(linked.realName.isEmpty ? "—" : linked.realName).foregroundStyle(.secondary) }
                    SecureField("Server password (optional)", text: $server.password)
                    Text("“\(linked.name)” is linked. Nick, username, real name, SASL, and NickServ come from the identity. Edit them in Setup → Identities.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    // Custom — edit inline on this profile.
                    TextField("Nickname", text: $server.nick)
                    TextField("Username", text: $server.user)
                    TextField("Real name", text: $server.realName)
                    SecureField("Server password (optional)", text: $server.password)
                }
            }
            Section("Authentication (SASL)") {
                if let linked = model.settings.identity(withID: server.identityID) {
                    LabeledContent("Mechanism") {
                        Text(linked.saslMechanism.displayName).foregroundStyle(.secondary)
                    }
                    if linked.saslMechanism == .plain {
                        LabeledContent("Account") {
                            Text(linked.saslAccount.isEmpty ? "(defaults to nick)" : linked.saslAccount)
                                .foregroundStyle(.secondary)
                        }
                        LabeledContent("Password") {
                            Text(linked.saslPassword.isEmpty ? "—" : "••••••••").foregroundStyle(.secondary)
                        }
                    }
                } else {
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
            }
            Section("NickServ fallback") {
                if let linked = model.settings.identity(withID: server.identityID) {
                    LabeledContent("NickServ password") {
                        Text(linked.nickServPassword.isEmpty ? "—" : "••••••••")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    SecureField("NickServ password (ignored when SASL is set)", text: $server.nickServPassword)
                    Text("Sent as PRIVMSG NickServ :IDENTIFY <password> after welcome, only when SASL is disabled.")
                        .font(.caption).foregroundStyle(.tertiary)
                }
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
            Section("Theme") {
                Picker("Theme override", selection: themeOverrideBinding) {
                    Text("— Use global theme —").tag("")
                    ForEach(Theme.all) { t in
                        Text(t.displayName).tag(t.id)
                    }
                    if !model.settings.settings.userThemes.isEmpty {
                        Divider()
                        ForEach(model.settings.settings.userThemes) { u in
                            Text("\(u.name) (custom)").tag(u.id.uuidString)
                        }
                    }
                }
                Text("Pick a theme that takes precedence over the global selection for buffers belonging to this network. Useful for visually distinguishing networks at a glance.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Section("Proxy") {
                Picker("Type", selection: $server.proxyType) {
                    ForEach(ProxyType.allCases) { t in
                        Text(t.displayName).tag(t)
                    }
                }
                .onChange(of: server.proxyType) { _, new in
                    if new == .http, server.proxyPort == 1080 { server.proxyPort = 8080 }
                    if new == .socks5, server.proxyPort == 8080 { server.proxyPort = 1080 }
                }
                if server.proxyType != .none {
                    TextField("Proxy host", text: $server.proxyHost)
                    Stepper(value: $server.proxyPort, in: 1...65535) {
                        TextField("Proxy port", value: $server.proxyPort, format: .number.grouping(.never))
                    }
                    TextField("Proxy username (optional)", text: $server.proxyUsername)
                    SecureField("Proxy password (optional)", text: $server.proxyPassword)
                    Text("The proxy handshake runs before TLS, so TLS connections via SOCKS5 or HTTP CONNECT are supported.")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
        .formStyle(.grouped)
    }
}


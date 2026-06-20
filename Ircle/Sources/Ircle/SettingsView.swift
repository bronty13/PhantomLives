import SwiftUI
import AppKit
import IRCKit

struct SettingsView: View {
    @EnvironmentObject var model: IrcleModel
    @State private var tab: SettingsTab = .servers

    enum SettingsTab: Hashable { case servers, appearance, themes, backup }

    var body: some View {
        TabView(selection: $tab) {
            ConnectionSettingsView()
                .tabItem { Label("Servers", systemImage: "network") }.tag(SettingsTab.servers)
            AppearanceSettingsView()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }.tag(SettingsTab.appearance)
            ModernSettingsView()
                .tabItem { Label("Themes", systemImage: "paintbrush.pointed") }.tag(SettingsTab.themes)
            BackupSettingsView()
                .tabItem { Label("Backup", systemImage: "externaldrive") }.tag(SettingsTab.backup)
        }
        .frame(width: 640, height: 500)
        // The Connections window's "Edit…"/"Server…" jumps straight to Servers.
        .onAppear { if model.pendingEditServerID != nil { tab = .servers } }
        .onChange(of: model.pendingEditServerID) { _, new in if new != nil { tab = .servers } }
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
        .onAppear {
            if model.pendingEditServerID != nil { consumePendingEdit() }
            else if selectedID == nil { selectedID = servers.first?.id }
        }
        // The Connections window's "Edit…" pre-selects a profile here, even if
        // the Settings window was already open.
        .onChange(of: model.pendingEditServerID) { _, _ in consumePendingEdit() }
    }

    /// If the Connections window asked to edit a specific server, select it.
    /// Applied on the next runloop tick so the List is laid out and the
    /// selection reliably "takes" (a synchronous set was flaky on first open).
    private func consumePendingEdit() {
        guard let pend = model.pendingEditServerID,
              servers.contains(where: { $0.id == pend }) else { return }
        DispatchQueue.main.async {
            selectedID = pend
            model.pendingEditServerID = nil
        }
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
    @Environment(\.openWindow) private var openWindow

    /// ColorPicker bindings: read the hex override (falling back to the theme's
    /// current colour for display), write the chosen colour back as hex.
    private var textColorBinding: Binding<Color> {
        Binding(
            get: { Color(ircleHex: settingsStore.settings.customTextColorHex) ?? settingsStore.palette.normalText },
            set: { settingsStore.settings.customTextColorHex = $0.ircleHexString ?? "" }
        )
    }
    private var backgroundColorBinding: Binding<Color> {
        Binding(
            get: { Color(ircleHex: settingsStore.settings.customBackgroundColorHex) ?? settingsStore.palette.textBG },
            set: { settingsStore.settings.customBackgroundColorHex = $0.ircleHexString ?? "" }
        )
    }

    private func eventSoundField(_ label: String, _ key: String) -> some View {
        TextField(label, text: eventBinding(key), prompt: Text("clip filename"))
    }
    private func eventBinding(_ key: String) -> Binding<String> {
        Binding(
            get: { settingsStore.settings.eventSounds[key] ?? "" },
            set: { settingsStore.settings.eventSounds[key] =
                    $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        )
    }

    var body: some View {
        Form {
            Section("Modern mode") {
                Toggle("Enable Modern mode", isOn: $settingsStore.settings.modernModeEnabled)
                Text("Off keeps the classic Ircle look below. On lets the Themes tab drive the whole window with a theme and custom fonts.")
                    .font(.caption).foregroundColor(.secondary)
            }
            Section("Classic appearance") {
                Picker("Appearance", selection: $settingsStore.settings.appearance) {
                    ForEach(IrcleAppearance.allCases) { a in
                        Text(a.displayName).tag(a)
                    }
                }
                .pickerStyle(.radioGroup)
                .disabled(settingsStore.settings.modernModeEnabled)
                if settingsStore.settings.modernModeEnabled {
                    Text("A Modern theme is active — this classic Platinum/Graphite choice applies when Modern mode is off.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            Section("Interface") {
                Picker("Style", selection: $settingsStore.settings.interfaceStyle) {
                    ForEach(InterfaceStyle.allCases) { s in
                        Text(s.displayName).tag(s)
                    }
                }
                .pickerStyle(.radioGroup)
                Text("Clean is a minimal single window. Classic adds the dense original-Ircle cockpit (action grid, mode row, formatting toolbar). Floating recreates Ircle 3.5's separate windows — a Console, a window per channel, a Userlist, and an Inputline.")
                    .font(.caption).foregroundColor(.secondary)
            }
            Section("Custom colours") {
                ColorPicker("Message text", selection: textColorBinding, supportsOpacity: false)
                ColorPicker("Message background", selection: backgroundColorBinding, supportsOpacity: false)
                Button("Reset to theme defaults") {
                    settingsStore.settings.customTextColorHex = ""
                    settingsStore.settings.customBackgroundColorHex = ""
                }
                .disabled(settingsStore.settings.customTextColorHex.isEmpty
                          && settingsStore.settings.customBackgroundColorHex.isEmpty)
                Text("Overrides the chat text and background on top of the chosen theme.")
                    .font(.caption).foregroundColor(.secondary)
            }
            Section("Sounds") {
                Toggle("Play incoming CTCP sound clips", isOn: $settingsStore.settings.ctcpSoundsEnabled)
                Toggle("Play per-event sounds", isOn: $settingsStore.settings.eventSoundsEnabled)
                Group {
                    eventSoundField("Mention", "mention")
                    eventSoundField("Private message", "privatemsg")
                    eventSoundField("Someone joins", "join")
                    eventSoundField("Someone parts", "part")
                }
                .disabled(!settingsStore.settings.eventSoundsEnabled)
                Button("Reveal Sounds Folder") {
                    let dir = SoundService.defaultDirectory
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    NSWorkspace.shared.activateFileViewerSelecting([dir])
                }
                Text("Drop .wav/.aiff/.mp3 clips into ~/Downloads/Ircle/Sounds/ and name them above.")
                    .font(.caption).foregroundColor(.secondary)
            }
            Section("Messages") {
                Toggle("Show timestamps", isOn: $settingsStore.settings.showTimestamps)
                Toggle("Notify me of mentions & private messages",
                       isOn: $settingsStore.settings.notificationsEnabled)
                HStack {
                    Text("Font size")
                    Slider(value: $settingsStore.settings.fontSize, in: 9...18, step: 1)
                    Text("\(Int(settingsStore.settings.fontSize)) pt")
                        .monospacedDigit().frame(width: 44, alignment: .trailing)
                }
            }
            Section("Logging") {
                Toggle("Save chat logs to disk", isOn: $settingsStore.settings.loggingEnabled)
                Text("Transcripts are written to ~/Downloads/Ircle/Logs/<network>/<channel>.log.")
                    .font(.caption).foregroundColor(.secondary)
                HStack {
                    Button("Open Log Viewer") { openWindow(id: "logs") }
                    Button("Reveal Logs Folder") {
                        let dir = LogService.defaultDirectory
                        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                        NSWorkspace.shared.activateFileViewerSelecting([dir])
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

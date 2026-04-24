import SwiftUI

struct SetupView: View {
    @EnvironmentObject var model: ChatModel
    @ObservedObject var settings: SettingsStore
    @State private var tab: Tab = .servers

    enum Tab: String, CaseIterable, Identifiable {
        case servers = "Servers"
        case addressBook = "Address Book"
        case channels = "Channels"
        case ignores = "Ignore"
        case behavior = "Behavior"
        case scripts = "PurpleBot"
        var id: String { rawValue }
        var systemImage: String {
            switch self {
            case .servers: return "server.rack"
            case .addressBook: return "person.crop.rectangle.stack"
            case .channels: return "number"
            case .ignores: return "nosign"
            case .behavior: return "slider.horizontal.3"
            case .scripts: return "curlybraces"
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
                case .ignores:     IgnoreSetup(settings: settings)
                case .behavior:    BehaviorSetup(settings: settings)
                case .scripts:     ScriptsSetup(bot: model.bot)
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
                        TextField("Proxy port", value: $server.proxyPort, format: .number)
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

// MARK: - Behavior (Logs + CTCP + Away)

struct BehaviorSetup: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section("Persistent logs") {
                Toggle("Enable persistent logs", isOn: $settings.settings.enablePersistentLogs)
                Toggle("Include server MOTD and info lines", isOn: $settings.settings.logMotdAndNumerics)
                LabeledContent("Log directory") {
                    Text(settings.logsDirectoryURL.path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Text("Logs rotate at 4 MB per channel. Files live under the app support directory.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Section("CTCP") {
                Toggle("Reply to CTCP requests", isOn: $settings.settings.ctcpRepliesEnabled)
                TextField("VERSION reply", text: $settings.settings.ctcpVersionString)
                Text("Replies to VERSION, PING, TIME, FINGER, SOURCE, USERINFO, CLIENTINFO. Disabled requests still fire events for PurpleBot to handle.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Section("Away") {
                Toggle("Auto-reply to direct PMs while away",
                       isOn: $settings.settings.autoReplyWhenAway)
                TextField("Default away reason",
                          text: $settings.settings.awayReasonDefault)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Auto-reply message").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $settings.settings.awayAutoReply)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 60)
                }
                Text("Use /away [reason] to mark yourself away and /back to return. Auto-replies are throttled per-sender.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Section("Theme") {
                Picker("Theme", selection: $settings.settings.themeID) {
                    ForEach(Theme.all, id: \.id) { t in
                        Text(t.displayName).tag(t.id)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section("Sounds") {
                Toggle("Enable event sounds", isOn: $settings.settings.soundsEnabled)
                ForEach(SoundEventKind.allCases) { kind in
                    HStack {
                        Text(kind.displayName)
                        Spacer()
                        Picker("", selection: soundBinding(for: kind)) {
                            ForEach(builtInSoundNames, id: \.self) { n in
                                Text(n.isEmpty ? "— none —" : n).tag(n)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 160)
                        Button("▶") {
                            let name = settings.settings.eventSounds[kind.rawValue] ?? ""
                            if !name.isEmpty { NSSound(named: name)?.play() }
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func soundBinding(for kind: SoundEventKind) -> Binding<String> {
        Binding(
            get: { settings.settings.eventSounds[kind.rawValue] ?? "" },
            set: { settings.settings.eventSounds[kind.rawValue] = $0 }
        )
    }
}

// MARK: - PurpleBot scripts

struct ScriptsSetup: View {
    @ObservedObject var bot: BotHost
    @State private var selection: UUID?
    @State private var draftSource: String = ""
    @State private var draftName: String = ""
    @State private var draftEnabled: Bool = true

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(bot.scripts) { s in
                        HStack {
                            Image(systemName: s.enabled ? "bolt.fill" : "bolt.slash")
                                .foregroundStyle(s.enabled ? .green : .secondary)
                            VStack(alignment: .leading) {
                                Text(s.name).font(.body)
                                Text(s.filename).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .tag(s.id)
                    }
                }
                Divider()
                HStack {
                    Button {
                        let s = bot.addScript(name: "new script", source: sampleScript)
                        selection = s.id
                        loadSelection()
                    } label: { Image(systemName: "plus") }
                    Button {
                        if let id = selection,
                           let s = bot.scripts.first(where: { $0.id == id }) {
                            bot.remove(s)
                            selection = bot.scripts.first?.id
                            loadSelection()
                        }
                    } label: { Image(systemName: "minus") }
                    .disabled(selection == nil)
                    Spacer()
                    Button("Reload all") { bot.reloadAll() }
                }
                .padding(6)
            }
            .frame(width: 240)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if let id = selection,
               let script = bot.scripts.first(where: { $0.id == id }) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("Name", text: $draftName)
                            .textFieldStyle(.roundedBorder)
                        Toggle("Enabled", isOn: $draftEnabled)
                        Button("Save") {
                            bot.update(script, name: draftName,
                                       source: draftSource, enabled: draftEnabled)
                        }
                        .keyboardShortcut("s", modifiers: [.command])
                    }
                    TextEditor(text: $draftSource)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 280)
                    botLogView
                }
                .padding()
                .onAppear { loadSelection() }
                .onChange(of: selection) { _, _ in loadSelection() }
            } else {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "curlybraces.square")
                        .font(.system(size: 40)).foregroundStyle(.secondary)
                    Text("PurpleBot — JavaScript scripting")
                        .font(.headline)
                    Text(helpText)
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                        .padding(.horizontal)
                    Spacer()
                }
            }
        }
        .onAppear {
            if selection == nil { selection = bot.scripts.first?.id }
            loadSelection()
        }
    }

    private func loadSelection() {
        guard let id = selection,
              let s = bot.scripts.first(where: { $0.id == id }) else {
            draftName = ""; draftSource = ""; draftEnabled = true
            return
        }
        draftName = s.name
        draftEnabled = s.enabled
        draftSource = bot.scriptSource(s)
    }

    private var botLogView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Bot log").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(bot.logLines) { line in
                        Text(line.text)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(color(for: line.level))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
                .padding(6)
            }
            .frame(minHeight: 100, maxHeight: 160)
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    private func color(for level: BotHost.BotLogLine.Level) -> Color {
        switch level {
        case .info:   return .secondary
        case .error:  return .red
        case .script: return .primary
        }
    }

    private let sampleScript = """
    // PurpleBot script — runs inside the app.
    // Docs (in-flight): irc.on(event, cb), irc.onCommand('name', cb),
    // irc.msg(target, text), irc.sendActive(raw), irc.setTimer(ms, cb).

    irc.on('privmsg', (e) => {
      if (e.isMention) {
        console.log('mentioned by ' + e.from + ' in ' + e.target + ': ' + e.text);
      }
    });

    irc.onCommand('hello', (args) => {
      irc.notify('Hello from PurpleBot! args: ' + args);
    });
    """

    private let helpText = """
    Write small scripts that react to IRC events or register /aliases.

    Select a script on the left — or hit + for a new one — to edit it. Press \
    Save (⌘S) to reload all scripts. Logs from console.log appear below the \
    editor.
    """
}

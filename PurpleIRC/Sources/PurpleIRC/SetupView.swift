import SwiftUI

struct SetupView: View {
    @EnvironmentObject var model: ChatModel
    @ObservedObject var settings: SettingsStore
    @State private var tab: Tab = .servers

    /// Adopt any one-shot tab directive (e.g. the Identity toolbar menu's
    /// "Manage identities…" button) so the sheet opens on the right tab
    /// instead of always landing on Servers.
    private func consumePendingTab() {
        if let req = model.pendingSetupTab {
            tab = req
            model.pendingSetupTab = nil
        }
    }

    enum Tab: String, CaseIterable, Identifiable {
        case servers = "Servers"
        case identities = "Identities"
        case addressBook = "Address Book"
        case channels = "Channels"
        case ignores = "Ignore"
        case highlights = "Highlights"
        case bot = "Bot"
        case appearance = "Appearance"
        case behavior = "Behavior"
        case security = "Security"
        case scripts = "PurpleBot"
        var id: String { rawValue }
        var systemImage: String {
            switch self {
            case .servers: return "server.rack"
            case .identities: return "person.2.wave.2"
            case .addressBook: return "person.crop.rectangle.stack"
            case .channels: return "number"
            case .ignores: return "nosign"
            case .highlights: return "sparkles"
            case .bot: return "bolt.badge.a"
            case .appearance: return "paintpalette"
            case .behavior: return "slider.horizontal.3"
            case .security: return "lock.shield"
            case .scripts: return "curlybraces"
            }
        }
    }

    /// Logical grouping used by the sidebar. A segmented bar at 10 tabs is
    /// unreadable on anything smaller than ~1000px; a sectioned sidebar
    /// scales indefinitely and matches the System Settings convention.
    private static let groups: [(String, [Tab])] = [
        ("Connections", [.servers, .identities, .security]),
        ("People & places", [.addressBook, .channels, .ignores]),
        ("Experience", [.appearance, .highlights, .bot, .behavior, .scripts]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                sidebar
                Divider()
                content
            }
        }
        .frame(minWidth: 820, minHeight: 560)
        .onAppear { consumePendingTab() }
        // The sheet may already be showing when a different tab gets
        // requested (e.g. user has Setup open, clicks the toolbar Identity
        // menu's "Manage identities…"). Watching the published value flips
        // the tab even on already-mounted sheets.
        .onChange(of: model.pendingSetupTab) { _, _ in consumePendingTab() }
    }

    private var header: some View {
        HStack {
            Image(systemName: "gearshape.2")
                .font(.title2)
                .foregroundStyle(Color.purple)
            Text("PurpleIRC Setup").font(.title3.weight(.semibold))
            Text("v\(AppVersion.short)")
                .font(.caption).foregroundStyle(.secondary)
                .help("Build \(AppVersion.build)")
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
    }

    private var sidebar: some View {
        List(selection: $tab) {
            ForEach(Self.groups, id: \.0) { (title, tabs) in
                Section(title) {
                    ForEach(tabs) { t in
                        Label(t.rawValue, systemImage: t.systemImage).tag(t)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 180, idealWidth: 200, maxWidth: 220)
    }

    @ViewBuilder
    private var content: some View {
        // No outer ScrollView — Form-based tabs (.appearance, .behavior,
        // .security, .scripts, .ignores, .channels, .addressBook detail)
        // scroll natively via .formStyle(.grouped). Master/detail tabs
        // (.servers, .identities, .highlights, .bot, .addressBook) need
        // their full sheet height so the bottom +/− toolbar stays
        // reachable instead of being pushed below the scroll edge by
        // a long list.
        Group {
            switch tab {
            case .servers:     ServersSetup(settings: settings)
            case .identities:  IdentitiesSetup(settings: settings)
            case .security:    SecuritySetup(settings: settings, keyStore: model.keyStore)
            case .addressBook: AddressBookSetup(settings: settings)
            case .channels:    ChannelsSetup(settings: settings)
            case .ignores:     IgnoreSetup(settings: settings)
            case .highlights:  HighlightsSetup(settings: settings)
            case .bot:         BotSetup(settings: settings, engine: model.botEngine)
            case .appearance:  AppearanceSetup(settings: settings)
            case .behavior:    BehaviorSetup(settings: settings)
            case .scripts:     ScriptsSetup(bot: model.bot)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

// MARK: - Address Book

struct AddressBookSetup: View {
    @ObservedObject var settings: SettingsStore
    @EnvironmentObject var model: ChatModel
    @State private var selection: UUID?

    var body: some View {
        VStack(spacing: 0) {
            alertOptionsBar
            Divider()
            contactsAndEditor
        }
    }

    /// Global alert configuration that fires when a watched user comes
    /// online or our own nick is mentioned. Lives at the top of the
    /// Address Book tab so the contact list and the alerts they trigger
    /// stay in one place — used to be split between this tab and the
    /// Watchlist sheet.
    private var alertOptionsBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "bell.badge.fill")
                    .foregroundStyle(Color.purple)
                Text("Alerts").font(.subheadline.weight(.semibold))
                Spacer()
                Text("Apply to every watched contact below + own-nick mentions")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            HStack(spacing: 24) {
                Toggle("System notification",
                       isOn: $settings.settings.systemNotificationsOnWatchHit)
                Toggle("Play sound",
                       isOn: $settings.settings.playSoundOnWatchHit)
                Toggle("Bounce Dock",
                       isOn: $settings.settings.bounceDockOnWatchHit)
                Toggle("Alert on own nick",
                       isOn: $settings.settings.highlightOnOwnNick)
                Spacer()
            }
            .toggleStyle(.checkbox)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// The original master/detail body, lifted out so the new alerts bar
    /// can sit above it without ballooning indentation.
    @ViewBuilder
    private var contactsAndEditor: some View {
        HStack(spacing: 0) {
            // Master pane — list of contacts. Watch toggle stays inline so
            // the user can flip alerts without opening the editor.
            VStack(spacing: 0) {
                if settings.settings.addressBook.isEmpty {
                    ContentUnavailableView(
                        "No contacts yet",
                        systemImage: "person.crop.circle.badge.plus",
                        description: Text("Add nicknames to track. Toggle “Watch” to get alerts when they come online.")
                    )
                    .padding(20)
                } else {
                    List(selection: $selection) {
                        ForEach(settings.settings.addressBook) { entry in
                            HStack {
                                Image(systemName: entry.watch ? "bell.fill" : "bell.slash")
                                    .foregroundStyle(entry.watch ? Color.purple : .secondary)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(entry.nick.isEmpty ? "(unnamed)" : entry.nick)
                                        .font(.body)
                                    if !entry.note.isEmpty {
                                        Text(entry.note)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                if !entry.richNotes.isEmpty {
                                    // Quick visual cue that the contact has
                                    // longer notes attached.
                                    Image(systemName: "doc.text")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            // Whole-row hit area so a click between the
                            // bell icon and the nick still counts as a tap.
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                openQuery(for: entry)
                            }
                            .tag(entry.id)
                        }
                    }
                }
                Divider()
                HStack {
                    Button {
                        let new = AddressEntry(nick: "", watch: true)
                        settings.settings.addressBook.append(new)
                        selection = new.id
                    } label: { Image(systemName: "plus") }
                    Button {
                        if let id = selection {
                            settings.removeAddress(id: id)
                            selection = settings.settings.addressBook.first?.id
                        }
                    } label: { Image(systemName: "minus") }
                        .disabled(selection == nil)
                    Spacer()
                }
                .padding(6)
            }
            .frame(minWidth: 240, idealWidth: 260, maxWidth: 300)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Detail pane — full editor for the selected contact.
            if let id = selection,
               let i = settings.settings.addressBook.firstIndex(where: { $0.id == id }) {
                AddressEntryEditor(entry: Binding(
                    get: { settings.settings.addressBook[i] },
                    set: { settings.settings.addressBook[i] = $0 }
                ))
            } else {
                VStack {
                    Spacer()
                    Text("Select a contact, or click + to add one.")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .onAppear {
            if selection == nil { selection = settings.settings.addressBook.first?.id }
        }
    }

    /// Open a /query buffer for the contact's nick and dismiss the Setup
    /// sheet so the user lands directly in the conversation. Falls back
    /// silently if the entry has no nick yet.
    private func openQuery(for entry: AddressEntry) {
        let nick = entry.nick.trimmingCharacters(in: .whitespaces)
        guard !nick.isEmpty else { return }
        // Dismiss Setup first so the new buffer is what's on screen
        // when the /query routes through ChatModel — handing off the
        // input is what makes the buffer "open" if it didn't exist.
        model.showSetup = false
        DispatchQueue.main.async {
            model.sendInput("/query \(nick)")
        }
    }
}

/// Editor for a single AddressEntry. Short fields up top, Markdown editor
/// + live preview at the bottom. Splits into two panes when there's
/// vertical room so you can write and see the rendered version side-by-side.
struct AddressEntryEditor: View {
    @Binding var entry: AddressEntry

    var body: some View {
        Form {
            Section("Contact") {
                TextField("Nickname", text: $entry.nick)
                    .textFieldStyle(.roundedBorder)
                Toggle("Alert when this nick comes online", isOn: $entry.watch)
                TextField("Short note (shown next to the nick)", text: $entry.note)
                    .textFieldStyle(.roundedBorder)
            }

            Section("Notes") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Markdown source")
                        .font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $entry.richNotes)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 140)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                        )
                }
                if !entry.richNotes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Preview")
                            .font(.caption).foregroundStyle(.secondary)
                        ScrollView {
                            Text(Self.markdown(entry.richNotes))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(8)
                        }
                        .frame(minHeight: 100, maxHeight: 200)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                        )
                    }
                }
                Text("Supports **bold**, *italic*, `code`, [links](https://example.com), and bullet lists with `-`. Notes are stored in settings.json so they're encrypted along with the rest of your config.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
    }

    /// Parse the Markdown source into an `AttributedString` for preview.
    /// Falls back to plain text on parse failure so a stray `]` doesn't
    /// blank the entire preview.
    private static func markdown(_ src: String) -> AttributedString {
        let opts = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        if let parsed = try? AttributedString(markdown: src, options: opts) {
            return parsed
        }
        return AttributedString(src)
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
    @EnvironmentObject var model: ChatModel
    @State private var legacyLogCount: Int = 0
    @State private var showConvertConfirm: Bool = false
    @State private var convertResultMessage: String? = nil

    var body: some View {
        Form {
            Section("Quit") {
                Toggle("Confirm before /quit or /exit closes the app",
                       isOn: $settings.settings.quitConfirmationEnabled)
                Text("/quit and /exit close PurpleIRC entirely (after sending a QUIT to each connected network). Use /disconnect to leave one network without quitting.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Section("Persistent logs") {
                Toggle("Enable persistent logs", isOn: $settings.settings.enablePersistentLogs)
                Toggle("Include server MOTD and info lines", isOn: $settings.settings.logMotdAndNumerics)
                LabeledContent("Log directory") {
                    Text(settings.logsDirectoryURL.path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Text("Logs rotate at 4 MB per channel. File names are SHA-256 hashes of the network and channel/nick, so someone browsing the folder can't tell which channels you log.")
                    .font(.caption).foregroundStyle(.tertiary)
                if legacyLogCount > 0 {
                    HStack {
                        Label("\(legacyLogCount) plaintext log file\(legacyLogCount == 1 ? "" : "s") left over from before encryption was on.",
                              systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Convert and delete originals…") {
                            showConvertConfirm = true
                        }
                    }
                }
                if let msg = convertResultMessage {
                    Text(msg).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Log retention") {
                Toggle("Auto-delete logs older than N days",
                       isOn: $settings.settings.purgeLogsEnabled)
                Stepper(value: $settings.settings.purgeLogsAfterDays, in: 1...3650) {
                    HStack {
                        Text("Days to keep")
                        Spacer()
                        TextField("", value: $settings.settings.purgeLogsAfterDays,
                                  format: .number.grouping(.never))
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
                    }
                }
                .disabled(!settings.settings.purgeLogsEnabled)
                HStack {
                    Button("Purge now") { model.purgeLogsNow() }
                    Spacer()
                    Text("Runs at app launch when the toggle is on. Off by default; suggested value is 90 days.")
                        .font(.caption).foregroundStyle(.tertiary)
                        .multilineTextAlignment(.trailing)
                }
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
            // Theme + Chat font moved to the dedicated Appearance tab so
            // Behavior stays focused on functional knobs (logging, CTCP,
            // away, sounds, DCC). Easier to reach + less crowded.
            Section("DCC (experimental)") {
                TextField("External IP (for outgoing offers)", text: $settings.settings.dccExternalIP)
                    .font(.system(.body, design: .monospaced))
                HStack {
                    Stepper(value: $settings.settings.dccPortRangeStart, in: 1024...65535) {
                        TextField("Port range start", value: $settings.settings.dccPortRangeStart, format: .number)
                    }
                    Stepper(value: $settings.settings.dccPortRangeEnd, in: 1024...65535) {
                        TextField("Port range end", value: $settings.settings.dccPortRangeEnd, format: .number)
                    }
                }
                Text("Outgoing DCC SEND / CHAT listens on this port range and advertises the address above. Behind NAT you'll need to port-forward and set the public IP — auto-detection only picks up LAN addresses. Passive/reverse DCC and RESUME aren't implemented yet.")
                    .font(.caption).foregroundStyle(.tertiary)
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
        .onAppear { refreshLegacyLogCount() }
        .confirmationDialog(
            "Convert \(legacyLogCount) plaintext log file\(legacyLogCount == 1 ? "" : "s")?",
            isPresented: $showConvertConfirm,
            titleVisibility: .visible
        ) {
            Button("Convert and delete originals", role: .destructive) {
                model.convertLegacyPlaintextLogs { count in
                    convertResultMessage = "Converted \(count) file\(count == 1 ? "" : "s") and removed the plaintext originals."
                    refreshLegacyLogCount()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Each plaintext log will be re-encrypted into the matching encrypted file. The original plaintext file is deleted only after every record is written successfully.")
        }
    }

    private func refreshLegacyLogCount() {
        model.legacyPlaintextLogCount { n in legacyLogCount = n }
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

// MARK: - Highlights

struct HighlightsSetup: View {
    @ObservedObject var settings: SettingsStore
    @State private var selection: UUID?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(settings.settings.highlightRules) { rule in
                        HStack {
                            Image(systemName: rule.enabled ? "sparkles" : "sparkle")
                                .foregroundStyle(rule.enabled
                                                 ? (rule.colorHex.flatMap { Color(hex: $0) } ?? .orange)
                                                 : .secondary)
                            VStack(alignment: .leading) {
                                Text(rule.name.isEmpty ? "(unnamed rule)" : rule.name)
                                Text(rule.pattern.isEmpty ? "(no pattern)" : rule.pattern)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .tag(rule.id)
                    }
                }
                Divider()
                HStack {
                    Button {
                        var rule = HighlightRule()
                        rule.name = "New highlight"
                        settings.upsertHighlight(rule)
                        selection = rule.id
                    } label: { Image(systemName: "plus") }
                    Button {
                        if let id = selection {
                            settings.removeHighlight(id: id)
                            selection = settings.settings.highlightRules.first?.id
                        }
                    } label: { Image(systemName: "minus") }
                        .disabled(selection == nil)
                    Spacer()
                }
                .padding(6)
            }
            .frame(width: 240)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if let id = selection,
               let i = settings.settings.highlightRules.firstIndex(where: { $0.id == id }) {
                HighlightRuleEditor(rule: Binding(
                    get: { settings.settings.highlightRules[i] },
                    set: { settings.settings.highlightRules[i] = $0 }
                ), settings: settings)
            } else {
                VStack {
                    Spacer()
                    Text("Select a highlight rule").foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .onAppear {
            if selection == nil { selection = settings.settings.highlightRules.first?.id }
        }
    }
}

struct HighlightRuleEditor: View {
    @Binding var rule: HighlightRule
    @ObservedObject var settings: SettingsStore
    /// Live colour for the ColorPicker — kept separate from `rule.colorHex`
    /// because a Binding(get:set:) wrapped around the hex string round-trip
    /// chokes on Color/hex conversion drift, and the user's selection
    /// silently doesn't stick. Sync explicitly via .onChange.
    @State private var pickerColor: Color = .orange

    private var regexError: String? {
        guard rule.isRegex, !rule.pattern.isEmpty else { return nil }
        do {
            _ = try NSRegularExpression(pattern: rule.pattern, options: [])
            return nil
        } catch {
            return "Invalid regex: \(error.localizedDescription)"
        }
    }

    var body: some View {
        Form {
            Section("Rule") {
                TextField("Name", text: $rule.name)
                Toggle("Enabled", isOn: $rule.enabled)
            }
            Section("Match") {
                TextField("Pattern", text: $rule.pattern)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                Toggle("Regular expression", isOn: $rule.isRegex)
                Toggle("Case sensitive", isOn: $rule.caseSensitive)
                if let err = regexError {
                    Text(err).font(.caption).foregroundStyle(.orange)
                }
            }
            Section("Appearance") {
                Toggle("Custom color", isOn: Binding(
                    get: { rule.colorHex != nil },
                    set: { enabled in
                        if enabled {
                            let hex = rule.colorHex ?? "#FFA500"
                            rule.colorHex = hex
                            pickerColor = Color(hex: hex) ?? .orange
                        } else {
                            rule.colorHex = nil
                        }
                    }
                ))
                if rule.colorHex != nil {
                    // ColorPicker bound to a real @State — much more
                    // reliable than a Binding(get:set:) over the hex string.
                    // Live changes propagate to rule.colorHex via onChange.
                    ColorPicker("Color", selection: $pickerColor, supportsOpacity: false)
                        .onChange(of: pickerColor) { _, new in
                            // Only commit while custom mode is on, so
                            // toggling off-then-on doesn't accidentally
                            // overwrite the saved colour with the picker
                            // default.
                            if rule.colorHex != nil {
                                rule.colorHex = new.hexRGB
                            }
                        }
                }
            }
            // Keep pickerColor in sync when the user switches between rules
            // or when colorHex is mutated from elsewhere (e.g. settings reload).
            .onAppear { syncPickerColor() }
            .onChange(of: rule.id) { _, _ in syncPickerColor() }
            Section("Actions on match") {
                Toggle("Play highlight sound", isOn: $rule.playSound)
                Toggle("Bounce Dock icon", isOn: $rule.bounceDock)
                Toggle("System notification", isOn: $rule.systemNotify)
            }
            Section("Networks") {
                NetworkMultiPicker(settings: settings, selected: $rule.networks)
            }
        }
        .formStyle(.grouped)
    }

    /// Pull the current rule's hex into the live ColorPicker state.
    /// Called on appear and on rule.id change so swapping between rules in
    /// the master list resets the picker to the right colour.
    private func syncPickerColor() {
        pickerColor = (rule.colorHex.flatMap { Color(hex: $0) }) ?? .orange
    }
}

// MARK: - Bot (native triggers + seen)

struct BotSetup: View {
    @ObservedObject var settings: SettingsStore
    let engine: BotEngine
    @EnvironmentObject var model: ChatModel
    @State private var selection: UUID?

    var body: some View {
        VStack(spacing: 16) {
            seenSection
            Divider()
            triggersSection
        }
    }

    private var seenSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Track joins, parts, quits, and messages for /seen",
                       isOn: $settings.settings.seenTrackingEnabled)
                Text("When enabled, PurpleIRC keeps a last-seen record per network at \(settings.supportDirectoryURL.appendingPathComponent("seen").path). Use /seen <nick> in any buffer to look up a record.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let conn = model.activeConnection {
                    HStack {
                        Text("Active network: \(conn.displayName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("View seen log…") {
                            model.showSetup = false
                            model.showSeenList = true
                        }
                        Button("Clear seen data for this network", role: .destructive) {
                            engine.seenStore.clear(
                                networkID: conn.id,
                                networkSlug: SeenStore.slug(for: conn.displayName)
                            )
                        }
                        .disabled(!settings.settings.seenTrackingEnabled)
                    }
                }
            }
            .padding(6)
        } label: {
            Label("Seen tracker", systemImage: "eye")
        }
    }

    private var triggersSection: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(settings.settings.triggerRules) { rule in
                        HStack {
                            Image(systemName: rule.enabled ? "bolt.fill" : "bolt.slash")
                                .foregroundStyle(rule.enabled ? Color.accentColor : Color.secondary)
                            VStack(alignment: .leading) {
                                Text(rule.name.isEmpty ? "(unnamed trigger)" : rule.name)
                                Text(rule.pattern.isEmpty ? "(no pattern)" : rule.pattern)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .tag(rule.id)
                    }
                }
                Divider()
                HStack {
                    Button {
                        var rule = TriggerRule()
                        rule.name = "New trigger"
                        settings.upsertTrigger(rule)
                        selection = rule.id
                    } label: { Image(systemName: "plus") }
                    Button {
                        if let id = selection {
                            settings.removeTrigger(id: id)
                            selection = settings.settings.triggerRules.first?.id
                        }
                    } label: { Image(systemName: "minus") }
                        .disabled(selection == nil)
                    Spacer()
                }
                .padding(6)
            }
            .frame(width: 240)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if let id = selection,
               let i = settings.settings.triggerRules.firstIndex(where: { $0.id == id }) {
                TriggerRuleEditor(rule: Binding(
                    get: { settings.settings.triggerRules[i] },
                    set: { settings.settings.triggerRules[i] = $0 }
                ), settings: settings)
            } else {
                VStack {
                    Spacer()
                    Text("Select a trigger rule, or add one with + to get started.\nExample: pattern `!rules`, response `The channel rules are at https://example.com/rules`.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .onAppear {
            if selection == nil { selection = settings.settings.triggerRules.first?.id }
        }
    }
}

struct TriggerRuleEditor: View {
    @Binding var rule: TriggerRule
    @ObservedObject var settings: SettingsStore

    private var regexError: String? {
        guard rule.isRegex, !rule.pattern.isEmpty else { return nil }
        do {
            _ = try NSRegularExpression(pattern: rule.pattern, options: [])
            return nil
        } catch {
            return "Invalid regex: \(error.localizedDescription)"
        }
    }

    var body: some View {
        Form {
            Section("Rule") {
                TextField("Name", text: $rule.name)
                Toggle("Enabled", isOn: $rule.enabled)
            }
            Section("Match") {
                TextField("Pattern", text: $rule.pattern)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                Toggle("Regular expression", isOn: $rule.isRegex)
                Toggle("Case sensitive", isOn: $rule.caseSensitive)
                Picker("Scope", selection: $rule.scope) {
                    ForEach(TriggerScope.allCases) { s in
                        Text(s.displayName).tag(s)
                    }
                }
                if let err = regexError {
                    Text(err).font(.caption).foregroundStyle(.orange)
                }
            }
            Section("Response") {
                TextEditor(text: $rule.response)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 60)
                Text("Placeholders: $nick (sender), $channel (target), $match (full match), $1..$9 (regex capture groups).")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Section("Networks") {
                NetworkMultiPicker(settings: settings, selected: $rule.networks)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Shared: network multi-picker

struct NetworkMultiPicker: View {
    @ObservedObject var settings: SettingsStore
    @Binding var selected: [UUID]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("All networks", isOn: Binding(
                get: { selected.isEmpty },
                set: { if $0 { selected = [] } }
            ))
            if !selected.isEmpty || !settings.settings.servers.isEmpty {
                ForEach(ServerProfile.sortedByName(settings.settings.servers)) { profile in
                    Toggle(profile.name, isOn: Binding(
                        get: { selected.contains(profile.id) },
                        set: { on in
                            if on {
                                if !selected.contains(profile.id) { selected.append(profile.id) }
                            } else {
                                selected.removeAll { $0 == profile.id }
                            }
                        }
                    ))
                    .disabled(selected.isEmpty)  // disabled while "all networks" mode is on
                    .foregroundStyle(selected.isEmpty ? .secondary : .primary)
                }
            }
        }
    }
}

// MARK: - Identities

struct IdentitiesSetup: View {
    @ObservedObject var settings: SettingsStore
    @State private var selection: UUID?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(settings.settings.identities) { ident in
                        HStack {
                            Image(systemName: "person.crop.circle")
                                .foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading) {
                                Text(ident.name.isEmpty ? "(unnamed)" : ident.name)
                                Text(ident.nick.isEmpty ? "(no nick)" : ident.nick)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(ident.id)
                    }
                }
                Divider()
                HStack {
                    Button {
                        let ident = Identity()
                        settings.upsertIdentity(ident)
                        selection = ident.id
                    } label: { Image(systemName: "plus") }
                    Button {
                        if let id = selection {
                            settings.removeIdentity(id: id)
                            selection = settings.settings.identities.first?.id
                        }
                    } label: { Image(systemName: "minus") }
                        .disabled(selection == nil)
                    Spacer()
                }
                .padding(6)
            }
            .frame(width: 240)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if let id = selection,
               let i = settings.settings.identities.firstIndex(where: { $0.id == id }) {
                IdentityEditor(identity: Binding(
                    get: { settings.settings.identities[i] },
                    set: { settings.settings.identities[i] = $0 }
                ))
            } else {
                VStack {
                    Spacer()
                    Text("Create an identity with + to share nick, realname, SASL, and NickServ across servers.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 24)
                    Spacer()
                }
            }
        }
        .onAppear {
            if selection == nil { selection = settings.settings.identities.first?.id }
        }
    }
}

struct IdentityEditor: View {
    @Binding var identity: Identity
    var body: some View {
        Form {
            Section("Identity") {
                TextField("Name (e.g. Work, Casual)", text: $identity.name)
            }
            Section("User") {
                TextField("Nickname", text: $identity.nick)
                TextField("Username", text: $identity.user)
                TextField("Real name", text: $identity.realName)
            }
            Section("Authentication (SASL)") {
                Picker("Mechanism", selection: $identity.saslMechanism) {
                    ForEach(SASLMechanism.allCases) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                if identity.saslMechanism == .plain {
                    TextField("Account (defaults to nick)", text: $identity.saslAccount)
                    SecureField("SASL password", text: $identity.saslPassword)
                }
            }
            Section("NickServ fallback") {
                SecureField("NickServ password (ignored when SASL is set)", text: $identity.nickServPassword)
                Text("Sent as PRIVMSG NickServ :IDENTIFY <password> after welcome, only when SASL is disabled.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Security

/// Manages encryption state: enable/disable, change passphrase, lock, reset.
/// Surfaces the composite-key design for the user so they understand what
/// protects what (credentials always via Keychain; metadata + logs only when
/// they enable encryption and pass an unlock).
struct SecuritySetup: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var keyStore: KeyStore

    @State private var showSetupSheet = false
    @State private var showChangeSheet = false
    @State private var showResetConfirm = false

    var body: some View {
        Form {
            Section("Credentials") {
                HStack {
                    Image(systemName: "key.horizontal.fill")
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading) {
                        Text("Stored in macOS Keychain").bold()
                        Text("SASL, NickServ, server, and proxy passwords are moved out of settings.json into your login Keychain on save. No passphrase required — this protection is always on.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Encryption") {
                statusRow
                if keyStore.state == .notSetup {
                    Button("Enable encryption with a passphrase…") {
                        showSetupSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                    Text("Encrypts settings.json and chat logs with AES-256-GCM. A data-encryption key is random; the passphrase wraps it. Forgotten passphrase = unrecoverable data.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    HStack {
                        Button("Change passphrase…") { showChangeSheet = true }
                            .disabled(!keyStore.isUnlocked)
                        Button("Lock now") {
                            keyStore.lock()
                        }
                        .disabled(!keyStore.isUnlocked)
                        Spacer()
                        Button("Disable encryption…", role: .destructive) {
                            showResetConfirm = true
                        }
                    }
                    Text("Lock now clears the Keychain-cached key on this Mac — next launch will require your passphrase. Disable erases the keystore and rewrites settings as plaintext.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Section("Biometrics") {
                if BiometricGate.isAvailable {
                    Toggle("Require Touch ID on launch",
                           isOn: $settings.settings.requireBiometricsOnLaunch)
                        .disabled(keyStore.state == .notSetup)
                    Text("When on and encryption is enabled, the Keychain's silent unlock is gated by Touch ID. Cancelling the prompt falls back to your passphrase. Touch ID is a gate in front of the cached key — it doesn't replace the passphrase.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    Label("Touch ID isn't available on this Mac.", systemImage: "touchid")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            Section("What this protects") {
                bulletRow("settings.json metadata (servers, channels, triggers, highlights) — encrypted on disk when the passphrase is set.")
                bulletRow("Chat logs — encrypted per-line when persistent logging is on (see Behavior tab).")
                bulletRow("Credentials — always in Keychain, regardless of passphrase state.")
                bulletRow("Not covered: running-memory state, a compromised logged-in session with both the Keychain and the passphrase.")
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showSetupSheet) {
            PassphraseSetupView(keyStore: keyStore) {
                // Force a re-save so the first envelope lands on disk.
                settings.save()
            }
        }
        .sheet(isPresented: $showChangeSheet) {
            PassphraseChangeView(keyStore: keyStore)
        }
        .confirmationDialog("Disable encryption?",
                            isPresented: $showResetConfirm,
                            titleVisibility: .visible) {
            Button("Erase keystore and rewrite as plaintext", role: .destructive) {
                keyStore.resetAndWipe()
                settings.save()  // falls back to plaintext now that keystore is gone
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The data-encryption key will be destroyed. Existing encrypted log files become unreadable (delete them manually from Files → Open logs folder). Credentials in the Keychain stay put.")
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        HStack {
            Image(systemName: keyStore.isUnlocked ? "lock.open.fill"
                             : keyStore.state == .locked ? "lock.fill"
                             : "lock.slash")
                .foregroundStyle(keyStore.isUnlocked ? Color.green
                                 : keyStore.state == .locked ? Color.orange
                                 : Color.secondary)
            VStack(alignment: .leading) {
                Text(statusTitle).bold()
                Text(statusDetail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var statusTitle: String {
        switch keyStore.state {
        case .notSetup: return "Not enabled"
        case .locked:   return "Locked"
        case .unlocked: return "Unlocked"
        }
    }

    private var statusDetail: String {
        switch keyStore.state {
        case .notSetup:
            return "settings.json is plaintext; chat logs are plaintext. Credentials still go to Keychain."
        case .locked:
            return "settings.json is encrypted on disk. Enter your passphrase to access it."
        case .unlocked:
            return settings.isEncryptedOnDisk
                ? "settings.json envelope is encrypted on disk; memory holds the decrypted copy."
                : "Keystore is ready. Save once to write the first encrypted envelope."
        }
    }

    @ViewBuilder
    private func bulletRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•").foregroundStyle(.secondary)
            Text(text).font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
    }
}

// MARK: - Theme preview

/// One tile in the theme gallery. Renders a few stylised chat lines using
/// the theme's actual color knobs so the user can pick by eye instead of
/// having to apply each option to find out what it looks like. Click a
/// card to commit; the selected theme gets an accent ring + checkmark.
struct ThemePreviewCard: View {
    let theme: Theme
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(theme.displayName).font(.headline)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            // Mini chat sample — uses real semantic colours from the theme.
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("<alice>").foregroundStyle(theme.ownNickColor)
                    Text("hey, anyone tried Swift 6?").foregroundStyle(.primary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("<bob>").foregroundStyle(theme.nickPalette.first ?? .blue)
                    Text("just yesterday").foregroundStyle(.primary)
                }
                Text("* alice waves").foregroundStyle(theme.actionColor).italic()
                Text("→ carol joined").foregroundStyle(theme.joinColor)
                Text("-NickServ- you are now identified")
                    .foregroundStyle(theme.noticeColor)
            }
            .font(.system(.caption, design: .monospaced))
            .lineLimit(1)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Use the theme's own chat background so cards visibly differ —
            // cream for Solarized Light, deep navy for Tokyo Night, etc.
            .background(theme.chatBackground)
            .foregroundStyle(theme.chatForeground)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            // Palette strip — quick read on the per-nick colours that
            // would land in this theme.
            HStack(spacing: 3) {
                ForEach(0..<min(theme.nickPalette.count, 8), id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(theme.nickPalette[i])
                        .frame(height: 6)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.25),
                        lineWidth: isSelected ? 2 : 0.5)
        )
    }
}

// MARK: - Appearance

/// Theme picker + chat font controls. Lives in its own tab so the user
/// can find visual customisation without hunting through Behavior.
/// Themes are grouped into Light / Adaptive / Dark sections so the gallery
/// reads like a proper picker instead of a wall of cards.
struct AppearanceSetup: View {
    @ObservedObject var settings: SettingsStore

    /// Adaptive themes use the OS appearance for background — they aren't
    /// strictly "light" or "dark" so they get their own section.
    private static let adaptiveIDs: Set<String> = ["classic", "highContrast"]

    private var lightThemes: [Theme] {
        Theme.all.filter { !Self.adaptiveIDs.contains($0.id) && $0.isLightish }
    }
    private var darkThemes: [Theme] {
        Theme.all.filter { !Self.adaptiveIDs.contains($0.id) && !$0.isLightish }
    }
    private var adaptiveThemes: [Theme] {
        Theme.all.filter { Self.adaptiveIDs.contains($0.id) }
    }

    var body: some View {
        Form {
            Section("Light themes") {
                themeGrid(lightThemes)
            }
            Section("Adaptive (follows macOS appearance)") {
                themeGrid(adaptiveThemes)
            }
            Section("Dark themes") {
                themeGrid(darkThemes)
            }
            Section("Time display") {
                Picker("Timestamp format", selection: $settings.settings.timestampFormat) {
                    ForEach(TimestampFormat.allCases) { fmt in
                        Text(fmt.displayName).tag(fmt.rawValue)
                    }
                    // Surface custom-pattern values (e.g. ones the user typed
                    // by hand into settings.json) so the picker can still
                    // reflect them without losing the value on display.
                    if !TimestampFormat.allCases.contains(where: { $0.rawValue == settings.settings.timestampFormat }) {
                        Text("Custom: \(settings.settings.timestampFormat)")
                            .tag(settings.settings.timestampFormat)
                    }
                }
                Text("Live preview — change applies immediately to every chat buffer.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Section("Chat font") {
                Picker("Font family", selection: $settings.settings.chatFontFamily) {
                    ForEach(ChatFontFamily.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                HStack {
                    Text("Size")
                    Slider(value: $settings.settings.chatFontSize, in: 10...24, step: 1)
                    Text(verbatim: "\(Int(settings.settings.chatFontSize)) pt")
                        .frame(width: 50, alignment: .trailing)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Toggle("Bold chat text", isOn: $settings.settings.boldChatText)
                Toggle("Relaxed row spacing (accessibility)", isOn: $settings.settings.relaxedRowSpacing)
                Text("Pairs well with High Contrast. Live preview applies as soon as you adjust the slider.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func themeGrid(_ themes: [Theme]) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10),
                      GridItem(.flexible(), spacing: 10)],
            spacing: 10
        ) {
            ForEach(themes) { theme in
                ThemePreviewCard(
                    theme: theme,
                    isSelected: theme.id == settings.settings.themeID
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    settings.settings.themeID = theme.id
                }
            }
        }
    }
}

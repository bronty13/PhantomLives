import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
        case servers      = "Servers"
        case identities   = "Identities"
        case proxyDcc     = "Proxy & DCC"
        case addressBook  = "Address Book"
        case channels     = "Channels"
        case ignores      = "Ignore"
        case highlights   = "Highlights"
        case behavior     = "Behavior"
        case notifications = "Notifications"
        case logging      = "Logging"
        case appearance   = "Appearance"
        case themes       = "Themes"
        case fonts        = "Fonts"
        case sounds       = "Sounds"
        case bot          = "Bot"
        case scripts      = "PurpleBot"
        case assistant    = "Assistant"
        case shortcuts    = "Shortcuts & Aliases"
        case backup       = "Backup"
        case security     = "Security"
        var id: String { rawValue }
        var systemImage: String {
            switch self {
            case .servers:       return "server.rack"
            case .identities:    return "person.2.wave.2"
            case .proxyDcc:      return "network"
            case .addressBook:   return "person.crop.rectangle.stack"
            case .channels:      return "number"
            case .ignores:       return "nosign"
            case .highlights:    return "sparkles"
            case .behavior:      return "slider.horizontal.3"
            case .notifications: return "bell.badge"
            case .logging:       return "doc.text"
            case .appearance:    return "paintpalette"
            case .themes:        return "swatchpalette"
            case .fonts:         return "textformat"
            case .sounds:        return "speaker.wave.2"
            case .bot:           return "bolt.badge.a"
            case .scripts:       return "curlybraces"
            case .assistant:     return "brain"
            case .shortcuts:     return "command"
            case .backup:        return "externaldrive.badge.timemachine"
            case .security:      return "lock.shield"
            }
        }
    }

    /// Logical grouping used by the sidebar — six sections, mirroring
    /// macOS System Settings. A segmented bar at 20 tabs would be
    /// unreadable; a sectioned sidebar scales indefinitely.
    private static let groups: [(String, [Tab])] = [
        ("Connections",     [.servers, .identities, .proxyDcc]),
        ("People & places", [.addressBook, .channels, .ignores, .highlights]),
        ("Behavior",        [.behavior, .notifications, .logging]),
        ("Personalization", [.appearance, .themes, .fonts, .sounds]),
        ("Power-user",      [.bot, .scripts, .assistant, .shortcuts, .backup]),
        ("Security",        [.security]),
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
            case .servers:       ServersSetup(settings: settings)
            case .identities:    IdentitiesSetup(settings: settings)
            case .proxyDcc:      ProxyDccSetup(settings: settings)
            case .security:      SecuritySetup(settings: settings, keyStore: model.keyStore)
            case .addressBook:   AddressBookSetup(settings: settings)
            case .channels:      ChannelsSetup(settings: settings)
            case .ignores:       IgnoreSetup(settings: settings)
            case .highlights:    HighlightsSetup(settings: settings)
            case .bot:           BotSetup(settings: settings, engine: model.botEngine)
            case .appearance:    AppearanceSetup(settings: settings)
            case .themes:        ThemesSetup(settings: settings)
            case .fonts:         FontsSetup(settings: settings)
            case .sounds:        SoundsSetup(settings: settings)
            case .behavior:      BehaviorSetup(settings: settings)
            case .notifications: NotificationsSetup(settings: settings)
            case .logging:       LoggingSetup(settings: settings)
            case .assistant:     AssistantSetup(settings: settings)
            case .shortcuts:     ShortcutsAliasesSetup(settings: settings)
            case .backup:        BackupSetup(settings: settings)
            case .scripts:       ScriptsSetup(bot: model.bot)
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

// MARK: - Address Book

struct AddressBookSetup: View {
    @ObservedObject var settings: SettingsStore
    @EnvironmentObject var model: ChatModel
    /// Set so the contact list supports cmd-click / shift-click multi-select.
    /// Bulk delete operates on every id in this set; the editor pane only
    /// renders when exactly one id is selected (so there's no ambiguity
    /// about which entry the form is editing).
    @State private var selection: Set<UUID> = []
    /// True while the "Manage tags" sheet is presented. Bound to the
    /// toolbar button so users can add, edit, or delete tags without
    /// leaving the Address Book tab.
    @State private var showTagManager: Bool = false
    /// IDs currently queued for the multi-delete confirmation dialog.
    /// Empty = dialog hidden. Single deletes skip the dialog (instant
    /// feedback matches the prior 1-click behaviour).
    @State private var confirmDeleteIDs: [UUID] = []

    var body: some View {
        VStack(spacing: 0) {
            alertOptionsBar
            Divider()
            contactsAndEditor
        }
        .sheet(isPresented: $showTagManager) {
            ContactTagManagerView(settings: settings)
        }
        .confirmationDialog(
            confirmDeleteIDs.count == 1
                ? "Delete this contact?"
                : "Delete \(confirmDeleteIDs.count) contacts?",
            isPresented: Binding(
                get: { !confirmDeleteIDs.isEmpty },
                set: { if !$0 { confirmDeleteIDs = [] } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                performDelete(ids: confirmDeleteIDs)
                confirmDeleteIDs = []
            }
            Button("Cancel", role: .cancel) {
                confirmDeleteIDs = []
            }
        } message: {
            Text("Removes the selected contact\(confirmDeleteIDs.count == 1 ? "" : "s") from the address book. Their attachments and notes are also removed.")
        }
    }

    /// Bulk-remove every id in `ids`. Picks the next selection BEFORE
    /// mutating the array — same crash-class fix as 1.0.109 — and uses
    /// the surviving entries to land on a sensible neighbor.
    private func performDelete(ids: [UUID]) {
        let removeSet = Set(ids)
        let remaining = settings.settings.addressBook.filter { !removeSet.contains($0.id) }
        // Drop pending selection first so the editor pane unbinds before
        // anything mutates underneath it.
        selection = Set(remaining.first.map { [$0.id] } ?? [])
        for id in ids {
            settings.removeAddress(id: id)
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
                Button {
                    showTagManager = true
                } label: {
                    Label("Manage tags\(settings.settings.contactTags.isEmpty ? "…" : " (\(settings.settings.contactTags.count))")",
                          systemImage: "tag")
                }
                .help("Define labels you can apply to any contact (deleting a tag removes it from every contact)")
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
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.nick.isEmpty ? "(unnamed)" : entry.nick)
                                        .font(.body)
                                    if !entry.note.isEmpty {
                                        Text(entry.note)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    if !entry.tagIDs.isEmpty {
                                        // Inline tag chips so users can spot
                                        // tagged contacts without opening
                                        // the editor. Resolved against the
                                        // global tag list each render so a
                                        // rename or delete propagates live.
                                        ContactTagChipRow(
                                            tagIDs: entry.tagIDs,
                                            allTags: settings.settings.contactTags,
                                            compact: true
                                        )
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
                        let nick = AddressEntry.nextDefaultNick(
                            existing: settings.settings.addressBook)
                        let new = AddressEntry(nick: nick, watch: true)
                        settings.settings.addressBook.append(new)
                        selection = [new.id]
                    } label: { Image(systemName: "plus") }
                    Button {
                        let ids = Array(selection)
                        guard !ids.isEmpty else { return }
                        if ids.count == 1 {
                            // Single-contact delete keeps the prior
                            // one-click behaviour — no confirmation,
                            // matches what users expect from the +/−
                            // bottom bar idiom.
                            performDelete(ids: ids)
                        } else {
                            confirmDeleteIDs = ids
                        }
                    } label: { Image(systemName: "minus") }
                        .disabled(selection.isEmpty)
                        .help(selection.count > 1
                              ? "Delete the \(selection.count) selected contacts"
                              : "Delete the selected contact")
                    Spacer()
                    if selection.count > 1 {
                        Text("\(selection.count) selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(6)
            }
            .frame(minWidth: 240, idealWidth: 260, maxWidth: 300)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Detail pane — full editor for the selected contact. The
            // binding looks up the row by id every time (rather than
            // capturing an index once) so deleting the row underneath
            // an active TextField is a safe no-op instead of an
            // out-of-range crash. Only renders for single-selection so
            // the form is never ambiguous about which row it's editing.
            if selection.count == 1,
               let id = selection.first,
               settings.settings.addressBook.contains(where: { $0.id == id }) {
                AddressEntryEditor(entry: Binding(
                    get: {
                        settings.settings.addressBook
                            .first(where: { $0.id == id }) ?? AddressEntry()
                    },
                    set: { newValue in
                        if let i = settings.settings.addressBook.firstIndex(where: { $0.id == id }) {
                            settings.settings.addressBook[i] = newValue
                        }
                    }
                ))
            } else if selection.count > 1 {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "person.2.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("\(selection.count) contacts selected")
                        .font(.headline)
                    Text("Click − to delete them all, or pick a single contact to edit.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
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
            // The sidebar's "Edit address book entry…" passes the entry's
            // UUID via `pendingAddressBookSelection`. When set, jump to it
            // directly instead of the default first-row landing. Cleared
            // after consume so re-opening the tab doesn't re-fire.
            if let target = model.pendingAddressBookSelection,
               settings.settings.addressBook.contains(where: { $0.id == target }) {
                selection = [target]
                model.pendingAddressBookSelection = nil
            } else if selection.isEmpty,
                      let first = settings.settings.addressBook.first?.id {
                selection = [first]
            }
        }
        .onChange(of: model.pendingAddressBookSelection) { _, newValue in
            // Handles the case where Setup is already open and the
            // directive arrives mid-flight.
            guard let target = newValue,
                  settings.settings.addressBook.contains(where: { $0.id == target })
            else { return }
            selection = [target]
            model.pendingAddressBookSelection = nil
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
    @EnvironmentObject var model: ChatModel

    /// Cross-network seen + log matches for `entry.nick`. Recomputed
    /// whenever the nick changes — see `loadMatches()`.
    @State private var matches: ContactMatchResult = ContactMatchResult()
    /// True while a popover for adding tags is open. Backed by @State so
    /// the popover anchors next to the "Add tag" button.
    @State private var showAddTagPopover: Bool = false

    /// True when the current nickname collides (case-insensitive) with
    /// some other contact in the address book. Surfaces a non-blocking
    /// warning under the field — the user is free to keep typing, but
    /// the visual cue catches accidental duplicates the moment they
    /// happen.
    private var hasDuplicateNick: Bool {
        AddressEntry.nickClashes(
            entry.nick,
            in: model.settings.settings.addressBook,
            excluding: entry.id
        )
    }

    var body: some View {
        Form {
            Section("Photo") {
                HStack(spacing: 16) {
                    ContactAvatar(entry: entry, size: 72)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Button {
                                pickPhoto()
                            } label: {
                                Label("Choose photo…", systemImage: "photo.on.rectangle")
                            }
                            if entry.photoData != nil {
                                Button(role: .destructive) {
                                    entry.photoData = nil
                                } label: {
                                    Label("Remove", systemImage: "xmark.circle")
                                }
                            }
                        }
                        Text(entry.photoData != nil
                             ? "Photo embedded in settings.json (downscaled to ≤256 px, JPEG)."
                             : "No photo. Falls back to the auto-tinted initial avatar.")
                            .font(.caption).foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers in
                    handleDrop(providers)
                    return true
                }
            }
            Section("Contact") {
                TextField("Nickname", text: $entry.nick)
                    .textFieldStyle(.roundedBorder)
                if hasDuplicateNick {
                    Label("Another contact already uses this nickname.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Toggle("Alert when this nick comes online", isOn: $entry.watch)
                TextField("Short note (shown next to the nick)", text: $entry.note)
                    .textFieldStyle(.roundedBorder)
            }

            Section("Tags") {
                if entry.tagIDs.isEmpty {
                    Text("No tags. Use the picker below to label this contact (e.g. *Friend*, *Work*, *Channel-op*).")
                        .font(.caption).foregroundStyle(.tertiary)
                } else {
                    ContactTagChipRow(
                        tagIDs: entry.tagIDs,
                        allTags: model.settings.settings.contactTags,
                        compact: false,
                        onRemove: { id in
                            entry.tagIDs.removeAll { $0 == id }
                        }
                    )
                }
                HStack {
                    Button {
                        showAddTagPopover = true
                    } label: {
                        Label("Add tag…", systemImage: "tag")
                    }
                    .popover(isPresented: $showAddTagPopover, arrowEdge: .bottom) {
                        ContactTagAddPopover(
                            assigned: entry.tagIDs,
                            settings: model.settings,
                            onPick: { id in
                                if !entry.tagIDs.contains(id) {
                                    entry.tagIDs.append(id)
                                }
                            }
                        )
                    }
                    Text("Defined in **Manage tags…** at the top of the Address Book tab. Deleting a tag removes it from every contact.")
                        .font(.caption).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section {
                ContactMatchesSection(
                    nick: entry.nick,
                    matches: matches,
                    onOpenSeenList: { conn in
                        model.activeConnectionID = conn.id
                        model.showSeenList = true
                    },
                    onOpenChatLogs: {
                        model.showChatLogs = true
                    },
                    onOpenQuery: { nick in
                        model.showSetup = false
                        DispatchQueue.main.async {
                            model.sendInput("/query \(nick)")
                        }
                    }
                )
            } header: {
                Text("Matches in seen log + chat logs")
            }

            Section("Attachments") {
                if entry.attachments.isEmpty {
                    Text("No attachments. Click **Attach file…** or drop any file into this section. Bytes live in the encrypted blob store; this list shows lightweight references.")
                        .font(.caption).foregroundStyle(.tertiary)
                } else {
                    ForEach(entry.attachments) { ref in
                        AttachmentRow(ref: ref) {
                            openAttachment(ref)
                        } onReveal: {
                            revealAttachment(ref)
                        } onRemove: {
                            removeAttachment(ref)
                        }
                    }
                }
                Button {
                    pickAttachment()
                } label: {
                    Label("Attach file…", systemImage: "paperclip")
                }
            }
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                handleAttachmentDrop(providers)
                return true
            }

            Section("Notes") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Markdown source")
                        .font(.caption).foregroundStyle(.secondary)
                    SpellCheckedTextEditor(text: $entry.richNotes)
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
        .onAppear { loadMatches() }
        .onChange(of: entry.id) { _, _ in loadMatches() }
        .onChange(of: entry.nick) { _, _ in loadMatches() }
    }

    /// Recompute exact + fuzzy matches against every connected network's
    /// SeenStore and the LogStore index. Cheap enough to run on each
    /// nick edit — both stores keep their data in memory once warm.
    /// LogStore is an actor, so the read happens off the main actor in a
    /// detached Task.
    private func loadMatches() {
        let nick = entry.nick.trimmingCharacters(in: .whitespaces)
        guard !nick.isEmpty else {
            matches = ContactMatchResult()
            return
        }
        // Seen-store work is synchronous on the main actor.
        var seenHits: [ContactMatchResult.SeenHit] = []
        for conn in model.connections {
            let entries = model.botEngine.seenStore.entries(
                networkID: conn.id,
                networkSlug: SeenStore.slug(for: conn.displayName))
            for e in entries where ContactMatchResult.matches(needle: nick, candidate: e.nick) {
                seenHits.append(.init(
                    connection: conn,
                    networkName: conn.displayName,
                    seen: e,
                    isExact: e.nick.caseInsensitiveCompare(nick) == .orderedSame
                ))
            }
        }
        // Sort: exact matches first, then by recency.
        seenHits.sort {
            if $0.isExact != $1.isExact { return $0.isExact && !$1.isExact }
            return $0.seen.timestamp > $1.seen.timestamp
        }
        // Log lookup is async — kick off a Task and merge results back on
        // the main actor when ready. The view re-renders on `matches` set.
        let needle = nick
        let store = model.logStore
        Task {
            let result = await store.enumerateAllLogs()
            var logHits: [ContactMatchResult.LogHit] = []
            for entry in result.named where ContactMatchResult.matches(needle: needle, candidate: entry.buffer) {
                logHits.append(.init(
                    network: entry.network,
                    buffer: entry.buffer,
                    isExact: entry.buffer.caseInsensitiveCompare(needle) == .orderedSame
                ))
            }
            logHits.sort {
                if $0.isExact != $1.isExact { return $0.isExact && !$1.isExact }
                if $0.network != $1.network {
                    return $0.network.localizedCaseInsensitiveCompare($1.network) == .orderedAscending
                }
                return $0.buffer.localizedCaseInsensitiveCompare($1.buffer) == .orderedAscending
            }
            await MainActor.run {
                // Only commit if the editor is still on the same nick — a
                // fast typist could have moved on while the actor was busy.
                if entry.nick.trimmingCharacters(in: .whitespaces) == needle {
                    self.matches = ContactMatchResult(seen: seenHits, logs: logHits)
                }
            }
        }
        // Show the seen results immediately while the log results land.
        matches = ContactMatchResult(seen: seenHits, logs: matches.logs)
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

    /// NSOpenPanel-driven photo picker. Filters to common image types,
    /// passes the chosen file through PhotoUtilities for downscale +
    /// JPEG re-encode so the inline storage stays small even when the
    /// user picks a 4K wallpaper.
    private func pickPhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Choose profile photo"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            if let data = PhotoUtilities.loadDownscaled(from: url) {
                Task { @MainActor in
                    entry.photoData = data
                }
            }
        }
    }

    /// NSOpenPanel-driven attachment picker. No type filter — any file
    /// is fair game. Routed through the BlobStore so the bytes are
    /// encrypted at rest the same way every other persistence path is.
    private func pickAttachment() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.title = "Attach files to \(entry.nick.isEmpty ? "this contact" : entry.nick)"
        panel.begin { response in
            guard response == .OK else { return }
            let urls = panel.urls
            let entryID = entry.id
            Task {
                for url in urls {
                    if let rec = await model.blobStore.store(fileURL: url, attachedTo: entryID) {
                        await MainActor.run {
                            entry.attachments.append(BlobStore.AttachmentRef(
                                id: rec.id,
                                filename: rec.filename,
                                contentType: rec.contentType,
                                sizeBytes: rec.sizeBytes
                            ))
                        }
                    }
                }
            }
        }
    }

    /// Drag-and-drop entry point for attachments. Accepts file URLs
    /// dragged from Finder, routes them through the BlobStore the
    /// same way the picker does.
    private func handleAttachmentDrop(_ providers: [NSItemProvider]) {
        let entryID = entry.id
        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { continue }
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                guard let urlData = item as? Data,
                      let url = URL(dataRepresentation: urlData, relativeTo: nil) else { return }
                Task {
                    if let rec = await model.blobStore.store(fileURL: url, attachedTo: entryID) {
                        await MainActor.run {
                            entry.attachments.append(BlobStore.AttachmentRef(
                                id: rec.id,
                                filename: rec.filename,
                                contentType: rec.contentType,
                                sizeBytes: rec.sizeBytes
                            ))
                        }
                    }
                }
            }
        }
    }

    /// "Open" — materialise the blob to a temp file and hand off to
    /// the OS via NSWorkspace. The OS picks the right handler based
    /// on file extension / UTType.
    private func openAttachment(_ ref: BlobStore.AttachmentRef) {
        let id = ref.id
        Task {
            guard let url = await model.blobStore.writeToTempFile(id) else { return }
            await MainActor.run {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// "Reveal in Finder" — same temp-file materialisation as Open,
    /// then `activateFileViewerSelecting` so the user gets a Finder
    /// window with the file selected.
    private func revealAttachment(_ ref: BlobStore.AttachmentRef) {
        let id = ref.id
        Task {
            guard let url = await model.blobStore.writeToTempFile(id) else { return }
            await MainActor.run {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }

    /// Remove the attachment from BOTH the inline ref list and the
    /// blob store. Keeping them in sync is the editor's job — the
    /// store doesn't reach back into AddressEntry.
    private func removeAttachment(_ ref: BlobStore.AttachmentRef) {
        entry.attachments.removeAll { $0.id == ref.id }
        let id = ref.id
        Task {
            await model.blobStore.delete(id)
        }
    }

    /// Drag-and-drop entry point. Accepts both `.image` (raw bitmap
    /// dragged from another app) and `.fileURL` (e.g. dragged from
    /// Finder). Resolves to a Data and routes through the same
    /// PhotoUtilities pipeline as the picker.
    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            if provider.canLoadObject(ofClass: NSImage.self) {
                provider.loadObject(ofClass: NSImage.self) { obj, _ in
                    guard let img = obj as? NSImage,
                          let data = PhotoUtilities.downscaleAndEncode(img) else { return }
                    Task { @MainActor in
                        entry.photoData = data
                    }
                }
                return
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    guard let urlData = item as? Data,
                          let url = URL(dataRepresentation: urlData, relativeTo: nil),
                          let data = PhotoUtilities.loadDownscaled(from: url) else { return }
                    Task { @MainActor in
                        entry.photoData = data
                    }
                }
                return
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
            Section("Quit") {
                Toggle("Confirm before /quit or /exit closes the app",
                       isOn: $settings.settings.quitConfirmationEnabled)
                Text("/quit and /exit close PurpleIRC entirely (after sending a QUIT to each connected network). Use /disconnect to leave one network without quitting.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Section("Session restore") {
                Toggle("Restore open channels and queries on launch",
                       isOn: $settings.settings.restoreOpenBuffersOnLaunch)
                Text("When you reconnect, PurpleIRC re-joins the channels you had open and re-creates query buffers from your last session. Channel JOINs go through the normal CAP / auto-join path, so server-side ACLs still apply. Off = fresh slate every connect.")
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
                    SpellCheckedTextEditor(
                        text: $settings.settings.awayAutoReply,
                        font: .systemFont(ofSize: 13))
                        .frame(minHeight: 60)
                }
                Text("Use /away [reason] to mark yourself away and /back to return. Auto-replies are throttled per-sender.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Section("Where to find moved settings") {
                Text("• Notifications (sound / dock / banner alerts) → **Notifications** tab")
                Text("• Persistent logs and retention → **Logging** tab")
                Text("• Per-event sound chooser → **Sounds** tab")
                Text("• DCC + proxy → **Proxy & DCC** tab")
                Text("• Backups → **Backup** tab")
            }
            .font(.caption)
        }
        .formStyle(.grouped)
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
        // Wrap in ScrollView — the assistant section + seen + triggers
        // together blow past the sheet's minHeight on smaller screens,
        // and without scrolling the header (which contains the Done
        // button) gets pushed off the top edge of the dialog.
        ScrollView {
            VStack(spacing: 16) {
                assistantSection
                Divider()
                seenSection
                Divider()
                triggersSection
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var assistantSection: some View {
        AssistantSetupSection(settings: settings)
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
                SpellCheckedTextEditor(text: $rule.response)
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
                    // Surface the live availability diagnostic so a "ready"
                    // row reads as confidence and a transient failure
                    // (locked out, etc.) tells the user what to fix.
                    Label(BiometricGate.availabilityDetail, systemImage: "touchid")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Label(BiometricGate.availabilityDetail, systemImage: "touchid")
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

            Section("Factory reset") {
                FactoryResetRow()
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

    var body: some View {
        Form {
            Section("Time display") {
                Picker("Timestamp format", selection: $settings.settings.timestampFormat) {
                    ForEach(TimestampFormat.allCases) { fmt in
                        Text(fmt.displayName).tag(fmt.rawValue)
                    }
                    if !TimestampFormat.allCases.contains(where: { $0.rawValue == settings.settings.timestampFormat }) {
                        Text("Custom: \(settings.settings.timestampFormat)")
                            .tag(settings.settings.timestampFormat)
                    }
                }
                Text("Live preview — change applies immediately to every chat buffer. /timestamp on|off|<pattern> works as a slash command too.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Section("Density") {
                Picker("Chat row density", selection: $settings.settings.chatDensity) {
                    ForEach(ChatDensity.allCases) { d in
                        Text(d.displayName).tag(d)
                    }
                }
                .pickerStyle(.segmented)
                Text("Vertical breathing room between chat rows. /density compact|cozy|comfortable also works.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Section("Reading aids") {
                Toggle("Bold chat text", isOn: $settings.settings.boldChatText)
                Toggle("Relaxed row spacing (accessibility)", isOn: $settings.settings.relaxedRowSpacing)
                Toggle("Collapse runs of join / part / quit lines",
                       isOn: $settings.settings.collapseJoinPart)
                Text("Each toggle applies immediately. Bold pairs well with High Contrast.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Section("Where to find moved settings") {
                Text("• Theme grid → **Themes** tab")
                Text("• Font family / size / weight → **Fonts** tab")
                Text("• Per-event sound chooser → **Sounds** tab")
            }
            .font(.caption)
        }
        .formStyle(.grouped)
    }
}

// MARK: - Proxy & DCC

/// Network plumbing that used to live at the bottom of Behavior. Splitting
/// it out keeps the per-network proxy + DCC settings together so a user
/// configuring a corporate proxy doesn't have to scroll past quit / away
/// toggles to find them.
struct ProxyDccSetup: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section("DCC (file transfers + chat)") {
                TextField("External IP (for outgoing offers)",
                          text: $settings.settings.dccExternalIP)
                    .font(.system(.body, design: .monospaced))
                HStack {
                    Stepper(value: $settings.settings.dccPortRangeStart, in: 1024...65535) {
                        TextField("Port range start",
                                  value: $settings.settings.dccPortRangeStart,
                                  format: .number)
                    }
                    Stepper(value: $settings.settings.dccPortRangeEnd, in: 1024...65535) {
                        TextField("Port range end",
                                  value: $settings.settings.dccPortRangeEnd,
                                  format: .number)
                    }
                }
                Text("Outgoing DCC SEND / CHAT listens on this port range and advertises the address above. Behind NAT you'll need to port-forward and set the public IP — auto-detection only picks up LAN addresses. Passive/reverse DCC and RESUME aren't implemented yet.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Section("Proxy") {
                Text("Per-server proxy settings (SOCKS5 / HTTP CONNECT) live on each server profile under **Servers**. Defaults are direct connection.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Notifications

/// All the channels through which an event can grab the user's attention,
/// surfaced as a single tab so they're easy to tune as a group rather
/// than scattered across Behavior + Appearance + Highlights.
struct NotificationsSetup: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section("Watchlist hits") {
                Toggle("Play sound", isOn: $settings.settings.playSoundOnWatchHit)
                Toggle("Bounce Dock icon", isOn: $settings.settings.bounceDockOnWatchHit)
                Toggle("Show macOS notification banner",
                       isOn: $settings.settings.systemNotificationsOnWatchHit)
                Text("A watch hit fires when a watched address-book contact comes online (via MONITOR or ISON polling) or speaks while you're connected.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Section("Own-nick mention") {
                Toggle("Highlight when someone says my nick",
                       isOn: $settings.settings.highlightOnOwnNick)
                Text("Mentions tint the row, mark it with @, and fire the same sound + banner + dock-bounce alerts as watchlist hits. Per-rule alerts on the **Highlights** tab override these defaults.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Section("Highlight rules") {
                Text("Per-rule sound / dock / banner toggles live alongside the rule editor on the **Highlights** tab.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Section("System") {
                Text("PurpleIRC requests notification permission the first time the app launches. If you denied it, grant access in **System Settings → Notifications → PurpleIRC**.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Logging

/// Persistent chat-log toggles, retention policy, and the legacy plaintext
/// conversion path. Lifted out of Behavior so a user worried about disk
/// usage or compliance has a single tab to audit.
struct LoggingSetup: View {
    @ObservedObject var settings: SettingsStore
    @EnvironmentObject var model: ChatModel
    @State private var legacyLogCount: Int = 0
    @State private var showConvertConfirm: Bool = false
    @State private var convertResultMessage: String? = nil

    var body: some View {
        Form {
            Section("Persistent logs") {
                Toggle("Enable persistent logs",
                       isOn: $settings.settings.enablePersistentLogs)
                Toggle("Include server MOTD and info lines",
                       isOn: $settings.settings.logMotdAndNumerics)
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
            Section("Retention") {
                Toggle("Auto-delete logs older than N days",
                       isOn: $settings.settings.purgeLogsEnabled)
                Stepper(value: $settings.settings.purgeLogsAfterDays, in: 1...3650) {
                    HStack {
                        Text("Days to keep")
                        Spacer()
                        TextField("",
                                  value: $settings.settings.purgeLogsAfterDays,
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
            Section("Diagnostic log") {
                Text("App-level events (debug → critical) live in the in-app diagnostic log, encrypted on disk. Open it via /log, the Help menu, or the Files menu. Useful for bug reports.")
                    .font(.caption).foregroundStyle(.tertiary)
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
}

// MARK: - Themes

/// Theme grid + WYSIWYG builder launchpad. The grid renders built-in
/// themes (grouped light / adaptive / dark) AND user themes (with
/// edit + delete affordances). New / Edit / Duplicate route to
/// ThemeBuilderView.
struct ThemesSetup: View {
    @ObservedObject var settings: SettingsStore
    @State private var builderDraft: UserTheme? = nil
    @State private var builderIsNew: Bool = false

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
            Section("Custom themes") {
                if settings.settings.userThemes.isEmpty {
                    Text("No custom themes yet. Click **+ New theme** to duplicate the currently-selected theme as a starting point, or **Import…** to load a `.purpletheme` file someone shared.")
                        .font(.caption).foregroundStyle(.tertiary)
                } else {
                    ForEach(settings.settings.userThemes) { user in
                        userThemeRow(user)
                    }
                }
                HStack {
                    Button {
                        startNewFromActive()
                    } label: {
                        Label("New theme", systemImage: "plus.square.on.square")
                    }
                    Button {
                        importThemeFile()
                    } label: {
                        Label("Import…", systemImage: "square.and.arrow.down")
                    }
                    Spacer()
                }
                .padding(.top, 4)
            }
            Section("Light themes")    { themeGrid(lightThemes) }
            Section("Adaptive (follows macOS appearance)") { themeGrid(adaptiveThemes) }
            Section("Dark themes")     { themeGrid(darkThemes) }
        }
        .formStyle(.grouped)
        .sheet(item: $builderDraft) { draft in
            ThemeBuilderView(
                settings: settings,
                draft: draft,
                isNew: builderIsNew
            )
        }
    }

    @ViewBuilder
    private func userThemeRow(_ user: UserTheme) -> some View {
        HStack(spacing: 10) {
            // Tiny preview swatch — chat background + foreground tile.
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(hex: user.chatBackgroundHex) ?? .gray)
                Text("Aa")
                    .foregroundStyle(Color(hex: user.chatForegroundHex) ?? .white)
                    .font(.caption.bold())
            }
            .frame(width: 44, height: 28)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(user.id.uuidString == settings.settings.themeID
                            ? Color.accentColor : Color.gray.opacity(0.3),
                            lineWidth: user.id.uuidString == settings.settings.themeID ? 2 : 1)
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(user.name).font(.body)
                if let basedOn = user.basedOn {
                    Text("Based on \(basedOn)")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Button("Use") {
                settings.settings.themeID = user.id.uuidString
            }
            .disabled(user.id.uuidString == settings.settings.themeID)
            Button {
                builderDraft = user
                builderIsNew = false
            } label: {
                Image(systemName: "pencil")
            }
            .help("Edit in the Theme Builder")
            .buttonStyle(.borderless)
            Button {
                duplicateUserTheme(user)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .help("Duplicate")
            .buttonStyle(.borderless)
            Button(role: .destructive) {
                deleteUserTheme(user)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
    }

    private func startNewFromActive() {
        // Resolve whatever's currently selected (built-in OR existing
        // user theme) and snapshot it as the starting point. Materialising
        // a user theme back through duplicate(of:) round-trips its
        // colors via Color, which can drift slightly on the OS color
        // pipeline — acceptable here since the user's editing it.
        let active = Theme.resolve(id: settings.settings.themeID,
                                    userThemes: settings.settings.userThemes)
        builderDraft = UserTheme.duplicate(of: active, name: "")
        builderIsNew = true
    }

    private func duplicateUserTheme(_ user: UserTheme) {
        var copy = user
        copy.id = UUID()
        copy.name = "\(user.name) copy"
        copy.createdAt = Date()
        settings.settings.userThemes.append(copy)
    }

    private func deleteUserTheme(_ user: UserTheme) {
        settings.settings.userThemes.removeAll { $0.id == user.id }
        if settings.settings.themeID == user.id.uuidString {
            settings.settings.themeID = user.basedOn ?? "classic"
        }
    }

    private func importThemeFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Import theme"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                if let imported = ThemeImporter.importTheme(from: url, into: settings) {
                    settings.settings.themeID = imported.id.uuidString
                }
            }
        }
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

// MARK: - Fonts

/// Font controls — Chat (root font), Per-element overrides, Zoom, plus
/// a built-in installed-font browser. Per-element overrides walk the
/// inheritance chain via `FontStyle.resolved(parent:)`, so leaving any
/// field at its sentinel inherits from the chat body.
struct FontsSetup: View {
    @ObservedObject var settings: SettingsStore
    @State private var browseTarget: BrowseTarget? = nil
    @State private var showCustomFont: Bool = false

    enum BrowseTarget: Identifiable {
        case chatBody, nick, timestamp, systemLine
        var id: Int {
            switch self {
            case .chatBody: return 0
            case .nick: return 1
            case .timestamp: return 2
            case .systemLine: return 3
            }
        }
        var label: String {
            switch self {
            case .chatBody:    return "chat body"
            case .nick:        return "nick column"
            case .timestamp:   return "timestamp column"
            case .systemLine:  return "system / info lines"
            }
        }
    }

    var body: some View {
        Form {
            Section("Chat font (root)") {
                Picker("Family", selection: $settings.settings.chatFontFamily) {
                    ForEach(ChatFontFamily.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                HStack {
                    if !settings.settings.chatBodyFont.family.isEmpty {
                        Label("Custom: \(settings.settings.chatBodyFont.family)",
                              systemImage: "textformat")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Clear") {
                            settings.settings.chatBodyFont.family = ""
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    } else {
                        Button {
                            browseTarget = .chatBody
                        } label: {
                            Label("Pick installed font…", systemImage: "magnifyingglass")
                        }
                    }
                    Spacer()
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
                Text("/font + - reset | <pt> | family <name> works as a slash command. ⌘= / ⌘- / ⌘0 in the View menu adjust size live. Picking a custom installed font overrides the family above.")
                    .font(.caption).foregroundStyle(.tertiary)
            }

            Section("Chat body — advanced") {
                ligaturesToggle(for: $settings.settings.chatBodyFont,
                                fallback: false)
                trackingSlider(for: $settings.settings.chatBodyFont)
                lineHeightSlider(for: $settings.settings.chatBodyFont)
                weightPicker(for: $settings.settings.chatBodyFont)
                italicToggle(for: $settings.settings.chatBodyFont)
            }

            Section("Per-element overrides") {
                Text("Each slot inherits from the chat body unless you override it. Use the **Inherit** weight or leave the family blank to fall back.")
                    .font(.caption).foregroundStyle(.tertiary)
                slotEditor(title: "Nick column",
                           target: .nick,
                           binding: $settings.settings.nickFont)
                slotEditor(title: "Timestamp column",
                           target: .timestamp,
                           binding: $settings.settings.timestampFont)
                slotEditor(title: "System / info lines",
                           target: .systemLine,
                           binding: $settings.settings.systemLineFont)
            }

            Section("Zoom") {
                HStack {
                    Text("View zoom")
                    Slider(value: $settings.settings.viewZoom, in: 0.5...2.0, step: 0.05)
                    Text(verbatim: String(format: "%.2f×", settings.settings.viewZoom))
                        .frame(width: 60, alignment: .trailing)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Text("Multiplies chat font size on top of the slider above. /zoom + - reset.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .sheet(item: $browseTarget) { target in
            FontFamilyPickerSheet(monoOnly: target == .chatBody) { picked in
                applyPickedFamily(picked, to: target)
                browseTarget = nil
            } onCancel: {
                browseTarget = nil
            }
        }
    }

    // MARK: Slot editor

    @ViewBuilder
    private func slotEditor(title: String,
                            target: BrowseTarget,
                            binding: Binding<FontStyle>) -> some View {
        DisclosureGroup(title) {
            HStack {
                if !binding.wrappedValue.family.isEmpty {
                    Text(binding.wrappedValue.family)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Button("Clear") { binding.wrappedValue.family = "" }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                } else {
                    Text("(inherits chat body family)")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                Spacer()
                Button {
                    browseTarget = target
                } label: {
                    Label("Pick…", systemImage: "magnifyingglass")
                }
                .controlSize(.small)
            }
            HStack {
                Text("Size")
                Slider(
                    value: Binding(
                        get: { binding.wrappedValue.size > 0 ? binding.wrappedValue.size : 0 },
                        set: { binding.wrappedValue.size = $0 }
                    ),
                    in: 0...24, step: 1
                )
                Text(binding.wrappedValue.size > 0
                     ? "\(Int(binding.wrappedValue.size)) pt"
                     : "inherit")
                    .frame(width: 60, alignment: .trailing)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            weightPicker(for: binding)
            italicToggle(for: binding)
            ligaturesToggle(for: binding, fallback: nil)
            trackingSlider(for: binding)
            lineHeightSlider(for: binding)
        }
    }

    // MARK: Field editors

    @ViewBuilder
    private func weightPicker(for binding: Binding<FontStyle>) -> some View {
        Picker("Weight", selection: binding.weight) {
            ForEach(FontStyle.Weight.allCases, id: \.self) { w in
                Text(w.displayName).tag(w)
            }
        }
    }

    @ViewBuilder
    private func italicToggle(for binding: Binding<FontStyle>) -> some View {
        Toggle("Italic", isOn: Binding(
            get: { binding.wrappedValue.italic ?? false },
            set: { binding.wrappedValue.italic = $0 }
        ))
    }

    @ViewBuilder
    private func ligaturesToggle(for binding: Binding<FontStyle>,
                                 fallback: Bool?) -> some View {
        Toggle("Ligatures", isOn: Binding(
            get: { binding.wrappedValue.ligatures ?? (fallback ?? false) },
            set: { binding.wrappedValue.ligatures = $0 }
        ))
    }

    @ViewBuilder
    private func trackingSlider(for binding: Binding<FontStyle>) -> some View {
        HStack {
            Text("Tracking")
            Slider(
                value: Binding(
                    get: { binding.wrappedValue.tracking ?? 0 },
                    set: { binding.wrappedValue.tracking = $0 }
                ),
                in: -2...4, step: 0.1
            )
            Text(verbatim: String(format: "%+.1f", binding.wrappedValue.tracking ?? 0))
                .frame(width: 50, alignment: .trailing)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private func lineHeightSlider(for binding: Binding<FontStyle>) -> some View {
        HStack {
            Text("Line height")
            Slider(
                value: Binding(
                    get: { binding.wrappedValue.lineHeightMultiple ?? 1.0 },
                    set: { binding.wrappedValue.lineHeightMultiple = $0 }
                ),
                in: 0.8...2.0, step: 0.05
            )
            Text(verbatim: String(format: "%.2f×", binding.wrappedValue.lineHeightMultiple ?? 1.0))
                .frame(width: 60, alignment: .trailing)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    // MARK: Picker callback

    private func applyPickedFamily(_ family: String, to target: BrowseTarget) {
        switch target {
        case .chatBody:    settings.settings.chatBodyFont.family = family
        case .nick:        settings.settings.nickFont.family = family
        case .timestamp:   settings.settings.timestampFont.family = family
        case .systemLine:  settings.settings.systemLineFont.family = family
        }
    }
}

/// Searchable installed-font picker. Lists every family
/// `NSFontManager.shared.availableFontFamilies` returns. The chat-body
/// picker can be filtered to monospaced fonts via the `monoOnly` flag
/// (the chat body really wants a fixed-pitch font; nick / timestamp
/// might not).
struct FontFamilyPickerSheet: View {
    let monoOnly: Bool
    let onPick: (String) -> Void
    let onCancel: () -> Void
    @State private var query: String = ""
    @State private var monoFilter: Bool

    init(monoOnly: Bool, onPick: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.monoOnly = monoOnly
        self.onPick = onPick
        self.onCancel = onCancel
        self._monoFilter = State(initialValue: monoOnly)
    }

    private var families: [String] {
        let source = monoFilter
            ? InstalledFonts.monospacedFamilyNames
            : InstalledFonts.allFamilyNames
        guard !query.isEmpty else { return source }
        let q = query.lowercased()
        return source.filter { $0.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Pick a font")
                    .font(.title3.weight(.semibold))
                Spacer()
                Toggle("Monospaced only", isOn: $monoFilter)
                    .toggleStyle(.checkbox)
            }
            .padding()
            Divider()
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search families", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            Divider()
            List(families, id: \.self) { name in
                HStack {
                    Text(name)
                        .font(.custom(name, size: 13))
                    Spacer()
                    Text("AaBb 123")
                        .font(.custom(name, size: 13))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture { onPick(name) }
            }
            .listStyle(.inset)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(minWidth: 480, minHeight: 480)
    }
}

// MARK: - Sounds

/// Per-event sound chooser, promoted from a Section to its own tab.
struct SoundsSetup: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section("Master") {
                Toggle("Enable event sounds", isOn: $settings.settings.soundsEnabled)
                Text("Master switch. Per-event sound choices below are saved either way.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Section("Per-event") {
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

// MARK: - Assistant

/// Local-LLM assistant configuration. Wraps the existing
/// AssistantSetupSection so the work that already lives there doesn't
/// get reimplemented.
struct AssistantSetup: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                AssistantSetupSection(settings: settings)
            }
            .padding()
        }
    }
}

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

// MARK: - Backup

/// Lifts BackupSettingsRow + FactoryResetRow into their own tab so the
/// "I want to safeguard / reset my data" task is one click from Setup
/// instead of buried under Behavior.
struct BackupSetup: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section("Backups") {
                BackupSettingsRow(settings: settings)
            }
            Section("Factory reset") {
                FactoryResetRow()
                Text("Use the destructive `/nuke` slash command (or PurpleIRC menu → Reset Everything…) when you're sure: it wipes every file PurpleIRC has on disk plus every Keychain item, then quits.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Attachment row

/// One row in the AddressEntryEditor's "Attachments" section. Shows
/// the file icon (resolved from the MIME type via UTType), filename,
/// and a human-readable size, plus three affordances: Open (hand
/// off to the OS via NSWorkspace), Reveal (in Finder), Remove
/// (drops both the inline ref and the blob-store payload).
struct AttachmentRow: View {
    let ref: BlobStore.AttachmentRef
    let onOpen: () -> Void
    let onReveal: () -> Void
    let onRemove: () -> Void

    private var iconName: String {
        // Map common MIME prefixes to SF Symbols. Anything not on
        // this list falls through to a generic doc icon — keeps the
        // visual cue useful without exhaustive enumeration.
        let mime = ref.contentType.lowercased()
        if mime.hasPrefix("image/")             { return "photo" }
        if mime.hasPrefix("video/")             { return "film" }
        if mime.hasPrefix("audio/")             { return "music.note" }
        if mime.hasPrefix("text/")              { return "doc.text" }
        if mime.contains("pdf")                 { return "doc.richtext" }
        if mime.contains("zip") || mime.contains("compressed") { return "archivebox" }
        if mime.contains("json") || mime.contains("xml") { return "curlybraces" }
        return "doc"
    }

    private var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(ref.sizeBytes),
                                  countStyle: .file)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(ref.filename)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(ref.contentType) • \(formattedSize)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                onOpen()
            } label: {
                Image(systemName: "arrow.up.right.square")
            }
            .help("Open with default app")
            .buttonStyle(.borderless)
            Button {
                onReveal()
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .help("Reveal in Finder")
            .buttonStyle(.borderless)
            Button(role: .destructive) {
                onRemove()
            } label: {
                Image(systemName: "trash")
            }
            .help("Remove attachment (deletes blob)")
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Contact tags

/// Inline chip row used in two places: read-only mini chips on the
/// address-book sidebar rows, and removable chips inside the editor.
/// Resolved against the live `allTags` array each render so renames /
/// deletions propagate without any cache.
struct ContactTagChipRow: View {
    let tagIDs: [UUID]
    let allTags: [ContactTag]
    /// True for the sidebar mini-chip mode — small, no remove button.
    var compact: Bool = false
    var onRemove: ((UUID) -> Void)? = nil

    var body: some View {
        let resolved = tagIDs.compactMap { id in allTags.first(where: { $0.id == id }) }
        // Wrapping flow layout via VStack-of-HStacks so chips wrap to a
        // second line when the editor is narrow. SwiftUI gained a real
        // FlowLayout in macOS 14, but this stays widely compatible.
        FlowChips(items: resolved, compact: compact, onRemove: onRemove)
    }
}

/// Tiny flow-layout for chip rows. macOS 13's `Layout` would be cleaner,
/// but a hand-rolled version keeps the deployment target flexible and
/// is small enough to justify the duplication.
private struct FlowChips: View {
    let items: [ContactTag]
    let compact: Bool
    let onRemove: ((UUID) -> Void)?

    var body: some View {
        // Use ViewThatFits/HStack? Falling back to a simple HStack with
        // wrapping via the iOS-style "tags" pattern: layout via
        // GeometryReader + offsets. For our small counts (typically <10)
        // a single horizontal scroll is fine and avoids layout math.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(items) { tag in
                    ContactTagChip(tag: tag, compact: compact, onRemove: onRemove)
                }
            }
            .padding(.vertical, 1)
        }
    }
}

struct ContactTagChip: View {
    let tag: ContactTag
    var compact: Bool = false
    var onRemove: ((UUID) -> Void)? = nil

    /// Resolved chip color — the user's custom hex when set, otherwise
    /// the default purple. Falls back to purple if the hex is unparseable
    /// so a corrupt settings.json field never blanks the chip out.
    private var color: Color {
        guard let hex = tag.colorHex, let c = Color(hex: hex) else { return .purple }
        return c
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "tag.fill")
                .font(compact ? .system(size: 8) : .caption2)
            Text(tag.name.isEmpty ? "(unnamed)" : tag.name)
                .font(compact ? .system(size: 10) : .caption)
                .lineLimit(1)
            if let onRemove {
                Button {
                    onRemove(tag.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Remove tag from this contact (tag itself stays defined)")
            }
        }
        .padding(.horizontal, compact ? 5 : 7)
        .padding(.vertical, compact ? 2 : 3)
        .background(color.opacity(compact ? 0.12 : 0.18))
        .foregroundStyle(color)
        .clipShape(Capsule())
        .help(tag.detail.isEmpty ? tag.name : "\(tag.name) — \(tag.detail)")
    }
}

/// Popover used by the "Add tag…" button on AddressEntryEditor. Lists
/// every defined tag with a checkmark for ones already on this contact;
/// also lets the user mint a brand-new tag inline so they don't have
/// to context-switch to the manager sheet for one-off labels.
struct ContactTagAddPopover: View {
    let assigned: [UUID]
    @ObservedObject var settings: SettingsStore
    let onPick: (UUID) -> Void

    @State private var newName: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pick a tag").font(.headline)
            if settings.settings.contactTags.isEmpty {
                Text("No tags defined yet. Create one below or use **Manage tags…** at the top of the Address Book tab.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(sortedTags) { tag in
                            Button {
                                onPick(tag.id)
                                dismiss()
                            } label: {
                                HStack {
                                    Image(systemName: assigned.contains(tag.id)
                                          ? "checkmark.circle.fill"
                                          : "circle")
                                        .foregroundStyle(assigned.contains(tag.id)
                                                         ? Color.purple
                                                         : .secondary)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(tag.name.isEmpty ? "(unnamed)" : tag.name)
                                        if !tag.detail.isEmpty {
                                            Text(tag.detail)
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                                .lineLimit(2)
                                        }
                                    }
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                                .padding(.vertical, 3)
                                .padding(.horizontal, 4)
                            }
                            .buttonStyle(.plain)
                            .disabled(assigned.contains(tag.id))
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
            Divider()
            HStack {
                TextField("New tag name", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { createAndPick() }
                Button("Create") { createAndPick() }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
        .frame(width: 280)
    }

    private var sortedTags: [ContactTag] {
        settings.settings.contactTags.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func createAndPick() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        // If a tag with this name already exists (case-insensitive),
        // pick that one rather than minting a duplicate. Matches the
        // "no duplicates" rule enforced elsewhere and avoids the
        // accidental "I typed Friend twice" footgun.
        if let existing = settings.settings.contactTags.first(where: {
            $0.name.trimmingCharacters(in: .whitespaces).lowercased() == trimmed.lowercased()
        }) {
            onPick(existing.id)
            newName = ""
            dismiss()
            return
        }
        let hex = ContactTag.nextDefaultColorHex(
            existing: settings.settings.contactTags)
        let tag = ContactTag(name: trimmed, colorHex: hex)
        settings.upsertTag(tag)
        onPick(tag.id)
        newName = ""
        dismiss()
    }
}

/// Manage-tags sheet. Master/detail layout: list of tags on the left,
/// edit pane on the right. Delete cascades through `SettingsStore.deleteTag`
/// (strips the id from every contact's `tagIDs`).
struct ContactTagManagerView: View {
    @ObservedObject var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    /// Set so cmd-click / shift-click can multi-select. Editor only
    /// renders when exactly one tag is selected.
    @State private var selection: Set<UUID> = []
    /// IDs queued for the multi-delete confirmation. Tag deletes always
    /// confirm (they cascade across every contact, so a misclick is
    /// expensive), regardless of whether one or many are selected.
    @State private var confirmDeleteIDs: [UUID] = []
    /// Live ColorPicker state for the selected tag. Held separately
    /// from `tag.colorHex` because Color↔hex round-trips through a
    /// Binding(get:set:) drift and lose user picks (same lesson as
    /// HighlightRuleEditor).
    @State private var pickerColor: Color = .purple

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "tag")
                    .foregroundStyle(Color.purple)
                Text("Manage contact tags").font(.title3.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
            Divider()
            HStack(spacing: 0) {
                listPane
                Divider()
                editorPane
            }
        }
        .frame(minWidth: 620, minHeight: 380)
        .confirmationDialog(
            confirmDeleteIDs.count == 1
                ? "Delete \"\(confirmDeleteTags.first?.name ?? "")\"?"
                : "Delete \(confirmDeleteIDs.count) tags?",
            isPresented: Binding(
                get: { !confirmDeleteIDs.isEmpty },
                set: { if !$0 { confirmDeleteIDs = [] } }),
            titleVisibility: .visible
        ) {
            Button("Delete from every contact", role: .destructive) {
                performDelete(ids: confirmDeleteIDs)
                confirmDeleteIDs = []
            }
            Button("Cancel", role: .cancel) {
                confirmDeleteIDs = []
            }
        } message: {
            Text(confirmDeleteIDs.count == 1
                 ? "Removes the tag definition and strips it from every contact that currently has it. The contacts themselves stay; only the tag goes away."
                 : "Removes \(confirmDeleteIDs.count) tag definitions and strips each from every contact that currently has them. The contacts themselves stay; only the tags go away.")
        }
    }

    private var confirmDeleteTags: [ContactTag] {
        confirmDeleteIDs.compactMap { id in
            settings.settings.contactTags.first(where: { $0.id == id })
        }
    }

    /// Bulk delete with the same selection-before-mutation discipline
    /// the address-book pane uses. Picks a surviving neighbour for the
    /// new selection so the editor pane lands somewhere useful instead
    /// of dropping back to the empty placeholder.
    private func performDelete(ids: [UUID]) {
        let removeSet = Set(ids)
        let remaining = settings.settings.contactTags.filter { !removeSet.contains($0.id) }
        selection = Set(remaining.first.map { [$0.id] } ?? [])
        for id in ids {
            settings.deleteTag(id: id)
        }
    }

    private var listPane: some View {
        VStack(spacing: 0) {
            if settings.settings.contactTags.isEmpty {
                ContentUnavailableView(
                    "No tags yet",
                    systemImage: "tag",
                    description: Text("Click + to add your first tag, then assign it to contacts from the Address Book editor.")
                )
                .padding(20)
            } else {
                List(selection: $selection) {
                    ForEach(sortedTags) { tag in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tag.name.isEmpty ? "(unnamed)" : tag.name)
                                .font(.body)
                            HStack(spacing: 6) {
                                Text("\(usageCount(of: tag.id)) contact\(usageCount(of: tag.id) == 1 ? "" : "s")")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                if !tag.detail.isEmpty {
                                    Text("•")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                    Text(tag.detail)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .tag(tag.id)
                    }
                }
            }
            Divider()
            HStack {
                Button {
                    let hex = ContactTag.nextDefaultColorHex(
                        existing: settings.settings.contactTags)
                    let name = ContactTag.nextDefaultName(
                        existing: settings.settings.contactTags)
                    let tag = ContactTag(name: name, colorHex: hex)
                    settings.upsertTag(tag)
                    selection = [tag.id]
                } label: { Image(systemName: "plus") }
                Button {
                    let ids = Array(selection)
                    guard !ids.isEmpty else { return }
                    confirmDeleteIDs = ids
                } label: { Image(systemName: "minus") }
                    .disabled(selection.isEmpty)
                    .help(selection.count > 1
                          ? "Delete the \(selection.count) selected tags from every contact"
                          : "Delete the selected tag from every contact")
                Spacer()
                if selection.count > 1 {
                    Text("\(selection.count) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(6)
        }
        .frame(minWidth: 220, idealWidth: 240, maxWidth: 280)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var editorPane: some View {
        // Look up by id every time. Captured indices crash when the
        // array shrinks underneath a pending TextField binding (which
        // is what we hit in 1.0.108's first cut on delete). Only
        // renders for single-selection — multi-selection is a delete
        // staging area, not an editing context.
        if selection.count == 1,
           let id = selection.first,
           settings.settings.contactTags.contains(where: { $0.id == id }) {
            Form {
                Section("Tag") {
                    TextField("Name", text: nameBinding(for: id))
                        .textFieldStyle(.roundedBorder)
                    if ContactTag.nameClashes(
                        currentTag(for: id)?.name ?? "",
                        in: settings.settings.contactTags,
                        excluding: id
                    ) {
                        Label("Another tag already uses this name.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Section("Color") {
                    Toggle("Custom color", isOn: customColorBinding(for: id))
                    if currentTag(for: id)?.colorHex != nil {
                        HStack {
                            ColorPicker("Chip color", selection: $pickerColor, supportsOpacity: false)
                                .onChange(of: pickerColor) { _, new in
                                    // Only persist while the toggle is
                                    // on. Without the guard, toggling off
                                    // and back on would overwrite the
                                    // saved color with the picker default.
                                    if let i = indexFor(id),
                                       settings.settings.contactTags[i].colorHex != nil {
                                        settings.settings.contactTags[i].colorHex = new.hexRGB
                                    }
                                }
                            ContactTagChip(tag: currentTag(for: id) ?? .init(name: "preview"))
                        }
                    } else {
                        Text("Default purple. Toggle **Custom color** above to pick your own.")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
                Section("Description (optional)") {
                    TextEditor(text: detailBinding(for: id))
                    .frame(minHeight: 90)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                    )
                    Text("Shown as a tooltip on the chip and next to the name in this manager. Plain text only.")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                Section("Usage") {
                    let users = contactsUsingTag(id: id)
                    if users.isEmpty {
                        Text("No contacts have this tag yet.")
                            .font(.caption).foregroundStyle(.tertiary)
                    } else {
                        ForEach(users) { c in
                            Text(c.nick.isEmpty ? "(unnamed)" : c.nick)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .onAppear { syncPickerColor(id: id) }
            .onChange(of: selection) { _, new in
                if new.count == 1, let only = new.first {
                    syncPickerColor(id: only)
                }
            }
        } else if selection.count > 1 {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "tag.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                Text("\(selection.count) tags selected")
                    .font(.headline)
                Text("Click − to delete them all from every contact, or pick a single tag to edit.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack {
                Spacer()
                Text("Select a tag, or click + to add one.")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Safe id-based binding helpers
    //
    // Looking the index up inside the binding's get/set closures (rather
    // than capturing it once) means deleting a tag underneath an active
    // TextField is safe — the closures simply find no row and become
    // no-ops instead of indexing an array out of bounds.

    private func indexFor(_ id: UUID) -> Int? {
        settings.settings.contactTags.firstIndex(where: { $0.id == id })
    }

    private func currentTag(for id: UUID) -> ContactTag? {
        settings.settings.contactTags.first(where: { $0.id == id })
    }

    private func nameBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { currentTag(for: id)?.name ?? "" },
            set: { newValue in
                if let i = indexFor(id) {
                    settings.settings.contactTags[i].name = newValue
                }
            }
        )
    }

    private func detailBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { currentTag(for: id)?.detail ?? "" },
            set: { newValue in
                if let i = indexFor(id) {
                    settings.settings.contactTags[i].detail = newValue
                }
            }
        )
    }

    private func customColorBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { currentTag(for: id)?.colorHex != nil },
            set: { enabled in
                guard let i = indexFor(id) else { return }
                if enabled {
                    let hex = settings.settings.contactTags[i].colorHex ?? "#7E57C2"
                    settings.settings.contactTags[i].colorHex = hex
                    pickerColor = Color(hex: hex) ?? .purple
                } else {
                    settings.settings.contactTags[i].colorHex = nil
                }
            }
        )
    }

    private func syncPickerColor(id: UUID) {
        let hex = currentTag(for: id)?.colorHex
        pickerColor = (hex.flatMap { Color(hex: $0) }) ?? .purple
    }

    private var sortedTags: [ContactTag] {
        settings.settings.contactTags.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func usageCount(of id: UUID) -> Int {
        settings.settings.addressBook.reduce(0) { $0 + ($1.tagIDs.contains(id) ? 1 : 0) }
    }

    private func contactsUsingTag(id: UUID) -> [AddressEntry] {
        settings.settings.addressBook.filter { $0.tagIDs.contains(id) }
    }
}

// MARK: - Contact match result

/// Cross-network seen-store + log-store hits for an address-book contact's
/// nick. Computed in `AddressEntryEditor.loadMatches()` and rendered by
/// `ContactMatchesSection`.
struct ContactMatchResult: Equatable {
    var seen: [SeenHit] = []
    var logs: [LogHit] = []

    struct SeenHit: Identifiable, Equatable {
        var id: String { "\(connection.id.uuidString):\(seen.id)" }
        /// IRCConnection so the matches view can route the user to the
        /// right /seen sheet. Equatable comparisons only care about ids.
        var connection: IRCConnection
        var networkName: String
        var seen: SeenEntry
        var isExact: Bool

        static func == (lhs: SeenHit, rhs: SeenHit) -> Bool {
            lhs.connection.id == rhs.connection.id
            && lhs.networkName == rhs.networkName
            && lhs.seen == rhs.seen
            && lhs.isExact == rhs.isExact
        }
    }

    struct LogHit: Identifiable, Equatable, Hashable {
        var id: String { "\(network)::\(buffer)" }
        var network: String
        var buffer: String
        var isExact: Bool
    }

    /// Match check used by both seen and log lookups: exact (case-insensitive)
    /// or fuzzy (substring contains, case-insensitive). Empty needles never
    /// match — caller short-circuits on those anyway.
    static func matches(needle: String, candidate: String) -> Bool {
        let n = needle.lowercased()
        guard !n.isEmpty else { return false }
        let c = candidate.lowercased()
        if c == n { return true }
        if c.contains(n) { return true }
        if n.contains(c) && c.count >= 3 { return true }
        return false
    }
}

/// Render seen + log matches inside the AddressEntryEditor. Empty matches
/// surface a friendly "no hits" message so the user knows the search ran.
struct ContactMatchesSection: View {
    let nick: String
    let matches: ContactMatchResult
    let onOpenSeenList: (IRCConnection) -> Void
    let onOpenChatLogs: () -> Void
    let onOpenQuery: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                Text("\(matches.seen.count) seen-bot match\(matches.seen.count == 1 ? "" : "es") • \(matches.logs.count) log file\(matches.logs.count == 1 ? "" : "s")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            if nick.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("Set a nickname above to see matches in the seen log and chat logs.")
                    .font(.caption).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if matches.seen.isEmpty && matches.logs.isEmpty {
                Text("No exact or fuzzy matches in any connected network's seen log or in the chat-log archive.")
                    .font(.caption).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !matches.seen.isEmpty {
                Text("Seen-bot matches")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                ForEach(matches.seen) { hit in
                    HStack(spacing: 8) {
                        Image(systemName: hit.isExact ? "person.fill.checkmark" : "person.fill.questionmark")
                            .foregroundStyle(hit.isExact ? Color.purple : .secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(hit.seen.nick)
                                    .font(.system(.body, design: .monospaced))
                                Text("on \(hit.networkName)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                if !hit.isExact {
                                    Text("(fuzzy)")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            HStack(spacing: 6) {
                                Text(Self.relativeDate(hit.seen.timestamp))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                if let ch = hit.seen.channel, !ch.isEmpty {
                                    Text("• \(ch)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Text("• \(hit.seen.kind)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button {
                            onOpenSeenList(hit.connection)
                        } label: {
                            Image(systemName: "list.bullet.rectangle")
                        }
                        .help("Open the seen log for \(hit.networkName)")
                        .buttonStyle(.borderless)
                        Button {
                            onOpenQuery(hit.seen.nick)
                        } label: {
                            Image(systemName: "bubble.left.and.bubble.right")
                        }
                        .help("Open a /query buffer with \(hit.seen.nick)")
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 2)
                }
            }
            if !matches.logs.isEmpty {
                Divider().padding(.vertical, 2)
                Text("Chat-log matches")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                ForEach(matches.logs) { hit in
                    HStack(spacing: 8) {
                        Image(systemName: hit.isExact ? "doc.text.fill" : "doc.text")
                            .foregroundStyle(hit.isExact ? Color.purple : .secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(hit.buffer)
                                    .font(.system(.body, design: .monospaced))
                                Text("on \(hit.network)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                if !hit.isExact {
                                    Text("(fuzzy)")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        Spacer()
                        Button {
                            onOpenChatLogs()
                        } label: {
                            Image(systemName: "tray.full")
                        }
                        .help("Open the chat-log viewer (pick \(hit.buffer) from the list)")
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private static func relativeDate(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}

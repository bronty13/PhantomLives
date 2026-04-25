import SwiftUI

/// Root view — gates the real UI behind the KeyStore's unlock state when the
/// user has opted in to encryption. `.notSetup` (no encryption) and
/// `.unlocked` drop straight through to `ContentView`. `.locked` shows a
/// modal unlock prompt over a dimmed placeholder.
struct RootView: View {
    @EnvironmentObject var model: ChatModel
    @State private var showUnlockSheet: Bool = false
    @State private var biometricPending: Bool = false

    /// `effectivelyLocked` is true whenever the UI should be gated: either
    /// the keystore itself is locked, or biometrics are required and haven't
    /// resolved yet this session.
    private var effectivelyLocked: Bool {
        model.keyStore.state == .locked || biometricPending
    }

    var body: some View {
        ZStack {
            ContentView()
                .disabled(effectivelyLocked)
                .blur(radius: effectivelyLocked ? 6 : 0)
            if effectivelyLocked {
                Color.black.opacity(0.25).ignoresSafeArea()
            }
        }
        .onAppear { initialGate() }
        .onChange(of: model.keyStore.state) { _, _ in refreshUnlockSheet() }
        .sheet(isPresented: $showUnlockSheet) {
            PassphraseUnlockView(keyStore: model.keyStore) {
                // Successful unlock — reload settings so the encrypted
                // envelope's plaintext lands in memory.
                model.settings.reload()
                showUnlockSheet = false
            }
            .interactiveDismissDisabled(true)
        }
    }

    /// Called once on appear. If the user opted into biometric gate AND the
    /// keystore silently unlocked via the Keychain, prompt Touch ID before
    /// we let them through. If they fail / cancel, lock the keystore and
    /// fall back to the passphrase sheet.
    private func initialGate() {
        let biometricsRequired = model.settings.settings.requireBiometricsOnLaunch
        if biometricsRequired,
           model.keyStore.state == .unlocked,
           BiometricGate.isAvailable {
            biometricPending = true
            Task {
                let ok = await BiometricGate.verify(
                    reason: "Unlock PurpleIRC to view encrypted settings and logs."
                )
                if ok {
                    biometricPending = false
                } else {
                    // User cancelled or biometry failed — drop to passphrase.
                    model.keyStore.lock()
                    biometricPending = false
                    refreshUnlockSheet()
                }
            }
        } else {
            refreshUnlockSheet()
        }
    }

    private func refreshUnlockSheet() {
        showUnlockSheet = (model.keyStore.state == .locked)
    }
}

struct ContentView: View {
    @EnvironmentObject var model: ChatModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            VStack(spacing: 0) {
                WatchHitBanner(watchlist: model.watchlist)
                    .animation(.spring(duration: 0.25), value: model.watchlist.recentHits.first?.id)
                if let id = model.selectedBufferID,
                   let idx = model.buffers.firstIndex(where: { $0.id == id }) {
                    BufferView(bufferIndex: idx)
                } else {
                    ConnectFormView()
                        .padding(24)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                ConnectionStatusView()
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.showSetup = true
                } label: {
                    Label("Setup", systemImage: "gearshape")
                }
                .help("Servers, address book, and saved channels (⌘,)")
            }
            ToolbarItem(placement: .primaryAction) {
                IdentityMenu()
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    FilesMenu(settings: model.settings)
                } label: {
                    Label("Files", systemImage: "folder")
                }
                .help("Reveal PurpleIRC's settings, logs, scripts, and seen data in Finder")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.showWatchlist = true
                } label: {
                    Label(model.watchlist.recentHits.isEmpty ? "Watchlist" : "Watchlist (\(model.watchlist.recentHits.count))",
                          systemImage: model.watchlist.recentHits.isEmpty ? "bell.badge" : "bell.badge.fill")
                }
                .help("Alert me when watched users come online")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    openWindow(id: "watch-monitor")
                } label: {
                    Label("Watch Monitor", systemImage: "waveform.badge.magnifyingglass")
                }
                .help("Open the cross-network activity monitor (⇧⌘M)")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if model.connectionState == .connected {
                        model.activeConnection?.requestChannelList()
                    }
                    model.showChannelList = true
                } label: {
                    Label("Channels", systemImage: "list.bullet.rectangle")
                }
                .help("Browse the server's channel directory (/list)")
                .disabled(model.activeConnection == nil)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if model.connectionState == .connected {
                        model.disconnect()
                    } else {
                        model.connect()
                    }
                } label: {
                    Label(model.connectionState == .connected ? "Disconnect" : "Connect",
                          systemImage: model.connectionState == .connected ? "bolt.slash" : "bolt")
                }
            }
        }
        .sheet(isPresented: $model.showRawLog) {
            RawLogView()
        }
        .sheet(isPresented: $model.showWatchlist) {
            WatchlistView(watchlist: model.watchlist)
                .environmentObject(model)
        }
        .sheet(isPresented: $model.showSetup) {
            SetupView(settings: model.settings)
                .environmentObject(model)
        }
        .confirmationDialog("Quit PurpleIRC?",
                            isPresented: $model.showQuitConfirmation,
                            titleVisibility: .visible) {
            Button("Quit", role: .destructive) {
                model.performQuit(reason: model.pendingQuitReason)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("All connections will send a QUIT (\"\(model.pendingQuitReason)\") and the app will close. Turn off confirmation in Setup → Behavior to skip this prompt.")
        }
        .sheet(isPresented: $model.showHelp) {
            HelpView(initialQuery: model.helpPrefillQuery)
        }
        .sheet(isPresented: $model.showSeenList) {
            if let conn = model.activeConnection {
                SeenListView(
                    entries: model.botEngine.seenStore.entries(
                        networkID: conn.id,
                        networkSlug: SeenStore.slug(for: conn.displayName)),
                    onQuery: { nick in model.sendInput("/query \(nick)") },
                    onClear: {
                        model.botEngine.seenStore.clear(
                            networkID: conn.id,
                            networkSlug: SeenStore.slug(for: conn.displayName))
                        model.showSeenList = false
                    }
                )
            } else {
                VStack(spacing: 12) {
                    Text("Connect to a server first.")
                    Button("Close") { model.showSeenList = false }
                }
                .padding(32)
            }
        }
        .sheet(isPresented: $model.showChannelList) {
            if let conn = model.activeConnection {
                ChannelListView(
                    service: conn.channelList,
                    onJoin: { channel in model.quickJoin(channel) },
                    onRefresh: { filter, full in
                        conn.requestChannelList(filter: filter, forceRefresh: full)
                    }
                )
            } else {
                // No connection — unreachable in practice since the toolbar
                // button is disabled, but provide a graceful fallback.
                VStack(spacing: 12) {
                    Text("Connect to a server first.")
                    Button("Close") { model.showChannelList = false }
                }
                .padding(32)
            }
        }
        .sheet(isPresented: $model.showDCC) {
            DCCView(service: model.dcc)
                .environmentObject(model)
        }
    }
}

struct ConnectionStatusView: View {
    @EnvironmentObject var model: ChatModel
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
    private var color: Color {
        switch model.connectionState {
        case .connected: return .green
        case .connecting: return .yellow
        case .failed: return .red
        case .disconnected: return .gray
        }
    }
    private var label: String {
        switch model.connectionState {
        case .connected: return "connected as \(model.nick)"
        case .connecting: return "connecting…"
        case .failed(let err): return "failed: \(err)"
        case .disconnected: return "offline"
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject var model: ChatModel

    var body: some View {
        List(selection: Binding(
            get: { model.selectedBufferID },
            set: { if let v = $0 { model.selectBuffer(v) } }
        )) {
            let channels = model.buffers.filter { $0.kind == .channel }
            if !channels.isEmpty {
                Section("Channels") {
                    ForEach(channels) { buf in
                        BufferRow(buffer: buf, icon: "number")
                    }
                }
            }

            // Private grouping — direct queries with users plus the
            // network/server console rows. The server rows live here so the
            // sidebar reads as "channels above, anything addressed to *you*
            // below". A subtle divider + dim styling on the server rows keeps
            // them distinct from query rows above and saved/contacts below.
            let queries  = model.buffers.filter { $0.kind == .query }
            let servers  = model.buffers.filter { $0.kind == .server }
            if !queries.isEmpty || !servers.isEmpty {
                Section("Private") {
                    ForEach(queries) { buf in
                        BufferRow(buffer: buf, icon: "person.fill")
                    }
                    if !queries.isEmpty && !servers.isEmpty {
                        // Visual separator between user queries and the
                        // network console rows. Pulled in from the row edge
                        // so it reads as a divider, not a real list row.
                        Divider()
                            .padding(.horizontal, 6)
                            .listRowSeparator(.hidden)
                    }
                    ForEach(servers) { buf in
                        ServerConsoleRow(buffer: buf)
                    }
                }
            }

            let saved = savedForCurrentServer
            if !saved.isEmpty {
                Section("Saved") {
                    ForEach(saved) { ch in
                        Button {
                            model.quickJoin(ch.name)
                        } label: {
                            HStack {
                                Image(systemName: "number.square")
                                    .foregroundStyle(Color.accentColor)
                                Text(ch.name)
                                if !ch.note.isEmpty {
                                    Text("— \(ch.note)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            let addresses = model.settings.settings.addressBook
            if !addresses.isEmpty {
                Section("Contacts") {
                    ForEach(addresses) { a in
                        ContactRow(entry: a, presence: presence(for: a))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            SidebarFooterView()
        }
    }

    private var savedForCurrentServer: [SavedChannel] {
        let sid = model.settings.settings.selectedServerID
        return model.settings.settings.savedChannels.filter {
            $0.serverID == nil || $0.serverID == sid
        }
    }

    private func presence(for entry: AddressEntry) -> WatchPresence {
        guard entry.watch else { return .unknown }
        return model.watchlist.presence[entry.nick.lowercased()] ?? .unknown
    }
}

/// Server console row in the sidebar — the network-info buffer that holds
/// raw notices, MOTD, server replies, etc. Styled distinctly from channel and
/// query rows: smaller/secondary type with a subtle accent dot so it reads as
/// "this is the network itself" rather than a peer or a topic.
struct ServerConsoleRow: View {
    let buffer: Buffer
    @EnvironmentObject var model: ChatModel
    @State private var isHovering: Bool = false

    private var isSelected: Bool { model.selectedBufferID == buffer.id }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "server.rack")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(buffer.name)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if buffer.unread > 0, !isHovering {
                Text("\(buffer.unread)")
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.secondary.opacity(0.35)))
                    .foregroundStyle(.white)
            }
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .tag(buffer.id as Buffer.ID?)
        .contextMenu {
            Button("Copy network name") {
                #if canImport(AppKit)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(buffer.name, forType: .string)
                #endif
            }
            Divider()
            if isSelected {
                Button("Disconnect from this network") { model.disconnect() }
            }
        }
    }
}

/// Address-book contact row in the sidebar. Single-click selects, double-click
/// opens a `/query` buffer with the contact, and the right-click menu exposes
/// every reasonable contact action (whois/whowas, watch toggle, edit, remove).
struct ContactRow: View {
    let entry: AddressEntry
    let presence: WatchPresence

    @EnvironmentObject var model: ChatModel

    var body: some View {
        HStack {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
            Text(entry.nick)
                .font(.system(.body, design: .monospaced))
            if entry.watch {
                Image(systemName: "bell.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.purple)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            model.sendInput("/query \(entry.nick)")
        }
        .contextMenu {
            Button("Open query with \(entry.nick)") {
                model.sendInput("/query \(entry.nick)")
            }
            Button("WHOIS \(entry.nick)")  { model.sendInput("/whois \(entry.nick)") }
            Button("WHOWAS \(entry.nick)") { model.sendInput("/whowas \(entry.nick)") }
            Divider()
            if entry.watch {
                Button("Stop notifying when online") { setWatch(false) }
            } else {
                Button("Notify when online") { setWatch(true) }
            }
            Button("Edit address book entry…") {
                model.pendingSetupTab = .addressBook
                model.showSetup = true
            }
            Button("Remove from address book", role: .destructive) {
                model.settings.removeAddress(id: entry.id)
            }
            Divider()
            Button("Copy nick") {
                #if canImport(AppKit)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.nick, forType: .string)
                #endif
            }
        }
    }

    private var dotColor: Color {
        guard entry.watch else { return .gray }
        switch presence {
        case .online: return .green
        case .offline: return .gray
        case .unknown: return .yellow
        }
    }

    private func setWatch(_ on: Bool) {
        var copy = entry
        copy.watch = on
        model.settings.upsertAddress(copy)
    }
}

/// Single channel/query row in the sidebar. Owns per-row hover state so a
/// close (X) button can appear without affecting neighbors. Right-clicking
/// opens a context menu for Leave/Close + Copy name.
struct BufferRow: View {
    let buffer: Buffer
    let icon: String

    @EnvironmentObject var model: ChatModel
    @State private var isHovering: Bool = false

    private var isChannel: Bool { buffer.kind == .channel }
    private var isSelected: Bool { model.selectedBufferID == buffer.id }

    var body: some View {
        HStack(spacing: 4) {
            Label(buffer.name, systemImage: icon)
            Spacer(minLength: 4)
            if buffer.unread > 0, !isHovering {
                Text("\(buffer.unread)")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor))
                    .foregroundStyle(.white)
            }
            if isHovering || isSelected {
                Button {
                    let id = buffer.id
                    DispatchQueue.main.async { model.closeBuffer(id: id) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(isChannel ? "Leave \(buffer.name)" : "Close query with \(buffer.name)")
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            // Throttle not needed — SwiftUI coalesces hover events well enough.
            isHovering = hovering
        }
        .tag(buffer.id as Buffer.ID?)
        .contextMenu {
            if isChannel {
                channelContextMenu
            } else {
                queryContextMenu
            }
        }
    }

    // MARK: - Context menus

    /// Actions appropriate to a channel row in the sidebar.
    @ViewBuilder
    private var channelContextMenu: some View {
        Button("Leave \(buffer.name)") {
            // Defer one runloop tick so the context menu can fully dismiss
            // and SwiftUI can complete the row teardown before we mutate
            // the buffers array — without this, the active-channel "Leave"
            // crashed on a stale BufferView body re-evaluation.
            let id = buffer.id
            DispatchQueue.main.async { model.closeBuffer(id: id) }
        }
        Divider()
        Button("Copy channel name") {
            copyToClipboard(buffer.name)
        }
        Divider()
        Button("Request topic") { model.sendInput("/topic") }
            .disabled(!isSelected)
        Button("Request names") { model.sendInput("/names") }
            .disabled(!isSelected)
        Button("Request mode") { model.sendInput("/mode \(buffer.name)") }
    }

    /// Actions appropriate to a private-query (nick) row in the sidebar.
    @ViewBuilder
    private var queryContextMenu: some View {
        let nick = buffer.name
        Button("Close query with \(nick)") {
            let id = buffer.id
            DispatchQueue.main.async { model.closeBuffer(id: id) }
        }
        Divider()
        Button("WHOIS \(nick)")  { model.sendInput("/whois \(nick)") }
        Button("WHOWAS \(nick)") { model.sendInput("/whowas \(nick)") }
        Button("CTCP VERSION")   { model.sendInput("/ctcp \(nick) VERSION") }
        Button("CTCP PING")      { model.sendInput("/ctcp \(nick) PING \(Int(Date().timeIntervalSince1970))") }
        Divider()
        if isInAddressBook(nick) {
            Button("Remove from address book") { removeFromAddressBook(nick) }
        } else {
            Button("Add to address book (watch)") { addToAddressBook(nick, watch: true) }
            Button("Add to address book") { addToAddressBook(nick, watch: false) }
        }
        Divider()
        if isIgnored(nick) {
            Button("Stop ignoring \(nick)") { removeIgnore(nick) }
        } else {
            Button("Ignore \(nick)!*@*") { model.sendInput("/ignore \(nick)!*@*") }
            Button("Ignore \(nick) (nick only)") { model.sendInput("/ignore \(nick)") }
        }
        Divider()
        Button("Copy nick") { copyToClipboard(nick) }
    }

    // MARK: - Context-menu helpers

    private func copyToClipboard(_ text: String) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    private func isInAddressBook(_ nick: String) -> Bool {
        model.settings.settings.addressBook.contains {
            $0.nick.caseInsensitiveCompare(nick) == .orderedSame
        }
    }

    private func addToAddressBook(_ nick: String, watch: Bool) {
        var entry = AddressEntry()
        entry.nick = nick
        entry.watch = watch
        model.settings.upsertAddress(entry)
    }

    private func removeFromAddressBook(_ nick: String) {
        let matches = model.settings.settings.addressBook.filter {
            $0.nick.caseInsensitiveCompare(nick) == .orderedSame
        }
        for entry in matches {
            model.settings.removeAddress(id: entry.id)
        }
    }

    /// True when any ignore-list mask matches the bare nick. We match both the
    /// exact nick and common `nick!*@*` / `nick!user@host` shapes so the menu
    /// label reflects what the user set earlier, whichever form they used.
    private func isIgnored(_ nick: String) -> Bool {
        let lower = nick.lowercased()
        return model.settings.settings.ignoreList.contains { entry in
            let mask = entry.mask.lowercased()
            if mask == lower { return true }
            // Strip user@host suffix for comparison: "alice!*@*" → "alice".
            let head = mask.split(separator: "!", maxSplits: 1).first.map(String.init) ?? mask
            return head == lower
        }
    }

    private func removeIgnore(_ nick: String) {
        let lower = nick.lowercased()
        let matches = model.settings.settings.ignoreList.filter { entry in
            let mask = entry.mask.lowercased()
            if mask == lower { return true }
            let head = mask.split(separator: "!", maxSplits: 1).first.map(String.init) ?? mask
            return head == lower
        }
        for entry in matches {
            model.settings.removeIgnore(id: entry.id)
        }
    }
}

struct SidebarFooterView: View {
    @EnvironmentObject var model: ChatModel
    @State private var joinTarget: String = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            HStack {
                TextField("Join #channel", text: $joinTarget)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(join)
                Button("Join", action: join)
                    .disabled(model.connectionState != .connected || joinTarget.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(8)
    }
    private func join() {
        let t = joinTarget.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        let name = t.hasPrefix("#") ? t : "#" + t
        model.sendInput("/join \(name)")
        joinTarget = ""
    }
}

struct ConnectFormView: View {
    @EnvironmentObject var model: ChatModel

    var body: some View {
        VStack(spacing: 16) {
            if model.settings.settings.servers.isEmpty {
                ContentUnavailableView(
                    "No servers configured",
                    systemImage: "server.rack",
                    description: Text("Open Setup (⌘,) to add a server profile.")
                )
                Button("Open Setup") { model.showSetup = true }
                    .keyboardShortcut(.defaultAction)
            } else {
                Form {
                    Section("Server profile") {
                        Picker("Profile", selection: Binding(
                            get: { model.settings.settings.selectedServerID ?? model.settings.settings.servers.first!.id },
                            set: { model.settings.settings.selectedServerID = $0 }
                        )) {
                            ForEach(ServerProfile.sortedByName(model.settings.settings.servers)) { s in
                                Text(s.name).tag(s.id)
                            }
                        }
                        if let p = model.settings.selectedServer() {
                            // Resolve the identity overlay so Nickname shows
                            // what will actually be registered on the server.
                            let identity = model.settings.identity(withID: p.identityID)
                            let effective = p.applyingIdentity(identity)
                            LabeledContent("Host") { Text("\(p.host):\(p.port)") }
                            LabeledContent("TLS") { Text(p.useTLS ? "yes" : "no") }
                            LabeledContent("Nickname") { Text(effective.nick) }
                            if let identity {
                                LabeledContent("Identity") {
                                    Text(identity.name).foregroundStyle(.secondary)
                                }
                            }
                            if !p.autoJoin.isEmpty {
                                LabeledContent("Auto-join") { Text(p.autoJoin).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
                .formStyle(.grouped)
                HStack {
                    Button("Edit in Setup…") { model.showSetup = true }
                    Spacer()
                    Button("Connect") { model.connect() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.connectionState == .connecting || model.connectionState == .connected)
                }
                .padding(.horizontal)
            }
        }
        .frame(maxWidth: 520)
    }
}

// MARK: - Files menu (reveal settings / logs / scripts / seen in Finder)

/// Toolbar dropdown for swapping the active connection's identity. Rendered
/// as a single button with a menu so the current identity name is always
/// visible without a click.
struct IdentityMenu: View {
    @EnvironmentObject var model: ChatModel

    private var activeConn: IRCConnection? { model.activeConnection }
    private var currentIdentity: Identity? {
        guard let conn = activeConn else { return nil }
        return model.settings.identity(withID: conn.profile.identityID)
    }
    private var label: String {
        currentIdentity?.name ?? "Custom"
    }

    var body: some View {
        Menu {
            if let conn = activeConn {
                Button {
                    model.applyIdentity(nil, to: conn)
                } label: {
                    if conn.profile.identityID == nil {
                        Label("Custom (inline profile fields)", systemImage: "checkmark")
                    } else {
                        Text("Custom (inline profile fields)")
                    }
                }
                Divider()
                if model.settings.settings.identities.isEmpty {
                    Text("No identities defined").disabled(true)
                } else {
                    ForEach(model.settings.settings.identities) { ident in
                        Button {
                            model.applyIdentity(ident, to: conn)
                        } label: {
                            if conn.profile.identityID == ident.id {
                                Label(ident.name.isEmpty ? "(unnamed)" : ident.name,
                                      systemImage: "checkmark")
                            } else {
                                Text(ident.name.isEmpty ? "(unnamed)" : ident.name)
                            }
                        }
                    }
                }
                Divider()
                Button("Manage identities…") {
                    // Land directly on the Identities tab instead of
                    // dropping into Servers and forcing the user to click.
                    model.pendingSetupTab = .identities
                    model.showSetup = true
                }
            } else {
                Text("Connect first to pick an identity").disabled(true)
            }
        } label: {
            Label(label, systemImage: "person.crop.circle.badge.questionmark")
        }
        .help(activeConn == nil ? "Connect to a network to switch identity" : "Identity on \(activeConn!.displayName): \(label) — reconnect to apply")
        .disabled(activeConn == nil)
    }
}

/// Each menu item reveals (or opens) a specific PurpleIRC file or directory in
/// Finder. Missing directories are created on-demand so the user always lands
/// somewhere concrete instead of a "couldn't find it" error.
struct FilesMenu: View {
    let settings: SettingsStore

    private var supportDir: URL { settings.supportDirectoryURL }

    var body: some View {
        Button("Reveal settings.json") {
            Self.revealInFinder(settings.settingsFileURL)
        }
        Button("Open logs folder") {
            Self.openDirectory(settings.logsDirectoryURL)
        }
        Button("Open scripts folder") {
            Self.openDirectory(supportDir.appendingPathComponent("scripts", isDirectory: true))
        }
        Button("Open seen-data folder") {
            Self.openDirectory(supportDir.appendingPathComponent("seen", isDirectory: true))
        }
        Divider()
        Button("Open PurpleIRC support folder") {
            Self.openDirectory(supportDir)
        }
        Divider()
        Button("Copy support path") {
            #if canImport(AppKit)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(supportDir.path, forType: .string)
            #endif
        }
    }

    /// Opens Finder with the target file highlighted. For missing files we
    /// fall back to the parent directory so the user sees *something*.
    private static func revealInFinder(_ url: URL) {
        #if canImport(AppKit)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            openDirectory(url.deletingLastPathComponent())
        }
        #endif
    }

    /// Opens a directory in Finder, creating it first if it doesn't exist.
    private static func openDirectory(_ url: URL) {
        #if canImport(AppKit)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
        #endif
    }
}

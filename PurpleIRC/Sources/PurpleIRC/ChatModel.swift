import Foundation
import SwiftUI
import Combine

struct ChatLine: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let kind: Kind
    let text: String
    var isMention: Bool = false

    /// ID of the HighlightRule that tagged this line, if any. Resolved at
    /// render time to look up color / styling; nil = no rule matched.
    var highlightRuleID: UUID? = nil

    /// Character-level match ranges in the post-format (code-stripped) text.
    /// Used by MessageRow to tint matched words after IRCFormatter.render.
    var highlightRanges: [NSRange] = []

    enum Kind: Equatable {
        case info
        case error
        case motd
        case privmsg(nick: String, isSelf: Bool)
        case action(nick: String)
        case notice(from: String)
        case join(nick: String)
        case part(nick: String, reason: String?)
        case quit(nick: String, reason: String?)
        case nick(old: String, new: String)
        case topic(setter: String?)
        case raw
    }
}

struct Buffer: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var kind: Kind
    var lines: [ChatLine] = []
    var users: [String] = []
    /// Lowercased nick → set of IRC user-mode letters (q, a, o, h, v) that
    /// have been granted to that user on this channel. Populated from
    /// RPL_NAMREPLY (353) and kept in sync by MODE handlers. Channels only;
    /// queries and the server buffer leave this empty.
    var userModes: [String: Set<Character>] = [:]
    var topic: String = ""
    var unread: Int = 0

    enum Kind: Equatable {
        case server
        case channel
        case query
    }

    var isChannel: Bool { kind == .channel }
    var displayName: String { name }
}

// MARK: - Channel user modes

extension Buffer {
    /// Privilege ranking for display / sort order. Higher wins.
    static let modeRank: [Character: Int] = [
        "q": 5, "a": 4, "o": 3, "h": 2, "v": 1
    ]
    /// IRC-standard display glyph per user-mode letter (owner, admin, op,
    /// halfop, voice). Used as the "symbol" column in the user list.
    static let modeSymbol: [Character: Character] = [
        "q": "~", "a": "&", "o": "@", "h": "%", "v": "+"
    ]
    /// Reverse lookup used when parsing RPL_NAMREPLY prefix characters.
    static func modeLetter(fromSymbol s: Character) -> Character? {
        switch s {
        case "~": return "q"
        case "&": return "a"
        case "@": return "o"
        case "%": return "h"
        case "+": return "v"
        default:  return nil
        }
    }
    /// Highest-rank mode letter currently set on `nick` in this channel, or
    /// nil for a plain user. Callers use this for both display symbol and
    /// row colour.
    func highestMode(for nick: String) -> Character? {
        let modes = userModes[nick.lowercased()] ?? []
        return modes.max { (Self.modeRank[$0] ?? 0) < (Self.modeRank[$1] ?? 0) }
    }
    /// Users sorted by privilege descending, then alphabetical. Matches the
    /// grouping most IRC clients show (ops cluster at the top).
    var usersSortedByRank: [String] {
        users.sorted { a, b in
            let ra = highestMode(for: a).flatMap { Self.modeRank[$0] } ?? 0
            let rb = highestMode(for: b).flatMap { Self.modeRank[$0] } ?? 0
            if ra != rb { return ra > rb }
            return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }
    }
}

extension Buffer {
    mutating func appendLine(_ l: ChatLine) {
        lines.append(l)
        if lines.count > 5000 {
            lines.removeFirst(lines.count - 5000)
        }
    }

    mutating func appendInfo(_ text: String) {
        appendLine(ChatLine(timestamp: Date(), kind: .info, text: text))
    }

    mutating func appendError(_ text: String) {
        appendLine(ChatLine(timestamp: Date(), kind: .error, text: text))
    }
}

/// Top-level app model. Now a thin orchestrator over `[IRCConnection]` — each
/// IRC network is its own `IRCConnection` with its own buffers, rawLog, state,
/// and event subject. ChatModel keeps the shared WatchlistService, holds the
/// settings store, tracks which connection is active for the UI, and forwards
/// the handful of "do this on the current connection" calls the views issue.
///
/// The PurpleBot scripting host will later subscribe to `events` here (a merged
/// stream of all connections' events) without needing to touch core dispatch.
@MainActor
final class ChatModel: ObservableObject {
    @Published var connections: [IRCConnection] = []
    @Published var activeConnectionID: UUID?

    @Published var showRawLog: Bool = false
    @Published var showWatchlist: Bool = false
    @Published var showSetup: Bool = false
    @Published var showChannelList: Bool = false
    @Published var showSeenList: Bool = false
    @Published var showHelp: Bool = false
    @Published var showDCC: Bool = false
    /// Prefilled search text when /help is invoked with an argument.
    var helpPrefillQuery: String = ""

    /// Surfaced when the user types /quit or /exit AND has the confirmation
    /// toggle enabled. When they confirm, `performQuit` fires.
    @Published var showQuitConfirmation: Bool = false
    /// Reason text carried into the server QUIT line; captured when the
    /// confirmation flips on, applied when the user confirms.
    var pendingQuitReason: String = ""

    /// Single shared watchlist across all connections. See IRCConnection doc
    /// on why this is shared rather than per-connection.
    let watchlist = WatchlistService()
    let settings = SettingsStore()

    /// Shared log writer. Off-main-actor; every connection writes through this
    /// when `enablePersistentLogs` is on.
    let logStore: LogStore

    /// Merged event stream across all connections. PurpleBot subscribes here.
    let events = PassthroughSubject<(UUID, IRCConnectionEvent), Never>()

    /// In-app scripting host (PurpleBot). See BotHost.swift.
    let bot: BotHost

    /// Native trigger + seen-bot engine. Subscribes to `events` to do its
    /// work; `/seen` looks up through this.
    let botEngine: BotEngine

    /// Passphrase-backed keystore for envelope encryption of settings + logs.
    /// See KeyStore.swift — this is the composite-key machine.
    let keyStore: KeyStore

    /// DCC file transfers + direct chats. See DCC.swift.
    let dcc: DCCService

    private var cancellables = Set<AnyCancellable>()
    /// Per-connection cancellables, keyed by connection id, so removing a
    /// connection can drop its subscriptions cleanly.
    private var connectionCancellables: [UUID: [AnyCancellable]] = [:]

    var activeConnection: IRCConnection? {
        guard let id = activeConnectionID else { return connections.first }
        return connections.first(where: { $0.id == id })
    }

    init() {
        self.logStore = LogStore(baseURL: settings.logsDirectoryURL)
        self.bot = BotHost(supportDir: settings.supportDirectoryURL)
        let seen = SeenStore(supportDirectoryURL: settings.supportDirectoryURL)
        self.botEngine = BotEngine(seenStore: seen)
        self.keyStore = KeyStore(supportDirectoryURL: settings.supportDirectoryURL)
        let downloads = settings.supportDirectoryURL.appendingPathComponent("downloads", isDirectory: true)
        self.dcc = DCCService(downloadsDir: downloads)
        // Link keystore to settings so save/load knows whether to wrap the
        // envelope. If the keystore is already unlocked via the Keychain
        // cache (silent path), reload settings immediately so an encrypted
        // envelope decrypts before the UI renders.
        self.settings.keyStore = self.keyStore
        if self.keyStore.isUnlocked {
            self.settings.reload()
        }
        // Push the current DEK into the LogStore so new lines get sealed
        // and existing encrypted logs remain readable.
        self.pushKeyToLogStore()
        watchlist.setDelegate(self)
        seedFromSelectedProfile()
        applySettingsToAll()
        bot.attach(self)
        botEngine.attach(to: self)
        dcc.chatModel = self
        // Age-based log purge runs once at launch when the user has it on.
        runLogPurgeIfEnabled()
        // Fan out bot-visible events to the sound player.
        events
            .sink { [weak self] tuple in
                Task { @MainActor in self?.playSoundFor(event: tuple.1) }
            }
            .store(in: &cancellables)
        // React to KeyStore state flips (lock / unlock / setup / reset):
        // reload the settings envelope and refresh LogStore's DEK so writes
        // and reads stay in sync with the current encryption state.
        keyStore.$state
            .sink { [weak self] _ in
                guard let self else { return }
                self.settings.reload()
                self.pushKeyToLogStore()
            }
            .store(in: &cancellables)

        // Forward nested SettingsStore changes so any view observing ChatModel
        // (via @EnvironmentObject) re-renders when settings mutate. Without
        // this, the Picker in ConnectFormView silently snaps back because
        // SwiftUI never hears that the selection actually changed.
        settings.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
                // Rule edits invalidate compiled regex in the trigger/highlight
                // engines. Cheap to clear; next evaluation recompiles.
                self?.botEngine.clearRegexCache()
            }
            .store(in: &cancellables)
        settings.$settings
            .sink { [weak self] _ in
                Task { @MainActor in self?.onSettingsChanged() }
            }
            .store(in: &cancellables)
    }

    // MARK: - Connection management

    private func seedFromSelectedProfile() {
        guard let profile = settings.selectedServer() else { return }
        let conn = addConnection(for: profile)
        activeConnectionID = conn.id
    }

    @discardableResult
    private func addConnection(for profile: ServerProfile) -> IRCConnection {
        let conn = IRCConnection(profile: profile, watchlist: watchlist)
        let cacheDir = settings.supportDirectoryURL.appendingPathComponent("channels", isDirectory: true)
        conn.bindChannelCache(baseDir: cacheDir)
        // Wire the new connection's channel cache into the active DEK so
        // its writes match every other persistence path.
        conn.channelList.setEncryptionKey(keyStore.currentKey)
        connections.append(conn)
        var bag: [AnyCancellable] = []
        conn.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &bag)
        conn.events
            .sink { [weak self] tuple in self?.events.send(tuple) }
            .store(in: &bag)
        connectionCancellables[conn.id] = bag
        return conn
    }

    /// Make sure there's a connection for the currently-selected profile.
    /// Existing connection for that profile wins; otherwise a new one is
    /// appended and made active.
    func ensureConnectionForSelectedProfile() {
        guard let profile = settings.selectedServer() else { return }
        if let existing = connections.first(where: { $0.profile.id == profile.id }) {
            activeConnectionID = existing.id
            return
        }
        let conn = addConnection(for: profile)
        activeConnectionID = conn.id
        applySettingsToAll()
    }

    /// Remove a connection (and its cancellables). If it was the active one,
    /// the first remaining connection becomes active.
    func removeConnection(id: UUID) {
        guard let idx = connections.firstIndex(where: { $0.id == id }) else { return }
        let conn = connections[idx]
        conn.disconnect()
        connections.remove(at: idx)
        connectionCancellables.removeValue(forKey: id)
        if activeConnectionID == id {
            activeConnectionID = connections.first?.id
        }
    }

    func selectConnection(id: UUID) {
        activeConnectionID = id
    }

    // MARK: - Settings sync

    private func onSettingsChanged() {
        // If the selected server in settings changed, make that the active
        // connection (creating one if needed).
        if let selID = settings.settings.selectedServerID,
           !connections.contains(where: { $0.id == activeConnectionID && $0.profile.id == selID }) {
            if let existing = connections.first(where: { $0.profile.id == selID }) {
                activeConnectionID = existing.id
            }
        }
        applySettingsToAll()
    }

    /// Selected theme — read by MessageRow at render time.
    var theme: Theme { Theme.named(settings.settings.themeID) }

    private func playSoundFor(event: IRCConnectionEvent) {
        let s = settings.settings
        switch event {
        case .state(.connected):
            SoundPlayer.play(.connect, settings: s)
        case .state(.disconnected), .state(.failed):
            SoundPlayer.play(.disconnect, settings: s)
        case .ctcpRequest:
            SoundPlayer.play(.ctcp, settings: s)
        case .privmsg(_, let target, _, _, let isMention):
            // Private query (target is our own nick) OR a mention — give them
            // different sounds. Private takes precedence if both apply.
            let isPrivate = !target.hasPrefix("#") && !target.hasPrefix("&")
            if isPrivate {
                SoundPlayer.play(.privateMessage, settings: s)
            } else if isMention {
                SoundPlayer.play(.mention, settings: s)
            }
        default:
            break
        }
    }

    private func applySettingsToAll() {
        watchlist.setWatchedList(settings.watchedFromAddressBook)
        let s = settings.settings
        for c in connections {
            c.applyAlertOptions(
                sound: s.playSoundOnWatchHit,
                dock: s.bounceDockOnWatchHit,
                banner: s.systemNotificationsOnWatchHit,
                highlight: s.highlightOnOwnNick
            )
            // Tier 2: logging, ignore list, CTCP, away auto-reply.
            c.logStore = logStore
            c.loggingEnabled = s.enablePersistentLogs
            c.logNoisyLines = s.logMotdAndNumerics
            c.ignoreMatchers = s.ignoreList
            c.ctcpRepliesEnabled = s.ctcpRepliesEnabled
            c.ctcpVersionString = s.ctcpVersionString
            c.autoReplyWhenAway = s.autoReplyWhenAway
            c.awayAutoReply = s.awayAutoReply
            c.highlightRules = s.highlightRules
            c.highlightSoundName = s.eventSounds["highlight"] ?? "Funk"
            // Resolve identity per connection, if any. Takes effect on the
            // next connect (SASL/NICK/USER are registration-time fields).
            c.activeIdentity = settings.identity(withID: c.profile.identityID)
            c.dcc = dcc
        }
        dcc.externalIPOverride = s.dccExternalIP
        dcc.portRangeStart = s.dccPortRangeStart
        dcc.portRangeEnd = s.dccPortRangeEnd
        // Make sure the shared watchlist's own alert toggles match settings too.
        watchlist.playSound = s.playSoundOnWatchHit
        watchlist.bounceDock = s.bounceDockOnWatchHit
        watchlist.systemNotifications = s.systemNotificationsOnWatchHit
        watchlist.soundName = s.eventSounds["watchlistHit"] ?? "Glass"
    }

    // MARK: - Active-connection forwarding (back-compat surface for views)

    func connect() {
        ensureConnectionForSelectedProfile()
        activeConnection?.connect()
    }

    func disconnect() {
        activeConnection?.disconnect()
    }

    func sendInput(_ text: String) {
        guard let conn = activeConnection else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // /ignore and /unignore mutate persisted settings; everything else
        // is forwarded verbatim to the connection.
        if trimmed.hasPrefix("/") {
            let body = String(trimmed.dropFirst())
            let bits = body.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
            let cmd = bits.first?.lowercased() ?? ""
            let rest = bits.count > 1 ? bits[1].trimmingCharacters(in: .whitespaces) : ""
            switch cmd {
            case "ignore":
                if rest.isEmpty {
                    conn.appendInfoOnSelected(listIgnoreLines())
                } else {
                    var entry = IgnoreEntry(); entry.mask = rest
                    settings.upsertIgnore(entry)
                    conn.appendInfoOnSelected("Ignoring \(rest)")
                }
                return
            case "unignore":
                guard !rest.isEmpty else { return }
                if let match = settings.settings.ignoreList.first(where: { $0.mask == rest }) {
                    settings.removeIgnore(id: match.id)
                    conn.appendInfoOnSelected("No longer ignoring \(rest)")
                } else {
                    conn.appendInfoOnSelected("No ignore entry matches \(rest)")
                }
                return
            case "reloadbots", "reloadscripts":
                bot.reloadAll()
                conn.appendInfoOnSelected("Reloaded \(bot.scripts.filter { $0.enabled }.count) bot scripts.")
                return
            case "help":
                helpPrefillQuery = rest.trimmingCharacters(in: .whitespaces)
                showHelp = true
                return
            case "identity":
                handleIdentityCommand(rest: rest, on: conn)
                return
            case "quit", "exit":
                // IRC convention has /quit close the connection; here it
                // closes the whole app (classic desktop client behavior).
                // /disconnect remains for users who only want to leave one
                // network without quitting.
                let reason = rest.isEmpty ? "Client closed" : rest
                if settings.settings.quitConfirmationEnabled {
                    pendingQuitReason = reason
                    showQuitConfirmation = true
                } else {
                    performQuit(reason: reason)
                }
                return
            case "list":
                // /list           → open sheet with cached directory (fast).
                // /list full      → wipe cache and issue a fresh LIST.
                // /list <filter>  → issue LIST with the server-side filter.
                let arg = rest.trimmingCharacters(in: .whitespaces)
                let isFull = arg.caseInsensitiveCompare("full") == .orderedSame
                    || arg.caseInsensitiveCompare("refresh") == .orderedSame
                if isFull {
                    conn.requestChannelList(filter: "", forceRefresh: true)
                } else if !arg.isEmpty {
                    conn.requestChannelList(filter: arg, forceRefresh: false)
                }
                // With no arg, we just show whatever's cached; the UI has a
                // Refresh button for live updates.
                showChannelList = true
                return
            case "seen":
                let nick = rest.trimmingCharacters(in: .whitespaces)
                guard !nick.isEmpty else {
                    // No argument → open the sortable/filterable seen log sheet.
                    showSeenList = true
                    return
                }
                // Always check live channel membership first — it's the
                // freshest answer and doesn't depend on whether tracking was
                // on when the user joined or whether they've spoken since.
                let presentIn = presentChannels(of: conn, nick: nick)
                let stored = botEngine.seen(on: conn, nick: nick)
                if !presentIn.isEmpty {
                    conn.appendInfoOnSelected("\(nick) is currently in \(presentIn.joined(separator: ", "))")
                } else if let entry = stored {
                    conn.appendInfoOnSelected(BotEngine.describe(entry, queriedNick: nick))
                } else if !settings.settings.seenTrackingEnabled {
                    conn.appendInfoOnSelected("No record of \(nick) on this network. (Tip: turn on seen tracking in Setup → Bot to record future joins/parts/messages.)")
                } else {
                    conn.appendInfoOnSelected("No record of \(nick) on this network.")
                }
                return
            default:
                // Let PurpleBot claim the command if it registered a matching
                // /alias via irc.onCommand(...).
                if bot.handleCommandAlias(cmd, args: rest) { return }
            }
        }
        conn.sendInput(text, from: conn.selectedBufferID)
    }

    private func listIgnoreLines() -> String {
        let list = settings.settings.ignoreList
        if list.isEmpty { return "Ignore list is empty. Use /ignore <mask>." }
        return "Ignore list:\n" + list.map { "  • \($0.mask)" }.joined(separator: "\n")
    }

    func quickJoin(_ channel: String) {
        activeConnection?.quickJoin(channel)
    }

    func selectBuffer(_ id: Buffer.ID) {
        activeConnection?.selectBuffer(id)
    }

    /// Run the age-based log purge if the user has it enabled. Called on
    /// launch, and after the user toggles the setting. Safe to call when
    /// disabled — it short-circuits inside the actor.
    func runLogPurgeIfEnabled() {
        let s = settings.settings
        guard s.purgeLogsEnabled, s.purgeLogsAfterDays > 0 else { return }
        let days = s.purgeLogsAfterDays
        Task { [logStore] in
            let removed = await logStore.purge(olderThanDays: days)
            if removed > 0 {
                NSLog("PurpleIRC: purged \(removed) log file(s) older than \(days) days")
            }
        }
    }

    /// Convert any plaintext log files under the logs directory to the
    /// encrypted format and delete the original plaintext on success.
    /// Returns the count via the completion so the UI can show a summary.
    func convertLegacyPlaintextLogs(_ done: @escaping @MainActor (Int) -> Void) {
        Task { [logStore] in
            let n = await logStore.convertLegacyPlaintextLogs()
            await MainActor.run { done(n) }
        }
    }

    /// Snapshot of how many plaintext log files exist on disk, refreshed
    /// each time the Setup view appears so the button label can show
    /// the right count.
    func legacyPlaintextLogCount(_ done: @escaping @MainActor (Int) -> Void) {
        Task { [logStore] in
            let n = await logStore.countLegacyPlaintextLogs()
            await MainActor.run { done(n) }
        }
    }

    /// Unconditional manual purge, triggered by the "Purge now" button in
    /// Setup → Behavior. Uses the user's configured days value so a click
    /// can't accidentally wipe more than the policy allows.
    func purgeLogsNow() {
        let days = max(1, settings.settings.purgeLogsAfterDays)
        Task { [logStore] in
            _ = await logStore.purge(olderThanDays: days)
        }
    }

    /// Forward the KeyStore's current DEK into every persistence subsystem
    /// (logs, seen tracker, channel cache on each connection, bot scripts).
    /// Called during init and whenever the keystore locks/unlocks; a nil key
    /// reverts everything to plaintext writes.
    private func pushKeyToLogStore() {
        let key = keyStore.currentKey
        Task { [logStore] in
            await logStore.setEncryptionKey(key)
        }
        botEngine.seenStore.setEncryptionKey(key)
        bot.setEncryptionKey(key)
        for c in connections {
            c.channelList.setEncryptionKey(key)
        }
    }

    /// Channels on `conn` whose user list contains `nick` (case-insensitive).
    /// Used by `/seen` as a freshness fallback when the SeenStore has no
    /// record — a visibly-online user should always get a useful answer.
    private func presentChannels(of conn: IRCConnection, nick: String) -> [String] {
        let lower = nick.lowercased()
        return conn.buffers
            .filter { $0.kind == .channel }
            .filter { $0.users.contains { $0.lowercased() == lower } }
            .map { $0.name }
    }

    /// `/identity` — no arg lists, one arg sets the active connection's
    /// linked identity by name. Change takes effect on next connect.
    private func handleIdentityCommand(rest: String, on conn: IRCConnection) {
        let arg = rest.trimmingCharacters(in: .whitespaces)
        let idents = settings.settings.identities
        if arg.isEmpty {
            if idents.isEmpty {
                conn.appendInfoOnSelected("No identities defined yet. Create some in Setup → Identities.")
                return
            }
            let current = settings.identity(withID: conn.profile.identityID)?.name ?? "Custom"
            let list = idents.map { "  • \($0.name)\($0.id == conn.profile.identityID ? "  ← active" : "")" }
                .joined(separator: "\n")
            conn.appendInfoOnSelected("Active identity on \(conn.displayName): \(current)\nAvailable:\n\(list)\nUse /identity <name> to switch, or /identity custom to revert to inline profile fields.")
            return
        }
        if arg.caseInsensitiveCompare("custom") == .orderedSame
            || arg.caseInsensitiveCompare("none") == .orderedSame {
            applyIdentity(nil, to: conn)
            conn.appendInfoOnSelected("Identity cleared on \(conn.displayName). Reconnect to apply.")
            return
        }
        guard let match = idents.first(where: { $0.name.caseInsensitiveCompare(arg) == .orderedSame }) else {
            conn.appendInfoOnSelected("No identity named “\(arg)”. Use /identity (no args) to list.")
            return
        }
        applyIdentity(match, to: conn)
        let reconnectHint = conn.state == .connected ? " Reconnect to apply." : ""
        conn.appendInfoOnSelected("Identity on \(conn.displayName) is now “\(match.name)”.\(reconnectHint)")
    }

    /// Link an identity (or nil) to `conn`'s profile, persisting through
    /// settings so it survives app restart. Pushes the resolved identity into
    /// the connection immediately so /whois and CTCP replies update without
    /// needing a reconnect (though NICK/USER/SASL only change on reconnect).
    func applyIdentity(_ identity: Identity?, to conn: IRCConnection) {
        var profile = conn.profile
        profile.identityID = identity?.id
        conn.profile = profile
        conn.activeIdentity = identity
        // Persist back into SettingsStore so the link survives restarts.
        settings.upsertServer(profile)
    }

    /// Terminates the app after disconnecting every live connection with a
    /// QUIT line. `IRCClient.disconnect` sends the QUIT synchronously (1s
    /// timeout) before closing the socket, so servers get a proper goodbye.
    func performQuit(reason: String) {
        for c in connections {
            c.disconnect(quitMessage: reason)
        }
        #if canImport(AppKit)
        NSApp.terminate(nil)
        #endif
    }

    func closeCurrentBuffer() {
        guard let conn = activeConnection, let sel = conn.selectedBufferID else { return }
        conn.closeBuffer(id: sel)
    }

    /// Close any buffer by id, regardless of which connection owns it. Used
    /// by the sidebar's per-row close (X) button + context menu so you can
    /// part a channel without first selecting it.
    func closeBuffer(id: Buffer.ID) {
        guard let conn = connections.first(where: { $0.buffers.contains(where: { $0.id == id }) }) else { return }
        conn.closeBuffer(id: id)
    }

    // Read-only forwarders matching the old singleton-IRCClient surface.
    var connectionState: IRCConnectionState { activeConnection?.state ?? .disconnected }
    var nick: String { activeConnection?.nick ?? "" }
    var buffers: [Buffer] { activeConnection?.buffers ?? [] }
    var selectedBufferID: Buffer.ID? { activeConnection?.selectedBufferID }

    /// Raw log for the active connection — views can clear it via the setter.
    var rawLog: [String] {
        get { activeConnection?.rawLog ?? [] }
        set { activeConnection?.rawLog = newValue }
    }
}

// MARK: - WatchlistDelegate

extension ChatModel: WatchlistDelegate {
    /// Route watchlist-sourced raw lines to whichever connection currently
    /// looks live. We prefer the active connection; if it isn't connected,
    /// fall back to the first `.connected` one. Multi-connection watchlist
    /// routing (picking the right network per watched nick) is a future
    /// concern — today there's effectively one connection at a time.
    func watchlistSendRaw(_ line: String) {
        if let active = activeConnection, active.state == .connected {
            active.watchlistRouteSendRaw(line)
            return
        }
        if let other = connections.first(where: { $0.state == .connected }) {
            other.watchlistRouteSendRaw(line)
        }
    }

    func watchlistPostInfo(_ text: String) {
        if let active = activeConnection {
            active.watchlistRoutePostInfo(text)
        }
    }
}

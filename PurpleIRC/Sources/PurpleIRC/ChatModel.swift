import Foundation
import SwiftUI
import Combine

/// A timestamped record of someone joining, parting, quitting, or changing
/// nick — across every connection. Powers the Watch Monitor window. Kept
/// flat (not tied to ChatLine.Kind) so the monitor can render its own
/// presentation without dragging chat-row styling along.
struct ActivityEvent: Identifiable, Hashable {
    enum Kind: String, Codable, CaseIterable {
        case join, part, quit, nick
    }
    let id = UUID()
    let timestamp: Date
    let kind: Kind
    let networkName: String
    let nick: String
    /// `user@host` portion of the IRC prefix at observation time, when known.
    let userHost: String?
    /// Channel for join/part. nil for quit (network-level) and nick changes.
    let channel: String?
    /// Reason / new-nick / other context. Free-form display string.
    let detail: String?
}

struct ChatLine: Identifiable, Equatable, Codable {
    let id: UUID
    let timestamp: Date
    let kind: Kind
    let text: String
    var isMention: Bool = false

    /// ID of the HighlightRule that tagged this line, if any. Resolved at
    /// render time to look up color / styling; nil = no rule matched.
    var highlightRuleID: UUID? = nil

    /// Character-level match ranges in the post-format (code-stripped) text.
    /// Used by MessageRow to tint matched words after IRCFormatter.render.
    /// Stored as `[location, length]` pairs for Codable compatibility.
    var highlightRanges: [NSRange] = []

    init(timestamp: Date,
         kind: Kind,
         text: String,
         isMention: Bool = false,
         highlightRuleID: UUID? = nil,
         highlightRanges: [NSRange] = []) {
        self.id = UUID()
        self.timestamp = timestamp
        self.kind = kind
        self.text = text
        self.isMention = isMention
        self.highlightRuleID = highlightRuleID
        self.highlightRanges = highlightRanges
    }

    enum Kind: Equatable, Codable {
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

    // MARK: - Codable (NSRange isn't Codable; pack as `[loc, len]`)

    private enum CodingKeys: String, CodingKey {
        case id, timestamp, kind, text
        case isMention, highlightRuleID, highlightRanges
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.timestamp = try c.decode(Date.self, forKey: .timestamp)
        self.kind = try c.decode(Kind.self, forKey: .kind)
        self.text = try c.decode(String.self, forKey: .text)
        self.isMention = try c.decodeIfPresent(Bool.self, forKey: .isMention) ?? false
        self.highlightRuleID = try c.decodeIfPresent(UUID.self, forKey: .highlightRuleID)
        // Persisted as flat [loc, len, loc, len, …] integer array.
        let flat = try c.decodeIfPresent([Int].self, forKey: .highlightRanges) ?? []
        var out: [NSRange] = []
        var i = 0
        while i + 1 < flat.count {
            out.append(NSRange(location: flat[i], length: flat[i + 1]))
            i += 2
        }
        self.highlightRanges = out
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(timestamp, forKey: .timestamp)
        try c.encode(kind, forKey: .kind)
        try c.encode(text, forKey: .text)
        try c.encode(isMention, forKey: .isMention)
        try c.encodeIfPresent(highlightRuleID, forKey: .highlightRuleID)
        var flat: [Int] = []
        flat.reserveCapacity(highlightRanges.count * 2)
        for r in highlightRanges {
            flat.append(r.location)
            flat.append(r.length)
        }
        try c.encode(flat, forKey: .highlightRanges)
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
    @Published var showAppLog: Bool = false
    @Published var showChatLogs: Bool = false
    @Published var showWatchlist: Bool = false
    @Published var showSetup: Bool = false
    /// One-shot directive for the Setup sheet to land on a specific tab.
    /// Cleared by SetupView once consumed so the next plain "Setup" button
    /// click drops the user on whatever tab they last used (or Servers).
    @Published var pendingSetupTab: SetupView.Tab? = nil
    /// One-shot directive for AddressBookSetup to pre-select a specific
    /// entry. Used by the sidebar's "Edit address book entry…" right-click
    /// action so the user lands on the row they just acted on instead of
    /// the first entry in the list.
    @Published var pendingAddressBookSelection: UUID? = nil
    @Published var showChannelList: Bool = false
    @Published var showSeenList: Bool = false
    @Published var showHelp: Bool = false
    @Published var showDCC: Bool = false
    /// Prefilled search text when /help is invoked with an argument.
    var helpPrefillQuery: String = ""

    /// Rolling cross-network feed of join / part / quit / nick events for
    /// the Watch Monitor window. Capped to keep memory bounded — see
    /// `activityFeedCap`. Newest events appended at the end.
    @Published var activityFeed: [ActivityEvent] = []
    private static let activityFeedCap = 1000

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

    /// Per-network archive of recent chat lines, written at quit/disconnect
    /// and replayed on the next launch so users see the trailing window of
    /// each open buffer instead of an empty channel.
    let sessionHistory: SessionHistoryStore

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
        self.sessionHistory = SessionHistoryStore(supportDirectoryURL: settings.supportDirectoryURL)
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
        // Wire AppLog to a file under the support dir, sealed with the same
        // DEK as everything else. Locked sessions log to memory only.
        AppLog.shared.bind(
            fileURL: settings.supportDirectoryURL.appendingPathComponent("app.log"),
            key: keyStore.currentKey)
        AppLog.shared.info("PurpleIRC \(AppVersion.short) launched", category: "Boot")
        // Capture the trailing window of every buffer at quit. Notifications
        // are AppKit-only — guard with canImport at the top of the file if
        // we ever target Linux.
        NotificationCenter.default
            .publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                Task { @MainActor in self?.saveAllHistories() }
            }
            .store(in: &cancellables)
        // Expose this model to AppleScript verbs (Resources/PurpleIRC.sdef).
        // Hooks the singleton bridge so connect / send / join / etc. routed
        // via Apple Events reach the live ChatModel.
        AppleScriptBridge.register(host: self)
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
        // Cross-network presence feed for the Watch Monitor window.
        events
            .sink { [weak self] tuple in
                Task { @MainActor in
                    self?.appendToActivityFeed(connectionID: tuple.0, event: tuple.1)
                }
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

        // Push the previous-session snapshot into the connection so it can
        // restore channels + queries during runPostWelcome. Keyed by the
        // (stable) profile UUID, not the (per-launch) connection UUID.
        // Set both an eager copy AND a resolver; the resolver lets the
        // connection re-fetch on every welcome so encrypted-keystore users
        // (whose lastSession is empty until after unlock — which happens
        // AFTER addConnection) still get their session restored.
        if settings.settings.restoreOpenBuffersOnLaunch {
            let key = profile.id.uuidString
            let history = sessionHistory.load(networkSlug: SeenStore.slug(for: conn.displayName))
            if let snap = settings.settings.lastSession[key] {
                conn.setPendingRestore(
                    channels: snap.channels,
                    queries: snap.queries,
                    selected: snap.selected,
                    history: history.buffers)
            } else if !history.buffers.isEmpty {
                // History without a session snapshot can happen when the
                // user toggled the lastSession reset — still worth restoring
                // history into whatever buffers materialize.
                conn.setPendingRestore(
                    channels: [], queries: [], selected: nil,
                    history: history.buffers)
            }
        }
        let pid = profile.id
        conn.sessionSnapshotResolver = { [weak self] in
            guard let self,
                  self.settings.settings.restoreOpenBuffersOnLaunch
            else { return nil }
            return self.settings.settings.lastSession[pid.uuidString]
        }
        conn.sessionHistoryResolver = { [weak self, weak conn] in
            guard let self, let conn,
                  self.settings.settings.restoreOpenBuffersOnLaunch
            else { return [:] }
            return self.sessionHistory.load(
                networkSlug: SeenStore.slug(for: conn.displayName)).buffers
        }

        connections.append(conn)
        var bag: [AnyCancellable] = []
        conn.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &bag)
        conn.events
            .sink { [weak self] tuple in self?.events.send(tuple) }
            .store(in: &bag)
        // Save the connection's buffer list to settings whenever it
        // changes shape. The check inside `maybeSaveSnapshot` is a cheap
        // equality test, so cycles where settings.save fires our sink
        // don't loop — the snapshot only writes when channels or queries
        // actually change.
        conn.$buffers
            .sink { [weak self, weak conn] _ in
                guard let self, let conn else { return }
                self.maybeSaveSnapshot(for: conn)
            }
            .store(in: &bag)
        // Also save when the user picks a new buffer so the next launch
        // restores focus to the same place.
        conn.$selectedBufferID
            .sink { [weak self, weak conn] _ in
                guard let self, let conn else { return }
                self.maybeSaveSnapshot(for: conn)
            }
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

    /// Spawn a NEW connection for the given profile, ignoring any existing
    /// connection for that profile. Used by the Networks panel's "Add"
    /// menu so the user can run multiple simultaneous connections to the
    /// same server (different identities, multiple bouncers, etc.).
    /// The new connection becomes active and starts connecting immediately.
    @discardableResult
    func connectAdditionalProfile(_ profile: ServerProfile) -> IRCConnection {
        let conn = addConnection(for: profile)
        activeConnectionID = conn.id
        applySettingsToAll()
        conn.connect()
        return conn
    }

    /// Connect-or-activate semantics: if a connection for the given profile
    /// is already running, focus it; otherwise spawn one and connect.
    /// Distinct from `connectAdditionalProfile` (which always spawns a
    /// fresh connection). This is the right verb for the Networks panel's
    /// per-profile "Connect" button.
    func connectProfile(_ profile: ServerProfile) {
        if let existing = connections.first(where: { $0.profile.id == profile.id }) {
            activeConnectionID = existing.id
            if existing.state != .connected && existing.state != .connecting {
                existing.connect()
            }
            return
        }
        connectAdditionalProfile(profile)
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
        // If the selected server in settings changed, follow it: switch to
        // an existing connection for that profile or seed a new one. The
        // "seed if missing" branch matters at unlock time — settings come
        // back from the encrypted envelope pointing at a profile that was
        // never live during the locked-startup phase.
        if let selID = settings.settings.selectedServerID {
            let alreadyActive = connections.contains {
                $0.id == activeConnectionID && $0.profile.id == selID
            }
            if !alreadyActive {
                if let existing = connections.first(where: { $0.profile.id == selID }) {
                    activeConnectionID = existing.id
                } else if let profile = settings.settings.servers.first(where: { $0.id == selID }) {
                    let conn = addConnection(for: profile)
                    activeConnectionID = conn.id
                }
            }
        }
        applySettingsToAll()
    }

    /// Selected theme — read by MessageRow at render time.
    var theme: Theme { Theme.named(settings.settings.themeID) }

    /// Resolved chat font (family + size + optional bold). Read by every
    /// view that renders chat text — keeps font customisation in one place
    /// instead of scattered `.font(...)` calls.
    var chatFont: Font {
        let s = settings.settings
        let base = s.chatFontFamily.font(size: CGFloat(s.chatFontSize))
        return s.boldChatText ? base.bold() : base
    }

    /// Caption-sized variant of the chat font (timestamps, join/part lines).
    /// Scales down 25% from the user's base size so timestamps still feel
    /// secondary even at large body sizes.
    var chatCaptionFont: Font {
        let s = settings.settings
        let size = max(9, CGFloat(s.chatFontSize) * 0.78)
        return s.chatFontFamily.font(size: size)
    }

    /// Translate the inbound IRC event stream into ActivityEvent rows for
    /// the Watch Monitor. Filters everything except join / part / quit /
    /// nickChanged. Caps at `activityFeedCap` by trimming the oldest.
    private func appendToActivityFeed(connectionID: UUID,
                                      event: IRCConnectionEvent) {
        guard let conn = connections.first(where: { $0.id == connectionID }) else { return }
        let net = conn.displayName
        let now = Date()
        let userHost: String?
        let new: ActivityEvent

        switch event {
        case .join(let nick, let channel, let isSelf):
            guard !isSelf else { return }
            userHost = conn.userHost(for: nick)
            new = ActivityEvent(timestamp: now, kind: .join, networkName: net,
                                nick: nick, userHost: userHost,
                                channel: channel, detail: nil)
        case .part(let nick, let channel, let reason, let isSelf):
            guard !isSelf else { return }
            userHost = conn.userHost(for: nick)
            new = ActivityEvent(timestamp: now, kind: .part, networkName: net,
                                nick: nick, userHost: userHost,
                                channel: channel, detail: reason)
        case .quit(let nick, let reason):
            guard nick.lowercased() != conn.nick.lowercased() else { return }
            userHost = conn.userHost(for: nick)
            new = ActivityEvent(timestamp: now, kind: .quit, networkName: net,
                                nick: nick, userHost: userHost,
                                channel: nil, detail: reason)
        case .nickChanged(let old, let newNick, let isSelf):
            guard !isSelf else { return }
            userHost = conn.userHost(for: newNick) ?? conn.userHost(for: old)
            new = ActivityEvent(timestamp: now, kind: .nick, networkName: net,
                                nick: old, userHost: userHost,
                                channel: nil, detail: "→ \(newNick)")
        default:
            return
        }
        activityFeed.append(new)
        // Trim oldest to keep memory bounded. 1000 entries is enough for
        // a long-running session without becoming a chore to render.
        if activityFeed.count > Self.activityFeedCap {
            activityFeed.removeFirst(activityFeed.count - Self.activityFeedCap)
        }
    }

    /// Wipe the watch-monitor history. Wired to the Clear button in the
    /// monitor window's toolbar.
    func clearActivityFeed() {
        activityFeed.removeAll()
    }

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
            case "log", "applog", "debuglog":
                // Open the diagnostic log viewer (encrypted on disk, levels
                // debug→critical, filterable). Useful when a user needs to
                // grab a snapshot for a bug report.
                showAppLog = true
                return
            case "logs", "viewlogs", "chatlog", "chatlogs":
                // Open the chat log viewer — decrypts the per-buffer log
                // files on the fly when the keystore is unlocked.
                showChatLogs = true
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

    // MARK: - Session snapshot persistence

    /// Cache of the last snapshot written to settings per profile, so we can
    /// skip redundant writes when nothing material has changed (the most
    /// common case — every chat-line append fires `$buffers`).
    private var lastSnapshotByProfileID: [UUID: SessionSnapshot] = [:]

    /// Persist the trailing-window of every buffer on every connected
    /// network. Called at quit (via `willTerminateNotification`) and on
    /// each disconnect so users see their last live state on relaunch.
    /// Drops the leading "previous session" / trailing "live" markers
    /// from earlier restores so successive launches don't accumulate
    /// banner pairs.
    func saveAllHistories() {
        for conn in connections where conn.state == .connected {
            let slug = SeenStore.slug(for: conn.displayName)
            var network = SessionHistoryStore.NetworkHistory()
            for buf in conn.buffers where buf.kind != .server {
                let trimmed = buf.lines
                    .filter { !Self.isRestoreBannerLine($0) }
                    .suffix(SessionHistoryStore.linesPerBuffer)
                network.buffers[buf.name] = Array(trimmed)
            }
            sessionHistory.save(networkSlug: slug, history: network)
        }
    }

    /// True for the marker lines `replayHistoryIntoBuffer` injects. Filtered
    /// out at save time so consecutive restores don't visually multiply.
    private static func isRestoreBannerLine(_ line: ChatLine) -> Bool {
        guard case .info = line.kind else { return false }
        return line.text.hasPrefix("── ") && line.text.hasSuffix(" ──")
    }

    /// Compute the connection's current snapshot and write it into settings
    /// if it differs from the last value we saved for that profile. Skipped
    /// when the connection isn't live yet — otherwise the empty initial
    /// `[]` value emitted by Combine on subscribe would clobber the saved
    /// snapshot before `applyPendingRestore` had a chance to use it.
    private func maybeSaveSnapshot(for conn: IRCConnection) {
        // Only persist while the connection is live. Disconnected/connecting
        // states don't hold authoritative buffer state — either we haven't
        // restored yet (so the saved snapshot is still authoritative) or
        // we're in a transient teardown (don't wipe on the way out).
        guard conn.state == .connected else { return }

        let snap = conn.currentSessionSnapshot()
        let pid = conn.profile.id
        if lastSnapshotByProfileID[pid] == snap { return }
        lastSnapshotByProfileID[pid] = snap

        let key = pid.uuidString
        if snap.channels.isEmpty && snap.queries.isEmpty {
            settings.settings.lastSession.removeValue(forKey: key)
        } else {
            settings.settings.lastSession[key] = snap
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
        sessionHistory.setEncryptionKey(key)
        for c in connections {
            c.channelList.setEncryptionKey(key)
        }
        // Re-bind AppLog so subsequent emits use the current DEK. Reading
        // the file picks the right format (encrypted vs plaintext) on its own.
        AppLog.shared.bind(
            fileURL: settings.supportDirectoryURL.appendingPathComponent("app.log"),
            key: key)
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

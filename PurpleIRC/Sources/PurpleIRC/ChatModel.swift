import Foundation
import SwiftUI
import Combine

struct ChatLine: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let kind: Kind
    let text: String
    var isMention: Bool = false

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
    @Published var showDCC: Bool = false

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
        let downloads = settings.supportDirectoryURL.appendingPathComponent("downloads", isDirectory: true)
        self.dcc = DCCService(downloadsDir: downloads)
        watchlist.setDelegate(self)
        seedFromSelectedProfile()
        applySettingsToAll()
        bot.attach(self)
        dcc.chatModel = self
        // Fan out bot-visible events to the sound player.
        events
            .sink { [weak self] tuple in
                Task { @MainActor in self?.playSoundFor(event: tuple.1) }
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

    func closeCurrentBuffer() {
        guard let conn = activeConnection, let sel = conn.selectedBufferID else { return }
        conn.closeBuffer(id: sel)
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

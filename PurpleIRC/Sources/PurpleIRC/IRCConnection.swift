import Foundation
import Combine
import AppKit

/// Forward-compat event stream. Every inbound IRC message, every state
/// transition, and the outbound lines we emit fan out through this enum so
/// the eventual PurpleBot scripting host (and any future listeners) can
/// subscribe without touching core dispatch. Kept `Sendable` so a bot context
/// off the main actor can consume events safely.
enum IRCConnectionEvent: Sendable {
    case state(IRCConnectionState)
    case inbound(IRCMessage)
    case outbound(String)
    case ownNickChanged(String)
    /// Any user on a shared channel changed nick. `isSelf == true` on our
    /// own changes (which are *also* delivered as `.ownNickChanged`).
    case nickChanged(old: String, new: String, isSelf: Bool)
    case privmsg(from: String, target: String, text: String, isAction: Bool, isMention: Bool)
    case notice(from: String, target: String, text: String)
    case join(nick: String, channel: String, isSelf: Bool)
    case part(nick: String, channel: String, reason: String?, isSelf: Bool)
    case quit(nick: String, reason: String?)
    case topic(channel: String, topic: String, setter: String?)
    case ctcpRequest(from: String, target: String, command: String, args: String)
    case awayChanged(isAway: Bool, reason: String?)
    case ignoredMessage(from: String, target: String)
}

/// One IRC connection: owns its `IRCClient`, its buffers, its watchlist
/// reference, reconnect bookkeeping, and a `PassthroughSubject` of events.
/// ChatModel holds a list of these; each event always carries the network id.
@MainActor
final class IRCConnection: ObservableObject, Identifiable {
    let id: UUID = UUID()

    @Published var profile: ServerProfile
    @Published var state: IRCConnectionState = .disconnected
    @Published var nick: String = ""
    @Published var buffers: [Buffer] = []
    @Published var selectedBufferID: Buffer.ID?
    @Published var rawLog: [String] = []

    /// Away state for this network.
    @Published private(set) var isAway: Bool = false
    @Published private(set) var awayReason: String?

    /// Per-network channel directory, fed by RPL_LIST (322). Exposed to the UI
    /// so the ChannelListView can bind directly. Disk cache is wired up by
    /// ChatModel via `bindChannelCache(baseDir:)` after construction.
    let channelList = ChannelListService()

    /// Hook the channel-list service up to the given cache directory, using
    /// the connection's display name to derive a stable slug for the file.
    /// Called from ChatModel.addConnection once the support dir is known.
    func bindChannelCache(baseDir: URL) {
        let slug = SeenStore.slug(for: displayName)
        channelList.setCacheLocation(baseDir: baseDir, slug: slug)
    }

    /// Shared across all connections — ChatModel owns the single instance and
    /// routes its delegate calls to the right connection.
    let watchlist: WatchlistService

    /// Fanout of everything that happens on this connection. PurpleBot's
    /// scripting host will subscribe to this later. The stream keeps no
    /// replay buffer — late subscribers miss older events.
    let events = PassthroughSubject<(UUID, IRCConnectionEvent), Never>()

    /// Label shown in the sidebar. Falls back to host when profile name is empty.
    var displayName: String {
        profile.name.isEmpty ? profile.host : profile.name
    }

    private let client = IRCClient()
    private var serverBufferID: Buffer.ID?
    private var haveRegisteredWatchlist = false

    private var userInitiatedDisconnect = false
    private var reconnectAttempt = 0
    private var reconnectTask: Task<Void, Never>?

    // Bounded 433 (nick-in-use) handling. Without this we'd keep appending
    // `_` forever and eventually hit NICKLEN, generating cascading 432/433
    // replies and no successful registration.
    private var nickCollisionRetries = 0
    private static let maxNickCollisionRetries = 4

    private(set) var saslActive = false

    // Tier 2 knobs — ChatModel pushes these in from settings.
    var highlightOnOwnNick: Bool = true
    var ignoreMatchers: [IgnoreEntry] = []
    var ctcpRepliesEnabled: Bool = true
    var ctcpVersionString: String = "PurpleIRC"
    var autoReplyWhenAway: Bool = true
    var awayAutoReply: String = ""

    // User-configured highlight rules (pushed in from settings). The matcher
    // caches compiled regex so busy channels don't recompile per message.
    var highlightRules: [HighlightRule] = [] {
        didSet { highlightMatcher.clearCache() }
    }
    /// Identity linked to this connection's profile (looked up from global
    /// AppSettings.identities by `profile.identityID`). Pushed in by ChatModel.
    /// Overrides nick/user/realName/SASL/NickServ at connect time when set.
    var activeIdentity: Identity? = nil
    /// NSSound name for the user's configured "highlight" event sound.
    var highlightSoundName: String = ""
    private let highlightMatcher = HighlightMatcher()

    // Log writer. ChatModel injects a shared LogStore; nil means no logging.
    var logStore: LogStore?
    var loggingEnabled: Bool = false
    var logNoisyLines: Bool = false

    /// DCC service. ChatModel injects the shared instance so /dcc and
    /// incoming CTCP DCC offers can route to the transfers window.
    weak var dcc: DCCService?

    // Throttle for away auto-replies so a spammer can't DoS us.
    private var lastAwayReplyAt: [String: Date] = [:]
    private static let awayReplyInterval: TimeInterval = 120 // seconds per-nick

    // MARK: - IRCv3 cap-derived state

    /// Lowercased nick → away reason ("" when away with no reason given).
    /// Missing key means the user is back / never seen as away. Populated
    /// by the IRCv3 AWAY notification (cap `away-notify`).
    @Published private(set) var awayByNick: [String: String] = [:]

    /// Lowercased nick → services account name. Populated by the
    /// `extended-join` cap on JOIN, the `account-notify` cap on the inline
    /// ACCOUNT command, and `account-tag` on individual messages.
    @Published private(set) var accountByNick: [String: String] = [:]

    /// True once CAP negotiation has reached a state where these caps are
    /// trustworthy. Used to gate behaviour like echo-message dedup so the
    /// pre-CAP burst of activity doesn't accidentally swallow lines.
    private var hasEchoMessageCap: Bool { client.enabledCaps.contains("echo-message") }

    /// IRCv3 BATCH bookkeeping. Each open batch records its type and any
    /// extra metadata the server attached so handlers can decide what to
    /// do with messages bearing that batch's `@batch=` tag.
    private struct BatchInfo {
        let id: String
        let type: String
        let params: [String]
    }
    private var openBatches: [String: BatchInfo] = [:]

    /// Channels we already requested CHATHISTORY for in this session, keyed
    /// lowercase. Re-joins shouldn't double-fetch — most servers (Soju,
    /// Ergo) don't gate the request and would happily replay it.
    private var chatHistoryFetched: Set<String> = []

    /// Effective CHATHISTORY upper bound for `LATEST`/`BEFORE` requests. The
    /// `chathistory=N` ISUPPORT-style cap argument advertises the server's
    /// max; we cap at 100 to avoid a flood for users joining busy rooms.
    private var chatHistoryLimit: Int {
        let advertised = Int(client.serverCapValues["chathistory"]
                          ?? client.serverCapValues["draft/chathistory"] ?? "")
        return min(100, max(20, advertised ?? 50))
    }

    // MARK: - Session restore (channel + query buffers persisted across launches)

    /// Channels we want to JOIN as soon as registration completes — populated
    /// by `setPendingRestore` before the connect, consumed in `runPostWelcome`.
    private var pendingRestoreChannels: [String] = []
    /// Query buffer names to pre-create after registration so the sidebar
    /// reflects the previous session before any new traffic arrives. Pure
    /// UI restore — no IRC verb is sent for queries.
    private var pendingRestoreQueries: [String] = []
    /// Best-effort selection target: bare buffer name to focus once restore
    /// has finished. Skipped if the buffer hasn't materialized yet.
    private var pendingRestoreSelection: String?

    /// Per-buffer trailing-window from the previous session. Keyed by the
    /// buffer name (case-preserved). Populated alongside the channel/query
    /// list and replayed into each buffer at restore time.
    private var pendingRestoreHistory: [String: [ChatLine]] = [:]

    /// Stash a snapshot to be applied during the post-welcome runloop. Safe
    /// to call before connect; safe to call repeatedly (latest wins).
    func setPendingRestore(channels: [String], queries: [String], selected: String?,
                           history: [String: [ChatLine]] = [:]) {
        self.pendingRestoreChannels = channels
        self.pendingRestoreQueries = queries
        self.pendingRestoreSelection = selected
        self.pendingRestoreHistory = history
    }

    /// Resolver for "what should I restore on welcome?" set by ChatModel.
    /// Run on every welcome so encrypted-store users — whose `lastSession`
    /// dictionary isn't populated until after the keystore unlocks — still
    /// get their channels and queries back. Returns nil when restore is
    /// disabled or no snapshot exists for this profile.
    var sessionSnapshotResolver: (() -> SessionSnapshot?)?

    /// Resolver for the per-buffer chat-line archive. Same pattern as
    /// `sessionSnapshotResolver` — re-fetched at welcome time so encrypted
    /// users (whose archive only loads after unlock) still see history.
    var sessionHistoryResolver: (() -> [String: [ChatLine]])?

    /// Capture the current buffer state for persistence. Server buffer is
    /// always live, so it's not represented in the snapshot — restore
    /// recreates it implicitly on connect.
    func currentSessionSnapshot() -> SessionSnapshot {
        var channels: [String] = []
        var queries: [String] = []
        for buf in buffers {
            switch buf.kind {
            case .channel: channels.append(buf.name)
            case .query:   queries.append(buf.name)
            case .server:  break
            }
        }
        let selected: String? = {
            guard let id = selectedBufferID,
                  let buf = buffers.first(where: { $0.id == id }),
                  buf.kind != .server else { return nil }
            return buf.name
        }()
        return SessionSnapshot(channels: channels, queries: queries, selected: selected)
    }

    /// Apply pending channel-join + query-buffer restore. Called from
    /// `runPostWelcome` after `autoJoinIfNeeded` so we don't double-JOIN
    /// channels already covered by the profile's auto-join list.
    private func applyPendingRestore() {
        // Encrypted-keystore users have their lastSession dictionary
        // populated only after the unlock unwraps the settings envelope,
        // which happens AFTER addConnection ran. Pull a fresh snapshot
        // each welcome so those users still get restore.
        if pendingRestoreChannels.isEmpty && pendingRestoreQueries.isEmpty,
           let snap = sessionSnapshotResolver?() {
            pendingRestoreChannels = snap.channels
            pendingRestoreQueries  = snap.queries
            pendingRestoreSelection = snap.selected
        }
        if pendingRestoreHistory.isEmpty,
           let history = sessionHistoryResolver?() {
            pendingRestoreHistory = history
        }
        defer {
            pendingRestoreChannels.removeAll()
            pendingRestoreQueries.removeAll()
            pendingRestoreSelection = nil
            pendingRestoreHistory.removeAll()
        }
        guard !pendingRestoreChannels.isEmpty || !pendingRestoreQueries.isEmpty else { return }
        AppLog.shared.info(
            "Restoring session for \(displayName): \(pendingRestoreChannels.count) channels, \(pendingRestoreQueries.count) queries",
            category: "IRC.\(displayName)")

        // Pre-create query buffers so the sidebar shows them immediately,
        // even before the other party messages back. Prepopulated with
        // history (when present) so users see the trailing window of the
        // previous session immediately.
        for q in pendingRestoreQueries where !q.isEmpty {
            let i = indexOfOrCreateBuffer(name: q, kind: .query)
            replayHistoryIntoBuffer(at: i, name: q)
        }

        // Channels: pre-create the buffer with history NOW so the user
        // sees the trailing window even before the JOIN reply arrives.
        // The handleJoin path's `indexOfOrCreateBuffer` will reuse the
        // same buffer when the server confirms the JOIN, then append
        // "You joined" after the history.
        let alreadyJoining = Set(profile.autoJoin
            .split { $0 == "," || $0 == " " }
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty })
        var seen = Set<String>()
        for raw in pendingRestoreChannels where !raw.isEmpty {
            let name = raw.hasPrefix("#") ? raw : "#" + raw
            let key = name.lowercased()
            guard seen.insert(key).inserted else { continue }
            // Pre-create the buffer + replay history regardless of
            // alreadyJoining (autoJoin will JOIN it; we still want history).
            let i = indexOfOrCreateBuffer(name: name, kind: .channel)
            replayHistoryIntoBuffer(at: i, name: name)
            // Send JOIN unless autoJoin already covered this channel.
            if !alreadyJoining.contains(key) {
                client.send("JOIN \(name)")
            }
        }

        // Re-select the previously-active buffer if it now exists. Channel
        // buffers may not yet exist (JOIN is async); store the target name
        // and let the JOIN handler resolve it the moment the buffer
        // materializes. Replaces a fire-and-forget 800 ms Task that left
        // a blank buffer on the screen when JOIN took longer than expected.
        if let target = pendingRestoreSelection {
            let lower = target.lowercased()
            if let i = buffers.firstIndex(where: { $0.name.lowercased() == lower }) {
                selectedBufferID = buffers[i].id
                pendingRestoreSelectName = nil
            } else {
                pendingRestoreSelectName = lower
            }
        }
    }

    /// Buffer name (lowercased) we still want to focus once it appears.
    /// Cleared by `indexOfOrCreateBuffer` the moment a matching buffer is
    /// created so the eventual JOIN reply lands the user on the right
    /// channel without a deferred timer.
    private var pendingRestoreSelectName: String?

    init(profile: ServerProfile, watchlist: WatchlistService) {
        self.profile = profile
        self.watchlist = watchlist
        self.nick = profile.nick
        client.onMessage = { [weak self] msg in
            Task { @MainActor in self?.handle(msg) }
        }
        client.onState = { [weak self] s in
            Task { @MainActor in self?.handleState(s) }
        }
        client.onRaw = { [weak self] line, outbound in
            Task { @MainActor in
                guard let self else { return }
                let prefix = outbound ? ">> " : "<< "
                self.rawLog.append(prefix + line)
                if self.rawLog.count > 2000 {
                    self.rawLog.removeFirst(self.rawLog.count - 2000)
                }
                if outbound {
                    self.emit(.outbound(line))
                }
            }
        }
    }

    // MARK: - Public control

    func connect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        userInitiatedDisconnect = false
        nickCollisionRetries = 0

        guard let portNum = UInt16(exactly: profile.port) else {
            appendError("Invalid port on \(profile.name): \(profile.port)")
            return
        }
        // Identity overlay — identity fields win when a linked identity exists.
        let effective = profile.applyingIdentity(activeIdentity)
        self.nick = effective.nick
        if let ident = activeIdentity {
            appendInfo("Connecting to \(profile.name) as \(ident.name) (\(effective.nick)) — \(profile.host):\(portNum), TLS=\(profile.useTLS)…")
        } else {
            appendInfo("Connecting to \(profile.name) (\(profile.host):\(portNum), TLS=\(profile.useTLS))…")
        }
        if effective.saslMechanism != .none {
            appendInfo("SASL \(effective.saslMechanism.rawValue) will be attempted after CAP negotiation.")
        }

        let proxyPort = UInt16(exactly: profile.proxyPort) ?? 0
        if profile.proxyType != .none {
            appendInfo("Via \(profile.proxyType.displayName) proxy \(profile.proxyHost):\(profile.proxyPort).")
        }
        let config = IRCConnectionConfig(
            host: profile.host,
            port: portNum,
            useTLS: profile.useTLS,
            nick: effective.nick,
            user: effective.user.isEmpty ? "purpleirc" : effective.user,
            realName: effective.realName.isEmpty ? "PurpleIRC" : effective.realName,
            serverPassword: profile.password.isEmpty ? nil : profile.password,
            saslMechanism: effective.saslMechanism,
            saslAccount: effective.saslAccount,
            saslPassword: effective.saslPassword,
            proxyType: profile.proxyType,
            proxyHost: profile.proxyHost,
            proxyPort: proxyPort,
            proxyUsername: profile.proxyUsername,
            proxyPassword: profile.proxyPassword
        )
        client.connect(config: config)
    }

    /// Profile with identity fields overlaid (when one is linked). Used by
    /// runtime code that needs the current identity values — CTCP replies,
    /// NickServ IDENTIFY, away reason — so identity changes take effect
    /// without a reconnect for things that don't require one.
    private var effectiveProfile: ServerProfile {
        profile.applyingIdentity(activeIdentity)
    }

    func disconnect(quitMessage: String = "PurpleIRC signing off") {
        userInitiatedDisconnect = true
        reconnectTask?.cancel()
        reconnectTask = nil
        client.disconnect(quitMessage: quitMessage)
    }

    /// Public outbound. Bot scripting will call this path.
    func sendRaw(_ line: String) {
        client.send(line)
    }

    func sendInput(_ text: String, from selectedBuffer: Buffer.ID?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if trimmed.hasPrefix("/") {
            handleCommand(String(trimmed.dropFirst()), selection: selectedBuffer)
            return
        }

        guard let bufID = selectedBuffer,
              let bufIdx = buffers.firstIndex(where: { $0.id == bufID }) else {
            return
        }
        let buf = buffers[bufIdx]
        guard buf.kind != .server else {
            buffers[bufIdx].appendInfo("Cannot send message in server buffer. Use a channel or /msg <nick> <text>.")
            return
        }
        client.send("PRIVMSG \(buf.name) :\(trimmed)")
        appendTo(bufferIndex: bufIdx, line: ChatLine(
            timestamp: Date(),
            kind: .privmsg(nick: nick, isSelf: true),
            text: trimmed
        ))
    }

    func closeBuffer(id: Buffer.ID) {
        guard let i = buffers.firstIndex(where: { $0.id == id }) else { return }
        let buf = buffers[i]
        guard buf.kind != .server else { return }
        if buf.kind == .channel, state == .connected {
            client.send("PART \(buf.name) :closed")
        }
        // Pick the next selection BEFORE mutating the array so SwiftUI
        // doesn't render a placeholder buffer for one frame. Prefer the
        // buffer immediately after the closed one; fall back to the one
        // before; fall back to first.
        let nextID: Buffer.ID? = {
            if selectedBufferID != id { return selectedBufferID }
            if i + 1 < buffers.count { return buffers[i + 1].id }
            if i > 0 { return buffers[i - 1].id }
            return nil
        }()
        buffers.remove(at: i)
        selectedBufferID = nextID ?? buffers.first?.id
    }

    func quickJoin(_ channel: String) {
        let name = channel.hasPrefix("#") ? channel : "#" + channel
        if state == .connected {
            client.send("JOIN \(name)")
        } else {
            appendError("Not connected — connect first.")
        }
    }

    /// Kick off a LIST against this network. `filter` is passed through as
    /// the LIST argument (e.g. ">5" on some daemons). Empty string = full
    /// list. `forceRefresh` wipes the local cache before querying so stale
    /// entries can't mask deletions upstream.
    func requestChannelList(filter: String = "", forceRefresh: Bool = false) {
        guard state == .connected else {
            appendError("Not connected — connect first.")
            return
        }
        if forceRefresh {
            channelList.clearCache()
        }
        channelList.begin()
        let trimmed = filter.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            client.send("LIST")
        } else {
            client.send("LIST \(trimmed)")
        }
    }

    func selectBuffer(_ id: Buffer.ID) {
        selectedBufferID = id
        if let i = buffers.firstIndex(where: { $0.id == id }) {
            buffers[i].unread = 0
        }
    }

    /// Wipe a buffer's rendered scrollback. UI-only — channel membership
    /// stays intact so the user keeps receiving fresh PRIVMSGs. Used by
    /// `/clear`. Resets the truncation-notice flag so the next overflow
    /// surfaces a fresh notice.
    func clearBufferLines(id: Buffer.ID) {
        guard let i = buffers.firstIndex(where: { $0.id == id }) else { return }
        buffers[i].lines.removeAll()
        buffers[i].truncationNoticeShown = false
    }

    /// Reset the unread badge on every buffer. Doesn't touch line content.
    /// Used by `/markread`.
    func markAllBuffersRead() {
        for i in buffers.indices {
            buffers[i].unread = 0
        }
    }

    /// Cycle the active buffer in the connection's list. Wraps at the
    /// edges. Used by `/next` and `/prev`.
    func cycleBuffer(forward: Bool) {
        guard !buffers.isEmpty else { return }
        let currentIdx = buffers.firstIndex(where: { $0.id == selectedBufferID }) ?? 0
        let next = forward
            ? (currentIdx + 1) % buffers.count
            : (currentIdx - 1 + buffers.count) % buffers.count
        selectBuffer(buffers[next].id)
    }

    /// Switch to a buffer by name (case-insensitive, exact > prefix > contains).
    /// Returns false if no match. Used by `/goto`.
    @discardableResult
    func selectBufferByName(_ name: String) -> Bool {
        let q = name.lowercased()
        let candidates = buffers
        if let exact = candidates.first(where: { $0.name.lowercased() == q }) {
            selectBuffer(exact.id); return true
        }
        if let pre = candidates.first(where: { $0.name.lowercased().hasPrefix(q) }) {
            selectBuffer(pre.id); return true
        }
        if let sub = candidates.first(where: { $0.name.lowercased().contains(q) }) {
            selectBuffer(sub.id); return true
        }
        return false
    }

    func applyAlertOptions(sound: Bool, dock: Bool, banner: Bool, highlight: Bool) {
        watchlist.playSound = sound
        watchlist.bounceDock = dock
        watchlist.systemNotifications = banner
        highlightOnOwnNick = highlight
    }

    /// Convenience used by the channel-mode UI. Sends a MODE line for the
    /// target channel and mode string, or no-op if not in a channel.
    func setMode(on channel: String, modes: String, arg: String? = nil) {
        guard state == .connected else { return }
        if let arg {
            client.send("MODE \(channel) \(modes) \(arg)")
        } else {
            client.send("MODE \(channel) \(modes)")
        }
    }

    // MARK: - Away

    /// Set or clear the away state on this network. Empty/nil reason clears.
    func setAway(reason: String?) {
        if let reason, !reason.trimmingCharacters(in: .whitespaces).isEmpty {
            isAway = true
            awayReason = reason
            client.send("AWAY :\(reason)")
            appendInfo("You are marked AWAY: \(reason)")
        } else {
            isAway = false
            awayReason = nil
            client.send("AWAY")
            appendInfo("You are no longer away.")
        }
        emit(.awayChanged(isAway: isAway, reason: awayReason))
    }

    // MARK: - State handling

    private func handleState(_ s: IRCConnectionState) {
        state = s
        let logCat = "IRC.\(displayName)"
        switch s {
        case .connecting:
            appendInfo("Connecting…")
            AppLog.shared.info("Connecting to \(profile.host):\(profile.port) (TLS=\(profile.useTLS))",
                              category: logCat)
        case .connected:
            appendInfo("TCP established. Authenticating…")
            AppLog.shared.info("TCP established; CAP/SASL handshake in progress.",
                              category: logCat)
        case .disconnected:
            appendInfo("Disconnected.")
            AppLog.shared.notice("Disconnected from \(profile.host).", category: logCat)
            haveRegisteredWatchlist = false
            watchlist.onDisconnected()
            // Drop any half-open BATCH/chathistory state so a reconnect
            // doesn't see ghosts left over from the previous session.
            openBatches.removeAll()
            chatHistoryFetched.removeAll()
            scheduleReconnectIfNeeded()
        case .failed(let err):
            appendError("Connection failed: \(err)")
            AppLog.shared.error("Connection failed: \(err)", category: logCat)
            haveRegisteredWatchlist = false
            watchlist.onDisconnected()
            openBatches.removeAll()
            chatHistoryFetched.removeAll()
            scheduleReconnectIfNeeded()
        }
        emit(.state(s))
    }

    private func scheduleReconnectIfNeeded() {
        if userInitiatedDisconnect { return }
        guard profile.autoReconnect else { return }
        reconnectAttempt = min(reconnectAttempt + 1, 6)
        let base: Double = [0, 2, 4, 8, 16, 30, 30][reconnectAttempt]
        let jitter = Double.random(in: 0.75...1.25)
        let delay = base * jitter

        appendInfo(String(format: "Reconnecting in %.1fs (attempt %d)…", delay, reconnectAttempt))

        reconnectTask?.cancel()
        // Capture the current connection identity so a delayed wake-up can
        // tell whether `self` is still the same logical connection (the
        // user might have disconnected and reconnected to a different
        // profile in the meantime, reusing the slot).
        let connID = id
        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            // Re-check cancellation on the same actor as the state we read,
            // so a disconnect issued during the sleep wins the race.
            await MainActor.run {
                guard let self else { return }
                if Task.isCancelled { return }
                guard self.id == connID else { return }
                if self.userInitiatedDisconnect { return }
                // Don't double-fire if disconnect+manual reconnect already
                // started a new attempt while we were sleeping.
                if self.state == .connecting || self.state == .connected { return }
                self.connect()
            }
        }
        reconnectTask = task
    }

    // MARK: - Message handling

    /// Most-recent `user@host` per nick on this network. Captured from every
    /// inbound IRC message that carries a prefix; consumed by BotEngine when
    /// it stamps a SeenEntry so the seen audit can show host changes.
    private var lastUserHostByNick: [String: String] = [:]

    /// When a /whois (or /whowas) is issued from a channel context, we
    /// stash the originating buffer ID here keyed by the target nick so
    /// the reply numerics can be mirrored back to that channel — the
    /// user doesn't have to switch to the server buffer just to see the
    /// answer to a question they asked from a channel right-click.
    /// Cleared when RPL_ENDOFWHOIS (318) / RPL_ENDOFWHOWAS (369) /
    /// ERR_NOSUCHNICK (401) / ERR_WASNOSUCHNICK (406) arrives.
    private var whoisOriginByNick: [String: Buffer.ID] = [:]

    /// Record the buffer the user issued /whois or /whowas from so the
    /// reply lands in the right place. Channel and query buffers are both
    /// valid origins; server-buffer requests fall through to the default
    /// "land in server buffer" behavior so no entry is needed for those.
    private func registerWhoisOrigin(target: String, selection: Buffer.ID?) {
        guard let sel = selection,
              let buf = buffers.first(where: { $0.id == sel }),
              buf.kind == .channel || buf.kind == .query else { return }
        let key = target.split(separator: " ").first.map(String.init)?.lowercased() ?? target.lowercased()
        whoisOriginByNick[key] = sel
    }

    /// Auto-WHOIS on new query opens — same registerWhoisOrigin pattern but
    /// the origin is the query buffer's own ID so the reply lands inside
    /// the conversation. Per-buffer log writes pick up the WHOIS lines for
    /// free.
    private func autoWhoisForQuery(_ nick: String, queryBufferID: Buffer.ID) {
        let key = nick.lowercased()
        whoisOriginByNick[key] = queryBufferID
        client.send("WHOIS \(nick)")
    }

    /// Read-only accessor for the captured user@host map. Returns nil when
    /// we haven't seen the nick send anything yet on this connection.
    func userHost(for nick: String) -> String? {
        lastUserHostByNick[nick.lowercased()]
    }

    private func handle(_ msg: IRCMessage) {
        emit(.inbound(msg))
        // Update the user@host map first so BotEngine sees the freshest
        // value when the same handle() call later emits a higher-level
        // event (.privmsg, .join, etc.) and the bot consults userHost(for:).
        if let prefix = msg.prefix,
           let bang = prefix.firstIndex(of: "!"),
           let nick = msg.nickFromPrefix {
            let userHost = String(prefix[prefix.index(after: bang)...])
            lastUserHostByNick[nick.lowercased()] = userHost
        }
        switch msg.command {
        case "PING":
            let token = msg.params.first ?? ""
            client.send("PONG :\(token)")
            return
        case "PRIVMSG":
            handlePrivmsg(msg, isNotice: false)
        case "NOTICE":
            handlePrivmsg(msg, isNotice: true)
        case "JOIN":
            handleJoin(msg)
        case "PART":
            handlePart(msg)
        case "QUIT":
            handleQuit(msg)
        case "NICK":
            handleNickChange(msg)
        case "TOPIC":
            handleTopic(msg)
        case "KICK":
            handleKick(msg)
        case "MODE":
            handleMode(msg)
        case "AWAY":
            handleAwayNotify(msg)
        case "ACCOUNT":
            handleAccountNotify(msg)
        case "CHGHOST":
            handleChgHost(msg)
        case "BATCH":
            handleBatch(msg)
        case "ERROR":
            let txt = msg.params.joined(separator: " ")
            appendError("ERROR: \(txt)")
        case "CAP", "AUTHENTICATE":
            logNumeric(msg)
        case "001":
            if msg.params.count >= 1 {
                self.nick = msg.params[0]
                emit(.ownNickChanged(self.nick))
            }
            logNumeric(msg)
            reconnectAttempt = 0
            nickCollisionRetries = 0
        case "301":
            // RPL_AWAYMSG — msg.params: [me, nick, "is away: <reason>"]
            if msg.params.count >= 3 {
                let who = msg.params[1]
                let why = msg.params[2]
                appendInfo("\(who) is away: \(why)")
                awayByNick[who.lowercased()] = why
            }
        case "305": // unaway
            isAway = false
            awayReason = nil
            emit(.awayChanged(isAway: false, reason: nil))
            logNumeric(msg)
        case "306": // away set
            isAway = true
            if awayReason == nil {
                awayReason = profile.realName.isEmpty ? "away" : "away"
            }
            emit(.awayChanged(isAway: true, reason: awayReason))
            logNumeric(msg)
        case "353":
            handleNames(msg)
        case "366":
            break
        case "332":
            if msg.params.count >= 3 {
                let chan = msg.params[1]
                let topic = msg.params[2]
                if let i = buffers.firstIndex(where: { $0.name == chan }) {
                    buffers[i].topic = topic
                    appendTo(bufferIndex: i, line: ChatLine(
                        timestamp: Date(),
                        kind: .topic(setter: nil),
                        text: "Topic: \(topic)"
                    ))
                    emit(.topic(channel: chan, topic: topic, setter: nil))
                }
            }
        case "005":
            let tokens = Array(msg.params.dropFirst().dropLast())
            watchlist.handleISupport(tokens)
            logNumeric(msg)
        case "376", "422":
            logNumeric(msg)
            if !haveRegisteredWatchlist {
                haveRegisteredWatchlist = true
                watchlist.onWelcomeCompleted()
                runPostWelcome()
                let caps = client.enabledCaps.sorted().joined(separator: ", ")
                AppLog.shared.info(
                    "Welcome completed on \(displayName); negotiated caps: [\(caps.isEmpty ? "none" : caps)]",
                    category: "IRC.\(displayName)")
            }
        case "372", "375", "371", "002", "003", "004", "250", "251", "252", "253", "254", "255", "265", "266":
            logNumeric(msg)
        case "303":
            let names = (msg.params.last ?? "")
                .split(separator: " ").map { String($0) }.filter { !$0.isEmpty }
            watchlist.handleISON(names)
        case "321":
            // RPL_LISTSTART — some daemons send it, some don't. Swallow either
            // way; we already flipped the loading flag when /LIST was issued.
            break
        case "322":
            // RPL_LIST — one row of the channel directory.
            channelList.append(from: msg)
        case "323":
            // RPL_LISTEND — the directory is complete.
            channelList.end()
        case "730":
            watchlist.handleMonitorOnline(monitorTargets(from: msg))
        case "731":
            watchlist.handleMonitorOffline(monitorTargets(from: msg))
        case "732", "733", "734":
            logNumeric(msg)
        case "900", "901", "902", "903", "904", "905", "906", "907":
            logNumeric(msg)
        case "433":
            // Cap retries — without this, the underscore tail grows forever
            // and we eventually trip the server's NICKLEN limit, generating
            // a fresh 432/433 cascade with no path to registration.
            nickCollisionRetries += 1
            if nickCollisionRetries > Self.maxNickCollisionRetries {
                appendError("Nickname and \(Self.maxNickCollisionRetries) fallbacks all in use. Disconnecting; pick a different nick in Setup.")
                userInitiatedDisconnect = true
                reconnectTask?.cancel()
                reconnectTask = nil
                client.disconnect()
                return
            }
            let alt = self.nick + "_"
            appendError("Nickname in use. Trying \(alt) (attempt \(nickCollisionRetries)/\(Self.maxNickCollisionRetries))")
            self.nick = alt
            client.send("NICK \(alt)")
        default:
            logNumeric(msg)
        }
    }

    /// Per-message timestamp source. Honours the IRCv3 `server-time` cap when
    /// the server tagged the line; falls back to the client's clock for
    /// untagged messages and locally-generated chat lines.
    private func messageTime(_ msg: IRCMessage) -> Date {
        msg.serverTime ?? Date()
    }

    /// IRCv3 AWAY notification (`away-notify` cap). The server pushes this
    /// inline whenever any visible user toggles their away state, so the
    /// client doesn't need to poll WHOIS to find out.
    /// Format: `:nick!user@host AWAY [:reason]` — empty trailing means back.
    private func handleAwayNotify(_ msg: IRCMessage) {
        guard let nick = msg.nickFromPrefix else { return }
        let key = nick.lowercased()
        if let reason = msg.params.first, !reason.isEmpty {
            awayByNick[key] = reason
        } else {
            awayByNick.removeValue(forKey: key)
        }
    }

    /// IRCv3 `account-notify`. `:nick!user@host ACCOUNT <name|*>` — `*` means
    /// the user logged out of services.
    private func handleAccountNotify(_ msg: IRCMessage) {
        guard let nick = msg.nickFromPrefix, let acct = msg.params.first else { return }
        let key = nick.lowercased()
        if acct == "*" {
            accountByNick.removeValue(forKey: key)
        } else {
            accountByNick[key] = acct
        }
    }

    /// IRCv3 CHGHOST. Server pushes when a user's user@host changes
    /// (typically a hostmask cloak being applied). We refresh the cached
    /// userhost so the seen tracker / WHOIS routing has the new value.
    private func handleChgHost(_ msg: IRCMessage) {
        guard let nick = msg.nickFromPrefix, msg.params.count >= 2 else { return }
        let user = msg.params[0]
        let host = msg.params[1]
        lastUserHostByNick[nick.lowercased()] = "\(user)@\(host)"
    }

    /// IRCv3 BATCH start/end. `+id <type> [params]` opens a batch; `-id`
    /// closes it. Messages within the batch carry an `@batch=id` tag; we
    /// surface the open batches so handlers can ask `msg.batchRef` and check
    /// `openBatches[ref]?.type` to decide presentation. Today we just bracket
    /// CHATHISTORY playbacks with an info line so the user sees the boundary.
    ///
    /// Robustness: a duplicate `+id` overwrites and logs a warning. An
    /// orphan `-id` (no matching `+id` ever seen) is ignored silently —
    /// they happen on flaky links and aren't actionable. The
    /// `openBatches` dict is also capped at 256 entries so a hostile or
    /// buggy server can't exhaust memory by opening batches forever.
    private func handleBatch(_ msg: IRCMessage) {
        guard let token = msg.params.first, !token.isEmpty else { return }
        if token.hasPrefix("+") {
            let id = String(token.dropFirst())
            guard !id.isEmpty else { return }
            let type = msg.params.count > 1 ? msg.params[1] : ""
            let extras = Array(msg.params.dropFirst(2))
            if openBatches[id] != nil {
                AppLog.shared.warn("Duplicate BATCH +\(id); replacing prior entry.",
                                   category: "IRC.\(displayName)")
            }
            // Cap before insert so the dict never exceeds the limit.
            if openBatches.count >= Self.maxOpenBatches {
                AppLog.shared.warn("BATCH cap reached (\(Self.maxOpenBatches)); evicting oldest.",
                                   category: "IRC.\(displayName)")
                if let drop = openBatches.keys.first { openBatches.removeValue(forKey: drop) }
            }
            openBatches[id] = BatchInfo(id: id, type: type, params: extras)
            if type == "chathistory", let chan = extras.first,
               let i = buffers.firstIndex(where: { $0.name == chan }) {
                appendTo(bufferIndex: i, line: ChatLine(
                    timestamp: messageTime(msg),
                    kind: .info,
                    text: "— Replaying recent history —"))
            }
        } else if token.hasPrefix("-") {
            let id = String(token.dropFirst())
            if let info = openBatches.removeValue(forKey: id), info.type == "chathistory",
               let chan = info.params.first,
               let i = buffers.firstIndex(where: { $0.name == chan }) {
                appendTo(bufferIndex: i, line: ChatLine(
                    timestamp: Date(),
                    kind: .info,
                    text: "— Live —"))
            }
            // Orphan `-id` (no matching `+id`) is silently ignored — flaky
            // links produce them and there's nothing the user can do.
        }
    }

    /// Cap on simultaneously-open BATCH ids. Keeps a misbehaving server
    /// from accumulating dictionary entries indefinitely.
    private static let maxOpenBatches = 256

    /// Append the saved history for `name` into `buffers[i]`, bracketed by
    /// "previous session" / "live" info markers. No-op when there's nothing
    /// in the pending history map for that name. The bracket markers help
    /// the user mentally separate stale lines from new traffic — without
    /// them the buffer reads as if all the history just arrived live.
    private func replayHistoryIntoBuffer(at i: Int, name: String) {
        guard let lines = pendingRestoreHistory[name], !lines.isEmpty else { return }
        guard i < buffers.count else { return }
        let topMarker = ChatLine(
            timestamp: lines.first?.timestamp ?? Date(),
            kind: .info,
            text: "── \(lines.count) lines from previous session ──")
        buffers[i].appendLine(topMarker)
        for line in lines {
            buffers[i].appendLine(line)
        }
        let endMarker = ChatLine(
            timestamp: Date(),
            kind: .info,
            text: "── live ──")
        buffers[i].appendLine(endMarker)
    }

    /// Issue a CHATHISTORY request for a channel we just joined. No-op when
    /// the cap wasn't granted, when the request was already issued this
    /// session, or when the buffer somehow doesn't exist. Servers that don't
    /// know CHATHISTORY will just NAK the cap and we never get here.
    private func requestChatHistory(for channel: String) {
        let key = channel.lowercased()
        guard !chatHistoryFetched.contains(key) else { return }
        let caps = client.enabledCaps
        guard caps.contains("chathistory") || caps.contains("draft/chathistory") else { return }
        chatHistoryFetched.insert(key)
        client.send("CHATHISTORY LATEST \(channel) * \(chatHistoryLimit)")
    }

    private func monitorTargets(from msg: IRCMessage) -> [String] {
        guard let payload = msg.params.last else { return [] }
        return payload.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func handlePrivmsg(_ msg: IRCMessage, isNotice: Bool) {
        guard msg.params.count >= 2 else { return }
        let target = msg.params[0]
        var text = msg.params[1]
        let from = msg.nickFromPrefix ?? msg.prefix ?? "?"
        let fullPrefix = msg.prefix ?? from
        let lineTime = messageTime(msg)

        // Drop the server's echo of our own PRIVMSG when the `echo-message`
        // cap is enabled — we already optimistically appended a local line in
        // sendInput. Real backlog (BATCH/CHATHISTORY) carries a batchRef and
        // is intentionally allowed through so users can replay history.
        if hasEchoMessageCap,
           from.lowercased() == self.nick.lowercased(),
           msg.batchRef == nil {
            return
        }

        // Track sender's services account when account-tag rides on the line.
        if let acct = msg.account {
            accountByNick[from.lowercased()] = acct
        }

        let isCTCP = text.hasPrefix("\u{01}") && text.hasSuffix("\u{01}") && text.count >= 2

        // Ignore filter — silently drop matching messages (we still emit an
        // event so future bot scripts see the drop; core UI is unaffected).
        if ignoreMatches(from: from, fullPrefix: fullPrefix,
                         isNotice: isNotice, isCTCP: isCTCP) {
            emit(.ignoredMessage(from: from, target: target))
            return
        }

        if !isNotice {
            watchlist.handleObservedActivity(nick: from, reason: "message")
        }

        // CTCP handling (everything wrapped in \u0001 except ACTION).
        if isCTCP {
            let body = String(text.dropFirst().dropLast())
            let (cmd, args) = splitCTCP(body)
            emit(.ctcpRequest(from: from, target: target, command: cmd, args: args))

            if cmd.uppercased() == "ACTION" {
                // Fall through to the action-rendering path below.
                text = "\u{01}ACTION \(args)\u{01}"
            } else if cmd.uppercased() == "DCC", !isNotice,
                      let svc = dcc,
                      svc.handleIncomingDCC(connection: self, from: from, args: args) {
                // DCC offer consumed; don't echo as a raw CTCP request.
                return
            } else {
                // Respond to a CTCP request (NOT a CTCP reply we received via
                // NOTICE). Requests come as PRIVMSG — NOTICEs carrying \u0001
                // are replies and must not trigger another reply.
                if !isNotice, ctcpRepliesEnabled {
                    sendCTCPReply(to: from, command: cmd, args: args)
                }
                // Log requests/replies to server buffer for visibility, and
                // also mirror into the query buffer for `from` when one is
                // open — so `/ctcp nick VERSION` shows its answer alongside
                // the conversation, not just in the server log.
                let kindLabel = isNotice ? "CTCP reply" : "CTCP request"
                let info = "\(kindLabel) \(cmd) from \(from): \(args)"
                appendInfo(info)
                if let qIdx = buffers.firstIndex(where: {
                    $0.kind == .query && $0.name.caseInsensitiveCompare(from) == .orderedSame
                }) {
                    appendTo(bufferIndex: qIdx, line: ChatLine(
                        timestamp: lineTime,
                        kind: .info,
                        text: info
                    ))
                }
                return
            }
        }

        let isToSelf = target.lowercased() == self.nick.lowercased()
        let bufferName = isToSelf ? from : target
        let kind: Buffer.Kind = target.hasPrefix("#") ? .channel : .query

        let plainForMatch = IRCFormatter.stripCodes(text)
        let mention = !isNotice
            && from.lowercased() != self.nick.lowercased()
            && highlightOnOwnNick
            && Self.containsOwnNick(self.nick, in: plainForMatch)

        // HighlightRule evaluation. Skips our own lines (we already know what
        // we typed). Runs on both PRIVMSG and NOTICE so users can highlight
        // NickServ notices, server notices, etc.
        let hits: [HighlightMatcher.Hit]
        if from.lowercased() != self.nick.lowercased() {
            hits = highlightMatcher.evaluate(
                rules: highlightRules,
                text: text,
                networkID: profile.id)
        } else {
            hits = []
        }
        let firstHit = hits.first
        let hitRuleID = firstHit?.rule.id
        let hitRanges = firstHit?.ranges ?? []

        // CTCP ACTION rendering
        if text.hasPrefix("\u{01}ACTION "), text.hasSuffix("\u{01}") {
            text = String(text.dropFirst(8).dropLast())
            let r = indexOfOrCreateBufferTracked(name: bufferName, kind: kind)
            let bIdx = r.index
            if r.created, kind == .query {
                autoWhoisForQuery(bufferName, queryBufferID: buffers[bIdx].id)
            }
            appendTo(bufferIndex: bIdx, line: ChatLine(
                timestamp: lineTime,
                kind: .action(nick: from),
                text: text,
                isMention: mention,
                highlightRuleID: hitRuleID,
                highlightRanges: hitRanges
            ))
            markUnread(at: bIdx)
            emit(.privmsg(from: from, target: bufferName, text: text, isAction: true, isMention: mention))
            if mention {
                watchlist.fireHighlightAlert(nick: from, channel: bufferName, text: "* \(from) \(IRCFormatter.stripCodes(text))")
            }
            fireHighlightHits(hits, from: from, channel: bufferName, plain: plainForMatch)
            maybeSendAwayAutoReply(to: from, target: target, isNotice: false)
            return
        }

        let r = indexOfOrCreateBufferTracked(name: bufferName, kind: kind)
        let bIdx = r.index
        // Auto-WHOIS the first time someone PMs us (or we open a /msg)
        // so the user immediately sees who they're talking to. The reply
        // routes back into this same query buffer via whoisOriginByNick.
        if r.created, kind == .query {
            autoWhoisForQuery(bufferName, queryBufferID: buffers[bIdx].id)
        }
        if isNotice {
            appendTo(bufferIndex: bIdx, line: ChatLine(
                timestamp: lineTime,
                kind: .notice(from: from),
                text: text,
                highlightRuleID: hitRuleID,
                highlightRanges: hitRanges
            ))
            emit(.notice(from: from, target: bufferName, text: text))
        } else {
            // Self-echoes (echo-message cap is off, but we still see our own
            // PRIVMSGs from CHATHISTORY replays carrying our nick): mark
            // `isSelf` so the row renders with the same chrome as locally
            // echoed lines.
            let isSelf = from.lowercased() == self.nick.lowercased()
            appendTo(bufferIndex: bIdx, line: ChatLine(
                timestamp: lineTime,
                kind: .privmsg(nick: from, isSelf: isSelf),
                text: text,
                isMention: mention,
                highlightRuleID: hitRuleID,
                highlightRanges: hitRanges
            ))
            emit(.privmsg(from: from, target: bufferName, text: text, isAction: false, isMention: mention))
        }
        markUnread(at: bIdx)

        if mention {
            watchlist.fireHighlightAlert(nick: from, channel: bufferName, text: IRCFormatter.stripCodes(text))
        }
        fireHighlightHits(hits, from: from, channel: bufferName, plain: plainForMatch)

        // Away auto-reply to direct PMs (not notices, not channel traffic).
        if !isNotice {
            maybeSendAwayAutoReply(to: from, target: target, isNotice: false)
        }
    }

    private func splitCTCP(_ body: String) -> (String, String) {
        if let spaceIdx = body.firstIndex(of: " ") {
            return (String(body[..<spaceIdx]), String(body[body.index(after: spaceIdx)...]))
        }
        return (body, "")
    }

    private func handleDCCCommand(_ rest: String) {
        guard let svc = dcc else {
            appendError("DCC service unavailable.")
            return
        }
        let bits = rest.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true).map(String.init)
        guard let subRaw = bits.first else {
            appendInfo("Usage: /dcc send <nick> [path]  |  /dcc chat <nick>")
            return
        }
        let sub = subRaw.lowercased()
        switch sub {
        case "send":
            guard bits.count >= 2 else {
                appendInfo("Usage: /dcc send <nick> [path]")
                return
            }
            let nick = bits[1]
            let providedPath = bits.count >= 3 ? bits[2].trimmingCharacters(in: .whitespaces) : ""
            if !providedPath.isEmpty {
                let url = URL(fileURLWithPath: (providedPath as NSString).expandingTildeInPath)
                guard FileManager.default.fileExists(atPath: url.path) else {
                    appendError("File not found: \(url.path)")
                    return
                }
                svc.offerSend(to: nick, fileURL: url, on: self)
            } else {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = false
                panel.canChooseFiles = true
                panel.allowsMultipleSelection = false
                panel.begin { [weak self] resp in
                    guard let self, resp == .OK, let url = panel.url else { return }
                    Task { @MainActor in
                        svc.offerSend(to: nick, fileURL: url, on: self)
                    }
                }
            }
        case "chat":
            guard bits.count >= 2 else {
                appendInfo("Usage: /dcc chat <nick>")
                return
            }
            svc.offerChat(to: bits[1], on: self)
        case "list":
            chatModelShowDCC()
        default:
            appendInfo("Usage: /dcc send <nick> [path]  |  /dcc chat <nick>  |  /dcc list")
        }
    }

    private func chatModelShowDCC() {
        dcc?.chatModel?.showDCC = true
    }

    private func sendCTCPReply(to nick: String, command: String, args: String) {
        let up = command.uppercased()
        let reply: String?
        switch up {
        case "VERSION":
            reply = "VERSION \(ctcpVersionString)"
        case "PING":
            // Echo back the args verbatim (usually a timestamp).
            reply = args.isEmpty ? "PING" : "PING \(args)"
        case "TIME":
            let df = DateFormatter()
            df.dateFormat = "EEE MMM d HH:mm:ss yyyy"
            df.locale = Locale(identifier: "en_US_POSIX")
            reply = "TIME \(df.string(from: Date()))"
        case "FINGER":
            reply = "FINGER \(effectiveProfile.realName.isEmpty ? "PurpleIRC user" : effectiveProfile.realName)"
        case "SOURCE":
            reply = "SOURCE https://github.com/bronty13/PhantomLives"
        case "USERINFO":
            reply = "USERINFO \(effectiveProfile.realName.isEmpty ? effectiveProfile.nick : effectiveProfile.realName)"
        case "CLIENTINFO":
            reply = "CLIENTINFO ACTION CLIENTINFO FINGER PING SOURCE TIME USERINFO VERSION"
        default:
            reply = nil
        }
        guard let body = reply else { return }
        client.send("NOTICE \(nick) :\u{01}\(body)\u{01}")
    }

    private func maybeSendAwayAutoReply(to from: String, target: String, isNotice: Bool) {
        guard isAway, autoReplyWhenAway, !isNotice else { return }
        // Only for direct PMs (target is our nick), not channel traffic.
        guard target.lowercased() == self.nick.lowercased() else { return }
        guard !from.isEmpty, from.lowercased() != self.nick.lowercased() else { return }
        let now = Date()
        let key = from.lowercased()
        if let last = lastAwayReplyAt[key],
           now.timeIntervalSince(last) < Self.awayReplyInterval { return }
        lastAwayReplyAt[key] = now
        // Bound dictionary growth: a long session in a busy network would
        // otherwise accumulate one entry per unique sender forever. Drop
        // entries older than the throttle window when the dict gets large.
        if lastAwayReplyAt.count > 1024 {
            let cutoff = now.addingTimeInterval(-Self.awayReplyInterval)
            lastAwayReplyAt = lastAwayReplyAt.filter { $0.value > cutoff }
        }
        let msg = awayAutoReply.isEmpty ? "I am away." : awayAutoReply
        client.send("NOTICE \(from) :[away] \(msg)")
    }

    /// True when the sender matches any configured ignore entry, honoring
    /// the entry's per-scope toggles (CTCP / notices) and falling back to
    /// "match the nick" when no full prefix is available.
    private func ignoreMatches(from: String, fullPrefix: String,
                               isNotice: Bool, isCTCP: Bool) -> Bool {
        guard !ignoreMatchers.isEmpty else { return false }
        for e in ignoreMatchers {
            let mask = e.mask.trimmingCharacters(in: .whitespaces)
            if mask.isEmpty { continue }
            if !glob(mask.lowercased(), matches: fullPrefix.lowercased())
                && !glob(mask.lowercased(), matches: from.lowercased()) { continue }
            if isCTCP && !e.ignoreCTCP { continue }
            if isNotice && !e.ignoreNotices { continue }
            return true
        }
        return false
    }

    /// Simple glob matcher — supports `*` (any run) and `?` (single char).
    /// Case-insensitive (caller must have already lowercased).
    private func glob(_ pattern: String, matches text: String) -> Bool {
        let p = Array(pattern); let t = Array(text)
        func m(_ pi: Int, _ ti: Int) -> Bool {
            if pi == p.count { return ti == t.count }
            let pc = p[pi]
            if pc == "*" {
                if pi + 1 == p.count { return true }
                var k = ti
                while k <= t.count {
                    if m(pi + 1, k) { return true }
                    k += 1
                }
                return false
            }
            if ti == t.count { return false }
            if pc == "?" || pc == t[ti] { return m(pi + 1, ti + 1) }
            return false
        }
        return m(0, 0)
    }

    /// Fire per-rule alerts for every matched HighlightRule. Uses the rule's
    /// own playSound/bounceDock/systemNotify toggles, not the watchlist's.
    private func fireHighlightHits(_ hits: [HighlightMatcher.Hit],
                                   from: String,
                                   channel: String,
                                   plain: String) {
        guard !hits.isEmpty else { return }
        for hit in hits {
            watchlist.fireRuleAlert(
                rule: hit.rule,
                from: from,
                channel: channel,
                text: plain,
                soundName: highlightSoundName
            )
        }
    }

    private static func containsOwnNick(_ nick: String, in text: String) -> Bool {
        guard !nick.isEmpty else { return false }
        let lowerText = text.lowercased()
        let lowerNick = nick.lowercased()
        var search = lowerText.startIndex
        while search < lowerText.endIndex,
              let r = lowerText.range(of: lowerNick, range: search..<lowerText.endIndex) {
            let before = r.lowerBound == lowerText.startIndex ? nil : lowerText[lowerText.index(before: r.lowerBound)]
            let after = r.upperBound == lowerText.endIndex ? nil : lowerText[r.upperBound]
            if !isNickChar(before) && !isNickChar(after) { return true }
            search = lowerText.index(after: r.lowerBound)
        }
        return false
    }

    private static func isNickChar(_ c: Character?) -> Bool {
        guard let c else { return false }
        if c.isLetter || c.isNumber { return true }
        return "-_[]{}\\|^".contains(c)
    }

    private func handleJoin(_ msg: IRCMessage) {
        guard let chan = msg.params.first, let who = msg.nickFromPrefix else { return }
        // extended-join: `:nick!u@h JOIN <channel> <account|*> :<realname>`
        // Persist the account so replies can reference it (e.g. highlight
        // rules matching on services account, not just nick).
        if msg.params.count >= 3, msg.params[1] != "*" {
            accountByNick[who.lowercased()] = msg.params[1]
        }
        let bIdx = indexOfOrCreateBuffer(name: chan, kind: .channel)
        let isSelf = who.lowercased() == self.nick.lowercased()
        let when = messageTime(msg)
        if isSelf {
            appendTo(bufferIndex: bIdx, line: ChatLine(
                timestamp: when, kind: .info, text: "You joined \(chan)"))
            selectedBufferID = buffers[bIdx].id
            // Replay missed messages from the server's CHATHISTORY store
            // when the cap is live. No-op if the cap wasn't granted.
            requestChatHistory(for: chan)
        } else {
            watchlist.handleObservedActivity(nick: who, reason: "JOIN \(chan)")
            appendTo(bufferIndex: bIdx, line: ChatLine(
                timestamp: when,
                kind: .join(nick: who),
                text: "\(who) joined"
            ))
            if !buffers[bIdx].users.contains(who) {
                buffers[bIdx].users.append(who)
                buffers[bIdx].users.sort()
            }
        }
        emit(.join(nick: who, channel: chan, isSelf: isSelf))
    }

    private func handlePart(_ msg: IRCMessage) {
        guard let chan = msg.params.first, let who = msg.nickFromPrefix else { return }
        let reason = msg.params.count > 1 ? msg.params[1] : nil
        guard let bIdx = buffers.firstIndex(where: { $0.name == chan }) else { return }
        let isSelf = who.lowercased() == self.nick.lowercased()
        if isSelf {
            appendTo(bufferIndex: bIdx, line: ChatLine(
                timestamp: Date(), kind: .info, text: "You left \(chan)"))
            buffers[bIdx].users.removeAll()
            buffers[bIdx].userModes.removeAll()
        } else {
            appendTo(bufferIndex: bIdx, line: ChatLine(
                timestamp: Date(),
                kind: .part(nick: who, reason: reason),
                text: "\(who) left" + (reason.map { " (\($0))" } ?? "")
            ))
            buffers[bIdx].users.removeAll(where: { $0 == who })
            buffers[bIdx].userModes.removeValue(forKey: who.lowercased())
        }
        emit(.part(nick: who, channel: chan, reason: reason, isSelf: isSelf))
    }

    private func handleQuit(_ msg: IRCMessage) {
        guard let who = msg.nickFromPrefix else { return }
        let reason = msg.params.first
        let lower = who.lowercased()
        for i in buffers.indices where buffers[i].users.contains(who) {
            buffers[i].users.removeAll(where: { $0 == who })
            buffers[i].userModes.removeValue(forKey: lower)
            appendTo(bufferIndex: i, line: ChatLine(
                timestamp: Date(),
                kind: .quit(nick: who, reason: reason),
                text: "\(who) quit" + (reason.map { " (\($0))" } ?? "")
            ))
        }
        emit(.quit(nick: who, reason: reason))
    }

    private func handleNickChange(_ msg: IRCMessage) {
        guard let old = msg.nickFromPrefix, let new = msg.params.first else { return }
        let isSelf = old.lowercased() == self.nick.lowercased()
        if isSelf {
            self.nick = new
            emit(.ownNickChanged(new))
        }
        emit(.nickChanged(old: old, new: new, isSelf: isSelf))
        let oldKey = old.lowercased()
        let newKey = new.lowercased()
        for i in buffers.indices {
            if let u = buffers[i].users.firstIndex(of: old) {
                buffers[i].users[u] = new
                buffers[i].users.sort()
                // Carry the user's op/voice flags forward to the new nick.
                if let modes = buffers[i].userModes.removeValue(forKey: oldKey) {
                    buffers[i].userModes[newKey] = modes
                }
                appendTo(bufferIndex: i, line: ChatLine(
                    timestamp: Date(),
                    kind: .nick(old: old, new: new),
                    text: "\(old) is now known as \(new)"
                ))
            }
        }
    }

    private func handleTopic(_ msg: IRCMessage) {
        guard msg.params.count >= 2 else { return }
        let chan = msg.params[0]
        let topic = msg.params[1]
        let who = msg.nickFromPrefix
        guard let i = buffers.firstIndex(where: { $0.name == chan }) else { return }
        buffers[i].topic = topic
        appendTo(bufferIndex: i, line: ChatLine(
            timestamp: Date(),
            kind: .topic(setter: who),
            text: (who.map { "\($0) set topic: " } ?? "Topic: ") + topic
        ))
        emit(.topic(channel: chan, topic: topic, setter: who))
    }

    private func handleKick(_ msg: IRCMessage) {
        guard msg.params.count >= 2 else { return }
        let chan = msg.params[0]
        let target = msg.params[1]
        let reason = msg.params.count > 2 ? msg.params[2] : nil
        let by = msg.nickFromPrefix ?? "?"
        guard let i = buffers.firstIndex(where: { $0.name == chan }) else { return }
        buffers[i].users.removeAll(where: { $0 == target })
        buffers[i].userModes.removeValue(forKey: target.lowercased())
        let text = "\(target) was kicked by \(by)" + (reason.map { " (\($0))" } ?? "")
        appendTo(bufferIndex: i, line: ChatLine(
            timestamp: Date(), kind: .info, text: text))
    }

    /// Surface the mode change in the affected channel's buffer AND mutate
    /// the channel's `userModes` map so the user list refreshes its op /
    /// voice glyphs live. Also handles compound flag strings like `+o-v` by
    /// walking one character at a time.
    private func handleMode(_ msg: IRCMessage) {
        guard msg.params.count >= 2 else { return }
        let target = msg.params[0]
        let flags = msg.params[1]
        let args = Array(msg.params.dropFirst(2))
        let modeLine = msg.params.dropFirst().joined(separator: " ")
        let by = msg.nickFromPrefix ?? "server"

        guard let i = buffers.firstIndex(where: { $0.name == target }) else {
            appendInfo("\(by) sets mode \(target) \(modeLine)")
            return
        }
        appendTo(bufferIndex: i, line: ChatLine(
            timestamp: Date(), kind: .info, text: "\(by) sets mode \(modeLine)"))
        applyUserModeChanges(channelIndex: i, flags: flags, args: args)
    }

    /// Walk `flags` once, consuming args for modes that take them, and update
    /// `buffers[i].userModes`. Only the five privilege letters (q/a/o/h/v)
    /// are tracked; everything else is skipped (with its arg eaten when the
    /// RFC says that mode carries an argument) so we don't misalign.
    private func applyUserModeChanges(channelIndex i: Int, flags: String, args: [String]) {
        /// User-privilege modes — the only ones we actually track on users.
        let userModes: Set<Character> = ["q", "a", "o", "h", "v"]
        /// Modes that always consume an argument (both setting and clearing).
        /// Includes user modes plus bans / exceptions / invites / channel key.
        let alwaysConsume: Set<Character> = userModes.union(["b", "e", "I", "k"])
        /// Modes that consume an argument only when being set (`l` = limit).
        let consumeOnSet: Set<Character> = ["l"]

        var sign: Character = "+"
        var argIdx = 0
        for c in flags {
            if c == "+" || c == "-" { sign = c; continue }

            let takesArg: Bool
            if alwaysConsume.contains(c) { takesArg = true }
            else if consumeOnSet.contains(c) { takesArg = (sign == "+") }
            else { takesArg = false }

            let arg: String? = {
                guard takesArg, argIdx < args.count else { return nil }
                defer { argIdx += 1 }
                return args[argIdx]
            }()

            guard userModes.contains(c), let nick = arg else { continue }
            let key = nick.lowercased()
            if sign == "+" {
                buffers[i].userModes[key, default: []].insert(c)
            } else {
                buffers[i].userModes[key]?.remove(c)
                if buffers[i].userModes[key]?.isEmpty == true {
                    buffers[i].userModes.removeValue(forKey: key)
                }
            }
        }
    }

    private func handleNames(_ msg: IRCMessage) {
        guard msg.params.count >= 4 else { return }
        let chan = msg.params[2]
        let names = msg.params[3].split(separator: " ").map { String($0) }
        guard let i = buffers.firstIndex(where: { $0.name == chan }) else { return }

        // Parse each entry: leading symbols (@+%&~) each map to a user-mode
        // letter we stash on the buffer, the rest is the clean nick. A user
        // can wear multiple prefixes (e.g. "@+alice" = op + voice).
        var existing = Set(buffers[i].users)
        for raw in names {
            var rest = raw
            var modes: Set<Character> = []
            while let first = rest.first, let letter = Buffer.modeLetter(fromSymbol: first) {
                modes.insert(letter)
                rest.removeFirst()
            }
            guard !rest.isEmpty else { continue }
            existing.insert(rest)
            if !modes.isEmpty {
                buffers[i].userModes[rest.lowercased(), default: []].formUnion(modes)
            }
        }
        buffers[i].users = Array(existing).sorted()
    }

    private func logNumeric(_ msg: IRCMessage) {
        let i = idx(of: ensureServerBufferID())
        let text = msg.params.dropFirst().joined(separator: " ")
        let kind: ChatLine.Kind = (msg.command == "372" || msg.command == "375" || msg.command == "376") ? .motd : .info
        appendTo(bufferIndex: i, line: ChatLine(
            timestamp: Date(),
            kind: kind,
            text: text.isEmpty ? msg.raw : text
        ))

        // WHOIS-family replies route to up to three places so the user sees
        // the answer wherever they were when they asked it:
        //   1. Server buffer (always — done above).
        //   2. Query buffer for the target nick if one is open.
        //   3. The channel buffer the request was issued from, when the
        //      right-click happened in a channel user list.
        if Self.whoisNumerics.contains(msg.command),
           msg.params.count >= 2 {
            let targetNick = msg.params[1]
            let key = targetNick.lowercased()
            let line = ChatLine(
                timestamp: Date(),
                kind: kind,
                text: text.isEmpty ? msg.raw : text
            )
            // Query buffer mirror.
            if let qIdx = buffers.firstIndex(where: {
                $0.kind == .query && $0.name.caseInsensitiveCompare(targetNick) == .orderedSame
            }) {
                appendTo(bufferIndex: qIdx, line: line)
            }
            // Originating channel mirror.
            if let originID = whoisOriginByNick[key],
               let originIdx = buffers.firstIndex(where: { $0.id == originID }) {
                appendTo(bufferIndex: originIdx, line: line)
            }
            // Clear the origin record once the reply is complete so a
            // later /whois from a different buffer doesn't get its
            // answer routed to the wrong channel.
            if Self.whoisEndNumerics.contains(msg.command) {
                whoisOriginByNick.removeValue(forKey: key)
            }
        }
    }

    /// End-of-reply numerics — clear the whois origin record once any of
    /// these arrives so a stale entry doesn't redirect a later request.
    private static let whoisEndNumerics: Set<String> = [
        "318",  // RPL_ENDOFWHOIS
        "369",  // RPL_ENDOFWHOWAS
        "401",  // ERR_NOSUCHNICK
        "406",  // ERR_WASNOSUCHNICK
    ]

    /// Numerics emitted in response to WHOIS (and the "no such nick" reply).
    /// Each of these has the queried nick at params[1], so we can reliably
    /// route them to a matching query buffer if the user has one open.
    private static let whoisNumerics: Set<String> = [
        // WHOIS replies
        "311", "312", "313", "314", "315", "317", "318", "319",
        "330", "338", "378", "379", "671",
        // WHOWAS replies
        "369", "406",
        // Generic "no such nick" — routes back to whatever nick prompted it
        "401"
    ]

    // MARK: - Commands

    private func handleCommand(_ raw: String, selection: Buffer.ID?) {
        var parts = raw.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
        guard !parts.isEmpty else { return }
        let cmd = parts.removeFirst().lowercased()
        let rest = parts.first ?? ""

        func currentBufferName() -> String? {
            guard let id = selection, let buf = buffers.first(where: { $0.id == id }) else { return nil }
            return buf.kind == .server ? nil : buf.name
        }

        switch cmd {
        case "disconnect", "quit":
            userInitiatedDisconnect = true
            reconnectTask?.cancel()
            reconnectTask = nil
            if rest.isEmpty { client.disconnect() } else { client.disconnect(quitMessage: rest) }
        case "connect":
            connect()
        case "join", "j":
            let target = rest.trimmingCharacters(in: .whitespaces)
            guard !target.isEmpty else { return }
            client.send("JOIN \(target)")
        case "part":
            let bits = rest.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
            let target = bits.first ?? currentBufferName() ?? ""
            let reason = bits.count > 1 ? bits[1] : nil
            guard !target.isEmpty else { return }
            if let r = reason { client.send("PART \(target) :\(r)") }
            else { client.send("PART \(target)") }
        case "msg":
            let bits = rest.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
            guard bits.count == 2 else { return }
            let target = bits[0]; let text = bits[1]
            client.send("PRIVMSG \(target) :\(text)")
            let kindToCreate: Buffer.Kind = target.hasPrefix("#") ? .channel : .query
            let result = indexOfOrCreateBufferTracked(name: target, kind: kindToCreate)
            appendTo(bufferIndex: result.index, line: ChatLine(
                timestamp: Date(),
                kind: .privmsg(nick: nick, isSelf: true),
                text: text))
            selectedBufferID = buffers[result.index].id
            // Auto-WHOIS on /msg-spawned queries — same UX as a /query.
            if result.created, kindToCreate == .query {
                autoWhoisForQuery(target, queryBufferID: buffers[result.index].id)
            }
        case "query":
            let target = rest.trimmingCharacters(in: .whitespaces)
            guard !target.isEmpty else { return }
            let kindToCreate: Buffer.Kind = target.hasPrefix("#") ? .channel : .query
            let result = indexOfOrCreateBufferTracked(name: target, kind: kindToCreate)
            selectedBufferID = buffers[result.index].id
            if result.created, kindToCreate == .query {
                autoWhoisForQuery(target, queryBufferID: buffers[result.index].id)
            }
        case "me":
            guard let target = currentBufferName(), !rest.isEmpty else { return }
            let ctcp = "\u{01}ACTION \(rest)\u{01}"
            client.send("PRIVMSG \(target) :\(ctcp)")
            if let bIdx = buffers.firstIndex(where: { $0.name == target }) {
                appendTo(bufferIndex: bIdx, line: ChatLine(
                    timestamp: Date(), kind: .action(nick: nick), text: rest))
            }
        case "nick":
            guard !rest.isEmpty else { return }
            client.send("NICK \(rest)")
        case "topic":
            guard let target = currentBufferName() else { return }
            if rest.isEmpty { client.send("TOPIC \(target)") }
            else { client.send("TOPIC \(target) :\(rest)") }
        case "raw", "quote":
            client.send(rest)
        case "close":
            if let sel = selection { closeBuffer(id: sel) }
        case "names":
            if let target = currentBufferName() { client.send("NAMES \(target)") }
        case "whois":
            guard !rest.isEmpty else { return }
            registerWhoisOrigin(target: rest, selection: selection)
            client.send("WHOIS \(rest)")
        case "whowas":
            guard !rest.isEmpty else { return }
            registerWhoisOrigin(target: rest, selection: selection)
            client.send("WHOWAS \(rest)")
        case "away":
            setAway(reason: rest.trimmingCharacters(in: .whitespaces).isEmpty ? nil : rest)
        case "back":
            setAway(reason: nil)
        case "op", "deop", "voice", "devoice":
            guard let chan = currentBufferName(), chan.hasPrefix("#"),
                  !rest.isEmpty else { return }
            let mode: String = {
                switch cmd {
                case "op": return "+o"
                case "deop": return "-o"
                case "voice": return "+v"
                case "devoice": return "-v"
                default: return ""
                }
            }()
            client.send("MODE \(chan) \(mode) \(rest)")
        case "kick":
            guard let chan = currentBufferName(), chan.hasPrefix("#"),
                  !rest.isEmpty else { return }
            let bits = rest.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
            let who = bits[0]
            if bits.count > 1 {
                client.send("KICK \(chan) \(who) :\(bits[1])")
            } else {
                client.send("KICK \(chan) \(who)")
            }
        case "ban":
            guard let chan = currentBufferName(), chan.hasPrefix("#"),
                  !rest.isEmpty else { return }
            client.send("MODE \(chan) +b \(rest)")
        case "unban":
            guard let chan = currentBufferName(), chan.hasPrefix("#"),
                  !rest.isEmpty else { return }
            client.send("MODE \(chan) -b \(rest)")
        case "mode":
            if rest.isEmpty, let chan = currentBufferName() { client.send("MODE \(chan)") }
            else { client.send("MODE \(rest)") }
        case "ctcp":
            let bits = rest.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
            guard bits.count >= 2 else { return }
            let target = bits[0]
            let body = bits[1]
            client.send("PRIVMSG \(target) :\u{01}\(body)\u{01}")
        case "dcc":
            handleDCCCommand(rest)
        case "reconnect":
            // Disconnect and immediately reconnect this network. Bypasses
            // the auto-reconnect timer so the user gets a fresh attempt
            // right now without waiting on backoff. We disconnect with a
            // recognizable QUIT reason so server-side observers see the
            // intent.
            appendInfo("Reconnect requested.")
            // Avoid scheduleReconnectIfNeeded firing on top of us — set
            // the flag, disconnect, then clear it before kicking a fresh
            // connect.
            userInitiatedDisconnect = true
            reconnectTask?.cancel(); reconnectTask = nil
            client.disconnect(quitMessage: "Reconnecting")
            Task { @MainActor [weak self] in
                // Brief pause so the cancel propagates and the OS sees
                // the close before we open a new socket.
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard let self else { return }
                self.userInitiatedDisconnect = false
                self.reconnectAttempt = 0
                self.connect()
            }
        case "rejoin", "cycle":
            // PART + JOIN current channel — refreshes server-side state
            // (membership, modes, NAMES, topic) without dropping the
            // connection. No-op outside a channel buffer.
            guard let chan = currentBufferName(),
                  let bufID = selectedBufferID,
                  let buf = buffers.first(where: { $0.id == bufID }),
                  buf.kind == .channel else {
                appendError("/rejoin only works inside a channel buffer.")
                return
            }
            let reason = rest.isEmpty ? "rejoining" : rest
            client.send("PART \(chan) :\(reason)")
            // Tiny delay so the server sees PART before JOIN — strict
            // back-to-back can race on some daemons.
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 200_000_000)
                self?.client.send("JOIN \(chan)")
            }
        case "invite":
            // /invite <nick> [#channel] — channel defaults to current.
            let bits = rest.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
            guard let nick = bits.first, !nick.isEmpty else {
                appendInfo("Usage: /invite <nick> [#channel]")
                return
            }
            let chan = bits.count > 1 ? bits[1] : (currentBufferName() ?? "")
            guard !chan.isEmpty else {
                appendError("/invite needs a channel — either as the second argument or by being in a channel buffer.")
                return
            }
            client.send("INVITE \(nick) \(chan)")
        case "knock":
            // KNOCK <channel> [reason] — supported by some servers (Solanum,
            // InspIRCd) for invite-only channels. Server will reply 480 if
            // unsupported; we let the user see that response naturally.
            guard !rest.isEmpty else {
                appendInfo("Usage: /knock <#channel> [reason]")
                return
            }
            client.send("KNOCK \(rest)")
        case "motd":
            client.send(rest.isEmpty ? "MOTD" : "MOTD \(rest)")
        case "lusers":
            client.send("LUSERS")
        case "admin":
            client.send(rest.isEmpty ? "ADMIN" : "ADMIN \(rest)")
        case "info":
            client.send(rest.isEmpty ? "INFO" : "INFO \(rest)")
        case "version":
            client.send(rest.isEmpty ? "VERSION" : "VERSION \(rest)")
        case "silence":
            // SILENCE +mask / -mask / list — server-side ignore on networks
            // that support it (DALnet, EFnet, IRCnet variants). We just
            // pass it through as-is so the user can experiment with the
            // syntax their network expects.
            client.send(rest.isEmpty ? "SILENCE" : "SILENCE \(rest)")
        case "unsilence":
            guard !rest.isEmpty else {
                appendInfo("Usage: /unsilence <mask>")
                return
            }
            client.send("SILENCE -\(rest)")
        default:
            client.send("\(cmd.uppercased()) \(rest)")
        }
    }

    // MARK: - Post-welcome

    private func runPostWelcome() {
        let eff = effectiveProfile
        if eff.saslMechanism == .none, !eff.nickServPassword.isEmpty {
            client.send("PRIVMSG NickServ :IDENTIFY \(eff.nickServPassword)")
            appendInfo("Sent NickServ IDENTIFY.")
        }
        let lines = profile.performOnConnect
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        for line in lines {
            if line.hasPrefix("/") {
                handleCommand(String(line.dropFirst()), selection: selectedBufferID)
            } else {
                client.send(line)
            }
        }
        autoJoinIfNeeded()
        // Restore any channels + query buffers that were live at the previous
        // quit. Skipped silently when the user has the toggle off (ChatModel
        // doesn't `setPendingRestore` in that case).
        applyPendingRestore()
        // Re-assert away status after reconnect.
        if isAway, let reason = awayReason {
            client.send("AWAY :\(reason)")
        }
    }

    private func autoJoinIfNeeded() {
        let profileChans = profile.autoJoin
            .split { $0 == "," || $0 == " " }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        for raw in profileChans {
            let name = raw.hasPrefix("#") ? raw : "#" + raw
            guard seen.insert(name.lowercased()).inserted else { continue }
            client.send("JOIN \(name)")
        }
    }

    func joinSavedChannels(_ names: [String]) {
        guard state == .connected else { return }
        var seen = Set<String>()
        for raw in names {
            let name = raw.hasPrefix("#") ? raw : "#" + raw
            guard seen.insert(name.lowercased()).inserted else { continue }
            client.send("JOIN \(name)")
        }
    }

    // MARK: - Buffer helpers

    @discardableResult
    func ensureServerBufferID() -> Buffer.ID {
        if let id = serverBufferID, buffers.contains(where: { $0.id == id }) {
            return id
        }
        let buf = Buffer(name: "*server*", kind: .server)
        buffers.append(buf)
        serverBufferID = buf.id
        if selectedBufferID == nil { selectedBufferID = buf.id }
        return buf.id
    }

    private func indexOfOrCreateBuffer(name: String, kind: Buffer.Kind) -> Int {
        if let i = buffers.firstIndex(where: { $0.name.lowercased() == name.lowercased() }) {
            applyPendingRestoreSelectionIfMatches(name: name, id: buffers[i].id)
            return i
        }
        let buf = Buffer(name: name, kind: kind)
        buffers.append(buf)
        applyPendingRestoreSelectionIfMatches(name: name, id: buf.id)
        return buffers.count - 1
    }

    /// Same as `indexOfOrCreateBuffer` but reports whether the buffer was
    /// newly created. Callers that want to do something distinctive on
    /// first-creation (e.g. auto-WHOIS on a new query) use this variant.
    private func indexOfOrCreateBufferTracked(name: String, kind: Buffer.Kind)
        -> (index: Int, created: Bool)
    {
        if let i = buffers.firstIndex(where: { $0.name.lowercased() == name.lowercased() }) {
            applyPendingRestoreSelectionIfMatches(name: name, id: buffers[i].id)
            return (i, false)
        }
        let buf = Buffer(name: name, kind: kind)
        buffers.append(buf)
        applyPendingRestoreSelectionIfMatches(name: name, id: buf.id)
        return (buffers.count - 1, true)
    }

    /// If the user wanted to focus this buffer at restore time, do it now —
    /// the moment the buffer materializes. Replaces the old fire-and-forget
    /// 800 ms retry that left a blank pane on the screen when JOIN took
    /// longer than the timer.
    private func applyPendingRestoreSelectionIfMatches(name: String, id: Buffer.ID) {
        guard let want = pendingRestoreSelectName,
              name.lowercased() == want else { return }
        selectedBufferID = id
        pendingRestoreSelectName = nil
    }

    private func idx(of id: Buffer.ID) -> Int {
        buffers.firstIndex(where: { $0.id == id })!
    }

    private func markUnread(at i: Int) {
        if buffers[i].id != selectedBufferID {
            buffers[i].unread += 1
        }
    }

    /// Append a line to a buffer AND, when persistence is enabled, write it
    /// to the on-disk log. The file write happens on a detached Task so it
    /// never blocks the main actor or the buffer mutation.
    private func appendTo(bufferIndex i: Int, line: ChatLine) {
        guard i < buffers.count else { return }
        buffers[i].appendLine(line)
        if loggingEnabled, let store = logStore {
            if !logNoisyLines, line.isNoisyLogKind { return }
            let network = displayName
            let buffer = buffers[i].name
            let text = line.toLogLine()
            Task.detached(priority: .utility) {
                await store.append(network: network, buffer: buffer, line: text)
            }
        }
    }

    private func appendInfo(_ text: String) {
        let i = idx(of: ensureServerBufferID())
        appendTo(bufferIndex: i, line: ChatLine(timestamp: Date(), kind: .info, text: text))
    }

    private func appendError(_ text: String) {
        let i = idx(of: ensureServerBufferID())
        appendTo(bufferIndex: i, line: ChatLine(timestamp: Date(), kind: .error, text: text))
    }

    private func emit(_ event: IRCConnectionEvent) {
        events.send((id, event))
    }
}

extension IRCConnection {
    /// Exposed to ChatModel which is the shared WatchlistDelegate — routes
    /// watchlist-sourced raw lines to this connection when it's the one
    /// currently holding the registered watchlist session.
    func watchlistRouteSendRaw(_ line: String) {
        guard state == .connected else { return }
        client.send(line)
    }
    func watchlistRoutePostInfo(_ text: String) {
        appendInfo(text)
    }

    /// Post an `.info` line to the currently-selected buffer (or the server
    /// buffer if nothing is selected). Used by ChatModel when it intercepts
    /// a slash command like `/ignore` and needs to surface feedback to the
    /// user without going through the IRC send path.
    func appendInfoOnSelected(_ text: String) {
        if let sel = selectedBufferID,
           let i = buffers.firstIndex(where: { $0.id == sel }) {
            appendTo(bufferIndex: i, line: ChatLine(timestamp: Date(), kind: .info, text: text))
        } else {
            appendInfo(text)
        }
    }
}

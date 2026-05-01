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
    /// True once we've emitted the "scrollback truncated" notice. Reset never
    /// — once a buffer hits the cap the user has been told; we don't repeat.
    var truncationNoticeShown: Bool = false

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
    /// Maximum scrollback retained per buffer. Older lines are dropped from
    /// the head when this limit is exceeded; a one-shot info notice flags
    /// the first occurrence so a busy channel's scrollback isn't silently
    /// truncated.
    static let maxScrollbackLines = 5000

    mutating func appendLine(_ l: ChatLine) {
        lines.append(l)
        if lines.count > Self.maxScrollbackLines {
            // Show the truncation notice exactly once per buffer — far less
            // noisy than re-emitting it on every overflow, and enough for
            // the user to know history is being shed.
            if !truncationNoticeShown {
                truncationNoticeShown = true
                let notice = ChatLine(
                    timestamp: Date(),
                    kind: .info,
                    text: "— Scrollback exceeded \(Self.maxScrollbackLines) lines; older history is being trimmed —"
                )
                lines.append(notice)
            }
            lines.removeFirst(lines.count - Self.maxScrollbackLines)
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

    /// Surfaced by `/nuke`. The confirmation sheet (in ContentView) requires
    /// the user to type the literal phrase `NUKE` before the destructive
    /// button enables. NukeService does the actual wiping.
    @Published var showNukeConfirmation: Bool = false

    /// One-shot find-bar prefill request. Set by `/find <text>`; consumed
    /// (set back to nil) by BufferView once the find bar opens. nil means
    /// no pending request.
    @Published var findRequest: String? = nil

    /// One-shot "clear current buffer" request, identifying which buffer
    /// to wipe. BufferView clears it after consuming. Channels keep their
    /// server-side membership; this is a UI-only scrollback wipe.
    @Published var clearBufferRequest: Buffer.ID? = nil

    /// Draft passed to `ThemeBuilderView` when the slash command (or a
    /// future menu item) wants to summon the WYSIWYG builder. Non-nil
    /// presents the sheet; `ThemeBuilderView` clears it on dismiss
    /// indirectly via `.sheet(item:)`.
    @Published var themeBuilderDraft: UserTheme? = nil
    /// True when `themeBuilderDraft` represents a brand-new theme (not
    /// yet in `settings.userThemes`). Drives the builder's Delete
    /// button visibility and the title.
    @Published var themeBuilderIsNew: Bool = false

    /// Generic single-line input prompt surfaced by ContentView whenever
    /// a menu item needs user input (Set Topic…, WHOIS…, Invite…). The
    /// prompt's `onSubmit` runs the chosen action with the typed text.
    /// Set to nil to dismiss.
    @Published var inputPrompt: InputPrompt? = nil

    struct InputPrompt: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let placeholder: String
        let defaultText: String
        let confirmLabel: String
        let onSubmit: (String) -> Void
    }

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

    /// Local-LLM-backed assistant. Off until the user enables it in
    /// Setup → Bot. Fires suggestions into the strip above the input
    /// bar; never sends without explicit user confirmation.
    let assistant = AssistantEngine()

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
        // Initial backfill — covers buffers from the seed connection plus
        // anything in lastSession from a previous run.
        backfillLogIndexFromLiveState()
        // Snapshot the support dir to ~/Downloads/PurpleIRC backup/ on
        // launch (encrypted with the keystore DEK when available).
        // Runs after settings have been resolved so we capture the
        // user's actual data, not init-time defaults.
        runBackupIfEnabled()
        // Assistant engine — wire the closures + event subscription. We
        // intentionally do NOT seed personas here. Seeding mutates
        // settings.settings, which fires didSet → save() during init.
        // That's the same shape as the d0cc021 data-loss bug — a save
        // can race with the unlock-and-reload sequence and clobber the
        // user's encrypted file. The persona library is seeded lazily
        // by `seedAssistantPersonasIfNeeded` when the user actually
        // opens Setup → Bot or invokes /assist for the first time.
        assistant.personasProvider = { [weak self] in
            self?.settings.settings.assistantPersonas ?? []
        }
        assistant.settingsProvider = { [weak self] in
            self?.settings.settings.assistant ?? AssistantSettings()
        }
        assistant.sendBlock = { [weak self] cid, bid, text in
            self?.sendAssistantSuggestion(connectionID: cid,
                                          bufferID: bid, text: text)
        }
        assistant.attach(eventStream: events.eraseToAnyPublisher(),
                         resolveBufferID: { [weak self] cid, bufName in
            guard let self,
                  let conn = self.connections.first(where: { $0.id == cid })
            else { return nil }
            return conn.buffers.first(where: {
                $0.name.lowercased() == bufName.lowercased()
            })?.id
        })
        // Capture the trailing window of every buffer at quit. The willTerminate
        // notification fires on the main thread; we MUST save synchronously
        // because the run loop is shutting down. An earlier version wrapped
        // this in `Task { @MainActor in … }` and the task body never ran —
        // the app exited first, history vanished. `assumeIsolated` lets us
        // call the @MainActor method synchronously without that loss.
        NotificationCenter.default
            .publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.saveAllHistories() }
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
                // Settings now have lastSession populated (encrypted users
                // start with empty defaults until unlock). Backfill so the
                // chat-log viewer can name those buffers.
                self.backfillLogIndexFromLiveState()
                // Run a backup pass now that the user's data is loaded
                // and the DEK is available — this is the first chance
                // we have to take a fully-encrypted snapshot.
                self.runBackupIfEnabled()
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
                // Re-run the backfill so any newly-created buffer shows
                // up in the chat-log viewer with its real name.
                self.backfillLogIndexFromLiveState()
            }
            .store(in: &bag)
        // Persist chat history when the connection drops, not only at
        // app quit. willTerminate covers Cmd+Q; this covers /disconnect,
        // network loss, and the "Disconnect" toolbar button — without
        // it, history saves only at quit and an app crash before quit
        // loses everything.
        conn.$state
            .removeDuplicates()
            .sink { [weak self, weak conn] state in
                guard let self, let conn else { return }
                if case .disconnected = state {
                    self.persistHistoryForConnection(conn)
                }
                if case .failed = state {
                    self.persistHistoryForConnection(conn)
                }
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

    /// Selected theme — read by MessageRow at render time. Resolution
    /// order:
    ///   1. The active connection's `themeOverrideID` (per-network
    ///      theme override on the profile), if it resolves to a
    ///      built-in or a user theme.
    ///   2. The global `settings.themeID`, looked up against built-ins
    ///      and user themes.
    ///   3. `.classic` as the ultimate fallback.
    var theme: Theme {
        let userThemes = settings.settings.userThemes
        if let override = activeConnection?.profile.themeOverrideID, !override.isEmpty {
            let t = Theme.resolve(id: override, userThemes: userThemes)
            // resolve falls back to .classic on miss; only honour the
            // override when it actually resolved to something specific.
            if t.id != "classic" || override == "classic" { return t }
        }
        return Theme.resolve(id: settings.settings.themeID, userThemes: userThemes)
    }

    /// Per-event color override, when the active theme is a UserTheme
    /// that has a non-nil entry for `tag`. nil means "use the theme's
    /// typed slot (`infoColor`, `joinColor`, etc.)" — MessageRow handles
    /// the fallback at the call site.
    func kindColor(for tag: ChatLineKindTag) -> Color? {
        let userThemes = settings.settings.userThemes
        // Resolve which UserTheme (if any) is currently active.
        let activeID: String = {
            if let override = activeConnection?.profile.themeOverrideID, !override.isEmpty {
                return override
            }
            return settings.settings.themeID
        }()
        guard let user = userThemes.first(where: { $0.id.uuidString == activeID }) else {
            return nil
        }
        return user.kindOverridesMaterialised[tag]
    }

    /// Resolved chat font (family + size + optional bold). Read by every
    /// view that renders chat text — keeps font customisation in one place
    /// instead of scattered `.font(...)` calls.
    var chatFont: Font {
        font(for: .chatBody).swiftUIFont
    }

    /// Per-slot font resolution. Walks the inheritance chain so a nick
    /// or timestamp slot can override only the fields it cares about
    /// while inheriting everything else from the chat-body root, which
    /// in turn falls back to the legacy `chatFontFamily` / `chatFontSize`
    /// / `boldChatText` fields. Renderers should call this once per
    /// row rather than re-walking the chain inline.
    func font(for slot: FontSlot) -> ResolvedFont {
        let s = settings.settings
        let chatBody = FontStyle.resolveChatBody(
            legacy: s.chatFontFamily,
            legacySize: s.chatFontSize,
            legacyBold: s.boldChatText,
            style: s.chatBodyFont
        )
        switch slot {
        case .chatBody:    return chatBody
        case .nick:        return s.nickFont.resolved(parent: chatBody)
        case .timestamp:   return s.timestampFont.resolved(parent: chatBody)
        case .systemLine:  return s.systemLineFont.resolved(parent: chatBody)
        }
    }

    /// Caption-sized variant of the chat font (timestamps, join/part lines).
    /// Scales down 25% from the user's base size so timestamps still feel
    /// secondary even at large body sizes. Honours the per-element
    /// system-line slot so a user who sets a different font for system
    /// rows sees it here too.
    var chatCaptionFont: Font {
        let sys = font(for: .systemLine)
        // Recompose the resolved font at 78% size — the slot's
        // configured size becomes the "100%" baseline that captions
        // shrink against. Avoids a separate "captionSize" knob.
        let captionSize = max(9, sys.size * 0.78)
        let recomposed: Font = {
            if sys.isBuiltInMonoToken {
                return .system(size: captionSize, design: .monospaced)
            } else if sys.isBuiltInPropToken {
                return .system(size: captionSize)
            } else {
                return .custom(sys.family, size: captionSize)
            }
        }()
        let weighted = recomposed.weight(sys.weight)
        return sys.italic ? weighted.italic() : weighted
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

    /// Disconnect + immediately reconnect the active network. Bypasses
    /// the auto-reconnect backoff timer so the user gets a fresh attempt
    /// right now. Routes through the connection's existing `/reconnect`
    /// path so menu and slash command share semantics.
    func reconnect() {
        activeConnection?.handleReconnectFromMenu()
    }

    /// Cycle the active connection forward / backward through the open
    /// connection list. Wraps at the edges. Used by the Buffer menu's
    /// Next Network / Previous Network items.
    func cycleNetwork(forward: Bool) {
        guard !connections.isEmpty else { return }
        let currentIdx = connections.firstIndex(where: { $0.id == activeConnectionID }) ?? 0
        let next = forward
            ? (currentIdx + 1) % connections.count
            : (currentIdx - 1 + connections.count) % connections.count
        activeConnectionID = connections[next].id
    }

    /// Wipe scrollback on the currently-selected buffer (UI only).
    func clearCurrentBuffer() {
        guard let conn = activeConnection,
              let id = conn.selectedBufferID else { return }
        clearBufferRequest = id
        conn.clearBufferLines(id: id)
    }

    /// Reset every buffer's unread badge across every connection.
    func markAllReadEverywhere() {
        for c in connections { c.markAllBuffersRead() }
    }

    /// Cycle the active connection's buffer forward / backward.
    func cycleBuffer(forward: Bool) {
        activeConnection?.cycleBuffer(forward: forward)
    }

    // MARK: - Font / theme / density convenience (menu-driven)

    private static let chatFontMin: Double = 8
    private static let chatFontMax: Double = 28
    private static let chatFontDefault: Double = 13

    func incrementFontSize() {
        settings.settings.chatFontSize = min(Self.chatFontMax,
                                             settings.settings.chatFontSize + 1)
    }
    func decrementFontSize() {
        settings.settings.chatFontSize = max(Self.chatFontMin,
                                             settings.settings.chatFontSize - 1)
    }
    func resetFontSize() {
        settings.settings.chatFontSize = Self.chatFontDefault
    }

    func setTheme(byID id: String) {
        guard Theme.all.contains(where: { $0.id == id }) else { return }
        settings.settings.themeID = id
    }

    func setDensity(_ d: ChatDensity) {
        settings.settings.chatDensity = d
    }

    // MARK: - Input prompt helpers

    /// Surface a one-line input dialog. Convenience wrapper used by the
    /// Conversation / Network menus so menu actions don't have to mint
    /// their own InputPrompt struct each time.
    func requestInput(title: String,
                      message: String,
                      placeholder: String = "",
                      defaultText: String = "",
                      confirmLabel: String = "OK",
                      onSubmit: @escaping (String) -> Void) {
        inputPrompt = InputPrompt(
            title: title,
            message: message,
            placeholder: placeholder,
            defaultText: defaultText,
            confirmLabel: confirmLabel,
            onSubmit: onSubmit
        )
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
            // User-defined alias: `/alias <name> <expansion>` stored in
            // settings; expansion may itself begin with a slash. Looked up
            // BEFORE built-ins so the user can shadow built-ins on purpose.
            if let expansion = settings.settings.userAliases[cmd], !expansion.isEmpty {
                let expanded = expansion + (rest.isEmpty ? "" : " \(rest)")
                sendInput(expanded)
                return
            }
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
            case "assist", "ai", "bot":
                // Toggle the local-LLM assistant on the active query.
                // Suggestion-only — no auto-send.
                toggleAssistantOnSelected()
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
            case "nuke":
                // Two-step destructive reset. First call surfaces the
                // confirmation sheet; only after the user types the literal
                // phrase NUKE in the sheet does NukeService actually run.
                requestNuke()
                return
            case "clear", "cls":
                // UI-only scrollback wipe. BufferView observes the request
                // flag and drops its rendered lines; the IRCConnection's
                // buffer also gets its lines array reset so the wipe sticks
                // across re-renders. Server-side membership is unchanged.
                if let bufID = conn.selectedBufferID {
                    clearBufferRequest = bufID
                    conn.clearBufferLines(id: bufID)
                    conn.appendInfoOnSelected("Buffer cleared.")
                }
                return
            case "find", "search":
                // Open the find bar pre-filled with the query (or empty).
                findRequest = rest
                return
            case "markread", "markallread":
                // Reset unread counts across every buffer on every network.
                for c in connections { c.markAllBuffersRead() }
                conn.appendInfoOnSelected("Marked all buffers as read.")
                return
            case "next", "nextbuffer":
                conn.cycleBuffer(forward: true)
                return
            case "prev", "previous", "prevbuffer":
                conn.cycleBuffer(forward: false)
                return
            case "goto", "switch":
                guard !rest.isEmpty else {
                    conn.appendInfoOnSelected("Usage: /goto <buffer-name>")
                    return
                }
                if !conn.selectBufferByName(rest) {
                    conn.appendInfoOnSelected("No buffer matching '\(rest)' on this network.")
                }
                return
            case "network":
                guard !rest.isEmpty else {
                    let names = connections.map { $0.displayName }.joined(separator: ", ")
                    conn.appendInfoOnSelected("Connected networks: \(names.isEmpty ? "(none)" : names)")
                    return
                }
                let lower = rest.lowercased()
                if let match = connections.first(where: {
                    $0.displayName.lowercased() == lower
                }) ?? connections.first(where: {
                    $0.displayName.lowercased().contains(lower)
                }) {
                    activeConnectionID = match.id
                } else {
                    conn.appendInfoOnSelected("No network matching '\(rest)'.")
                }
                return
            case "theme":
                handleThemeCommand(rest: rest, on: conn)
                return
            case "font":
                handleFontCommand(rest: rest, on: conn)
                return
            case "density":
                guard let d = ChatDensity(rawValue: rest.lowercased()) else {
                    conn.appendInfoOnSelected("Usage: /density compact|cozy|comfortable")
                    return
                }
                settings.settings.chatDensity = d
                conn.appendInfoOnSelected("Density: \(d.displayName)")
                return
            case "zoom":
                handleZoomCommand(rest: rest, on: conn)
                return
            case "timestamp", "ts":
                handleTimestampCommand(rest: rest, on: conn)
                return
            case "lock":
                // Drop the in-memory DEK and remove the Keychain cache;
                // every encrypted persistence path now refuses to write
                // (per safeWrite.skippedLockedEncrypted) until the user
                // re-enters the passphrase.
                keyStore.lock()
                conn.appendInfoOnSelected("Keystore locked. Re-enter passphrase to unlock.")
                return
            case "backup":
                // Surface the backup sheet — already implemented by
                // BackupService + BackupSettingsView. Land the user on
                // the right Setup tab so they can review settings too.
                pendingSetupTab = .behavior
                showSetup = true
                return
            case "export":
                handleExportCommand(rest: rest, on: conn)
                return
            case "alias":
                handleAliasCommand(rest: rest, on: conn)
                return
            case "repeat":
                handleRepeatCommand(rest: rest, on: conn)
                return
            case "timer":
                handleTimerCommand(rest: rest, on: conn)
                return
            case "summary":
                handleSummaryCommand(rest: rest, on: conn)
                return
            case "translate":
                handleTranslateCommand(rest: rest, on: conn)
                return
            default:
                // Let PurpleBot claim the command if it registered a matching
                // /alias via irc.onCommand(...).
                if bot.handleCommandAlias(cmd, args: rest) { return }
            }
        }
        conn.sendInput(text, from: conn.selectedBufferID)
    }

    /// Surface the `/nuke` confirmation sheet. Idempotent — clicking the
    /// same flag twice while it's already true is a no-op for SwiftUI.
    func requestNuke() {
        showNukeConfirmation = true
    }

    /// Execute the destructive reset. Called by the confirmation sheet
    /// once the user has typed the literal phrase NUKE.
    func performNukeAndQuit() {
        let result = NukeService.performNuke(model: self)
        AppLog.shared.warn("NUKE result: \(result.summary)", category: "Nuke")
        NukeService.terminate(after: 0.5)
    }

    // MARK: - Slash command helpers

    /// `/theme`           — list built-ins + user themes + show current
    /// `/theme <id>`      — switch to a theme by id
    /// `/theme builder`   — open the WYSIWYG ThemeBuilderView sheet
    /// `/theme import <path>` — load a `.purpletheme` JSON from disk
    /// `/theme export <id> <path>` — save a user theme to disk
    private func handleThemeCommand(rest: String, on conn: IRCConnection) {
        let trimmed = rest.trimmingCharacters(in: .whitespaces)

        // No-arg list view.
        if trimmed.isEmpty {
            let builtins = Theme.all.map { $0.id }.joined(separator: ", ")
            let users = settings.settings.userThemes
                .map { "\($0.name) [\($0.id.uuidString.prefix(8))…]" }
                .joined(separator: ", ")
            var lines = ["Built-ins: \(builtins)"]
            if !users.isEmpty { lines.append("Custom: \(users)") }
            lines.append("Current: \(settings.settings.themeID)")
            lines.append("Try: /theme <id>, /theme builder, /theme import <path>, /theme export <id> <path>.")
            conn.appendInfoOnSelected(lines.joined(separator: "\n"))
            return
        }

        // Subcommands.
        let firstSpace = trimmed.firstIndex(of: " ")
        let head = firstSpace.map { String(trimmed[trimmed.startIndex..<$0]).lowercased() }
            ?? trimmed.lowercased()
        let tail = firstSpace.map { String(trimmed[trimmed.index(after: $0)...])
            .trimmingCharacters(in: .whitespaces) } ?? ""

        switch head {
        case "builder", "edit", "new":
            // Snapshot the active theme as the starting point so the
            // builder opens with a meaningful palette rather than blank.
            let active = Theme.resolve(id: settings.settings.themeID,
                                       userThemes: settings.settings.userThemes)
            themeBuilderDraft = UserTheme.duplicate(of: active, name: "")
            themeBuilderIsNew = true
            return
        case "import":
            guard !tail.isEmpty else {
                conn.appendInfoOnSelected("Usage: /theme import <path-to-.purpletheme>")
                return
            }
            let url = URL(fileURLWithPath: (tail as NSString).expandingTildeInPath)
            if let imported = ThemeImporter.importTheme(from: url, into: settings) {
                settings.settings.themeID = imported.id.uuidString
                conn.appendInfoOnSelected("Imported '\(imported.name)' and switched to it.")
            } else {
                conn.appendInfoOnSelected("Couldn't read \(url.path) as a .purpletheme file.")
            }
            return
        case "export":
            // /theme export <id-or-name> <path>
            let parts = tail.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                .map(String.init)
            guard parts.count == 2 else {
                conn.appendInfoOnSelected("Usage: /theme export <user-theme-name-or-id> <path>")
                return
            }
            let key = parts[0]
            let path = (parts[1] as NSString).expandingTildeInPath
            guard let user = settings.settings.userThemes.first(where: {
                $0.id.uuidString == key
                    || $0.id.uuidString.hasPrefix(key)
                    || $0.name.lowercased() == key.lowercased()
            }) else {
                conn.appendInfoOnSelected("No user theme matching '\(key)'. Built-ins can't be exported (they're code).")
                return
            }
            do {
                let enc = JSONEncoder()
                enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try enc.encode(user)
                try data.write(to: URL(fileURLWithPath: path), options: .atomic)
                conn.appendInfoOnSelected("Exported '\(user.name)' to \(path)")
            } catch {
                conn.appendInfoOnSelected("Export failed: \(error.localizedDescription)")
            }
            return
        default:
            break
        }

        // Plain `/theme <id>` — match against built-ins by id, then user
        // themes by uuid prefix or by name (case-insensitive).
        let lower = trimmed.lowercased()
        if let built = Theme.all.first(where: { $0.id.lowercased() == lower }) {
            settings.settings.themeID = built.id
            conn.appendInfoOnSelected("Theme: \(built.id)")
            return
        }
        if let user = settings.settings.userThemes.first(where: {
            $0.id.uuidString == trimmed
                || $0.id.uuidString.hasPrefix(trimmed)
                || $0.name.lowercased() == lower
        }) {
            settings.settings.themeID = user.id.uuidString
            conn.appendInfoOnSelected("Theme: \(user.name)")
            return
        }
        conn.appendInfoOnSelected("No theme matching '\(trimmed)'. Try /theme to list available themes.")
    }

    /// `/font + - reset | <ptsize> | family <name>`
    private func handleFontCommand(rest: String, on conn: IRCConnection) {
        let trimmed = rest.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            conn.appendInfoOnSelected(
                "Font: \(settings.settings.chatFontFamily.rawValue) @ \(Int(settings.settings.chatFontSize))pt. " +
                "Usage: /font + | - | reset | <pt> | family <name>")
            return
        }
        if trimmed == "+" {
            settings.settings.chatFontSize = min(28, settings.settings.chatFontSize + 1)
        } else if trimmed == "-" {
            settings.settings.chatFontSize = max(8, settings.settings.chatFontSize - 1)
        } else if trimmed.lowercased() == "reset" {
            settings.settings.chatFontSize = 13
        } else if let pt = Double(trimmed) {
            settings.settings.chatFontSize = max(8, min(28, pt))
        } else if trimmed.lowercased().hasPrefix("family ") {
            let name = String(trimmed.dropFirst("family ".count)).trimmingCharacters(in: .whitespaces)
            if let fam = ChatFontFamily.allCases.first(where: { $0.rawValue.lowercased() == name.lowercased() }) {
                settings.settings.chatFontFamily = fam
            } else {
                conn.appendInfoOnSelected("Unknown font family. Choices: " +
                    ChatFontFamily.allCases.map { $0.rawValue }.joined(separator: ", "))
                return
            }
        } else {
            conn.appendInfoOnSelected("Usage: /font + | - | reset | <pt> | family <name>")
            return
        }
        conn.appendInfoOnSelected("Font: \(settings.settings.chatFontFamily.rawValue) @ \(Int(settings.settings.chatFontSize))pt")
    }

    /// `/zoom + - reset | <multiplier>`
    private func handleZoomCommand(rest: String, on conn: IRCConnection) {
        let trimmed = rest.trimmingCharacters(in: .whitespaces).lowercased()
        var z = settings.settings.viewZoom
        switch trimmed {
        case "":      conn.appendInfoOnSelected("Zoom: \(String(format: "%.2f", z))×. Usage: /zoom + | - | reset | <0.5–2.0>"); return
        case "+":     z = min(2.0, z + 0.1)
        case "-":     z = max(0.5, z - 0.1)
        case "reset": z = 1.0
        default:
            guard let v = Double(trimmed) else {
                conn.appendInfoOnSelected("Usage: /zoom + | - | reset | <0.5–2.0>")
                return
            }
            z = max(0.5, min(2.0, v))
        }
        settings.settings.viewZoom = z
        conn.appendInfoOnSelected(String(format: "Zoom: %.2f×", z))
    }

    /// `/timestamp on | off | <DateFormatter pattern>`
    private func handleTimestampCommand(rest: String, on conn: IRCConnection) {
        let trimmed = rest.trimmingCharacters(in: .whitespaces)
        switch trimmed.lowercased() {
        case "":
            conn.appendInfoOnSelected("Timestamp: \"\(settings.settings.timestampFormat)\". Usage: /timestamp on | off | <pattern>")
        case "off":
            settings.settings.timestampFormat = ""
            conn.appendInfoOnSelected("Timestamp hidden.")
        case "on":
            settings.settings.timestampFormat = "HH:mm:ss"
            conn.appendInfoOnSelected("Timestamp: HH:mm:ss")
        default:
            settings.settings.timestampFormat = trimmed
            conn.appendInfoOnSelected("Timestamp: \"\(trimmed)\"")
        }
    }

    /// `/export buffer | all`
    /// Writes plaintext transcripts to ~/Downloads/PurpleIRC export/<timestamp>/.
    private func handleExportCommand(rest: String, on conn: IRCConnection) {
        let target = rest.trimmingCharacters(in: .whitespaces).lowercased()
        let mode: ExportMode
        switch target {
        case "", "buffer", "current": mode = .currentBuffer
        case "all": mode = .allBuffers
        default:
            conn.appendInfoOnSelected("Usage: /export buffer | all")
            return
        }
        Task { @MainActor in
            let url = await exportTranscripts(mode: mode)
            if let url {
                conn.appendInfoOnSelected("Export written to \(url.path)")
            } else {
                conn.appendInfoOnSelected("Export failed.")
            }
        }
    }

    private enum ExportMode { case currentBuffer, allBuffers }

    private func exportTranscripts(mode: ExportMode) async -> URL? {
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd_HHmmss"
        let baseDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads", isDirectory: true)
            .appendingPathComponent("PurpleIRC export", isDirectory: true)
            .appendingPathComponent(stamp.string(from: Date()), isDirectory: true)
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)

        let lineFmt = DateFormatter()
        lineFmt.dateFormat = "yyyy-MM-dd HH:mm:ss"

        func dump(buf: Buffer, network: String) {
            let body = buf.lines.map { line -> String in
                "[\(lineFmt.string(from: line.timestamp))] \(line.text)"
            }.joined(separator: "\n")
            let safeName = buf.name.replacingOccurrences(of: "/", with: "_")
            let netSafe = network.replacingOccurrences(of: "/", with: "_")
            let url = baseDir.appendingPathComponent("\(netSafe)__\(safeName).txt")
            try? body.write(to: url, atomically: true, encoding: .utf8)
        }

        switch mode {
        case .currentBuffer:
            guard let conn = activeConnection,
                  let bufID = conn.selectedBufferID,
                  let buf = conn.buffers.first(where: { $0.id == bufID }) else { return nil }
            dump(buf: buf, network: conn.displayName)
        case .allBuffers:
            for c in connections {
                for b in c.buffers where !b.lines.isEmpty {
                    dump(buf: b, network: c.displayName)
                }
            }
        }
        return baseDir
    }

    /// `/alias`           — list user aliases
    /// `/alias name args` — define
    /// `/alias -name`     — remove
    private func handleAliasCommand(rest: String, on conn: IRCConnection) {
        let trimmed = rest.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            let aliases = settings.settings.userAliases
            if aliases.isEmpty {
                conn.appendInfoOnSelected("No user aliases. Usage: /alias <name> <expansion> — or /alias -<name> to remove.")
            } else {
                let lines = aliases
                    .sorted(by: { $0.key < $1.key })
                    .map { "  /\($0.key) → \($0.value)" }
                    .joined(separator: "\n")
                conn.appendInfoOnSelected("User aliases:\n\(lines)")
            }
            return
        }
        if trimmed.hasPrefix("-") {
            let name = String(trimmed.dropFirst()).lowercased()
            if settings.settings.userAliases.removeValue(forKey: name) != nil {
                conn.appendInfoOnSelected("Removed alias /\(name).")
            } else {
                conn.appendInfoOnSelected("No alias /\(name).")
            }
            return
        }
        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
        guard parts.count == 2 else {
            conn.appendInfoOnSelected("Usage: /alias <name> <expansion>")
            return
        }
        let name = parts[0].lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let expansion = parts[1]
        guard !name.isEmpty else {
            conn.appendInfoOnSelected("Alias name cannot be empty.")
            return
        }
        settings.settings.userAliases[name] = expansion
        conn.appendInfoOnSelected("Alias /\(name) → \(expansion)")
    }

    /// `/repeat <n> <command>` — fires the command N times with a small
    /// inter-fire delay so a server-side flood-throttle doesn't kill the
    /// connection. Capped at 20 to make accidental loops survivable.
    private func handleRepeatCommand(rest: String, on conn: IRCConnection) {
        let parts = rest.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
        guard parts.count == 2, let n = Int(parts[0]), n > 0 else {
            conn.appendInfoOnSelected("Usage: /repeat <count 1-20> <command>")
            return
        }
        let cap = min(20, n)
        let cmd = parts[1]
        Task { @MainActor [weak self] in
            for _ in 0..<cap {
                self?.sendInput(cmd)
                try? await Task.sleep(nanoseconds: 250_000_000) // 250 ms
            }
        }
    }

    /// `/timer <seconds> <command>` — fire-and-forget delayed command,
    /// capped at 1 hour so a typo can't wedge a stray task forever.
    private func handleTimerCommand(rest: String, on conn: IRCConnection) {
        let parts = rest.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
        guard parts.count == 2, let secs = Int(parts[0]), secs > 0 else {
            conn.appendInfoOnSelected("Usage: /timer <seconds 1-3600> <command>")
            return
        }
        let s = min(3600, secs)
        let cmd = parts[1]
        conn.appendInfoOnSelected("Will run in \(s)s: \(cmd)")
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(s) * 1_000_000_000)
            self?.sendInput(cmd)
        }
    }

    /// `/summary [N]` — local-LLM digest of the most recent N lines in
    /// the active buffer. Stub for now: surfaces a "configure assistant"
    /// hint when AssistantEngine isn't ready. Full integration lands
    /// alongside the broader assistant work; the command shape is in
    /// place so users see it in autocomplete + /help.
    private func handleSummaryCommand(rest: String, on conn: IRCConnection) {
        if !settings.settings.assistant.enabled {
            conn.appendInfoOnSelected("/summary requires the local-LLM assistant. Enable it in Setup → Power-user → Assistant.")
            return
        }
        let n = Int(rest.trimmingCharacters(in: .whitespaces)) ?? 50
        conn.appendInfoOnSelected("(Summary of last \(n) lines — assistant integration coming soon.)")
    }

    /// `/translate <lang>` — stub for the same reason as /summary.
    private func handleTranslateCommand(rest: String, on conn: IRCConnection) {
        if !settings.settings.assistant.enabled {
            conn.appendInfoOnSelected("/translate requires the local-LLM assistant. Enable it in Setup → Power-user → Assistant.")
            return
        }
        let target = rest.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else {
            conn.appendInfoOnSelected("Usage: /translate <language>")
            return
        }
        conn.appendInfoOnSelected("(Translate next message → \(target) — assistant integration coming soon.)")
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

    /// Backfill the LogStore index with every (network, buffer) pair we
    /// can identify from in-memory state. Called at launch and whenever
    /// connections gain or lose buffers. Without this, log files written
    /// before the index existed (or while the index was sealed under a
    /// different DEK) show up as opaque slugs in the chat-log viewer.
    func backfillLogIndexFromLiveState() {
        var pairs: [(network: String, buffer: String)] = []
        // Live connections — every buffer that's currently open.
        for conn in connections {
            for buf in conn.buffers where buf.kind != .server {
                pairs.append((network: conn.displayName, buffer: buf.name))
            }
        }
        // Saved sessions — the channels and queries that were live at the
        // previous quit. Resolves slug filenames for buffers the user has
        // PARTed but might still want to read history from.
        for (key, snap) in settings.settings.lastSession {
            // The lastSession key is the profile UUID; resolve to the
            // server profile's display name.
            guard let uuid = UUID(uuidString: key),
                  let profile = settings.settings.servers.first(where: { $0.id == uuid })
            else { continue }
            let networkName = profile.name.isEmpty ? profile.host : profile.name
            for c in snap.channels { pairs.append((network: networkName, buffer: c)) }
            for q in snap.queries  { pairs.append((network: networkName, buffer: q)) }
        }
        guard !pairs.isEmpty else { return }
        let store = logStore
        Task { await store.backfillIndex(pairs) }
    }

    /// Persist the trailing-window of every buffer on every connected
    /// network. Called at quit (via `willTerminateNotification`) and on
    /// each disconnect so users see their last live state on relaunch.
    /// Drops the leading "previous session" / trailing "live" markers
    /// from earlier restores so successive launches don't accumulate
    /// banner pairs.
    func saveAllHistories() {
        for conn in connections {
            persistHistoryForConnection(conn)
        }
    }

    /// Snapshot one connection's buffers and write them to disk. Pulled
    /// out of `saveAllHistories` so per-disconnect saves can target one
    /// connection cheaply. Skips connections whose buffers are empty so
    /// we don't wipe a previously-saved history with nothing — that
    /// happened during an earlier debug session and was a real footgun.
    fileprivate func persistHistoryForConnection(_ conn: IRCConnection) {
        let slug = SeenStore.slug(for: conn.displayName)
        var network = SessionHistoryStore.NetworkHistory()
        for buf in conn.buffers where buf.kind != .server {
            let trimmed = buf.lines
                .filter { !Self.isRestoreBannerLine($0) }
                .suffix(SessionHistoryStore.linesPerBuffer)
            if trimmed.isEmpty { continue }
            network.buffers[buf.name] = Array(trimmed)
        }
        // If the snapshot has nothing worth saving, leave whatever's on
        // disk in place. Otherwise persist.
        guard !network.buffers.isEmpty else { return }
        sessionHistory.save(networkSlug: slug, history: network)
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

    // MARK: - Assistant integration

    /// Populate the persona library with the built-in templates the
    /// first time the assistant feature is touched. Idempotent — re-
    /// running won't re-add templates the user has since renamed or
    /// deleted (we identify by the fixed builtin UUIDs in
    /// `AssistantPersona.defaultPersonas`). Called from `/assist` and
    /// from the AssistantSetupSection's `onAppear`. Safe to call once
    /// the keystore is settled and the user's settings are loaded.
    func seedAssistantPersonasIfNeeded() {
        let existingIDs = Set(settings.settings.assistantPersonas.map { $0.id })
        var added = false
        for builtin in AssistantPersona.defaultPersonas() {
            if !existingIDs.contains(builtin.id) {
                settings.settings.assistantPersonas.append(builtin)
                added = true
            }
        }
        if added,
           settings.settings.assistant.defaultPersonaID == nil,
           let first = settings.settings.assistantPersonas.first {
            settings.settings.assistant.defaultPersonaID = first.id
        }
    }

    /// Toggle the assistant on / off for the active query buffer. Echoes
    /// state into the buffer so the user has a clear log of what changed.
    /// Returns true when engagement is now ON.
    @discardableResult
    func toggleAssistantOnSelected() -> Bool {
        // First-touch seeding — runs at most once per install, only when
        // the user actually invokes /assist, so we never mutate settings
        // during init.
        seedAssistantPersonasIfNeeded()
        guard settings.settings.assistant.enabled else {
            activeConnection?.appendInfoOnSelected(
                "Assistant is disabled. Enable it in Setup → Bot → Assistant.")
            return false
        }
        guard let conn = activeConnection,
              let bufID = conn.selectedBufferID,
              let buf = conn.buffers.first(where: { $0.id == bufID })
        else { return false }
        guard buf.kind == .query else {
            activeConnection?.appendInfoOnSelected(
                "/assist only works in query buffers — channels are too noisy for one-on-one suggestions.")
            return false
        }
        // Make sure the engine has a closure that returns this buffer's
        // lines on demand. Re-registering each time is fine (idempotent
        // overwrite) and ensures rejoined buffers get a fresh closure.
        let connRef = conn
        assistant.registerHistoryProvider(bufferID: bufID) { [weak connRef] in
            connRef?.buffers.first(where: { $0.id == bufID })?.lines ?? []
        }
        let now = assistant.toggleEngagement(bufferID: bufID)
        if now {
            let persona = assistant.activePersona(bufferID: bufID)
            conn.appendInfoOnSelected(
                "Assistant engaged on /\(buf.name) — persona: \(persona?.name ?? "none"). New incoming messages will draft a reply you can review.")
        } else {
            assistant.removeHistoryProvider(bufferID: bufID)
            conn.appendInfoOnSelected("Assistant disengaged from /\(buf.name).")
        }
        return now
    }

    // MARK: - Backup

    /// Resolve the user's configured backup directory, expanding `~` and
    /// falling back to the default `~/Downloads/PurpleIRC backup/` when
    /// the field is empty.
    var backupDirectoryURL: URL {
        let raw = settings.settings.backupDirectory.trimmingCharacters(in: .whitespaces)
        let expanded: String
        if raw.isEmpty {
            expanded = (("~/Downloads/PurpleIRC backup/") as NSString).expandingTildeInPath
        } else {
            expanded = (raw as NSString).expandingTildeInPath
        }
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }

    /// Run one backup pass when the user has it enabled. Errors are
    /// logged to AppLog rather than thrown — backup failures shouldn't
    /// surface as crash dialogs to a user who's just launching the app.
    /// Throttled to at most one backup per 60 seconds so the
    /// init-time + post-unlock pair don't both write a copy.
    private static var lastBackupAt: Date = .distantPast
    private static let backupMinInterval: TimeInterval = 60

    func runBackupIfEnabled() {
        guard settings.settings.backupEnabled else { return }
        let now = Date()
        if now.timeIntervalSince(Self.lastBackupAt) < Self.backupMinInterval {
            return
        }
        Self.lastBackupAt = now

        let supportDir = settings.supportDirectoryURL
        let backupDir = backupDirectoryURL
        let key = keyStore.currentKey
        let retention = max(0, settings.settings.backupRetentionDays)

        // Run on a background thread — the zip can take a few seconds
        // for users with chunky log archives. Detached so it doesn't
        // hold up app launch.
        Task.detached(priority: .background) {
            do {
                let url = try BackupService.runBackup(
                    supportDir: supportDir,
                    backupDir: backupDir,
                    key: key)
                let removed = BackupService.trimOldBackups(
                    in: backupDir, retentionDays: retention)
                await MainActor.run {
                    AppLog.shared.info(
                        "Backup written to \(url.path); pruned \(removed) older files.",
                        category: "Backup")
                }
            } catch {
                await MainActor.run {
                    AppLog.shared.error(
                        "Backup failed: \(error.localizedDescription)",
                        category: "Backup")
                }
            }
        }
    }

    /// Force a backup now, bypassing the throttle. Used by the Setup
    /// "Run backup now" button. Returns the URL of the new archive on
    /// success, throws on failure so the UI can surface the error.
    @discardableResult
    func runBackupNow() async throws -> URL {
        Self.lastBackupAt = Date()
        let supportDir = settings.supportDirectoryURL
        let backupDir = backupDirectoryURL
        let key = keyStore.currentKey
        let retention = max(0, settings.settings.backupRetentionDays)
        let url = try BackupService.runBackup(
            supportDir: supportDir, backupDir: backupDir, key: key)
        _ = BackupService.trimOldBackups(in: backupDir, retentionDays: retention)
        AppLog.shared.info("Manual backup written to \(url.path)", category: "Backup")
        return url
    }

    /// Apply a backup archive over the live support directory and quit.
    /// The user picks the archive in the Setup → Backups UI; we perform
    /// the destructive swap here and terminate so the next launch reads
    /// the restored state from a clean process. Errors propagate so the
    /// UI can surface them inline.
    func performRestore(from archiveURL: URL) throws {
        AppLog.shared.notice(
            "Restore triggered from \(archiveURL.path)",
            category: "Restore")
        try BackupService.restore(
            from: archiveURL,
            into: settings.supportDirectoryURL,
            key: keyStore.currentKey)
        AppLog.shared.notice("Restore complete; terminating to relaunch.",
                              category: "Restore")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApplication.shared.terminate(nil)
        }
    }

    // MARK: - Factory reset

    /// Wipe the support directory and quit. Called from the Setup →
    /// Security factory-reset flow after typed confirmation. Doesn't
    /// touch the backup directory — that's the user's escape hatch and
    /// must survive the wipe.
    func performFactoryReset() {
        let supportDir = settings.supportDirectoryURL
        AppLog.shared.notice(
            "Factory reset triggered — wiping \(supportDir.path)",
            category: "Reset")
        do {
            let count = try FactoryReset.wipe(supportDir: supportDir)
            AppLog.shared.notice("Factory reset removed \(count) entries.",
                                  category: "Reset")
        } catch {
            AppLog.shared.error(
                "Factory reset failed: \(error.localizedDescription)",
                category: "Reset")
        }
        // Quit so the next launch starts from a fresh-install state.
        // Doesn't go through performQuit's IRC QUIT path on purpose —
        // we've just wiped the keystore, no point sending a clean QUIT
        // before exiting.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApplication.shared.terminate(nil)
        }
    }

    /// User accepted a suggestion (or edited it). Threads through the
    /// connection's normal sendInput so /msg, history, logs, and the
    /// outbound event all fire as if the user typed it themselves.
    func sendAssistantSuggestion(connectionID: UUID, bufferID: UUID,
                                 text: String) {
        guard let conn = connections.first(where: { $0.id == connectionID }),
              let buf = conn.buffers.first(where: { $0.id == bufferID })
        else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Use /msg so the path is identical to the user typing the
        // message manually — no special-case rendering.
        conn.sendInput("/msg \(buf.name) \(trimmed)", from: bufferID)
        assistant.dismissSuggestion(bufferID: bufferID)
    }
}

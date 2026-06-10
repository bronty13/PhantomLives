import Foundation
import UserNotifications
import AppKit

enum WatchPresence {
    case online
    case offline
    case unknown
}

struct WatchHit: Identifiable, Equatable {
    let id = UUID()
    let nick: String
    let source: String
    let timestamp: Date
}

struct HighlightHit: Identifiable, Equatable {
    let id = UUID()
    let nick: String    // who said it
    let channel: String // where
    let text: String
    let timestamp: Date
}

@MainActor
protocol WatchlistDelegate: AnyObject {
    /// Send a watchlist-sourced raw line (MONITOR / ISON) on a specific
    /// network's socket — `network` is the originating `IRCConnection.id`,
    /// so the line reaches the connection that registered it rather than
    /// whichever one happens to be active.
    func watchlistSendRaw(_ line: String, network: UUID)
    func watchlistPostInfo(_ text: String)
}

@MainActor
final class WatchlistService: ObservableObject {
    @Published private(set) var presence: [String: WatchPresence] = [:]
    @Published private(set) var watched: [String] = []
    /// Lowercased membership set, kept in sync with `watched`, so per-row
    /// "is this from a watched user?" checks are O(1) without rebuilding a
    /// Set on every chat-row render. Updated only in `setWatchedList`.
    private var watchedLower: Set<String> = []
    @Published private(set) var recentHits: [WatchHit] = []
    @Published private(set) var recentHighlights: [HighlightHit] = []
    @Published private(set) var notificationsAuthorized: Bool = false

    // Alert preferences — ChatModel syncs these from SettingsStore.
    var playSound: Bool = true
    var bounceDock: Bool = true
    var systemNotifications: Bool = true
    /// Named NSSound to play for watchlist hits. Empty string = silent.
    /// Defaults to Glass to preserve prior behavior.
    var soundName: String = "Glass"

    /// Per-nick `ContactAlertOverride` resolver. Set by ChatModel at
    /// init so this service can consult per-contact overrides without
    /// importing SettingsStore. Each `fireSystemAlert(...)` call passes
    /// the nick through this closure first; nil result = fall back to
    /// the four global toggles above.
    var contactAlertOverrideResolver: ((String) -> ContactAlertOverride?)? = nil

    /// "Is the user already looking at this conversation?" resolver,
    /// installed by ChatModel. Receives the originating network's
    /// `IRCConnection.id` and the buffer name the message landed in;
    /// returns true when the app is frontmost AND that buffer is the
    /// selected one — in which case message-driven alerts (mention /
    /// highlight-rule banners, sounds, dock bounces) are suppressed.
    /// Gated behind `AppSettings.quietWhenBufferVisible`, which the
    /// resolver itself consults. nil (tests) = never suppress.
    var alertSuppressionResolver: ((UUID, String) -> Bool)? = nil

    private weak var delegate: WatchlistDelegate?

    /// All watch state that is genuinely per-network. Previously these
    /// were single shared fields, which let one connection's disconnect /
    /// ISON reply / MONITOR capability clobber every other network's
    /// state (presence flapping, wrong-socket MONITOR/ISON routing,
    /// single-timer polling). Keyed by `IRCConnection.id`.
    private struct NetworkWatchState {
        var presence: [String: WatchPresence] = [:]
        var supportsMonitor = false
        var serverMonitorLimit = 0
        var isonTimer: Timer?
    }
    private var networks: [UUID: NetworkWatchState] = [:]

    /// Per-nick last-alert timestamp for short-window dedupe across EVERY
    /// alert path — watch-online (MONITOR / ISON / observed activity),
    /// own-nick mention, and highlight-rule matches. Without this, one
    /// message from one person could stack a mention banner + a rule
    /// banner + a watch banner within the same second. One audible/visible
    /// alert per person per window; the in-buffer row tint and the
    /// recent-hits feeds still record everything.
    private var lastAlertAt: [String: Date] = [:]
    private static let alertDedupeWindow: TimeInterval = 3.0

    /// Check-and-stamp the per-nick dedupe gate. Returns false when an
    /// alert for `nick` fired within the window (caller should stay
    /// silent), true otherwise — and records `now` so subsequent callers
    /// across any path see the stamp. Factored out of `fireOnlineAlert`
    /// so mention and rule alerts share the same gate (and so it's
    /// directly testable without touching UNUserNotificationCenter).
    func shouldFireAlert(forNick nick: String, now: Date = Date()) -> Bool {
        let key = nick.lowercased()
        if let last = lastAlertAt[key],
           now.timeIntervalSince(last) < Self.alertDedupeWindow {
            return false
        }
        lastAlertAt[key] = now
        if lastAlertAt.count > 256 {
            let cutoff = now.addingTimeInterval(-Self.alertDedupeWindow * 4)
            lastAlertAt = lastAlertAt.filter { $0.value > cutoff }
        }
        return true
    }

    init() {
        requestAuth()
    }

    /// Test-only init that skips `UNUserNotificationCenter` authorization,
    /// which raises an NSException under xctest (no bundle). Production
    /// code always calls the parameterless `init()`.
    init(skipAuthRequest: Bool) {
        if !skipAuthRequest { requestAuth() }
    }

    func setDelegate(_ d: WatchlistDelegate) {
        self.delegate = d
    }

    /// O(1) case-insensitive membership test against the watched list,
    /// backed by the cached `watchedLower` set.
    func isWatched(_ nick: String) -> Bool {
        watchedLower.contains(nick.lowercased())
    }

    // MARK: - Sync watched list from settings

    func setWatchedList(_ list: [String]) {
        let prev = Set(watched.map { $0.lowercased() })
        let next = Set(list.map { $0.lowercased() })
        let adds = list.filter { !prev.contains($0.lowercased()) }
        let removes = watched.filter { !next.contains($0.lowercased()) }

        watched = list
        watchedLower = next
        // Drop no-longer-watched nicks from every network's presence slice.
        for id in networks.keys {
            for k in Array(networks[id]!.presence.keys) where !next.contains(k) {
                networks[id]!.presence.removeValue(forKey: k)
            }
        }
        recomputeAllAggregates()

        syncRemote(adding: adds, removing: removes)
    }

    // MARK: - Aggregate presence (the OR across all networks)

    /// Rebuild the published `presence` map (the per-nick status the UI
    /// shows) from every network's slice. A nick is online if it's online
    /// on *any* connected network, offline only if known-offline on at
    /// least one and online on none, else unknown. This is what stops a
    /// nick's absence on network B from flipping a nick that's online on
    /// network A.
    private func recomputeAllAggregates() {
        var agg: [String: WatchPresence] = [:]
        for n in watched {
            agg[n.lowercased()] = aggregatePresence(for: n.lowercased())
        }
        presence = agg
    }

    private func aggregatePresence(for key: String) -> WatchPresence {
        var hasOnline = false
        var hasKnown = false
        for st in networks.values {
            if let p = st.presence[key] {
                if p == .online { hasOnline = true }
                if p != .unknown { hasKnown = true }
            }
        }
        return hasOnline ? .online : (hasKnown ? .offline : .unknown)
    }

    /// Set a watched nick's presence on one network, refresh the
    /// aggregate, and fire the online alert only when the *aggregate*
    /// transitions into online (was not online anywhere, now is). Basing
    /// the alert on the aggregate transition — rather than a single
    /// network's view — is what eliminates cross-network alert flapping
    /// and the old `seenInChannel` re-alert suppression hack in one move.
    private func markPresence(nick: String,
                              on network: UUID,
                              to newValue: WatchPresence,
                              source: String) {
        let key = nick.lowercased()
        guard watched.contains(where: { $0.lowercased() == key }) else { return }
        let aggBefore = presence[key] ?? .unknown
        networks[network, default: NetworkWatchState()].presence[key] = newValue
        let aggAfter = aggregatePresence(for: key)
        if presence[key] != aggAfter { presence[key] = aggAfter }
        if aggAfter == .online && aggBefore != .online {
            fireOnlineAlert(nick: nick, source: source)
        }
    }

    // MARK: - Server capability

    func handleISupport(_ tokens: [String], network: UUID) {
        var st = networks[network] ?? NetworkWatchState()
        for t in tokens {
            if t.hasPrefix("MONITOR=") {
                st.supportsMonitor = true
                st.serverMonitorLimit = Int(t.dropFirst("MONITOR=".count)) ?? 100
            } else if t == "MONITOR" {
                st.supportsMonitor = true
                st.serverMonitorLimit = 100
            }
        }
        networks[network] = st
    }

    func onWelcomeCompleted(network: UUID) {
        if networks[network]?.supportsMonitor == true {
            register(network: network)
        } else {
            startISONPolling(network: network)
        }
    }

    func onDisconnected(network: UUID) {
        networks[network]?.isonTimer?.invalidate()
        // Drop only the disconnecting network's slice. Other networks keep
        // their presence, timers, and MONITOR capability untouched.
        networks.removeValue(forKey: network)
        recomputeAllAggregates()
    }

    /// A watched-list change pushes the diff to every connected
    /// MONITOR-capable network on its own socket. ISON networks need no
    /// push — their next poll() already sends the updated list.
    private func syncRemote(adding: [String], removing: [String]) {
        guard let d = delegate else { return }
        for (id, st) in networks where st.supportsMonitor {
            if !adding.isEmpty {
                d.watchlistSendRaw("MONITOR + \(adding.joined(separator: ","))", network: id)
            }
            if !removing.isEmpty {
                d.watchlistSendRaw("MONITOR - \(removing.joined(separator: ","))", network: id)
            }
        }
    }

    private func register(network: UUID) {
        guard let d = delegate, let st = networks[network], !watched.isEmpty else { return }
        let limit = max(1, st.serverMonitorLimit)
        for chunk in watched.chunked(into: limit) {
            d.watchlistSendRaw("MONITOR + \(chunk.joined(separator: ","))", network: network)
        }
    }

    // MARK: - MONITOR numerics

    func handleMonitorOnline(_ targets: [String], network: UUID) {
        for t in targets {
            let nick = t.split(separator: "!").first.map(String.init) ?? t
            markPresence(nick: nick, on: network, to: .online, source: "MONITOR")
        }
    }

    func handleMonitorOffline(_ targets: [String], network: UUID) {
        for t in targets {
            let nick = t.split(separator: "!").first.map(String.init) ?? t
            markPresence(nick: nick, on: network, to: .offline, source: "MONITOR")
        }
    }

    // MARK: - JOIN/PRIVMSG bridge

    func handleObservedActivity(nick: String, reason: String, network: UUID) {
        markPresence(nick: nick, on: network, to: .online, source: reason)
    }

    // MARK: - ISON fallback polling

    private func startISONPolling(network: UUID) {
        networks[network]?.isonTimer?.invalidate()
        guard !watched.isEmpty else { return }
        poll(network: network)
        let timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll(network: network) }
        }
        networks[network, default: NetworkWatchState()].isonTimer = timer
    }

    private func poll(network: UUID) {
        guard let d = delegate, !watched.isEmpty else { return }
        for chunk in watched.chunked(into: 15) {
            d.watchlistSendRaw("ISON " + chunk.joined(separator: " "), network: network)
        }
    }

    func handleISON(_ onlineNicks: [String], network: UUID) {
        let onlineLower = Set(onlineNicks.map { $0.lowercased() })
        for n in watched {
            markPresence(nick: n,
                         on: network,
                         to: onlineLower.contains(n.lowercased()) ? .online : .offline,
                         source: "ISON")
        }
    }

    // MARK: - Notifications

    private func requestAuth() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            Task { @MainActor in self?.notificationsAuthorized = granted }
        }
    }

    func fireTestAlert() {
        fireOnlineAlert(nick: "test-user", source: "manual test")
    }

    private func fireOnlineAlert(nick: String, source: String) {
        // Short-window dedupe across MONITOR / ISON / PRIVMSG sources so a
        // single sighting that simultaneously trips two paths produces one
        // banner, not two. Manual test alerts skip the gate by design so
        // users can verify notification permission repeatedly.
        let now = Date()
        if source != "manual test", !shouldFireAlert(forNick: nick, now: now) {
            return
        }

        let hit = WatchHit(nick: nick, source: source, timestamp: now)
        recentHits.insert(hit, at: 0)
        if recentHits.count > 25 { recentHits.removeLast(recentHits.count - 25) }

        delegate?.watchlistPostInfo("\u{2605}\u{2605}\u{2605} \(nick) is online  (via \(source))")

        fireSystemAlert(
            forContactNick: nick,
            title: "\(nick) is online",
            subtitle: "PurpleIRC watchlist",
            body: "Spotted \(nick) via \(source)",
            identifier: "watch-\(nick)-\(Int(now.timeIntervalSince1970))"
        )
    }

    /// Called by the connection when the user's own nick is mentioned in a
    /// PRIVMSG. The hit is always recorded for the recent-highlights feed;
    /// the alert channels (banner / dock bounce) are skipped when the user
    /// is already viewing that buffer, and deduped per sender so a burst of
    /// mentions from one person produces one alert per window. The mention
    /// *sound* is owned by `ChatModel.playSoundFor` (the per-event "mention"
    /// sound) — this path deliberately stays silent so a single message
    /// can't play two sounds.
    func fireHighlightAlert(nick: String, channel: String, text: String, network: UUID) {
        let hit = HighlightHit(nick: nick, channel: channel, text: text, timestamp: Date())
        recentHighlights.insert(hit, at: 0)
        if recentHighlights.count > 50 { recentHighlights.removeLast(recentHighlights.count - 50) }

        if alertSuppressionResolver?(network, channel) == true { return }
        guard shouldFireAlert(forNick: nick) else { return }

        // Mention alerts also consult per-contact overrides — if the
        // mentioner is in the address book with an alert override, it
        // wins over the global watchlist toggles.
        fireSystemAlert(
            forContactNick: nick,
            title: "\(nick) mentioned you",
            subtitle: channel,
            body: text,
            identifier: "mention-\(nick)-\(Int(Date().timeIntervalSince1970))",
            includeSound: false
        )
    }

    /// Fire a user-configured `HighlightRule` match. Obeys the rule's own
    /// `playSound` / `bounceDock` / `systemNotify` toggles instead of the
    /// watchlist-global flags, so rules are independent of watchlist settings.
    /// `soundName` is the user's configured "highlight" event sound.
    /// Shares the per-sender dedupe gate with mention and watch alerts —
    /// when a message both mentions you and matches a rule, exactly one
    /// alert fires.
    func fireRuleAlert(rule: HighlightRule,
                       from: String,
                       channel: String,
                       text: String,
                       soundName: String,
                       network: UUID) {
        let hit = HighlightHit(nick: from, channel: channel, text: text, timestamp: Date())
        recentHighlights.insert(hit, at: 0)
        if recentHighlights.count > 50 { recentHighlights.removeLast(recentHighlights.count - 50) }

        if alertSuppressionResolver?(network, channel) == true { return }
        guard shouldFireAlert(forNick: from) else { return }

        if rule.bounceDock {
            NSApp.requestUserAttention(.criticalRequest)
        }
        if rule.playSound, !soundName.isEmpty {
            NSSound(named: soundName)?.play()
        }
        if rule.systemNotify {
            let content = UNMutableNotificationContent()
            content.title = rule.name.isEmpty ? "Highlight match" : rule.name
            content.subtitle = "\(from) in \(channel)"
            content.body = text
            content.sound = .default
            let id = "highlight-\(rule.id.uuidString)-\(Int(Date().timeIntervalSince1970))"
            let req = UNNotificationRequest(identifier: id, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(req) { _ in }
        }
    }

    /// Fire the alert channels (banner / sound / dock bounce) for a
    /// watchlist hit. Resolves the four channels by checking the
    /// contact's `ContactAlertOverride` first (via
    /// `contactAlertOverrideResolver`); fields the override doesn't set
    /// fall back to the global toggles.
    ///
    /// `forContactNick` is the nick this alert is about — `nil` for
    /// non-contact-scoped alerts (none today, but the parameter keeps
    /// the API honest about the override boundary).
    ///
    /// `includeSound: false` is the mention path: the per-event "mention"
    /// sound is played by `ChatModel.playSoundFor` on the same message, so
    /// playing the watch-hit sound here too would double up.
    private func fireSystemAlert(forContactNick nick: String?,
                                 title: String,
                                 subtitle: String,
                                 body: String,
                                 identifier: String,
                                 includeSound: Bool = true) {
        let override = nick.flatMap { contactAlertOverrideResolver?($0) }
        let effectiveBounce  = override?.bounceDock   ?? bounceDock
        let effectiveSound   = override?.playSound    ?? playSound
        let effectiveBanner  = override?.systemBanner ?? systemNotifications
        let effectiveSound2  = override?.customSoundName ?? soundName
        let effectiveBody    = override?.customBannerMessage ?? body

        if effectiveBounce {
            NSApp.requestUserAttention(.criticalRequest)
        }
        if includeSound, effectiveSound, !effectiveSound2.isEmpty {
            NSSound(named: effectiveSound2)?.play()
        }
        if effectiveBanner {
            let content = UNMutableNotificationContent()
            content.title = title
            content.subtitle = subtitle
            content.body = effectiveBody
            content.sound = .default
            let req = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(req) { _ in }
        }
    }

    func dismissHit(_ id: UUID) {
        recentHits.removeAll { $0.id == id }
    }

    func clearHits() {
        recentHits.removeAll()
    }

    func clearHighlights() {
        recentHighlights.removeAll()
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

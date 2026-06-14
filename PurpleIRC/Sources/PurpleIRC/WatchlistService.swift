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

    /// When true, the burst of "already online" sightings that arrives in
    /// the first few seconds after a network finishes connecting (the
    /// initial MONITOR/ISON roster) is acknowledged *silently* — those
    /// contacts are marked online and gated as already-alerted, but no
    /// banner/sound/Dock-bounce fires. Off by default: connecting still
    /// alerts you for everyone already online, exactly as before. Opt in to
    /// only be alerted about people who come online *after* you connect.
    /// Synced from `AppSettings.suppressInitialWatchRoster` by ChatModel.
    var suppressInitialRoster: Bool = false

    /// How long after a network's welcome completes its online sightings
    /// count as the "initial roster" and are suppressed (when the setting
    /// above is on). MONITOR/ISON replies to the connect-time registration
    /// land within a second or two; this leaves comfortable headroom.
    private static let rosterPrimeWindow: TimeInterval = 6.0

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
        /// True while this network is inside its connect-time roster window
        /// (see `suppressInitialRoster`). Online sightings on this network
        /// are acknowledged silently while set.
        var primingRoster = false
        /// One-shot timer that ends the priming window. Invalidated on
        /// disconnect alongside `isonTimer`.
        var rosterPrimeTimer: Timer?
        /// Online nicks (lowercased) accumulated across the CURRENT ISON
        /// poll cycle. ISON replies arrive one 303 per `ISON` command, and
        /// each command only carries one chunk of the watched list — so a
        /// nick's absence from any single 303 does NOT mean it's offline.
        /// We union every reply here and decide offline only when the cycle
        /// is finalized at the next poll. Without this, presence flapped
        /// (and re-alerted) every poll for any watchlist over one chunk.
        var isonOnlineAccum: Set<String> = []
    }
    private var networks: [UUID: NetworkWatchState] = [:]

    /// Nicks (lowercased) we've already alerted as online and have NOT
    /// re-armed. This is the "once acknowledged it's gone" gate: an online
    /// alert fires only when a nick is added here, and a nick is only
    /// removed on a *confirmed* aggregate-offline transition (a real
    /// disconnect / logoff seen across every network). Because it's
    /// decoupled from the presence map, a still-online nick whose presence
    /// is re-asserted by repeated ISON/MONITOR/activity sightings never
    /// re-alerts; only an offline-then-online round trip does.
    private var alertedOnline: Set<String> = []

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
        // Drop no-longer-watched nicks from every network's presence slice
        // and ISON accumulator.
        for id in networks.keys {
            for k in Array(networks[id]!.presence.keys) where !next.contains(k) {
                networks[id]!.presence.removeValue(forKey: k)
            }
            networks[id]!.isonOnlineAccum.formIntersection(next)
        }
        // Forget the acknowledged state of anyone removed, so re-adding a
        // nick later starts fresh and alerts on their next online sighting.
        alertedOnline.formIntersection(next)
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
    /// aggregate, and gate the online alert through `alertedOnline` so each
    /// online session produces exactly one alert. The aggregate (the OR
    /// across networks) is what we act on — that already eliminates
    /// cross-network flapping — but the alert itself is gated by
    /// `alertedOnline`, not by the raw transition, so even a same-network
    /// presence flap (or repeated sightings) can't re-fire while the nick
    /// is still considered online. A confirmed aggregate-offline re-arms
    /// the nick so a genuine disconnect→reconnect alerts again; a drop to
    /// `.unknown` (our own client disconnecting) deliberately does NOT
    /// re-arm, or a reconnect would replay an alert for everyone still on.
    private func markPresence(nick: String,
                              on network: UUID,
                              to newValue: WatchPresence,
                              source: String) {
        let key = nick.lowercased()
        guard watched.contains(where: { $0.lowercased() == key }) else { return }
        networks[network, default: NetworkWatchState()].presence[key] = newValue
        let aggAfter = aggregatePresence(for: key)
        if presence[key] != aggAfter { presence[key] = aggAfter }
        switch aggAfter {
        case .online:
            // First online sighting since the last confirmed offline →
            // alert once and mark acknowledged. `Set.insert` is atomic:
            // `.inserted` is true only the first time, so concurrent
            // sources asserting the same nick online can't double-fire.
            if alertedOnline.insert(key).inserted {
                // During a network's connect-time roster window we still
                // mark the nick acknowledged (above) but stay silent — the
                // user opted out of being alerted for people already online
                // when they connected. They'll still get alerted if this
                // person later goes offline and comes back.
                if networks[network]?.primingRoster != true {
                    fireOnlineAlert(nick: nick, source: source)
                }
            }
        case .offline:
            // Confirmed offline everywhere → re-arm for the next round trip.
            alertedOnline.remove(key)
        case .unknown:
            // Information loss, not a confirmed offline → keep the ack flag.
            break
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
        // Open the connect-time roster window first (if opted in) so the
        // MONITOR registration / first ISON poll we kick off right below is
        // treated as the initial roster, not as live arrivals.
        if suppressInitialRoster {
            beginRosterPriming(network: network)
        }
        if networks[network]?.supportsMonitor == true {
            register(network: network)
        } else {
            startISONPolling(network: network)
        }
    }

    func onDisconnected(network: UUID) {
        networks[network]?.isonTimer?.invalidate()
        networks[network]?.rosterPrimeTimer?.invalidate()
        // Drop only the disconnecting network's slice. Other networks keep
        // their presence, timers, and MONITOR capability untouched.
        networks.removeValue(forKey: network)
        recomputeAllAggregates()
    }

    // MARK: - Connect-time roster suppression

    /// Begin (or restart) the connect-time roster window for a network:
    /// while active, online sightings on it are acknowledged silently.
    /// Production schedules `endRosterPriming` after `rosterPrimeWindow`;
    /// tests drive the boundary directly. Internal, not private, so the
    /// test suite can open/close the window without a live run loop.
    func beginRosterPriming(network: UUID) {
        networks[network, default: NetworkWatchState()].rosterPrimeTimer?.invalidate()
        networks[network, default: NetworkWatchState()].primingRoster = true
        let timer = Timer.scheduledTimer(withTimeInterval: Self.rosterPrimeWindow,
                                         repeats: false) { [weak self] _ in
            Task { @MainActor in self?.endRosterPriming(network: network) }
        }
        networks[network, default: NetworkWatchState()].rosterPrimeTimer = timer
    }

    /// Close the roster window: later online sightings on this network
    /// alert normally again.
    func endRosterPriming(network: UUID) {
        networks[network]?.rosterPrimeTimer?.invalidate()
        networks[network]?.rosterPrimeTimer = nil
        networks[network]?.primingRoster = false
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
        // Close out the previous cycle (deciding offline from everything we
        // accumulated) before opening a new one, then fire the chunked
        // queries. By the time this runs — 30s after the last poll — every
        // 303 from the prior cycle has long since arrived.
        beginISONCycle(network: network)
        for chunk in watched.chunked(into: 15) {
            d.watchlistSendRaw("ISON " + chunk.joined(separator: " "), network: network)
        }
    }

    /// Finalize the previous ISON poll cycle and open a fresh accumulator.
    /// Internal (not private) so tests can drive cycle boundaries without
    /// waiting on the 30s `Timer`. Marks any watched nick that did not
    /// appear online in ANY 303 this cycle as offline — the single point
    /// where ISON declares someone offline, which is why a per-reply
    /// absence can no longer flap presence.
    func beginISONCycle(network: UUID) {
        if let accum = networks[network]?.isonOnlineAccum {
            for n in watched where !accum.contains(n.lowercased()) {
                markPresence(nick: n, on: network, to: .offline, source: "ISON")
            }
        }
        networks[network, default: NetworkWatchState()].isonOnlineAccum.removeAll()
    }

    func handleISON(_ onlineNicks: [String], network: UUID) {
        // Online evidence is safe to apply immediately — a nick listed in a
        // 303 really is online. We also union it into this cycle's
        // accumulator; absence is reconciled to offline only at the next
        // `beginISONCycle`, never from a single (chunked) reply.
        for n in onlineNicks {
            let key = n.lowercased()
            guard watched.contains(where: { $0.lowercased() == key }) else { continue }
            networks[network, default: NetworkWatchState()].isonOnlineAccum.insert(key)
            markPresence(nick: n, on: network, to: .online, source: "ISON")
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
        // Dedupe is owned by the `alertedOnline` gate in `markPresence`:
        // this fires at most once per online session (and re-arms only on a
        // confirmed offline), so MONITOR / ISON / PRIVMSG sightings of an
        // already-online nick never reach here a second time. We deliberately
        // do NOT consult the shared short-window `shouldFireAlert` gate here —
        // it would wrongly swallow a genuine offline→online re-alert that
        // lands within its window. Manual test alerts call straight in.
        let now = Date()
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

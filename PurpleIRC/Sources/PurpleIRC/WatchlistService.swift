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
    func watchlistSendRaw(_ line: String)
    func watchlistPostInfo(_ text: String)
}

@MainActor
final class WatchlistService: ObservableObject {
    @Published private(set) var presence: [String: WatchPresence] = [:]
    @Published private(set) var watched: [String] = []
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

    private weak var delegate: WatchlistDelegate?
    private var supportsMonitor = false
    private var serverMonitorLimit: Int = 0
    private var isonTimer: Timer?
    private var seenInChannel: Set<String> = []

    init() {
        requestAuth()
    }

    func setDelegate(_ d: WatchlistDelegate) {
        self.delegate = d
    }

    // MARK: - Sync watched list from settings

    func setWatchedList(_ list: [String]) {
        let prev = Set(watched.map { $0.lowercased() })
        let next = Set(list.map { $0.lowercased() })
        let adds = list.filter { !prev.contains($0.lowercased()) }
        let removes = watched.filter { !next.contains($0.lowercased()) }

        watched = list
        for n in list where presence[n.lowercased()] == nil {
            presence[n.lowercased()] = .unknown
        }
        for k in Array(presence.keys) where !next.contains(k) {
            presence.removeValue(forKey: k)
        }

        syncRemote(adding: adds, removing: removes)
    }

    // MARK: - Server capability

    func handleISupport(_ tokens: [String]) {
        for t in tokens {
            if t.hasPrefix("MONITOR=") {
                let n = Int(t.dropFirst("MONITOR=".count)) ?? 100
                supportsMonitor = true
                serverMonitorLimit = n
            } else if t == "MONITOR" {
                supportsMonitor = true
                serverMonitorLimit = 100
            }
        }
    }

    func onWelcomeCompleted() {
        if supportsMonitor {
            register(allWatched: true)
        } else {
            startISONPolling()
        }
    }

    func onDisconnected() {
        isonTimer?.invalidate()
        isonTimer = nil
        for k in presence.keys { presence[k] = .unknown }
        seenInChannel.removeAll()
        supportsMonitor = false
        serverMonitorLimit = 0
    }

    private func syncRemote(adding: [String], removing: [String]) {
        guard let d = delegate else { return }
        if supportsMonitor {
            if !adding.isEmpty {
                d.watchlistSendRaw("MONITOR + \(adding.joined(separator: ","))")
            }
            if !removing.isEmpty {
                d.watchlistSendRaw("MONITOR - \(removing.joined(separator: ","))")
            }
        }
    }

    private func register(allWatched: Bool) {
        guard let d = delegate, !watched.isEmpty else { return }
        let limit = max(1, serverMonitorLimit)
        for chunk in watched.chunked(into: limit) {
            d.watchlistSendRaw("MONITOR + \(chunk.joined(separator: ","))")
        }
    }

    // MARK: - MONITOR numerics

    func handleMonitorOnline(_ targets: [String]) {
        for t in targets {
            let nick = t.split(separator: "!").first.map(String.init) ?? t
            let key = nick.lowercased()
            let prev = presence[key] ?? .unknown
            presence[key] = .online
            if prev != .online {
                fireOnlineAlert(nick: nick, source: "MONITOR")
            }
        }
    }

    func handleMonitorOffline(_ targets: [String]) {
        for t in targets {
            let nick = t.split(separator: "!").first.map(String.init) ?? t
            let key = nick.lowercased()
            presence[key] = .offline
        }
    }

    // MARK: - JOIN/PRIVMSG bridge

    func handleObservedActivity(nick: String, reason: String) {
        guard watched.contains(where: { $0.caseInsensitiveCompare(nick) == .orderedSame }) else { return }
        let key = nick.lowercased()
        let prev = presence[key] ?? .unknown
        presence[key] = .online
        if prev != .online && !seenInChannel.contains(key) {
            fireOnlineAlert(nick: nick, source: reason)
        }
        seenInChannel.insert(key)
    }

    // MARK: - ISON fallback polling

    private func startISONPolling() {
        isonTimer?.invalidate()
        guard !watched.isEmpty else { return }
        poll()
        isonTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    private func poll() {
        guard let d = delegate, !watched.isEmpty else { return }
        for chunk in watched.chunked(into: 15) {
            d.watchlistSendRaw("ISON " + chunk.joined(separator: " "))
        }
    }

    func handleISON(_ onlineNicks: [String]) {
        let onlineLower = Set(onlineNicks.map { $0.lowercased() })
        for n in watched {
            let k = n.lowercased()
            let prev = presence[k] ?? .unknown
            let nowOnline = onlineLower.contains(k)
            presence[k] = nowOnline ? .online : .offline
            if nowOnline && prev != .online {
                fireOnlineAlert(nick: n, source: "ISON")
            }
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
        let hit = WatchHit(nick: nick, source: source, timestamp: Date())
        recentHits.insert(hit, at: 0)
        if recentHits.count > 25 { recentHits.removeLast(recentHits.count - 25) }

        delegate?.watchlistPostInfo("\u{2605}\u{2605}\u{2605} \(nick) is online  (via \(source))")

        fireSystemAlert(
            title: "\(nick) is online",
            subtitle: "PurpleIRC watchlist",
            body: "Spotted \(nick) via \(source)",
            identifier: "watch-\(nick)-\(Int(Date().timeIntervalSince1970))"
        )
    }

    /// Called by ChatModel when the user's own nick is mentioned in a PRIVMSG.
    func fireHighlightAlert(nick: String, channel: String, text: String) {
        let hit = HighlightHit(nick: nick, channel: channel, text: text, timestamp: Date())
        recentHighlights.insert(hit, at: 0)
        if recentHighlights.count > 50 { recentHighlights.removeLast(recentHighlights.count - 50) }

        fireSystemAlert(
            title: "\(nick) mentioned you",
            subtitle: channel,
            body: text,
            identifier: "mention-\(nick)-\(Int(Date().timeIntervalSince1970))"
        )
    }

    /// Fire a user-configured `HighlightRule` match. Obeys the rule's own
    /// `playSound` / `bounceDock` / `systemNotify` toggles instead of the
    /// watchlist-global flags, so rules are independent of watchlist settings.
    /// `soundName` is the user's configured "highlight" event sound.
    func fireRuleAlert(rule: HighlightRule,
                       from: String,
                       channel: String,
                       text: String,
                       soundName: String) {
        let hit = HighlightHit(nick: from, channel: channel, text: text, timestamp: Date())
        recentHighlights.insert(hit, at: 0)
        if recentHighlights.count > 50 { recentHighlights.removeLast(recentHighlights.count - 50) }

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

    private func fireSystemAlert(title: String, subtitle: String, body: String, identifier: String) {
        if bounceDock {
            NSApp.requestUserAttention(.criticalRequest)
        }
        if playSound, !soundName.isEmpty {
            NSSound(named: soundName)?.play()
        }
        if systemNotifications {
            let content = UNMutableNotificationContent()
            content.title = title
            content.subtitle = subtitle
            content.body = body
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

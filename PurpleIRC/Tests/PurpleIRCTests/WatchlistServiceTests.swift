import Foundation
import Testing
@testable import PurpleIRC

/// Per-network behaviour for `WatchlistService`. Before the per-network
/// refactor this was a single shared bag of state, so one connection's
/// ISON reply / disconnect / MONITOR capability clobbered every other
/// network (presence flapping, wrong-socket routing, a single shared
/// timer). These tests pin the fixes: state is keyed by network id,
/// presence is the OR across networks, and MONITOR/ISON lines are sent
/// on the originating network's socket.
@MainActor
@Suite("WatchlistService per-network")
struct WatchlistServiceTests {

    /// Captures everything the service routes out, tagged with the
    /// network id it was addressed to.
    final class CaptureDelegate: WatchlistDelegate {
        var sends: [(network: UUID, line: String)] = []
        var infos: [String] = []
        func watchlistSendRaw(_ line: String, network: UUID) {
            sends.append((network, line))
        }
        func watchlistPostInfo(_ text: String) { infos.append(text) }
    }

    /// Build a service with all user-facing alert channels muted so
    /// `fireOnlineAlert` never reaches `NSSound` / `UNUserNotificationCenter`
    /// (which misbehave under xctest). We still observe alerts through the
    /// `recentHits` log, which is populated before any of that.
    private func makeService() -> (WatchlistService, CaptureDelegate) {
        let svc = WatchlistService(skipAuthRequest: true)
        svc.playSound = false
        svc.bounceDock = false
        svc.systemNotifications = false
        let d = CaptureDelegate()
        svc.setDelegate(d)
        return (svc, d)
    }

    // MARK: - Presence aggregation / no cross-network flapping

    @Test func absenceOnOneNetworkDoesNotFlipOnlineOnAnother() {
        let (svc, _) = makeService()
        let a = UUID(); let b = UUID()
        svc.setWatchedList(["alice"])

        // alice online on A → one alert, aggregate online.
        svc.handleISON(["alice"], network: a)
        #expect(svc.presence["alice"] == .online)
        #expect(svc.recentHits.count == 1)

        // B's ISON reply doesn't list alice. Pre-refactor this flipped her
        // to .offline and the next A poll re-fired the online alert. Now
        // the aggregate stays online and nothing re-fires.
        svc.handleISON([], network: b)
        #expect(svc.presence["alice"] == .online)
        #expect(svc.recentHits.count == 1)
    }

    @Test func disconnectClearsOnlyTheDisconnectingNetwork() {
        let (svc, _) = makeService()
        let a = UUID(); let b = UUID()
        svc.setWatchedList(["alice"])

        svc.handleISON(["alice"], network: a)
        svc.handleISON(["alice"], network: b)
        #expect(svc.presence["alice"] == .online)
        #expect(svc.recentHits.count == 1)   // single online transition

        // B drops — A is still connected and still has alice online.
        svc.onDisconnected(network: b)
        #expect(svc.presence["alice"] == .online)

        // A drops too — now no network knows her state.
        svc.onDisconnected(network: a)
        #expect(svc.presence["alice"] == .unknown)
    }

    // MARK: - ISON chunk accumulation (no per-reply flapping)

    @Test func multiChunkIsonReplyDoesNotFlapAbsentNick() {
        let (svc, _) = makeService()
        let net = UUID()
        svc.setWatchedList(["alice", "bob"])

        // A poll over a watchlist spanning two ISON chunks comes back as two
        // separate 303 replies. The first lists alice, the second bob.
        svc.handleISON(["alice"], network: net)
        #expect(svc.presence["alice"] == .online)
        #expect(svc.recentHits.count == 1)

        // bob's reply must NOT knock alice offline (the old bug marked every
        // watched nick missing from a single reply as offline, so the next
        // poll re-fired alice's online alert).
        svc.handleISON(["bob"], network: net)
        #expect(svc.presence["alice"] == .online)
        #expect(svc.presence["bob"] == .online)
        #expect(svc.recentHits.count == 2)   // alice once, bob once — no re-fire
    }

    // MARK: - Acknowledge-once / re-arm-on-offline

    @Test func onlineAlertFiresOnceAndStaysAcknowledgedAcrossPolls() {
        let (svc, _) = makeService()
        let net = UUID()
        svc.setWatchedList(["alice"])

        // First sighting alerts.
        svc.handleISON(["alice"], network: net)
        #expect(svc.recentHits.count == 1)

        // Subsequent poll cycles that keep finding alice online must NOT
        // re-alert — once acknowledged, the alert is gone until she leaves.
        for _ in 0..<5 {
            svc.beginISONCycle(network: net)
            svc.handleISON(["alice"], network: net)
        }
        #expect(svc.presence["alice"] == .online)
        #expect(svc.recentHits.count == 1)
    }

    @Test func offlineThenOnlineReArmsAndReAlerts() {
        let (svc, _) = makeService()
        let net = UUID()
        svc.setWatchedList(["alice"])

        svc.handleISON(["alice"], network: net)
        #expect(svc.recentHits.count == 1)

        // alice drops off: the next poll cycle finalizes with her absent
        // from everything accumulated, so she's marked offline.
        svc.beginISONCycle(network: net)          // closes the cycle she was in
        svc.handleISON([], network: net)          // fresh cycle, alice not seen
        svc.beginISONCycle(network: net)          // finalize → alice offline
        #expect(svc.presence["alice"] == .offline)
        #expect(svc.recentHits.count == 1)        // going offline doesn't alert

        // She comes back — this is a genuine round trip, so it alerts again.
        svc.handleISON(["alice"], network: net)
        #expect(svc.presence["alice"] == .online)
        #expect(svc.recentHits.count == 2)
    }

    @Test func ownDisconnectDoesNotReArmStillOnlineNick() {
        let (svc, _) = makeService()
        let net = UUID()
        svc.setWatchedList(["alice"])

        svc.handleISON(["alice"], network: net)
        #expect(svc.recentHits.count == 1)

        // Our client drops the connection (presence becomes unknown, not a
        // confirmed offline) then reconnects and re-polls. A reconnect must
        // not replay an alert for someone who never actually left.
        svc.onDisconnected(network: net)
        #expect(svc.presence["alice"] == .unknown)
        svc.handleISON(["alice"], network: net)
        #expect(svc.recentHits.count == 1)
    }

    @Test func reAddingARemovedNickReArms() {
        let (svc, _) = makeService()
        let net = UUID()
        svc.setWatchedList(["alice"])
        svc.handleISON(["alice"], network: net)
        #expect(svc.recentHits.count == 1)

        // Drop alice from the watchlist, then add her back: her acknowledged
        // state is forgotten, so her next online sighting alerts afresh.
        svc.setWatchedList([])
        svc.setWatchedList(["alice"])
        svc.handleISON(["alice"], network: net)
        #expect(svc.recentHits.count == 2)
    }

    // MARK: - Connect-time roster suppression (opt-in)

    @Test func initialRosterAlertsWhenSuppressionOff() {
        // Default behavior: connecting alerts you for everyone already on.
        let (svc, _) = makeService()       // suppressInitialRoster defaults off
        let net = UUID()
        svc.setWatchedList(["alice", "bob"])
        svc.handleISON(["alice", "bob"], network: net)
        #expect(svc.recentHits.count == 2)
    }

    @Test func initialRosterIsSilentWhenSuppressionOn() {
        let (svc, _) = makeService()
        svc.suppressInitialRoster = true
        let net = UUID()
        svc.setWatchedList(["alice", "bob"])
        svc.beginRosterPriming(network: net)

        // The connect-time roster is acknowledged but silent.
        svc.handleISON(["alice", "bob"], network: net)
        #expect(svc.presence["alice"] == .online)
        #expect(svc.presence["bob"] == .online)
        #expect(svc.recentHits.isEmpty)

        // Window closes; re-seeing the same already-acknowledged people
        // still doesn't alert (they never left).
        svc.endRosterPriming(network: net)
        svc.beginISONCycle(network: net)
        svc.handleISON(["alice", "bob"], network: net)
        #expect(svc.recentHits.isEmpty)
    }

    @Test func arrivalAfterRosterWindowAlertsEvenWhenSuppressionOn() {
        let (svc, _) = makeService()
        svc.suppressInitialRoster = true
        let net = UUID()
        svc.setWatchedList(["alice", "carol"])
        svc.beginRosterPriming(network: net)

        // Only alice is on at connect → silently acknowledged.
        svc.handleISON(["alice"], network: net)
        #expect(svc.recentHits.isEmpty)

        // Window closes. carol was offline at connect and now comes online
        // → a genuine post-connect arrival, so it alerts.
        svc.endRosterPriming(network: net)
        svc.beginISONCycle(network: net)
        svc.handleISON(["alice", "carol"], network: net)
        #expect(svc.recentHits.count == 1)
        #expect(svc.recentHits.first?.nick == "carol")
    }

    @Test func rosterMemberWhoDropsAndReturnsStillAlertsUnderSuppression() {
        let (svc, _) = makeService()
        svc.suppressInitialRoster = true
        let net = UUID()
        svc.setWatchedList(["alice"])
        svc.beginRosterPriming(network: net)

        // alice present at connect → silent.
        svc.handleISON(["alice"], network: net)
        #expect(svc.recentHits.isEmpty)
        svc.endRosterPriming(network: net)

        // alice drops…
        svc.beginISONCycle(network: net)
        svc.handleISON([], network: net)
        svc.beginISONCycle(network: net)
        #expect(svc.presence["alice"] == .offline)

        // …and comes back: a real round trip, so now it alerts.
        svc.handleISON(["alice"], network: net)
        #expect(svc.recentHits.count == 1)
    }

    // MARK: - Command routing to the originating socket

    @Test func monitorAndIsonGoToTheirOwnNetworkSocket() {
        let (svc, d) = makeService()
        let monNet = UUID()   // supports MONITOR
        let isonNet = UUID()  // ISON fallback
        svc.setWatchedList(["alice", "bob"])

        svc.handleISupport(["MONITOR=100"], network: monNet)
        svc.onWelcomeCompleted(network: monNet)
        svc.onWelcomeCompleted(network: isonNet)

        let monSends = d.sends.filter { $0.network == monNet }
        let isonSends = d.sends.filter { $0.network == isonNet }

        // MONITOR network registers via MONITOR + on ITS socket, never ISON.
        #expect(monSends.contains { $0.line.hasPrefix("MONITOR + ") && $0.line.contains("alice") })
        #expect(!monSends.contains { $0.line.hasPrefix("ISON") })

        // ISON network polls via ISON on ITS socket, never MONITOR.
        #expect(isonSends.contains { $0.line.hasPrefix("ISON ") })
        #expect(!isonSends.contains { $0.line.hasPrefix("MONITOR") })

        // cleanup the ISON poll timer
        svc.onDisconnected(network: monNet)
        svc.onDisconnected(network: isonNet)
    }

    @Test func watchedListChangePushesDiffOnlyToMonitorNetworks() {
        let (svc, d) = makeService()
        let monNet = UUID()
        let isonNet = UUID()

        svc.handleISupport(["MONITOR=100"], network: monNet)
        svc.onWelcomeCompleted(network: monNet)
        svc.onWelcomeCompleted(network: isonNet)
        d.sends.removeAll()

        // Add a nick. Only the MONITOR network gets a MONITOR + diff; the
        // ISON network picks the new nick up on its next poll, so it gets
        // nothing here.
        svc.setWatchedList(["carol"])
        #expect(d.sends.contains { $0.network == monNet && $0.line == "MONITOR + carol" })
        #expect(d.sends.allSatisfy { $0.network == monNet })

        svc.onDisconnected(network: monNet)
        svc.onDisconnected(network: isonNet)
    }

    // MARK: - MONITOR online/offline are per-network too

    // MARK: - Cross-path alert dedupe + quiet-mode suppression

    @Test func dedupeGateIsPerSenderAndTimeWindowed() {
        let (svc, _) = makeService()
        let t0 = Date()
        #expect(svc.shouldFireAlert(forNick: "Alice", now: t0))
        // Same sender (case-insensitive) inside the window → suppressed.
        #expect(!svc.shouldFireAlert(forNick: "alice", now: t0.addingTimeInterval(1)))
        // A different sender gets its own gate.
        #expect(svc.shouldFireAlert(forNick: "bob", now: t0.addingTimeInterval(1)))
        // Same sender after the window expires → fires again.
        #expect(svc.shouldFireAlert(forNick: "alice", now: t0.addingTimeInterval(10)))
    }

    @Test func mentionAlertStampsTheSharedGateSoRulePathStaysQuiet() {
        let (svc, _) = makeService()
        svc.fireHighlightAlert(nick: "alice", channel: "#swift",
                               text: "ping you", network: UUID())
        #expect(svc.recentHighlights.count == 1)
        // fireRuleAlert consults this same per-sender gate, so a message
        // that both mentions the user and matches a rule produces exactly
        // one audible/visible alert.
        #expect(!svc.shouldFireAlert(forNick: "alice"))
    }

    @Test func suppressedMentionStillRecordsHitButDoesNotStampGate() {
        let (svc, _) = makeService()
        // Quiet-mode resolver says the user is viewing this buffer.
        svc.alertSuppressionResolver = { _, _ in true }
        svc.fireHighlightAlert(nick: "alice", channel: "#swift",
                               text: "hey", network: UUID())
        // The recent-highlights feed still records it…
        #expect(svc.recentHighlights.count == 1)
        // …but the dedupe gate was NOT stamped — a follow-up mention in a
        // buffer the user is NOT viewing must still alert.
        #expect(svc.shouldFireAlert(forNick: "alice"))
    }

    @Test func monitorOfflineOnOneNetworkKeepsOnlineFromAnother() {
        let (svc, _) = makeService()
        let a = UUID(); let b = UUID()
        svc.setWatchedList(["dave"])

        svc.handleMonitorOnline(["dave!u@h"], network: a)
        svc.handleMonitorOnline(["dave!u@h"], network: b)
        #expect(svc.presence["dave"] == .online)
        #expect(svc.recentHits.count == 1)

        // dave signs off on B only — A still has him.
        svc.handleMonitorOffline(["dave"], network: b)
        #expect(svc.presence["dave"] == .online)

        // now off A as well → offline everywhere.
        svc.handleMonitorOffline(["dave"], network: a)
        #expect(svc.presence["dave"] == .offline)
    }
}

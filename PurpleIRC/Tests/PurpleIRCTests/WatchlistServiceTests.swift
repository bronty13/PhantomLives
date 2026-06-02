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

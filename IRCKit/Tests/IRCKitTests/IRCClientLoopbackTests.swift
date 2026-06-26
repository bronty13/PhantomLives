import Testing
import Foundation
import Network
import IRCKit

/// Loopback stress harness for `IRCClient`'s threading.
///
/// `IRCClient` runs its `NWConnection` on a private serial queue
/// (`IRCKit.client`) but exposes a *synchronous* API (`connect`/`disconnect`/
/// `send`) that callers invoke from the main actor. Its mutable connection
/// state (`connection`, `buffer`, `negotiator`, …) is therefore touched from
/// two threads. This suite stands up a local `NWListener` that accepts the
/// client and trickles bytes back (to keep the receive/`drainBuffer` path busy
/// on the client's queue), then drives connect/send/disconnect/reconnect from
/// other threads.
///
/// Purpose is two-fold:
///   1. Functional coverage of the (previously untested) reconnect path.
///   2. A **ThreadSanitizer** target that proves there is no data race on the
///      connection state. Run it with:
///
///         IRCKIT_STRESS=1 swift test --sanitize=thread \
///             --filter IRCClientLoopbackTests
///
///      Against the pre-fix engine TSan flags `connection` / `buffer`; against
///      the queue-confined engine it is clean (ignore any races reported
///      purely inside `Network.framework`/`libnetwork` — those are Apple's, not
///      IRCKit's; look for `IRCClient.swift` frames).
@Suite struct IRCClientLoopbackTests {

    // MARK: - Test helpers

    /// Thread-safe tally of observed connection states. Tests capture a
    /// baseline count *before* an action, then wait for the count to rise —
    /// race-free against states that fire before the wait is entered.
    final class StateLatch: @unchecked Sendable {
        private let lock = NSLock()
        private var counts: [String: Int] = [:]

        func record(_ s: IRCConnectionState) {
            let key = Self.key(s)
            lock.lock(); counts[key, default: 0] += 1; lock.unlock()
        }
        func count(_ key: String) -> Int {
            lock.lock(); defer { lock.unlock() }; return counts[key, default: 0]
        }
        /// Poll until `count(key)` exceeds `baseline` or the timeout elapses.
        func waitAbove(_ key: String, _ baseline: Int, timeout: TimeInterval) -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if count(key) > baseline { return true }
                usleep(2_000)
            }
            return count(key) > baseline
        }
        static func key(_ s: IRCConnectionState) -> String {
            switch s {
            case .connected:    return "connected"
            case .disconnected: return "disconnected"
            case .connecting:   return "connecting"
            case .failed:       return "failed"
            }
        }
    }

    /// Minimal loopback "server": accepts connections, drains whatever the
    /// client writes, and (optionally) trickles IRC-looking lines back so the
    /// client's receive loop keeps mutating its `buffer`.
    final class LoopbackServer: @unchecked Sendable {
        let listener: NWListener
        let queue = DispatchQueue(label: "loopback.server")
        private var conns: [NWConnection] = []
        private(set) var port: UInt16 = 0
        private let trickle: Bool

        init(trickle: Bool = true) throws {
            self.trickle = trickle
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            listener = try NWListener(using: params)            // ephemeral port
            listener.newConnectionHandler = { [weak self] c in self?.accept(c) }
        }

        func start() {
            let sem = DispatchSemaphore(value: 0)
            listener.stateUpdateHandler = { st in if case .ready = st { sem.signal() } }
            listener.start(queue: queue)
            _ = sem.wait(timeout: .now() + 5)
            port = listener.port?.rawValue ?? 0
        }

        private func accept(_ c: NWConnection) {
            conns.append(c)                                     // on listener queue
            c.start(queue: queue)
            drain(c)
            if trickle { pump(c) }
        }

        private func drain(_ c: NWConnection) {
            c.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] _, _, done, err in
                guard let self, !done, err == nil else { return }
                self.drain(c)
            }
        }

        private func pump(_ c: NWConnection) {
            let line = Data("PING :loopback\r\n".utf8)
            c.send(content: line, completion: .contentProcessed { [weak self] err in
                guard let self, err == nil else { return }
                self.queue.asyncAfter(deadline: .now() + 0.002) { [weak self] in
                    guard let self else { return }
                    if case .ready = c.state { self.pump(c) }
                }
            })
        }

        func stop() {
            listener.cancel()
            queue.async { self.conns.forEach { $0.cancel() }; self.conns.removeAll() }
        }
    }

    private func cfg(port: UInt16) -> IRCConnectionConfig {
        IRCConnectionConfig(host: "127.0.0.1", port: port, useTLS: false,
                            nick: "tsan", user: "tsan", realName: "tsan probe")
    }

    // MARK: - Tests

    /// Functional: connect → connected, disconnect → disconnected, then
    /// reconnect → connected again. New coverage for the reconnect path.
    @Test func reconnectReachesConnectedTwice() async throws {
        let server = try LoopbackServer(); server.start()
        #expect(server.port != 0)
        defer { server.stop() }

        let latch = StateLatch()
        let client = IRCClient()
        client.onState = { latch.record($0) }

        var base = latch.count("connected")
        client.connect(config: cfg(port: server.port))
        #expect(latch.waitAbove("connected", base, timeout: 8))

        base = latch.count("disconnected")
        client.disconnect(quitMessage: "bye")
        #expect(latch.waitAbove("disconnected", base, timeout: 8))

        base = latch.count("connected")
        client.connect(config: cfg(port: server.port))
        #expect(latch.waitAbove("connected", base, timeout: 8))

        client.disconnect()
    }

    /// Stress: hammer `send()` from a background thread while the receive loop
    /// runs and the connection is repeatedly torn down + rebuilt. This is the
    /// ThreadSanitizer target for the `connection` use-after-free on the hot
    /// send path. Gated behind `IRCKIT_STRESS` so normal runs stay fast.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["IRCKIT_STRESS"] != nil))
    func concurrentSendDisconnectReconnectStress() async throws {
        let server = try LoopbackServer(); server.start()
        #expect(server.port != 0)
        defer { server.stop() }

        let client = IRCClient()
        let latch = StateLatch()
        client.onState = { latch.record($0) }

        for _ in 0..<10 {
            let base = latch.count("connected")
            client.connect(config: cfg(port: server.port))
            _ = latch.waitAbove("connected", base, timeout: 5)

            // Hammer send() from a background task concurrently with the
            // receive loop, then tear down mid-flight.
            let hammer = Task.detached {
                for _ in 0..<500 { client.send("PRIVMSG #x :hammer") }
            }
            try? await Task.sleep(nanoseconds: 15_000_000)   // overlap with receive loop
            client.disconnect(quitMessage: "bye")
            await hammer.value
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        client.disconnect()
    }
}

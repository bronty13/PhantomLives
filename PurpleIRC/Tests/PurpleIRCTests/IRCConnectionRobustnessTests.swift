import Foundation
import IRCKit
import Testing
@testable import PurpleIRC

/// Robustness invariants for `IRCConnection` that don't need a live socket.
///
/// These exercises drive parsed `IRCMessage`s through the (internal)
/// `handle(_:)` entry point and observe state through the narrow
/// `_test*` accessors at the bottom of `IRCConnection.swift`. The
/// connection's `IRCClient` is never connected — `send()` early-returns
/// when the underlying `NWConnection` is nil — so feeding messages
/// in is side-effect-free outside the connection's own bookkeeping.
@MainActor
@Suite("IRCConnection robustness")
struct IRCConnectionRobustnessTests {

    // MARK: - Helpers

    private func makeConnection(nick: String = "purple-user") -> IRCConnection {
        let profile = ServerProfile(
            name: "Test Network",
            host: "irc.example.org",
            port: 6697,
            useTLS: true,
            nick: nick,
            user: "purpleirc",
            realName: "PurpleIRC",
            autoReconnect: false
        )
        return IRCConnection(profile: profile,
                             watchlist: WatchlistService(skipAuthRequest: true))
    }

    private func parse(_ line: String) -> IRCMessage {
        guard let m = IRCMessage.parse(line) else {
            Issue.record("Test line failed to parse: \(line)")
            fatalError("unreachable")
        }
        return m
    }

    // MARK: - 433 nick-collision retry cap
    //
    // The 1.0.92 security & robustness pass capped 433 retries at 4. Without
    // a cap the underscore tail grew forever and we'd eventually trip the
    // server's NICKLEN, generating a cascading 432/433 storm with no path
    // to registration. After the cap we mark `userInitiatedDisconnect` and
    // tear down the link so the auto-reconnect path doesn't loop on the
    // same failure.

    @Test func nickCollisionRetriesIncrementOnEach433() {
        let conn = makeConnection(nick: "alice")
        #expect(conn._testNickCollisionRetryCount == 0)

        _ = conn.handle(parse(":server 433 * alice :Nickname is already in use"))
        #expect(conn._testNickCollisionRetryCount == 1)
        #expect(conn.nick == "alice_")

        _ = conn.handle(parse(":server 433 * alice_ :Nickname is already in use"))
        #expect(conn._testNickCollisionRetryCount == 2)
        #expect(conn.nick == "alice__")
    }

    @Test func nickCollision433CapsAtMaxAndDisconnects() {
        let conn = makeConnection(nick: "alice")
        let max = IRCConnection._testMaxNickCollisionRetries

        // Fire `max` 433s — the counter ticks up to `max`, still under the
        // cap, and the connection keeps trying.
        for _ in 0..<max {
            _ = conn.handle(parse(":server 433 * \(conn.nick) :in use"))
        }
        #expect(conn._testNickCollisionRetryCount == max)
        #expect(conn._testUserInitiatedDisconnect == false)

        // One more — the counter goes to max+1, the cap trips, the
        // connection self-disconnects so the reconnect path doesn't loop
        // on the same failure.
        _ = conn.handle(parse(":server 433 * \(conn.nick) :in use"))
        #expect(conn._testNickCollisionRetryCount == max + 1)
        #expect(conn._testUserInitiatedDisconnect == true)
    }

    @Test func nickCollisionRetriesResetOn001() {
        let conn = makeConnection(nick: "alice")

        _ = conn.handle(parse(":server 433 * alice :in use"))
        _ = conn.handle(parse(":server 433 * alice_ :in use"))
        #expect(conn._testNickCollisionRetryCount == 2)

        // Welcome numeric → reset. Real servers fire 001 after the
        // registration burst completes, so subsequent 433s (from a /nick
        // attempt later in the session) start counting from zero again.
        _ = conn.handle(parse(":server 001 alice__ :Welcome to Test Network"))
        #expect(conn._testNickCollisionRetryCount == 0)
        // 001 also picks up the server's authoritative nick assignment.
        #expect(conn.nick == "alice__")
    }

    // MARK: - BATCH cap + reset
    //
    // `openBatches` is bounded at `maxOpenBatches` (256) so a hostile or
    // buggy server can't exhaust memory by opening batches forever. A
    // duplicate `+id` overwrites and logs a warning. An orphan `-id` (no
    // matching `+id`) is silently dropped — flaky links produce them and
    // there's nothing the user can do.

    @Test func batchPlusOpensAndMinusCloses() {
        let conn = makeConnection()
        #expect(conn._testOpenBatchCount == 0)

        _ = conn.handle(parse("BATCH +abc chathistory #room"))
        #expect(conn._testOpenBatchCount == 1)
        #expect(conn._testHasOpenBatch("abc"))

        _ = conn.handle(parse("BATCH -abc"))
        #expect(conn._testOpenBatchCount == 0)
        #expect(conn._testHasOpenBatch("abc") == false)
    }

    @Test func orphanBatchMinusIsSilentNoOp() {
        let conn = makeConnection()
        _ = conn.handle(parse("BATCH -never-opened"))
        // No crash, no entry added. Production code logs nothing for this
        // — flaky links produce orphan `-id` and there's nothing actionable.
        #expect(conn._testOpenBatchCount == 0)
    }

    @Test func duplicateBatchPlusReplacesPriorEntry() {
        let conn = makeConnection()
        _ = conn.handle(parse("BATCH +xyz chathistory #room1"))
        _ = conn.handle(parse("BATCH +xyz chathistory #room2"))
        // Cap was honoured (count didn't grow past 1), and the id still
        // resolves — the second open replaces the first, not appends.
        #expect(conn._testOpenBatchCount == 1)
        #expect(conn._testHasOpenBatch("xyz"))
    }

    @Test func batchCapEvictsOldestOnceFull() {
        let conn = makeConnection()
        let cap = IRCConnection._testMaxOpenBatches
        // Open `cap` distinct batches. After the cap-th, count = cap.
        for i in 0..<cap {
            _ = conn.handle(parse("BATCH +b\(i) chathistory #c\(i)"))
        }
        #expect(conn._testOpenBatchCount == cap)
        // One more open trips the cap. The dict size stays at `cap`
        // (one old entry evicted before the new one is inserted).
        _ = conn.handle(parse("BATCH +overflow chathistory #overflow"))
        #expect(conn._testOpenBatchCount == cap)
        #expect(conn._testHasOpenBatch("overflow"))
    }

    @Test func batchDictClearsOnDisconnect() {
        let conn = makeConnection()
        _ = conn.handle(parse("BATCH +abc chathistory #room"))
        _ = conn.handle(parse("BATCH +def chathistory #other"))
        #expect(conn._testOpenBatchCount == 2)

        // A real disconnect arrives via `IRCClient.onState`; drive the
        // same handler directly. The connection's bookkeeping must clear
        // so a reconnect doesn't see batch ids left over from the prior
        // session.
        conn.handleState(.disconnected)
        #expect(conn._testOpenBatchCount == 0)
    }

    @Test func batchDictClearsOnFailedState() {
        let conn = makeConnection()
        _ = conn.handle(parse("BATCH +abc chathistory #room"))
        #expect(conn._testOpenBatchCount == 1)

        // The `.failed` state-cleanup mirrors `.disconnected` — both
        // paths nuke the half-open BATCH dict.
        conn.handleState(.failed("simulated"))
        #expect(conn._testOpenBatchCount == 0)
    }
}

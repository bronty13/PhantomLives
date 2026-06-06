import Foundation
import Testing
@testable import PurpleIRC

/// Coverage for `ChatLine.fromLogRecord` — the best-effort inverse of
/// `ChatLine.toLogLine()` used to seed a freshly-opened query buffer with
/// scrollback from disk logs. The two conversation-bearing shapes (privmsg,
/// notice) reconstruct structurally; everything else falls back to a verbatim
/// `.raw` line.
@Suite("Log record parsing")
struct LogRecordParseTests {

    private let stamp = "2026-05-12T14:33:21.123Z"

    /// Build the on-disk record shape (`"<ISO> <toLogLine>"`) for a line.
    private func record(_ line: ChatLine) -> String {
        "\(stamp) \(line.toLogLine())"
    }

    @Test func parsesIncomingPrivmsg() throws {
        let line = ChatLine(timestamp: Date(), kind: .privmsg(nick: "alice", isSelf: false),
                            text: "hello there")
        let parsed = try #require(ChatLine.fromLogRecord(record(line)))
        guard case let .privmsg(nick, isSelf) = parsed.kind else {
            Issue.record("expected privmsg, got \(parsed.kind)"); return
        }
        #expect(nick == "alice")
        #expect(isSelf == false)
        #expect(parsed.text == "hello there")
    }

    @Test func parsesOwnPrivmsg() throws {
        let line = ChatLine(timestamp: Date(), kind: .privmsg(nick: "me", isSelf: true),
                            text: "my reply")
        let parsed = try #require(ChatLine.fromLogRecord(record(line)))
        guard case let .privmsg(nick, isSelf) = parsed.kind else {
            Issue.record("expected privmsg, got \(parsed.kind)"); return
        }
        #expect(nick == "me")
        #expect(isSelf == true)
        #expect(parsed.text == "my reply")
    }

    @Test func parsesNotice() throws {
        let line = ChatLine(timestamp: Date(), kind: .notice(from: "NickServ"),
                            text: "You are now identified.")
        let parsed = try #require(ChatLine.fromLogRecord(record(line)))
        guard case let .notice(from) = parsed.kind else {
            Issue.record("expected notice, got \(parsed.kind)"); return
        }
        #expect(from == "NickServ")
        #expect(parsed.text == "You are now identified.")
    }

    @Test func actionFallsBackToRawVerbatim() throws {
        // Actions are ambiguous against info lines once code-stripped, so they
        // render verbatim rather than risk a misparse.
        let line = ChatLine(timestamp: Date(), kind: .action(nick: "bob"), text: "waves")
        let parsed = try #require(ChatLine.fromLogRecord(record(line)))
        guard case .raw = parsed.kind else {
            Issue.record("expected raw, got \(parsed.kind)"); return
        }
        #expect(parsed.text == "* bob waves")
    }

    @Test func membershipLineFallsBackToRaw() throws {
        let line = ChatLine(timestamp: Date(), kind: .join(nick: "carol"), text: "")
        let parsed = try #require(ChatLine.fromLogRecord(record(line)))
        guard case .raw = parsed.kind else {
            Issue.record("expected raw, got \(parsed.kind)"); return
        }
        #expect(parsed.text == "→ carol joined")
    }

    @Test func preservesTimestamp() throws {
        let line = ChatLine(timestamp: Date(), kind: .privmsg(nick: "alice", isSelf: false),
                            text: "hi")
        let parsed = try #require(ChatLine.fromLogRecord(record(line)))
        let expected = LogStore.parseLogTimestamp("\(stamp) x")
        #expect(parsed.timestamp == expected)
    }

    @Test func emptyAndMalformedReturnNil() {
        #expect(ChatLine.fromLogRecord("") == nil)
        #expect(ChatLine.fromLogRecord("no-space-so-no-timestamp") == nil)
        // Timestamp present but empty body.
        #expect(ChatLine.fromLogRecord("\(stamp) ") == nil)
    }

    @Test func privmsgWithEmptyNickFallsBackToRaw() throws {
        // "<> text" — empty nick shouldn't claim a privmsg.
        let parsed = try #require(ChatLine.fromLogRecord("\(stamp) <> orphaned"))
        guard case .raw = parsed.kind else {
            Issue.record("expected raw, got \(parsed.kind)"); return
        }
    }
}

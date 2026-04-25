import Foundation
import Testing
@testable import PurpleIRC

/// Verify `ChatLine` survives JSON roundtrip in every shape the live code
/// produces. This is the persistence path for `SessionHistoryStore`, so a
/// regression here silently breaks the "previous session" replay on launch.
@Suite("ChatLine Codable")
struct ChatLineCodableTests {

    private func roundtrip(_ line: ChatLine) -> ChatLine? {
        guard let data = try? JSONEncoder().encode(line) else { return nil }
        return try? JSONDecoder().decode(ChatLine.self, from: data)
    }

    // MARK: - Each kind variant

    @Test func roundtripInfoKind() {
        let l = ChatLine(timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                         kind: .info, text: "joined #swift")
        let r = roundtrip(l)
        #expect(r?.text == "joined #swift")
        #expect(r?.timestamp == l.timestamp)
        if case .info = r?.kind { } else { Issue.record("kind mismatch: \(String(describing: r?.kind))") }
    }

    @Test func roundtripErrorKind() {
        let l = ChatLine(timestamp: Date(), kind: .error, text: "boom")
        if case .error = roundtrip(l)?.kind { } else { Issue.record("error kind lost") }
    }

    @Test func roundtripMotdKind() {
        let l = ChatLine(timestamp: Date(), kind: .motd, text: "Welcome to FooNet")
        if case .motd = roundtrip(l)?.kind { } else { Issue.record("motd kind lost") }
    }

    @Test func roundtripPrivmsgPreservesNickAndIsSelf() {
        let l = ChatLine(timestamp: Date(),
                         kind: .privmsg(nick: "alice", isSelf: false),
                         text: "hi")
        let r = roundtrip(l)
        if case .privmsg(let nick, let isSelf) = r?.kind {
            #expect(nick == "alice"); #expect(isSelf == false)
        } else { Issue.record("privmsg kind lost") }

        // self path
        let s = ChatLine(timestamp: Date(),
                         kind: .privmsg(nick: "me", isSelf: true), text: "hey")
        let rs = roundtrip(s)
        if case .privmsg(_, let isSelf) = rs?.kind { #expect(isSelf == true) }
        else { Issue.record("privmsg(isSelf:true) kind lost") }
    }

    @Test func roundtripActionKind() {
        let l = ChatLine(timestamp: Date(),
                         kind: .action(nick: "bob"), text: "waves")
        if case .action(let n) = roundtrip(l)?.kind { #expect(n == "bob") }
        else { Issue.record("action kind lost") }
    }

    @Test func roundtripNoticeKind() {
        let l = ChatLine(timestamp: Date(),
                         kind: .notice(from: "NickServ"), text: "auth failed")
        if case .notice(let f) = roundtrip(l)?.kind { #expect(f == "NickServ") }
        else { Issue.record("notice kind lost") }
    }

    @Test func roundtripJoinPartQuit() {
        let j = ChatLine(timestamp: Date(), kind: .join(nick: "alice"), text: "")
        if case .join(let n) = roundtrip(j)?.kind { #expect(n == "alice") }
        else { Issue.record("join lost") }

        let p = ChatLine(timestamp: Date(),
                         kind: .part(nick: "alice", reason: "bbl"), text: "")
        if case .part(let n, let r) = roundtrip(p)?.kind {
            #expect(n == "alice"); #expect(r == "bbl")
        } else { Issue.record("part lost") }

        let p2 = ChatLine(timestamp: Date(),
                          kind: .part(nick: "bob", reason: nil), text: "")
        if case .part(_, let r) = roundtrip(p2)?.kind { #expect(r == nil) }
        else { Issue.record("part(nil reason) lost") }

        let q = ChatLine(timestamp: Date(),
                         kind: .quit(nick: "carol", reason: "Connection reset"),
                         text: "")
        if case .quit(let n, let r) = roundtrip(q)?.kind {
            #expect(n == "carol"); #expect(r == "Connection reset")
        } else { Issue.record("quit lost") }
    }

    @Test func roundtripNickKind() {
        let l = ChatLine(timestamp: Date(),
                         kind: .nick(old: "alice", new: "alice_"), text: "")
        if case .nick(let o, let n) = roundtrip(l)?.kind {
            #expect(o == "alice"); #expect(n == "alice_")
        } else { Issue.record("nick rename kind lost") }
    }

    @Test func roundtripTopicKind() {
        let l = ChatLine(timestamp: Date(),
                         kind: .topic(setter: "alice"),
                         text: "the new topic")
        if case .topic(let s) = roundtrip(l)?.kind { #expect(s == "alice") }
        else { Issue.record("topic(setter) lost") }

        let l2 = ChatLine(timestamp: Date(),
                          kind: .topic(setter: nil), text: "topic")
        if case .topic(let s) = roundtrip(l2)?.kind { #expect(s == nil) }
        else { Issue.record("topic(nil setter) lost") }
    }

    @Test func roundtripRawKind() {
        let l = ChatLine(timestamp: Date(), kind: .raw, text: ":server PING :x")
        if case .raw = roundtrip(l)?.kind { } else { Issue.record("raw lost") }
    }

    // MARK: - Field handling

    @Test func roundtripPreservesIsMention() {
        let l = ChatLine(timestamp: Date(),
                         kind: .privmsg(nick: "a", isSelf: false),
                         text: "hi", isMention: true)
        #expect(roundtrip(l)?.isMention == true)
    }

    @Test func roundtripPreservesHighlightRuleID() {
        let id = UUID()
        let l = ChatLine(timestamp: Date(),
                         kind: .privmsg(nick: "a", isSelf: false),
                         text: "x", highlightRuleID: id)
        #expect(roundtrip(l)?.highlightRuleID == id)
    }

    @Test func roundtripPreservesNSRangeArray() {
        // The NSRange flat-int packing is the gnarly part. Multiple ranges
        // need to round-trip accurately even when locations / lengths
        // overlap.
        let r1 = NSRange(location: 0, length: 5)
        let r2 = NSRange(location: 8, length: 3)
        let r3 = NSRange(location: 100, length: 0)         // zero-length
        let l = ChatLine(timestamp: Date(),
                         kind: .privmsg(nick: "a", isSelf: false),
                         text: "irrelevant",
                         highlightRanges: [r1, r2, r3])
        let r = roundtrip(l)
        #expect(r?.highlightRanges.count == 3)
        #expect(r?.highlightRanges[0] == r1)
        #expect(r?.highlightRanges[1] == r2)
        #expect(r?.highlightRanges[2] == r3)
    }

    @Test func roundtripPreservesEmptyRanges() {
        let l = ChatLine(timestamp: Date(), kind: .info, text: "nothing")
        let r = roundtrip(l)
        #expect(r?.highlightRanges.isEmpty == true)
    }

    @Test func roundtripPreservesUnicodeText() {
        let l = ChatLine(timestamp: Date(), kind: .info, text: "Привет 🐉 𝓞")
        #expect(roundtrip(l)?.text == "Привет 🐉 𝓞")
    }

    // MARK: - Backward-compat decoding

    @Test func decodesPayloadWithoutOptionalFields() throws {
        // Hand-crafted minimal JSON that omits isMention, highlightRuleID,
        // and highlightRanges. Decoder fallback must fill defaults. The
        // session-history file format is forward-compatible only if this
        // path stays alive across releases.
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "timestamp": 700000000,
          "text": "hello",
          "kind": { "info": {} }
        }
        """
        let data = json.data(using: .utf8)!
        let line = try JSONDecoder().decode(ChatLine.self, from: data)
        #expect(line.id == id)
        #expect(line.text == "hello")
        #expect(line.isMention == false)
        #expect(line.highlightRuleID == nil)
        #expect(line.highlightRanges.isEmpty)
        if case .info = line.kind { } else { Issue.record("info kind lost") }
    }

    @Test func arrayRoundtripIsStable() {
        // SessionHistoryStore writes arrays of ChatLines. Verify a small
        // mixed batch survives an end-to-end JSON encode/decode in order.
        let lines: [ChatLine] = [
            ChatLine(timestamp: Date(timeIntervalSince1970: 1), kind: .info, text: "a"),
            ChatLine(timestamp: Date(timeIntervalSince1970: 2),
                     kind: .privmsg(nick: "alice", isSelf: false), text: "hi"),
            ChatLine(timestamp: Date(timeIntervalSince1970: 3),
                     kind: .nick(old: "alice", new: "alice_"), text: ""),
            ChatLine(timestamp: Date(timeIntervalSince1970: 4),
                     kind: .quit(nick: "alice_", reason: "bye"), text: "")
        ]
        let data = try? JSONEncoder().encode(lines)
        let back = try? JSONDecoder().decode([ChatLine].self, from: data ?? Data())
        #expect(back?.count == lines.count)
        #expect(back?.first?.text == "a")
        #expect(back?.last?.text == "")
        if case .quit(let n, _) = back?.last?.kind { #expect(n == "alice_") }
        else { Issue.record("array tail lost") }
    }
}

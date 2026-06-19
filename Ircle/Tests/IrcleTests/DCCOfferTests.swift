import Foundation
import Testing
import IRCKit
@testable import Ircle

/// Ircle surfaces inbound DCC offers (parsed/validated by IRCKit's DCC engine)
/// into the server console — safe offers as a notice, unsafe peer addresses as
/// a rejection. Transport/accept is Stage 2; this verifies the detection path
/// (no sockets).
@MainActor
@Suite("DCC offer surfacing")
struct DCCOfferTests {

    private func session() -> IrcleSession {
        let cfg = IRCConnectionConfig(host: "irc.example.org", port: 6697, useTLS: true,
                                      nick: "me", user: "me", realName: "Me")
        return IrcleSession(config: cfg, displayName: "Example")
    }

    private func serverLines(_ s: IrcleSession) -> [IrcleLine] { s.serverBuffer.lines }

    @Test func chatOfferIsSurfacedAsNotice() {
        let s = session()
        s.ingest(":bob!u@h PRIVMSG me :\u{01}DCC CHAT chat 16909060 5000\u{01}")
        let hit = serverLines(s).first { $0.kind == .notice && $0.text.contains("DCC chat") }
        #expect(hit != nil)
        #expect(hit?.sender == "bob")
    }

    @Test func sendOfferShowsFilenameAndSize() {
        let s = session()
        s.ingest(":bob!u@h PRIVMSG me :\u{01}DCC SEND photo.jpg 16909060 5000 2048\u{01}")
        let hit = serverLines(s).first { $0.kind == .notice && $0.text.contains("photo.jpg") }
        #expect(hit != nil)
    }

    @Test func unsafeAddressIsRejectedNotOffered() {
        let s = session()
        // 2130706433 == 127.0.0.1 — the SSRF guard must refuse it.
        s.ingest(":bob!u@h PRIVMSG me :\u{01}DCC CHAT chat 2130706433 5000\u{01}")
        #expect(serverLines(s).contains { $0.kind == .error && $0.text.contains("unsafe") })
        #expect(!serverLines(s).contains { $0.kind == .notice && $0.text.contains("DCC chat") })
    }
}

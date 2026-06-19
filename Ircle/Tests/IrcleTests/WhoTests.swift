import Foundation
import Testing
import IRCKit
@testable import Ircle

/// WHO (numeric 352) populates each member's hostname + IRCop flag in the nick
/// list.
@MainActor
@Suite("WHO host/ircop")
struct WhoTests {

    private func session() -> IrcleSession {
        let cfg = IRCConnectionConfig(host: "irc.example.org", port: 6697, useTLS: true,
                                      nick: "me", user: "me", realName: "Me")
        return IrcleSession(config: cfg, displayName: "Example")
    }

    @Test func whoPopulatesHostAndIrcOpFlag() {
        let s = session()
        s.ingest(":me!u@h JOIN #x")
        s.ingest(":server 353 me = #x :bob alice")
        // 352: <me> <chan> <user> <host> <server> <nick> <flags> :<hops> <real>
        s.ingest(":server 352 me #x bu bob.host srv bob H* :0 Bob")     // H* → IRCop
        s.ingest(":server 352 me #x au ali.host srv alice H :0 Alice")  // not an op

        let buf = s.buffers.first { $0.name == "#x" }
        let bob = buf?.users.first { $0.nick == "bob" }
        let alice = buf?.users.first { $0.nick == "alice" }
        #expect(bob?.host == "bu@bob.host")
        #expect(bob?.isIrcOp == true)
        #expect(alice?.host == "au@ali.host")
        #expect(alice?.isIrcOp == false)
    }

    @Test func userDefaultsHaveNoHostUntilWho() {
        let s = session()
        s.ingest(":me!u@h JOIN #x")
        s.ingest(":server 353 me = #x :carol")
        let carol = s.buffers.first { $0.name == "#x" }?.users.first { $0.nick == "carol" }
        #expect(carol?.host == nil)
        #expect(carol?.isIrcOp == false)
    }
}
